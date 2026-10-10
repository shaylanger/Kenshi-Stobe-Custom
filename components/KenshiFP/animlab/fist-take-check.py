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
  hud     wrists clear of the game HUD (spec U23, spec.HUD_RECTS): hidden share <= .08 per hand in the ready frames and
          in the swing frames (FIST-shoteiL op-b6: fists half under the HUD while the HUD-less sheets showed them)
Only verified swings count for match/plays/view/hud: a swing whose native body (spine, recorded 'sp') leaves the guard
body by > --body-max dm is another native technique under the arms (the fist_tech force bug: op-b6 shoteiL swing 3 leaned
~8 dm), and with --swings <KenshiFP.log swing lines> only as many swings as there are "tech='<anim>' ... fallback=0"
lines (the first ones) are trusted. The lab clock is u * keys.json length (pose.txt runs on past the clip by the
motion's hold: the old dur = last pose time skewed every lab frame by 20%, op-b6).
"""
import sys, os, json, math, argparse
HARN = os.environ.get('ANIMLAB_DIR', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
if not os.path.isdir(HARN):   # 4080 (Windows python, no /mnt/c): the harness tree next to this repo
    HARN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab')
sys.path.insert(0, HARN)
import recfmt, spec

ap = argparse.ArgumentParser()
ap.add_argument('rec'); ap.add_argument('lab'); ap.add_argument('--max-err', type=float, default=0.6)
ap.add_argument('--swings', help='KenshiFP.log [vm] fist swing lines of this take'); ap.add_argument('--body-max', type=float, default=3.0)
a = ap.parse_args()
R = recfmt.parse(a.rec).frames
kj = json.load(open(os.path.join(a.lab, 'keys.json')))
P = [f for f in spec.read_pose(os.path.join(a.lab, 'pose.txt')) if f['t'] >= 0]
dur = float(kj.get('length') or P[-1]['t']); near = float(kj.get('near', 2.0)); strikers = kj.get('strikers') or ['R']


def lab_at(u):
    t = max(0.0, min(1.0, u)) * dur
    k = min(range(len(P)), key=lambda i: abs(P[i]['t'] - t))
    return P[k]


anim = kj.get('anim', '?')
nlog = None
if a.swings:
    nlog = sum(1 for ln in open(a.swings, errors='replace') if "tech='%s'" % anim in ln and 'fallback=0' in ln)
gb = next((f['sp'] for f in R if f['st'] == 'ready' and f.get('sp') and any(f['sp'])), None)   # guard body (spine)
per, swings, last, guard = {}, 0, None, []
for i in range(1, len(R)):
    q, r = R[i - 1], R[i]
    if q['st'] == 'ready':
        guard.append(r)
    if q['st'] != 'swinging' or not (0.0 <= q['prog'] <= 1.0):
        last = None; continue
    if last is None or q['prog'] < last - 0.3:   # a new swinging stretch, or the clock restarted (next swing)
        swings += 1
    last = q['prog']
    per.setdefault(swings, []).append((q['prog'], r))
ok_sw, notes = [], []
for k in sorted(per):
    lean = max((math.dist(r['sp'], gb) for u, r in per[k] if gb and r.get('sp')), default=0.0)
    if lean > a.body_max:
        notes.append('swing %d body %.1f dm off the guard (other native technique)' % (k, lean))
    elif nlog is not None and len(ok_sw) >= nlog:
        notes.append('swing %d not in the swing log (forced %s lines %d)' % (k, anim, nlog))
    else:
        ok_sw.append(k)
rows = [x for k in ok_sw for x in per[k]]
res = []
n = len(rows)
res.append(('swings', 'PASS' if n >= 10 else 'FAIL', 'swinging frames %d, swings %d, verified %d%s' % (
    n, swings, len(ok_sw), ('; excluded: ' + '; '.join(notes)) if notes else '')))
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
    hh = {s: sum(1 for u, r in rows if spec._hud(r[s + 'wr'], near)) / float(n) for s in 'LR'}
    gh = {s: sum(1 for r in guard if spec._hud(r[s + 'wr'], near)) for s in 'LR'}
    ng = float(max(len(guard), 1))
    res.append(('hud', 'PASS' if all(v <= 0.08 for v in hh.values()) and all(gh[x] / ng <= 0.08 for x in 'LR') else 'FAIL',
                'wrists under the game HUD: ready-frame share L %.2f R %.2f, swing share L %.2f R %.2f (<= .08 each)' % (
                    gh['L'] / ng, gh['R'] / ng, hh['L'], hh['R'])))
for x in res:
    print('%-7s %-4s %s' % x)
bad = [x[0] for x in res if x[1] == 'FAIL']
print('fistgame %s %s %s' % ('PASS' if not bad and n else 'FAIL', kj.get('anim', '?'), ' '.join('%s=%s' % (x[0], x[1]) for x in res)))
sys.exit(0 if not bad and n else 1)
