#!/usr/bin/env python3
"""selftest_sfy.py (imm26-sfY): offline proof of the opening-sentence fix in v2/assert_stance.py (rows 01-bx / 01-cx) and of rowtools/unblockcheck_e_v2.py (row 10-b).
Fixtures = copies of the 4080-i3 NC20 stored evidence (C:/KenshiTestRuns/agents/imm26-sfY-fixtures/{01-bx,01-cx}); 10-b uses synthetic dirs.  Never touches the game or a lane.
Prints `SELFTEST sfY-<name> PASS|FAIL ...` and `SELFTEST SFY ALL PASS|FAIL n/m`.   Usage: python -I selftest_sfy.py [--runs DIR]"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORIG = os.path.dirname(HERE)
RT = os.path.join(ORIG, 'rowtools')
FIX = sys.argv[sys.argv.index('--runs') + 1] if '--runs' in sys.argv else 'C:/KenshiTestRuns/agents/imm26-sfY-fixtures'
TMP = tempfile.mkdtemp(prefix='sfy-')
N = [0, 0]
sys.path.insert(0, HERE)


def report(name, ok, info=''):
    N[1] += 1
    N[0] += bool(ok)
    print(f'SELFTEST sfY-{name} {"PASS" if ok else "FAIL"} {info}')


def run(script, args):
    p = subprocess.run([sys.executable, '-I', script] + args, capture_output=True, text=True)
    ls = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
    return ls[0] if ls else 'NO-RESULT ' + (p.stderr or '')[-200:]


def kind(r):
    return r.split()[2] if len(r.split()) > 2 else '?'


def failed(r):
    return [x.strip() for x in r.split(' FAIL ', 1)[1].split(';') if '!' in x] if ' FAIL ' in r else []


# ---- 1. opening_sentence units (importing assert_stance also proves the module loads)
import assert_stance as S  # noqa: E402
U = [("Slave Hunter. I don't know you, and I don't linger.", "Slave Hunter. I don't know you, and I don't linger."),
     ('Hnh. You are talking to me. Say what you want.', 'Hnh. You are talking to me.'),
     ('No. Not with you. Go away.', 'No. Not with you.'),
     ('Together. Hm. I will pass on that, truly.', 'Together. Hm. I will pass on that, truly.'),
     ('Day is only good if it stays quiet. Two.', 'Day is only good if it stays quiet.'),
     ('Hello', 'Hello'), ('', '')]
for i, (inp, want) in enumerate(U):
    got = S.opening_sentence(inp)
    report(f'opening-unit{i}', got == want, f'got={got!r}')


def fx(*p):
    return f'{FIX}/' + '/'.join(p)


def clone(src, name, reply):
    d = os.path.join(TMP, name, os.path.basename(src))
    shutil.copytree(src, d)
    f = os.path.join(d, 'events.txt')
    out = []
    for ln in open(f, encoding='utf-8', errors='replace').read().splitlines():
        p = ln.split('|', 3)
        m = re.match(r'(\s*)([^:]+?):\s*(.*?)(\s*\(talking to:.*)', p[2]) if len(p) >= 3 and p[1] == 'chat' else None
        if m and m.group(2).strip().lower() not in ('shay', 'player'):
            p[2] = f'{m.group(1)}{m.group(2)}: {reply}{m.group(4)}'
            ln = '|'.join(p)
        out.append(ln)
    open(f, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    return d


def bx_args(sav, T=None):
    seed = open(fx('01-bx', sav, 'seed.txt'), encoding='utf-8').read().strip()
    t = T or [fx('01-bx', sav, x) for x in ('T1', 'T2', 'T3')]
    return ['01-bx', '--target'] + t + ['--ctl-nohist'] + [fx('01-bx', sav, x) for x in ('CN1', 'CN2', 'CN3')] + \
           ['--ctl-pos'] + [fx('01-bx', sav, x) for x in ('CP1', 'CP2', 'CP3')] + ['--seed', seed]


def cx_args(sav, H=None):
    h = H or [fx('01-cx', sav, x) for x in ('H1', 'H2', 'H3')]
    return ['01-cx', '--target'] + h + ['--ctl'] + [fx('01-cx', sav, x) for x in ('A1', 'A2', 'A3')]


V1, V2 = os.path.join(ORIG, 'assert_stance.py'), os.path.join(HERE, 'assert_stance.py')
if os.path.isdir(FIX):
    # ---- 2. stored 4080-i3 evidence: v1 FAILs on the fragment; v2 verdict is real (01-bx both saves PASS, 01-cx savB PASS, 01-cx savA stays a REAL FAIL: 1/3 guarded openings)
    for sav in ('savA', 'savB'):
        o, v = run(V1, bx_args(sav)), run(V2, bx_args(sav))
        report(f'01-bx-{sav}-v1-fails-v2-passes', kind(o) == 'FAIL' and any('target_reluctant' in x for x in failed(o)) and kind(v) == 'PASS', f'v1={kind(o)} v2={kind(v)}')
    o, v = run(V1, cx_args('savB')), run(V2, cx_args('savB'))
    report('01-cx-savB-v1-fails-v2-passes', kind(o) == 'FAIL' and kind(v) == 'PASS', f'v1={kind(o)} v2={kind(v)}')
    v = run(V2, cx_args('savA'))
    report('01-cx-savA-real-fail-kept', kind(v) == 'FAIL' and any('hostile_guarded' in x for x in failed(v)), f'v2={kind(v)}')
    # ---- 3. negative controls: a fragment followed by a cooperative sentence must NOT pass
    T = [clone(fx('01-bx', 'savA', x), f'n1{x}', 'Hnh. Sure, lead the way, I will walk with you.') for x in ('T1', 'T2', 'T3')]
    v = run(V2, bx_args('savA', T))
    report('01-bx-negctl-fragment-then-coop-fails', kind(v) == 'FAIL' and any('target_reluctant' in x or 'not_coop' in x for x in failed(v)), f'v2={kind(v)}')
    H = [clone(fx('01-cx', 'savB', x), f'n2{x}', 'Together. Sure, lead the way, friend.') for x in ('H1', 'H2', 'H3')]
    v = run(V2, cx_args('savB', H))
    report('01-cx-negctl-fragment-then-coop-fails', kind(v) == 'FAIL' and any('no_coop' in x or 'hostile_guarded' in x for x in failed(v)), f'v2={kind(v)}')
else:
    print(f'SELFTEST sfY-fixtures SKIP {FIX} missing')


# ---- 4. 10-b: aff_end.txt OR haff-aff_end.txt
def mk10(name, afname, aff=-47):
    d = os.path.join(TMP, name)
    os.makedirs(d)
    open(f'{d}/victim.txt', 'w').write('Cind [Hungry Bandit]')
    open(f'{d}/gift.txt', 'w').write('Iron Plates')
    open(f'{d}/effects_c.txt', 'w').write('aggression|-24|Cind|Shay|100\napology_relief|2|Cind|Shay|110\ngift|3|Cind|Shay|120\n')
    open(f'{d}/inbox_transfer.txt', 'w').write('Cind|false|Shay|true|{}|{}|{"Iron Plates": 1}\n')
    open(f'{d}/transfer_log.txt', 'w').write('SOCIAL_CAPTURE kind=item_transfer actor=#1(Cind) target=#2(Shay) verified:true\n')
    if afname:
        open(f'{d}/{afname}', 'w').write('{"before":{"Shay":{"aff":%d}},"after":{"Shay":{"aff":%d}}}' % (aff, aff))
    return d


E1, E2 = os.path.join(RT, 'unblockcheck_e.py'), os.path.join(RT, 'unblockcheck_e_v2.py')
for nm, af, exp in (('haff-name', 'haff-aff_end.txt', 'PASS'), ('plain-name', 'aff_end.txt', 'PASS'), ('no-file', None, 'FAIL')):
    d = mk10('e' + nm, af)
    v2, v1 = run(E2, ['10-b', d]), run(E1, ['10-b', d])
    ok = kind(v2) == exp and (af != 'haff-aff_end.txt' or kind(v1) == 'FAIL') and (exp != 'FAIL' or 'affinity_still_negative' in v2)
    report(f'10-b-{nm}', ok, f'v1={kind(v1)} v2={kind(v2)}')
v2 = run(E2, ['10-b', mk10('epos', 'haff-aff_end.txt', 5)])
report('10-b-positive-aff-still-fails', kind(v2) == 'FAIL' and 'affinity_still_negative' in v2, kind(v2))
if os.path.isdir('C:/KenshiTestRuns/imm26-4080/rows/10-b/s1'):
    r = run(E2, ['10-b', 'C:/KenshiTestRuns/imm26-4080/rows/10-b'])
    report('10-b-stored-4080-i3-evidence', kind(r) == 'PASS', kind(r))
report('unblockdefs_e_v2-bash-n', subprocess.run(['bash', '-n', 'unblockdefs_e_v2.sh'], cwd=RT).returncode == 0)
t = open(os.path.join(RT, 'unblockdefs_e_v2.sh'), encoding='utf-8').read()
report('unblockdefs_e_v2-uses-v2-checker', 'unblockcheck_e_v2.py' in t and 'unblockcheck_e.py' not in t)
h = open(os.path.join(RT, 'hxrun_v2.sh'), encoding='utf-8').read()
report('hxrun_v2-has-HXA-rows-and-v2-dir', 'hxdefs_a.sh' in h and 'HXA_ROWS' in h and 'HX_ASSERT_DIR' in h and os.path.isfile(V2))

shutil.rmtree(TMP, ignore_errors=True)
print(f'SELFTEST SFY ALL {"PASS" if N[0] == N[1] else "FAIL"} {N[0]}/{N[1]}')
sys.exit(0 if N[0] == N[1] else 1)
