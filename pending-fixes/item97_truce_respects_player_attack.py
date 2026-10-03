#!/usr/bin/env python3
"""Item 97 (REL surrender diagnosis, run m16): `PERSONAL_TRUCE: reapplied first=Rel Brak second=Shay orders_cleared=1`
cleared Shay's explicit attack order (given 9 s after the accept, inside the truce guard). Shay's call: an explicit
player attack order (a click; the harness `attack` acts like one) is never cancelled. Breaking a deal is the player's
choice (the server records it: item 86 player_resumed_fight). The guard keeps stopping automatic defend/aggro only.
Fix: an explicit player attack order on the other party ends that pair's personal truce guard instead of being
cleared: checked every guard tick (HasExplicitPlayerAttackOrder), in the AI enemy hooks (BreakFactionCeasefireFor-
PlayerOrder) and in the harness `attack` hook. Log: `PERSONAL_TRUCE: broken by player order ... (item 97)`.
Usage: item97_truce_respects_player_attack.py <STOBE-src root>"""
import sys, pathlib
src = pathlib.Path(sys.argv[1]) / 'src'

def patch(name, reps):
    p = src / name
    s = p.read_text(encoding='utf-8', errors='surrogateescape')
    if 'Item 97' in s: sys.exit(name + ': already applied')
    for old, new in reps:
        if s.count(old) != 1: sys.exit(name + ': anchor missing: ' + old[:80])
        s = s.replace(old, new)
    p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)

patch('Functions.h', [(
"""bool BreakFactionCeasefireForExplicitAttack(Character *attacker,
                                            Character *target,
                                            const std::string &source);
""",
"""bool BreakFactionCeasefireForExplicitAttack(Character *attacker,
                                            Character *target,
                                            const std::string &source);
// Item 97: an explicit player attack order ends the pair's personal truce guard (never cleared by it)
bool BreakPersonalTruceForExplicitAttack(Character *attacker, Character *target,
                                         const std::string &source);
""")])

patch('Functions.cpp', [
("""bool BreakFactionCeasefireForPlayerOrder(Character *attacker,
                                         Character *target,
                                         const std::string &source) {
  return HasExplicitPlayerAttackOrder(attacker, target) &&
         BreakFactionCeasefireForExplicitAttack(attacker, target, source);
}""",
"""bool BreakFactionCeasefireForPlayerOrder(Character *attacker,
                                         Character *target,
                                         const std::string &source) {
  if (!HasExplicitPlayerAttackOrder(attacker, target)) {
    return false;
  }
  BreakPersonalTruceForExplicitAttack(attacker, target, source); // Item 97
  return BreakFactionCeasefireForExplicitAttack(attacker, target, source);
}"""),
("""static void RegisterPersonalTruce(Character *first, Character *second) {
  PersonalTruceGuard guard;""",
"""// Item 97: the player chose to fight this pair again: drop the guard instead of clearing the order.
bool BreakPersonalTruceForExplicitAttack(Character *attacker, Character *target,
                                         const std::string &source) {
  if (!attacker || (uintptr_t)attacker <= 0x1000 || !target ||
      (uintptr_t)target <= 0x1000 || g_personalTruces.empty()) {
    return false;
  }
  unsigned int a = 0, t = 0;
  try {
    a = attacker->getHandle().serial;
    t = target->getHandle().serial;
  } catch (...) {
    return false;
  }
  bool removed = false;
  for (std::vector<PersonalTruceGuard>::iterator it = g_personalTruces.begin();
       it != g_personalTruces.end();) {
    if ((it->first.serial == a && it->second.serial == t) ||
        (it->first.serial == t && it->second.serial == a)) {
      it = g_personalTruces.erase(it);
      removed = true;
    } else {
      ++it;
    }
  }
  if (removed) {
    Log("PERSONAL_TRUCE: broken by player order source=" + source + " attacker=" +
        SafeCharacterName(attacker) + " target=" + SafeCharacterName(target) +
        " (item 97: explicit orders are never cleared)");
  }
  return removed;
}

static void RegisterPersonalTruce(Character *first, Character *second) {
  PersonalTruceGuard guard;"""),
("""    if (PersonalFoeTargeted(first, second) ||
        PersonalFoeTargeted(second, first)) {
      int ordersCleared = 0;""",
"""    // Item 97: a player's explicit attack order is the player's choice, not aggro to clear
    if (HasExplicitPlayerAttackOrder(first, second) ||
        HasExplicitPlayerAttackOrder(second, first)) {
      Character *attacker = HasExplicitPlayerAttackOrder(first, second) ? first : second;
      Character *target = attacker == first ? second : first;
      Log("PERSONAL_TRUCE: broken by player order source=guard_tick attacker=" +
          SafeCharacterName(attacker) + " target=" + SafeCharacterName(target) +
          " (item 97: explicit orders are never cleared)");
      it = g_personalTruces.erase(it);
      continue;
    }
    if (PersonalFoeTargeted(first, second) ||
        PersonalFoeTargeted(second, first)) {
      int ordersCleared = 0;"""),
])

patch('StobeHarnessBridge.cpp', [(
"""  BreakFactionCeasefireForExplicitAttack(static_cast<Character *>(attacker),
                                         static_cast<Character *>(target),
                                         "test_attack_order");""",
"""  BreakFactionCeasefireForExplicitAttack(static_cast<Character *>(attacker),
                                         static_cast<Character *>(target),
                                         "test_attack_order");
  // Item 97: the harness `attack` acts like a player click: it ends the pair's personal truce too
  BreakPersonalTruceForExplicitAttack(static_cast<Character *>(attacker),
                                      static_cast<Character *>(target),
                                      "test_attack_order");""")])
