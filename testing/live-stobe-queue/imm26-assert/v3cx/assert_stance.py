#!/usr/bin/env python3
"""IMM-01-cx asserter v3cx (imm26-fix01cx).  NEW file; v2/assert_stance.py, v2/imm26_lib.py and v3/ are NOT edited (lib imported from v2, reply_to_player from v3).
Usage (same argv as v2):  assert_stance.py 01-cx --target H1 H2 H3 --ctl A1 A2 A3 [--hostile-rel -50 --allied-rel 50]  -> one RESULT line.

Why (evidence: 3 replicates on 4080-i3 op30 + sfY + 5090 op32, ~60 hostile/allied samples): v2 decided hostile_guarded with GUARDED.search(opening_sentence(first chat row)).
  (1) GUARDED is a short generic word list ("no|not|don't|what do you want|keep back|...").  Too NARROW for hostile: it misses the guarded idioms the model really uses:
      "keep your distance", "keep your hands where I can see them", "state your business", "say what you want", "move along", "Day's only good if you keep breathing",
      "Either you're new, or you're bait", "you're not one of mine", "we won't have a problem", "If you're looking to get chained".
  (2) Too BROAD for allied: bare "no|not|don't" flags friendly text ("Not much of one yet, but I'll take it", "I don't hand them out for free" from an allied trader).
  (3) Only the opening sentence of the FIRST chat row was judged, but the unfriendly part is often the next sentence/row ("Day's only good if you keep breathing through it. What do you want?").
  The replies were checked by hand (all savA/savB runs): they ARE guarded; the allied ones are not.  v2 also let any OPEN word rescue a guarded allied reply.

v3cx definition, applied to the NPC's REPLY TO THE PLAYER'S TURN (chat rows after the last inputtext, addressed to the player, not cancelled; all utterances of that turn):
  guarded(reply) = reply has >= 3 words AND matches >= 1 GUARD marker (below) AND matches no WARM marker.
  GUARD markers (content, not mood words): KEEP_OFF (keep your distance / keep your hands where I can see / stay back / step aside / move along / back off / keep walking /
  don't linger), STRANGER_DISTRUST (I don't know you / don't care to / rather keep it that way / not in the habit of chatting with strangers / don't hand out my name /
  who's asking / you're bait / count exits / Don't read more into it / that's enough for you to know / only answer you get / you're not one of mine / not exactly friends),
  DEMAND (what do you want / state your business / say what you want|need / say your piece / keep your questions short / Day's only good if ...), THREAT (chained / won't have a
  problem / give me a reason / or else), HOSTILE_LABEL (enemy / your kind).
  WARM markers (welcome / glad to / nice to / pleased to / well met / happy to / good to see / my friend / how can I help) make a reply NOT guarded: a hostile greeting that
  welcomes the player is open, even if it also contains a stiff phrase.
Row checks (all v2 checks kept unchanged): samples, distinct utterances, known_relationship false, not in combat, faction_rel thresholds, hostile: enemy line + Opening rule +
  first sentence not COOP; allied: no enemy line + share/allied line.  Changed:
  hostile_guarded>=2/3        : guarded(reply) for >= 2 of 3 hostile samples (was GUARDED on the first sentence).
  allied_not_guarded>=2/3     : reply present (>= 3 words) AND NOT guarded(reply) for >= 2 of 3 allied samples (v2 let an OPEN word rescue a guarded allied reply; v3cx does not).
  hostile_not_open            : no hostile sample carries a WARM marker (informational gate: a welcoming hostile reply fails even when the other two are guarded).
  --strict-opening (opt-in, not used by the rerun command): ALSO gate on the row text's literal reading, >= 2/3 opening sentences (v2 opening_sentence: first full sentence, >= 3 words) guarded by the same markers.
  Informational (no gate unless --strict-opening, in the RESULT line): opening_guarded = how many hostile samples are guarded in their FIRST sentence by the same markers.
Nothing is weakened for the allied/neutral case; a hostile reply that is open, curt-but-friendly ("Morning."), empty or neutral is NOT guarded and the row FAILs."""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'v2'))
from imm26_lib import *  # noqa: E402,F401


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, rel))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


reply_to_player = _load('_v3_stance', '../v3/assert_stance.py').reply_to_player
_v2 = _load('_v2_stance', '../v2/assert_stance.py')   # also installs v2's opening_sentence on Bundle.first_sentence (COOP check unchanged)
opening_sentence = _v2.opening_sentence

I = re.I
GUARD = {
    'KEEP_OFF': re.compile(r"keep (your|a) distance|keep (back|away|walking)\b|hands where i can see|stay (back|away|clear)|step aside|move along|back off|get lost|"
                           r"don'?t linger|keep your (distance|hands)", I),
    'STRANGER_DISTRUST': re.compile(r"(i )?don'?t (much )?know you|don'?t know you|don'?t (much )?care to|rather keep it that way|(not|never) in the habit of (chatting|talking)|"
                                    r"don'?t (hand|give) (out )?(those|my name|names?)|don'?t settle into conversation|who'?s asking|you'?re bait|"
                                    r"count(ed)? (the |my )?exits|don'?t read more into|(that'?s|it'?s) (enough|all) (for you|you need)|only (answer|one|part) .{0,40}(get|matters|owed)|"
                                    r"not one of (mine|ours)|not exactly friends|aren'?t (exactly )?friends|don'?t have anything for you|before i say anything else|"
                                    r"a thing you earn|decide if it'?s worth my time", I),
    'DEMAND': re.compile(r"what do you want|state (your|it)\b|say what you (want|need)|say your (piece|business)|keep your questions short|"
                         r"day'?s (only )?good if|which is it", I),
    'THREAT': re.compile(r"chained|won'?t have a problem|give me a reason|\bor else\b|keep standing there", I),
    'HOSTILE_LABEL': re.compile(r"\benem(y|ies)\b|your kind", I),
}
WARM = re.compile(r"\bwelcome\b|glad to|nice to|pleased to|well met|happy to|good to see|my friend|how can i help|what can i do for you", I)


def guard_markers(text):
    """Names of the GUARD marker groups that match `text` (empty list = no guarded wording)."""
    return [k for k, rx in GUARD.items() if rx.search(text or '')]


def is_guarded(text):
    t = (text or '').strip()
    return len(t.split()) >= 3 and bool(guard_markers(t)) and not WARM.search(t)


def row_01cx(a, res):
    T, C = [Bundle(d) for d in a['--target']], [Bundle(d) for d in a['--ctl']]
    hostile, allied = int(a['--hostile-rel'] or -50), int(a['--allied-rel'] or 50)
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    distinct_inputs(C, 3, res)
    for grp, lab in ((T, 'hostile'), (C, 'allied')):
        for b in grp:
            res.check(f'{b.name}:known_relationship_false', 'known_relationship":false' in b.prompt.replace('&quot;', '"').replace(' ', '') or 'known_relationship:false' in b.prompt.replace('&quot;', '').replace(' ', ''), '')
            res.check(f'{b.name}:not_in_combat', not b.listener_in_combat(), '')
            t = res.need(os.path.join(b.dir, 'faction_rel.txt'), f'{b.name}/faction_rel.txt')
            if t is not None:
                v = num_file(t, r'rel\w*[^\d-]*(-?\d+)')
                res.check(f'{b.name}:faction_rel', v is not None and (v <= hostile if lab == 'hostile' else v >= allied), v)
    for b in T:
        res.check(f'{b.name}:first_contact_enemy_line', bool(re.search(r'First contact, no personal history:.*enem', b.prompt)), '')
        res.check(f'{b.name}:opening_rule', 'Opening rule' in b.prompt, '')
        res.check(f'{b.name}:no_coop_first_sentence', not COOP.search(b.first_sentence()), b.first_sentence()[:50])
    for b in C:
        res.check(f'{b.name}:no_enemy_line', not re.search(r'First contact, no personal history:.*enem', b.prompt), '')
        res.check(f'{b.name}:share_or_allied_line', bool(re.search(r'share a faction|allied|friendly faction', b.prompt, re.I)), '')
    hrep = [reply_to_player(b) for b in T]
    arep = [reply_to_player(b) for b in C]
    hg = [is_guarded(r) for r in hrep]
    res.check('hostile_guarded>=2/3', sum(hg) >= 2, '/'.join(','.join(guard_markers(r)) or 'none' for r in hrep) if sum(hg) < 2 else f'{sum(hg)}/3')
    res.check('hostile_not_open', not any(WARM.search(r) for r in hrep), [b.name for b, r in zip(T, hrep) if WARM.search(r)])
    ag = [is_guarded(r) for r in arep]
    present = [len(r.split()) >= 3 for r in arep]
    res.check('allied_not_guarded>=2/3', sum(p and not g for p, g in zip(present, ag)) >= 2,
              f'guarded={[b.name for b, g in zip(C, ag) if g]} empty={[b.name for b, p in zip(C, present) if not p]}')
    og = sum(bool(guard_markers(opening_sentence(r))) and not WARM.search(opening_sentence(r)) for r in hrep)
    if a['--strict-opening']:
        res.check('opening_guarded>=2/3(strict)', og >= 2, f'{og}/{len(hrep)}')
    else:
        res.good.append('info:opening_guarded=%d/%d' % (og, len(hrep)))


if __name__ == '__main__':
    pos, a = parse_args(sys.argv[1:], ('--target', '--ctl'), ('--hostile-rel', '--allied-rel'), ('--lenient', '--strict-opening'))
    if not pos or pos[0] != '01-cx':
        raise SystemExit('usage: assert_stance.py 01-cx --target H1 H2 H3 --ctl A1 A2 A3 [--hostile-rel -50 --allied-rel 50]   (v3cx handles 01-cx only)')
    res = Result('IMM-01-cx', a['--lenient'])
    row_01cx(a, res)
    sys.exit(res.emit())
