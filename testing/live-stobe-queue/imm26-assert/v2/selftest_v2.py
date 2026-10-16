#!/usr/bin/env python3
"""selftest_v2.py (imm26-sfU): offline proof of the v2 asserters against the STORED evidence of the fxA table, plus a negative control for every widened check.
Each case copies stored bundle dirs to a temp dir (optionally rewriting one reply / file), runs the ORIGINAL asserter (../) and the v2 asserter (this dir) and
compares the verdicts with the expected ones.  Never touches the game, a lane or the originals.  Prints `SELFTEST sfU-v2-<name> PASS|FAIL ...` lines and
`SELFTEST SFU-V2 ALL PASS|FAIL n/m`.   Usage: python -I selftest_v2.py [--runs C:/KenshiTestRuns]"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORIG = os.path.dirname(HERE)
RUNS = 'C:/KenshiTestRuns/agents/imm26-sfU-fixtures'   # copies of the stored evidence (the originals are overwritten by reruns)
if '--runs' in sys.argv:
    RUNS = sys.argv[sys.argv.index('--runs') + 1]
TMP = tempfile.mkdtemp(prefix='sfu-v2-')
N = [0, 0]


def run(base, script, args):
    p = subprocess.run([sys.executable, '-I', os.path.join(base, script)] + args, capture_output=True, text=True)
    lines = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
    return lines[0] if lines else 'NO-RESULT ' + (p.stderr or '')[-200:]


def clone(src, name, **edits):
    """clone(src_dir, name, reply='text' | files={'info_panel.txt': 'text'} | sub=('haff.txt', old, new))"""
    d = os.path.join(TMP, name, os.path.basename(src))   # keep the label (F3, T2, O3...) so check names match
    shutil.copytree(src, d)
    if 'reply' in edits:
        f = os.path.join(d, 'events.txt')
        out = []
        for ln in open(f, encoding='utf-8', errors='replace').read().splitlines():
            p = ln.split('|', 3)
            m = re.match(r'(\s*)([^:]+?):\s*(.*?)(\s*\(talking to:.*)', p[2]) if len(p) >= 3 and p[1] == 'chat' else None
            if m and m.group(2).strip().lower() not in ('shay', 'player'):
                p[2] = f'{m.group(1)}{m.group(2)}: {edits["reply"]}{m.group(4)}'
                ln = '|'.join(p)
            out.append(ln)
        open(f, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    for fn, txt in (edits.get('files') or {}).items():
        open(os.path.join(d, fn), 'w', encoding='utf-8').write(txt)
    if 'sub' in edits:
        fn, old, new = edits['sub']
        f = os.path.join(d, fn)
        s = open(f, encoding='utf-8').read()
        assert old in s, f'{fn}: anchor {old!r} missing'
        open(f, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    return d


def case(name, script, args, o_kind, v_kind, v_bad=(), v_not_bad=(), o_bad=()):
    """expect the ORIGINAL to give o_kind (and o_bad tokens among its failures) and v2 to give v_kind (v_bad tokens must be failed checks, v_not_bad must NOT be)."""
    N[1] += 1
    o, v = run(ORIG, script, args), run(HERE, script, args)
    ok = o.split()[2:3] == [o_kind] and v.split()[2:3] == [v_kind]
    vfail = v.split(' FAIL ', 1)[1].split(';') if ' FAIL ' in v else []
    vfail = [x.strip() for x in vfail if '!' in x]
    ofail = o.split(' FAIL ', 1)[1].split(';') if ' FAIL ' in o else []
    ofail = [x.strip() for x in ofail if '!' in x]
    ok = ok and all(any(t in x for x in vfail) for t in v_bad) and not any(t in x for t in v_not_bad for x in vfail)
    ok = ok and all(any(t in x for x in ofail) for t in o_bad)
    N[0] += ok
    print(f'SELFTEST sfU-v2-{name} {"PASS" if ok else "FAIL"} orig={o_kind if o.split()[2:3] == [o_kind] else o[:90]} v2={v_kind if v.split()[2:3] == [v_kind] else v[:140]}')


def dirs(base, labels):
    return [f'{base}/{x}' for x in labels]


AX = f'{RUNS}/imm26-4080-i4/02-ax'
DX = f'{RUNS}/imm26-5090-hx/02-dx'
CX = f'{RUNS}/imm26-4080-hx/02-cx'
BX = f'{RUNS}/imm26-4080-i4/16-bx'


def ax(f3=None, f3name='F3'):
    return ['02-ax', '--target'] + dirs(AX, ['T1', 'T2', 'T3']) + ['--ctl', AX + '/F1', AX + '/F2', f3 or AX + '/F3']


# ---- 02-ax
case('02ax-stored-negated-oath', 'assert_principle.py', ax(), 'FAIL', 'PASS', o_bad=['F3:no_invented_principle'])
f = clone(AX + '/F3', 'ax-real-oath', reply="I stand for keeping my kit in order. I swore an oath to the Holy Nation, stranger, and I keep it.")
case('02ax-control-real-invention-still-fails', 'assert_principle.py', ax(f), 'FAIL', 'FAIL', v_bad=['F3:no_invented_principle'])
f = clone(AX + '/F3', 'ax-neg-other-clause', reply="I never trust strangers. I took a vow of silence, and my kit stays in order.")
case('02ax-control-negation-in-earlier-clause-still-fails', 'assert_principle.py', ax(f), 'FAIL', 'FAIL', v_bad=['F3:no_invented_principle'])
f = clone(AX + '/F3', 'ax-neg-far', reply="I do not talk much but i swore an oath long ago, and my kit stays in order.")
case('02ax-control-negation-then-new-clause-oath-still-fails', 'assert_principle.py', ax(f), 'FAIL', 'FAIL', v_bad=['F3:no_invented_principle'])
f = clone(AX + '/F3', 'ax-wordprefix', reply="I keep my kit in order and my debts square, nothing avowed, nothing more.")
case('02ax-word-prefix-avowed-not-a-vow', 'assert_principle.py', ax(f), 'FAIL', 'PASS', o_bad=['F3:no_invented_principle'])

f = clone(AX + '/F3', 'ax-neg-list', reply="I stand for keeping my kit in order and my debts square. I don't hand out oaths, vows or sworn promises to strangers.")
case('02ax-negated-list-of-words-passes', 'assert_principle.py', ax(f), 'FAIL', 'PASS', o_bad=['F3:no_invented_principle'])
f = clone(AX + '/F3', 'ax-comma-subject', reply="I never trust strangers, I swore an oath once, and my kit stays in order.")
case('02ax-control-comma-new-subject-oath-still-fails', 'assert_principle.py', ax(f), 'FAIL', 'FAIL', v_bad=['F3:no_invented_principle'])

# ---- 02-dx
def dx(t2=None, t1=None):
    return ['02-dx', '--target', t1 or DX + '/T1', t2 or DX + '/T2', DX + '/T3', '--ctl'] + dirs(DX, ['C1', 'C2', 'C3']) + ['--principle', 'slavery']


case('02dx-stored-second-sentence-refusal-and-after-aff', 'assert_principle.py', dx(), 'FAIL', 'PASS', o_bad=['T2:refuses', 'C1:haff'])
f = clone(DX + '/T2', 'dx-coop', reply="Sure, I'll chain him up for you, Shay. Lead the way.")
case('02dx-control-cooperation-still-fails', 'assert_principle.py', dx(f), 'FAIL', 'FAIL', v_bad=['T2:refuses'])
f = clone(DX + '/T2', 'dx-late', reply="Hmm, let me think about that. Interesting offer, Shay. Alright, fine, lead the way.")
case('02dx-control-refusal-after-two-sentences-still-fails', 'assert_principle.py', dx(f), 'FAIL', 'FAIL', v_bad=['T2:refuses'])
f = clone(DX + '/T1', 'dx-aff0', sub=('haff.txt', '"after":{"Shay":{"aff":60', '"after":{"Shay":{"aff":0'))
case('02dx-control-target-after-aff-not-60-still-fails', 'assert_principle.py', dx(t1=f), 'FAIL', 'FAIL', v_bad=['T1:haff'])
f = clone(DX + '/T2', 'dx-action', files={'reply.txt': open(DX + '/T2/reply.txt', encoding='utf-8', errors='replace').read() + '\n[2026-10-16 00:00:00.000] [Stobe] ACTION_EXEC: CAPTURE [Cind]: shackle him (NPC)\n'})
case('02dx-control-foreign-action-still-fails', 'assert_principle.py', dx(f), 'FAIL', 'FAIL', v_bad=['T2:no_action'])

# ---- 02-cx
def cx(c3=None):
    return ['02-cx', '--target', CX + '/C1', CX + '/C2', c3 or CX + '/C3', '--ctl'] + dirs(CX, ['O1', 'O2', 'O3']) + ['--principle', 'slavery']


case('02cx-stored-panel-says-shackles', 'assert_principle.py', cx(), 'FAIL', 'FAIL', v_bad=['C2:replies_names_principle'], v_not_bad=['C3:info_panel'], o_bad=['C3:info_panel'])
f = clone(CX + '/C3', 'cx-nopanel', files={'info_panel.txt': 'open=1 key=1|Shay text=Cind | Job: Hungry Bandit | ABOUT THEM | He likes bread and long walks.\n'})
case('02cx-control-panel-without-principle-still-fails', 'assert_principle.py', cx(f), 'FAIL', 'FAIL', v_bad=['C3:info_panel_shows_principle'])

# ---- 16-bx
def bx(o3=None):
    return ['16-bx', '--target'] + dirs(BX, ['R1', 'R2', 'R3']) + ['--ctl', BX + '/O1', BX + '/O2', o3 or BX + '/O3', '--trait', 'reserved']


case('16bx-stored-good-to-see-is-friendly', 'assert_stance.py', bx(), 'FAIL', 'FAIL', v_bad=['R1:words 3..40', 'O2:ctl_friendly_words'], v_not_bad=['O1:ctl_friendly_words'], o_bad=['O1:ctl_friendly_words'])
f = clone(BX + '/O3', 'bx-cold', reply="State your business and make it quick. I do not know you.")
case('16bx-control-unfriendly-control-still-fails', 'assert_stance.py', bx(f), 'FAIL', 'FAIL', v_bad=['O3:ctl_friendly_words'])
f = clone(BX + '/R1', 'bx-r1-short', reply="Good to see you breathing. Sit, and let me look at that.")
case('16bx-word-cap-kept', 'assert_stance.py', ['16-bx', '--target', f, BX + '/R2', BX + '/R3', '--ctl'] + dirs(BX, ['O1', 'O2', 'O3']) + ['--trait', 'reserved'], 'FAIL', 'FAIL', v_not_bad=['R1:words 3..40'], v_bad=['O2:ctl_friendly_words'])
f = clone(BX + '/R1', 'bx-r1-long', reply=' '.join(['word'] * 45))
case('16bx-control-45-word-reply-still-fails-cap', 'assert_stance.py', ['16-bx', '--target', f, BX + '/R2', BX + '/R3', '--ctl'] + dirs(BX, ['O1', 'O2', 'O3']) + ['--trait', 'reserved'], 'FAIL', 'FAIL', v_bad=['R1:words 3..40'])

shutil.rmtree(TMP, ignore_errors=True)
print(f'SELFTEST SFU-V2 ALL {"PASS" if N[0] == N[1] else "FAIL"} {N[0]}/{N[1]}')
sys.exit(0 if N[0] == N[1] else 1)
