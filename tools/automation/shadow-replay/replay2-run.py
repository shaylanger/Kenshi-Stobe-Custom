#!/usr/bin/env python
"""replay2-run.py - runner for the three replay2 experiments (HAIKU PAIR, DRAFT-REVIEW, GUARD RAILS) on the 120 offline coordinator points.

Same mechanism as replay-run.py: this tool writes batch plans (ready-to-use Agent calls); the EXECUTOR makes the Agent calls (background, tagged
[case:bench] [model:..] [effort:high]); `collect` finds each transcript by the marker 'replay-run: <rid>' and reads tokens/USD from it.

  plan [--round r1,r2,r3,dr,gr] [--batch 20] [--ids P001,..] [--first N]   build job files (jobs\\) + plan\\batch-<round>-NN.json for runs whose output is
                                                                              missing; r2 needs both r1 outputs, r3 needs both r2 outputs AND differing actions
  collect [--hours 24] [--redo]                                             parse outputs, tokens/USD -> runs2.tsv (+ grader cost -> graders.tsv)
  status                                                                    per round: done / missing / not yet plannable
  retry [--batch 20]                                                        delete invalid outputs, re-plan the missing runs (run those batches ONCE)
  finalize                                                                  final decisions per arm -> final\\<arm>\\P###.json, cands.jsonl, guard-log.jsonl
  aggregate-cost                                                            per point / per arm wall, tokens, USD -> cost.json, cost.md, cost-points.csv
Windows python:  python -I replay2-run.py <cmd>
"""
import argparse, csv, glob, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import replay2_common as C  # noqa: E402
import replay2_guard as G  # noqa: E402

RUNS_TSV = lambda: C.p2('runs2.tsv')
COLS = ['rid', 'point', 'round', 'arm', 'agent_id', 'attempts', 'status', 'schema_problems', 'wall_s', 'tool_calls', 'model', 'in', 'out', 'cache_w', 'cache_r', 'tokens', 'usd']


def desc_of(rid, model):
    return '[case:bench] [ticket:REPLAY2-%s] [model:%s] [effort:high] replay2 %s' % (rid, model, rid)


def entry(pid, suf):
    rd, model, arm = C.SUFFIX_INFO[suf]
    rid = C.rid_of(pid, suf)
    return {'rid': rid, 'point': pid, 'round': rd, 'arm': arm, 'description': desc_of(rid, model),
            'prompt': C.PROMPT.format(rid=rid, job=C.job_path(rid)), 'run_in_background': True}


def write_job(rid, pid, suf, extra=None):
    os.makedirs(os.path.dirname(C.job_path(rid)), exist_ok=True)
    os.makedirs(os.path.dirname(C.out_path(rid)), exist_ok=True)
    with open(C.job_path(rid), 'w', encoding='utf-8', newline='\n') as f:
        f.write(C.build_job(rid, pid, suf, extra))


def plannable(rd, pid):
    """-> (ok, extra-for-job-builder or reason)"""
    if rd in ('r1',):
        return True, None
    if rd == 'gr':
        return True, {'done_block': G.done_block(C.read_input(pid))}
    if rd == 'dr':
        draft = C.load_json(os.path.join(C.BASE, 'runs', 'ra', pid + '.json'))
        if draft is None or C.replay_run().check_schema(draft):
            return False, 'no valid Haiku-alone draft runs\\ra\\%s.json' % pid
        return True, {'draft': draft}
    if rd == 'r2':
        a = C.valid_output(C.rid_of(pid, 'pa1')); b = C.valid_output(C.rid_of(pid, 'pb1'))
        if a is None or b is None:
            return False, 'r1 output missing'
        return True, ('r2', a, b)
    if rd == 'r3':
        a = C.valid_output(C.rid_of(pid, 'pa2')); b = C.valid_output(C.rid_of(pid, 'pb2'))
        if a is None or b is None:
            return False, 'r2 output missing'
        if not C.differ(a, b):
            return False, 'r2 decisions agree (no R3)'
        return True, {'a': C.strip_extra(a) | {'peer_note': a.get('peer_note')}, 'b': C.strip_extra(b) | {'peer_note': b.get('peer_note')}}
    return False, 'unknown round'


def plan_round(rd, ids, batch, redo=False):
    calls = []; waiting = {}
    for pid in ids:
        ok, extra = plannable(rd, pid)
        if not ok:
            waiting.setdefault(extra, []).append(pid)
            continue
        for suf in C.ROUNDS[rd]['suffixes']:
            rid = C.rid_of(pid, suf)
            if not redo and C.valid_output(rid) is not None:
                continue
            if rd == 'r2':
                own, other = (extra[1], extra[2]) if suf == 'pa2' else (extra[2], extra[1])
                ex = {'own': C.strip_extra(own), 'other': C.strip_extra(other)}
            else:
                ex = extra
            write_job(rid, pid, suf, ex)
            calls.append(entry(pid, suf))
    pdir = C.p2('plan')
    os.makedirs(pdir, exist_ok=True)
    for old in glob.glob(os.path.join(pdir, 'batch-%s-*.json' % rd)):
        os.remove(old)
    files = []
    for i in range(0, len(calls), batch):
        p = os.path.join(pdir, 'batch-%s-%02d.json' % (rd, i // batch + 1))
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(calls[i:i + batch], f, indent=0)
        files.append(p)
    return calls, files, waiting


def cmd_plan(a):
    ids = a.ids.split(',') if a.ids else C.point_ids()
    if a.first:
        ids = ids[:a.first]
    rounds = a.round.split(',') if a.round else ['r1', 'gr', 'dr', 'r2', 'r3']
    total = 0
    for rd in rounds:
        calls, files, waiting = plan_round(rd, ids, a.batch, a.redo)
        total += len(calls)
        print('round %-2s: %3d runs planned in %d batch file(s)%s' % (rd, len(calls), len(files),
              ''.join('; %d points waiting (%s)' % (len(v), k) for k, v in waiting.items())))
        for p in files:
            print('   ' + p)
    print('total planned runs: %d (Agent description/prompt of each run are in the batch files)' % total)


# ------------------------------------------------------------------ collect
def scan_transcripts(hours):
    rr = C.replay_run()
    now = time.time(); runs = {}; graders = {}
    for p in glob.glob(os.path.join(C.PROJ_ROOT, '*', 'subagents', 'agent-*.jsonl')):
        try:
            if now - os.path.getmtime(p) > hours * 3600:
                continue
        except OSError:
            continue
        ft = rr.first_user_text(p)[:3000]
        m = re.search(r'replay-run: (P\d+-[a-z0-9]+)', ft)
        if m and C.parse_rid(m.group(1)):
            runs.setdefault(m.group(1), []).append(p)
            continue
        g = re.search(r'replay2[\\/]+grading[\\/]+(chunk-\d+)\.md', ft)
        if g:
            graders.setdefault(g.group(1), []).append(p)
    return runs, graders


def read_tsv(path):
    if not os.path.exists(path):
        return {}
    return {r['rid']: r for r in csv.DictReader(open(path, encoding='utf-8'), delimiter='\t')}


def write_tsv(path, rows, cols):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter='\t'); w.writeheader()
        for r in sorted(rows.values(), key=lambda r: r['rid']):
            w.writerow({k: r.get(k, '') for k in cols})


def cmd_collect(a):
    rr = C.replay_run(); rc = C.rowcmp(); ca = rc.load_ca(); prices = ca.load_prices()
    found, graders = scan_transcripts(a.hours)
    have = read_tsv(RUNS_TSV())
    new = 0
    for rid, paths in sorted(found.items()):
        old = have.get(rid)
        if old and not a.redo and str(old['status']).startswith('ok') and int(old.get('attempts') or 1) == len(paths):
            continue
        pid, suf = C.parse_rid(rid)
        rd, model, arm = C.SUFFIX_INFO[suf]
        paths = sorted(paths, key=os.path.getmtime)
        p = paths[-1]
        aid = re.search(r'agent-(\w+)\.jsonl', p).group(1)
        n, t0, t1, mdl, wrote = rr.tool_calls(p)
        op = C.out_path(rid)
        txt = None
        if os.path.exists(op):
            txt = open(op, encoding='utf-8', errors='replace').read()
        elif wrote:
            txt = wrote
        else:
            txt = rr.final_text(p)
        dec, st = rr.parse_decision(txt)
        probs = rr.check_schema(dec) if dec is not None else ['unparsed']
        if dec is not None and not probs:
            os.makedirs(os.path.dirname(op), exist_ok=True)
            json.dump(dec, open(op, 'w', encoding='utf-8'), indent=1)
        status = st if not probs else st + '+schema'
        cost = rc.window_cost(paths, 0, 4e9, ca, prices)      # all attempts of this rid count
        if model not in (mdl or '').lower():
            status += '+MODEL?' + (mdl or '')
        wall = round(rr.iso_epoch(t1) - rr.iso_epoch(t0), 1) if t0 and t1 else ''
        have[rid] = dict(rid=rid, point=pid, round=rd, arm=arm, agent_id=aid, attempts=len(paths), status=status,
                         schema_problems=';'.join(probs)[:200], wall_s=wall, tool_calls=n, model=mdl,
                         **{'in': cost['in'], 'out': cost['out'], 'cache_w': cost['cw'], 'cache_r': cost['cr'], 'tokens': cost['tokens'], 'usd': round(cost['usd'], 5)})
        new += 1
    os.makedirs(C.R2, exist_ok=True)
    write_tsv(RUNS_TSV(), have, COLS)
    # graders
    gh = read_tsv(C.p2('graders.tsv'))
    for name, paths in graders.items():
        cost = rc.window_cost(paths, 0, 4e9, ca, prices)
        gh[name] = dict(rid=name, point='', round='grader', arm='', agent_id='', attempts=len(paths), status='ok', schema_problems='', wall_s='', tool_calls='',
                        model='', **{'in': cost['in'], 'out': cost['out'], 'cache_w': cost['cw'], 'cache_r': cost['cr'], 'tokens': cost['tokens'], 'usd': round(cost['usd'], 5)})
    if gh:
        write_tsv(C.p2('graders.tsv'), gh, COLS)
    print('collected %d new/updated (total %d runs, %d grader transcripts) -> %s' % (new, len(have), len(gh), RUNS_TSV()))
    bad = [r['rid'] for r in have.values() if not str(r['status']).startswith('ok') or 'MODEL?' in str(r['status'])]
    print('bad:', bad[:40])


def cmd_status(a):
    ids = C.point_ids()
    have = read_tsv(RUNS_TSV())
    print('points %d; collected runs %d' % (len(ids), len(have)))
    for rd in ['r1', 'r2', 'r3', 'dr', 'gr']:
        done = miss = wait = 0; mlist = []
        for pid in ids:
            ok, extra = plannable(rd, pid)
            if not ok:
                wait += 1
                continue
            for suf in C.ROUNDS[rd]['suffixes']:
                if C.valid_output(C.rid_of(pid, suf)) is not None:
                    done += 1
                else:
                    miss += 1; mlist.append(C.rid_of(pid, suf))
        extra_txt = ' (r3 only for points whose r2 decisions differ)' if rd == 'r3' else ''
        print('round %-2s: done %3d, missing %3d, points not plannable yet %3d%s %s' % (rd, done, miss, wait, extra_txt, ' '.join(mlist[:8])))


def cmd_retry(a):
    have = read_tsv(RUNS_TSV()); bad = []
    for rid, r in have.items():
        if not str(r['status']).startswith('ok') or r['schema_problems'] or 'MODEL?' in r['status']:
            op = C.out_path(rid)
            if os.path.exists(op) and C.valid_output(rid) is None:
                os.remove(op)
            bad.append(rid)
    print('invalid runs cleared:', bad)
    a.ids = None; a.first = None; a.round = None; a.redo = False
    cmd_plan(a)


# ------------------------------------------------------------------ finalize
def pair_final(pid):
    """Return (decision-or-None, meta)."""
    g = C.valid_output
    r1a, r1b = g(C.rid_of(pid, 'pa1')), g(C.rid_of(pid, 'pb1'))
    r2a, r2b = g(C.rid_of(pid, 'pa2')), g(C.rid_of(pid, 'pb2'))
    r3 = g(C.rid_of(pid, 'pc3'))
    meta = {'rids': [C.rid_of(pid, s) for s in ('pa1', 'pb1', 'pa2', 'pb2', 'pc3') if g(C.rid_of(pid, s)) is not None], 'fallback': ''}
    # an R2 that is missing falls back to that agent's R1
    a_fin = r2a or r1a; b_fin = r2b or r1b
    if r2a is None and r1a is not None:
        meta['fallback'] += 'a:r1;'
    if r2b is None and r1b is not None:
        meta['fallback'] += 'b:r1;'
    if a_fin is None and b_fin is None:
        return None, dict(meta, source='none')
    if a_fin is None or b_fin is None:
        meta['fallback'] += 'single-agent;'
        return C.strip_extra(a_fin or b_fin), dict(meta, source='single')
    if not C.differ(a_fin, b_fin):
        meta['r3'] = False; meta['r2_agree'] = True
        return C.strip_extra(a_fin), dict(meta, source='r2-common')
    meta['r2_agree'] = False
    if r3 is not None:
        meta['r3'] = True
        return C.strip_extra(r3), dict(meta, source='r3')
    meta['fallback'] += 'r3-missing:used-a-r2;'
    return C.strip_extra(a_fin), dict(meta, source='r2-a-fallback')


def cmd_finalize(a):
    cands = []; glog = []
    for pid in C.point_ids():
        itext = C.read_input(pid)
        d, meta = pair_final(pid)
        cands.append({'point': pid, 'arm': 'pair', 'valid': d is not None, 'meta': meta, 'decision': d})
        dr = C.valid_output(C.rid_of(pid, 'dr'))
        cands.append({'point': pid, 'arm': 'dr', 'valid': dr is not None, 'meta': {'rids': [C.rid_of(pid, 'dr')], 'draft_rid': C.rid_of(pid, 'ra'),
                      'review_note': (dr or {}).get('review_note'), 'changed_vs_draft': bool(dr) and C.differ(dr, C.load_json(os.path.join(C.BASE, 'runs', 'ra', pid + '.json')))},
                      'decision': C.strip_extra(dr) if dr else None})
        gr = C.valid_output(C.rid_of(pid, 'gr'))
        rej = []; fd = None
        if gr is not None:
            fd, rej = G.filter_decision(C.strip_extra(gr), itext, pid)
        glog += rej
        cands.append({'point': pid, 'arm': 'gr', 'valid': gr is not None, 'meta': {'rids': [C.rid_of(pid, 'gr')], 'rejected_actions': len({r['action_index'] for r in rej}),
                      'rejection_records': len(rej), 'actions_before': len((gr or {}).get('decision') or []), 'actions_after': len((fd or {}).get('decision') or [])},
                      'decision': fd, 'unfiltered': C.strip_extra(gr) if gr else None})
        for c in cands[-3:]:
            if c['decision'] is not None:
                p = C.final_path(c['arm'], pid)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                json.dump(c['decision'], open(p, 'w', encoding='utf-8'), indent=1)
    with open(C.p2('cands.jsonl'), 'w', encoding='utf-8') as f:
        for c in cands:
            f.write(json.dumps(c, ensure_ascii=False) + '\n')
    with open(C.p2('guard-log.jsonl'), 'w', encoding='utf-8') as f:
        for r in glog:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    nv = {arm: sum(1 for c in cands if c['arm'] == arm and c['valid']) for arm in C.ARMS}
    print('finalize: %d candidates (%s valid) -> %s ; guard rejections: %d records' % (len(cands), nv, C.p2('cands.jsonl'), len(glog)))


# ------------------------------------------------------------------ cost
def cost_rows():
    """per (point, arm) cost dict from runs2.tsv (+ the Haiku-alone draft run for arm dr)."""
    runs = read_tsv(RUNS_TSV())
    base = read_tsv(os.path.join(C.BASE, 'runs.tsv'))
    per = {}
    keys = ('in', 'out', 'cache_w', 'cache_r', 'tokens', 'usd')

    def f(x):
        try:
            return float(x)
        except (TypeError, ValueError):
            return 0.0

    def add(pid, arm, r, step):
        d = per.setdefault((pid, arm), {'calls': 0, 'steps': {}, **{k: 0.0 for k in keys}})
        d['calls'] += 1
        for k in keys:
            d[k] += f(r[k])
        d['steps'].setdefault(step, []).append(f(r['wall_s']))

    for rid, r in runs.items():
        pid, suf = C.parse_rid(rid)
        rd, model, arm = C.SUFFIX_INFO[suf]
        add(pid, arm, r, rd)
    for pid in C.point_ids():
        r = base.get(C.rid_of(pid, 'ra'))
        if r and (pid, 'dr') in per:          # the draft is part of the arm only for points that were reviewed
            add(pid, 'dr', r, 'draft')
    for d in per.values():
        walls = d['steps']
        d['wall_crit_s'] = round(sum(max(v) for v in walls.values()), 1)     # sequential steps; parallel agents inside a step overlap
        d['wall_sum_s'] = round(sum(sum(v) for v in walls.values()), 1)
        d['steps'] = {k: len(v) for k, v in walls.items()}
    return per


def cmd_cost(a):
    per = cost_rows()
    base = read_tsv(os.path.join(C.BASE, 'runs.tsv'))
    gr = read_tsv(C.p2('graders.tsv'))
    res = {'arms': {}, 'graders': {'n': len(gr), 'usd': round(sum(float(r['usd'] or 0) for r in gr.values()), 4),
                                    'tokens': int(sum(float(r['tokens'] or 0) for r in gr.values()))}}
    L = ['# replay2 cost (API-equivalent, prices.json; agent transcripts; same method as replay-run.py collect)', '',
         '| arm | points | calls | calls/point | in | out | cache-w | cache-r | tokens | tokens/point | USD total | USD/point | wall s/point (critical path) | wall s/point (sum of calls) |',
         '|' + '---|' * 14]
    for arm in C.ARMS:
        ps = {pid: d for (pid, ar), d in per.items() if ar == arm}
        n = len(ps)
        if not n:
            L.append('| %s | 0 |' % C.ARM_LABEL[arm] + ' - |' * 12); continue
        s = lambda k: sum(d[k] for d in ps.values())
        t = {k: s(k) for k in ('in', 'out', 'cache_w', 'cache_r', 'tokens', 'usd', 'calls', 'wall_crit_s', 'wall_sum_s')}
        res['arms'][arm] = dict(points=n, **{k: round(v, 4) for k, v in t.items()})
        if arm == 'dr':
            dra = sum(float(base[C.rid_of(p, 'ra')]['usd']) for p in ps if C.rid_of(p, 'ra') in base)
            res['arms'][arm]['draft_usd_included'] = round(dra, 4)
        L.append('| %s | %d | %d | %.2f | %d | %d | %d | %d | %d | %d | %.3f | %.4f | %.1f | %.1f |' % (
            C.ARM_LABEL[arm], n, t['calls'], t['calls'] / n, t['in'], t['out'], t['cache_w'], t['cache_r'], t['tokens'], t['tokens'] / n, t['usd'], t['usd'] / n,
            t['wall_crit_s'] / n, t['wall_sum_s'] / n))
    L += ['', 'Draft-review total = Haiku draft (existing run P###-ra, counted here) + Sonnet review. Pair wall time (critical path) = max of the two parallel agents in each of R1, R2 + R3 when it ran.',
          'Graders for these 3 arms (replay2 chunks): %d transcripts, %d tokens, $%.3f.' % (res['graders']['n'], res['graders']['tokens'], res['graders']['usd'])]
    json.dump(res, open(C.p2('cost.json'), 'w', encoding='utf-8'), indent=1)
    open(C.p2('cost.md'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    with open(C.p2('cost-points.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f); w.writerow(['point', 'arm', 'calls', 'in', 'out', 'cache_w', 'cache_r', 'tokens', 'usd', 'wall_crit_s', 'wall_sum_s'])
        for (pid, arm), d in sorted(per.items()):
            w.writerow([pid, arm, d['calls'], int(d['in']), int(d['out']), int(d['cache_w']), int(d['cache_r']), int(d['tokens']), round(d['usd'], 5), d['wall_crit_s'], d['wall_sum_s']])
    print('\n'.join(L))
    print('wrote cost.json cost.md cost-points.csv in', C.R2)


def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('plan'); p.add_argument('--round'); p.add_argument('--ids'); p.add_argument('--first', type=int); p.add_argument('--batch', type=int, default=20)
    p.add_argument('--redo', action='store_true'); p.set_defaults(f=cmd_plan)
    p = sp.add_parser('collect'); p.add_argument('--hours', type=float, default=24); p.add_argument('--redo', action='store_true'); p.set_defaults(f=cmd_collect)
    p = sp.add_parser('status'); p.set_defaults(f=cmd_status)
    p = sp.add_parser('retry'); p.add_argument('--batch', type=int, default=20); p.set_defaults(f=cmd_retry)
    p = sp.add_parser('finalize'); p.set_defaults(f=cmd_finalize)
    p = sp.add_parser('aggregate-cost'); p.set_defaults(f=cmd_cost)
    a = ap.parse_args(); a.f(a)


if __name__ == '__main__':
    main()
