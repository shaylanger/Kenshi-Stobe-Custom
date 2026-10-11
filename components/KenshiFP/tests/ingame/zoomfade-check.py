#!/usr/bin/env python3
"""zoomfade-check.py <rec.txt[,rec2.txt...]> <ready|block|swing> <steps "0 0.5 ... 25"> [--bandhide 1|0]
(several recs = one sweep dumped in chunks: the fp_vm recorder holds 6000 frames)
Z1 zoom crossfade check (COMBAT_TEST_PLAN Gate 6): an fp_vm rec dump of a camera sweep (fp_camera distance d held at each
step) in ONE sword state. The viewmodel weight zf = 1 - smoothstep((d - zf0) / (zf1 - zf0)) (KenshiFP g_vm_zf0/zf1 = 2/8 dm)
blends the eye-relative FP pose into the native third-person pose; the band hide (fp_camera bandhide 1, default) hides the
whole character between the eye (0.65 dm) and head_show_dm (16 dm).
Per step (frames whose recorded zoom is within 0.05 dm of the step; held states only frames in that state, swing = frames
of a swing):
  band    bandhide 1: every frame with 0.65 <= zoom < HEAD_SHOW (16) has band_hidden=1, every frame at >= HEAD_SHOW 0
  head    right wrist + grip >= HD_MIN (2.0 dm) from the head centre (head bone + 0.9 dm along neck->head), on visible
          frames with zoom >= 0.65 (zoom-0 frames are the FP viewmodel in front of the eye)
  vis     >= 5 of the 21 grip->tip points on screen from the zoomed camera (0,0,-zoom), visible frames
  stretch upper arm / forearm lengths of both arms vs the native lengths at the farthest step: per segment the ratio
          stays within [min(1, r0)*(1-ST_TOL), max(1, r0)*(1+ST_TOL)] (r0 = that segment's zoom-0 FP ratio, accepted FP
          stretch; ST_TOL 0.08): the half-mix must not stretch/shrink a limb beyond both end poses
          and the recorded upper-arm stretch <= max(1.05 * zoom-0 stretch, 1.05)
  jump    per step pose = median of the joints (both arms, grip, blade tip) relative to the spine in WORLD axes (the camera
          basis rotates with the orbit); adjacent visible steps: max joint move <= J_MIN (0.8 dm) + J_K (2.0) * expected,
          expected = |dzf| * |P_fp - P_native| (+ (1 - zf) * native spread: the native block/swing tech is random). Swing:
          poses sampled at swing progress 0.3/0.5/0.7.
  basis   self-check: shoulder line yaw in world axes constant within 20 deg over the steps (else a recorder/basis bug)
A check FAILs when more than 3% of a step's frames break it (head/vis/stretch/band) or any adjacent pair jumps.
Prints per-step lines, then one line: zoomfade <state> PASS|FAIL steps=.. <evidence>"""
import sys, math, statistics as stt

def V(s): return tuple(float(x) for x in s.split(','))
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def mul(a, k): return (a[0]*k, a[1]*k, a[2]*k)
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def ln(a): return math.sqrt(dot(a, a))
def nz(a):
    l = ln(a); return mul(a, 1/l) if l > 1e-6 else a

def parse(path):
    F = []
    for line in open(path):
        if line.startswith('#') or '|' not in line: continue
        pa = line.split('|'); h = pa[0].split()
        try:
            v = [V(x) for x in pa[1].split()]
            r = dict(t=float(h[1]), st=h[3], cls=int(h[5]), w=float(h[7]), sw=int(h[8]), prog=float(h[10]), zoom=float(h[16]),
                     mp=v[4], mf=v[5], j=v[7:13], cam=[V(x) for x in pa[2].split()])
            x3 = pa[3].split(); r['wih'] = int(x3[4]); r['stretch'] = float(x3[5])
            x4 = pa[4].split(); r['wb'] = float(x4[0]); r['zf'] = float(x4[3]); r['hd'] = V(x4[4]); r['nk'] = V(x4[5]); r['sp'] = V(x4[6])
            r['band'] = 0
            for g in pa[5:]:
                g = g.split()
                if g and g[0] == 'H' and len(g) >= 5: r['band'] = int(g[4])
        except (IndexError, ValueError):
            continue
        if len(r['j']) == 6: F.append(r)
    return F

BL = {0: 8.0, 1: 5.85}
def world(r, c):   # camera numbers -> world axes (no origin: callers use differences)
    e, rt, up, fw = r['cam']; return add(add(mul(rt, c[0]), mul(up, c[1])), mul(fw, c[2]))
def pose(r):       # joints + grip + tip relative to the spine, world axes
    pts = list(r['j']) + [r['mp'], add(r['mp'], mul(r['mf'], BL.get(r['cls'], 8.0)))]
    return [world(r, sub(p, r['sp'])) for p in pts]
def medpose(fr):
    P = [pose(r) for r in fr]
    return [tuple(stt.median(p[k][i] for p in P) for i in range(3)) for k in range(len(P[0]))]
def lens(r):
    J = r['j']; return [ln(sub(J[0], J[1])), ln(sub(J[1], J[2])), ln(sub(J[3], J[4])), ln(sub(J[4], J[5]))]   # L upper/fore, R upper/fore
def prj(P, C):
    q = sub(P, C); return (q[0]/q[2], q[1]/q[2], q[2]) if q[2] > 0.1 else None

def main():
    a = sys.argv[1:]
    if len(a) < 3: print(__doc__); sys.exit(2)
    rec, state, steps = a[0], a[1], [float(x) for x in a[2].replace(',', ' ').split()]
    bandhide = int(a[a.index('--bandhide')+1]) if '--bandhide' in a else 1
    import os
    E = lambda k, d: float(os.environ.get(k, d))
    HDM, EYE, HS, ZF0, ZF1 = E('HD_MIN', 2.0), E('EYE_LIMIT', 0.65), E('HEAD_SHOW', 16.0), E('ZF0', 2.0), E('ZF1', 8.0)
    JMIN, JK, FR, ST_TOL = E('J_MIN', 0.8), E('J_K', 2.0), E('BAD_FRAC', 0.03), E('ST_TOL', 0.08)
    F = [r for p in rec.split(",") if p for r in parse(p)]
    if not F: print('zoomfade %s FAIL no frames in %s' % (state, rec)); return 1
    def instate(r):
        if state == 'ready': return r['st'] == 'ready' and not r['sw']
        if state == 'block': return r['st'] == 'blocking'
        return bool(r['sw']) or r['st'] == 'swinging'
    S = []   # (d, frames)
    for d in steps:
        fr = [r for r in F if abs(r['zoom']-d) <= 0.05 and instate(r) and r['wih'] and r['cls'] == 0]
        S.append((d, fr))
    miss = [d for d, fr in S if len(fr) < 3]
    S = [(d, fr) for d, fr in S if len(fr) >= 3]
    if len(S) < 0.8*len(steps) or not S:
        print('zoomfade %s FAIL steps=%d/%d missing=%s (fewer than 3 %s frames at those distances)' % (state, len(S), len(steps), ','.join('%g' % d for d in miss[:12]), state))
        return 1
    far = S[-1][1]; near = S[0][1]
    L0 = [stt.median(x) for x in zip(*[lens(r) for r in far])]
    def ratios(r): return [l/max(b, 1e-3) for l, b in zip(lens(r), L0)]
    r0 = [stt.median(x) for x in zip(*[ratios(r) for r in near])]   # zoom-0 FP ratio per segment (accepted FP stretch)
    RLO = [min(1.0, x)*(1-ST_TOL) for x in r0]; RHI = [max(1.0, x)*(1+ST_TOL) for x in r0]
    STM = max(1.05, 1.05*max(r['stretch'] for r in near))
    vis_f = lambda r: not (bandhide and r['band'])
    bad = {}; out = []; vstep = []
    def flag(k, d): bad.setdefault(k, []).append('%g' % d)
    yaws = []
    for d, fr in S:
        n = len(fr); c = dict(band=0, head=0, vis=0, stretch=0)
        hmin, npmin, rmin, rmax, zfs, bh = 99.0, 99, 9.0, 0.0, [], 0
        for r in fr:
            zfs.append(r['zf']); bh += r['band']
            if bandhide and ((EYE <= r['zoom'] < HS) != bool(r['band'])): c['band'] += 1
            if not vis_f(r): continue
            if r['zoom'] >= EYE:
                hc = add(r['hd'], mul(nz(sub(r['hd'], r['nk'])), 0.9)); hd = min(ln(sub(r['j'][5], hc)), ln(sub(r['mp'], hc)))
                hmin = min(hmin, hd); c['head'] += hd < HDM
            C = (0, 0, -r['zoom']); npt = 0
            for k in range(21):
                s_ = prj(add(r['mp'], mul(r['mf'], BL.get(r['cls'], 8.0)*k/20)), C)
                npt += bool(s_ and abs(s_[0]) < 1.245 and abs(s_[1]) < 0.70)
            npmin = min(npmin, npt); c['vis'] += npt < 5
            rr = ratios(r); rmin, rmax = min(rmin, min(rr)), max(rmax, max(rr))
            c['stretch'] += any(x < lo or x > hi for x, lo, hi in zip(rr, RLO, RHI)) or r['stretch'] > STM
        zf = stt.median(zfs); visible = sum(vis_f(r) for r in fr) > n/2
        for k, v in c.items():
            if v > FR*n: flag(k, d)
        sh = world(fr[0], sub(fr[0]['j'][3], fr[0]['j'][0])); yaws.append(math.degrees(math.atan2(sh[0], sh[2])))
        if state == 'swing':
            P = []
            for u in (0.3, 0.5, 0.7):
                best = min(fr, key=lambda r: abs(r['prog']-u)); P += pose(best)
        else:
            P = medpose(fr)
        vstep.append((d, zf, visible, P))
        out.append('step d=%5.2f n=%3d zf=%.2f band=%d/%d head_min=%s pts_min=%s len_ratio=%.2f..%.2f%s' % (
            d, n, zf, bh, n, ('%.2f' % hmin) if hmin < 99 else '-', npmin if npmin < 99 else '-', rmin if rmin < 9 else 0, rmax,
            ''.join(' %s:%d' % (k, v) for k, v in c.items() if v)))
    # jump between adjacent visible steps
    fp_ = [p for d, zf, v, p in vstep if zf > 0.95]; na_ = [p for d, zf, v, p in vstep if zf < 0.05]
    nsp = 0.0
    if len(na_) >= 2:
        nsp = max(ln(sub(a_[k], b_[k])) for a_ in na_ for b_ in na_ for k in range(len(a_)))
    jmax, jw = 0.0, ''
    for (d1, z1, v1, p1), (d2, z2, v2, p2) in zip(vstep, vstep[1:]):
        if not (v1 and v2): continue
        for k in range(len(p1)):
            dif = ln(sub(p1[k], p2[k]))
            fn = ln(sub(fp_[0][k], na_[-1][k])) if fp_ and na_ else 0.0
            lim = JMIN + JK*(abs(z1-z2)*fn + (1-min(z1, z2))*nsp)
            if dif > lim:
                flag('jump', d2); jw = jw or '%g->%g joint%d %.2f>%.2f' % (d1, d2, k, dif, lim)
            jmax = max(jmax, dif)
    ysp = max(yaws) - min(yaws) if yaws else 0
    if ysp > 180: ysp = 360 - ysp
    if ysp > 20: flag('basis', 0)
    for l in out: print(l)
    ok = not bad
    nvis = sum(1 for x in vstep if x[2])
    print('zoomfade %s %s steps=%d/%d visible=%d bandhide=%d jump_max=%.2f%s native_spread=%.2f len_lim=%s st_lim=%.2f yaw_spread=%.0f bad=%s' % (
        state, 'PASS' if ok else 'FAIL', len(S), len(steps), nvis, bandhide, jmax, (' (' + jw + ')') if jw else '', nsp, ','.join('%.2f..%.2f' % x for x in zip(RLO, RHI)), STM, ysp,
        ';'.join('%s@%s' % (k, ','.join(v[:6])) for k, v in sorted(bad.items())) or 'none'))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
