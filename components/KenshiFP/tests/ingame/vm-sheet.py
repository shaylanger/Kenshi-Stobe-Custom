#!/usr/bin/env python3
"""vm-sheet.py <out.jpg> <manifest.tsv> [--cols N] [--width W] [--split DIR]
Labelled contact sheet from a manifest (one shot per line: row<TAB>label<TAB>png path). Rows keep their first-seen
order; each row wraps after --cols tiles (default: the longest row). --split DIR also writes one sheet per row as
DIR/final-<weapon>-zoom<z>.jpg (row "sword zoom 25" -> final-sword-zoom25.jpg; full-size frames, 3 per line, VMQ_TILE=
width). Missing shots become grey tiles."""
import sys, os, re

def wp(path):   # Windows python under Git Bash (4080 rig): /c/... -> c:/...
    return re.sub(r'^/([a-zA-Z])/', r':/', path) if os.name == 'nt' else path
from PIL import Image, ImageDraw, ImageFont

def font(sz):
    for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 'C:/Windows/Fonts/arialbd.ttf'):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def sheet(out, rows, cols, tw):
    th = None; tiles = {}
    for r, items in rows:
        for lab, path in items:
            try: im = Image.open(wp(path)).convert('RGB')
            except Exception: im = None
            if im is not None and th is None: th = int(tw * im.height / im.width)
            tiles[(r, lab, path)] = im
    th = th or int(tw * 9 / 16); lh = 30; rh = 34; f1, f2 = font(22), font(26)
    lines = []
    for r, items in rows:
        lines.append(('row', r, None))
        for k in range(0, len(items), cols): lines.append(('tiles', r, items[k:k + cols]))
    H = sum(rh if t == 'row' else th + lh for t, _, _ in lines); W = cols * tw
    S = Image.new('RGB', (W, H), (20, 20, 20)); d = ImageDraw.Draw(S); y = 0
    for t, r, items in lines:
        if t == 'row':
            d.rectangle([0, y, W, y + rh], fill=(60, 60, 90)); d.text((8, y + 3), r, fill=(255, 255, 255), font=f2); y += rh; continue
        for c, (lab, path) in enumerate(items):
            im = tiles[(r, lab, path)]; x = c * tw
            if im is None: d.rectangle([x, y, x + tw - 2, y + th], fill=(90, 90, 90))
            else: S.paste(im.resize((tw - 2, th)), (x, y))
            d.text((x + 6, y + th + 3), lab, fill=(255, 230, 120), font=f1)
        y += th + lh
    S.save(out, quality=90)

def main():
    a = sys.argv[1:]; out, man = wp(a[0]), wp(a[1]); cols = None; tw = 560; split = None
    if '--cols' in a: cols = int(a[a.index('--cols') + 1])
    if '--width' in a: tw = int(a[a.index('--width') + 1])
    if '--split' in a: split = wp(a[a.index('--split') + 1])
    rows = []
    for line in open(man, encoding='utf-8'):
        p = line.rstrip('\n').split('\t')
        if len(p) < 3: continue
        for r, items in rows:
            if r == p[0]: items.append((p[1], p[2])); break
        else: rows.append((p[0], [(p[1], p[2])]))
    if not rows: sys.exit('empty manifest')
    n = cols or max(len(i) for _, i in rows)
    sheet(out, rows, n, tw)
    if split:
        for r, items in rows:
            w = r.split()
            name = 'final-%s-zoom%s.jpg' % (w[0], w[-1]) if len(w) >= 3 and w[1] == 'zoom' else r.replace(' ', '-') + '.jpg'
            # full-resolution frames (Shay 2026-10-09: sheets must be judgeable), 3 per line
            sheet(os.path.join(split, name), [(r, items)], min(3, len(items)), int(os.environ.get('VMQ_TILE', '1602')))
    print(out)

main()
