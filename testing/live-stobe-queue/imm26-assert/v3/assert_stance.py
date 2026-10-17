#!/usr/bin/env python3
"""IMM-16-bx asserter v3 (imm26-fix16bx).  NEW file; v2/assert_stance.py and v2/imm26_lib.py are NOT edited (the lib is imported from v2).
Usage (same argv as v2):  assert_stance.py 16-bx --target R1 R2 R3 --ctl O1 O2 O3 --trait reserved   -> one RESULT line.

What changed against v2, and why (evidence: 3 replicates on 4080-i4, rows/16-bx-rep1..3):
  1. reply_of() in v2 joined EVERY NPC chat row in the bundle.  The bundle window also holds (a) Cind's native NPC-to-NPC talk with the control NPC
     ("(talking to: Malzin)", status `cancelled` once the player speaks) and (b) the control NPC's lines to Cind.  R1 therefore had 194/241/180 "words".
     v3 counts only the reply to the player's turn: chat rows AFTER the player's last inputtext row, speaker not the player, addressed to the player
     ("(talking to: Shay)"), status not `cancelled`.  Several utterances addressed to the player in that turn are still all counted (one reply = one LLM answer).
  2. ctl_friendly_words in v2 = OPEN word or "!".  A friendly outgoing answer to "how are you?" ("Still breathing ... What about you?") has neither.
     v3: friendly = (OPEN word or "!" or engagement with the player: reciprocal question / offer of help / concern) AND no hostile/cold wording
     (HOSTILE_V3).  A cold one-word answer, or a hostile answer that happens to contain "friend", still FAILS.
  3. (imm26-fix16bxengage) ENGAGE widened: 'how about you', 'you tell me', 'your turn', "what's the story", 'what happened', 'you look (like you|tired|rough|...)'
     -> real i4 op21 reps 2/3 control replies ("...what's the story?", "You look like you've had a rougher night than me") were false negatives. Hostile wording still vetoes.
Everything else (trait, tier, gush, exclamation, parrot, 3..40 words, pairwise similarity, foreign action, tier of control, give/gift, inventory) is the v2 logic unchanged."""
import os
import re
import sys

V2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'v2')
sys.path.insert(0, V2)
from imm26_lib import *  # noqa: E402,F401

ENGAGE = re.compile(r"(what about you|and you\b|\byou\?|how('?s| is| are) (the |your )|what('?s| is) on your mind|what brings you|"
                    r"need a hand|can i help|do you need|you hurt|you all right|you okay|are you (ok|alright|hurt)|"
                    r"walk with you|glad|good to|pleased|nice to|welcome|"
                    # fix16bxengage: return questions / invitations to carry on the talk, and attention paid to the player's state
                    r"how about you|you tell me|your turn|what('?s| is) (the|your) story|what happened|"
                    r"you look (like you|tired|rough|worn|beat|pale|well|hurt)|you'?ve got the look of)", re.I)
HOSTILE_V3 = re.compile(r"(state your (business|name)|what do you want|stay back|keep (back|away|your)|back off|get lost|move along|"
                        r"i don'?t know you|who are you|your kind|enem(y|ies)|not (a )?friend of|no friend of|leave me|piss off|"
                        r"i'?ll (kill|cut|gut)|or else|walk away|go away|don'?t (talk|speak) to me)", re.I)


def reply_to_player(b):
    """Text of the NPC's reply to the player's last chat turn in this bundle (see module docstring)."""
    evs = b.events()
    last_in = max([e[0] for e in evs if e[1] == 'inputtext'] or [-1])
    out = []
    for eid, t, d, st in evs:
        if t != 'chat' or eid <= last_in or st.strip().lower() == 'cancelled':
            continue
        m = re.match(r'\s*([^:]+?):\s*(.*?)\s*\(talking to:\s*([^)]*)\)\s*$', d)
        if not m:
            continue
        spk, txt, to = m.group(1), m.group(2), m.group(3)
        if spk.strip().lower() in PLAYER_NAMES or to.strip().split(' ')[0].lower() not in PLAYER_NAMES:
            continue
        out.append(txt)
    return ' '.join(out)


def friendly_v3(rep):
    if HOSTILE_V3.search(rep):
        return False
    return bool(OPEN.search(rep)) or rep.count('!') >= 1 or bool(ENGAGE.search(rep))


def row_16bx(a, res):
    T, C = [Bundle(d) for d in a['--target']], [Bundle(d) for d in a['--ctl']]
    trait = (a['--trait'] or 'reserved').lower()
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    reps = []
    for b in T:
        ins, rep = (b.inputs() or [''])[-1], reply_to_player(b)
        reps.append(rep)
        res.check(f'{b.name}:trait_in_prompt', trait in b.prompt.lower(), trait)
        res.check(f'{b.name}:tier_warm', b.stance()[1] in ('Fond', 'Warm', 'Friendly', 'Devoted'), b.stance()[1])
        res.check(f'{b.name}:no_gush_words', not GUSH.search(rep), GUSH.search(rep).group(0) if GUSH.search(rep) else '')
        res.check(f'{b.name}:exclaim<=1', rep.count('!') <= 1, rep.count('!'))
        res.check(f'{b.name}:not_parrot', similar(rep, ins) < .85, round(similar(rep, ins), 2))
        res.check(f'{b.name}:words 3..40', 3 <= len(rep.split()) <= 40, len(rep.split()))
        res.check(f'{b.name}:no_foreign_action', not b.foreign_actions(), b.foreign_actions())
    pair = [similar(x, y) for i, x in enumerate(reps) for y in reps[i + 1:]]
    res.check('replies_not_canned(pair<0.8)', all(p < .8 for p in pair), [round(p, 2) for p in pair])
    for b in C:
        rep = reply_to_player(b)
        res.check(f'{b.name}:ctl_tier_not_fond', b.stance()[1] not in ('Fond', 'Devoted'), b.stance()[1])
        res.check(f'{b.name}:ctl_no_give_action', not any(re.search(r'give|gift|trade', x, re.I) for x in b.foreign_actions()), '')
        before, after = res.need(os.path.join(b.dir, 'inv_before.txt')), res.need(os.path.join(b.dir, 'inv_after.txt'))
        if before is not None and after is not None:
            norm = lambda t: sorted(l.strip() for l in t.splitlines() if l.strip())
            res.check(f'{b.name}:ctl_inv_unchanged', norm(before) == norm(after), '')
        res.check(f'{b.name}:ctl_friendly_words', friendly_v3(rep), rep[:40])


if __name__ == '__main__':
    pos, a = parse_args(sys.argv[1:], ('--target', '--ctl'), ('--trait',))
    if not pos or pos[0] != '16-bx':
        raise SystemExit('usage: assert_stance.py 16-bx --target R1 R2 R3 --ctl O1 O2 O3 --trait reserved   (v3 handles 16-bx only)')
    res = Result('IMM-16-bx', a['--lenient'])
    row_16bx(a, res)
    sys.exit(res.emit())
