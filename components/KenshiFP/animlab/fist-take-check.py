#!/usr/bin/env python3
"""fist-take-check.py <vmrec.txt> <lab technique dir (native.py fists --out <dir>/<tech>: pose.txt + keys.json) | - (native fists)> [--max-err 0.6]

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
  lens    (spec U24) EVERY first-person frame of the take, any technique (verified or not): no arm point (shoulder ->
          elbow -> wrist, 11 samples per bone) on screen nearer than --lens-near dm (forearm at the lens / cut by the near
          plane), and no wrist in the top band of the view (y_ndc > --high-y) for longer than --high-s s (arm swung up
          huge). CLASS: arm across the lens (Misses FIST-ma_chudan/badpunch/ma_2strike fist4080n+p: forearm fills a
          third of the frame, hollow sleeve at the near plane, wrist in the top-left corner with the elbow out of frame).
  hand    (spec U25) EVERY first-person frame, any technique: each hand's rendered orientation (hand bone X and Y axes,
          rec group F, both hands; older recordings: the weapon hand 'mh' only) stays within --hand-max deg of its guard
          orientation (median over the ready frames), no excursion longer than --hand-s s. CLASS: native hand flails
          (fist4080r C2/C0: knuckles end-on at the lens / fingers-up palm during kicks while the wrist stayed put).
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
ap.add_argument('--lens-near', type=float, default=1.0); ap.add_argument('--high-y', type=float, default=0.5)
ap.add_argument('--high-s', type=float, default=0.3)
ap.add_argument('--hand-max', type=float, default=60.0); ap.add_argument('--hand-s', type=float, default=0.1)
a = ap.parse_args()
R = recfmt.parse(a.rec).frames
NOLAB = a.lab == '-'   # native fists (fp-fists.sh FIST_NATIVE=1): no lab technique; swings/view rows + lens/hand only
kj = {'anim': 'native'} if NOLAB else json.load(open(os.path.join(a.lab, 'keys.json')))
P = [] if NOLAB else [f for f in spec.read_pose(os.path.join(a.lab, 'pose.txt')) if f['t'] >= 0]
dur = 1.0 if NOLAB else float(kj.get('length') or P[-1]['t']); near = float(kj.get('near', 2.0)); strikers = kj.get('strikers') or ['R']


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
    if lean > a.body_max and not NOLAB:   # native fists: every native technique moves the body
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
g = {s: P[0][s]['wr'] for s in 'LR'} if P else {}
for u, r in rows:
    L = lab_at(u) if P else None
    for s in 'LR':
        w = r[s + 'wr']
        if P:
            err.append(math.dist(w, L[s]['wr']))
            travel[s] = max(travel[s], math.dist(w, g[s]))
        if not spec._onscr(w, near, 1.0):
            off[s] += 1
if n and P:
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
# lens (U24): all first-person frames (zoom < 0.5 dm), measured joints of record i = frame i-1 (the time of record i-1)
TX, TY = 1.245, 0.70   # metrics.TX/TY: Kenshi FP view tan half-angles


def ndc(p):
    return (p[0] / p[2] / TX, p[1] / p[2] / TY) if p[2] > 0.05 else None


lens_n, lens_w, high, run = 0, None, [], {s: None for s in 'LR'}
fp = [(R[i - 1]['t'], R[i]) for i in range(1, len(R)) if R[i - 1].get('zoom', 0.0) < 0.5 and R[i].get('Lwr')]
for t, r in fp:
    dmin = 99.0
    for s in 'LR':
        for a0, b0 in ((r[s + 'sh'], r[s + 'el']), (r[s + 'el'], r[s + 'wr'])):
            for k in range(11):
                p = tuple(a0[j] + (b0[j] - a0[j]) * k / 10.0 for j in range(3))
                q = ndc(p)
                if q and abs(q[0]) <= 1.0 and abs(q[1]) <= 1.0:
                    dmin = min(dmin, p[2])
        q = ndc(r[s + 'wr'])
        hi = bool(q) and q[1] > a.high_y and abs(q[0]) <= 1.2
        if hi and run[s] is None:
            run[s] = t
        elif not hi and run[s] is not None:
            high.append((t - run[s], s, run[s])); run[s] = None
    if dmin < a.lens_near:
        lens_n += 1
        lens_w = min(lens_w or (99.0, 0), (dmin, t))
for s in 'LR':
    if run[s] is not None and fp:
        high.append((fp[-1][0] - run[s], s, run[s]))
t0 = fp[0][0] if fp else 0.0
hb = [h for h in high if h[0] > a.high_s]
hw = max(high) if high else (0.0, '-', t0)
res.append(('lens', 'PASS' if fp and not lens_n and not hb else 'FAIL',
            'fp frames %d; arm nearer than %.1f dm on screen %d%s; wrist above y %.2f longest %.2f s (%s at %.1f s, <= %.2f)' % (
                len(fp), a.lens_near, lens_n, (' (nearest %.2f dm at %.1f s)' % (lens_w[0], lens_w[1] - t0)) if lens_w else '',
                a.high_y, hw[0], hw[1], hw[2] - t0, a.high_s)))
# hand (U25): rendered hand orientation vs its guard orientation, every FP frame (record i = frame i-1)
def _ang(u, v):
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(p * q for p, q in zip(u, v)) / max(1e-9, math.sqrt(sum(p * p for p in u) * sum(q * q for q in v)))))))


def _axes(r):
    if r.get('fh'):
        return {'L': r['fh'][0:2], 'R': r['fh'][2:4]}
    return {'R': (r['mh'],)} if r.get('mh') else {}


hf = [(R[i - 1]['t'], R[i - 1]['st'], _axes(R[i])) for i in range(1, len(R)) if R[i - 1].get('zoom', 0.0) < 0.5]
hf = [x for x in hf if x[2]]
src = 'F' if any(R[i].get('fh') for i in range(len(R))) else 'mh(R only)'
gd = {}
for s_ in 'LR':
    G = [x[2][s_] for x in hf if x[1] == 'ready' and s_ in x[2]]
    if G:
        gd[s_] = [tuple(sorted(g[k][j] for g in G)[len(G) // 2] for j in range(3)) for k in range(len(G[0]))]
hmax, hrun, hbad = {s_: (0.0, 0.0) for s_ in gd}, {s_: None for s_ in gd}, []
for t, st, ax in hf:
    for s_ in gd:
        if s_ not in ax:
            continue
        d = max(_ang(ax[s_][k], gd[s_][k]) for k in range(len(gd[s_])))
        if d > hmax[s_][0]:
            hmax[s_] = (d, t)
        if d > a.hand_max and hrun[s_] is None:
            hrun[s_] = t
        elif d <= a.hand_max and hrun[s_] is not None:
            hbad.append((t - hrun[s_], s_, hrun[s_])); hrun[s_] = None
for s_ in gd:
    if hrun[s_] is not None and hf:
        hbad.append((hf[-1][0] - hrun[s_], s_, hrun[s_]))
ht0 = hf[0][0] if hf else 0.0
hlong = max(hbad) if hbad else (0.0, '-', ht0)
res.append(('hand', 'PASS' if gd and not [h for h in hbad if h[0] > a.hand_s] else 'FAIL',
            'hand ori vs guard (%s): max %s; longest > %.0f deg %.2f s (%s at %.1f s, <= %.2f)' % (
                src, ' '.join('%s %.0f deg at %.1f s' % (s_, hmax[s_][0], hmax[s_][1] - ht0) for s_ in sorted(gd)) or 'n/a',
                a.hand_max, hlong[0], hlong[1], hlong[2] - ht0, a.hand_s)))
for x in res:
    print('%-7s %-4s %s' % x)
bad = [x[0] for x in res if x[1] == 'FAIL']
print('fistgame %s %s %s' % ('PASS' if not bad and n else 'FAIL', kj.get('anim', '?'), ' '.join('%s=%s' % (x[0], x[1]) for x in res)))
sys.exit(0 if not bad and n else 1)
