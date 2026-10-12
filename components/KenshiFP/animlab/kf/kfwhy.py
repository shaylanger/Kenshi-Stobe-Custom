#!/usr/bin/env python3
"""kfwhy.py <replayed rec> [stroke]: the check texts of each full swing of one replayed recording (kfcheck --keep dir),
plus the per-u weapon/arm trace of the first swing (u, tip px, grip cam, wb, blade on-screen length) to see WHY a
keyframe candidate fails (keyframe-player 2026-10-11)."""
import sys, os, math
sys.path.insert(0, '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab')
import recfmt, metrics as M
rec = sys.argv[1]; stroke = int(sys.argv[2]) if len(sys.argv) > 2 else None
M.STROKE_ONLY = stroke
r = recfmt.parse(rec); P = M.frame_metrics(r)
for v in M.swing_verdicts(r.frames, P, (2,), inline=True):
    if not v['full'] or (stroke is not None and v['stroke'] not in (None, -1, stroke)):
        continue
    print('swing k=%s ok=%s' % (v['k'], {k: x for k, x in v['ok'].items()}))
    for key in ('btxt', 'stxt', 'itxt', 'ptxt'):
        print('  %s %s' % (key, ' '.join(v.get(key, []))[:600]))
    print('  ctxt %s' % str(v.get('ctxt'))[:400])
    print('  wb_max %.1f arc %d/%d' % (v['wb_max'], v['arc_good'], v['arc_n']))
    break
