#!/usr/bin/env python
"""replay2-headless.py - run the remaining replay2 model calls as headless `claude -p` processes instead of Agent-tool subagents.

Why: the session caps concurrent subagents at 20 and executor agents die at their context limit. This tool needs no executor: it launches up to
--parallel (<= 20) `claude -p` processes (Haiku/Sonnet, effort high, tools Read + Write only, scratch cwd, no settings/hooks, no session file)
with the SAME prompt text as the plan entry ("replay-run: <rid>\\nRead <job> and follow it exactly."), the model writes the output file itself,
and this tool validates it with replay2-run's own validator (C.valid_output / replay-run.check_schema).

  python -I replay2-headless.py run --round r2|r3|gr|dr|r1|grade [--batch NN] [--ids P001,P002] [--parallel 16] [--dry-run] [--limit N]
  python -I replay2-headless.py status                 missing / claimed / done per round + headless usage totals
  python -I replay2-headless.py merge-cost             append the headless usage rows to runs2.tsv (so `aggregate-cost` counts them); idempotent

Rules: only ADDS files (jobs\\<rid>.md when a job is missing and plannable, runs\\<rid>.json written by the model, headless\\*). Never touches plan
files, existing job files or runs2.tsv (except merge-cost). A run is skipped when (a) its output is already valid, (b) a headless claim file
headless\\claims\\<rid>.claim is fresh (< 25 min), (c) an Agent-tool subagent transcript carrying the marker 'replay-run: <rid>' was modified in the
last 12 min (= another executor is running it). Side file with tokens/USD/time per attempt: headless-usage.jsonl.
Root = env REPLAY2_ROOT (default C:\\KenshiTestRuns\\shadow\\replay2). Windows python: python -I replay2-headless.py ...
"""
import argparse, concurrent.futures as cf, glob, json, os, re, shutil, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import replay2_common as C  # noqa: E402

CLAIM_STALE_S = 25 * 60
SUBAGENT_FRESH_S = 12 * 60
TIMEOUT_S = 600
MAX_TURNS = 8
HEAD = lambda *a: C.p2('headless', *a)
USAGE = lambda: C.p2('headless-usage.jsonl')
ALLROUNDS = ['r1', 'r2', 'r3', 'dr', 'gr']
_lock = threading.Lock()
_rr2 = {}


def run_mod():
    if 'm' not in _rr2:
        _rr2['m'] = C.load_path('replay2_run_mod', os.path.join(HERE, 'replay2-run.py'))
    return _rr2['m']


# ------------------------------------------------------------------ which runs are missing
def job_extra(rd, pid, suf, extra):
    if rd == 'r2':
        own, other = (extra[1], extra[2]) if suf == 'pa2' else (extra[2], extra[1])
        return {'own': C.strip_extra(own), 'other': C.strip_extra(other)}
    return extra


def candidates(rd, ids, batch):
    """-> (list of (rid, pid, suf), waiting-count). Same logic as `replay2-run.py status`; creates a missing job file only (never overwrites)."""
    rm = run_mod(); out = []; wait = 0
    only = None
    if batch:
        pf = C.p2('plan', 'batch-%s-%02d.json' % (rd, int(batch)))
        only = {e['rid'] for e in (C.load_json(pf) or [])}
    for pid in ids:
        ok, extra = rm.plannable(rd, pid)
        if not ok:
            wait += 1
            continue
        for suf in C.ROUNDS[rd]['suffixes']:
            rid = C.rid_of(pid, suf)
            if only is not None and rid not in only:
                continue
            if C.valid_output(rid) is not None:
                continue
            out.append((rid, pid, suf, extra))
    return out, wait


def ensure_job(rd, rid, pid, suf, extra, dry):
    jp = C.job_path(rid)
    if os.path.exists(jp):
        return 'existing'
    if dry:
        return 'would-create'
    rm = run_mod()
    rm.write_job(rid, pid, suf, job_extra(rd, pid, suf, extra))
    return 'created'


# ------------------------------------------------------------------ claims
def claim_path(rid):
    return HEAD('claims', rid + '.claim')


def try_claim(rid):
    os.makedirs(HEAD('claims'), exist_ok=True)
    p = claim_path(rid)
    for _ in range(2):
        try:
            fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, ('pid=%d t=%d\n' % (os.getpid(), time.time())).encode()); os.close(fd)
            return True
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(p) > CLAIM_STALE_S:
                    os.remove(p); continue
            except OSError:
                pass
            return False
    return False


def release_claim(rid):
    try:
        os.remove(claim_path(rid))
    except OSError:
        pass


def claim_fresh(rid):
    try:
        return time.time() - os.path.getmtime(claim_path(rid)) < CLAIM_STALE_S
    except OSError:
        return False


_sub = {'t': 0, 'set': set()}


def subagent_running():
    """rids that an Agent-tool subagent transcript touched in the last SUBAGENT_FRESH_S (cached 15 s)."""
    now = time.time()
    with _lock:
        if now - _sub['t'] < 15:
            return _sub['set']
        found = set(); rr = C.replay_run()
        for p in glob.glob(os.path.join(C.PROJ_ROOT, '*', 'subagents', 'agent-*.jsonl')):
            try:
                if now - os.path.getmtime(p) > SUBAGENT_FRESH_S:
                    continue
                m = re.search(r'replay-run: (P\d+-[a-z0-9]+)', rr.first_user_text(p)[:3000])
                if m:
                    found.add(m.group(1))
            except Exception:
                continue
        _sub['t'] = now; _sub['set'] = found
        return found


# ------------------------------------------------------------------ one claude -p call
def context_file():
    """Project + user CLAUDE.md and the memory index appended to the system prompt (the Agent-tool subagents see them; `--setting-sources ''` hides them)."""
    p = HEAD('context.md')
    if os.path.exists(p):
        return p
    os.makedirs(HEAD(), exist_ok=True)
    parts = []
    for title, f in (('User global instructions (~/.claude/CLAUDE.md)', r'C:\Users\Shay\.claude\CLAUDE.md'),
                     ('Project instructions (C:\\KenshiModding\\CLAUDE.md)', r'C:\KenshiModding\CLAUDE.md'),
                     ('Auto-memory index', r'C:\Users\Shay\.claude\projects\C--KenshiModding\memory\MEMORY.md')):
        if os.path.exists(f):
            parts.append('# %s\n\n%s\n' % (title, open(f, encoding='utf-8', errors='replace').read()))
    open(p, 'w', encoding='utf-8').write('Codebase and user instructions are shown below.\n\n' + '\n'.join(parts))
    return p


def claude_exe():
    return shutil.which('claude') or r'C:\Users\Shay\.local\bin\claude.exe'


def build_cmd(model, ctx, extra_deny=None):
    cwd_add = [C.R2]
    cmd = [claude_exe(), '-p', '--model', model, '--effort', 'high', '--tools', 'Read,Write', '--allowedTools', 'Read', 'Write',
           '--permission-mode', 'dontAsk', '--setting-sources', '', '--no-session-persistence', '--disable-slash-commands',
           '--strict-mcp-config', '--max-turns', str(MAX_TURNS), '--output-format', 'stream-json', '--verbose']
    for d in cwd_add:
        cmd += ['--add-dir', d]
    if ctx:
        cmd += ['--append-system-prompt-file', ctx]
    if extra_deny:
        cmd += ['--disallowedTools'] + extra_deny
    return cmd


def parse_stream(path):
    """-> dict(model, turns, in, out, cw, cr, tokens, usd, reported_usd, result_ok, error). Per-message usage as in pilot-rowcmp.load_msgs (largest output per message id)."""
    rc = C.rowcmp(); ca = rc.load_ca(); prices = ca.load_prices()
    msgs = {}; res = {}; model = ''
    try:
        for raw in open(path, 'rb'):
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get('type') == 'assistant':
                m = d.get('message') or {}; u = m.get('usage'); mid = m.get('id')
                if not u or not mid:
                    continue
                model = m.get('model') or model
                i = u.get('input_tokens') or 0; o = u.get('output_tokens') or 0; cr = u.get('cache_read_input_tokens') or 0
                cwt = u.get('cache_creation_input_tokens') or 0; cc = u.get('cache_creation') or {}
                cw1 = cc.get('ephemeral_1h_input_tokens') or 0; cw5 = cc.get('ephemeral_5m_input_tokens')
                if cw5 is None:
                    cw5 = cwt - cw1
                rec = (0, model, i, o, cw5, cw1, cr)
                if mid not in msgs or o > msgs[mid][3]:
                    msgs[mid] = rec
            elif d.get('type') == 'result':
                res = d
    except OSError:
        pass
    # streamed assistant events carry only the FIRST chunk's output_tokens, so the totals come from the final `result` event (true totals);
    # the per-message sums are the fallback. USD = pilot-rowcmp.price on the totals (Haiku >100k band decided by the largest single prompt).
    t = {'in': 0, 'out': 0, 'cw': 0, 'cr': 0, 'usd': 0.0}
    for rec in msgs.values():
        t['in'] += rec[2]; t['out'] += rec[3]; t['cw'] += rec[4] + rec[5]; t['cr'] += rec[6]; t['usd'] += rc.price(rec, prices, ca)
    ru = res.get('usage') or {}
    if ru and msgs:
        cc = ru.get('cache_creation') or {}
        cw1 = cc.get('ephemeral_1h_input_tokens') or 0
        cwt = ru.get('cache_creation_input_tokens') or 0
        cw5 = cc.get('ephemeral_5m_input_tokens')
        if cw5 is None:
            cw5 = cwt - cw1
        big = max(r[2] + r[4] + r[5] + r[6] for r in msgs.values())
        fam = ca.family(model)
        rate = prices['haiku_over_100k' if (fam == 'haiku' and big > ca.BAND) else fam] if fam != 'unknown' else None
        t = {'in': ru.get('input_tokens') or 0, 'out': ru.get('output_tokens') or 0, 'cw': cw5 + cw1, 'cr': ru.get('cache_read_input_tokens') or 0,
             'usd': ca.usd_at(rate, ru.get('input_tokens') or 0, ru.get('output_tokens') or 0, ru.get('cache_read_input_tokens') or 0, cw5, cw1) if rate else 0.0}
    return dict(model=model, turns=len(msgs), **{'in': t['in'], 'out': t['out'], 'cache_w': t['cw'], 'cache_r': t['cr']},
                tokens=t['in'] + t['out'] + t['cw'] + t['cr'], usd=round(t['usd'], 5), reported_usd=res.get('total_cost_usd'),
                result_ok=(res.get('subtype') == 'success' and not res.get('is_error')), error=(res.get('subtype') if res.get('is_error') or res.get('subtype') != 'success' else ''))


def kill_tree(proc):
    try:
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True, timeout=20)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def fix_output(rid):
    """Make the output file exactly what `collect` would leave: valid JSON, schema ok. Returns (ok, why)."""
    if C.valid_output(rid) is not None:
        return True, 'ok'
    op = C.out_path(rid)
    if not os.path.exists(op):
        return False, 'no-output-file'
    rr = C.replay_run()
    dec, st = rr.parse_decision(open(op, encoding='utf-8', errors='replace').read())
    probs = rr.check_schema(dec) if dec is not None else ['unparsed']
    if dec is not None and not probs:
        json.dump(dec, open(op, 'w', encoding='utf-8'), indent=1)       # same rewrite as collect
        return True, 'rewritten-' + st
    return False, 'invalid:' + ';'.join(probs)[:120]


def one_call(rid, rd, prompt, model, ctx, attempt, extra_deny=None, out_check=None):
    cwd = HEAD('cwd'); os.makedirs(cwd, exist_ok=True); os.makedirs(HEAD('logs'), exist_ok=True)
    log = HEAD('logs', '%s.a%d.jsonl' % (rid, attempt)); err = HEAD('logs', '%s.a%d.err' % (rid, attempt))
    t0 = time.time(); rc = None; to = False
    with open(log, 'wb') as fo, open(err, 'wb') as fe:
        proc = subprocess.Popen(build_cmd(model, ctx, extra_deny), cwd=cwd, stdin=subprocess.PIPE, stdout=fo, stderr=fe,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            proc.communicate(prompt.encode('utf-8'), timeout=TIMEOUT_S); rc = proc.returncode
        except subprocess.TimeoutExpired:
            to = True; kill_tree(proc)
            try:
                proc.communicate(timeout=20)
            except Exception:
                pass
    wall = round(time.time() - t0, 1)
    u = parse_stream(log)
    ok, why = (out_check or fix_output)(rid)
    fam = 'haiku' if model == 'haiku' else model
    if ok and fam not in (u['model'] or '').lower():
        why += '+MODEL?' + (u['model'] or '')
    rec = dict(rid=rid, round=rd, attempt=attempt, ok=ok, why=('timeout' if to else why), rc=rc, wall_s=wall, requested_model=model, ts=int(t0), **u)
    with _lock:
        with open(USAGE(), 'a', encoding='utf-8') as f:
            f.write(json.dumps(rec) + '\n')
    if ok:
        for p in (log, err):
            try:
                os.remove(p)
            except OSError:
                pass
    return rec


def do_run(rid, rd, prompt, model, ctx, out_check=None, extra_deny=None):
    for attempt in (1, 2):
        if attempt == 2 and C.valid_output(rid) is None:
            # drop a half-written/invalid file so the retry starts clean
            try:
                op = C.out_path(rid)
                if os.path.exists(op) and not (out_check or (lambda r: (C.valid_output(r) is not None, '')))(rid)[0]:
                    os.remove(op)
            except OSError:
                pass
        rec = one_call(rid, rd, prompt, model, ctx, attempt, extra_deny, out_check)
        if rec['ok']:
            return rec
    return rec


# ------------------------------------------------------------------ commands
def worklist(a):
    ids = a.ids.split(',') if a.ids else C.point_ids()
    rounds = ALLROUNDS if a.round == 'all' else [a.round]
    work = []; info = {}
    sub = subagent_running()
    for rd in rounds:
        cand, wait = candidates(rd, ids, a.batch)
        n_claim = n_sub = 0
        for rid, pid, suf, extra in cand:
            if claim_fresh(rid):
                n_claim += 1; continue
            if rid in sub:
                n_sub += 1; continue
            work.append((rd, rid, pid, suf, extra))
        info[rd] = dict(missing=len(cand), claimed_headless=n_claim, running_as_subagent=n_sub, waiting_inputs=wait)
    return work, info


def grade_work(a):
    ch = sorted(glob.glob(C.p2('grading', 'chunk-*.md')))
    work = []
    for p in ch:
        name = os.path.basename(p)[:-3]
        out = C.p2('grading', 'out', name + '.json')
        if os.path.exists(out) and C.load_json(out) is not None:
            continue
        if claim_fresh('grade-' + name):
            continue
        work.append(name)
    return work


def grade_check(name):
    def f(_rid):
        d = C.load_json(C.p2('grading', 'out', name + '.json'))
        return (isinstance(d, list) and len(d) > 0), ('ok' if isinstance(d, list) and d else 'no-valid-grade-json')
    return f


def cmd_run(a):
    par = max(1, min(int(a.parallel), 20))
    if a.round == 'grade':
        work = grade_work(a)
        print('grade chunks to run: %d %s' % (len(work), work[:20]))
        if a.dry_run or not work:
            return
        ctx = context_file() if not a.no_context else None
        key = C.p2('grading', 'key.json')
        deny = ['Read(%s)' % key.replace('\\', '/'), 'Read(%s)' % key]
        jobs = []
        for name in work[:a.limit or None]:
            if try_claim('grade-' + name):
                prompt = 'Read %s and follow it exactly.' % C.p2('grading', name + '.md')
                jobs.append((name, prompt))
        _execute(jobs, par, 'sonnet', ctx, 'grade', grade_check, deny)
        return
    work, info = worklist(a)
    print('round %s: %s' % (a.round, json.dumps(info)))
    if a.limit:
        work = work[:a.limit]
    print('to run now: %d (parallel %d, timeout %d s, one retry)' % (len(work), par, TIMEOUT_S))
    rm = run_mod()
    if a.dry_run:
        for rd, rid, pid, suf, extra in work[:5]:
            model = C.SUFFIX_INFO[suf][1]
            job = ensure_job(rd, rid, pid, suf, extra, True)
            print('  %s round=%s model=%s job=%s\n    prompt=%r\n    cmd=%s' % (rid, rd, model, job, rm.entry(pid, suf)['prompt'], ' '.join(build_cmd(model, HEAD('context.md')))))
        print('  ... %s' % ' '.join(w[1] for w in work[5:30]))
        return
    ctx = None if a.no_context else context_file()
    jobs = []
    for rd, rid, pid, suf, extra in work:
        ensure_job(rd, rid, pid, suf, extra, False)
        jobs.append((rid, rm.entry(pid, suf)['prompt'], C.SUFFIX_INFO[suf][1], rd))
    _execute_runs(jobs, par, ctx)


def _launch_guard(rid):
    """Last-moment checks right before spawning; returns True if we may run it."""
    if C.valid_output(rid) is not None:
        return False
    if rid in subagent_running():
        return False
    return try_claim(rid)


def _execute_runs(jobs, par, ctx):
    done = fail = skipped = 0; t0 = time.time(); results = []

    def work(j):
        rid, prompt, model, rd = j
        if not _launch_guard(rid):
            return rid, None
        try:
            return rid, do_run(rid, rd, prompt, model, ctx)
        finally:
            release_claim(rid)

    with cf.ThreadPoolExecutor(max_workers=par) as ex:
        futs = []
        for j in jobs:
            futs.append(ex.submit(work, j)); time.sleep(0.4)        # stagger launches
        for f in cf.as_completed(futs):
            rid, rec = f.result()
            if rec is None:
                skipped += 1; print('skip   %s (output exists / claimed / running elsewhere)' % rid)
            elif rec['ok']:
                done += 1; print('ok     %s %.0fs %d tok $%.4f %s' % (rid, rec['wall_s'], rec['tokens'], rec['usd'], rec['why']))
            else:
                fail += 1; print('FAIL   %s %.0fs %s' % (rid, rec['wall_s'], rec['why']))
            sys.stdout.flush()
    print('SUMMARY ok=%d fail=%d skipped=%d in %.0fs' % (done, fail, skipped, time.time() - t0))


def _execute(jobs, par, model, ctx, rd, checkf, deny):
    def work(j):
        name, prompt = j
        try:
            return name, do_run(name, rd, prompt, model, ctx, checkf(name), deny)
        finally:
            release_claim('grade-' + name)
    ok = 0
    with cf.ThreadPoolExecutor(max_workers=par) as ex:
        for name, rec in ex.map(work, jobs):
            ok += rec['ok']; print('%s %s %.0fs %d tok $%.3f %s' % ('ok  ' if rec['ok'] else 'FAIL', name, rec['wall_s'], rec['tokens'], rec['usd'], rec['why']))
    print('SUMMARY ok=%d of %d' % (ok, len(jobs)))


def usage_rows():
    rows = []
    try:
        for l in open(USAGE(), encoding='utf-8'):
            try:
                rows.append(json.loads(l))
            except ValueError:
                pass
    except OSError:
        pass
    return rows


def cmd_status(a):
    ids = C.point_ids()
    for rd in ALLROUNDS:
        cand, wait = candidates(rd, ids, None)
        cl = sum(1 for c in cand if claim_fresh(c[0])); sub = subagent_running()
        print('round %-2s: missing %3d (headless-claimed %d, running as subagent %d), points waiting for inputs %d' % (rd, len(cand), cl, sum(1 for c in cand if c[0] in sub), wait))
    rows = usage_rows()
    if rows:
        ok = [r for r in rows if r['ok']]
        print('headless usage: %d attempts, %d ok, tokens %d, usd %.3f, mean wall %.1fs' % (len(rows), len(ok), sum(r['tokens'] for r in rows), sum(r['usd'] for r in rows),
              sum(r['wall_s'] for r in ok) / max(1, len(ok))))


def cmd_merge(a):
    """Append one runs2.tsv row per headless rid (all attempts' tokens/USD summed, wall of the last ok attempt) for rids that have no row yet."""
    rm = run_mod(); tsv = rm.RUNS_TSV(); have = rm.read_tsv(tsv)
    per = {}
    for r in usage_rows():
        if r['round'] == 'grade':
            continue
        per.setdefault(r['rid'], []).append(r)
    new = 0
    for rid, rs in per.items():
        if rid in have and 'headless' not in str(have[rid].get('agent_id', '')):
            continue            # a subagent transcript already counted this rid
        pt = C.parse_rid(rid)
        if not pt or not any(r['ok'] for r in rs):
            continue
        rd, model, arm = C.SUFFIX_INFO[pt[1]]
        last = [r for r in rs if r['ok']][-1]
        have[rid] = dict(rid=rid, point=pt[0], round=rd, arm=arm, agent_id='headless', attempts=len(rs), status='ok', schema_problems='', wall_s=last['wall_s'],
                         tool_calls=last['turns'] - 1, model=last['model'], **{'in': sum(r['in'] for r in rs), 'out': sum(r['out'] for r in rs),
                         'cache_w': sum(r['cache_w'] for r in rs), 'cache_r': sum(r['cache_r'] for r in rs), 'tokens': sum(r['tokens'] for r in rs),
                         'usd': round(sum(r['usd'] for r in rs), 5)})
        new += 1
    rm.write_tsv(tsv, have, rm.COLS)
    print('merge-cost: %d headless rows added/updated in %s (re-run after any `collect`; idempotent)' % (new, tsv))


def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('run'); p.add_argument('--round', required=True, choices=ALLROUNDS + ['all', 'grade']); p.add_argument('--batch'); p.add_argument('--ids')
    p.add_argument('--parallel', type=int, default=16); p.add_argument('--dry-run', action='store_true'); p.add_argument('--limit', type=int)
    p.add_argument('--no-context', action='store_true', help='do not append CLAUDE.md/MEMORY.md to the system prompt'); p.set_defaults(f=cmd_run)
    sp.add_parser('status').set_defaults(f=cmd_status)
    sp.add_parser('merge-cost').set_defaults(f=cmd_merge)
    a = ap.parse_args(); a.f(a)


if __name__ == '__main__':
    main()
