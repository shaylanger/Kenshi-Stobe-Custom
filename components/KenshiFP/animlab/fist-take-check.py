#!/usr/bin/env python3
"""fist-take-check.py <vmrec.txt> <lab technique dir (native.py fists --out <dir>/<tech>: pose.txt + keys.json)> [--max-err 0.6]

Game take vs lab for one NA1 fist technique (fp-fists.sh). The KenshiFP recording (`fp_vm rec dump`) holds per camera
frame the swing clock (prog = g_fpc_fs_prog) and the measured arm joints; record n's joints are what frame n-1 rendered,
so they are paired with record n-1's clock. Rows (one RESULT line at the end):
  swings  swinging frames with a moving clock (>= 10 per swing expected; fewer = the technique did not play)
  match   measured wrists vs the lab's solved wrists at the same u (pose.txt, both hands): p95 <= --max-err dm
          (the lab predicts the game: a FAIL here with the lab PASS is a lab Misses row, not a refilm)
  plays   the striking hand(s) leave the guard by >= 1.0 dm (memory 'state must visibly play')
  view    every hand's wrist on screen in >= 92% of the swing frames (spec U22 on the game: fists on screen)
"""
import sys, os, json, math, argparse
HARN = os.environ.get('ANIMLAB_DIR', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
sys.path.insert(0, HARN)
import recfmt, spec

ap = argparse.ArgumentParser()
ap.add_argument('rec'); ap.add_argument('lab'); ap.add_argument('--max-err', type=float, default=0.6)
a = ap.parse_args()
R = recfmt.parse(a.rec).frames
kj = json.load(open(os.path.join(a.lab, 'keys.json')))
P = [f for f in spec.read_pose(os.path.join(a.lab, 'pose.txt')) if f['t'] >= 0]
dur = P[-1]['t']; near = float(kj.get('near', 2.0)); strikers = kj.get('strikers') or ['R']


def lab_at(u):
    t = max(0.0, min(1.0, u)) * dur
    k = min(range(len(P)), key=lambda i: abs(P[i]['t'] - t))
    return P[k]


rows, swings, last = [], 0, None
for i in range(1, len(R)):
    q, r = R[i - 1], R[i]
    if q['st'] != 'swinging' or not (0.0 <= q['prog'] <= 1.0):
        last = None; continue
    if last is None or q['prog'] < last - 0.3:   # a new swinging stretch, or the clock restarted (next swing)
        swings += 1
    last = q['prog']
    rows.append((q['prog'], r))
res = []
n = len(rows)
res.append(('swings', 'PASS' if n >= 10 else 'FAIL', 'swinging frames %d, swings %d' % (n, swings)))
err, travel, off = [], {s: 0.0 for s in 'LR'}, {s: 0 for s in 'LR'}
g = {s: P[0][s]['wr'] for s in 'LR'}
for u, r in rows:
    L = lab_at(u)
    for s in 'LR':
        w = r[s + 'wr']
        err.append(math.dist(w, L[s]['wr']))
        travel[s] = max(travel[s], math.dist(w, g[s]))
        if not spec._onscr(w, near, 1.0):
            off[s] += 1
if n:
    err.sort(); p95 = err[int(0.95 * (len(err) - 1))]
    res.append(('match', 'PASS' if p95 <= a.max_err else 'FAIL', 'game wrists vs lab p95 %.2f max %.2f dm (<= %.2f)' % (p95, err[-1], a.max_err)))
    res.append(('plays', 'PASS' if all(travel[s] >= 1.0 for s in strikers) else 'FAIL',
                'striker travel from the guard ' + ' '.join('%s %.2f' % (s, travel[s]) for s in strikers) + ' dm (>= 1.0)'))
    sh = {s: off[s] / float(n) for s in 'LR'}
    res.append(('view', 'PASS' if all(v <= 0.08 for v in sh.values()) else 'FAIL',
                'wrist off screen share L %.2f R %.2f (<= .08)' % (sh['L'], sh['R'])))
for x in res:
    print('%-7s %-4s %s' % x)
bad = [x[0] for x in res if x[1] == 'FAIL']
print('fistgame %s %s %s' % ('PASS' if not bad and n else 'FAIL', kj.get('anim', '?'), ' '.join('%s=%s' % (x[0], x[1]) for x in res)))
sys.exit(0 if not bad and n else 1)
