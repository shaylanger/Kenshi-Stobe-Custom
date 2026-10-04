#!/usr/bin/env python3
"""m31 crash fix: ceasefire reject inside attackingYou/attackTarget hooks -> deferred.
Usage: python3 m31-ceasefire-defer-reject.py <STOBE tree root>  (needs src/StobeDeferredCombat.h present)"""
import sys, os
root = sys.argv[1]
def patch(rel, old, new, count=1):
    p = os.path.join(root, rel); s = open(p, encoding='utf-8', newline='').read()
    if new in s: print('already', rel); return
    n = s.count(old); assert n == count, (rel, old[:60], n)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))
    print('patched', rel)
assert os.path.exists(os.path.join(root, 'src/StobeDeferredCombat.h'))

# Functions.h: declarations
patch('src/Functions.h',
"""void RejectFactionCeasefireAttack(Character *attacker, Character *target,
                                  const std::string &gate);
""",
"""void RejectFactionCeasefireAttack(Character *attacker, Character *target,
                                  const std::string &gate);
// Hooks (attackingYou/attackTarget) may fire inside CombatClassAI::decisionState:
// they only queue the reject; ExecuteQueuedActions applies it (m31 crash fix).
void QueueFactionCeasefireReject(Character *attacker, Character *target,
                                 const std::string &gate);
void ApplyDeferredFactionCeasefireRejects(GameWorld *world);
""")

# Functions.cpp: include + implementation after RejectFactionCeasefireAttack
patch('src/Functions.cpp', '#include "KenshiBuildingCompat.h"\n',
      '#include "KenshiBuildingCompat.h"\n#include "StobeDeferredCombat.h"\n')
patch('src/Functions.cpp',
"""        " " + aiState);
  }
}
struct StopFactionAttackResult {""",
"""        " " + aiState);
  }
}

static SRWLOCK g_deferredCeasefireRejectLock = SRWLOCK_INIT;
static Stobe::DeferredCombatRejectQueue g_deferredCeasefireRejects;

void QueueFactionCeasefireReject(Character *attacker, Character *target,
                                 const std::string &gate) {
  if (!attacker || (uintptr_t)attacker <= 0x1000 || !target ||
      (uintptr_t)target <= 0x1000) {
    return;
  }
  unsigned int attackerSerial = 0;
  unsigned int targetSerial = 0;
  try {
    attackerSerial = attacker->getHandle().serial;
    targetSerial = target->getHandle().serial;
  } catch (...) {
    return;
  }
  AcquireSRWLockExclusive(&g_deferredCeasefireRejectLock);
  g_deferredCeasefireRejects.Push(attackerSerial, targetSerial, gate);
  ReleaseSRWLockExclusive(&g_deferredCeasefireRejectLock);
}

static Character *FindLiveCharacterBySerial(GameWorld *world,
                                            unsigned int serial) {
  if (!world || serial == 0) {
    return nullptr;
  }
  try {
    const ogre_unordered_set<Character *>::type &chars =
        world->getCharacterUpdateList();
    for (ogre_unordered_set<Character *>::type::const_iterator it =
             chars.begin();
         it != chars.end(); ++it) {
      Character *candidate = *it;
      if (candidate && (uintptr_t)candidate > 0x1000 &&
          candidate->getHandle().serial == serial) {
        return candidate;
      }
    }
  } catch (...) {
  }
  return nullptr;
}

void ApplyDeferredFactionCeasefireRejects(GameWorld *world) {
  std::vector<Stobe::DeferredCombatReject> pending;
  size_t dropped = 0;
  AcquireSRWLockExclusive(&g_deferredCeasefireRejectLock);
  g_deferredCeasefireRejects.TakeAll(pending);
  dropped = g_deferredCeasefireRejects.Dropped();
  ReleaseSRWLockExclusive(&g_deferredCeasefireRejectLock);
  static size_t loggedDropped = 0;
  if (dropped != loggedDropped) {
    loggedDropped = dropped;
    Log("CEASEFIRE_TRUCE: deferred reject queue full, dropped_total=" +
        ToString((int)dropped));
  }
  for (size_t i = 0; i < pending.size(); ++i) {
    Character *attacker =
        FindLiveCharacterBySerial(world, pending[i].attackerSerial);
    Character *target = FindLiveCharacterBySerial(world, pending[i].targetSerial);
    if (!attacker || !target) {
      continue;
    }
    RejectFactionCeasefireAttack(attacker, target, pending[i].gate);
  }
}
struct StopFactionAttackResult {""")

# ExecuteQueuedActions: apply right after the guard update (main thread)
patch('src/Functions.cpp',
"""  UpdateFactionCeasefireGuards(thisptr);
  UpdatePersonalTruces(thisptr);""",
"""  UpdateFactionCeasefireGuards(thisptr);
  ApplyDeferredFactionCeasefireRejects(thisptr);
  UpdatePersonalTruces(thisptr);""")

# main.cpp hooks: queue instead of mutating combat state inside the hook
patch('src/main.cpp', 'RejectFactionCeasefireAttack(attacker, npc, "attacking_you");',
      'QueueFactionCeasefireReject(attacker, npc, "attacking_you");')
patch('src/main.cpp', 'RejectFactionCeasefireAttack(attacker, target, "attack_target");',
      'QueueFactionCeasefireReject(attacker, target, "attack_target");')

# portable tests
patch('tests/cpp/stobe_text_tests.cpp', '#include "StobeEventPolicy.h"\n',
      '#include "StobeEventPolicy.h"\n#include "StobeDeferredCombat.h"\n')
patch('tests/cpp/stobe_text_tests.cpp',
"""  if (g_failures != 0) {
    std::cerr << g_failures << " portable C++ tests failed.\\n";""",
"""  {
    // m31 crash: hooks queue ceasefire rejects; the pump applies them later.
    Stobe::DeferredCombatRejectQueue q(2);
    ExpectBool("Deferred reject queues a pair", q.Push(10, 20, "attacking_you"), true);
    ExpectBool("Deferred reject dedupes the same pair", q.Push(10, 20, "attack_target"), false);
    ExpectBool("Deferred reject ignores zero serials", q.Push(0, 20, "attacking_you"), false);
    ExpectBool("Deferred reject keeps reversed pair", q.Push(20, 10, "attacking_you"), true);
    ExpectBool("Deferred reject drops when full", q.Push(30, 40, "attacking_you"), false);
    ExpectUInt32("Deferred reject counts drops", (unsigned int)q.Dropped(), 1);
    std::vector<Stobe::DeferredCombatReject> taken;
    q.TakeAll(taken);
    ExpectUInt32("Deferred reject TakeAll returns all", (unsigned int)taken.size(), 2);
    ExpectEq("Deferred reject keeps order and gate", taken.empty() ? "" : taken[0].gate, "attacking_you");
    ExpectUInt32("Deferred reject TakeAll empties queue", (unsigned int)q.Size(), 0);
    ExpectBool("Deferred reject accepts pair again after drain", q.Push(10, 20, "attacking_you"), true);
  }

  if (g_failures != 0) {
    std::cerr << g_failures << " portable C++ tests failed.\\n";""")
