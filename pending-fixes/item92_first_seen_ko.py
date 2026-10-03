#!/usr/bin/env python3
"""Item 92 (A13 v2, run m16): an NPC already unconscious the first time Stobe's event sweep sees him gets
no knockout event, even when he went down in a fight with the squad (Kor Gast: spawned, legs cut to -27,
KO'd before the first sweep). Fix: on first sight, unconscious + not dead + in a player-side fight within
the last 2 min (g_lastPlayerFightTickBySerial, item 88c) -> emit the knockout now.
Usage: python3 item92_first_seen_ko.py <STOBE-src root>   (asserts the anchor, refuses a second run)"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / 'src' / 'main.cpp'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 92' in s:
    sys.exit('already applied')
anchor = """      state.lastSeenTick = nowTick;
      if (!isPlayerActor && IsAnyPredationTask(currentTaskNow)) {"""
if s.count(anchor) != 1:
    sys.exit('anchor not found exactly once')
new = """      state.lastSeenTick = nowTick;
      // Item 92: first seen already down, but he went down in a fight with the squad (sweep missed the moment)
      if (unconsciousNow && !deadNow) {
        std::map<unsigned int, DWORD>::const_iterator pf92 = g_lastPlayerFightTickBySerial.find(serial);
        if (pf92 != g_lastPlayerFightTickBySerial.end() && nowTick - pf92->second <= kFledFighterHealthMs) {
          Log("EVENT_SCAN: first seen unconscious after a squad fight serial=" + ToString(serial) +
              " name=" + ResolveCharacterNameSafe(npc) + " (item 92: knockout reported now)");
          EmitKnockoutEvent(npc, &inventorySnapshot, hasMoneyNow ? moneyNow : -1);
        }
      }
      if (!isPlayerActor && IsAnyPredationTask(currentTaskNow)) {"""
s = s.replace(anchor, new)
p.write_text(s, encoding='utf-8', errors='surrogateescape')
print('patched', p)
