#!/usr/bin/env python3
"""Stobe.dll round 8 (DLL tree). Fixes from the 2026-09-30 automated run.

  bug 20  One-on-one fights: STOP_ATTACK's faction ceasefire refuses them
          (reason=faction_not_supported) and KenshiFP's STOP_FIGHT only calms the NPC,
          so the player's auto-defence and the NPC's temp-enemy link restarted the fight.
          Now: when the faction path doesn't apply, stop the pair on both sides (clear
          temp-enemy status, reject the attack task, clear the player's attack orders,
          end combat mode) and re-apply it every second for 20 s while either side
          re-targets the other.

Usage: patch_dll_round8.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


PERSONAL = r'''std::string SafeRootObjectName(const hand &targetHandle) {'''

patch("src/Functions.cpp", PERSONAL, r'''// ---- One-on-one truce ------------------------------------------------------
// The faction ceasefire refuses personal fights (faction_not_supported), so a
// paid-off NPC and the player kept re-acquiring each other. Stop both sides of
// the pair and keep doing it for a while as vanilla AI re-thinks.

static bool StopPersonalFightSide(Character *self, Character *foe,
                                  int &playerOrdersCleared,
                                  int &attackTasksRejected) {
  if (!self || (uintptr_t)self <= 0x1000 || !foe || (uintptr_t)foe <= 0x1000) {
    return false;
  }
  bool changed = false;
  if (IsInPlayerFactionSafe(self)) {
    try {
      OrdersReceiver *orders = self->getOrdersReciever();
      if (orders &&
          (orders->hasPlayerOrder(UNPROVOKED_FOCUSED_MELEE_ATTACK) ||
           orders->hasPlayerOrder(FOCUSED_MELEE_ATTACK) ||
           orders->hasPlayerOrder(RANGED_ATTACK_FOCUSED_UNPROVOKED) ||
           orders->hasPlayerOrder(RANGED_ATTACK_FOCUSED))) {
        orders->clearOrders();
        ++playerOrdersCleared;
        changed = true;
      }
    } catch (...) {
    }
  }
  bool targetsFoe = false;
  try {
    hand targetHandle = self->getAttackTarget();
    targetsFoe = targetHandle.isValid() && !targetHandle.isNull() &&
                 targetHandle.getCharacter() == foe;
  } catch (...) {
  }
  if (targetsFoe) {
    try {
      OrdersReceiver *orders = self->getOrdersReciever();
      AITaskSytem *tasks = orders && (uintptr_t)orders > 0x1000
                               ? static_cast<AITaskSytem *>(orders)
                               : nullptr;
      if (tasks && (uintptr_t)tasks > 0x1000) {
        tasks->taskImpossible();
        tasks->setNeedGOAP();
        ++attackTasksRejected;
        changed = true;
      }
    } catch (...) {
    }
  }
  try {
    self->endCombatMode();
    changed = true;
  } catch (...) {
  }
  return changed;
}

static int StopPersonalFightPair(Character *first, Character *second,
                                 int &playerOrdersCleared,
                                 int &attackTasksRejected) {
  int stopped = 0;
  ClearCeasefirePairCombatState(first, second);
  if (StopPersonalFightSide(first, second, playerOrdersCleared,
                            attackTasksRejected)) {
    ++stopped;
  }
  if (StopPersonalFightSide(second, first, playerOrdersCleared,
                            attackTasksRejected)) {
    ++stopped;
  }
  return stopped;
}

struct PersonalTruceGuard {
  hand first;
  hand second;
  DWORD until;
  DWORD nextCheck;
  int reapplied;
};
static std::vector<PersonalTruceGuard> g_personalTruces;

static void RegisterPersonalTruce(Character *first, Character *second) {
  PersonalTruceGuard guard;
  try {
    guard.first = first->getHandle();
    guard.second = second->getHandle();
  } catch (...) {
    return;
  }
  DWORD now = GetTickCount();
  guard.until = now + 20000;
  guard.nextCheck = now + 1000;
  guard.reapplied = 0;
  for (size_t i = 0; i < g_personalTruces.size(); ++i) {
    if (g_personalTruces[i].first.serial == guard.first.serial &&
        g_personalTruces[i].second.serial == guard.second.serial) {
      g_personalTruces[i] = guard;
      return;
    }
  }
  g_personalTruces.push_back(guard);
}

static bool PersonalFoeTargeted(Character *self, Character *foe) {
  try {
    hand targetHandle = self->getAttackTarget();
    return targetHandle.isValid() && !targetHandle.isNull() &&
           targetHandle.getCharacter() == foe;
  } catch (...) {
    return false;
  }
}

void UpdatePersonalTruces() {
  if (g_personalTruces.empty()) {
    return;
  }
  DWORD now = GetTickCount();
  for (std::vector<PersonalTruceGuard>::iterator it = g_personalTruces.begin();
       it != g_personalTruces.end();) {
    if ((LONG)(now - it->until) >= 0) {
      Log("PERSONAL_TRUCE: ended reapplied=" + ToString(it->reapplied));
      it = g_personalTruces.erase(it);
      continue;
    }
    if ((LONG)(now - it->nextCheck) < 0) {
      ++it;
      continue;
    }
    it->nextCheck = now + 1000;
    Character *first = nullptr;
    Character *second = nullptr;
    try {
      first = it->first.getCharacter();
      second = it->second.getCharacter();
    } catch (...) {
    }
    if (!first || (uintptr_t)first <= 0x1000 || !second ||
        (uintptr_t)second <= 0x1000) {
      it = g_personalTruces.erase(it);
      continue;
    }
    if (PersonalFoeTargeted(first, second) ||
        PersonalFoeTargeted(second, first)) {
      int ordersCleared = 0;
      int tasksRejected = 0;
      StopPersonalFightPair(first, second, ordersCleared, tasksRejected);
      ++it->reapplied;
      Log("PERSONAL_TRUCE: reapplied first=" + SafeCharacterName(first) +
          " second=" + SafeCharacterName(second) +
          " orders_cleared=" + ToString(ordersCleared) +
          " tasks_rejected=" + ToString(tasksRejected));
    }
    ++it;
  }
}

std::string SafeRootObjectName(const hand &targetHandle) {''')

patch("src/Functions.cpp",
      """  UpdateFactionCeasefireGuards(thisptr);
""",
      """  UpdateFactionCeasefireGuards(thisptr);
  UpdatePersonalTruces();
""")

patch("src/Functions.cpp",
      """          } else {
            thisptr->showPlayerAMessage_withLog(
                SafeCharacterName(npc) + " could not stop the fighting.", true);
          }
        } else if (act.type == ACT_JOIN_PARTY && thisptr->player) {""",
      """          } else if (target && (uintptr_t)target > 0x1000 && target != npc) {
            // No faction ceasefire applies (a one-on-one fight): stop the pair itself.
            int ordersCleared = 0;
            int tasksRejected = 0;
            int stopped = StopPersonalFightPair(npc, target, ordersCleared,
                                                tasksRejected);
            RegisterPersonalTruce(npc, target);
            Log("ACTION_EXEC: STOP_ATTACK personal actor=" + SafeCharacterName(npc) +
                " target=" + SafeCharacterName(target) +
                " sides_stopped=" + ToString(stopped) +
                " player_orders_cleared=" + ToString(ordersCleared) +
                " attack_tasks_rejected=" + ToString(tasksRejected) +
                " guard_seconds=20");
            thisptr->showPlayerAMessage_withLog(
                SafeCharacterName(npc) + " stops fighting.", true);
          } else {
            thisptr->showPlayerAMessage_withLog(
                SafeCharacterName(npc) + " could not stop the fighting.", true);
          }
        } else if (act.type == ACT_JOIN_PARTY && thisptr->player) {""")

# bug 5: NPC money never reached the server (verification and prompts ran blind on the
# NPC's purse). Send it with the inventory sync, and resend when only the Cats change.
patch("src/main.cpp",
      """  payload += "\\"inventory_item_count\\":" + ToString(inventoryItemCount) + ",";
  payload += "\\"source\\":\\"inventory_live_sync\\",";""",
      """  payload += "\\"inventory_item_count\\":" + ToString(inventoryItemCount) + ",";
  int money = -1;
  try {
    money = npc->getMoney();
    if (money <= 0 && npc->getOwnerships())
      money = npc->getOwnerships()->getMoney();
  } catch (...) {
    money = -1;
  }
  if (money >= 0) {
    payload += "\\"money\\":" + ToString(money) + ",";
  }
  payload += "\\"source\\":\\"inventory_live_sync\\",";""")

patch("src/main.cpp",
      """  RefreshInventoryContextCache(npc, inventoryJson, isPlayerCharacter);
""",
      """  RefreshInventoryContextCache(npc, inventoryJson, isPlayerCharacter);
  // Cats aren't an item: fold them into the change hash so a payment alone resyncs.
  try {
    int cats = npc->getMoney();
    if (cats <= 0 && npc->getOwnerships())
      cats = npc->getOwnerships()->getMoney();
    inventoryHash += "|cats=" + ToString(cats);
  } catch (...) {
  }
""")

print("patch_dll_round8: applied")
