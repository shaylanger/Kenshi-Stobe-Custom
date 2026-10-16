#!/usr/bin/env python3
"""hxcheck.py <ROW> <evidence-dir>   verdict for the hardening rows 17-bx 18-cx 16-bx 15-bx 13-ax 02-ax (imm26-rowtools43).
`hxcheck.py --has <ROW>` exits 0 when the row belongs to this file (used by pywrap_hx.sh).
It does NOT judge anything itself: it finds the sample bundles that hxdefs.sh wrote (dir named by <evidence-dir>/bundle_dir.txt, else the evidence dir),
builds the row's assert command line exactly as the row text in NPC_IMMERSION_26_TESTS.md gives it, runs the assert script and prints ONE line
`RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED <the assert's evidence> [evidence=<dir>]` (exit 0/1/2/3, same shape as rowcheck.py).
  17-bx  assert_claims.py 17-bx --false F1 F2 F3 --true T1 T2 T3 --item <item.txt>
  18-cx  assert_claims.py 18-cx --combat C1 C2 C3 --calm K1 K2 K3 --target <target.txt>
  16-bx  assert_stance.py 16-bx --target R1 R2 R3 --ctl O1 O2 O3 --trait reserved
  15-bx  assert_witness.py 15-bx --out X1 X2 X3 --inrange P1 P2 P3 --asleep S1 --fighters <fighters.txt> --starter <starter.txt>
  13-ax  assert_witness.py 13-ax --pos P1 P2 --neg N1 N2 --ctl C1   (price from each run's deal.txt; GATED `PARTIAL` when not all five runs exist)
  02-ax  assert_principle.py 02-ax --target T1 T2 T3 --ctl F1 F2 F3
A missing bundle dir = SETUP-FAIL naming it (the row script stopped early); the assert itself is never loosened (no --lenient).
Env HX_ASSERT_DIR points at another directory holding the assert_*.py scripts (the offline selftest uses stubs to check the argument lists)."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSERT = os.environ.get('HX_ASSERT_DIR') or os.path.join(HERE, '..')


def rd(ev, name):
    f = os.path.join(ev, name)
    return open(f, encoding='utf-8', errors='replace').read().strip() if os.path.isfile(f) else ''


def lab(prefix, n):
    return [f'{prefix}{i}' for i in range(1, n + 1)]


# row -> (assert script, [(flag, [labels])], single flags [(flag, file-with-value | literal)], required labels, text for the setup-fail)
def spec(row, bd, ev):
    if row == '17-bx':
        return 'assert_claims.py', [('--false', lab('F', 3)), ('--true', lab('T', 3))], [('--item', rd(bd, 'item.txt') or 'Sabreclaw')], None
    if row == '18-cx':
        return 'assert_claims.py', [('--combat', lab('C', 3)), ('--calm', lab('K', 3))], [('--target', rd(bd, 'target.txt'))], None
    if row == '16-bx':
        return 'assert_stance.py', [('--target', lab('R', 3)), ('--ctl', lab('O', 3))], [('--trait', 'reserved')], None
    if row == '15-bx':
        return 'assert_witness.py', [('--out', lab('X', 3)), ('--inrange', lab('P', 3)), ('--asleep', ['S1'])], [('--fighters', rd(bd, 'fighters.txt')), ('--starter', rd(bd, 'starter.txt'))], None
    if row == '13-ax':
        return 'assert_witness.py', [('--pos', ['P1', 'P2']), ('--neg', ['N1', 'N2']), ('--ctl', ['C1'])], [], 'partial'
    if row == '02-ax':
        return 'assert_principle.py', [('--target', lab('T', 3)), ('--ctl', lab('F', 3))], [], None
    return None


ROWS = ('17-bx', '18-cx', '16-bx', '15-bx', '13-ax', '02-ax')


def norm(row):
    return re.sub(r'^IMM-', '', row)


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if norm(argv[2]) in ROWS else 1
    if len(argv) < 3 or norm(argv[1]) not in ROWS:
        print(f'usage: hxcheck.py <ROW> <evidence-dir>   rows: {" ".join(ROWS)}', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    bd = rd(ev, 'bundle_dir.txt') or ev
    sc, groups, singles, mode = spec(norm(row), bd, ev)
    missing = [f'{g}:{d}' for g, ds in groups for d in ds if not os.path.isdir(os.path.join(bd, d))]
    tail = f' [evidence={ev}]'
    if mode == 'partial' and missing:
        have = [d for g, ds in groups for d in ds if os.path.isdir(os.path.join(bd, d))]
        print(f'RESULT {row} GATED PARTIAL 13-ax: runs present {",".join(have) or "none"}, missing {",".join(m.split(":")[1] for m in missing)} (the assert needs all five; rerun the rest with --runs){tail}')
        return 3
    if missing:
        print(f'RESULT {row} SETUP-FAIL bundle dirs missing under {bd}: {",".join(missing)} (the row script stopped early; see run.log){tail}')
        return 2
    empty = [f for f, v in singles if not v]
    if empty:
        print(f'RESULT {row} SETUP-FAIL the row script wrote no value for {",".join(empty)} (target.txt / fighters.txt / starter.txt){tail}')
        return 2
    argv2 = [sys.executable, '-u', os.path.join(ASSERT, sc), norm(row)]
    for flag, ds in groups:
        argv2 += [flag] + [os.path.join(bd, d) for d in ds]
    for flag, v in singles:
        argv2 += [flag, v]
    p = subprocess.run(argv2, capture_output=True, text=True)
    line = ''
    for ln in (p.stdout or '').splitlines():
        if re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\b', ln):
            line = ln
    if not line:
        why = ((p.stderr or '').strip().splitlines() or ['no output'])[-1][:200]
        print(f'RESULT {row} FAIL {sc} produced no RESULT line (rc={p.returncode}): {why}{tail}')
        return 1
    m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*)$', line)
    kind, rest = m.group(1), m.group(2)
    print(f'RESULT {row} {kind} {rest[:1500]}{tail}')
    return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]


if __name__ == '__main__':
    sys.exit(main(sys.argv))
