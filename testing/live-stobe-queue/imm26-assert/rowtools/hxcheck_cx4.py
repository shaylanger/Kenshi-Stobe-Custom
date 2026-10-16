#!/usr/bin/env python3
"""hxcheck_cx4.py <ROW> <evidence-dir>   verdict for 05-cx v4 (imm26-fix15bx05cx3).  NEW file: hxcheck.py / hxcheck_b.py are NOT edited.
Same bundle checks and RESULT line as hxcheck_b.py 05-cx, but the assert script is rowtools/assert_principle_cx4.py (same argv:
  05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3).  HX_ASSERT_DIR (selftest stubs) still wins and then must hold assert_principle_cx4.py.
`--has <ROW>` exits 0 for 05-cx; `--roster <sample-dir>` as hxcheck_b.py."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hxcheck as base  # noqa: E402

ROWS_X = ('05-cx',)
_orig_spec = base.spec


def spec_x(row, bd, ev):
    if row == '05-cx':
        return 'assert_principle_cx4.py', [('--target', base.lab('E', 3)), ('--ctl', base.lab('N', 3)), ('--hidden', base.lab('H', 3))], [], None
    return _orig_spec(row, bd, ev)


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if base.norm(argv[2]) in ROWS_X else 1
    if len(argv) == 3 and argv[1] == '--roster':
        sys.path.insert(0, os.environ.get('HX_LIB_DIR') or os.path.join(HERE, '..'))
        from imm26_lib import Bundle
        print(';'.join(Bundle(argv[2]).roster()))
        return 0
    if len(argv) < 3 or base.norm(argv[1]) not in ROWS_X:
        print(f'usage: hxcheck_cx4.py <ROW> <evidence-dir>   rows: {" ".join(ROWS_X)}', file=sys.stderr)
        return 2
    base.spec = spec_x
    base.ROWS = tuple(base.ROWS) + ROWS_X
    if not os.environ.get('HX_ASSERT_DIR'):
        base.ASSERT = HERE
    return base.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
