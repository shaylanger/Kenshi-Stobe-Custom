#!/usr/bin/env python
"""replay2-grade.py - mechanical metrics + BLIND grading packets for the three replay2 arms (pair, dr, gr).

  python -I replay2-grade.py mech                 -> replay2\\mech.json (+ mech.csv); reuses grade.mech_one on final\\<arm>\\P###.json
  python -I replay2-grade.py packets [--chunk 8]  -> replay2\\grading\\chunk-NN.md (3 blind candidates A/B/C per point, order random per point) + grading\\key.json
                                                      (key.json is the secret label->arm mapping: NEVER print or open it; graders write grading\\out\\chunk-NN.json)
Rubric, harm gate and packet layout come from grade.py (imported, same text; only 'two candidates A/B' becomes 'three candidates A/B/C').
The baselines (Haiku alone, Sonnet alone) are NOT re-graded; they are read from replay\\aggregate.md by replay2-aggregate.py.
"""
import argparse, csv, hashlib, json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import replay2_common as C  # noqa: E402

GR = C.grade_mod()
GRADING = lambda: C.p2('grading')


def final_cand(pid, arm):
    return C.load_json(C.final_path(arm, pid))


def head_text():
    """grade.GRADE_HEAD adapted to three candidates (asserts every replacement so a change in grade.py is noticed)."""
    h = GR.GRADE_HEAD
    reps = [('two candidate decisions A and B', 'three candidate decisions A, B and C'),
            ('anonymous\nagents', 'anonymous\nagents'),
            ('whether it later had to be corrected), and', 'whether it later had to be corrected), and'),
            ('"B": {{...same...}}, "truth_ok"', '"B": {{...same...}}, "C": {{...same...}}, "truth_ok"'),
            ('You do not know which model wrote A or B', 'You do not know which model or protocol wrote A, B or C')]
    for old, new in reps:
        assert old in h, 'grade.GRADE_HEAD changed: %r not found' % old
        h = h.replace(old, new)
    return h


def cmd_mech(a):
    ids = C.point_ids(); qb = []; qp = []; rows = []
    GR.cand = lambda pid, arm: final_cand(pid, arm)         # grade.mech_one reads candidates through this hook
    for pid in ids:
        truth = C.load_json(os.path.join(C.POINTS, pid + '.truth.json'))
        inp = GR.norm(C.read_input(pid))
        for arm in C.ARMS:
            rows.append(GR.mech_one(pid, arm, truth, inp, qb, qp))
    syn = {}; syn.update(GR.bash_syntax(qb)); syn.update(GR.ps_syntax(qp))
    out = {}
    for r in rows:
        if not r.get('valid'):
            continue
        bad = [(k[2], e) for k, e in syn.items() if k[0] == r['pid'] and k[1] == r['arm'] and e]
        r['syntax_errors'] = [{'action': i, 'error': e} for i, e in bad]
        r['commands_checked'] = sum(1 for k in syn if k[0] == r['pid'] and k[1] == r['arm'])
        out.setdefault(r['pid'], {})[r['arm']] = r
    os.makedirs(C.R2, exist_ok=True)
    json.dump(out, open(C.p2('mech.json'), 'w', encoding='utf-8'), indent=1)
    with open(C.p2('mech.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f); w.writerow(['pid', 'arm', 'valid', 'class_match', 'first_type_match', 'type_jaccard', 'missed_event', 'extra_action', 'cmds', 'syntax_err', 'invented_paths', 'forbidden', 'unsupported_claims'])
        for pid, d in sorted(out.items()):
            for arm, r in d.items():
                w.writerow([pid, arm, r['valid'], r.get('class_match'), r.get('first_type_match'), r.get('type_jaccard'), r.get('missed_event'), r.get('extra_action'),
                            r.get('commands_checked'), len(r.get('syntax_errors', [])), len(r.get('invented_paths', [])), len(r.get('forbidden_flags', [])), len(r.get('unsupported_claims', []))])
    print('mech: %d points, %d candidate rows -> %s' % (len(out), sum(len(v) for v in out.values()), C.p2('mech.json')))


def build_packets(chunk, seed='replay2'):
    os.makedirs(os.path.join(GRADING(), 'out'), exist_ok=True)
    mech = C.load_json(C.p2('mech.json')) or {}
    ids = [p for p in C.point_ids() if all(final_cand(p, arm) is not None for arm in C.ARMS)]
    skipped = [p for p in C.point_ids() if p not in ids]
    key = {}
    chunks = [ids[i:i + chunk] for i in range(0, len(ids), chunk)]
    labels = ['A', 'B', 'C']
    for ci, ch in enumerate(chunks, 1):
        name = 'chunk-%02d' % ci
        outfile = os.path.join(GRADING(), 'out', name + '.json')
        parts = [head_text().format(name=name, n=len(ch), harm=GR.HARM_GATE, outfile=outfile)]
        for pid in ch:
            truth = C.load_json(os.path.join(C.POINTS, pid + '.truth.json'))
            inp = C.read_input(pid)
            ev = inp.split('## EVENT BATCH', 1)[-1][:2200]
            rnd = random.Random(hashlib.sha1((seed + pid).encode()).hexdigest())
            order = list(C.ARMS); rnd.shuffle(order)
            key[pid] = {lab: order[i] for i, lab in enumerate(labels)}
            key[pid]['chunk'] = name
            t = {'class': truth['class'], 'outcome': truth['outcome'], 'actions': truth['actions'][:8], 'narration': truth['narration'][:3]}
            parts.append('\n' + '=' * 60 + '\n### POINT %s (event class %s) - full input: %s\n' % (pid, truth['class'], os.path.join(C.POINTS, pid + '.input.md')))
            parts.append('EVENT BATCH (abridged):\n' + ev + '\n')
            parts.append('TRUTH (real coordinator):\n' + json.dumps(t, indent=1)[:3500] + '\n')
            for lab in labels:
                arm = key[pid][lab]
                parts.append('CANDIDATE %s:\n%s\nmech(%s): %s\n' % (lab, json.dumps(final_cand(pid, arm), indent=1)[:3500], lab, json.dumps(GR.short_mech(mech.get(pid, {}).get(arm)))))
        with open(os.path.join(GRADING(), name + '.md'), 'w', encoding='utf-8') as f:
            f.write('\n'.join(parts))
    with open(os.path.join(GRADING(), 'key.json'), 'w', encoding='utf-8') as f:
        json.dump(key, f, indent=1)
    return ids, skipped, chunks


def cmd_packets(a):
    ids, skipped, chunks = build_packets(a.chunk)
    print('packets: %d points in %d chunks -> %s (key.json is secret); points skipped (an arm has no valid final): %s' % (len(ids), len(chunks), GRADING(), skipped))
    for ci in range(1, len(chunks) + 1):
        n = 'chunk-%02d' % ci
        print('  Agent: subagent_type kenshi-grader; description "[case:grade] [ticket:REPLAY2-%s] grade %s"; prompt "Read %s\\%s.md and follow it exactly."' % (n, n, GRADING(), n))


def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
    sp.add_parser('mech').set_defaults(f=cmd_mech)
    p = sp.add_parser('packets'); p.add_argument('--chunk', type=int, default=8); p.set_defaults(f=cmd_packets)
    a = ap.parse_args(); a.f(a)


if __name__ == '__main__':
    main()
