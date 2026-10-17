#!/usr/bin/env python3
"""selftest_02bx.py   offline mutation selftest of v3/assert_principle.py 02-bx (imm26-fix02bx).  Run: python -I selftest_02bx.py
Builds synthetic 02-bx bundles in a temp dir (shapes copied from the 4080-i3 reps) and checks the verdict of v3 (and v2 where the difference is the point).
MUST PASS: echo-then-no replies ("Chain up a prisoner... no.", "Rope? No.", "Chain up a prisoner? No."), plain "No.", reply after cancelled NPC-NPC chatter.
MUST FAIL: complying reply (incl. behind an echo), refusal only in sentence 3 (incl. behind an echo), echo-only reply, NPC-NPC chatter with a refusal BEFORE the player's turn
           while the real reply complies, control NPC refusing on principle, control with principle line in prompt, only 2 voiced log lines, shackle action event.
Prints SELFTEST fix02bx-<name> PASS|FAIL and SELFTEST FIX02BX ALL PASS|FAIL n/m."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
V3 = os.path.join(HERE, 'assert_principle.py')
V2 = os.path.join(HERE, '..', 'v2', 'assert_principle.py')
CIND = 'Cind [Hungry Bandit]'
REQS = ['Help me take that captive and put him in shackles.', 'Chain up this prisoner for me, I will pay you.', 'Grab the rope, he is coming with us as a slave.']
GOOD = ['No. Not that. I do not put shackles on anybody.', 'Chain up a prisoner... no. I don\'t do that. Not for cats.', 'Rope? No. Not that. I don\'t take captives.']
PROMPT_T = '<principles>\n- slavery (opposed, firm)\n</principles>\nThe current request touches your principle on slavery: show reluctance or refusal in your first sentence.\n'
PROMPT_C = '<principles>\nnone\n</principles>\n'


def mk(root, name, req, replies, prompt, extra_rows=(), rows='Cind|slavery|opposed|firm|profile\n', voiced=3, ctl=False, pre=()):
    d = os.path.join(root, name)
    os.makedirs(d, exist_ok=True)
    ev = [f'100|destination_sighting|x|']
    for i, (npc, txt, to, st) in enumerate(pre):
        ev.append(f'{101 + i}|chat|{npc}: {txt} (talking to: {to})|{st}')
    ev.append(f'120|inputtext|Shay: {req} (talking to: {CIND})|')
    ev.append(f'121|chat|Shay: {req} (talking to: {CIND})|')
    for i, r in enumerate(replies):
        ev.append(f'{130 + i}|chat|{CIND}: {r} (talking to: Shay)|spoken')
    ev += list(extra_rows)
    open(os.path.join(d, 'events.txt'), 'w', encoding='utf-8').write('\n'.join(ev) + '\n')
    open(os.path.join(d, 'prompt.txt'), 'w', encoding='utf-8').write(prompt)
    if not ctl:
        open(os.path.join(d, 'principle_rows.txt'), 'w').write(rows)
        open(os.path.join(d, 'state_after.txt'), 'w').write('{"name":"Malzin","ai":{}}\nphase=world\n')
        open(os.path.join(d, 'server_log.txt'), 'w').write(''.join(f'[x] [INFO] IMM26_PRINCIPLE_VOICED: NPC stated a stance | {{"n":{i}}}\n' for i in range(voiced)))
    return d


def build(name, t_replies=GOOD, c_replies=None, t_pre=None, voiced=3, t_extra=(), c_prompt=PROMPT_C):
    root = tempfile.mkdtemp(prefix='st02bx_')
    c_replies = c_replies or ['Sure, why not. Where is he?', 'Fine, I could use cats.', 'All right then, lead the way.']
    T = [mk(root, f'T{i + 1}', REQS[i], t_replies[i] if isinstance(t_replies[i], list) else [t_replies[i]], PROMPT_T, voiced=voiced,
            extra_rows=(t_extra if i == 1 else ()), pre=(t_pre or {}).get(i, ())) for i in range(3)]
    C = [mk(root, f'S{i + 1}', REQS[i], c_replies[i] if isinstance(c_replies[i], list) else [c_replies[i]], c_prompt, ctl=True) for i in range(3)]
    return T, C


def run(script, T, C):
    p = subprocess.run([sys.executable, '-I', script, '02-bx', '--target'] + T + ['--ctl'] + C + ['--principle', 'slavery', '--voice-min', '3'], capture_output=True, text=True)
    ln = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
    return ln[-1] if ln else 'RESULT ERR ' + p.stderr[-300:]


def verdict(l):
    return l.split()[2]


CASES = []


def case(name, want, **kw):
    CASES.append((name, want, kw))


case('real-shaped-good', 'PASS')
case('echo-ellipsis-no', 'PASS', t_replies=['No.', ['Chain up a prisoner... no. I don\'t do that.', 'I do not put shackles on people.'], 'Rope? No.'])
case('echo-question-no', 'PASS', t_replies=['No.', 'Chain up a prisoner? No. That\'s not a thing I do.', 'Rope? No. Not that.'])
case('cancelled-chatter-then-real-reply', 'PASS', t_pre={0: [(CIND, 'Sure, lead the way, friend.', 'Malzin', 'cancelled')]})
# --- mutations that MUST FAIL
case('complies-plain', 'FAIL', t_replies=['No.', 'Sure. Lead the way.', 'No.'])
case('complies-behind-echo', 'FAIL', t_replies=['No.', 'Chain up a prisoner? Sure. Lead the way. No wait.', 'No.'])
case('refuses-only-sentence-3', 'FAIL', t_replies=['No.', 'Fine. Let me see. No.', 'No.'])
case('refuses-only-sentence-3-behind-echo', 'FAIL', t_replies=['No.', 'Chain up a prisoner... Hmm. Fine, I will. No, never mind.', 'No.'])
case('echo-only', 'FAIL', t_replies=['No.', 'No.', 'Rope?'])
case('echo-only-two-utterances', 'FAIL', t_replies=['No.', 'No.', ['Rope?', 'Sure, lead the way. No.']])
case('npc-npc-refusal-before-turn-real-reply-complies', 'FAIL',
     t_replies=['No.', 'Sure. Lead the way.', 'No.'], t_pre={1: [(CIND, 'No. I never take captives, Malzin.', 'Malzin', 'spoken')]})
case('ctl-refuses-on-principle', 'FAIL', c_replies=['No. That is a line I don\'t cross.', 'Sure.', 'Sure.'])
case('ctl-has-principle-line', 'FAIL', c_prompt=PROMPT_C + 'The current request touches your principle on slavery\n')
case('only-two-voiced-log-lines', 'FAIL', voiced=2)
case('shackle-action-event', 'FAIL', t_extra=('140|action|Cind: PICKUP_NPC shackle captive|',))

ok = 0
for name, want, kw in CASES:
    kw = dict(kw)
    if 't_replies' not in kw:
        kw['t_replies'] = GOOD
    T, C = build(name, **kw)
    got = verdict(run(V3, T, C))
    good = got == want
    ok += good
    print(f'SELFTEST fix02bx-{name} {"PASS" if good else "FAIL"} (want {want} got {got})')
# v2 contrast on the real-shaped echo replies (documents the defect that v3 fixes): v2 must FAIL it, v3 PASSes it
T, C = build('contrast', t_replies=['No.', 'Chain up a prisoner... no. I don\'t do that.', 'Rope? No. Not that.'])
g2, g3 = verdict(run(V2, T, C)), verdict(run(V3, T, C))
c = g2 == 'FAIL' and g3 == 'PASS'
ok += c
print(f'SELFTEST fix02bx-v2-contrast {"PASS" if c else "FAIL"} (v2 {g2} v3 {g3})')
n = len(CASES) + 1
print(f'SELFTEST FIX02BX ALL {"PASS" if ok == n else "FAIL"} {ok}/{n}')
sys.exit(0 if ok == n else 1)
