#!/usr/bin/env python
"""replay2-selftest.py - offline selftest of the replay2 tooling in a TEMP root (never touches C:\\KenshiTestRuns\\shadow\\replay2, never reads a real key.json).
  python -I replay2-selftest.py          -> prints PASS/FAIL per check, exit code 1 on any failure
Covers: done-list extraction, guard post-filter (agent/alert/lane/row/path/forbidden + spawn exception), action-signature compare, job builders (pair R1/R2/R3,
draft-review, guard rails), plan batching (<=20), collect-free finalize (pair R2-agree / R3 / fallbacks, dr, gr filter), cost aggregation, blind packets
(3 candidates, key mapping, 8 per chunk), mech reuse, baseline parser, aggregate end-to-end.
"""
import argparse, json, os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix='replay2-selftest-')
os.environ['REPLAY2_ROOT'] = TMP
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import replay2_common as C  # noqa: E402
import replay2_guard as G  # noqa: E402

RUN = C.load_path('replay2_run_mod', os.path.join(HERE, 'replay2-run.py'))
GRD = C.load_path('replay2_grade_mod', os.path.join(HERE, 'replay2-grade.py'))
AGG = C.load_path('replay2_agg_mod', os.path.join(HERE, 'replay2-aggregate.py'))

FAILS = []


def check(name, cond, info=''):
    print('%s  %s %s' % ('PASS' if cond else 'FAIL', name, ('- ' + str(info)) if (info and not cond) else ''))
    if not cond:
        FAILS.append(name)


def act(t, txt, why='x'):
    return {'type': t, 'exact_command_or_message': txt, 'why': why}


def dec(*acts, cls='relay'):
    return {'event_class': cls, 'decision': list(acts), 'checks': []}


SYN = """You are the COORDINATOR of a replay.

## HANDOFF "Right now" text at that time (git abc, first 6000 chars)
lane 5090-i3 is held. Agent imm26-5090-i3op3 RUNNING.

## Preceding conversation (last 6 entries, tool output truncated to 1500 chars)

[INBOUND/USER] go

[coordinator] Spawning the fixer.
-> Agent: [case:patch] fix the thing | Brief: STATUS via agent-status.ps1 imm26-fixer1 RUNNING ...

[tool result] -> Bash: this is output, not a call

[coordinator] -> Bash: powershell -NoProfile -File tools/automation/alert-ack.ps1 lane-idle-5090-i3 "restarted"
-> SendMessage: {"to": "imm26-5090-i3op3", "message": "please continue the row 26-a run"}
-> Bash: cat /c/KenshiTestRuns/agents/imm26-fixer1.status
-> Bash: git add x && git commit -m "fix 26-a"

## EVENT BATCH (arrived at 10:00:00 UTC)

[INBOUND] agent-orphaned-imm26-fixer1 alert, 5090-i4 idle

## Now output the decision JSON only.
"""


def t_done_list():
    d = G.done_list(SYN)
    check('done: spawned has agent name', len(d['spawned']) == 1 and 'imm26-fixer1' in d['spawned'][0], d['spawned'])
    check('done: acked has the alert-ack', len(d['acked']) == 1 and 'lane-idle-5090-i3' in d['acked'][0], d['acked'])
    check('done: message captured', len(d['messages']) == 1 and 'imm26-5090-i3op3' in d['messages'][0], d['messages'])
    check('done: commit captured', len(d['commits']) == 1, d['commits'])
    check('done: read-only cat not listed, tool-result arrow not parsed', not d['commands'], d['commands'])
    b = G.done_block(SYN)
    check('done block mentions all headings and do-not-repeat', 'ALREADY DONE' in b and 'Do NOT repeat' in b and 'MESSAGES ALREADY SENT' in b)
    ok = True
    for pid in C.point_ids():
        try:
            G.done_block(C.read_input(pid))
        except Exception as e:
            ok = False; print('   done_block failed on', pid, e)
    check('done block builds for all 120 real points', ok)


def t_filter():
    inp = SYN
    good = act('ack', 'powershell -File tools/automation/alert-ack.ps1 agent-orphaned-imm26-fixer1 "done"')
    bad_alert = act('ack', 'powershell -File tools/automation/alert-ack.ps1 lane-idle-4080-i9 "x"')
    bad_agent = act('message-agent', 'to=imm26-ghost: please look')
    bad_lane = act('hold-lane', 'echo 5090-i7 >> C:\\KenshiTestRuns\\lanes.held')
    bad_row = act('mark-row', 'mark-row.py 99-z PASS')
    ok_row = act('mark-row', 'mark-row.py 26-a PASS')
    spawn_new = act('spawn', '[case:patch] new agent imm26-brandnew4 agent-status.ps1 imm26-brandnew4 RUNNING; handle 26-a')
    spawn_badrow = act('spawn', '[case:patch] agent imm26-brandnew5 for row 77-q')
    bad_path = act('edit-file', 'C:\\KenshiModding\\tools\\automation\\no-such-script-xyz.ps1 :: edit')
    bad_rel = act('run', 'powershell -File tools/automation/no-such-script-xyz.ps1')
    fbd = act('run', 'cp x.php /var/www/html/StobeServer/x.php')
    d, rej = G.filter_decision(dec(good, bad_alert, bad_agent, bad_lane, bad_row, ok_row, spawn_new, spawn_badrow, bad_path, bad_rel, fbd), inp, 'PT')
    kept = [a['exact_command_or_message'] for a in d['decision']]
    kinds = {(r['kind'], r['token']) for r in rej}
    check('filter keeps valid ack', good['exact_command_or_message'] in kept)
    check('filter keeps valid row', ok_row['exact_command_or_message'] in kept)
    check('filter keeps spawn with a NEW agent name', spawn_new['exact_command_or_message'] in kept)
    check('filter rejects invented alert', ('alert', 'lane-idle-4080-i9') in kinds, kinds)
    check('filter rejects invented agent', ('agent', 'imm26-ghost') in kinds, kinds)
    check('filter rejects invented lane', ('lane', '5090-i7') in kinds, kinds)
    check('filter rejects invented row', ('row', '99-z') in kinds, kinds)
    check('filter rejects invented row inside a spawn', ('row', '77-q') in kinds, kinds)
    check('filter rejects invented script path (abs)', any(k == 'path' and 'no-such-script-xyz' in t for k, t in kinds), kinds)
    check('filter rejects invented script path (relative)', sum(1 for k, t in kinds if k == 'path') >= 2, kinds)
    check('filter rejects live-server write', any(k == 'forbidden-target' for k, t in kinds), kinds)
    check('rejection records carry point + index + text', all(r['point'] == 'PT' and 'action_index' in r and r['text'] for r in rej))
    d2, rej2 = G.filter_decision(dec(bad_agent), inp, 'PT')
    check('all-rejected decision becomes a single wait', len(d2['decision']) == 1 and d2['decision'][0]['type'] == 'wait' and rej2)
    d3, rej3 = G.filter_decision(dec(act('ignore', 'nothing to do')), inp, 'PT')
    check('ignore passes untouched', not rej3 and d3['decision'][0]['type'] == 'ignore')


def t_sig():
    a = dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i3 "x"'), act('wait', 'for x'))
    b = dec(act('ack', 'powershell alert-ack.ps1 lane-idle-5090-i3 "other words"'), act('ignore', 'later'))
    c = dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i4 "x"'))
    check('signature: same actions, different wording = no difference', not C.differ(a, b), (C.action_sig(a['decision']), C.action_sig(b['decision'])))
    check('signature: different target = differs', C.differ(a, c))
    check('signature: different action count/type = differs', C.differ(a, dec(act('spawn', 'x'))))


def t_jobs():
    pid = C.point_ids()[0]
    for suf, extra in [('pa1', None), ('gr', {'done_block': 'DONEBLOCK'}), ('pa2', {'own': dec(act('ignore', 'OWN')), 'other': dec(act('ignore', 'OTHER'))}),
                       ('pc3', {'a': dec(act('ignore', 'AA')), 'b': dec(act('ignore', 'BB'))}), ('dr', {'draft': dec(act('ignore', 'DRAFT'))})]:
        rid = C.rid_of(pid, suf)
        t = C.build_job(rid, pid, suf, extra)
        check('job %s: ends with write instruction to its output file' % suf, C.out_path(rid) in t[-400:])
        check('job %s: contains the original input' % suf, 'EVENT BATCH' in t and 'You are the COORDINATOR' in t)
        check('job %s: instructions come before the final decision marker' % suf, t.find(C.MARK) == -1 or (t.find('DONEBLOCK') < t.find(C.MARK) if suf == 'gr' else True))
    t = C.build_job(C.rid_of(pid, 'pa2'), pid, 'pa2', {'own': dec(act('ignore', 'OWN')), 'other': dec(act('ignore', 'OTHER'))})
    check('job r2 shows own and colleague decision, no model names', 'OWN' in t and 'OTHER' in t and 'haiku' not in t.lower().split('## peer review')[1])
    t = C.build_job(C.rid_of(pid, 'dr'), pid, 'dr', {'draft': dec(act('ignore', 'DRAFT'))})
    check('job dr: draft + review rules', 'DRAFT' in t and 'DO NOT rewrite parts that are already correct' in t and 'REMOVE any action that duplicates' in t and 'ADD any required action' in t)


def t_plan():
    ns = argparse.Namespace(round=None, ids=None, first=None, batch=20, redo=False)
    RUN.cmd_plan(ns)
    names = sorted(os.listdir(C.p2('plan')))
    sizes = {n: len(json.load(open(C.p2('plan', n), encoding='utf-8'))) for n in names}
    check('plan: r1 240 runs, gr 120, dr 120 in batches <=20', sum(v for k, v in sizes.items() if k.startswith('batch-r1')) == 240 and sum(v for k, v in sizes.items() if k.startswith('batch-gr')) == 120
          and sum(v for k, v in sizes.items() if k.startswith('batch-dr')) == 120 and max(sizes.values()) <= 20, sizes)
    check('plan: r2/r3 not planned before r1/r2 exist', not any(n.startswith('batch-r2') or n.startswith('batch-r3') for n in names))
    e = json.load(open(C.p2('plan', 'batch-dr-01.json'), encoding='utf-8'))[0]
    check('plan entry: tags, marker and job path', '[case:bench]' in e['description'] and '[model:sonnet]' in e['description'] and '[effort:high]' in e['description']
          and e['prompt'].startswith('replay-run: ' + e['rid']) and os.path.exists(C.job_path(e['rid'])) and e['run_in_background'] is True, e)
    e = json.load(open(C.p2('plan', 'batch-r1-01.json'), encoding='utf-8'))[0]
    check('plan entry r1: haiku tag, prompt never names a model', '[model:haiku]' in e['description'] and 'haiku' not in e['prompt'].lower() and 'sonnet' not in e['prompt'].lower())


def write_out(rid, d):
    os.makedirs(os.path.dirname(C.out_path(rid)), exist_ok=True)
    json.dump(d, open(C.out_path(rid), 'w', encoding='utf-8'))


def t_pair_and_finalize():
    pids = C.point_ids()[:10]
    inp0 = C.read_input(pids[0])
    # P0: R1 both, R2 agree -> R3 not planned, final = a's R2
    for i, pid in enumerate(pids):
        a1 = dec(act('wait', 'r1a'), cls='other'); b1 = dec(act('ignore', 'r1b'), cls='other')
        write_out(C.rid_of(pid, 'pa1'), a1); write_out(C.rid_of(pid, 'pb1'), b1)
    RUN.cmd_plan(argparse.Namespace(round='r2', ids=','.join(pids), first=None, batch=20, redo=False))
    n2 = sum(len(json.load(open(C.p2('plan', n), encoding='utf-8'))) for n in os.listdir(C.p2('plan')) if n.startswith('batch-r2'))
    check('plan r2: 2 runs per point with both r1 present', n2 == 20, n2)
    jt = open(C.job_path(C.rid_of(pids[0], 'pb2')), encoding='utf-8').read()
    check('r2 job of agent b shows a-r1 as colleague', 'r1a' in jt and jt.index('YOUR first decision') < jt.index('r1b') < jt.index("COLLEAGUE's first decision") < jt.index('r1a'))
    # R2: points 0-4 agree, 5-9 differ
    for i, pid in enumerate(pids):
        if i < 5:
            write_out(C.rid_of(pid, 'pa2'), dict(dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i3 "x"')), peer_note='agree: same'))
            write_out(C.rid_of(pid, 'pb2'), dict(dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i3 "words differ"')), peer_note='agree: ok'))
        else:
            write_out(C.rid_of(pid, 'pa2'), dict(dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i3 "x"')), peer_note='disagree: a'))
            write_out(C.rid_of(pid, 'pb2'), dict(dec(act('spawn', '[case:patch] imm26-x brief')), peer_note='disagree: b'))
    RUN.cmd_plan(argparse.Namespace(round='r3', ids=','.join(pids), first=None, batch=20, redo=False))
    n3 = sum(len(json.load(open(C.p2('plan', n), encoding='utf-8'))) for n in os.listdir(C.p2('plan')) if n.startswith('batch-r3'))
    check('plan r3: only for points whose r2 decisions differ (5)', n3 == 5, n3)
    for pid in pids[5:9]:      # point 9 keeps r3 missing -> fallback
        write_out(C.rid_of(pid, 'pc3'), dec(act('ack', 'alert-ack.ps1 lane-idle-5090-i3 "final r3"')))
    # dr and gr outputs
    for pid in pids:
        write_out(C.rid_of(pid, 'dr'), dict(dec(act('ignore', 'review')), review_note='unchanged'))
    write_out(C.rid_of(pids[0], 'gr'), dec(act('ack', 'alert-ack.ps1 lane-idle-9999-i9 "invented"'), act('ignore', 'x')))
    for pid in pids[1:]:
        write_out(C.rid_of(pid, 'gr'), dec(act('ignore', 'nothing')))
    # fake runs2.tsv (cost)
    rows = {}
    import csv
    for pid in pids:
        for suf in ('pa1', 'pb1', 'pa2', 'pb2', 'pc3', 'dr', 'gr'):
            rid = C.rid_of(pid, suf)
            if C.valid_output(rid) is None:
                continue
            rd, model, arm = C.SUFFIX_INFO[suf]
            rows[rid] = dict(rid=rid, point=pid, round=rd, arm=arm, agent_id='a', attempts=1, status='ok', schema_problems='', wall_s=10, tool_calls=3, model=model,
                             **{'in': 6, 'out': 1000, 'cache_w': 10000, 'cache_r': 100000, 'tokens': 111006, 'usd': 0.01})
    RUN.write_tsv(C.p2('runs2.tsv'), rows, RUN.COLS)
    RUN.cmd_finalize(argparse.Namespace())
    cands = {}
    for ln in open(C.p2('cands.jsonl'), encoding='utf-8'):
        c = json.loads(ln); cands[(c['point'], c['arm'])] = c
    check('finalize: 360 candidate lines (120 points x 3 arms)', len(cands) == 360, len(cands))
    c0 = cands[(pids[0], 'pair')]
    check('pair: R2 agree -> source r2-common, no R3', c0['meta']['source'] == 'r2-common' and c0['meta'].get('r3') is False, c0['meta'])
    c5 = cands[(pids[5], 'pair')]
    check('pair: R2 differ + R3 present -> final is R3', c5['meta']['source'] == 'r3' and 'final r3' in c5['decision']['decision'][0]['exact_command_or_message'], c5['meta'])
    c9 = cands[(pids[9], 'pair')]
    check('pair: R3 missing -> fallback flagged', c9['meta']['source'] == 'r2-a-fallback' and c9['meta']['fallback'], c9['meta'])
    check('pair final has no peer_note', 'peer_note' not in c0['decision'])
    g0 = cands[(pids[0], 'gr')]
    check('gr: invented alert rejected, ignore kept, log written', g0['meta']['rejected_actions'] == 1 and len(g0['decision']['decision']) == 1 and os.path.getsize(C.p2('guard-log.jsonl')) > 0, g0['meta'])
    d0 = cands[(pids[0], 'dr')]
    check('dr: final has no review_note and valid', d0['valid'] and 'review_note' not in d0['decision'])
    check('cands for missing points marked invalid', not cands[(C.point_ids()[50], 'pair')]['valid'])
    RUN.cmd_cost(argparse.Namespace())
    cj = json.load(open(C.p2('cost.json'), encoding='utf-8'))
    check('cost: pair 10 points, calls counted (r1 2 + r2 2 + r3 if any)', cj['arms']['pair']['points'] == 10 and cj['arms']['pair']['calls'] == 10 * 4 + 4, cj['arms']['pair'])
    check('cost: dr includes the baseline draft run', cj['arms']['dr']['calls'] >= 10 and cj['arms']['dr'].get('draft_usd_included', 0) > 0, cj['arms']['dr'])
    check('cost: critical path wall = max per round summed (pair no-R3 point = 20s)', abs(cj['arms']['pair']['wall_crit_s'] - (5 * 20 + 4 * 30 + 1 * 20)) < 0.01, cj['arms']['pair'])
    return pids


def t_packets_and_agg(pids):
    RUN.cmd_finalize(argparse.Namespace())
    GRD.cmd_mech(argparse.Namespace())
    ids, skipped, chunks = GRD.build_packets(8)
    check('packets: points with 3 valid finals only; 8 per chunk', len(ids) == 10 and [len(c) for c in chunks] == [8, 2], (len(ids), [len(c) for c in chunks]))
    key = json.load(open(C.p2('grading', 'key.json'), encoding='utf-8'))
    check('key maps A/B/C to the 3 arms for every point', all(sorted([key[p]['A'], key[p]['B'], key[p]['C']]) == sorted(C.ARMS) for p in ids))
    check('labels are shuffled across points', len({(key[p]['A'], key[p]['B'], key[p]['C']) for p in ids}) > 1)
    t = open(C.p2('grading', 'chunk-01.md'), encoding='utf-8').read()
    check('packet text: 3 candidates, blind, harm gate present', t.count('CANDIDATE A:') == 8 and t.count('CANDIDATE C:') == 8 and 'HARM GATE' in t
          and 'three candidate decisions' in t and '"C": {' in t and 'guard rails' not in t.lower() and 'draft-review' not in t.lower())
    # fake grader output, then aggregate
    for ci, ch in enumerate(chunks, 1):
        arr = []
        for p in ch:
            arr.append({'id': p, 'A': {'class': 'equivalent', 'clause': '', 'better_than_truth': False, 'note': ''}, 'B': {'class': 'worse', 'clause': '', 'better_than_truth': False, 'note': ''},
                        'C': {'class': 'harmful', 'clause': 'c', 'better_than_truth': False, 'note': ''}, 'truth_ok': True})
        os.makedirs(C.p2('grading', 'out'), exist_ok=True)
        json.dump(arr, open(C.p2('grading', 'out', 'chunk-%02d.json' % ci), 'w', encoding='utf-8'))
    out = C.p2('aggregate.md')
    AGG.main(['--out', out])
    md = open(out, encoding='utf-8').read()
    check('aggregate: comparison table with baselines + 3 arms', 'Haiku alone (baseline)' in md and 'Sonnet alone (baseline)' in md and 'Haiku pair' in md and 'Draft-review' in md and 'Guard rails' in md)
    check('aggregate: baseline numbers parsed from replay\\aggregate.md', '| Haiku alone (baseline) | 120 |' in md and '| Sonnet alone (baseline) | 120 |' in md, md[md.find('## Comparison'):md.find('## Comparison') + 700])
    check('aggregate: guard rails section with rejections + calibration', 'Guard rails: post-filter rejections' in md and 'Calibration' in md)
    check('aggregate: per-class matrix and verdicts', 'Agreement by class' in md and 'Per-class verdict per new arm' in md)
    graded_per_arm = {ar: sum(1 for p in ids if key[p]['A'] == ar) for ar in C.ARMS}
    check('aggregate counts grades through the key (A=equivalent arm shows 100% agree)', md.count('100%') >= 1)


def t_baseline_parser():
    b = AGG.parse_baseline(os.path.join(C.BASE, 'aggregate.md'))
    check('baseline parser: 18 class rows, totals and cost for H and S', len(b['class']) == 18 and set(b['totals']) == {'H', 'S'} and set(b['cost']) == {'H', 'S'}, (len(b['class']), b['totals'].keys(), b['cost'].keys()))
    if b['totals']:
        check('baseline parser: Sonnet harmful = 4, Haiku agree rows sum', b['totals']['S']['harmful'] == 4 and b['totals']['H']['worse'] == 69, b['totals'])


def t_collect():
    """Fake a transcript from a real baseline Haiku transcript (marker rewritten to a replay2 rid) in a temp project root; collect must parse it."""
    rr = C.replay_run()
    real = rr.find_transcripts(24 * 60)
    src = (real.get('P001-ra') or [None])[0]
    if not src:
        print('SKIP  collect: baseline transcript P001-ra not found')
        return
    proj = tempfile.mkdtemp(prefix='replay2-proj-')
    d = os.path.join(proj, 'sess', 'subagents')
    os.makedirs(d)
    txt = open(src, encoding='utf-8', errors='ignore').read().replace('replay-run: P001-ra', 'replay-run: P001-gr')
    open(os.path.join(d, 'agent-afake0000000001.jsonl'), 'w', encoding='utf-8').write(txt)
    C.PROJ_ROOT = proj
    try:
        # the baseline agent wrote its answer to the baseline runs dir; collect falls back to the Write content in the transcript
        RUN.cmd_collect(argparse.Namespace(hours=24, redo=False))
        r = RUN.read_tsv(RUN.RUNS_TSV()).get('P001-gr')
        check('collect: fake transcript found by marker, parsed ok, cost > 0, model checked', bool(r) and str(r['status']).startswith('ok') and float(r['usd']) > 0 and int(r['tokens']) > 0, r)
        check('collect: decision file written for the rid', C.valid_output('P001-gr') is not None)
    finally:
        shutil.rmtree(proj, ignore_errors=True)


def main():
    try:
        for f in (t_done_list, t_filter, t_sig, t_jobs, t_plan, t_baseline_parser):
            f()
        t_collect()
        pids = t_pair_and_finalize()
        t_packets_and_agg(pids)
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    print('\nSELFTEST %s (%d failed)' % ('FAILED' if FAILS else 'OK', len(FAILS)))
    if FAILS:
        print('failed:', FAILS)
    sys.exit(1 if FAILS else 0)


if __name__ == '__main__':
    main()
