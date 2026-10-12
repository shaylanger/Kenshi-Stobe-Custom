#!/usr/bin/env python3
"""fist-punch-synth.py <src vmrec> <out vmrec>: synthetic "punch reads" PASS reference (mutation inverse of fq0).

No game take passes fist-punch-check.py yet (fists-fix's first rework will be the first real PASS). Until then the gate's
PASS side is this synthetic recording: the source take (fq0 = Shay-rejected badpunch) keeps its clock, states and NATIVE
arm (so fist-punch-check finds the same punches), while the measured arms are rewritten to the fists-design targets:
guard L/R (-+1.4, -0.8, 3.6); per punch (at the source's peak time tp) a .16 s wind-up .55 dm toward the shoulder, a .09 s
ease-in strike to a near-straight arm (.95 x arm length) aimed at the crosshair, a .05 s hold, a .30 s ease-out recovery;
hand X axis onto the view axis and palm (+(X x Y) in the camera frame) down at the peak; off wrist pulls back .3 dm; camera yaw +1 deg impulse. Elbows by two-bone IK
(the frame's own bone lengths, its own bend side). Synthetic data: it proves the check can PASS and anchors the
mutations; it is not a pose anyone accepted.
"""
import sys, os, math, subprocess
H = os.path.dirname(os.path.abspath(__file__))
HARN = os.environ.get('ANIMLAB_DIR', '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
sys.path.insert(0, HARN)
from recfmt import sub, add, mul, dot, ln, cross, nz

src, out = sys.argv[1], sys.argv[2]
pk = subprocess.run([sys.executable, os.path.join(H, 'fist-punch-check.py'), src, '--peaks'], stdout=subprocess.PIPE,
                    universal_newlines=True).stdout
PEAKS = [(l.split()[1], float(l.split()[2])) for l in pk.splitlines() if l.startswith('PEAK ')]
if not PEAKS:
    sys.exit('fist-punch-synth: no punch in ' + src)
GN = {'L': (-1.4, -0.8, 3.6), 'R': (1.4, -0.8, 3.6)}
TGT = {'L': (-0.12, 0.0, 1.0), 'R': (0.12, 0.0, 1.0)}   # strike direction targets (crosshair, slightly toward the hand's side)
J = {'L': (7, 8, 9), 'R': (10, 11, 12)}                   # group 1 indices: sh el wr
WU, ST, HO, RC = .16, .09, .05, .30
BACK = .55


def ease(x):
    x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)


def v3(s):
    return tuple(float(x) for x in s.split(','))


def fmt(v):
    return '%.4f,%.4f,%.4f' % v


def ik(S, W, a, b, Eo):
    d = ln(sub(W, S)); u = nz(sub(W, S))
    d = min(d, a + b - 1e-4)
    x = (a * a - b * b + d * d) / (2 * d); h = math.sqrt(max(a * a - x * x, 0.0))
    p = sub(sub(Eo, S), mul(u, dot(sub(Eo, S), u)))
    p = nz(p) if ln(p) > 1e-6 else (0.0, -1.0, 0.0)
    return add(add(S, mul(u, x)), mul(p, h))


def owner(t):
    """the punch that owns time t (nearest peak whose span covers t, spans clipped at the midpoints)"""
    best = None
    for i, (s, tp) in enumerate(PEAKS):
        lo, hi = tp - WU - ST - .04, tp + HO + RC + .04
        if i > 0 and PEAKS[i - 1][0] == s:
            lo = max(lo, (PEAKS[i - 1][1] + tp) / 2)
        if i + 1 < len(PEAKS) and PEAKS[i + 1][0] == s:
            hi = min(hi, (PEAKS[i + 1][1] + tp) / 2)
        if lo <= t <= hi and (best is None or abs(t - tp) < abs(t - best[1])):
            best = (s, tp)
    return best


lines = open(src).read().split('\n')
data = [i for i, l in enumerate(lines) if l.strip() and not l.startswith('#')]
prev_t = None
for i in data:
    g = lines[i].split(' | ')
    g0 = g[0].split(); t_rec = float(g0[1])
    t = prev_t if prev_t is not None else t_rec   # measured joints of record n = frame n-1
    prev_t = t_rec
    g1 = g[1].split()
    ow = owner(t)
    yaw_off = 0.0
    for s in 'LR':
        S, Eo, Wo = (v3(g1[k]) for k in J[s])
        a, b = ln(sub(Eo, S)), ln(sub(Wo, Eo))
        G = GN[s]
        W = G
        if ow and ow[0] == s:
            tp = ow[1]; dt = t - tp
            Pk = add(S, mul(nz(sub(mul(TGT[s], 5.0), S)), .95 * (a + b)))   # the frame's own shoulder (the native body moves it ~1 dm)
            su = nz(sub(S, G))
            if dt < -ST:      # wind-up toward the shoulder: rise then hold until the strike
                x = (dt + ST + WU) / WU
                W = add(G, mul(su, BACK * ease(x)))
            elif dt < 0:      # strike: from the wound-up point to the peak, ease-in (fast at the end)
                x = (dt + ST) / ST
                W0 = add(G, mul(su, BACK))
                W = add(W0, mul(sub(Pk, W0), x ** 1.6))
            elif dt <= HO:
                W = Pk
            else:
                x = (dt - HO) / RC
                W = add(Pk, mul(sub(G, Pk), ease(x)))
            if -ST <= dt <= HO + RC * .5:
                yaw_off = 1.0 * (ease((dt + ST) / ST) if dt < 0 else 1.0 - ease(dt / .08))
        elif ow:              # off hand: pulls back toward the chin through the other hand's strike
            dt = t - ow[1]
            k = ease((dt + .04) / .04) if dt < 0 else 1.0 - ease((dt - HO) / RC)   # during the strike itself (C8 compares t20 vs peak)
            W = add(G, mul((0.0, 0.15, -0.35), k))
        g1[J[s][2]] = fmt(W)
        g1[J[s][1]] = fmt(ik(S, W, a, b, Eo))
    g[1] = ' '.join(g1)
    g0[14] = '%.2f' % (float(g0[14]) + yaw_off)
    g[0] = ' '.join(g0)
    for k, x in enumerate(g):   # hand axes: the striking hand's X axis onto the view axis around its peak
        tk = x.split()
        if tk[:1] == ['F'] and ow:
            j = 1 if ow[0] == 'L' else 3
            dt = t - ow[1]
            w_ = ease((dt + ST) / ST) if dt < 0 else 1.0 - ease((dt - HO) / RC)
            X, Y = v3(tk[j]), v3(tk[j + 1])
            Xn = nz(add(mul(X, 1 - w_), mul((0.0, 0.0, 1.0), w_)))
            Zt = nz(sub((0.0, -1.0, 0.0), mul(Xn, -Xn[1])))        # camera-frame X x Y down = palm down (the rec's camera frame is
            Yt = cross(Zt, Xn)                                      # left-handed: palm = +(X x Y) there, fist-punch-check C7)
            Yo = nz(sub(Y, mul(Xn, dot(Y, Xn))))
            Yn = nz(add(mul(Yo, 1 - w_), mul(Yt, w_)))
            Yn = nz(sub(Yn, mul(Xn, dot(Yn, Xn))))
            tk[j], tk[j + 1] = fmt(Xn), fmt(Yn)
            g[k] = ' '.join(tk)
    lines[i] = ' | '.join(g)
open(out, 'w').write('\n'.join(lines))
print('fist-punch-synth: %d punches -> %s' % (len(PEAKS), out))
