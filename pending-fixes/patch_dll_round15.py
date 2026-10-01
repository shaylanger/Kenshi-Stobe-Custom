#!/usr/bin/env python3
"""DLL round 15: bug 40, faction-mates who join after a personal STOP_ATTACK are stood down.

A personal STOP_ATTACK registered a 20 s truce guard for the NPC and the player only. Her
faction-mates who engaged a moment later (a fight where she called for help) kept attacking.
The guard now remembers her faction and, every second while it runs, stands down any
member of that faction who targets the other side.
Usage: patch_dll_round15.py <STOBE-src root>
"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / "src/Functions.cpp"
s = p.read_text()


def rep(old, new):
    global s
    assert s.count(old) == 1, f"anchor found {s.count(old)}x (already applied?): {old[:70]!r}"
    s = s.replace(old, new)


rep("""struct PersonalTruceGuard {
  hand first;
  hand second;
  DWORD until;""",
    """struct PersonalTruceGuard {
  hand first;
  hand second;
  Faction *faction; // bug 40: first's faction; its members attacking second are stood down too
  int factionStoodDown;
  DWORD until;""")

rep("""  try {
    guard.first = first->getHandle();
    guard.second = second->getHandle();
  } catch (...) {
    return;
  }
  DWORD now = GetTickCount();
  guard.until = now + 20000;""",
    """  try {
    guard.first = first->getHandle();
    guard.second = second->getHandle();
  } catch (...) {
    return;
  }
  guard.faction = nullptr;
  guard.factionStoodDown = 0;
  try {
    guard.faction = first->getFaction();
    if (guard.faction && guard.faction->isThePlayer()) {
      guard.faction = nullptr; // never order the player's own squad around
    }
  } catch (...) {
    guard.faction = nullptr;
  }
  DWORD now = GetTickCount();
  guard.until = now + 20000;""")

rep("""void UpdatePersonalTruces() {
  if (g_personalTruces.empty()) {
    return;
  }""",
    """void UpdatePersonalTruces(GameWorld *world) {
  if (g_personalTruces.empty()) {
    return;
  }""")

rep("""    if ((LONG)(now - it->until) >= 0) {
      Log("PERSONAL_TRUCE: ended reapplied=" + ToString(it->reapplied));""",
    """    if ((LONG)(now - it->until) >= 0) {
      Log("PERSONAL_TRUCE: ended reapplied=" + ToString(it->reapplied) +
          " faction_stood_down=" + ToString(it->factionStoodDown));""")

rep("""      Log("PERSONAL_TRUCE: reapplied first=" + SafeCharacterName(first) +
          " second=" + SafeCharacterName(second) +
          " orders_cleared=" + ToString(ordersCleared) +
          " tasks_rejected=" + ToString(tasksRejected));
    }
    ++it;""",
    """      Log("PERSONAL_TRUCE: reapplied first=" + SafeCharacterName(first) +
          " second=" + SafeCharacterName(second) +
          " orders_cleared=" + ToString(ordersCleared) +
          " tasks_rejected=" + ToString(tasksRejected));
    }
    // Bug 40: her faction-mates who joined in (before or after the stop) stand down too.
    if (world && it->faction) {
      try {
        const ogre_unordered_set<Character *>::type &chars =
            world->getCharacterUpdateList();
        for (ogre_unordered_set<Character *>::type::const_iterator c =
                 chars.begin();
             c != chars.end(); ++c) {
          Character *mate = *c;
          if (!mate || (uintptr_t)mate <= 0x1000 || mate == first ||
              mate == second) {
            continue;
          }
          Faction *mateFaction = nullptr;
          try {
            mateFaction = mate->getFaction();
          } catch (...) {
            continue;
          }
          if (mateFaction != it->faction || !PersonalFoeTargeted(mate, second)) {
            continue;
          }
          int mateOrdersCleared = 0;
          int mateTasksRejected = 0;
          StopPersonalFightPair(mate, second, mateOrdersCleared,
                                mateTasksRejected);
          ++it->factionStoodDown;
          Log("PERSONAL_TRUCE: stood down faction-mate=" +
              SafeCharacterName(mate) +
              " target=" + SafeCharacterName(second) +
              " tasks_rejected=" + ToString(mateTasksRejected));
        }
      } catch (...) {
      }
    }
    ++it;""")

rep("""  UpdatePersonalTruces();
  UpdatePersonalFights(thisptr);""",
    """  UpdatePersonalTruces(thisptr);
  UpdatePersonalFights(thisptr);""")

p.write_text(s)
print("patched", p)
