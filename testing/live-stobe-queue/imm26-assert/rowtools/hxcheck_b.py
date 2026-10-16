#!/usr/bin/env python3
"""hxcheck_b.py <ROW> <evidence-dir>   verdict for the hardening rows of family B (imm26-hxB): 05-cx.  Reuses hxcheck.py (same RESULT line shape, same SETUP-FAIL rules);
nothing in hxcheck.py is edited: this file adds its rows to hxcheck's ROWS/spec at import time.
  05-cx  assert_principle.py 05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3
`hxcheck_b.py --has <ROW>` exits 0 when the row belongs to this file (pywrap_hx.sh).  `hxcheck_b.py --roster <sample-dir>` prints the names under
'## Nearby People Awareness' (player excluded, the assert's own parser) joined by ';' (empty = empty roster)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hxcheck as base  # noqa: E402

ROWS_B = ('05-cx',)


def spec_b(row, bd, ev):
    if row == '05-cx':
        return 'assert_principle.py', [('--target', base.lab('E', 3)), ('--ctl', base.lab('N', 3)), ('--hidden', base.lab('H', 3))], [], None
    return _orig_spec(row, bd, ev)


_orig_spec = base.spec


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if base.norm(argv[2]) in ROWS_B else 1
    if len(argv) == 3 and argv[1] == '--roster':
        sys.path.insert(0, os.environ.get('HX_LIB_DIR') or os.path.join(HERE, '..'))
        from imm26_lib import Bundle
        print(';'.join(Bundle(argv[2]).roster()))
        return 0
    if len(argv) < 3 or base.norm(argv[1]) not in ROWS_B:
        print(f'usage: hxcheck_b.py <ROW> <evidence-dir>   rows: {" ".join(ROWS_B)}', file=sys.stderr)
        return 2
    base.spec = spec_b
    base.ROWS = tuple(base.ROWS) + ROWS_B
    return base.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
