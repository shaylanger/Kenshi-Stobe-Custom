#!/usr/bin/env python3
"""Detached black-bar detector (FP fists 'black line' artifact).
usage: detect_bar.py <video> [y_hud=610] [AR=0.06]
Works at half resolution (640x360). Per frame:
  dark  = luma < 40 (glove/skin-underlayer black) in rows 92..y_hud (above the HUD panel)
  armor = luma > 110 and chroma (max-min RGB) < 30 (grey/white arm plates; sand is orange, high chroma)
8-connected dark components with area >= 150 half-res px (~600 full-res) are scored by
  armor_ring = fraction of the 3-px ring around the component that is armor.
A real glove hand always joins its armor sleeve (armor_ring >= ~0.10); a component with
armor_ring < AR (argv3, default 0.06) is a black mesh with no sleeve = FLAG. Prints FLAG lines in full-res coordinates."""
import sys, subprocess, numpy as np

def label(m):
    ys, xs = np.nonzero(m)
    if len(ys) == 0: return []
    H, W = m.shape
    idx = -np.ones(m.shape, np.int64); idx[ys, xs] = np.arange(len(ys))
    par = np.arange(len(ys))
    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]; a = par[a]
        return a
    for dy, dx in ((0, 1), (1, -1), (1, 0), (1, 1)):
        yy = ys + dy; xx = xs + dx
        ok = (yy < H) & (xx >= 0) & (xx < W)
        a = np.nonzero(ok)[0]; nb = idx[yy[ok], xx[ok]]; sel = nb >= 0
        for i, j in zip(a[sel], nb[sel]):
            ri, rj = find(i), find(j)
            if ri != rj: par[ri] = rj
    roots = np.array([find(i) for i in range(len(ys))])
    return [(ys[roots == r], xs[roots == r]) for r in np.unique(roots)]

def dilate(m, r):
    o = m.copy()
    for _ in range(r):
        n = o.copy()
        n[1:] |= o[:-1]; n[:-1] |= o[1:]; n[:, 1:] |= o[:, :-1]; n[:, :-1] |= o[:, 1:]
        o = n
    return o

v = sys.argv[1]; yh = int(sys.argv[2]) if len(sys.argv) > 2 else 610
ATT = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
import os; DEBUG = os.environ.get("BAR_DEBUG") == "1"
W, H = 640, 360; y0, y1 = 46, yh // 2
p = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-i', v, '-vf', 'scale=640:360', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
# pass 1: static dark mask (HUD widgets, banner) = dark in >=85% of frames sampled every 10th frame
q = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-i', v, '-vf', 'select=not(mod(n\,10)),scale=640:360', '-vsync', '0', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
acc = None; cnt = 0
while True:
    b = q.stdout.read(W * H * 3)
    if len(b) < W * H * 3: break
    f = np.frombuffer(b, np.uint8).reshape(H, W, 3)[y0:y1].astype(np.int16)
    d = ((f[..., 0] * 3 + f[..., 1] * 6 + f[..., 2]) // 10) < 40
    acc = d.astype(np.int32) if acc is None else acc + d; cnt += 1
static = dilate(acc >= 0.85 * cnt, 2)
n = 0
while True:
    b = p.stdout.read(W * H * 3)
    if len(b) < W * H * 3: break
    f = np.frombuffer(b, np.uint8).reshape(H, W, 3)[y0:y1].astype(np.int16)
    lum = (f[..., 0] * 3 + f[..., 1] * 6 + f[..., 2]) // 10
    chroma = f.max(2) - f.min(2)
    dark = (lum < 40) & ~static
    armor = (lum > 110) & (chroma < 30)
    attach = (lum >= 40) & ~((chroma >= 45) & (lum >= 90))   # non-dark, non-sand: sleeve armor, leather, cloth
    for ys, xs in label(dark):
        if len(ys) < 150: continue
        cm = np.zeros(dark.shape, bool); cm[ys, xs] = True
        ring = dilate(cm, 3) & ~cm
        ar = armor[ring].mean() if ring.any() else 0
        att = attach[ring].mean() if ring.any() else 0
        side = static[ring].mean() if ring.any() else 0
        touch = ys.max() >= dark.shape[0] - 2
        h = (ys.max() - ys.min() + 1) * 2
        bar = touch and side < 0.12 and att < ATT and 1500 <= len(ys) * 4 <= 8000 and h <= 130
        if bar or (DEBUG and touch):
            print(f"FLAG frame {n} t={n/30:.3f} bbox x{xs.min()*2}-{xs.max()*2} y{(ys.min()+y0)*2}-{(ys.max()+y0)*2} area_full {len(ys)*4} armor_ring {ar:.3f} attach {att:.3f} side_hud {side:.3f} touch_hud {int(touch)} BAR {int(bar)}", flush=True)
    n += 1
