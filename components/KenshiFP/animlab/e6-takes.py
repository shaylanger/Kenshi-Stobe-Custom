#!/usr/bin/env python3
"""e6-takes.py -- the corpus E6 GAME takes replayed with the CANDIDATE source, judged per take and per stroke exactly like
the take judge (fp-e6-strokes.sh: `animlab.py --only-stroke s inline|metrics(arc)`), gate step 3c.
Why (Misses 2026-10-11 "E6-s1pt30-s1", "E6 stroke 3 wind-up inline"): the gate pool predicts a take pass RATE over native
variants (aggregate >= 0.95 over 820 two-swing takes); 13334FFF passed the pool while its replay of the game take s1pt30
failed stroke-1 arc wb 53.2 > 50, and the pool had no inline check. Here every corpus E6 take is replayed with its own
`# set` lines (own strokes, own table values) and every stroke it plays gets its own verdict.
Usage: e6-takes.py --adapter <kfpvm build> [--list <file>] [--args "<adapter args>"] [--name tag] [-j N]
  list (default corpus pools/e6-takes/takes.list): `<rec relative to the list> [adapter args]` (# comments)
Prints `E6TAKE <rec> s<n> inline|arc PASS|FAIL <evidence>` per take x stroke x check, `RESULT E6-TAKES PASS|FAIL n=.. fail=..`
(exit 1 on any FAIL; the gate judges the verdict lines against its baseline). Replays + checks go through labcache."""
import argparse, os, re, shlex, subprocess, sys, tempfile, shutil
from concurrent.futures import ThreadPoolExecutor
L = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
sys.path.insert(0, L)
import labcache  # noqa: E402

C = os.environ.get('ANIMLAB_CORPUS', '/mnt/c/KenshiTestRuns/corpus')
ap = argparse.ArgumentParser()
ap.add_argument('--adapter', required=True); ap.add_argument('--list', default=os.path.join(C, 'pools/e6-takes/takes.list'))
ap.add_argument('--args', default=''); ap.add_argument('--name', default='')
ap.add_argument('-j', type=int, default=int(os.environ.get('LABNICE_J') or min(8, os.cpu_count() or 4)))
a = ap.parse_args()
base = os.path.dirname(os.path.abspath(a.list))
jobs = []
for l in open(a.list):
    if not l.strip() or l.lstrip().startswith('#'):
        continue
    t = shlex.split(l)
    jobs.append((t[0] if os.path.isabs(t[0]) else os.path.join(base, t[0]), t[1:]))
tmp = tempfile.mkdtemp(prefix='animlab-e6takes-')


def strokes_of(rec):
    """scripted strokes the replay played: the per-record `stroke` field (recfmt) of swinging records."""
    import recfmt
    R = recfmt.parse(rec)
    return sorted({f.get('stroke') for f in R.frames if f.get('stroke') is not None and f.get('stroke') >= 0
                   and str(f.get('st', '')).startswith('swing')})


def check(out, s, c):
    r = subprocess.run([sys.executable, os.path.join(L, 'animlab.py'), '--only-stroke', str(s), c, out],
                       capture_output=True, text=True)
    k = 'arc' if c == 'metrics' else c
    line = next((x for x in r.stdout.splitlines() if x.startswith(k + ' ')), '%s FAIL no verdict (rc %d) %s' % (k, r.returncode, r.stderr[-200:].strip()))
    return k, line


def one(job):
    rec, xa = job
    name = os.path.splitext(os.path.basename(rec))[0]
    if not os.path.exists(rec):
        return name, [('-', 'rec', 'FAIL recording missing ' + rec)]
    out = os.path.join(tmp, name + '.txt')
    rc, so, se = labcache.replay([a.adapter], rec, out, shlex.split(a.args) + xa)
    if rc != 0 or not os.path.exists(out):
        return name, [('-', 'replay', 'FAIL adapter rc=%d %s' % (rc, se[-200:].strip()))]
    res = []
    for s in strokes_of(out):
        for c in ('inline', 'metrics'):
            k, line = check(out, s, c)
            res.append((s, k, line[len(k) + 1:]))
    return name, res


try:
    with ThreadPoolExecutor(max_workers=a.j) as ex:
        R = list(ex.map(one, jobs))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
n = nf = 0
for name, res in R:
    for s, k, v in res:
        n += 1; ok = v.startswith('PASS')
        nf += 0 if ok else 1
        print('E6TAKE %s s%s %s %s' % (name, s, k, v[:220]))
print('RESULT E6-TAKES %s%s n=%d fail=%d takes=%d adapter=%s%s' % ('PASS' if n and not nf else 'FAIL', ' ' + a.name if a.name else '',
      n, nf, len(jobs), a.adapter, ' args=' + a.args if a.args else ''))
sys.exit(0 if n and not nf else 1)
