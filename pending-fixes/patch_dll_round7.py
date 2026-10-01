#!/usr/bin/env python3
"""Stobe.dll round 7 (DLL tree): bug 3 from test-run-2026-09-30.md.

  - Restore the player Cats + squad sync. Upstream commit 49ce420 moved world reads out of
    the background loop into the update hook but left these two behind, so the server
    never learned the player's balance and every money check ran blind.
  - A player's GIVE_CATS is all or nothing: asking for more than the purse holds
    transfers nothing (it used to hand over the whole purse).

Usage: patch_dll_round7.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("src/main.cpp",
      "  UpdateTestInbox(worldUi, sel);\n",
      """  UpdateTestInbox(worldUi, sel);

  // Player Cats and squads for the server (these used to run on the background loop).
  static DWORD lastPlayerSyncTick = 0;
  if (worldUi && worldUi->player && worldUi->player->playerCharacters.size() > 0 &&
      GetTickCount() - lastPlayerSyncTick >= 2000) {
    lastPlayerSyncTick = GetTickCount();
    Character *primaryPlayer = worldUi->player->playerCharacters[0];
    if (primaryPlayer && (uintptr_t)primaryPlayer > 0x1000) {
      SyncPlayerCatsValue(primaryPlayer, false, "update_tick");
      SyncPlayerSquadsToConfOpts(worldUi, false, "update_tick");
    }
  }
""")

patch("src/Functions.cpp",
      """            int amt = (act.taskValue > actorMoney) ? actorMoney : act.taskValue;
            if (amt > 0) {""",
      """            int amt = (act.taskValue > actorMoney) ? actorMoney : act.taskValue;
            bool actorIsPlayer = false;
            try {
              actorIsPlayer = npc->isPlayerCharacter();
            } catch (...) {
            }
            if (actorIsPlayer && act.taskValue > actorMoney) {
              // A player payment is all or nothing: never hand over the whole purse.
              thisptr->showPlayerAMessage_withLog(
                  SafeCharacterName(npc) + " only has " + ToString(actorMoney) + " cats.", true);
              Log("ACTION_EXEC: GIVE_CATS refused actor=" + SafeCharacterName(npc) +
                  " requested=" + ToString(act.taskValue) +
                  " available=" + ToString(actorMoney));
            } else if (amt > 0) {""")

print("patch_dll_round7: applied")
