#!/usr/bin/env python3
"""Stance/tone family: IMM-01-bx, IMM-01-cx, IMM-16-bx.  Prints one RESULT line.

Usage (each --flag takes the sample bundle dirs; every dir = one utterance):
  assert_stance.py 01-bx --target D1 D2 D3 --ctl-nohist C1 C2 C3 --ctl-pos P1 P2 P3 --seed "line1|line2|line3" [--aff-target -80 --aff-pos 60] [--lenient]
      target   = aff -80 AFTER seeded coop history (3 distinct utterances): tier Hostile, history in prompt, no action, not cooperative.
      ctl-nohist = same -80, FRESH save, no history: same outcome (history is not what blocks the deal) and seed absent from prompt.
      ctl-pos  = +60 with the same history: tier not Hostile, history present, >=2/3 first sentences not reluctant.
      Needs haff.txt in every dir (H-AFF read, contains `aff=<n>`).
  assert_stance.py 01-cx --target D1 D2 D3 --ctl D1 D2 D3 [--hostile-rel -50 --allied-rel 50]
      target = hostile-faction stranger (no relationship entry), ctl = allied-faction stranger, neither in combat.
      Needs faction_rel.txt in each dir (`rel=<n>` = faction_relation_state listener->player faction).
  assert_stance.py 16-bx --target D1 D2 D3 --ctl C1 C2 C3 --trait reserved
      target = reserved NPC at +60, ctl = outgoing NPC at 0. Needs inv_before.txt + inv_after.txt in each ctl dir.
Pass criteria are in each row of NPC_IMMERSION_26_TESTS.md.
"""
import re
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imm26_lib import *


def aff_from_haff(b, res, want):
    t = res.need(os.path.join(b.dir, 'haff.txt'), f'{b.name}/haff.txt')
    if t is None:
        return
    m = re.search(r'aff\w*[^\d-]*(-?\d+)', t)
    res.check(f'{b.name}:haff', bool(m) and int(m.group(1)) == want, f'{m.group(1) if m else None}want{want}')


def row_01bx(a, res):
    seed = [s.strip() for s in (a['--seed'] or '').split('|') if s.strip()]
    res.check('seed_lines>=3', len(seed) >= 3, len(seed))
    aff_t, aff_p = int(a['--aff-target'] or -80), int(a['--aff-pos'] or 60)
    T, N, P = [Bundle(d) for d in a["--target"]], [Bundle(d) for d in a['--ctl-nohist']], [Bundle(d) for d in a['--ctl-pos']]
    res.check('samples>=3 each', min(len(T), len(N), len(P)) >= 3, f'{len(T)}/{len(N)}/{len(P)}')
    distinct_inputs(T, 3, res)
    for b in T + N:
        aff_from_haff(b, res, aff_t)
        res.check(f'{b.name}:tier=Hostile', b.stance()[1] == 'Hostile', b.stance()[1])
        res.check(f'{b.name}:prompt_aff', b.affinity_in_prompt() in (None, aff_t), b.affinity_in_prompt())
        res.check(f'{b.name}:no_foreign_action', not b.foreign_actions(), b.foreign_actions())
        res.check(f'{b.name}:no_agreement_row', not b.event_types('travel_agreement', 'activity_agreement'), '')
        rep = reply_of(b)
        res.check(f'{b.name}:not_coop', not COOP.search(b.first_sentence()), b.first_sentence()[:60])
        res.check(f'{b.name}:no_seed_echo', not any(similar(rep, s) > .6 or s.lower() in rep.lower() for s in seed), '')
    for b in T:
        res.check(f'{b.name}:history_in_prompt', any(s.lower()[:40] in b.prompt.lower() for s in seed), '')
    for b in N:
        res.check(f'{b.name}:no_history_in_prompt', not any(s.lower()[:40] in b.prompt.lower() for s in seed), '')
    res.check('target_reluctant>=2/3', sum(bool(RELUCTANT.search(b.first_sentence())) for b in T) >= 2, '')
    for b in P:
        aff_from_haff(b, res, aff_p)
        res.check(f'{b.name}:tier!=Hostile', b.stance()[1] not in (None, 'Hostile'), b.stance()[1])
        res.check(f'{b.name}:history_in_prompt', any(s.lower()[:40] in b.prompt.lower() for s in seed), '')
    res.check('pos_ctl_not_reluctant>=2/3', sum(not RELUCTANT.search(b.first_sentence()) for b in P) >= 2, '')


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
    res.check('hostile_guarded>=2/3', sum(bool(GUARDED.search(b.first_sentence())) for b in T) >= 2, '')
    res.check('allied_not_guarded>=2/3', sum(not GUARDED.search(b.first_sentence()) or bool(OPEN.search(b.first_sentence())) for b in C) >= 2, '')


def row_16bx(a, res):
    T, C = [Bundle(d) for d in a['--target']], [Bundle(d) for d in a['--ctl']]
    trait = (a['--trait'] or 'reserved').lower()
    res.check('samples>=3 each', min(len(T), len(C)) >= 3, f'{len(T)}/{len(C)}')
    distinct_inputs(T, 3, res)
    reps = []
    for b in T:
        ins, rep = (b.inputs() or [''])[-1], reply_of(b)
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
        rep = reply_of(b)
        res.check(f'{b.name}:ctl_tier_not_fond', b.stance()[1] not in ('Fond', 'Devoted'), b.stance()[1])
        res.check(f'{b.name}:ctl_no_give_action', not any(re.search(r'give|gift|trade', x, re.I) for x in b.foreign_actions()), '')
        before, after = res.need(os.path.join(b.dir, 'inv_before.txt')), res.need(os.path.join(b.dir, 'inv_after.txt'))
        if before is not None and after is not None:
            norm = lambda t: sorted(l.strip() for l in t.splitlines() if l.strip())
            res.check(f'{b.name}:ctl_inv_unchanged', norm(before) == norm(after), '')
        res.check(f'{b.name}:ctl_friendly_words', bool(OPEN.search(rep)) or rep.count('!') >= 1, rep[:40])


ROWS = {'01-bx': (row_01bx, ('--target', '--ctl-nohist', '--ctl-pos'), ('--seed', '--aff-target', '--aff-pos')),
        '01-cx': (row_01cx, ('--target', '--ctl'), ('--hostile-rel', '--allied-rel')),
        '16-bx': (row_16bx, ('--target', '--ctl'), ('--trait',))}

if __name__ == '__main__':
    pos, a = parse_args(sys.argv[1:], *(ROWS.get(sys.argv[1] if len(sys.argv) > 1 else '', ROWS['01-bx'])[1:]))
    if not pos or pos[0] not in ROWS:
        raise SystemExit('usage: assert_stance.py {01-bx|01-cx|16-bx} --target ... (see docstring)')
    res = Result('IMM-' + pos[0], a['--lenient'])
    ROWS[pos[0]][0](a, res)
    sys.exit(res.emit())
