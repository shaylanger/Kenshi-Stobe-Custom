#!/usr/bin/env python3
"""Bug 103: Shay bought food from a trader, but the events said "bought 4x
Gohan from Malzin for 1704 cats" (and 2512, 855). For a money change the DLL
asked ResolveLikelyInventoryTransferCounterparty() first, which returns the
player's talk target (Malzin), and ResolveLikelyTraderForActor() also prefers
the talk target if flagged as a trader (Malzin is).
Fix: for cats trades look for a real trader first; a squad member
(isPlayerCharacter) is never the seller/counterparty of a player's cats trade.
Usage: patch_r20_bug103_seller.py <STOBE-src tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("src/main.cpp", [
    ("""static Character *ResolveLikelyTraderForActor(GameWorld *world, Character *actor) {
  auto isValidTrader = [&](Character *candidate) -> bool {
    if (!candidate || (uintptr_t)candidate < 0x1000 || candidate == actor) {
      return false;
    }
    bool trader = false;""",
     """static Character *ResolveLikelyTraderForActor(GameWorld *world, Character *actor) {
  auto isValidTrader = [&](Character *candidate) -> bool {
    if (!candidate || (uintptr_t)candidate < 0x1000 || candidate == actor) {
      return false;
    }
    try { // bug 103: your own squad never sells to you
      if (candidate->isPlayerCharacter()) return false;
    } catch (...) {
      return false;
    }
    bool trader = false;"""),
    ("""      if (hasMoneyDelta && moneyDelta != 0) {
        tradeCounterparty = ResolveLikelyInventoryTransferCounterparty(npc);
        if ((!tradeCounterparty || (uintptr_t)tradeCounterparty <= 0x1000) &&
            isPlayerActor) {
          tradeCounterparty = ResolveLikelyTraderForActor(world, npc);
        }
      }""",
     """      if (hasMoneyDelta && moneyDelta != 0) {
        // Bug 103: a real trader first; squad members never trade cats with you.
        if (isPlayerActor) {
          tradeCounterparty = ResolveLikelyTraderForActor(world, npc);
        }
        if (!tradeCounterparty || (uintptr_t)tradeCounterparty <= 0x1000) {
          tradeCounterparty = ResolveLikelyInventoryTransferCounterparty(npc);
        }
        if (tradeCounterparty && (uintptr_t)tradeCounterparty > 0x1000 && isPlayerActor) {
          bool counterpartySquad = false;
          try {
            counterpartySquad = tradeCounterparty->isPlayerCharacter();
          } catch (...) {
            counterpartySquad = true;
          }
          if (counterpartySquad) {
            Log("INV_TRANSFER: cats trade counterparty " +
                ResolveCharacterNameSafe(tradeCounterparty) +
                " is in the player's squad; not a seller (bug 103)");
            tradeCounterparty = nullptr;
          }
        }
      }"""),
])
