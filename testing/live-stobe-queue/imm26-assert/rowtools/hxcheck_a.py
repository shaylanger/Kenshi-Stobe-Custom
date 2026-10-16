#!/usr/bin/env python3
"""hxcheck_a.py <ROW> <evidence-dir>   verdict for the hardening rows of family A (imm26-hxA): 01-bx 01-cx 02-cx.  Reuses hxcheck.py helpers (rd, lab, norm,
ASSERT dir incl. HX_ASSERT_DIR for the offline selftest); nothing in hxcheck.py is edited.  Prints ONE line `RESULT <ROW> PASS|FAIL|SETUP-FAIL|GATED ... [evidence=<dir>]`.
  01-bx  per save (dirs savA/ and savB/ under the bundle dir): assert_stance.py 01-bx --target T1 T2 T3 --ctl-nohist CN1 CN2 CN3 --ctl-pos CP1 CP2 CP3 --seed "<savX/seed.txt>"
  01-cx  per save (savA/ savB/): assert_stance.py 01-cx --target H1 H2 H3 --ctl A1 A2 A3
  02-cx  assert_principle.py 02-cx --target C1 C2 C3 --ctl O1 O2 O3 --principle <principle.txt, default slavery>
01-bx/01-cx pass only when BOTH saves pass (one assert run per save, the line lists each).  A missing bundle dir = SETUP-FAIL naming it.
`hxcheck_a.py --has <ROW>` exits 0 when the row belongs to this file (pywrap_hx.sh)."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hxcheck as base  # noqa: E402

ROWS_A = ('01-bx', '01-cx', '02-cx')
SAVES = ('savA', 'savB')


def run_assert(script, row, groups, singles):
    argv = [sys.executable, '-u', os.path.join(base.ASSERT, script), row]
    for flag, dirs in groups:
        argv += [flag] + dirs
    for flag, v in singles:
        argv += [flag, v]
    p = subprocess.run(argv, capture_output=True, text=True)
    line = ''
    for ln in (p.stdout or '').splitlines():
        if re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\b', ln):
            line = ln
    if not line:
        why = ((p.stderr or '').strip().splitlines() or ['no output'])[-1][:200]
        return 'FAIL', f'{script} produced no RESULT line (rc={p.returncode}): {why}'
    m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*)$', line)
    return m.group(1), m.group(2)


def per_save(row, bd, groups_labels, single_fn):
    """Run the assert once per save dir; returns (kind, text)."""
    sc = 'assert_stance.py'
    miss = [f'{sv}/{d}' for sv in SAVES for _, ds in groups_labels for d in ds if not os.path.isdir(os.path.join(bd, sv, d))]
    if miss:
        return 'SETUP-FAIL', f'bundle dirs missing under {bd}: {",".join(miss)} (the row script stopped early; see run.log)'
    kinds, parts = [], []
    for sv in SAVES:
        sdir = os.path.join(bd, sv)
        singles = single_fn(sdir)
        empty = [f for f, v in singles if not v]
        if empty:
            return 'SETUP-FAIL', f'{sv}: the row script wrote no value for {",".join(empty)} (seed.txt)'
        k, rest = run_assert(sc, row, [(f, [os.path.join(sdir, d) for d in ds]) for f, ds in groups_labels], singles)
        kinds.append(k)
        parts.append(f'{sv}={k} {rest[:700]}')
    if 'FAIL' in kinds:
        kind = 'FAIL'
    elif 'SETUP-FAIL' in kinds:
        kind = 'SETUP-FAIL'
    elif 'GATED' in kinds:
        kind = 'GATED'
    else:
        kind = 'PASS'
    return kind, ' | '.join(parts)


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if base.norm(argv[2]) in ROWS_A else 1
    if len(argv) < 3 or base.norm(argv[1]) not in ROWS_A:
        print(f'usage: hxcheck_a.py <ROW> <evidence-dir>   rows: {" ".join(ROWS_A)}', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    n = base.norm(row)
    bd = base.rd(ev, 'bundle_dir.txt') or ev
    tail = f' [evidence={ev}]'
    if n == '01-bx':
        kind, txt = per_save('01-bx', bd, [('--target', base.lab('T', 3)), ('--ctl-nohist', base.lab('CN', 3)), ('--ctl-pos', base.lab('CP', 3))],
                             lambda sd: [('--seed', base.rd(sd, 'seed.txt'))])
    elif n == '01-cx':
        kind, txt = per_save('01-cx', bd, [('--target', base.lab('H', 3)), ('--ctl', base.lab('A', 3))], lambda sd: [])
    else:  # 02-cx
        groups = [('--target', base.lab('C', 3)), ('--ctl', base.lab('O', 3))]
        miss = [f'{g}:{d}' for g, ds in groups for d in ds if not os.path.isdir(os.path.join(bd, d))]
        if miss:
            kind, txt = 'SETUP-FAIL', f'bundle dirs missing under {bd}: {",".join(miss)} (the row script stopped early; see run.log)'
        else:
            pr = base.rd(bd, 'principle.txt') or 'slavery'
            kind, txt = run_assert('assert_principle.py', n, [(g, [os.path.join(bd, d) for d in ds]) for g, ds in groups], [('--principle', pr)])
    print(f'RESULT {row} {kind} {txt[:1700]}{tail}')
    return {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}[kind]


if __name__ == '__main__':
    sys.exit(main(sys.argv))
