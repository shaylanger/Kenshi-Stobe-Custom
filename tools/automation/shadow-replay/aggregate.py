#!/usr/bin/env python
"""aggregate.py - per-class table for the offline coordinator replay (arm H = Haiku High, arm S = Sonnet High).

  python -I aggregate.py [--out C:\\KenshiTestRuns\\shadow\\replay\\aggregate.md]

Reads: points\\*.truth.json, INDEX.csv, mech.json (grade.py mech), grading\\out\\chunk-*.json + grading\\key.json (blind grades),
runs.tsv (replay-run.py collect: tokens and API-equivalent cost from the agent transcripts, prices.json).
Missing inputs are tolerated (a column shows '-').
"""
import argparse, collections, csv, glob, json, os

REPLAY = r'C:\KenshiTestRuns\shadow\replay'
CORE = {'relay', 'lane-alert', 'setup-fail', 'shay-message', 'agent-stopped', 'stop-hook'}
ORDER = ['relay', 'setup-fail', 'lane-alert', 'waker-digest', 'shay-message', 'stop-hook', 'agent-stopped', 'build-compose', 'other']


def jl(p):
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else None


def pct(a, b):
    return '-' if not b else '%d%%' % round(100.0 * a / b)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--out', default=os.path.join(REPLAY, 'aggregate.md')); a = ap.parse_args()
    truth = {}
    for f in glob.glob(os.path.join(REPLAY, 'points', '*.truth.json')):
        t = jl(f); truth[t['id']] = t
    mech = jl(os.path.join(REPLAY, 'mech.json')) or {}
    key = jl(os.path.join(REPLAY, 'grading', 'key.json')) or {}
    grades = {}   # (pid, arm) -> dict
    truth_ok = {}
    for f in sorted(glob.glob(os.path.join(REPLAY, 'grading', 'out', 'chunk-*.json'))):
        try:
            arr = jl(f)
        except ValueError:
            continue
        for g in arr or []:
            pid = g.get('id')
            if pid not in key:
                continue
            for lab in ('A', 'B'):
                if lab in g:
                    grades[(pid, key[pid][lab])] = g[lab]
            truth_ok[pid] = g.get('truth_ok')
    runs = {}
    p = os.path.join(REPLAY, 'runs.tsv')
    if os.path.exists(p):
        for r in csv.DictReader(open(p, encoding='utf-8'), delimiter='\t'):
            runs[(r['point'], r['arm'])] = r

    L = ['# Coordinator replay: aggregate (H = Haiku High, S = Sonnet High)', '']
    pids = sorted(truth)
    L.append('Points: %d; graded points: %d; runs collected: %d' % (len(pids), len({k[0] for k in grades}), len(runs)))
    L.append('')
    L.append('Agreement = (equivalent + acceptable-different) / graded. Harmful = any harm-gate clause (a..i). Core classes fail for an arm on any single harmful.')
    L.append('')
    hdr = '| class | n | arm | graded | equiv | accept | worse | HARMFUL | agree | type-match | first-type | invalid cmds | invented paths | missed | extra | claims unsupported | brief ok | gate |'
    L.append(hdr); L.append('|' + '---|' * hdr.count('|')[:0] if False else '|' + '---|' * 18)
    tot = {arm: collections.Counter() for arm in 'HS'}
    for cls in ORDER:
        ps = [x for x in pids if truth[x]['class'] == cls]
        if not ps:
            continue
        for arm in 'HS':
            c = collections.Counter(); tj = []; ft = []
            for x in ps:
                m = (mech.get(x) or {}).get(arm)
                g = grades.get((x, arm))
                if g:
                    c['graded'] += 1; c[g.get('class', '?')] += 1
                    if g.get('better_than_truth'):
                        c['better'] += 1
                if m and m.get('valid'):
                    c['valid'] += 1
                    c['syntax'] += len(m.get('syntax_errors', []))
                    c['invented'] += len(m.get('invented_paths', []))
                    c['missed'] += 1 if m.get('missed_event') else 0
                    c['extra'] += 1 if m.get('extra_action') else 0
                    c['claims'] += len(m.get('unsupported_claims', []))
                    c['forbidden'] += len(m.get('forbidden_flags', []))
                    for b in m.get('briefs', []):
                        c['briefs'] += 1; c['briefs_ok'] += 1 if b['ok'] else 0
                    tj.append(m.get('type_jaccard', 0)); ft.append(1 if m.get('first_type_match') else 0)
                else:
                    c['invalid_run'] += 1
            agree = c['equivalent'] + c['acceptable-different']
            gate = '-' if not c['graded'] else ('FAIL' if (c['harmful'] and cls in CORE) else ('harm' if c['harmful'] else 'ok'))
            L.append('| %s | %d | %s | %d | %d | %d | %d | %d | %s | %s | %s | %d | %d | %d | %d | %d | %s | %s |' % (
                cls, len(ps), arm, c['graded'], c['equivalent'], c['acceptable-different'], c['worse'], c['harmful'], pct(agree, c['graded']),
                ('%.2f' % (sum(tj) / len(tj))) if tj else '-', pct(sum(ft), len(ft)), c['syntax'], c['invented'], c['missed'], c['extra'], c['claims'],
                pct(c['briefs_ok'], c['briefs']), gate))
            tot[arm].update(c)
    L.append('')
    L.append('## Totals per arm')
    L.append('| arm | graded | agree | harmful | worse | better-than-truth | syntax errs | invented paths | forbidden flags | missed | extra | unsupported claims | brief ok | invalid/missing runs |')
    L.append('|' + '---|' * 14)
    for arm in 'HS':
        c = tot[arm]
        agree = c['equivalent'] + c['acceptable-different']
        L.append('| %s | %d | %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s | %d |' % (arm, c['graded'], pct(agree, c['graded']), c['harmful'], c['worse'], c['better'],
                 c['syntax'], c['invented'], c['forbidden'], c['missed'], c['extra'], c['claims'], pct(c['briefs_ok'], c['briefs']), c['invalid_run']))
    # agreement by truth outcome
    L.append('')
    L.append('## Agreement by truth outcome label (good = real coordinator not corrected later)')
    L.append('| outcome | arm | graded | agree | harmful | worse |'); L.append('|---|---|---|---|---|---|')
    for lab in ('good', 'corrected', 'bad'):
        for arm in 'HS':
            c = collections.Counter()
            for x in pids:
                if truth[x]['outcome']['label'] != lab:
                    continue
                g = grades.get((x, arm))
                if g:
                    c['n'] += 1; c[g.get('class')] += 1
            L.append('| %s | %s | %d | %s | %d | %d |' % (lab, arm, c['n'], pct(c['equivalent'] + c['acceptable-different'], c['n']), c['harmful'], c['worse']))
    # cost
    L.append('')
    L.append('## Tokens and cost (API-equivalent, prices.json; agent transcripts)')
    L.append('| arm | runs | tokens/run | in | out | cache-w | cache-r | USD total | USD/run | wall s/run | USD for 120 points |'); L.append('|' + '---|' * 11)
    for arm in 'HS':
        rs = [r for (pid, ar), r in runs.items() if ar == arm]
        if not rs:
            L.append('| %s | 0 |' % arm + ' - |' * 9); continue
        n = len(rs)
        s = lambda k: sum(float(r[k] or 0) for r in rs)
        walls = [float(r['wall_s']) for r in rs if r['wall_s'] not in ('', None)]
        L.append('| %s | %d | %d | %d | %d | %d | %d | %.3f | %.4f | %.1f | %.2f |' % (arm, n, s('tokens') / n, s('in'), s('out'), s('cache_w'), s('cache_r'), s('usd'), s('usd') / n,
                 sum(walls) / len(walls) if walls else 0, s('usd') / n * 120))
    # recommendation helper
    L.append('')
    L.append('## Per-class verdict (mechanical: core class with any harmful or <80% agreement = Sonnet only; otherwise Haiku ok if within 10 points of Sonnet)')
    L.append('| class | H agree | S agree | H harmful | S harmful | verdict |'); L.append('|---|---|---|---|---|---|')
    for cls in ORDER:
        ps = [x for x in pids if truth[x]['class'] == cls]
        st = {}
        for arm in 'HS':
            c = collections.Counter()
            for x in ps:
                g = grades.get((x, arm))
                if g:
                    c['n'] += 1; c[g.get('class')] += 1
            st[arm] = c
        if not st['H']['n']:
            L.append('| %s | - | - | - | - | not graded |' % cls); continue
        ha = (st['H']['equivalent'] + st['H']['acceptable-different']) / float(st['H']['n'])
        sa = (st['S']['equivalent'] + st['S']['acceptable-different']) / float(st['S']['n'] or 1)
        if st['H']['harmful'] and cls in CORE:
            v = 'Sonnet only (harm gate)'
        elif ha < 0.8 or ha < sa - 0.10:
            v = 'Sonnet only (quality)'
        else:
            v = 'Haiku ok' + (' (minor harm: review)' if st['H']['harmful'] else '')
        L.append('| %s | %d%% | %d%% | %d | %d | %s |' % (cls, round(ha * 100), round(sa * 100), st['H']['harmful'], st['S']['harmful'], v))
    L.append('')
    L.append('Truth rated not-ok by graders: %d of %d graded points.' % (sum(1 for v in truth_ok.values() if v is False), len(truth_ok)))
    open(a.out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print('wrote', a.out, '(%d lines)' % len(L))


if __name__ == '__main__':
    main()
