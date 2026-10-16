#!/usr/bin/env python3
"""pilot-rowcmp.py - per-row time/tokens/cost comparison of a Haiku pilot against the Sonnet agents that ran the same rows.

Read-only on the Claude transcripts (never prints transcript text; only timestamps, row ids, verdict words, numbers).
RUN WITH WINDOWS python:  python -I tools/automation/pilot-rowcmp.py <command> ...

Commands
  index   [--out FILE] [--rows R,R,..]
      Scan every transcript (main + subagents) under C:\\Users\\Shay\\.claude\\projects\\C--KenshiModding and write an index
      (default C:\\KenshiTestRuns\\agents\\out\\imm26-pilotcmp\\index.json): per agent id, name, model, per row the timestamps of
      tool calls naming the row, launch calls (nohup/hxrun/unblock*/go-row ... naming the row), mark calls
      (mark-row.py / status-mark.sh <row> <verdict>), and every checker line "RESULT <row> PASS|FAIL|SETUP-FAIL|GATED"
      seen in a tool result.
  runs    ROW [--index FILE] [--after 'YYYY-MM-DD HH:MM']
      List genuine runs of a row by non-Haiku agents: launch time, RESULT time, verdict, mark time, agent.
      A run is genuine when a launch call naming the row precedes the RESULT line by <= 45 min (latest launch wins).
  cost    AGENT_ID START END [--agent-id ID2 ...]
      Tokens and API-price-equivalent USD (prices.json via cost-audit.py's scan rules: one record per message id,
      per-message model price) of the assistant messages of the transcript(s) between START and END (local time,
      'YYYY-MM-DD HH:MM:SS'), second resolution.
  build   CHOICES.json OUT.md
      CHOICES.json = {"rows":[{row, same, haiku:{agent_ids:[..],start,end,verdict,short,wall_note},
      sonnet:{agent_id,agent,start,end,verdict,short,result_at,whole_agent,whole_rows} or null}, ...]}; builds the table
      with totals (sum) and per-row means.
  selftest
      Synthetic transcript check of the window cost logic.
"""
import argparse, collections, datetime as dt, glob, importlib.util, json, os, re, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'
OUTDIR = r'C:\KenshiTestRuns\agents\out\imm26-pilotcmp'
DEF_ROWS = '02-cx 02-ax 16-bx 15-bx 08-d 23-b 22-b 20-a 20-d 23-e 24-c 05-cx 12-d'.split()
# A row launch = a script invocation whose first argument is the row id (hxrun.sh 02-cx ..., sfrrun.sh 23-b ..., go-row.sh 05-cx ...),
# except the marking / card helpers. Tool calls other than Bash/PowerShell (Write, Edit, Read) never count.
LAUNCH_ARG_RE = (r'(?<![\w.-])(?!mark-row|status-mark|row-card|agent-status|pilot-mark|attempts)[\w.-]+\.(?:sh|py|ps1)[\s"' + "'" + r']+(?:-\S+\s+)*%s(?![0-9a-z])')
SKIP_START = re.compile(r'^\s*(?:for\s+i\s+in|grep|tail|cat|ls|sed|git|head|echo|powershell\s+\S+\s+\S*agent-status)')
MARK_RE = re.compile(r'(?:mark-row\.py|status-mark\.sh)\s+(?:\S+\s+)??[\'"]?(\d+-[a-z0-9]+)[\'"]?\s+[\'"]?(PASS|FAIL|SETUP-FAIL|GATED)\b')


def load_ca():
    spec = importlib.util.spec_from_file_location('ca', os.path.join(HERE, 'cost-audit.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def fmt(t):
    return dt.datetime.fromtimestamp(t).strftime('%Y-%m-%d %H:%M:%S')


def parse_t(s):
    s = s.strip().replace('T', ' ')
    for f in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M'):
        try:
            return dt.datetime.strptime(s, f).timestamp()
        except ValueError:
            pass
    raise SystemExit('bad time %r' % s)


def hms(sec):
    sec = int(round(sec))
    if sec < 60:
        return '%ds' % sec
    if sec < 3600:
        return '%dm%02ds' % (sec // 60, sec % 60)
    return '%dh%02dm%02ds' % (sec // 3600, sec % 3600 // 60, sec % 60)


def files_all(root):
    return glob.glob(os.path.join(root, '*.jsonl')) + glob.glob(os.path.join(root, '*', 'subagents', 'agent-*.jsonl'))


def row_alt(rows):
    return re.compile(r'(?<![0-9a-z])(%s)(?![0-9a-z])' % '|'.join(re.escape(r) for r in rows))


def scan_index_file(p, rows, ca):
    rx = row_alt(rows)
    res_rx = re.compile(r'(?m)^\s*RESULT\s+(%s)\s+(PASS|FAIL|SETUP-FAIL|GATED)\b' % '|'.join(re.escape(r) for r in rows))
    bro = re.compile('|'.join(re.escape(r) for r in rows).encode())
    kind = 'sub' if os.sep + 'subagents' + os.sep in p else 'main'
    ent = {'path': p, 'id': os.path.basename(p)[6:-6] if kind == 'sub' else 'main:' + os.path.basename(p)[:8],
           'kind': kind, 'name': '', 'desc': '', 'model': '', 'uses': {}, 'launch': {}, 'mark': {}, 'res': []}
    mp = p[:-6] + '.meta.json'
    if os.path.exists(mp):
        try:
            ent['desc'] = (json.load(open(mp, encoding='utf-8')).get('description') or '')[:120]
        except Exception:
            pass
    fu = ''
    with open(p, 'rb') as f:
        for raw in f:
            if not ent['model'] and b'"type":"assistant"' in raw:
                mm = re.search(rb'"model":"([^"]+)"', raw)
                if mm:
                    ent['model'] = mm.group(1).decode()
            if not bro.search(raw):
                continue
            try:
                d = json.loads(raw)
            except Exception:
                continue
            ty = d.get('type')
            msg = d.get('message') or {}
            c = msg.get('content')
            t = ca.local_day(d.get('timestamp') or '')[2]
            if ty == 'user' and not fu:
                s = c if isinstance(c, str) else ' '.join(x.get('text', '') for x in c if isinstance(x, dict) and x.get('type') == 'text') if isinstance(c, list) else ''
                if s.strip() and not s.lstrip().startswith('<'):
                    fu = s.strip()[:400]
            if ty == 'assistant' and isinstance(c, list):
                for x in c:
                    if isinstance(x, dict) and x.get('type') == 'tool_use':
                        shell = x.get('name') in ('Bash', 'PowerShell')
                        cmd = (x.get('input') or {}).get('command') or json.dumps(x.get('input'))
                        found = set(rx.findall(cmd))
                        for r in found:
                            ent['uses'].setdefault(r, []).append(t)
                            if shell and not SKIP_START.match(cmd) and re.search(LAUNCH_ARG_RE % re.escape(r), cmd):
                                ent['launch'].setdefault(r, []).append(t)
                        for mm in MARK_RE.finditer(cmd):
                            if mm.group(1) in rows:
                                ent['mark'].setdefault(mm.group(1), []).append([t, mm.group(2)])
            if ty == 'user' and isinstance(c, list):
                for x in c:
                    if isinstance(x, dict) and x.get('type') == 'tool_result':
                        ct = x.get('content')
                        if isinstance(ct, list):
                            ct = ' '.join(y.get('text', '') for y in ct if isinstance(y, dict))
                        if isinstance(ct, str) and 'RESULT ' in ct:
                            for mm in res_rx.finditer(ct):
                                ent['res'].append([t, mm.group(1), mm.group(2)])
    ent['name'] = (ca.explicit_name(fu) if fu else '') or ''
    if not (ent['uses'] or ent['res']):
        return None
    return ent


def _job(args):
    p, rows = args
    return scan_index_file(p, rows, load_ca())


def cmd_index(a):
    rows = a.rows.split(',') if a.rows else DEF_ROWS
    from concurrent.futures import ProcessPoolExecutor
    fs = files_all(a.root)
    with ProcessPoolExecutor(max_workers=12) as ex:
        out = [e for e in ex.map(_job, [(p, rows) for p in fs], chunksize=4) if e]
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump({'rows': rows, 'agents': out}, open(a.out, 'w'))
    print('files %d, agents with row activity %d -> %s' % (len(fs), len(out), a.out))


def runs_for(index, row):
    """Genuine runs of row by non-Haiku agents. Returns list of dicts sorted by RESULT time."""
    out = []
    for a in index['agents']:
        if 'haiku' in a['model'] or not a['model']:
            continue
        la = sorted(a['launch'].get(row, []))
        mk = sorted(a['mark'].get(row, []))
        seen = set()
        for t, r, v in a['res']:
            if r != row:
                continue
            prior = [x for x in la if x <= t + 2]
            if not prior or t - prior[-1] > 2700:
                continue
            st = prior[-1]
            key = (st, v)
            if key in seen:
                continue
            seen.add(key)
            mt = next((m for m in mk if t - 2 <= m[0] <= t + 1200), None)
            out.append({'agent_id': a['id'], 'agent': a['name'] or a['desc'] or a['id'], 'model': a['model'], 'launch': st,
                        'result': t, 'verdict': v, 'mark': mt[0] if mt else None, 'mark_verdict': mt[1] if mt else None})
    out.sort(key=lambda r: r['result'])
    return out


def cmd_runs(a):
    index = json.load(open(a.index))
    after = parse_t(a.after) if a.after else 0
    for r in runs_for(index, a.row):
        if r['result'] < after:
            continue
        print('%s launch %s -> RESULT %s %-10s mark %s %-10s %s %s' % (r['agent_id'][:8], fmt(r['launch'])[5:], fmt(r['result'])[11:], r['verdict'],
              fmt(r['mark'])[11:] if r['mark'] else '-', r['mark_verdict'] or '', r['model'][-12:], r['agent'][:50]))


def load_msgs(path, ca):
    """{mid: (epoch, model, i, o, cw5, cw1, cr)} one record per message id (largest output wins), same as cost-audit."""
    msgs = {}
    with open(path, 'rb') as f:
        for raw in f:
            if b'"type":"assistant"' not in raw:
                continue
            d = json.loads(raw)
            m = d.get('message') or {}
            u = m.get('usage')
            mid = m.get('id') or d.get('requestId')
            if not u or not mid:
                continue
            i = u.get('input_tokens') or 0
            o = u.get('output_tokens') or 0
            cr = u.get('cache_read_input_tokens') or 0
            cwt = u.get('cache_creation_input_tokens') or 0
            cc = u.get('cache_creation') or {}
            cw1 = cc.get('ephemeral_1h_input_tokens') or 0
            cw5 = cc.get('ephemeral_5m_input_tokens')
            if cw5 is None:
                cw5 = cwt - cw1
            ep = ca.local_day(d.get('timestamp') or '')[2]
            rec = (ep, m.get('model') or '', i, o, cw5, cw1, cr)
            prev = msgs.get(mid)
            if prev is None or o > prev[3]:
                msgs[mid] = rec
    return msgs


def price(rec, prices, ca):
    ep, model, i, o, cw5, cw1, cr = rec
    fam = ca.family(model)
    prompt = i + cr + cw5 + cw1
    if fam == 'unknown':
        return 0.0
    r = prices['haiku_over_100k' if (fam == 'haiku' and prompt > ca.BAND) else fam]
    return ca.usd_at(r, i, o, cr, cw5, cw1)


def window_cost(paths, t0, t1, ca, prices, cache=None):
    tot = {'n': 0, 'in': 0, 'out': 0, 'cw': 0, 'cr': 0, 'tokens': 0, 'usd': 0.0}
    for p in paths:
        if cache is not None and p in cache:
            msgs = cache[p]
        else:
            msgs = load_msgs(p, ca)
            if cache is not None:
                cache[p] = msgs
        for rec in msgs.values():
            if t0 <= rec[0] <= t1:
                tot['n'] += 1
                tot['in'] += rec[2]
                tot['out'] += rec[3]
                tot['cw'] += rec[4] + rec[5]
                tot['cr'] += rec[6]
                tot['tokens'] += rec[2] + rec[3] + rec[4] + rec[5] + rec[6]
                tot['usd'] += price(rec, prices, ca)
    return tot


def path_of_id(aid, root=ROOT):
    g = glob.glob(os.path.join(root, '*', 'subagents', 'agent-%s.jsonl' % aid))
    if not g:
        g = glob.glob(os.path.join(root, '*', 'subagents', 'agent-%s*.jsonl' % aid))
    if not g:
        raise SystemExit('no transcript for agent id %s' % aid)
    return g[0]


def cmd_cost(a):
    ca = load_ca()
    prices = ca.load_prices()
    ids = [a.agent_id] + (a.agent_id2 or [])
    tot = window_cost([path_of_id(i, a.root) for i in ids], parse_t(a.start), parse_t(a.end), ca, prices)
    print(json.dumps(tot))


def fmt_tok(n):
    return '{:,}'.format(int(n))


def fmt_usd(x):
    return '$%.2f' % x if x >= 0.095 else '$%.3f' % x


def cmd_build(a):
    ca = load_ca()
    prices = ca.load_prices()
    ch = json.load(open(a.choices, encoding='utf-8'))
    cache = {}
    lines = []
    lines.append('| row | Haiku verdict (checker RESULT) | Sonnet verdict (checker RESULT; agent; time) | same / different | '
                 'Haiku wall | Sonnet wall | Haiku tokens | Sonnet tokens | Haiku cost USD | Sonnet cost USD |')
    lines.append('|' + '---|' * 10)
    sums = collections.defaultdict(float)
    cnt = collections.Counter()
    for r in ch['rows']:
        h, s = r['haiku'], r.get('sonnet')
        hp = [path_of_id(i) for i in h['agent_ids']]
        ht0, ht1 = parse_t(h['start']), parse_t(h['end'])
        hc = window_cost(hp, ht0, ht1, ca, prices, cache)
        hw = ht1 - ht0
        sums['hw'] += hw
        sums['ht'] += hc['tokens']
        sums['hc'] += hc['usd']
        cnt['h'] += 1
        hcell_v = h['verdict'] + (' ' + h['short'] if h.get('short') else '')
        if s:
            sp = [path_of_id(s['agent_id'])]
            if s.get('whole_agent'):
                msgs = load_msgs(sp[0], ca)
                eps = [m[0] for m in msgs.values()]
                st0, st1 = min(eps), max(eps)
            else:
                st0, st1 = parse_t(s['start']), parse_t(s['end'])
            sc = window_cost(sp, st0, st1, ca, prices, cache)
            sw = st1 - st0
            scell_v = '%s (%s; %s)' % (s['verdict'] + (' ' + s['short'] if s.get('short') else ''), s['agent'], s['result_at'])
            swc, stc, scc = hms(sw), fmt_tok(sc['tokens']), fmt_usd(sc['usd'])
            if s.get('whole_agent'):
                swc = 'whole agent, %s rows: %s' % (s.get('whole_rows', 'N'), swc)
            else:
                sums['sw'] += sw
                sums['st'] += sc['tokens']
                sums['sc'] += sc['usd']
                cnt['s'] += 1
        else:
            scell_v, swc, stc, scc = 'no Sonnet run', '-', '-', '-'
        lines.append('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            r['row'], hcell_v, scell_v, r.get('same_short', r['same']), hms(hw) + h.get('wall_note', ''), swc, fmt_tok(hc['tokens']), stc, fmt_usd(hc['usd']), scc))
    n_h, n_s = cnt['h'], cnt['s']
    lines.append('| **TOTAL (sum)** | %d rows | %d rows with a per-row Sonnet window | | %s | %s | %s | %s | %s | %s |' % (
        n_h, n_s, hms(sums['hw']), hms(sums['sw']), fmt_tok(sums['ht']), fmt_tok(sums['st']), fmt_usd(sums['hc']), fmt_usd(sums['sc'])))
    lines.append('| **PER-ROW MEAN** | | | | %s | %s | %s | %s | %s | %s |' % (
        hms(sums['hw'] / max(1, n_h)), hms(sums['sw'] / max(1, n_s)), fmt_tok(sums['ht'] / max(1, n_h)), fmt_tok(sums['st'] / max(1, n_s)),
        fmt_usd(sums['hc'] / max(1, n_h)), fmt_usd(sums['sc'] / max(1, n_s))))
    notes = ['', 'Per-row notes (same / different, reasons):', ''] + ['- **%s**: %s' % (r['row'], r['same']) for r in ch['rows']]
    open(a.out, 'w', encoding='utf-8').write('\n'.join(lines) + '\n' + '\n'.join(notes) + '\n')
    print('\n'.join(lines))
    json.dump({'sums': dict(sums), 'cnt': dict(cnt)}, open(a.out + '.sums.json', 'w'))


def cmd_selftest(a):
    ca = load_ca()
    prices = ca.load_prices()
    base = dt.datetime(2026, 1, 1, 12, 0, 0)
    d = tempfile.mkdtemp(prefix='pilotcmp-selftest-')
    p = os.path.join(d, 'agent-x.jsonl')

    def line(sec, mid, model, i, o, cr, cw):
        t = (base + dt.timedelta(seconds=sec)).astimezone(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
        return json.dumps({'type': 'assistant', 'timestamp': t, 'requestId': mid, 'message': {'id': mid, 'model': model, 'content': [],
                'usage': {'input_tokens': i, 'output_tokens': o, 'cache_read_input_tokens': cr, 'cache_creation_input_tokens': cw,
                          'cache_creation': {'ephemeral_5m_input_tokens': cw, 'ephemeral_1h_input_tokens': 0}}}}, separators=(',', ':'))
    lines = [line(0, 'm1', 'claude-sonnet-5-5', 100, 50, 1000, 200),
             line(10, 'm2', 'claude-sonnet-5-5', 10, 5, 2000, 0),
             line(10, 'm2', 'claude-sonnet-5-5', 10, 7, 2000, 0),  # duplicate id, larger output wins
             line(30, 'm3', 'claude-haiku-4-5', 1, 1, 1, 1)]
    open(p, 'w').write('\n'.join(lines) + '\n')
    t0 = base.timestamp()
    w = window_cost([p], t0 + 5, t0 + 15, ca, prices)
    assert w['n'] == 1 and w['out'] == 7 and w['tokens'] == 10 + 7 + 2000, w
    w = window_cost([p], t0, t0 + 10, ca, prices)
    assert w['n'] == 2 and w['out'] == 57, w
    r = prices['sonnet']
    exp = (110 * r['input'] + 57 * r['output'] + 3000 * r['cache_read'] + 200 * r['cache_write_5m']) / 1e6
    assert abs(w['usd'] - exp) < 1e-9, (w['usd'], exp)
    w = window_cost([p], t0 - 100, t0 + 100, ca, prices)
    assert w['n'] == 3
    assert hms(41) == '41s' and hms(138) == '2m18s' and hms(3725) == '1h02m05s'
    L = lambda c, r: bool(re.search(LAUNCH_ARG_RE % re.escape(r), c)) and not SKIP_START.match(c)
    assert L('cd x; nohup bash hxrun.sh 02-cx 4080-i3 --save k', '02-cx')
    assert L('export A=1; bash rowtools/sfrrun.sh 23-b 4080-i3 --no-ini', '23-b')
    assert L('bash rowtools/unblockrun_d2.sh --x 03-b 4080-i3', '03-b')
    assert not L('python tools/automation/mark-row.py 02-cx PASS "x"', '02-cx')
    assert not L('bash tools/automation/status-mark.sh a 01-cx FAIL', '01-cx')
    assert not L('grep -a "^RESULT 02-cx" /c/x/y.out', '02-cx')
    assert not L('cat /c/KenshiTestRuns/imm26-4080-hx/02-cx/foo.txt', '02-cx')
    assert MARK_RE.search('python tools/automation/mark-row.py 02-cx PASS "x"').group(2) == 'PASS'
    assert MARK_RE.search('python tools/automation/mark-row.py 02-cx PASS "x"').group(1) == '02-cx'
    print('SELFTEST PASS')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    s = sp.add_parser('index')
    s.add_argument('--out', default=os.path.join(OUTDIR, 'index.json'))
    s.add_argument('--rows', default='')
    s.add_argument('--root', default=ROOT)
    s.set_defaults(f=cmd_index)
    s = sp.add_parser('runs')
    s.add_argument('row')
    s.add_argument('--index', default=os.path.join(OUTDIR, 'index.json'))
    s.add_argument('--after', default='')
    s.set_defaults(f=cmd_runs)
    s = sp.add_parser('cost')
    s.add_argument('agent_id')
    s.add_argument('start')
    s.add_argument('end')
    s.add_argument('--agent-id', dest='agent_id2', action='append')
    s.add_argument('--root', default=ROOT)
    s.set_defaults(f=cmd_cost)
    s = sp.add_parser('build')
    s.add_argument('choices')
    s.add_argument('out')
    s.set_defaults(f=cmd_build)
    s = sp.add_parser('selftest')
    s.set_defaults(f=cmd_selftest)
    a = ap.parse_args()
    a.f(a)


if __name__ == '__main__':
    main()
