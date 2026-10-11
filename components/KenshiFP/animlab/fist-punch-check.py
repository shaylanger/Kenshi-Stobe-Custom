#!/usr/bin/env python3
"""fist-punch-check.py <vmrec.txt> [--camera] [--only C1,C2,...] [-v]

"Punch reads" (NA1 fists, fists-design 2026-10-11, harness Misses "fist punch read"): Shay rejected FP fists on fq0 ("the
hands just moved a little bit and lacked any actual substance") while every lab + take check passed. CLASS: a punch that
does not read in first person (no depth, misses the crosshair, small, soft symmetric S-curve, no wind-up, no stop,
side/palm-on hand, dead off hand, still camera). Judged on the per-frame KenshiFP recording (`fp_vm rec dump`, recfmt.py),
never the 1.2 Hz fp_vm fist lines.

Punch = per hand, a stretch of first-person frames where the NATIVE arm (rec group 5, pre-IK) extends forward the way
kfp-fist-strike gates it: es = smoothstep(|W-S|/(|E-S|+|W-E|), .70, .86) x smoothstep(forearm-line forwardness z, .75, .95)
>= 0.5 (gaps <= 2 frames merged). The measured (rendered) wrist of record i+1 is paired with record i's clock + native pose.
Guard g = median measured wrist over the ready frames. Peak = the most-forward (max z) measured wrist within .15 s of the
es stretch. Strike line = unit(peak - g); progress p(t) = (w(t) - g) . line; strike start t20 = last frame before the peak
with p <= .2 p_peak, t90 = first frame after t20 with p >= .9 p_peak. Screen numbers: FP vFOV 70, 16:9 (metrics TX/TY).
Rows (each = worst punch; a check FAILs if any punch fails it; no punch at all = every row FAIL):
  C1 depth   z_peak / z_guard >= 1.35 and the measured arm near-straight at the peak: |W-S| / (|E-S|+|W-E|) >= .92
  C2 aim     peak wrist on screen inside the centre box x 40-60 %, y 42-55 % (y from the top)
  C3 travel  screen travel from the guard >= 20 % of the screen height (x in height units) and the FP strike (furthest
             wound-up point -> peak) >= .25 x native travel (native wrist from its ready median; spec said .35, but its own
             guard (z 3.4-3.8) -> centre box (z ~5) geometry gives 2.0-2.6 dm vs native 7-9 dm = .25-.30; fq0 .14)
  C4 snap    t90 - t20 <= .150 s for a straight punch (NATIVE wrist at its max es vs its guard: |dz| >= |dx|), <= .220 s for a hook
  C5 recover peak -> back to p <= .2 p_peak (or the end of the FP stretch) >= 1.5 x (t90 - t20)
  C6 windup  in the .08-.20 s before t20 the wrist moves >= .3 dm toward its shoulder (from the guard, along unit(S - g))
  C7 hand    at the peak the striking hand's forward axis (hand bone X, rec group F) within 35 deg of the view axis (+z), its
             palm (-hand Z, Z = X x Y: the convention of animlab native.py fist_hand) within 60 deg of down (knuckles up/forward,
             not the palm-up / side-on reach), and from t20 to peak+.1 s the palm never within 60 deg of the wrist->camera ray
  C8 off     the other wrist at the peak vs at t20: moves <= .5 dm and pulls back (dz <= -.15 dm)
  hold       after the peak the wrist speed stays < 10 % of the strike's peak speed for >= 2 frames (within .1 s of the peak)
  C9 camera  (report-only until the camera-impulse toggle ships; --camera gates it) camera yaw/pitch moves .5-1.5 deg
             within .1 s of the peak (vs .15 s before t20) and comes back within .3 s
Prints one row per check and `RESULT FIST-PUNCH PASS|FAIL punches=<n> <row>=<verdict> ...`; exit 0 PASS, 1 FAIL.
"""
import sys, os, math, argparse
HARN = os.environ.get('ANIMLAB_DIR', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
if not os.path.isdir(HARN):
    HARN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'Kenshi-Automation-Harness', 'tools', 'animlab')
sys.path.insert(0, HARN)
import recfmt
from recfmt import sub, dot, ln

TX, TY = 1.245, 0.70
ap = argparse.ArgumentParser()
ap.add_argument('rec'); ap.add_argument('--camera', action='store_true', help='C9 gates (camera impulse toggle shipped)')
ap.add_argument('--only', default=''); ap.add_argument('-v', action='store_true')
ap.add_argument('--detect', default='native', choices=('native', 'fp'), help='punch stretches from the native arm (es, default) or from the FP wrist itself (fp: measured wrist >= guard z + .8 dm, any state; synthesized FP punches kfp-fist-zpunch / fp_fire takes, whose timing does not follow the native es)')
ap.add_argument('--peaks', action='store_true', help='also print PEAK <hand> <t_peak> <t20> <guard x,y,z> per punch (mutate.py / fist-punch-synth.py)')
a = ap.parse_args()
R = recfmt.parse(a.rec).frames


def ss(x, e0, e1):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def es(n, s):
    S, E, W = n[s + 'sh'], n[s + 'el'], n[s + 'wr']
    v = sub(W, S); L_ = ln(sub(E, S)) + ln(sub(W, E)); m = ln(v)
    return ss(m / L_, .70, .86) * ss(v[2] / m, .75, .95) if L_ > 1e-3 and m > 1e-3 else 0.0


def med(vs):
    return tuple(sorted(v[j] for v in vs)[len(vs) // 2] for j in range(3)) if vs else None


def scr(w):   # screen % (x from the left, y from the top)
    return (50 + 50 * w[0] / (w[2] * TX), 50 - 50 * w[1] / (w[2] * TY)) if w[2] > .05 else (999.0, 999.0)


def scr_h(w):  # screen position in screen-height units
    return (0.5 * w[0] / (w[2] * TY), 0.5 * w[1] / (w[2] * TY)) if w[2] > .05 else (99.0, 99.0)


def ang(u, v):
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(u, v) / max(1e-9, ln(u) * ln(v))))))


# frames: (t, st, measured record (i+1), native record i, yaw, pitch); first person only
F = []
for i in range(len(R) - 1):
    q, r = R[i], R[i + 1]
    if q.get('zoom', 0.0) >= 0.5 or not r.get('Lwr'):
        continue
    F.append(dict(t=q['t'], st=q['st'], m=r, n=q.get('nat'), yaw=q.get('yaw', 0.0), pitch=q.get('pitch', 0.0)))
ready = [f for f in F if f['st'] == 'ready']
G = {s: med([f['m'][s + 'wr'] for f in ready]) for s in 'LR'}
NG = {s: med([f['n'][s + 'wr'] for f in ready if f['n']]) for s in 'LR'}
SH = {s: med([f['m'][s + 'sh'] for f in ready]) for s in 'LR'}

# punches: es >= .5 stretches (gaps <= 2 frames), swinging frames only
P = []
for s in 'LR':
    run = None
    for k, f in enumerate(F):
        if a.detect == 'fp':
            on = G[s] is not None and f['m'][s + 'wr'][2] >= G[s][2] + 0.8
        else:
            on = f['st'] == 'swinging' and f['n'] is not None and es(f['n'], s) >= 0.5
        if on:
            run = [k, k] if run is None or k - run[1] > 3 else [run[0], k]
            if run[0] == k:
                P.append([s, run])
            else:
                P[-1][1] = run
P = [(s, r[0], r[1]) for s, r in P]
P.sort(key=lambda x: F[x[1]]['t'])


def at(t0, t1):
    return [k for k, f in enumerate(F) if t0 <= f['t'] <= t1]


PK = []
rows = {c: [] for c in ('C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'hold', 'C9')}
if ready:
    for s, k0, k1 in P:
        o = 'R' if s == 'L' else 'L'
        g = G[s]
        tA, tB = F[k0]['t'], F[k1]['t']
        win = at(tA - .15, tB + .15)
        kp = max(win, key=lambda k: F[k]['m'][s + 'wr'][2])
        tp = F[kp]['t']; wp = F[kp]['m'][s + 'wr']
        dv = sub(wp, g); dl = max(ln(dv), 1e-6); line = tuple(x / dl for x in dv)
        ext = at(tp - .6, tp + .8)
        # stop the extended range at the next punch's es stretch of this hand / a ready frame far after
        p = {k: dot(sub(F[k]['m'][s + 'wr'], g), line) for k in ext}
        pk = p[kp]
        pre = [k for k in ext if k < kp]
        k20 = max([k for k in pre if p[k] <= .2 * pk], default=pre[0] if pre else kp)
        k90 = min([k for k in ext if k > k20 and p[k] >= .9 * pk], default=kp)
        t20, t90 = F[k20]['t'], F[k90]['t']; st_ = t90 - t20
        post = [k for k in ext if k > kp]
        kr = min([k for k in post if p[k] <= .2 * pk], default=post[-1] if post else kp)
        rec_ = F[kr]['t'] - tp
        tag = '%s@%.2f' % (s, tp - (F[0]['t'] if F else 0))
        PK.append('PEAK %s %.4f %.4f %.4f,%.4f,%.4f' % (s, tp, t20, g[0], g[1], g[2]))
        # C1 depth
        zr = wp[2] / g[2]
        mp_ = F[kp]['m']
        xr = ln(sub(wp, mp_[s + 'sh'])) / max(ln(sub(mp_[s + 'el'], mp_[s + 'sh'])) + ln(sub(wp, mp_[s + 'el'])), 1e-6)
        rows['C1'].append((zr >= 1.35 and xr >= .92, min(zr / 1.35, xr / .92), '%s z %.2f/%.2f=%.2f (>= 1.35), arm extension %.2f (>= .92)' % (tag, wp[2], g[2], zr, xr)))
        # C2 aim
        x_, y_ = scr(wp)
        rows['C2'].append((40 <= x_ <= 60 and 42 <= y_ <= 55, -max(0, 40 - x_, x_ - 60, 42 - y_, y_ - 55), '%s peak at x %.0f%% y %.0f%% (box 40-60, 42-55)' % (tag, x_, y_)))
        # C3 travel
        g_h = scr_h(g)
        trav = max(math.dist(scr_h(F[k]['m'][s + 'wr']), g_h) for k in at(t20 - .05, tp + .05)) * 100
        fpt = max(ln(sub(wp, F[k]['m'][s + 'wr'])) for k in at(t20 - .25, tp))   # visible strike: furthest wound-up point -> peak
        nat = max((ln(sub(F[k]['n'][s + 'wr'], NG[s])) for k in win if F[k]['n'] and NG[s]), default=0.0)
        fr = fpt / nat if nat > 1e-6 else 0.0
        rows['C3'].append((trav >= 20 and fr >= .25, min(trav / 20, fr / .25), '%s screen %.0f%% of height (>= 20), fp %.2f / native %.2f dm = %.2f (>= .25)' % (tag, trav, fpt, nat, fr)))
        # C4 snap
        # jab vs hook from the NATIVE technique (the FP motion of a bad punch is itself a sideways swipe)
        kn = max((k for k in range(k0, k1 + 1) if F[k]['n'] and NG[s]), key=lambda k: es(F[k]['n'], s), default=None)
        nd = sub(F[kn]['n'][s + 'wr'], NG[s]) if kn is not None else dv
        if a.detect == 'fp': nd = dv   # synthesized punch: its own path says jab or hook
        straight = abs(nd[2]) >= abs(nd[0]); lim = .150 if straight else .220
        rows['C4'].append((0 < st_ <= lim, -st_, '%s strike 20->90%% %.3f s (%s <= %.3f)' % (tag, st_, 'jab' if straight else 'hook', lim)))
        # C5 recovery asymmetry
        rows['C5'].append((st_ > 0 and rec_ >= 1.5 * st_, rec_ / st_ if st_ > 0 else 0, '%s recovery %.3f s vs 1.5 x strike %.3f' % (tag, rec_, 1.5 * st_)))
        # C6 wind-up toward the shoulder
        su = sub(SH[s], g); su = tuple(x / max(ln(su), 1e-6) for x in su)
        wu = max((dot(sub(F[k]['m'][s + 'wr'], g), su) for k in at(t20 - .20, t20 - .08)), default=0.0)
        rows['C6'].append((wu >= .3, wu, '%s wind-up toward the shoulder %.2f dm (>= .30)' % (tag, wu)))
        # C7 hand presentation
        fh = F[kp]['m'].get('fh')
        if fh:
            j = 0 if s == 'L' else 2
            fa = ang(fh[j], (0.0, 0.0, 1.0))
            def palm(k):   # palm normal = -hand Z (Z = X x Y; animlab fist_hand: the mesh fingers curl toward -Z)
                h = F[k]['m']['fh']; return tuple(-x for x in recfmt.cross(h[j], h[j + 1]))
            pd = ang(palm(kp), (0.0, -1.0, 0.0))
            pc = min(ang(palm(k), tuple(-x for x in F[k]['m'][s + 'wr'])) for k in at(t20, tp + .1) if F[k]['m'].get('fh'))
            rows['C7'].append((fa <= 35 and pd <= 60 and pc > 60, -max(fa / 35, pd / 60, 60 / max(pc, 1)),
                               '%s hand forward %.0f deg off the view axis (<= 35), palm %.0f deg from down (<= 60), palm->camera min %.0f deg (> 60)' % (tag, fa, pd, pc)))
        else:
            rows['C7'].append((False, -999, '%s no hand axes (rec group F)' % tag))
        # C8 off hand
        od = sub(F[kp]['m'][o + 'wr'], F[k20]['m'][o + 'wr'])
        rows['C8'].append((ln(od) <= .5 and od[2] <= -.15, -od[2], '%s off hand %s moved %.2f dm, dz %+.2f (<= .5, dz <= -.15)' % (tag, o, ln(od), od[2])))
        # hold at peak
        def spd(k):
            return ln(sub(F[k]['m'][s + 'wr'], F[k - 1]['m'][s + 'wr'])) / max(F[k]['t'] - F[k - 1]['t'], 1e-4)
        vmax = max((spd(k) for k in range(max(k20, 1), kp + 1)), default=0.0)
        best = cur = 0
        for k in at(tp - .02, tp + .1):
            if k < 1:
                continue
            cur = cur + 1 if spd(k) < .1 * vmax else 0; best = max(best, cur)
        rows['hold'].append((vmax > 0 and best >= 2, best, '%s frames under 10%% of strike speed %.1f dm/s: %d (>= 2)' % (tag, vmax, best)))
        # C9 camera impulse
        kb = min(range(len(F)), key=lambda k: abs(F[k]['t'] - (t20 - .15)))   # baseline before the strike
        y0, p0 = F[kb]['yaw'], F[kb]['pitch']
        def cd(k):
            dy = (F[k]['yaw'] - y0 + 180) % 360 - 180
            return math.hypot(dy, F[k]['pitch'] - p0)
        imp = max((cd(k) for k in at(tp - .1, tp + .1)), default=0.0)
        back = min((cd(k) for k in at(tp + .1, tp + .3)), default=99.0)
        rows['C9'].append((.5 <= imp <= 1.5 and back <= .25 * max(imp, 1e-6), imp, '%s camera impulse %.2f deg (.5-1.5), back to %.2f deg by +.3 s' % (tag, imp, back)))

only = [x for x in a.only.split(',') if x]
gate = [c for c in rows if (not only or c in only) and (c != 'C9' or a.camera)]
verd = {}
for c in rows:
    v = rows[c]
    if not v:
        ok, msg = False, 'no punch (native es >= .5 never)' if ready else 'no ready frames (guard)'
    else:
        ok = all(x[0] for x in v)
        w = min(v, key=lambda x: (x[0], x[1]))
        msg = '%d/%d punches ok; worst %s' % (sum(1 for x in v if x[0]), len(v), w[2])
    verd[c] = 'PASS' if ok else 'FAIL'
    lab = verd[c] if c in gate else ('INFO-' + verd[c])
    print('%-5s %-9s %s' % (c, lab, msg))
    if a.v:
        for x in v:
            print('      %s %s' % ('ok ' if x[0] else 'BAD', x[2]))
bad = [c for c in gate if verd[c] == 'FAIL']
if a.peaks:
    print(chr(10).join(PK))
print('RESULT FIST-PUNCH %s punches=%d %s' % ('FAIL' if bad or not P else 'PASS', len(P),
                                              ' '.join('%s=%s' % (c, verd[c] if c in gate else 'info') for c in rows)))
sys.exit(1 if bad or not P else 0)
