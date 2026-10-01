#!/usr/bin/env python3
"""Stobe.dll round 9b (DLL tree). Bug 24 follow-up: round 9's room check used
Inventory::hasRoomForItem(GameData*), which checks room for one unit only. Handing over
a stack could still drop it at the recipient's feet unreported. Now each section of
the recipient's inventory is asked whether the whole stack fits
(InventorySection::hasRoomForItem(GameData*, quantity)).

Usage: patch_dll_round9b.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:70]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("src/Functions.cpp",
      """                  Inventory *recipientInventory = recipient->getInventory();
                  if (recipientInventory && detached->data) {
                    recipientHasRoom =
                        recipientInventory->hasRoomForItem(detached->data);
                  }""",
      """                  Inventory *recipientInventory = recipient->getInventory();
                  if (recipientInventory && detached->data) {
                    // The whole stack must fit in one section.
                    lektor<InventorySection *> &sections =
                        recipientInventory->getAllSections();
                    if (sections.size() > 0) {
                      recipientHasRoom = false;
                      for (uint32_t s = 0; s < sections.size(); ++s) {
                        InventorySection *section = sections.stuff[s];
                        if (section && (uintptr_t)section > 0x1000 &&
                            section->hasRoomForItem(detached->data,
                                                    actualTransferred)) {
                          recipientHasRoom = true;
                          break;
                        }
                      }
                    }
                  }""")

print("patch_dll_round9b: applied")
