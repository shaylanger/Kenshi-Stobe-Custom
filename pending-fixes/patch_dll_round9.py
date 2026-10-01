#!/usr/bin/env python3
"""Stobe.dll round 9 (DLL tree). Fixes from the 2026-09-30 K run.

  bug 24  GIVE_ITEM to a full pack: Kenshi drops the item at the recipient's feet
          (giveItem dropOnFail), but the log said "transferred" and nobody was told.
          Check room before the give; if none, log dropped_at_feet=N, tell the player,
          and log a game event so the NPC knows.
  bug 27  A personal fight (STOBE ATTACK by an outsider on a player character): her
          faction-mates piled in and the server's stand-down came ~13 s late and didn't
          stick. The DLL now registers the fight and, every 250 ms for 3 minutes, stops
          any faction-mate who targets the player (two-sided stop + 20 s truce guard).
          "ATTACK@<player>@help" (the NPC called for help) skips this, as J3 allows.

Usage: patch_dll_round9.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


# ---- bug 24 ------------------------------------------------------------------
patch("src/Functions.cpp",
      """            int transferredCount = 0;
            std::string transferredItemName = "";""",
      """            int transferredCount = 0;
            int droppedAtFeetCount = 0;
            std::string transferredItemName = "";""")

patch("src/Functions.cpp",
      """                recipient->giveItem(detached, true, false);
                transferredCount += actualTransferred;
                inventoryTimer = 999;""",
      """                // A full pack makes giveItem drop the item at the recipient's feet.
                bool recipientHasRoom = true;
                try {
                  Inventory *recipientInventory = recipient->getInventory();
                  if (recipientInventory && detached->data) {
                    recipientHasRoom =
                        recipientInventory->hasRoomForItem(detached->data);
                  }
                } catch (...) {
                  recipientHasRoom = true;
                }
                recipient->giveItem(detached, true, false);
                if (!recipientHasRoom) {
                  droppedAtFeetCount += actualTransferred;
                }
                transferredCount += actualTransferred;
                inventoryTimer = 999;""")

patch("src/Functions.cpp",
      """              thisptr->showPlayerAMessage_withLog(
                  SafeCharacterName(npc) + " gave " + quantityPrefix +
                      givenItemName + " to " + SafeCharacterName(recipient) +
                      partialSuffix + ".",
                  true);
              Log("ACTION_EXEC: GIVE_ITEM actor=" + SafeCharacterName(npc) +
                  " recipient=" + SafeCharacterName(recipient) +
                  " requested=" + ToString(requestedCount) +
                  " transferred=" + ToString(transferredCount) +
                  " item='" + givenItemName + "' source=" + transferSourceLabel);""",
      """              const std::string droppedSuffix =
                  droppedAtFeetCount > 0
                      ? (" No room in " + SafeCharacterName(recipient) +
                         "'s pack: dropped at their feet.")
                      : "";
              thisptr->showPlayerAMessage_withLog(
                  SafeCharacterName(npc) + " gave " + quantityPrefix +
                      givenItemName + " to " + SafeCharacterName(recipient) +
                      partialSuffix + "." + droppedSuffix,
                  true);
              Log("ACTION_EXEC: GIVE_ITEM actor=" + SafeCharacterName(npc) +
                  " recipient=" + SafeCharacterName(recipient) +
                  " requested=" + ToString(requestedCount) +
                  " transferred=" + ToString(transferredCount) +
                  " item='" + givenItemName + "' source=" + transferSourceLabel +
                  " dropped_at_feet=" + ToString(droppedAtFeetCount));
              if (droppedAtFeetCount > 0) {
                try {
                  LogGameEvent("infoaction", SafeCharacterName(npc),
                               "", SafeCharacterName(recipient), "",
                               "handed over " + givenItemName + ", but " +
                                   SafeCharacterName(recipient) +
                                   "'s pack was full, so it was dropped at their feet",
                               npc->getHandle().serial,
                               recipient->getHandle().serial);
                } catch (...) {
                }
              }""")

print("patch_dll_round9 part 1 (bug 24) applied")

# ---- bug 27 ------------------------------------------------------------------
patch("src/Functions.cpp",
      "void UpdatePersonalTruces() {",
      r'''// ---- Personal fight: keep it one-on-one -----------------------------------
// When an outsider attacks a player character on STOBE's ATTACK action, her
// faction-mates who join are stopped at once (the server's stand-down came
// ~13 s late and was one-sided). The NPC calling for help ("@help") skips this.
struct PersonalFightGuard {
  hand attacker;
  hand victim;
  Faction *faction;
  DWORD until;
  DWORD nextCheck;
  int stoodDown;
};
static std::vector<PersonalFightGuard> g_personalFights;

static void RegisterPersonalFight(Character *attacker, Character *victim) {
  PersonalFightGuard fight;
  try {
    fight.attacker = attacker->getHandle();
    fight.victim = victim->getHandle();
    fight.faction = attacker->getFaction();
  } catch (...) {
    return;
  }
  if (!fight.faction) {
    return;
  }
  DWORD now = GetTickCount();
  fight.until = now + 180000;
  fight.nextCheck = now;
  fight.stoodDown = 0;
  for (size_t i = 0; i < g_personalFights.size(); ++i) {
    if (g_personalFights[i].attacker.serial == fight.attacker.serial &&
        g_personalFights[i].victim.serial == fight.victim.serial) {
      g_personalFights[i] = fight;
      return;
    }
  }
  g_personalFights.push_back(fight);
  Log("PERSONAL_FIGHT: registered attacker=" + SafeCharacterName(attacker) +
      " victim=" + SafeCharacterName(victim));
}

static bool PersonalFoeTargeted(Character *self, Character *foe);
static int StopPersonalFightPair(Character *first, Character *second,
                                 int &playerOrdersCleared,
                                 int &attackTasksRejected);
static void RegisterPersonalTruce(Character *first, Character *second);

void UpdatePersonalFights(GameWorld *world) {
  if (g_personalFights.empty() || !world) {
    return;
  }
  DWORD now = GetTickCount();
  for (std::vector<PersonalFightGuard>::iterator it = g_personalFights.begin();
       it != g_personalFights.end();) {
    if ((LONG)(now - it->until) >= 0) {
      Log("PERSONAL_FIGHT: ended stood_down=" + ToString(it->stoodDown));
      it = g_personalFights.erase(it);
      continue;
    }
    if ((LONG)(now - it->nextCheck) < 0) {
      ++it;
      continue;
    }
    it->nextCheck = now + 250;
    Character *attacker = nullptr;
    Character *victim = nullptr;
    try {
      attacker = it->attacker.getCharacter();
      victim = it->victim.getCharacter();
    } catch (...) {
    }
    if (!victim || (uintptr_t)victim <= 0x1000) {
      it = g_personalFights.erase(it);
      continue;
    }
    try {
      const ogre_unordered_set<Character *>::type &chars =
          world->getCharacterUpdateList();
      for (ogre_unordered_set<Character *>::type::const_iterator c =
               chars.begin();
           c != chars.end(); ++c) {
        Character *joiner = *c;
        if (!joiner || (uintptr_t)joiner <= 0x1000 || joiner == attacker ||
            joiner == victim) {
          continue;
        }
        Faction *joinerFaction = nullptr;
        try {
          joinerFaction = joiner->getFaction();
        } catch (...) {
          continue;
        }
        if (joinerFaction != it->faction || !PersonalFoeTargeted(joiner, victim)) {
          continue;
        }
        int ordersCleared = 0;
        int tasksRejected = 0;
        StopPersonalFightPair(joiner, victim, ordersCleared, tasksRejected);
        RegisterPersonalTruce(joiner, victim);
        ++it->stoodDown;
        Log("PERSONAL_FIGHT: stood down joiner=" + SafeCharacterName(joiner) +
            " victim=" + SafeCharacterName(victim) +
            " tasks_rejected=" + ToString(tasksRejected));
      }
    } catch (...) {
    }
    ++it;
  }
}

void UpdatePersonalTruces() {''')

patch("src/Functions.cpp",
      """  UpdateFactionCeasefireGuards(thisptr);
  UpdatePersonalTruces();
""",
      """  UpdateFactionCeasefireGuards(thisptr);
  UpdatePersonalTruces();
  UpdatePersonalFights(thisptr);
""")

patch("src/Functions.cpp",
      """          npc->attackTarget(target);
          npc->addGoal(MELEE_ATTACK, (RootObjectBase *)target);
          npc->reThinkCurrentAIAction();""",
      """          npc->attackTarget(target);
          npc->addGoal(MELEE_ATTACK, (RootObjectBase *)target);
          npc->reThinkCurrentAIAction();
          // An outsider attacking a player character over a private matter:
          // keep her faction-mates out (unless she called for help).
          try {
            if (act.message != "help" && target->isPlayerCharacter() &&
                !IsInPlayerFactionSafe(npc)) {
              RegisterPersonalFight(npc, target);
            }
          } catch (...) {
          }""")

# main.cpp: "ATTACK@<target>@help" -> target, message="help"
patch("src/main.cpp",
      """            act.type = ACT_ATTACK;
            act.actor = targetHand;
            hand resolvedTarget = resolveActionTargetHand(actionArgument, targetHand);""",
      """            act.type = ACT_ATTACK;
            act.actor = targetHand;
            const std::string helpSuffix = "@help";
            if (actionArgument.size() > helpSuffix.size() &&
                actionArgument.compare(actionArgument.size() - helpSuffix.size(),
                                       helpSuffix.size(), helpSuffix) == 0) {
              actionArgument.erase(actionArgument.size() - helpSuffix.size());
              act.message = "help";
            }
            hand resolvedTarget = resolveActionTargetHand(actionArgument, targetHand);""")

print("patch_dll_round9: applied")
