#!/usr/bin/env python3
"""unblockcheck_c_v2.py <ROW> <evidence-dir>   verdict for the v2 15-bx scene (imm26-sfU 2026-10-16; unblockcheck_c.py is NOT edited).  `--has <ROW>` exits 0 for 15-bx.
ONE line on stdout: `RESULT 15-bx PASS|FAIL|SETUP-FAIL|GATED <evidence> [evidence=<dir>]`.  Same as unblockcheck_c.py plus:
  * S1 sleep state: <bundle>/S1/sleep_state.txt (written by unblockdefs_c_v2.sh: tags ordered / after_fight / sample) must exist and the after_fight and sample lines must
    show S1 asleep (first_order SLEEP*) or unconscious; otherwise SETUP-FAIL "S1 was not asleep/KO when the fight events were emitted" (no behaviour verdict: a woken sleeper
    getting fight events is correct, not a native gap).
  * away.txt: X was sent away BEFORE the pair (informational; its absence is a SETUP-FAIL: v1 scene).
  * the asserter directory defaults to ../v2 (HX_ASSERT_DIR still wins), so hxcheck.py 15-bx uses assert_witness.py + the v2 imm26_lib.py.
Nothing is loosened: every v1 scene check and the unchanged assert_witness.py 15-bx verdict stay."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault('HX_ASSERT_DIR', os.path.join(os.path.dirname(HERE), 'v2'))
ROWS = ('15-bx',)
CODES = {'PASS': 0, 'FAIL': 1, 'SETUP-FAIL': 2, 'GATED': 3}


def norm(row):
    return re.sub(r'^IMM-', '', row)


def rd(*parts):
    f = os.path.join(*parts)
    return open(f, encoding='utf-8', errors='replace').read() if os.path.isfile(f) else ''


def out(row, kind, text, ev):
    print(f'RESULT {row} {kind} {text[:1500]} [evidence={ev}]')
    return CODES[kind]


def last_result(text):
    line = ''
    for ln in (text or '').splitlines():
        if re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\b', ln):
            line = ln
    return line


# ------------------------------------------------------------------------------------------------ 15-bx
def dist_entries(d):
    res = []
    for ln in rd(d, 'distance.txt').splitlines():
        p = ln.split('|')
        if len(p) >= 2:
            try:
                res.append((p[0].strip(), float(p[1])))
            except ValueError:
                pass
    return res


def check_15bx(row, ev):
    bd = rd(ev, 'bundle_dir.txt').strip() or ev
    if os.name == 'nt' and len(bd) > 2 and bd[0] == '/' and bd[2] == '/':
        bd = bd[1].upper() + ':' + bd[2:]
        try:
            open(os.path.join(ev, 'bundle_dir.txt'), 'w').write(bd + chr(10))   # hxcheck.py/assert_witness need the same Windows path
        except OSError:
            pass
    labs = [f'X{i}' for i in (1, 2, 3)] + [f'P{i}' for i in (1, 2, 3)] + ['S1']
    missing = [d for d in labs if not os.path.isdir(os.path.join(bd, d))]
    if missing:
        return out(row, 'SETUP-FAIL', f'bundle dirs missing under {bd}: {",".join(missing)} (the row script stopped early; see run.log)', ev)
    fighters = [f.strip() for f in rd(bd, 'fighters.txt').strip().split(',') if f.strip()]
    starter = rd(bd, 'starter.txt').strip()
    bad = []
    if len(set(f.lower() for f in fighters)) < 2:
        bad.append(f'fighters.txt has <2 names ({fighters})')
    if any(f.lower() == 'malzin' for f in fighters):
        bad.append('Malzin is in the fighter roster')
    if starter.lower() not in [f.lower() for f in fighters]:
        bad.append(f'starter "{starter}" is not one of the fighters {fighters}')
    fl = [f.lower() for f in fighters]
    for x in ('X1', 'X2', 'X3'):
        far = [v for k, v in dist_entries(os.path.join(bd, x)) if k.lower() not in fl]
        if not far or min(far) < 250:
            bad.append(f'{x} distance {far[:2]} < 250')
    for x in ('X1', 'X2', 'X3'):   # fix15bxorder: X is sampled before S1 exists; an unconscious body in X's prompt makes the model say "I came in after <S1> was down" (EYEWITNESS)
        hit = [ln.strip()[:90] for ln in rd(bd, x, 'prompt.txt').splitlines() if re.search(r'Action:\s*unconscious|doing:\s*unconscious|\(unconscious\)', ln)]
        if hit:
            bad.append(f'{x} prompt shows an unconscious character ({hit[0]}): recipe order regression, X1-X3 must be sampled before S1 is KO ordered')
    for p in ('P1', 'P2', 'P3'):
        near = [v for k, v in dist_entries(os.path.join(bd, p)) if k.lower() not in fl]
        if not near or min(near) > 15:
            bad.append(f'{p} distance {near[:2]} > 15')
    s1 = [v for k, v in dist_entries(os.path.join(bd, 'S1')) if k.lower() not in fl]
    if not s1 or max(s1) > 100:
        bad.append(f'S1 distance {s1[:2]} > 100')
    if not rd(ev, 'away.txt').strip() and not rd(bd, 'away.txt').strip():
        bad.append('away.txt missing: X was not sent away before the pair spawned (v1 scene, rerun with unblockdefs_c_v2.sh)')
    ss = rd(bd, 'S1', 'sleep_state.txt')
    states = {}
    for ln in ss.splitlines():
        if '|' in ln:
            tag, _, rest = ln.partition('|')
            states[tag.strip()] = rest
    asleep = lambda t: bool(re.search(r'"unconscious"\s*:\s*true', t) or re.search(r'"first_order"\s*:\s*"[^"]*SLEEP', t, re.I))
    if not ss.strip():
        bad.append('S1/sleep_state.txt missing: S1 sleep state not recorded')
    else:
        for tag in ('after_fight', 'sample'):
            if tag not in states:
                bad.append(f'S1 sleep state "{tag}" not recorded')
            elif not asleep(states[tag]):
                bad.append(f'S1 was not asleep/KO at {tag} ({states[tag].strip()[:100]}): the fight woke it or the sleep order did not hold')
    if bad:
        return out(row, 'SETUP-FAIL', 'scene invalid (no behaviour verdict): ' + '; '.join(bad), ev)
    # the server side facts for the report line
    combat = []
    for x in ('X1', 'X2', 'X3'):
        pr = rd(bd, x, 'prompt.txt')
        n = sum(1 for ln in pr.splitlines() if re.search(r'\[combat[^\]]*\]', ln) and any(f in ln.lower() for f in fl))
        combat.append(n)
    argv = [sys.executable, '-u', os.path.join(HERE, 'hxcheck.py'), '15-bx', ev]
    p = subprocess.run(argv, capture_output=True, text=True, env=os.environ.copy())
    line = last_result(p.stdout)
    if not line:
        return out(row, 'FAIL', f'hxcheck.py produced no RESULT line (rc={p.returncode}): {((p.stderr or "").strip().splitlines() or ["no output"])[-1][:200]}', ev)
    m = re.match(r'^RESULT\s+\S+\s+(PASS|FAIL|SETUP-FAIL|GATED)\s*(.*?)(\s*\[evidence=.*\])?$', line)
    kind, rest = m.group(1), m.group(2)
    extra = f' | SERVER X combat lines naming the fighters per sample={combat} fighters={",".join(fighters)} starter={starter} S1 sleep={";".join(t + "=asleep" for t in states)}'
    if kind == 'FAIL' and any(combat):
        extra += ' (a clean scene: the out-of-range witness still got fight events = the separate server bug "witnesses > 277 u get fight events")'
    return out(row, kind, rest + extra, ev)


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if norm(argv[2]) in ROWS else 1
    if len(argv) < 3 or norm(argv[1]) not in ROWS:
        print(f'usage: unblockcheck_c.py <ROW> <evidence-dir>   rows: {" ".join(ROWS)}', file=sys.stderr)
        return 2
    row, ev = argv[1], argv[2]
    return {'15-bx': check_15bx}[norm(row)](row, ev)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
