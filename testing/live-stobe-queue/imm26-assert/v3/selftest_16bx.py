#!/usr/bin/env python3
"""selftest_16bx.py [evidence-root]   offline selftest of v3/assert_stance.py 16-bx (imm26-fix16bx).  Run: python -I selftest_16bx.py
Part 1: the three real 4080-i4 replicate dirs (root/16-bx-rep1..3) -> prints each verdict (all judged by the same logic).
Part 2: mutations of rep1 (copied to a temp dir) that MUST FAIL or must NOT change the verdict:
  long-reply (target reply to the player > 40 words)         -> FAIL on words
  long-reply-split (3 utterances to the player, > 40 total)  -> FAIL on words (multi-utterance replies are still summed)
  gush / exclaim / parrot target                             -> FAIL
  hostile-ctl (control answers coldly/hostile)               -> FAIL on ctl_friendly_words
  hostile-with-friend ("no friend of mine, stay back")       -> FAIL on ctl_friendly_words
  cold-ctl ("Alive.")                                        -> FAIL on ctl_friendly_words
  ctl-gives-item (inv_after differs)                         -> FAIL
  noise-npc-npc (huge NPC-to-NPC monologue appended)         -> verdict unchanged (PASS)
  no-reply (all replies to the player removed)               -> FAIL (words 3..40, no fallback to NPC-NPC chat)
Prints SELFTEST fix16bx-<name> PASS|FAIL and SELFTEST FIX16BX ALL PASS|FAIL n/m."""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else 'C:/KenshiTestRuns/imm26-4080-i4/rows'
AS = os.path.join(HERE, 'assert_stance.py')


def run(d):
    a = [sys.executable, '-I', AS, '16-bx', '--target'] + [os.path.join(d, x) for x in ('R1', 'R2', 'R3')] + ['--ctl'] + [os.path.join(d, x) for x in ('O1', 'O2', 'O3')] + ['--trait', 'reserved']
    p = subprocess.run(a, capture_output=True, text=True)
    ln = [l for l in p.stdout.splitlines() if l.startswith('RESULT')]
    return ln[-1] if ln else 'NO-RESULT ' + p.stderr[-200:]


def verdict(l):
    return l.split()[2] if l.startswith('RESULT') else 'ERR'


def spoken(npc, txt, to, eid):
    return f'{eid}|chat|{npc}: {txt} (talking to: {to})|spoken\n'


def edit_events(d, lab, fn):
    p = os.path.join(d, lab, 'events.txt')
    lines = open(p, encoding='utf-8').read().splitlines(True)
    open(p, 'w', encoding='utf-8').write(''.join(fn(lines)))


def replace_reply(d, lab, texts, to='Shay', npc=None):
    """drop every `spoken`/`pending` NPC chat row addressed to the player and put `texts` in its place (after the inputtext row)."""
    def fn(lines):
        out, done = [], False
        for l in lines:
            m = re.match(r'(\d+)\|chat\|([^:]+): .*\(talking to: ([^)]*)\)\|(spoken|pending)', l)
            if m and m.group(3).split(' ')[0] == to and m.group(2).split(' ')[0].lower() not in ('shay', 'kint'):
                npc_n = npc or m.group(2)
                if not done:
                    done = True
                    for i, t in enumerate(texts):
                        out.append(spoken(npc_n, t, to, int(m.group(1)) + i * 0))
                continue
            out.append(l)
        return out
    edit_events(d, lab, fn)


def main():
    n = ok = 0

    def chk(name, cond, extra=''):
        nonlocal n, ok
        n += 1
        ok += bool(cond)
        print(f'SELFTEST fix16bx-{name} {"PASS" if cond else "FAIL"} {extra}'[:400])

    base = os.path.join(ROOT, '16-bx-rep1')
    if not os.path.isdir(base):
        print('evidence dir missing', base); return 2
    for r in (1, 2, 3):
        l = run(os.path.join(ROOT, f'16-bx-rep{r}'))
        print(f'REAL rep{r}: {verdict(l)} ' + ('; '.join(re.findall(r'[A-Z]\d:[a-z_ ]*[<>.\d]*!?[^;]*!', l)) or ''))
    chk('real-rep1', verdict(run(base)) == 'PASS')
    chk('real-rep2', verdict(run(os.path.join(ROOT, '16-bx-rep2'))) == 'PASS')
    l3 = run(os.path.join(ROOT, '16-bx-rep3'))
    chk('real-rep3-fails-only-on-R3-46-words', verdict(l3) == 'FAIL' and re.findall(r'(\w+:[^;]*?)!', l3.split('samples')[0]) == ['R3:words 3..40'], l3[:90])
    tmp = tempfile.mkdtemp(prefix='fix16bx-')

    def mut(name):
        d = os.path.join(tmp, name)
        shutil.copytree(base, d)
        return d

    d = mut('long'); replace_reply(d, 'R2', ['I am doing well and I thought a great deal about where we last parted and what the road has been like since then, with all the weather and the bandits and the long dull marches between towns, so there is a lot to say about it all.'])
    l = run(d); chk('mut-long-reply', verdict(l) == 'FAIL' and 'R2:words 3..40!' in l)
    d = mut('split'); replace_reply(d, 'R2', ['Alive and well, thank you for asking me that.', 'The road has been long and dull and the weather turned on me twice this week alone.', 'I kept my gear in order and my wits about me the whole way through it.', 'You look well yourself, friend, and I am pleased to see you here.'])
    l = run(d); chk('mut-long-reply-split-over-4-utterances', verdict(l) == 'FAIL' and 'R2:words 3..40!' in l)
    d = mut('gush'); replace_reply(d, 'R2', ['I am delighted, truly thrilled to see you.']); l = run(d); chk('mut-gush', verdict(l) == 'FAIL' and 'R2:no_gush_words!' in l)
    d = mut('excl'); replace_reply(d, 'R2', ['Hello there! Good to see you! Well met!']); l = run(d); chk('mut-exclaim', verdict(l) == 'FAIL' and 'R2:exclaim<=1!' in l)
    d = mut('parrot'); replace_reply(d, 'R2', ['It has been a while, how are you?']); l = run(d); chk('mut-parrot', verdict(l) == 'FAIL' and 'R2:not_parrot!' in l)
    d = mut('hostile'); replace_reply(d, 'O2', ['State your business. I do not know you, so keep back.'], npc='Malzin')
    l = run(d); chk('mut-hostile-ctl', verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l)
    d = mut('hostfriend'); replace_reply(d, 'O2', ['You are no friend of mine, so stay back and leave me be.'], npc='Malzin')
    l = run(d); chk('mut-hostile-with-friend-word', verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l)
    d = mut('cold'); replace_reply(d, 'O2', ['Alive.'], npc='Malzin'); l = run(d); chk('mut-cold-ctl', verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l)
    d = mut('gives'); open(os.path.join(d, 'O2', 'inv_after.txt'), 'a').write('Dried Meat\n'); l = run(d); chk('mut-ctl-gives-item', verdict(l) == 'FAIL' and 'O2:ctl_inv_unchanged!' in l)
    d = mut('noise')
    edit_events(d, 'R1', lambda ls: ls + [spoken('Cind [Hungry Bandit]', 'word ' * 120, 'Malzin', 99999 + i) for i in range(3)] + [f'99990|chat|Cind [Hungry Bandit]: ignored words go here and here and here (talking to: Shay)|cancelled\n'])
    l = run(d); chk('mut-npc-npc-noise-and-cancelled-ignored', verdict(l) == 'PASS')
    d = mut('noreply')
    edit_events(d, 'R2', lambda ls: [x for x in ls if not re.search(r'\(talking to: Shay\)\|(spoken|pending)', x)])
    l = run(d); chk('mut-no-reply-to-player', verdict(l) == 'FAIL' and 'R2:words 3..40!' in l)
    shutil.rmtree(tmp, ignore_errors=True)
    print(f'SELFTEST FIX16BX ALL {"PASS" if ok == n else "FAIL"} {ok}/{n}')
    return 0 if ok == n else 1


sys.exit(main())
