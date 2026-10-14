#!/usr/bin/env python3
"""punch-check.py <vmrec.txt> [--vfov 70] [--aspect 1.7778] [--json out.json]

FP punch read (fists-redesign 2026-10-11, Shay: "not punches at all, the arms don't extend, both hands stay side by side").
Judges every FP punch in a KenshiFP viewmodel recording (`fp_vm rec dump`, per camera frame, measured wrists in camera
numbers: x right, y up, z forward, dm). A punch = one hand's wrist leaving its guard (median ready position) by >= 0.6 dm.
Per punch (one line each), targets from the fists-design spec (C1-C8, game-feel practice at 60 fps):
  depth   z_peak / z_guard >= 1.35          (the fist visibly shrinks: a FP punch reads through depth)        C1
  aim     straight punches peak in the centre box x 35-65 %, y 38-62 % of the screen (knuckles near the crosshair) C2
  travel  screen travel guard -> peak >= 20 % of the screen height                                             C3
  snap    20 % -> 90 % of the travel in 40-180 ms                                                               C4
  hold    wrist within 0.15 dm of its peak for >= 2 frames                                                       C5
  recover peak -> back to 20 % takes >= 1.3 x the snap time                                                      C5
  windup  the wrist first moves 0.15-0.9 dm AWAY from the strike direction within 300 ms before it             C6
  offhand the other wrist moves <= 1.0 dm (stays in guard / tucks to the chin)                                  C8
  sides   both hands at the guard are >= 25 % of the screen width apart, each in its own half                  (Shay: side by side)
CLASS: weak-punch (fists-fix fq0/NA1-fists.mp4: depth 1.13, peak at chest height, no snap/hold/wind-up). Last line:
  RESULT punch PASS|FAIL punches=<n> pass=<k> [first failure]
"""
import sys, os, math, argparse, json
HARN = os.environ.get('ANIMLAB_DIR', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
if not os.path.isdir(HARN):
    HARN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab')
sys.path.insert(0, HARN)
import recfmt

ap = argparse.ArgumentParser()
ap.add_argument('rec'); ap.add_argument('--vfov', type=float, default=70.0); ap.add_argument('--aspect', type=float, default=16 / 9)
ap.add_argument('--json'); ap.add_argument('--min-exc', type=float, default=0.6)
a = ap.parse_args()
TY = math.tan(math.radians(a.vfov / 2)); TX = TY * a.aspect
def scr(p):   # screen % (x from left, y from top)
    z = max(p[2], 1e-3); return (50 + 50 * p[0] / z / TX, 50 - 50 * p[1] / z / TY)
sub, ln = recfmt.sub, recfmt.ln
F = [r for r in recfmt.parse(a.rec).frames if r.get('Lwr') and r['zoom'] < 1.0]
if len(F) < 30:
    print('RESULT punch FAIL setup: %d first-person frames' % len(F)); sys.exit(1)
# guard per hand: median over frames with both wrists slow (ready stance)
def med(v): v = sorted(v); return v[len(v) // 2]
G = {}
for h in 'LR':
    ok = [r[h + 'wr'] for i, r in enumerate(F[1:], 1) if r['st'] in ('ready', 'swinging') and ln(sub(r[h + 'wr'], F[i - 1][h + 'wr'])) < 0.02]
    if not ok: ok = [r[h + 'wr'] for r in F]
    G[h] = tuple(med([p[k] for p in ok]) for k in range(3))
gs = {h: scr(G[h]) for h in 'LR'}
res = []; out = []
sides_ok = gs['L'][0] < 50 < gs['R'][0] and gs['R'][0] - gs['L'][0] >= 25
out.append('guard L %.1f,%.1f,%.1f (%.0f%%,%.0f%%) R %.1f,%.1f,%.1f (%.0f%%,%.0f%%) sides %s' % (*G['L'], *gs['L'], *G['R'], *gs['R'], 'PASS' if sides_ok else 'FAIL'))
for h in 'LR':
    o = 'R' if h == 'L' else 'L'
    d = [ln(sub(r[h + 'wr'], G[h])) for r in F]
    i = 0; n = len(F)
    while i < n:
        if d[i] < a.min_exc: i += 1; continue
        s = i
        while s > 0 and d[s - 1] > 0.15: s -= 1
        e = i
        while e < n - 1 and d[e + 1] > 0.15: e += 1
        seg = F[s:e + 1]; k = max(range(s, e + 1), key=lambda j: F[j][h + 'wr'][2] - 0.3 * abs(F[j][h + 'wr'][0]))
        P = F[k][h + 'wr']; tp = F[k]['t']
        trav = d[k]
        def tcross(frac, lo, hi, rising):
            rng = range(lo, hi + 1) if rising else range(hi, lo - 1, -1)
            for j in rng:
                if (d[j] >= frac * trav) if rising else (d[j] <= frac * trav): return F[j]['t']
            return None
        t20 = tcross(0.2, s, k, True); t90 = tcross(0.9, s, k, True)
        snap = (t90 - t20) if (t20 is not None and t90 is not None) else None
        r20 = None
        for j in range(k, e + 1):
            if d[j] <= 0.2 * trav: r20 = F[j]['t']; break
        if r20 is None: r20 = F[e]['t']
        rec_t = r20 - tp
        hold = sum(1 for j in range(s, e + 1) if ln(sub(F[j][h + 'wr'], P)) <= 0.15)
        dirv = recfmt.nz(sub(P, G[h]))
        wu = 0.0
        for j in range(s - 1, -1, -1):
            if tp - F[j]['t'] > 0.6: break
            wu = max(wu, -recfmt.dot(sub(F[j][h + 'wr'], G[h]), dirv))
        for j in range(s, k):
            wu = max(wu, -recfmt.dot(sub(F[j][h + 'wr'], G[h]), dirv))
        oh = max(ln(sub(F[j][o + 'wr'], G[o])) for j in range(s, e + 1))
        ps = scr(P); g2 = scr(G[h])
        tr_scr = math.hypot((ps[0] - g2[0]) * a.aspect, ps[1] - g2[1])
        depth = P[2] / max(G[h][2], 1e-3)
        straight = abs(P[0]) < 1.2 and P[1] > G[h][1] - 0.5
        chk = [('depth', depth >= 1.35, '%.2f' % depth),
               ('aim', (35 <= ps[0] <= 65 and 38 <= ps[1] <= 62) or not straight, '%.0f%%,%.0f%%' % ps),
               ('travel', tr_scr >= 20, '%.0f%%' % tr_scr),
               ('snap', snap is not None and 0.04 <= snap <= 0.18, '%s' % ('%.0fms' % (snap * 1000) if snap is not None else '-')),
               ('hold', hold >= 2, '%d' % hold),
               ('recover', snap is not None and rec_t >= 1.3 * snap, '%.0fms' % (rec_t * 1000)),
               ('windup', 0.15 <= wu <= 0.9, '%.2fdm' % wu),
               ('offhand', oh <= 1.0, '%.2fdm' % oh)]
        okp = all(c[1] for c in chk)
        res.append(dict(hand=h, t=tp, ok=okp, checks={c[0]: [c[1], c[2]] for c in chk}, peak=P))
        out.append('punch %s t=%.2f %s ' % (h, tp, 'PASS' if okp else 'FAIL') + ' '.join('%s=%s%s' % (c[0], c[2], '' if c[1] else '!') for c in chk))
        i = e + 1
res.sort(key=lambda r: r['t'])
for l in out: print(l)
npass = sum(r['ok'] for r in res)
first = next((('%s@%.2f ' % (r['hand'], r['t'])) + ','.join(k for k, v in r['checks'].items() if not v[0]) for r in res if not r['ok']), '')
ok = bool(res) and npass == len(res) and sides_ok
if a.json: json.dump(dict(guard=G, punches=res, sides=sides_ok), open(a.json, 'w'), indent=1)
print('RESULT punch %s punches=%d pass=%d%s%s' % ('PASS' if ok else 'FAIL', len(res), npass, '' if sides_ok else ' sides!', (' first=' + first) if first else ''))
sys.exit(0 if ok else 1)
