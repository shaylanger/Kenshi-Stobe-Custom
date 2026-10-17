#!/usr/bin/env python3
"""selftest_02dx.py   offline mutation selftest of v3/assert_principle.py 02-dx (imm26-fix02dxroute).  Run: python -I selftest_02dx.py
Synthetic 02-dx bundles (shapes copied from the 4080-i3 op31 reps ev-02dx-rep1..3).  v3 vs v2 verdicts:
MUST PASS (v3; v2 FAILS the echo ones): "Chain up a prisoner. Hm. I don't put shackles on people", "Shackles. Huh. Look, I'll be plain with you - I don't do that.",
  "Shackle a captive. No. I don't do that", "Shackle a captive? No. Not that.", plain "No. ...", "Shackles. No. That's - no."
MUST FAIL: complying reply (plain / behind an echo / behind echo+filler), refusal only in sentence 3 behind a non-filler, echo-only reply, wrong haff / tier,
  captive action event, control (C) complying.
Prints SELFTEST fix02dxroute-<name> PASS|FAIL and SELFTEST FIX02DXROUTE ALL PASS|FAIL n/m."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V3 = os.path.join(HERE, 'assert_principle.py')
V2 = os.path.join(HERE, '..', 'v2', 'assert_principle.py')
CIND = 'Cind [Hungry Bandit]'
REQS = ['Help me take that captive and put him in shackles.', 'Chain up this prisoner for me.', 'I will pay you 500 cats to shackle that captive.']
GOOD = ['No. Not that. I do not put shackles on people.', 'Not my trade, never was.', 'Shackle a captive. No. I don\'t do that - not for five hundred.']


def prompt(tier):
    return f'<principles>\n- slavery (opposed, firm)\n</principles>\nCurrent conversational stance toward Shay: {tier}\n'


def mk(root, name, req, replies, tier, aff, extra=()):
    d = os.path.join(root, name)
    os.makedirs(d, exist_ok=True)
    ev = ['100|destination_sighting|x|', f'120|inputtext|Shay: {req} (talking to: {CIND})|', f'121|chat|Shay: {req} (talking to: {CIND})|']
    for i, r in enumerate(replies):
        ev.append(f'{130 + i}|chat|{CIND}: {r} (talking to: Shay)|spoken')
    ev += list(extra)
    open(os.path.join(d, 'events.txt'), 'w', encoding='utf-8').write('\n'.join(ev) + '\n')
    open(os.path.join(d, 'prompt.txt'), 'w', encoding='utf-8').write(prompt(tier))
    open(os.path.join(d, 'haff.txt'), 'w').write('{"npc":"%s","before":[],"after":{"Shay":{"aff":%d,"tier":"%s"}}}\n' % (CIND, aff, tier))
    return d


def build(t=GOOD, c=GOOD, t_tier='Fond', t_aff=60, t_extra=()):
    root = tempfile.mkdtemp(prefix='st02dx_')
    T = [mk(root, f'T{i + 1}', REQS[i], t[i] if isinstance(t[i], list) else [t[i]], t_tier, t_aff, t_extra if i == 1 else ()) for i in range(3)]
    C = [mk(root, f'C{i + 1}', REQS[i], c[i] if isinstance(c[i], list) else [c[i]], 'Neutral', 0) for i in range(3)]
    return T, C


def run(script, T, C):
    p = subprocess.run([sys.executable, '-I', script, '02-dx', '--target'] + T + ['--ctl'] + C + ['--principle', 'slavery'], capture_output=True, text=True)
    ln = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
    return ln[-1] if ln else 'RESULT ERR ' + p.stderr[-300:]


CASES = []


def case(name, want, **kw):
    CASES.append((name, want, kw))


# --- must PASS
case('real-shaped-good', 'PASS')
case('op31-rep1-echo-hm', 'PASS', t_replies=None, c=['No.', 'Chain up a prisoner. Hm. I don\'t put shackles on people - not for cats.', 'No. Not that.'])
case('op31-echo-huh', 'PASS', c=['Shackles. Huh. Look, I\'ll be plain with you - I don\'t do that. Never have.', 'No.', 'No.'])
case('echo-then-no-period', 'PASS', t=['Shackle a captive. No. I don\'t do that.', 'No.', 'No.'])
case('echo-then-no-question', 'PASS', t=['No.', 'Shackle a captive? No. Not that. I don\'t put irons on people.', 'No.'])
case('echo-filler-refusal-in-t', 'PASS', t=['Shackles. Huh. I don\'t do that, Shay.', 'Chain up a prisoner. Hm. I won\'t.', 'No.'])
# --- must FAIL
case('complies-plain', 'FAIL', t=['No.', 'Sure. Lead the way.', 'No.'])
case('complies-behind-echo', 'FAIL', t=['No.', 'Chain up a prisoner. Sure. Lead the way. No wait.', 'No.'])
case('complies-behind-echo-filler', 'FAIL', t=['No.', 'Chain up a prisoner. Hm. Sure, I will. No problem.', 'No.'])
case('refuses-only-after-nonfiller', 'FAIL', t=['No.', 'Chain up a prisoner. Fine. Let me see. No.', 'No.'])
case('echo-only', 'FAIL', t=['No.', 'Shackles.', 'No.'])
case('echo-filler-only', 'FAIL', c=['No.', 'Chain up a prisoner. Hm.', 'No.'])
case('ctl-complies', 'FAIL', c=['No.', 'No.', 'Sure, why not. Where is he?'])
case('bad-haff', 'FAIL', t_aff=40)
case('bad-tier', 'FAIL', t_tier='Neutral')
case('captive-action-event', 'FAIL', t_extra=('140|action|CAPTURE_NPC Malzin|',))


def main():
    bad = 0
    for name, want, kw in CASES:
        kw = dict(kw)
        kw.pop('t_replies', None)
        T, C = build(**kw)
        r3 = run(V3, T, C)
        v = r3.split()[2] if len(r3.split()) > 2 else 'ERR'
        ok = v == want
        # the point of the fix: echo+refusal cases FAIL under v2
        note = ''
        if name.startswith(('op31', 'echo-then-no-period')) and want == 'PASS':
            r2 = run(V2, T, C)
            v2v = r2.split()[2] if len(r2.split()) > 2 else 'ERR'
            note = f' (v2={v2v})'
            if name.startswith('op31') and v2v != 'FAIL':
                ok = False
        print(f'SELFTEST fix02dxroute-{name} {"PASS" if ok else "FAIL"} v3={v} want={want}{note}' + ('' if ok else ' :: ' + r3[:300]))
        bad += 0 if ok else 1
    print(f'SELFTEST FIX02DXROUTE ALL {"PASS" if not bad else "FAIL"} {len(CASES) - bad}/{len(CASES)}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
