#!/usr/bin/env python3
"""Bug 109: a fight that never ends.

UpdateLocalCombatEncounter follows the attack graph to everyone within 600
units of where the fight started. A spawned bandit walked off and joined a
Dust Bandit raid ~300 away; that separate fight kept Shay and Malzin's
encounter "active" (no combat_end for minutes), and Malzin refused an order
because "a bandit is breathing down our necks". Use a local radius of 150.

Usage: patch_r21_bug109_combat_radius.py <STOBE tree root>
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'src' / 'main.cpp'
text = path.read_text(encoding='utf-8')
edits = [
    ("static const size_t kCombatParticipantLimit = 64;\n",
     "static const size_t kCombatParticipantLimit = 64;\n"
     "// Bug 109: a separate fight farther away must not keep this encounter alive.\n"
     "static const float kCombatLocalRadius = 150.0f;\n"),
    ("    if (serial == 0 || claimed.count(serial) != 0 ||\n"
     "        npc->getPosition().distance(combatState.origin) > 600.0f) {\n",
     "    if (serial == 0 || claimed.count(serial) != 0 ||\n"
     "        npc->getPosition().distance(combatState.origin) > kCombatLocalRadius) {\n"),
]
# Part 2: Shay/Malzin keep the fled bandit as attack target, so "has an attack
# target" kept the fight alive; a target/attacker only counts when close.
edits2 = [
    ("  observation.evidence =\n"
     "      !observation.dead && !observation.unconscious &&\n"
     "      (inCombat || rangedCombat || underMeleeAttack ||\n"
     "       observation.attackTarget != nullptr || !observation.attackers.empty() ||\n"
     "       HasRecentCombatSignal(serial, nowTick));\n",
     "  // Bug 109: someone far away (fled, or fighting elsewhere) is no evidence.\n"
     "  bool closeTarget = false;\n"
     "  try {\n"
     "    const Ogre::Vector3 me = npc->getPosition();\n"
     "    if (observation.attackTarget &&\n"
     "        observation.attackTarget->getPosition().distance(me) <= kCombatLocalRadius)\n"
     "      closeTarget = true;\n"
     "    for (size_t i = 0; i < observation.attackers.size() && !closeTarget; ++i)\n"
     "      if (observation.attackers[i]->getPosition().distance(me) <= kCombatLocalRadius)\n"
     "        closeTarget = true;\n"
     "  } catch (...) {\n"
     "  }\n"
     "  observation.evidence =\n"
     "      !observation.dead && !observation.unconscious &&\n"
     "      (underMeleeAttack || closeTarget ||\n"
     "       ((inCombat || rangedCombat || HasRecentCombatSignal(serial, nowTick)) &&\n"
     "        (closeTarget || (observation.attackTarget == nullptr &&\n"
     "                         observation.attackers.empty()))));\n"),
]
if 'Bug 109: someone far away' in text:
    print('already patched')
    sys.exit(0)
if 'kCombatLocalRadius' in text:
    edits = []
for old, new in edits2:
    assert text.count(old) == 1, 'anchor not found exactly once: %r' % old[:60]
    text = text.replace(old, new)
for old, new in edits:
    assert text.count(old) == 1, 'anchor not found exactly once: %r' % old[:60]
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
