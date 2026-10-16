#!/usr/bin/env python3
"""pilot-ab2-compare.py: result table of the controlled pilot 2 (Haiku High vs Sonnet High, every row run once by each, same lane 5090-i4).
RUN WITH WINDOWS python:  python -I tools/automation/pilot-ab2/pilot-ab2-compare.py [--out FILE] [--root DIR] [--no-cost]
  --selftest   offline check with a synthetic data dir + transcript (no game, no real data)
Per row and arm: checker verdict (last RESULT line of the row script, from captures.jsonl), operator verdict + agree flag + escalations + refusals (arm verdicts.csv),
script wall, operator wall (START..mark), agent tokens and API-price-equivalent USD (whole transcript of the agent whose Agent description holds `ab2-<arm>-<row>`;
cost logic = tools/automation/pilot-rowcmp.py load_msgs/window_cost + prices.json), and the status-count check (status-count-check.py: numeric claims in the agent's status
file vs the ledger). Then per-row cross-arm agreement and totals per arm. Read-only; never prints transcript text.
"""
import sys, os, re, csv, json, glob, importlib.util, subprocess, tempfile, shutil, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
AUTO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ab2_lib as L

ROOT = r'C:\Users\Shay\.claude\projects\C--KenshiModding'


def load_mod(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(AUTO, fn))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def find_transcripts(root, agent):
    out = []
    for meta in glob.glob(os.path.join(root, '*', 'subagents', 'agent-*.meta.json')):
        try:
            d = json.load(open(meta, encoding='utf-8'))
        except Exception:
            continue
        if agent in (d.get('description') or ''):
            p = meta[:-len('.meta.json')] + '.jsonl'
            if os.path.exists(p):
                out.append(p)
    return out


def agent_cost(rc, ca, prices, paths):
    tot = {'n': 0, 'tokens': 0, 'usd': 0.0, 'first': None, 'last': None, 'models': set()}
    for p in paths:
        msgs = rc.load_msgs(p, ca)
        for rec in msgs.values():
            tot['n'] += 1
            tot['tokens'] += rec[2] + rec[3] + rec[4] + rec[5] + rec[6]
            tot['usd'] += rc.price(rec, prices, ca)
            tot['first'] = rec[0] if tot['first'] is None else min(tot['first'], rec[0])
            tot['last'] = rec[0] if tot['last'] is None else max(tot['last'], rec[0])
            tot['models'].add(rec[1])
    return tot


def read_csv(arm):
    p = '%s/%s/verdicts.csv' % (L.ab2_dir(), arm)
    rows = []
    if os.path.isfile(p):
        with open(p, encoding='utf-8', newline='') as f:
            rows = list(csv.DictReader(f))
    return rows


def count_check(agent, arm):
    cmd = [sys.executable, '-I', os.path.join(AUTO, 'status-count-check.py'), agent, '--runs', L.runs_dir(),
           '--pilot-dir', '%s/%s' % (L.ab2_dir(), arm), '--no-asof']
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as e:
        return 'ERR', str(e)[:120]
    txt = ((r.stdout or '') + (r.stderr or '')).strip().replace('\n', ' | ')
    return ('MISMATCH' if r.returncode == 1 else ('ok' if r.returncode == 0 else 'ERR%d' % r.returncode)), txt[:300]


def hms(sec):
    if sec is None:
        return '-'
    sec = int(sec)
    return '%dm%02ds' % (sec // 60, sec % 60) if sec >= 60 else '%ds' % sec


def build(root, do_cost=True):
    plan = L.load_plan()
    st = L.load_state()
    caps = {}
    for ln in open(L.ab2_dir() + '/captures.jsonl', encoding='utf-8') if os.path.isfile(L.ab2_dir() + '/captures.jsonl') else []:
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if 'seq' in d and 'arm' in d and 'checker' in d:
            caps[(d['row'], d['arm'])] = d
    csvs = {a: read_csv(a) for a in L.ARMS}
    rc = ca = prices = None
    if do_cost:
        rc, ca = load_mod('rc', 'pilot-rowcmp.py'), load_mod('ca', 'cost-audit.py')
        prices = ca.load_prices()
    per = {}
    for row in plan['rows']:
        for arm in L.ARMS:
            agent = 'ab2-%s-%s' % (arm, row)
            cap = caps.get((row, arm))
            ledger = [r for r in csvs[arm] if r['row'] == row]
            final = [r for r in ledger if (r.get('notes') or '').startswith(('ESCALATE', 'REFUSED')) is False]
            op = (final[-1]['operator_verdict'] if final else (ledger[-1]['operator_verdict'] if ledger else '-'))
            agree = (final[-1]['agree'] if final else (ledger[-1]['agree'] if ledger else '-'))
            esc = sum(1 for r in ledger if (r.get('notes') or '').startswith('ESCALATE'))
            ref = sum(1 for r in ledger if (r.get('notes') or '').startswith('REFUSED'))
            opwall = ledger[-1]['wall_s'] if ledger else ''
            cost = None
            if do_cost:
                ps = find_transcripts(root, agent)
                cost = agent_cost(rc, ca, prices, ps) if ps else None
            cc = count_check(agent, arm) if os.path.isfile('%s/agents/%s.status' % (L.runs_dir(), agent)) else ('-', 'no status file')
            per[(row, arm)] = {'cap': cap, 'op': op, 'agree': agree, 'esc': esc, 'ref': ref, 'opwall': opwall, 'cost': cost, 'cc': cc,
                               'voided': any(str(r['seq']) in st.get('voided', {}) for r in plan['runs'] if r['row'] == row and r['arm'] == arm)}
    return plan, per


def fmt_cost(c):
    if not c:
        return '- | -'
    return '{:,} | ${:.3f}'.format(c['tokens'], c['usd'])


def render(plan, per, st):
    out = []
    out.append('# Pilot 2 (ab2): Haiku High vs Sonnet High, same rows, lane 5090-i4\n')
    out.append('seed %s, plan created %s; baseline %s\n' % (plan['seed'], plan['created'], json.dumps(plan.get('baseline'))))
    out.append('| row | order | Haiku checker | Haiku operator (agree) | Sonnet checker | Sonnet operator (agree) | checkers same? | Haiku script wall | Sonnet script wall | Haiku op wall | Sonnet op wall | Haiku tokens | Haiku USD | Sonnet tokens | Sonnet USD | esc H/S | refused H/S | status-count H/S | drift |')
    out.append('|' + '---|' * 19)
    tot = {a: {'wall': 0, 'tok': 0, 'usd': 0.0, 'agree': 0, 'n': 0, 'esc': 0, 'ref': 0, 'mm': 0} for a in L.ARMS}
    same_n = both_n = 0
    for row in plan['rows']:
        h, s = per[(row, 'haiku')], per[(row, 'sonnet')]
        order = next(r['arm'] for r in plan['runs'] if r['row'] == row and r['order'] == 'first')
        hk = (h['cap'] or {}).get('checker') or ('VOID' if h['voided'] else '-')
        sk = (s['cap'] or {}).get('checker') or ('VOID' if s['voided'] else '-')
        same = '-' if '-' in (hk, sk) or 'VOID' in (hk, sk) else ('SAME' if hk == sk else 'DIFFERENT')
        if same != '-':
            both_n += 1
            same_n += same == 'SAME'
        drift = ', '.join(sorted(set((h['cap'] or {}).get('drift', []) + (s['cap'] or {}).get('drift', []))))[:80] or '-'
        out.append('| %s | %s first | %s | %s (%s) | %s | %s (%s) | %s | %s | %s | %s | %s | %s | %s | %d/%d | %d/%d | %s/%s | %s |' % (
            row, order, hk, h['op'], h['agree'], sk, s['op'], s['agree'], same,
            hms((h['cap'] or {}).get('wall_s')), hms((s['cap'] or {}).get('wall_s')),
            hms(int(h['opwall'])) if h['opwall'] else '-', hms(int(s['opwall'])) if s['opwall'] else '-',
            fmt_cost(h['cost']), fmt_cost(s['cost']), h['esc'], s['esc'], h['ref'], s['ref'], h['cc'][0], s['cc'][0], drift))
        for arm, x in (('haiku', h), ('sonnet', s)):
            t = tot[arm]
            if x['cap']:
                t['n'] += 1
                t['wall'] += x['cap'].get('wall_s') or 0
                kind = x['cap'].get('checker')
                t['agree'] += 1 if (kind in ('PASS', 'FAIL') and x['op'] == kind) or (kind not in ('PASS', 'FAIL') and x['op'] in ('ESCALATE', 'SETUP-FAIL', 'GATED')) else 0
            if x['cost']:
                t['tok'] += x['cost']['tokens']; t['usd'] += x['cost']['usd']
            t['esc'] += x['esc']; t['ref'] += x['ref']; t['mm'] += x['cc'][0] == 'MISMATCH'
    out.append('')
    out.append('## Totals')
    out.append('| arm | runs | operator matches checker | script wall | agent tokens | API-price USD | escalation lines | refused marks | status-count MISMATCH |')
    out.append('|---|---|---|---|---|---|---|---|---|')
    for arm in L.ARMS:
        t = tot[arm]
        out.append('| %s | %d | %d/%d | %s | {:,} | ${:.3f} | %d | %d | %d |'.format(t['tok'], t['usd']) % (arm, t['n'], t['agree'], t['n'], hms(t['wall']), t['esc'], t['ref'], t['mm']))
    out.append('')
    out.append('Checker verdicts identical across arms on %d of %d rows with both runs (a row that is LLM-sampling noisy can differ for either arm; the checker RESULT line is the ground truth, the operator verdict only has to equal it).' % (same_n, both_n))
    out.append('Status-count notes: ' + ('; '.join('%s/%s: %s' % (r, a, per[(r, a)]['cc'][1][:160]) for r in plan['rows'] for a in L.ARMS if per[(r, a)]['cc'][0] == 'MISMATCH') or 'none'))
    out.append('')
    out.append('Costs are API-price-equivalent (prices.json), whole transcript per agent (one agent per run). op wall = START..mark; script wall = the row script only.')
    return '\n'.join(out)


def selftest():
    d = tempfile.mkdtemp(prefix='ab2-compare-selftest-')
    try:
        runs, root = d + '/runs', d + '/proj'
        ab2 = runs + '/pilot/ab2'
        os.makedirs(ab2 + '/haiku'); os.makedirs(ab2 + '/sonnet'); os.makedirs(runs + '/agents')
        os.environ['KAH_RUNS_DIR'] = runs
        os.environ['AB2_DIR'] = ab2
        open(ab2 + '/queue.txt', 'w').write('02-ax :: bash rowtools/x.sh 02-ax\n23-b :: bash rowtools/y.sh 23-b\n')
        plan = L.make_plan(['02-ax', '23-b'], 7)
        plan['baseline'] = {'dll_mods': 'AAAA'}
        plan['queue'] = {'02-ax': 'x', '23-b': 'y'}
        plan['manifest'] = {'02-ax': {}, '23-b': {}}
        L.write_json(ab2 + '/plan.json', plan)
        L.write_json(ab2 + '/state.json', {'cur': 5, 'runs': {}, 'voided': {}})
        hdr = 'row,lane,model,start,end,wall_s,tokens,cost,operator_verdict,checker_result,agree,false_claims_n,notes\n'
        verdict = {('02-ax', 'haiku'): 'PASS', ('02-ax', 'sonnet'): 'PASS', ('23-b', 'haiku'): 'FAIL', ('23-b', 'sonnet'): 'PASS'}
        for arm in L.ARMS:
            with open('%s/%s/verdicts.csv' % (ab2, arm), 'w') as f:
                f.write(hdr)
                for row in ('02-ax', '23-b'):
                    f.write('%s,5090-i4,%s,t,t,120,,,%s,RESULT,1,,ok\n' % (row, arm, verdict[(row, arm)]))
        for r in plan['runs']:
            L.append_jsonl(ab2 + '/captures.jsonl', {'seq': r['seq'], 'arm': r['arm'], 'row': r['row'], 'checker': verdict[(r['row'], r['arm'])], 'wall_s': 100 + r['seq'], 'drift': []})
        # one fake transcript for ab2-haiku-02-ax
        sub = root + '/sess/subagents'
        os.makedirs(sub)
        open(sub + '/agent-aaa.meta.json', 'w').write(json.dumps({'description': '[case:bench] [model:haiku] [effort:high] ab2-haiku-02-ax'}))
        t = datetime.datetime(2026, 1, 1, 12, 0, 0).astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
        open(sub + '/agent-aaa.jsonl', 'w').write(json.dumps({'type': 'assistant', 'timestamp': t, 'requestId': 'm1', 'message': {'id': 'm1', 'model': 'claude-haiku-4-5', 'content': [], 'usage': {
            'input_tokens': 100, 'output_tokens': 50, 'cache_read_input_tokens': 1000, 'cache_creation_input_tokens': 0}}}, separators=(',', ':')) + '\n')
        plan2, per = build(root, True)
        md = render(plan2, per, L.load_state())
        assert per[('02-ax', 'haiku')]['cost']['tokens'] == 1150, per[('02-ax', 'haiku')]['cost']
        assert per[('02-ax', 'sonnet')]['cost'] is None
        assert '| 23-b |' in md and 'DIFFERENT' in md and 'SAME' in md, md
        assert 'Checker verdicts identical across arms on 1 of 2 rows' in md, md
        print('SELFTEST OK (%d lines)' % len(md.splitlines()))
        return 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main(a):
    if '--selftest' in a:
        return selftest()
    root = a[a.index('--root') + 1] if '--root' in a else ROOT
    out = a[a.index('--out') + 1] if '--out' in a else None
    plan, per = build(root, '--no-cost' not in a)
    md = render(plan, per, L.load_state())
    if out:
        open(out, 'w', encoding='utf-8').write(md + '\n')
        print('wrote', out)
    else:
        print(md)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
