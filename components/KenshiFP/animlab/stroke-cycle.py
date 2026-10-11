#!/usr/bin/env python3
"""stroke-cycle.py -- E6 default stroke cycle per weapon class (gate step 3b; Misses 2026-10-11 "E6 default stroke cycle":
6E7C0363 played only stroke 0 on the katana although the shipped mask was 0xF, because kfp-e6-default-mask v1 kept every
2H weapon on stroke 0 and kfp-2h-light made katanas 2H light; the gate pooled strokes FORCED only).

The replay adapter of the candidate source replays a corpus sword recording with native swings UNFORCED (`--no-rec-sets`:
no recorded stroke force / mask, so the source's compiled default mask and its stroke pick run) once per weapon class
(`--set wcat/wpom/wtip` = the class's skill category and mesh dims, so g_vm_2h / g_vm_2hl come out as in the game), reads
the picked stroke of every swing from the adapter's `[vm] swing #k stroke s (mask ..)` log and compares the picked set
with the class's expected set: `mask` = every stroke of the source's default mask (g_vm_strokes in kfp_viewmodel.inc),
or an explicit list (heavy/polearm keep stroke 0 by design). A class that never reaches its shipped strokes FAILs.
Usage: stroke-cycle.py --adapter <kfpvm build> --src <client dir> [--table <tsv>] [--rec <rec>] [--name <tag>]
  table (default corpus pools/stroke-cycle/classes.tsv): `class wcat wpom wtip expect [rec]` (# comments)
Prints `CYCLE <class> PASS|FAIL picked=[..] want=[..] mask=0x..` per class + `RESULT STROKE-CYCLE PASS|FAIL ...`; exit 1 on FAIL.
Replays go through labcache (same adapter + rec + args = cache hit)."""
import argparse, os, re, sys, tempfile, shutil
L = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
sys.path.insert(0, L)
import labcache  # noqa: E402

C = os.environ.get('ANIMLAB_CORPUS', '/mnt/c/KenshiTestRuns/corpus')
ap = argparse.ArgumentParser()
ap.add_argument('--adapter', required=True); ap.add_argument('--src', required=True)
ap.add_argument('--table', default=os.path.join(C, 'pools/stroke-cycle/classes.tsv'))
ap.add_argument('--rec'); ap.add_argument('--name', default='')
a = ap.parse_args()
inc = open(os.path.join(a.src, 'kfp_viewmodel.inc')).read()
m = re.search(r'static int g_vm_strokes = (0x[0-9a-fA-F]+|\d+)', inc)
mask = int(m.group(1), 0) if m else 1
mstrokes = [n for n in range(8) if (mask >> n) & 1]
tdir = os.path.dirname(os.path.abspath(a.table))
rows = [l.split() for l in open(a.table) if l.strip() and not l.lstrip().startswith('#')]
tmp = tempfile.mkdtemp(prefix='animlab-cycle-')
bad = []
try:
    for r in rows:
        cls, wcat, wpom, wtip, exp = r[:5]
        rec = a.rec or os.path.join(tdir, r[5] if len(r) > 5 else 'cycle.txt')
        want = sorted(set(mstrokes if exp == 'mask' else [int(x) for x in exp.split(',')]))
        args = ['--no-rec-sets', '--set', 'wcat=' + wcat, '--set', 'wpom=' + wpom, '--set', 'wtip=' + wtip]
        rc, so, se = labcache.replay([a.adapter], rec, os.path.join(tmp, cls + '.txt'), args)
        picked = [int(x) for x in re.findall(r'\[vm\] swing #\d+ stroke (-?\d+) \(mask', se)]
        if rc != 0:
            ok, why = False, ' adapter rc=%d' % rc
        elif len(picked) < len(want):
            ok, why = False, ' only %d swings < %d' % (len(picked), len(want))
        else:
            ok, why = sorted(set(picked)) == want, ''
        print('CYCLE %s %s picked=[%s] want=[%s] mask=0x%x wcat=%s%s' % (cls, 'PASS' if ok else 'FAIL', ','.join(map(str, picked)),
              ','.join(map(str, want)), mask, wcat, why))
        if not ok:
            bad.append(cls)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
print('RESULT STROKE-CYCLE %s%s classes=%d fail=%s mask=0x%x adapter=%s' % ('PASS' if not bad and rows else 'FAIL',
      ' ' + a.name if a.name else '', len(rows), ','.join(bad) or 'none', mask, a.adapter))
sys.exit(0 if not bad and rows else 1)
