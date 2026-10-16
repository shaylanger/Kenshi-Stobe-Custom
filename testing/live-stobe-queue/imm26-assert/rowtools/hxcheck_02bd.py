#!/usr/bin/env python3
"""hxcheck_02bd.py <ROW> <evidence-dir>   verdict for the row runners 02-bx and 02-dx (imm26-rr02).  Reuses hxcheck.py / hxcheck_a.py helpers (nothing edited).
`hxcheck_02bd.py --has <ROW>` exits 0 when the row belongs to this file (pywrap_02bd.sh).  Prints ONE line `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ... [evidence=<dir>]`.
  02-bx  assert_principle.py 02-bx --target T1 T2 T3 --ctl S1 S2 S3 --principle <principle.txt|slavery> --voice-min 3
  02-dx  assert_principle.py 02-dx --target T1 T2 T3 --ctl C1 C2 C3 --principle <principle.txt|slavery>
A missing bundle dir = SETUP-FAIL naming it.  The assert (v2 dir via HX_ASSERT_DIR) is never loosened."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault('HX_ASSERT_DIR', os.path.join(HERE, '..', 'v2'))
import hxcheck as base  # noqa: E402
import hxcheck_a as ha  # noqa: E402

ROWS = ('02-bx', '02-dx')


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if base.norm(argv[2]) in ROWS else 1
    if len(argv) < 3 or base.norm(argv[1]) not in ROWS:
        print(f'usage: hxcheck_02bd.py <ROW> <evidence-dir>   rows: {" ".join(ROWS)}', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    n = base.norm(row)
    bd = base.rd(ev, 'bundle_dir.txt') or ev
    tail = f' [evidence={ev}]'
    groups = [('--target', base.lab('T', 3)), ('--ctl', base.lab('S' if n == '02-bx' else 'C', 3))]
    miss = [f'{g}:{d}' for g, ds in groups for d in ds if not os.path.isdir(os.path.join(bd, d))]
    if miss:
        print(f'RESULT {row} SETUP-FAIL bundle dirs missing under {bd}: {",".join(miss)} (the row script stopped early; see run.log){tail}')
        return 2
    singles = [('--principle', base.rd(bd, 'principle.txt') or 'slavery')]
    if n == '02-bx':
        singles.append(('--voice-min', os.environ.get('HX02B_VOICE_MIN', '3')))
    kind, txt = ha.run_assert('assert_principle.py', n, [(g, [os.path.join(bd, d) for d in ds]) for g, ds in groups], singles)
    print(f'RESULT {row} {kind} {txt[:1700]}{tail}')
    return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]


if __name__ == '__main__':
    sys.exit(main(sys.argv))
