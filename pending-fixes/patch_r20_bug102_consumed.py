#!/usr/bin/env python3
"""Bug 102: Malzin mocked Shay for "feeding that Dust Bandit like a pet"
(water, wheatstraw, dried meat). Shay gave nothing: Shay and Malzin ate and
drank from their own packs. An inventory loss with no matching gain (eating,
drinking, a used medkit) aged out and was pinned on a "likely counterparty"
(talk target / listener: Skovrek) as "transferred 1x Water to Skovrek".
Fix: a loss without a matching gain is not a hand-over. Real hand-overs are
matched against the receiver's gain earlier; unmatched losses are only logged
(INV_TRANSFER: unmatched loss ... used up or dropped), never sent as a trade.
Usage: patch_r20_bug102_consumed.py <STOBE-src tree root>"""
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
    ("""      if (!empty && expired) {
        Character *fromActor =
            ResolveCharacterBySerialForInventoryEvent(it->fromSerial);
        Character *counterparty =
            ResolveLikelyInventoryTransferCounterparty(fromActor);
        if (counterparty && (uintptr_t)counterparty > 0x1000) {
          appendAggregation(
              agedOutByPair, it->fromSerial, it->fromName, it->fromFaction,
              ResolveCharacterSerialForEvent(counterparty),
              ResolveCharacterNameSafe(counterparty), SafeFaction(counterparty),
              it->itemKey, it->itemName, it->qty);
        } else {
          appendAggregation(agedOutByPair, it->fromSerial, it->fromName,
                            it->fromFaction, 0, "Ground", "None", it->itemKey,
                            it->itemName, it->qty);
        }
      }""",
     """      if (!empty && expired) {
        // Bug 102: no matching gain = eaten, drunk, used up or dropped; never
        // a hand-over to whoever is nearby.
        Log("INV_TRANSFER: unmatched loss from=" + it->fromName + " item=" +
            it->itemName + " qty=" + ToString(it->qty) +
            " (used up or dropped; no event)");
      }"""),
    ("""    if (overflow.qty > 0 && overflow.fromSerial != 0 && !overflow.itemKey.empty()) {
      Character *fromActor =
          ResolveCharacterBySerialForInventoryEvent(overflow.fromSerial);
      Character *counterparty =
          ResolveLikelyInventoryTransferCounterparty(fromActor);
      if (counterparty && (uintptr_t)counterparty > 0x1000) {
        appendAggregation(
            agedOutByPair, overflow.fromSerial, overflow.fromName,
            overflow.fromFaction, ResolveCharacterSerialForEvent(counterparty),
            ResolveCharacterNameSafe(counterparty), SafeFaction(counterparty),
            overflow.itemKey, overflow.itemName, overflow.qty);
      } else {
        appendAggregation(agedOutByPair, overflow.fromSerial, overflow.fromName,
                          overflow.fromFaction, 0, "Ground", "None",
                          overflow.itemKey, overflow.itemName, overflow.qty);
      }
    }""",
     """    if (overflow.qty > 0 && overflow.fromSerial != 0 && !overflow.itemKey.empty()) {
      Log("INV_TRANSFER: unmatched loss from=" + overflow.fromName + " item=" +
          overflow.itemName + " qty=" + ToString(overflow.qty) +
          " (queue full; no event)"); // bug 102
    }"""),
])
