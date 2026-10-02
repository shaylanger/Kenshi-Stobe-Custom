#!/usr/bin/env python3
"""Hand-overs: Character::giveItem failed silently and the item was lost/dropped.

Run 11: "Malzin, give me one of your dried meats." -> GIVE_ITEM transferred=1
dropped_at_feet=0, Malzin 14 -> 13, but Shay never got it although her pack had room
(stobe-auto give Shay "Dried Meat" 1 worked at once). giveItem(item, dropOnFail=true, ...)
returned false and dropped it; its result was ignored and dropped_at_feet came from a
pre-check prediction.

Now every hand-over (GIVE_ITEM, the deal/voice hand-over path and the player's give
path) goes through StobeHandOverItem(): the recipient's inventory addItem first (what
the test helper uses), giveItem with drop-on-fail only if that fails, and that case is
what counts as "dropped at their feet".

Usage: patch_dll_r23_handover_inventory_first.py <STOBE-src root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'src' / 'Functions.cpp'
s = f.read_text(encoding='utf-8')
if 'StobeHandOverItem' in s:
    print('already patched'); sys.exit(0)

helper_anchor = "const float kNpcCloseActionRangeUnits = 25.0f;"
helper = """// Hand an item to a character: into their inventory first; only if that fails,
// Kenshi's giveItem with drop-on-fail (counted as dropped at their feet).
// giveItem alone failed silently with room in the pack (run 11).
static bool StobeHandOverItem(Character *recipient, Item *item, int quantity,
                              bool *droppedAtFeet) {
  if (droppedAtFeet)
    *droppedAtFeet = false;
  if (!recipient || !item || (uintptr_t)item <= 0x1000)
    return false;
  try {
    Inventory *inv = recipient->getInventory();
    if (inv && (uintptr_t)inv > 0x1000 &&
        inv->addItem(item, quantity > 0 ? quantity : 1, false, false))
      return true;
  } catch (...) {
  }
  try {
    recipient->giveItem(item, true, false);
  } catch (...) {
    return false;
  }
  if (droppedAtFeet)
    *droppedAtFeet = true;
  return true;
}

"""
edits = [
    (helper_anchor, helper + helper_anchor),
    # player/deal path (~4335)
    ("""    try {
      recipient->giveItem(detached, true, false);
    } catch (...) {
      return false;
    }

    itemNameOut = itemName;
    quantityTransferredOut = detachedQuantity;""",
     """    bool handOverDropped = false;
    if (!StobeHandOverItem(recipient, detached, detachedQuantity, &handOverDropped)) {
      return false;
    }
    if (handOverDropped) {
      Log("ACTION_EXEC: hand-over to " + SafeCharacterName(recipient) +
          " did not fit: dropped at their feet item='" + itemName + "'");
    }

    itemNameOut = itemName;
    quantityTransferredOut = detachedQuantity;"""),
    # GIVE_ITEM path (~8694): replace prediction + giveItem
    ("""                recipient->giveItem(detached, true, false);
                if (!recipientHasRoom) {
                  droppedAtFeetCount += actualTransferred;
                }""",
     """                (void)recipientHasRoom; // prediction only; the real result decides
                bool handOverDropped = false;
                if (!StobeHandOverItem(recipient, detached, actualTransferred,
                                       &handOverDropped)) {
                  continue;
                }
                if (handOverDropped) {
                  droppedAtFeetCount += actualTransferred;
                }"""),
    # TAKE_ITEM path (~8298): the taker receives a detached item the same way
    ("""            try {
              npc->giveItem(toGive, true, false);
            } catch (...) {
              return false;
            }""",
     """            try {
              if (detached) {
                if (!StobeHandOverItem(npc, toGive, transferQuantity, nullptr)) {
                  return false;
                }
              } else {
                npc->giveItem(toGive, true, false);
              }
            } catch (...) {
              return false;
            }"""),
]
for o, n in edits:
    assert s.count(o) == 1, 'anchor: ' + o[:60]
    s = s.replace(o, n)
f.write_text(s, encoding='utf-8', newline='')
print('patched', f)
