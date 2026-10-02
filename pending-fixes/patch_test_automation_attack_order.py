#!/usr/bin/env python3
"""Test automation: `attack` gives a real attack order, like the player's.

attackTarget() alone did nothing for Shay against an NPC under a truce
(run 9, test 20): no combat, so a player breach could never be tested. Like
AutonomyExecutor's attack: break a ceasefire for the explicit attack, add an
UNPROVOKED_FOCUSED_MELEE_ATTACK order, then attackTarget().

Usage: patch_test_automation_attack_order.py <STOBE tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'src' / 'TestAutomation.cpp'
text = path.read_text(encoding='utf-8')
old = """    Character *target = FindCharacter(world, f[3]);
    if (!target)
      return "no character named: " + f[3];
    c->attackTarget(target);
"""
new = """    Character *target = FindCharacter(world, f[3]);
    if (!target)
      return "no character named: " + f[3];
    // A real order, as the player gives it: break a truce, queue the attack.
    BreakFactionCeasefireForExplicitAttack(c, target, "test_attack_order");
    OrdersReceiver *orders = c->getOrdersReciever();
    if (orders && (uintptr_t)orders > 0x1000)
      orders->addOrder(UNPROVOKED_FOCUSED_MELEE_ATTACK, target->getHandle(),
                       target->getPosition(), true, false);
    c->attackTarget(target);
"""
inc_old = '#include <kenshi/Character.h>\n'
inc_new = '#include <kenshi/AI/AITaskSystem.h>\n#include <kenshi/Character.h>\n'
fn_old = '#include "Context.h"             // BuildInventorySnapshot\n'
fn_new = fn_old + '#include "Functions.h"           // BreakFactionCeasefireForExplicitAttack\n'
if 'test_attack_order' in text:
    print('already patched')
    sys.exit(0)
for a in (old, inc_old, fn_old):
    assert text.count(a) == 1, 'anchor not found exactly once: ' + a[:40]
text = text.replace(old, new).replace(inc_old, inc_new)
if '#include "Functions.h"' not in text:
    text = text.replace(fn_old, fn_new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
