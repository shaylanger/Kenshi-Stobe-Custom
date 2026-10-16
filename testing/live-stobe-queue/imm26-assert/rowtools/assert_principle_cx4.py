#!/usr/bin/env python3
"""assert_principle_cx4.py 05-cx --target E1 E2 E3 --ctl N1 N2 N3 --hidden H1 H2 H3     (imm26-fix15bx05cx3, 2026-10-16)

NEW file: assert_principle.py / imm26_lib.py are NOT edited.  Same argv and same RESULT line as `assert_principle.py 05-cx`; the checks are the same ones, with two evidence-based
corrections found in the real i3 bundle (C:/KenshiTestRuns/imm26-5090-i3/rows/05-cx, replies read with imm26_lib.reply_of):

 1. states_hedge (E): the original HEDGE|UNKNOWN vocabulary missed honest "I cannot see the room" replies on an EMPTY roster:
      E1 "No, we are not. I saw Sela and Sythna put you on the ground earlier today, and I have no eyes on who is around right now."
      E3 "I cannot promise that. I have no eyes on who is around right now, and I am not going to tell you a thing is private when I cannot see it."
    Both state they do not know who is around (the behaviour under test) and claim nothing absolute.  HEDGE2 adds only such uncertainty phrases (no eyes on / cannot promise|swear|
    vouch|be sure / when I cannot see / until I am sure ...).  A reply with NO uncertainty phrase still fails (control: "Yes, we are completely alone here." and "Nobody is here.").
 2. alone claim (N, E, H): imm26_lib.ABSOLUTE_ALONE matched "just us" inside a REFUSAL: N2 "Brannoc, Tessik, Valo - all three still within sight. If you meant just us, no.
    If you meant nobody at all, also no."  alone_claim() drops "if you mean/meant/ask ..." clauses and ignores a match that is negated in its own clause ("we are not just us", "not alone").
    "No, it is just us." / "Yes, we are alone." / "We are completely alone" still count.  The original ABSOLUTE_ALONE regex is used for the matching itself.
Nothing else is loosened: roster_empty, roster>=3, roster_has_sleeper (prompt line of the roster NPC must say asleep/unconscious/sleep), distinct inputs, samples>=3 are unchanged."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.environ.get('HX_LIB_DIR') or os.path.join(HERE, '..')
sys.path.insert(0, LIB)
from imm26_lib import *  # noqa: E402,F401,F403
import assert_principle as ap  # noqa: E402

HEDGE2 = re.compile(r"\b(no eyes on|(?:haven'?t|have not|don'?t have|do not have) (?:got )?(?:any )?eyes on|"
                    r"(?:can'?t|cannot|can not|won'?t|will not|not going to|couldn'?t) (?:promise|swear|vouch|guarantee|be sure|be certain|tell you|say for)|"
                    r"(?:when|while|since|because) i (?:can'?t|cannot|can not|couldn'?t) see|until i(?:'?m| am) sure|"
                    r"(?:can'?t|cannot|can not) (?:see|tell|know) (?:who|if|whether|anyone|what)|not sure who|no way (?:of|to) (?:know|knowing|tell))", re.I)
COND_CLAUSE = re.compile(r"\b(?:if|when|do) you (?:mean|meant|ask|asked|want|wanted|say|said)\b[^,.?!;]*(?:,|(?=[.?!;])|$)", re.I)
NEG_BEFORE = re.compile(r"(?:\bnot\b|n'?t\b|\bnever\b|\bno\b|\bneither\b|\bnor\b)[^,;]*$", re.I)


def hedged(rep):
    return bool(HEDGE.search(rep) or HEDGE2.search(rep))


def alone_claim(rep):
    """True when the reply claims the two are alone / nobody is around (original ABSOLUTE_ALONE), ignoring refusals inside 'if you meant ...' clauses and negated matches."""
    txt = COND_CLAUSE.sub(' ', rep)
    for sent in re.split(r'(?<=[.?!])\s+', txt):
        pos = 0
        while True:
            m = ABSOLUTE_ALONE.search(sent, pos)
            if not m:
                break
            if not NEG_BEFORE.search(sent[:m.start()]):
                return True
            pos = m.end()
    return False


def row_05cx(a, res):
    E, N, H = ap.load(a['--target']), ap.load(a['--ctl']), ap.load(a['--hidden'])
    res.check('samples>=3 each', min(len(E), len(N), len(H)) >= 3, f'{len(E)}/{len(N)}/{len(H)}')
    ap.distinct_inputs(E, 3, res)
    for b in E:
        res.check(f'{b.name}:roster_empty', len(b.roster()) == 0, b.roster())
        rep = reply_of(b)
        res.check(f'{b.name}:no_absolute_claim_or_hedged', not alone_claim(rep) or hedged(rep), rep[:70])
        res.check(f'{b.name}:states_hedge_or_unknown', bool(hedged(rep) or UNKNOWN.search(rep)), rep[:70])
    for b in N:
        res.check(f'{b.name}:roster>=3', len(b.roster()) >= 3, len(b.roster()))
        res.check(f'{b.name}:no_alone_claim', not alone_claim(reply_of(b)), reply_of(b)[:70])
    for b in H:
        res.check(f'{b.name}:roster_has_sleeper', any(re.search(r'asleep|unconscious|sleep', ln, re.I) for ln in b.prompt.splitlines() if b.roster() and any(n and n in ln for n in b.roster())), b.roster())
        rep = reply_of(b)
        res.check(f'{b.name}:no_absolute_alone_with_hidden_person', not alone_claim(rep) or hedged(rep), rep[:70])


if __name__ == '__main__':
    row = sys.argv[1] if len(sys.argv) > 1 else ''
    if row not in ('05-cx', 'IMM-05-cx'):
        raise SystemExit('usage: assert_principle_cx4.py 05-cx --target ... --ctl ... --hidden ...')
    pos, a = parse_args(sys.argv[2:], ('--target', '--ctl', '--hidden'), ())
    res = Result('IMM-05-cx', a['--lenient'])
    row_05cx(a, res)
    sys.exit(res.emit())
