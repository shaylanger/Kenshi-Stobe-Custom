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
  fix16bx2: did-you-walk-away-clean / what-was-that-about / you-ok PASS; walk-away-now / or-walk-away / hostile+question / refusal / empty FAIL; real op22 reps PASS
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
    # --- imm26-fix16bxengage: widened ENGAGE ---
    pos = {'how-about-you': 'Alive enough. How about you, traveler.', 'you-tell-me': 'Same as ever, hauling packs. You tell me.',
           'your-turn': 'Still upright. Your turn.', 'whats-the-story': "Still breathing, though you look worse than me - what's the story?",
           'you-look-like': "Fed and dry. You look like you've had a rougher night than me, though.", 'what-happened': 'Not much here. What happened to your arm?'}
    for k, t in pos.items():
        d = mut('p-' + k); replace_reply(d, 'O2', [t], npc='Malzin'); l = run(d); chk('mut-engage-' + k, verdict(l) == 'PASS', l[:90])
    neg = {'curt-no-question': 'Alive, fed, and not bleeding.', 'hostile-with-marker': 'How about you leave. State your business, stay back.',
           'hostile-you-look': 'You look like trouble, so back off and go away.', 'empty': ''}
    for k, t in neg.items():
        d = mut('n-' + k); replace_reply(d, 'O2', [t] if t else [], npc='Malzin'); l = run(d); chk('mut-engage-neg-' + k, verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l, l[:90])
    d = mut('n-longtarget'); replace_reply(d, 'R2', ['I am doing well and I thought a great deal about where we last parted and what the road has been like since then, with all the weather and the bandits and the long dull marches between towns, so there is a lot to say about it all. How about you?'])
    l = run(d); chk('mut-engage-neg-long-target-still-fails', verdict(l) == 'FAIL' and 'R2:words 3..40!' in l)
    # --- imm26-fix16bx2: narrowed 'walk away' veto + generic return/curiosity/concern questions ---
    pos2 = {'did-walk-away-clean': 'Alive and fed. Saw Zelvia swing at you - did you walk away clean?',
            'did-you-get-away': 'Not bad at all. Did you get away from her in one piece?',
            'what-was-that-about': "You're still standing, I see. What was that about?",
            'whats-that-about': 'Fed and dry. What is that about, with the swords out?',
            'whats-going-on': "Breathing. What's going on with the guards today?",
            'you-ok': 'Breathing, same as ever. You ok?',
            'are-you-alright': 'Fed and in one piece. Are you alright after that?'}
    for k, t in pos2.items():
        d = mut('p2-' + k); replace_reply(d, 'O2', [t], npc='Malzin'); l = run(d); chk('mut-fix2-' + k, verdict(l) == 'PASS', l[:90])
    neg2 = {'walk-away-now': 'Just walk away now.', 'or-walk-away': 'Pay up or walk away, traveler.', 'walk-away-bare': 'Walk away. What was that about?',
            'did-you-walk-away-now': 'Did you walk away now or what, stranger, back off.', 'what-about-hostile': 'What was that about? Get lost.',
            'refusal': 'I would rather not discuss it.', 'cold-what': 'Whatever.', 'empty': ''}
    for k, t in neg2.items():
        d = mut('n2-' + k); replace_reply(d, 'O2', [t] if t else [], npc='Malzin'); l = run(d); chk('mut-fix2-neg-' + k, verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l, l[:90])
    d = mut('n2-longtarget'); replace_reply(d, 'R2', ['I am doing well and I thought a great deal about where we last parted and what the road has been like since then, with all the weather and the bandits and the long dull marches between towns, so there is a lot to say about it all. What was that about? You ok?'])
    l = run(d); chk('mut-fix2-neg-long-target-still-fails', verdict(l) == 'FAIL' and 'R2:words 3..40!' in l)
    # --- imm26-fix16bxctl: plain conversational control reply passes; refusal/hostile/curt still fail ---
    posc = {'op32-still-breathing': "Still breathing, still working - that's about the best anyone can claim out here.",
            'plain-sentence': 'Getting by, same as everyone out on this road, and the dust is not as bad as last week.'}
    for k, t in posc.items():
        d = mut('pc-' + k); replace_reply(d, 'O2', [t], npc='Malzin'); l = run(d); chk('mut-ctl-' + k, verdict(l) == 'PASS', l[:90])
    negc = {'long-refusal': 'I would rather not discuss it with someone I have only just met on this road.',
            'long-none-of-your': 'What I do out here is none of your business, and that is all I plan to say about it.',
            'long-hostile': 'Keep your hands where I can see them and state your business before I lose my patience here.',
            'curt-still-fails': 'Alive, fed, and not bleeding.', 'short-whatever': 'Whatever, I am busy.'}
    for k, t in negc.items():
        d = mut('nc-' + k); replace_reply(d, 'O2', [t], npc='Malzin'); l = run(d); chk('mut-ctl-neg-' + k, verdict(l) == 'FAIL' and 'O2:ctl_friendly_words!' in l, l[:90])
    o32 = 'C:/KenshiTestRuns/agents/out/imm26-4080-i3op32/16bx-rep3'
    if os.path.isdir(o32):
        lo = run(o32); chk('real-op32rep3-passes', verdict(lo) == 'PASS' and 'ctl_friendly_words!' not in lo, lo[:90])
    # real op22 reps (copies of the failing i4 dirs): control must now pass ctl_friendly_words (whole row PASS)
    for r in (1, 2):
        o = os.path.join(ROOT, f'16-bx-op22rep{r}')
        if os.path.isdir(o):
            lo = run(o); chk(f'real-op22rep{r}-passes', verdict(lo) == 'PASS' and 'ctl_friendly_words!' not in lo, lo[:90])
    # real op21 reps (if present): rep1 fails only on length, rep2/3 pass
    o1 = os.path.join(ROOT, '16-bx-op21rep1')
    if os.path.isdir(o1):
        l1 = run(o1); chk('real-op21rep1-fails-on-length-only', verdict(l1) == 'FAIL' and 'ctl_friendly' not in l1.split('samples')[0] and 'R1:words 3..40!' in l1, l1[:90])
        for r in (2, 3):
            lr = run(os.path.join(ROOT, f'16-bx-op21rep{r}')); chk(f'real-op21rep{r}-passes', verdict(lr) == 'PASS', lr[:90])
    shutil.rmtree(tmp, ignore_errors=True)
    print(f'SELFTEST FIX16BX ALL {"PASS" if ok == n else "FAIL"} {ok}/{n}')
    return 0 if ok == n else 1


sys.exit(main())
