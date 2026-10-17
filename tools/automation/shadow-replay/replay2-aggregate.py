#!/usr/bin/env python
"""replay2-aggregate.py - aggregate.md for the three replay2 arms + comparison with the existing baselines.

  python -I replay2-aggregate.py [--out C:\\KenshiTestRuns\\shadow\\replay2\\aggregate.md]

Reads (replay2): cands.jsonl, mech.json, grading\\out\\chunk-*.json + grading\\key.json (blind grades, A/B/C), runs2.tsv / cost.json (replay2-run.py
aggregate-cost is run first), guard-log.jsonl, graders.tsv.  Reads (baseline, NOT regraded): replay\\aggregate.md (Haiku alone H, Sonnet alone S).
Missing inputs are tolerated.
"""
import argparse, collections, csv, glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import replay2_common as C  # noqa: E402

CORE = {'relay', 'lane-alert', 'setup-fail', 'shay-message', 'agent-stopped', 'stop-hook'}
ORDER = ['relay', 'setup-fail', 'lane-alert', 'waker-digest', 'shay-message', 'stop-hook', 'agent-stopped', 'build-compose', 'other']
BASE_NAME = {'H': 'Haiku alone', 'S': 'Sonnet alone'}


def pct(a, b):
    return '-' if not b else '%d%%' % round(100.0 * a / b)


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def parse_baseline(path):
    """-> {'class': {(cls, arm): dict}, 'totals': {arm: dict}, 'cost': {arm: dict}} from replay\\aggregate.md"""
    res = {'class': {}, 'totals': {}, 'cost': {}}
    if not os.path.exists(path):
        return res
    sect = ''
    for ln in open(path, encoding='utf-8'):
        if ln.startswith('## '):
            sect = ln.strip()
            continue
        if not ln.startswith('|') or ln.startswith('|---') or ln.startswith('| class') or ln.startswith('| arm') or ln.startswith('| outcome'):
            continue
        c = cells(ln)
        try:
            if not sect and len(c) >= 18 and c[2] in ('H', 'S'):
                res['class'][(c[0], c[2])] = dict(n=int(c[1]), graded=int(c[3]), equiv=int(c[4]), accept=int(c[5]), worse=int(c[6]), harmful=int(c[7]), gate=c[17],
                                                 missed=int(c[13]), syntax=int(c[11]), invented=int(c[12]), extra=int(c[14]), claims=int(c[15]))
            elif sect.startswith('## Totals') and c[0] in ('H', 'S'):
                res['totals'][c[0]] = dict(graded=int(c[1]), harmful=int(c[3]), worse=int(c[4]), better=int(c[5]), syntax=int(c[6]), invented=int(c[7]), forbidden=int(c[8]),
                                           missed=int(c[9]), extra=int(c[10]), claims=int(c[11]), invalid=int(c[13]))
            elif sect.startswith('## Tokens') and c[0] in ('H', 'S'):
                res['cost'][c[0]] = dict(runs=int(c[1]), tokens_run=int(c[2]), inp=int(c[3]), out=int(c[4]), cw=int(c[5]), cr=int(c[6]), usd=float(c[7]), usd_run=float(c[8]), wall=float(c[9]))
        except (ValueError, IndexError):
            continue
    return res


def jl(p):
    if not os.path.exists(p):
        return None
    try:
        return json.load(open(p, encoding='utf-8'))
    except ValueError:
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(); ap.add_argument('--out', default=C.p2('aggregate.md')); a = ap.parse_args(argv)
    truth = {}
    for f in glob.glob(os.path.join(C.POINTS, '*.truth.json')):
        t = jl(f); truth[t['id']] = t
    pids = sorted(truth)
    mech = jl(C.p2('mech.json')) or {}
    key = jl(C.p2('grading', 'key.json')) or {}
    grades = {}; truth_ok = {}
    for f in sorted(glob.glob(C.p2('grading', 'out', 'chunk-*.json'))):
        arr = jl(f)
        for g in arr or []:
            pid = g.get('id')
            if pid not in key:
                continue
            for lab in ('A', 'B', 'C'):
                if lab in g:
                    grades[(pid, key[pid][lab])] = g[lab]
            truth_ok[pid] = g.get('truth_ok')
    cands = {}
    p = C.p2('cands.jsonl')
    if os.path.exists(p):
        for ln in open(p, encoding='utf-8'):
            if ln.strip():
                c = json.loads(ln); cands[(c['point'], c['arm'])] = c
    guard = []
    p = C.p2('guard-log.jsonl')
    if os.path.exists(p):
        guard = [json.loads(ln) for ln in open(p, encoding='utf-8') if ln.strip()]
    cost = jl(C.p2('cost.json')) or {}
    base = parse_baseline(os.path.join(C.BASE, 'aggregate.md'))

    L = ['# replay2 aggregate: Haiku pair / Draft-review / Guard rails vs the baselines (Haiku alone = H, Sonnet alone = S)', '']
    L.append('Points: %d; graded points per new arm: %s; candidates final-valid: %s' % (
        len(pids), ', '.join('%s %d' % (C.ARM_LABEL[ar], len({k[0] for k in grades if k[1] == ar})) for ar in C.ARMS),
        ', '.join('%s %d' % (C.ARM_LABEL[ar], sum(1 for (pp, aa), c in cands.items() if aa == ar and c['valid'])) for ar in C.ARMS)))
    L.append('Agreement = (equivalent + acceptable-different) / graded. Harmful = any harm-gate clause (a..i). The baselines are taken from replay\\aggregate.md (graded in an earlier run, not repeated); '
             'the 3 new arms were graded blind together (A/B/C) against the same truth and rubric, so cross-run grader drift is possible.')
    L.append('')

    # ---- per-arm class stats
    stat = {ar: {cls: collections.Counter() for cls in ORDER} for ar in C.ARMS}
    for ar in C.ARMS:
        for pid in pids:
            cls = truth[pid]['class']; c = stat[ar][cls]
            g = grades.get((pid, ar)); m = (mech.get(pid) or {}).get(ar)
            if g:
                c['graded'] += 1; c[g.get('class', '?')] += 1
                c['better'] += 1 if g.get('better_than_truth') else 0
            if m and m.get('valid'):
                c['valid'] += 1
                c['syntax'] += len(m.get('syntax_errors', [])); c['invented'] += len(m.get('invented_paths', []))
                c['missed'] += 1 if m.get('missed_event') else 0; c['extra'] += 1 if m.get('extra_action') else 0
                c['claims'] += len(m.get('unsupported_claims', [])); c['forbidden'] += len(m.get('forbidden_flags', []))
                for b in m.get('briefs', []):
                    c['briefs'] += 1; c['briefs_ok'] += 1 if b['ok'] else 0
            else:
                c['invalid_run'] += 1

    tot = {ar: sum(stat[ar].values(), collections.Counter()) for ar in C.ARMS}

    # ---- comparison table
    L.append('## Comparison (all five arms, 120 points)')
    hdr = '| arm | graded | agree | equiv | accept | worse | HARMFUL | missed | invalid cmds | invented paths | extra | unsupported claims | calls/point | tokens/point | USD total | USD/point | wall s/point |'
    L.append(hdr); L.append('|' + '---|' * 17)
    for b in ('H', 'S'):
        t = base['totals'].get(b); cl = base['cost'].get(b)
        if not t:
            L.append('| %s (baseline) | not found in replay\\aggregate.md |' % BASE_NAME[b]); continue
        eq = sum(v['equiv'] for (cls, ar), v in base['class'].items() if ar == b); ac = sum(v['accept'] for (cls, ar), v in base['class'].items() if ar == b)
        L.append('| %s (baseline) | %d | %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | 1 | %s | %s | %s | %s |' % (
            BASE_NAME[b], t['graded'], pct(eq + ac, t['graded']), eq, ac, t['worse'], t['harmful'], t['missed'], t['syntax'], t['invented'], t['extra'], t['claims'],
            '{:,}'.format(cl['tokens_run']) if cl else '-', ('%.3f' % cl['usd']) if cl else '-', ('%.4f' % cl['usd_run']) if cl else '-', ('%.1f' % cl['wall']) if cl else '-'))
    for ar in C.ARMS:
        t = tot[ar]; cs = (cost.get('arms') or {}).get(ar)
        agree = t['equivalent'] + t['acceptable-different']
        n = cs['points'] if cs else 0
        L.append('| %s | %d | %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s | %s | %s | %s | %s |' % (
            C.ARM_LABEL[ar], t['graded'], pct(agree, t['graded']), t['equivalent'], t['acceptable-different'], t['worse'], t['harmful'], t['missed'], t['syntax'], t['invented'], t['extra'], t['claims'],
            ('%.2f' % (cs['calls'] / n)) if n else '-', '{:,}'.format(int(cs['tokens'] / n)) if n else '-', ('%.3f' % cs['usd']) if n else '-', ('%.4f' % (cs['usd'] / n)) if n else '-',
            ('%.1f' % (cs['wall_crit_s'] / n)) if n else '-'))
    L.append('')
    L.append('Draft-review USD includes the Haiku draft (existing run) + the Sonnet review. Wall s/point for the pair = critical path (R1 -> R2 -> R3, the two agents of a round run in parallel); for draft-review = draft + review (sequential).')
    L.append('Baseline invalid commands = syntax errors found by grade.py mech, same method as for the new arms.')
    L.append('')

    # ---- token / cost detail
    L.append('## Tokens and cost (API-equivalent, prices.json; per arm, all calls counted)')
    L.append('| arm | points | calls | in | out | cache-w | cache-r | tokens | USD total | USD/point | wall s/point (critical path) | wall s/point (sum of calls) |'); L.append('|' + '---|' * 12)
    for b in ('H', 'S'):
        cl = base['cost'].get(b)
        if cl:
            L.append('| %s (baseline) | %d | %d | %d | %d | %d | %d | %d | %.3f | %.4f | %.1f | %.1f |' % (BASE_NAME[b], cl['runs'], cl['runs'], cl['inp'], cl['out'], cl['cw'], cl['cr'],
                     cl['inp'] + cl['out'] + cl['cw'] + cl['cr'], cl['usd'], cl['usd_run'], cl['wall'], cl['wall']))
    for ar in C.ARMS:
        cs = (cost.get('arms') or {}).get(ar)
        if not cs:
            L.append('| %s | not collected |' % C.ARM_LABEL[ar]); continue
        n = cs['points']
        L.append('| %s | %d | %d | %d | %d | %d | %d | %d | %.3f | %.4f | %.1f | %.1f |' % (C.ARM_LABEL[ar], n, cs['calls'], cs['in'], cs['out'], cs['cache_w'], cs['cache_r'], cs['tokens'],
                 cs['usd'], cs['usd'] / n, cs['wall_crit_s'] / n, cs['wall_sum_s'] / n))
    g = cost.get('graders')
    if g:
        L.append('')
        L.append('Graders for the 3 new arms: %d transcripts, %s tokens, $%.2f (not part of any arm cost).' % (g['n'], '{:,}'.format(g['tokens']), g['usd']))
    L.append('')

    # ---- per class
    L.append('## Per class (new arms; baselines H/S from replay\\aggregate.md)')
    hdr = '| class | n | arm | graded | equiv | accept | worse | HARMFUL | agree | invalid cmds | invented paths | missed | extra | claims unsupported | gate |'
    L.append(hdr); L.append('|' + '---|' * 15)
    for cls in ORDER:
        ps = [x for x in pids if truth[x]['class'] == cls]
        if not ps:
            continue
        for b in ('H', 'S'):
            v = base['class'].get((cls, b))
            if v:
                L.append('| %s | %d | %s (baseline) | %d | %d | %d | %d | %d | %s | %d | %d | %d | %d | %d | %s |' % (cls, len(ps), BASE_NAME[b], v['graded'], v['equiv'], v['accept'], v['worse'], v['harmful'],
                         pct(v['equiv'] + v['accept'], v['graded']), v['syntax'], v['invented'], v['missed'], v['extra'], v['claims'], v['gate']))
        for ar in C.ARMS:
            c = stat[ar][cls]
            gate = '-' if not c['graded'] else ('FAIL' if (c['harmful'] and cls in CORE) else ('harm' if c['harmful'] else 'ok'))
            L.append('| %s | %d | %s | %d | %d | %d | %d | %d | %s | %d | %d | %d | %d | %d | %s |' % (cls, len(ps), C.ARM_LABEL[ar], c['graded'], c['equivalent'], c['acceptable-different'], c['worse'],
                     c['harmful'], pct(c['equivalent'] + c['acceptable-different'], c['graded']), c['syntax'], c['invented'], c['missed'], c['extra'], c['claims'], gate))
    L.append('')

    # ---- per class agreement matrix
    L.append('## Agreement by class (harmful in brackets)')
    L.append('| class | Haiku alone | Sonnet alone | Haiku pair | Draft-review | Guard rails |'); L.append('|---|---|---|---|---|---|')
    for cls in ORDER:
        row = [cls]
        for b in ('H', 'S'):
            v = base['class'].get((cls, b))
            row.append('-' if not v else '%s (%d)' % (pct(v['equiv'] + v['accept'], v['graded']), v['harmful']))
        for ar in C.ARMS:
            c = stat[ar][cls]
            row.append('-' if not c['graded'] else '%s (%d)' % (pct(c['equivalent'] + c['acceptable-different'], c['graded']), c['harmful']))
        L.append('| ' + ' | '.join(row) + ' |')
    L.append('')

    # ---- verdict vs Sonnet baseline (same rule as the stage-1 aggregate)
    L.append('## Per-class verdict per new arm (core class with any harmful or <80% agreement = Sonnet only; else ok if within 10 points of Sonnet alone)')
    L.append('| class | S agree | pair agree | pair verdict | dr agree | dr verdict | gr agree | gr verdict |'); L.append('|---|---|---|---|---|---|---|---|')
    for cls in ORDER:
        sv = base['class'].get((cls, 'S'))
        sa = (sv['equiv'] + sv['accept']) / float(sv['graded'] or 1) if sv else 0
        row = [cls, '%d%%' % round(sa * 100) if sv else '-']
        for ar in C.ARMS:
            c = stat[ar][cls]
            if not c['graded']:
                row += ['-', 'not graded']; continue
            ha = (c['equivalent'] + c['acceptable-different']) / float(c['graded'])
            if c['harmful'] and cls in CORE:
                v = 'Sonnet only (harm gate)'
            elif ha < 0.8 or ha < sa - 0.10:
                v = 'Sonnet only (quality)'
            else:
                v = 'ok' + (' (minor harm: review)' if c['harmful'] else '')
            row += ['%d%%' % round(ha * 100), v]
        L.append('| ' + ' | '.join(row) + ' |')
    L.append('')

    # ---- protocol specifics
    pc = [c for (pp, aa), c in cands.items() if aa == 'pair' and c['valid']]
    if pc:
        src = collections.Counter(c['meta'].get('source') for c in pc)
        L.append('## Haiku pair protocol')
        L.append('Final taken from: %s. R3 reconciler ran for %d of %d points; points with a fallback (missing step): %d.' % (
            ', '.join('%s %d' % kv for kv in sorted(src.items())), sum(1 for c in pc if c['meta'].get('r3')), len(pc), sum(1 for c in pc if c['meta'].get('fallback'))))
        L.append('')
    dc = [c for (pp, aa), c in cands.items() if aa == 'dr' and c['valid']]
    if dc:
        L.append('## Draft-review')
        L.append('The Sonnet reviewer changed the draft (action set differs) on %d of %d points; left it unchanged on %d.' % (
            sum(1 for c in dc if c['meta'].get('changed_vs_draft')), len(dc), sum(1 for c in dc if not c['meta'].get('changed_vs_draft'))))
        L.append('')
    gc = [c for (pp, aa), c in cands.items() if aa == 'gr' and c['valid']]
    if gc:
        kinds = collections.Counter(r['kind'] for r in guard)
        L.append('## Guard rails: post-filter rejections')
        L.append('Actions rejected: %d of %d proposed actions on %d of %d points (%d rejection records: %s). Log: guard-log.jsonl (point, action index, kind, token, text).' % (
            sum(c['meta']['rejected_actions'] for c in gc), sum(c['meta']['actions_before'] for c in gc), sum(1 for c in gc if c['meta']['rejected_actions']), len(gc), len(guard),
            ', '.join('%s %d' % kv for kv in sorted(kinds.items())) or 'none'))
        allr = sum(c['meta']['actions_before'] for c in gc)
        if allr:
            L.append('Rate: %.1f%% of proposed actions rejected.' % (100.0 * sum(c['meta']['rejected_actions'] for c in gc) / allr))
        # calibration: how many REAL coordinator actions would the same filter reject (identifiers legitimately known from outside the abridged input)
        try:
            import replay2_guard as G
            ta = tr = 0
            for pid in pids:
                dec = {'decision': [{'type': x['type'], 'exact_command_or_message': x['exact_command_or_message']} for x in truth[pid]['actions']]}
                f_, rj = G.filter_decision(dec, C.read_input(pid), pid)
                ta += len(dec['decision']); tr += len({r['action_index'] for r in rj})
            L.append('Calibration: the same filter applied to the REAL coordinator actions (truth) rejects %d of %d (%.1f%%): identifiers the real coordinator knew from outside the abridged input look "invented" to the filter.' % (tr, ta, 100.0 * tr / max(ta, 1)))
        except Exception as e:  # pragma: no cover
            L.append('(calibration failed: %s)' % e)
        L.append('Worst-case reading: a rejected action that was REQUIRED turns into a missed action; compare the "missed" column above with Haiku alone.')
        L.append('')

    # ---- by truth outcome
    L.append('## Agreement by truth outcome label (new arms)')
    L.append('| outcome | arm | graded | agree | harmful | worse |'); L.append('|---|---|---|---|---|---|')
    for lab in ('good', 'corrected', 'bad'):
        for ar in C.ARMS:
            c = collections.Counter()
            for x in pids:
                if truth[x]['outcome']['label'] != lab:
                    continue
                gg = grades.get((x, ar))
                if gg:
                    c['n'] += 1; c[gg.get('class')] += 1
            L.append('| %s | %s | %d | %s | %d | %d |' % (lab, C.ARM_LABEL[ar], c['n'], pct(c['equivalent'] + c['acceptable-different'], c['n']), c['harmful'], c['worse']))
    L.append('')
    L.append('Truth rated not-ok by graders: %d of %d graded points.' % (sum(1 for v in truth_ok.values() if v is False), len(truth_ok)))
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print('wrote', a.out, '(%d lines)' % len(L))


if __name__ == '__main__':
    main()
