#!/usr/bin/env python3
"""NC26 = NC25 + imm26 10-f option A (native save-persistent item id).
Usage: python3 nc26_edit.py <tree>   (tree = NC25 tree with src/ and CMakeLists.txt; copies native/StobeDurableItem.{h,cpp} into
src/, edits CMakeLists.txt and src/main.cpp; CRLF-safe, anchor-asserted, refuses a second run)."""
import sys, io, os, shutil
tree = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))

def edit(path, pairs, marker, counts=None):
    s = io.open(path, encoding="utf-8", newline="").read()
    nl = "\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n"
    assert marker not in s, "NC26 already applied: " + path
    for i, (old, new) in enumerate(pairs):
        o2, n2 = old.replace("\n", nl), new.replace("\n", nl)
        want = counts[i] if counts else 1
        assert s.count(o2) == want, "anchor count %d (want %d) in %s: %r" % (s.count(o2), want, path, old[:70])
        s = s.replace(o2, n2)
    io.open(path, "w", encoding="utf-8", newline="").write(s)

for f in ("StobeDurableItem.h", "StobeDurableItem.cpp"):
    dst = os.path.join(tree, "src", f)
    assert not os.path.exists(dst), "NC26 already applied: " + dst
edit(os.path.join(tree, "CMakeLists.txt"), [(
"  src/ShopPriceHook.cpp\n", "  src/ShopPriceHook.cpp\n  src/StobeDurableItem.cpp\n")], "StobeDurableItem")

HELPER = '''// NC26 (10-f option A): the save-persistent id of a proven item. The exact transfer evidence already proves the SAME live
// Item object (address+serial+prototype+quantity) moved; here the receiver's inventory is scanned for that object and it is
// stamped (get-or-create). The id is written into the save by Stobe::DurableItem and read back after a reload, when
// hand_<serial> no longer identifies anything. Empty = no id (server falls back to the type fingerprint).
static std::string DurableIdField(Character *holder, const SocialInventoryInstance &a) {
  if (!holder || (uintptr_t)holder < 0x1000) return "";
  try {
    std::vector<Item *> items;
    GetAllCharacterItems(holder, items);
    for (size_t i = 0; i < items.size(); ++i) {
      Item *item = items[i];
      if (!item || (uintptr_t)item < 0x1000 || reinterpret_cast<uintptr_t>(item) != a.address) continue;
      if (item->getHandle().serial != a.serial || item->quantity != a.quantity) return "";
      GameData *data = item->getGameData();
      if (!data || (uintptr_t)data < 0x1000 || TrimCopy(data->stringID) != a.prototypeId) return "";
      const std::string id = Stobe::DurableItem::Stamp(item);
      return id.empty() ? "" : ",\\"durable_item_id\\":" + StobeSocial::JsonString(id);
    }
  } catch (...) { /* No id is not evidence. */ }
  return "";
}

// Proves ONLY unchanged whole stacks observed moving between these two holders.
'''
edit(os.path.join(tree, "src", "main.cpp"), [
 ('#include "ShopPriceHook.h"\n', '#include "ShopPriceHook.h"\n#include "StobeDurableItem.h"\n'),
 ("    Stobe::ShopPrice::ClearCache();\n", "    Stobe::ShopPrice::ClearCache();\n    Stobe::DurableItem::Reset();\n"),
 ("  Stobe::ShopPrice::Install(hLib); // item 104: relationship shop prices\n",
  "  Stobe::ShopPrice::Install(hLib); // item 104: relationship shop prices\n  Stobe::DurableItem::Install(hLib); // NC26 10-f A: save-persistent item id\n"),
 ("// Proves ONLY unchanged whole stacks observed moving between these two holders.\n", HELPER),
 ('''          ",\\"to_storage_id\\":" + StobeSocial::JsonString(receiver.storageId) + "}";
      provedByType[a.typeKey] += a.quantity;
''', '''          ",\\"to_storage_id\\":" + StobeSocial::JsonString(receiver.storageId) +
          DurableIdField(to->npc, a) + "}";
      provedByType[a.typeKey] += a.quantity;
'''),
], "StobeDurableItem.h", counts=[1, 3, 1, 1, 1])

for f in ("StobeDurableItem.h", "StobeDurableItem.cpp"):
    shutil.copyfile(os.path.join(here, "native", f), os.path.join(tree, "src", f))
print("NC26 applied to " + tree)
