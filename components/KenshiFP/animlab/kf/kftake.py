#!/usr/bin/env python3
"""kftake.py: the GAME TAKE judge of fp-e6-strokes.sh run on lab replays of corpus E6 game takes (kf-lab 2026-10-11).

  kftake.py --stroke N [--tables F] [--set k=v].. [--adapter BIN] [--list F] [--rec R].. [-j 8] [--keep DIR]

Why (STATUS.md Misses 2026-10-11 "kf-s0b"): keyframe set kf-s0-k5sl passed kfcheck (sword-swing pool, score 1.53) and
failed its game take (wrist 82.7/50, path late .071 ctr .148). The pool replays run with --no-rec-sets and the pool
recordings carry no weapon geometry, so the lab judged the stroke on the adapter's default blade; every E6 game take
records the shipped sword (`# set -1 wcat 0 / wpom 2.00747 / wtip 10.2554`), and keyframes are keyed in hilt + tip
space, so the blade length decides the wrist. Here each game take recording is replayed with
  --no-rec-sets  + the recording's CONDITION sets (weapon wcat/wpom/wtip, rlamp, sw_pose, ...; every `# set` key except
                   the variant keys stroke/strokes/kfmask/slmask/t.*), in recorded order, --set-at for per-frame ones
                 + --set stroke=N (every swing of the take plays stroke N) + the variant (--tables F, --set k=v)
and judged with EXACTLY the take judge's lab commands (fp-e6-strokes.sh lines "for c in inline metrics churn blade",
`animlab.py path`, `animlab.py stroke --overhead 2`), with the same gating: every line must PASS except the documented
stroke-0 blade baseline exception (reported, not gating). Any recording failing = FAIL (a take fails on one bad swing).
List (default corpus pools/sword-take/take.list): `<rec relative to the list>` per line, # comments.
Prints `KFTAKE <rec> <check> PASS|FAIL <evidence>` per gating line and `RESULT KFTAKE-s<N> PASS|FAIL n=.. fail=.. worst=..`.
Replays go through labcache. Used by kfcheck.py (gate on top of the pool score) and kfpreview.py --pool."""
import sys, os, re, shlex, subprocess, tempfile, shutil, argparse
from concurrent.futures import ThreadPoolExecutor
L = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab'
sys.path.insert(0, L)
import labcache  # noqa: E402

C = os.environ.get('ANIMLAB_CORPUS', '/mnt/c/KenshiTestRuns/corpus')
LIST = os.path.join(C, 'pools/sword-take/take.list')
ADAPTER = '/root/animlab-build/kfpvm_kf'
VARIANT = re.compile(r'^(stroke|strokes|kfmask|slmask|t\..*)$')


def take_recs(lst=LIST):
    base = os.path.dirname(os.path.abspath(lst))
    out = []
    for l in open(lst):
        if l.strip() and not l.lstrip().startswith('#'):
            p = shlex.split(l)[0]
            out.append(p if os.path.isabs(p) else os.path.normpath(os.path.join(base, p)))
    return out


def cond_args(rec, drop=()):
    """the recording's condition sets (not the variant keys), in recorded order -> adapter args"""
    args = []
    for l in open(rec, errors='replace'):
        if not l.startswith('#'):
            if l.strip():
                break   # sets are in the header block; frames follow
            continue
        t = l.split()
        if len(t) >= 5 and t[1] == 'set':
            f, k, v = t[2], t[3], t[4]
            if VARIANT.match(k) or k in drop:
                continue
            args += ['--set', '%s=%s' % (k, v)] if int(f) < 0 else ['--set-at', '%s:%s=%s' % (f, k, v)]
    return args


def replay(adapter, rec, out, stroke, tables, sets):
    drop = set()
    for _ in range(8):   # a key this adapter does not know (e.g. fn_r0 of older builds) is dropped, like rec-set mode does
        args = ['--no-rec-sets'] + cond_args(rec, drop) + ['--set', 'stroke=%d' % stroke]
        if tables:
            args += ['--tables', tables]
        for kv in sets:
            args += ['--set', kv]
        rc, so, se = labcache.replay([adapter], rec, out, args)
        if rc == 0 and os.path.exists(out):
            return out, drop
        m = re.search(r'set ([\w.]+)=\S* failed', (se or '') + (so or ''))
        if not m or m.group(1) in drop or m.group(1) == 'stroke' or any(m.group(1) == kv.split('=')[0] for kv in sets):
            raise RuntimeError('adapter rc=%d on %s: %s' % (rc, os.path.basename(rec), ((se or so or '')[-300:]).strip()))
        drop.add(m.group(1))
    raise RuntimeError('adapter keeps failing on %s' % rec)


def _cl(argv, _unused=None):
    r = subprocess.run([sys.executable, os.path.join(L, 'animlab.py')] + argv, capture_output=True, text=True)
    return r.stdout.splitlines(), r


def judge(out, stroke):
    """the take judge of fp-e6-strokes.sh on one replay -> [(check, gating, line)]"""
    res = []
    for c in ('inline', 'metrics', 'churn', 'blade'):
        x = ['--stroke'] if c == 'churn' else []
        lines, r = _cl(['--only-stroke', str(stroke), c] + x + [out], None)
        line = next((y for y in lines if re.match(r'^(inline|arc|churn|blade) ', y)), None)
        if line is None:
            line = '%s FAIL no verdict (rc %d) %s' % (c, r.returncode, r.stderr[-160:].strip())
        k = line.split()[0]
        gate = not (stroke == 0 and k == 'blade')   # take judge: stroke 0 blade snap/seen = documented baseline exception
        res.append((k, gate, line))
    lines, r = _cl(['path', out], None)
    pr = [y for y in lines if y.startswith('path ')]
    res.append(('path', True, pr[-1] if pr else 'path FAIL no verdict'))
    for y in lines:
        if y.startswith('pathsw ') and ' PASS ' not in y:
            res.append(('pathsw', False, y))   # detail of the path line (the take prints them too)
    lines, r = _cl(['stroke', '--overhead', '2', out], None)
    sk = next((y for y in lines if y.startswith('stroke ')), 'stroke FAIL no verdict')
    res.append(('stroke', True, sk))
    return res


def num(pat, s):
    m = re.search(pat, s)
    return float(m.group(1)) if m else None


def evaluate(adapter=ADAPTER, stroke=0, tables=None, sets=(), recs=None, j=8, keep=None):
    """-> dict(ok, n, fail, lines, worst, txt). ok = every gating line of every recording PASS."""
    recs = recs or take_recs()
    d = keep or tempfile.mkdtemp(prefix='kftake-', dir='/tmp')
    os.makedirs(d, exist_ok=True)

    def one(rec):
        name = os.path.splitext(os.path.basename(rec))[0]
        try:
            out, drop = replay(adapter, rec, os.path.join(d, name + '.txt'), stroke, tables, list(sets))
        except Exception as e:
            return name, [('replay', True, 'replay FAIL %s' % e)]
        return name, judge(out, stroke)
    try:
        with ThreadPoolExecutor(max_workers=j) as ex:
            R = list(ex.map(one, recs))
    finally:
        if not keep:
            shutil.rmtree(d, ignore_errors=True)
    lines, nf, n = [], 0, 0
    wb, late, ctr = [], [], []
    for name, res in R:
        for k, gate, line in res:
            ok = bool(re.match(r'^\w+ PASS', line))
            if gate:
                n += 1; nf += 0 if ok else 1
            lines.append('KFTAKE %s %s%s %s' % (name, k, '' if gate else '(info)', line[len(k) + 1:][:240]))
            if k == 'arc':
                v = num(r'wb_max=([\d.]+)', line); wb += [v] if v is not None else []
            if k == 'path':
                v = num(r'(?:late|hook)=([\d.]+)', line); late += [v] if v is not None else []
                v = num(r'ctr=([\d.]+)', line); ctr += [v] if v is not None else []
    worst = 'wb=%s late=%s ctr=%s' % tuple('%.3g' % max(x) if x else '-' for x in (wb, late, ctr))
    ok = n > 0 and nf == 0
    return dict(ok=ok, n=n, fail=nf, takes=len(recs), lines=lines, worst=worst,
                txt='take=%s n=%d fail=%d takes=%d worst %s' % ('PASS' if ok else 'FAIL', n, nf, len(recs), worst))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--stroke', type=int, required=True)
    ap.add_argument('--tables')
    ap.add_argument('--set', action='append', default=[])
    ap.add_argument('--adapter', default=ADAPTER)
    ap.add_argument('--list', default=LIST)
    ap.add_argument('--rec', action='append', default=[])
    ap.add_argument('-j', type=int, default=int(os.environ.get('LABNICE_J') or 8))
    ap.add_argument('--keep')
    ap.add_argument('--tag', default='')
    ap.add_argument('-q', action='store_true', help='only failing lines + RESULT')
    a = ap.parse_args()
    recs = [os.path.abspath(r) for r in a.rec] or take_recs(a.list)
    r = evaluate(a.adapter, a.stroke, os.path.abspath(a.tables) if a.tables else None, a.set, recs, a.j, a.keep)
    for l in r['lines']:
        if not a.q or ' FAIL' in l:
            print(l)
    print('RESULT KFTAKE-s%d%s %s n=%d fail=%d takes=%d worst %s' % (a.stroke, a.tag, 'PASS' if r['ok'] else 'FAIL',
                                                                    r['n'], r['fail'], r['takes'], r['worst']))
    return 0 if r['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
