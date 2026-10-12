#!/usr/bin/env python3
"""zoomret-check.py <rec> --adapter <kfpvm_replay> [--set k=v]... [--row NAME]   (WSL; cleaver-fix 2026-10-11)

Class "carried solver state" (STATUS.md Misses, 139-wc-clv / REEL-Long_Cleaver): after the camera comes back from a
zoom-out (third person, zoom fade weight 0) the arm IK kept the zoomed-out elbow target and settled in a second ready
pose (elbow ~4 dm off, arm stretch 3.37 vs 2.08, blade rolled ~95 deg) until a swing. A pose must not depend on what the
camera did before: for every zoom return in the recording (zoom >= 8 -> < 1) the replay of the WHOLE recording is compared
with a replay that starts fresh at that frame (the recording cut there, same weapon sets). Judged on the first 30 zoom-0
ready frames at full weight from 15 frames after the return: forearm hinge axis (rec 'H' group) <= 20 deg apart and arm
stretch within 0.5. No zoom return in the recording = PASS (nothing to judge).
Prints one line per return and `RESULT <row> PASS|FAIL returns=<n> worst=<deg>/<stretch>`; exit 1 on FAIL."""
import argparse, math, os, subprocess, sys, tempfile


def load(p):
    R = {}
    for l in open(p):
        if l.startswith('#') or not l.strip():
            continue
        g = l.rstrip('\n').split('|'); h = g[0].split()
        try:
            n = int(h[0])
            H = next((x.split() for x in g if x.split()[:1] == ['H']), None)
            R[n] = dict(st=h[3], w=float(h[7]), zoom=float(h[16]), stch=float(g[3].split()[5]),
                        hf=[float(v) for v in H[2].split(',')] if H else None)
        except (ValueError, IndexError):
            continue
    return R


def cut(src, dst, k):
    with open(dst, 'w') as o:
        for l in open(src):
            if l.startswith('# set '):
                p = l.split(); f = int(p[2])
                o.write('# set %d %s\n' % (-1 if f < k else f - k, ' '.join(p[3:]))); continue
            if l.startswith('#') or not l.strip():
                o.write(l); continue
            h = l.split(' ', 1)
            try:
                n = int(h[0])
            except ValueError:
                o.write(l); continue
            if n >= k:
                o.write('%d %s' % (n - k, h[1]))


def ang(u, v):
    d = sum(x * y for x, y in zip(u, v)) / (math.hypot(*u) * math.hypot(*v) + 1e-9)
    return math.degrees(math.acos(max(-1.0, min(1.0, d))))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('rec'); ap.add_argument('--adapter', required=True)
    ap.add_argument('--set', action='append', default=[]); ap.add_argument('--row', default='ZOOMRET')
    ap.add_argument('--keep')
    a = ap.parse_args()
    G = load(a.rec)
    fr = sorted(G)
    rets = [n for i, n in enumerate(fr[1:], 1) if G[n]['zoom'] < 1 and G[fr[i - 1]]['zoom'] >= 8]
    if not rets:
        print('RESULT %s PASS returns=0 (no zoom return in the recording)' % a.row); return 0
    d = a.keep or tempfile.mkdtemp(prefix='zoomret-')
    sets = sum((['--set', s] for s in a.set), [])
    full = os.path.join(d, 'full.txt')
    subprocess.run([a.adapter, a.rec, full] + sets, check=True, capture_output=True)
    F = load(full)
    worst, bad = (0.0, 0.0), 0
    for k in rets:
        c, o = os.path.join(d, 'cut%d.rec' % k), os.path.join(d, 'cut%d.txt' % k)
        cut(a.rec, c, k)
        subprocess.run([a.adapter, c, o] + sets, check=True, capture_output=True)
        C = load(o)
        fs = [n for n in sorted(F) if n >= k + 15 and F[n]['st'] == 'ready' and F[n]['w'] >= 0.999 and F[n]['zoom'] < 1
              and F[n]['hf'] and (n - k) in C and C[n - k]['hf']][:30]
        if not fs:
            print('ZOOMRET return@%d: no ready frames after it (not judged)' % k); continue
        da = max(ang(F[n]['hf'], C[n - k]['hf']) for n in fs)
        ds = max(abs(F[n]['stch'] - C[n - k]['stch']) for n in fs)
        ok = da <= 20 and ds <= 0.5
        bad += not ok; worst = max(worst, (da, ds))
        print('ZOOMRET return@%d %s hinge=%.1fdeg stretch=%.2f/%.2f (carried/fresh) frames=%d'
              % (k, 'ok' if ok else 'BAD', da, F[fs[0]]['stch'], C[fs[0] - k]['stch'], len(fs)))
    print('RESULT %s %s returns=%d bad=%d worst=%.1fdeg/%.2f' % (a.row, 'FAIL' if bad else 'PASS', len(rets), bad, *worst))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
