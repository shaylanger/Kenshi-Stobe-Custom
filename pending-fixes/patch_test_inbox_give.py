#!/usr/bin/env python3
"""Adds give_cats / give_item to the Stobe.dll test inbox (needs patch_test_inbox.py first).

  give_cats <amount>          adds Cats to the speaking player character
  give_item <name> [count]    creates an item (ITEM/WEAPON/ARMOUR data, case-insensitive
                              exact name, else a unique substring) in the player's inventory

Usage: patch_test_inbox_give.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])


def patch(rel, old, new):
    p = root / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor not found exactly once: {old[:60]!r}"
    p.write_text(text.replace(old, new), encoding="utf-8")


patch("src/main.cpp",
      "static std::string RunTestInboxCommand(GameWorld *world, Character *sel,",
      r'''#include <kenshi/RootObjectFactory.h>

// Finds item data by name for give_item: exact (case-insensitive) match wins,
// otherwise a single substring match. Candidates are listed on ambiguity.
static GameData *FindTestInboxItemData(GameWorld *world, const std::string &name,
                                       std::string &error) {
  std::string wanted = TestInboxLower(name);
  const itemType categories[] = {ITEM, WEAPON, ARMOUR};
  std::vector<GameData *> partial;
  for (size_t c = 0; c < 3; ++c) {
    const auto categoryIt = world->gamedata.gamedataCatSID.find((int)categories[c]);
    if (categoryIt == world->gamedata.gamedataCatSID.end())
      continue;
    const auto &entries = categoryIt->second;
    for (auto it = entries.begin(); it != entries.end(); ++it) {
      GameData *data = it->second;
      if (!data || (uintptr_t)data <= 0x1000)
        continue;
      std::string dataName = TestInboxLower(data->name);
      if (dataName == wanted)
        return data;
      if (dataName.find(wanted) != std::string::npos)
        partial.push_back(data);
    }
  }
  if (partial.size() == 1)
    return partial[0];
  if (partial.empty()) {
    error = "no item data named: " + name;
  } else {
    error = "ambiguous item name, candidates:";
    for (size_t i = 0; i < partial.size() && i < 12; ++i)
      error += " [" + partial[i]->name + "]";
  }
  return nullptr;
}

static std::string RunTestInboxCommand(GameWorld *world, Character *sel,''')

patch("src/main.cpp",
      '  return "unknown command: " + cmd;\n}',
      r'''  if (cmd == "give_cats") {
    int amount = f.size() >= 3 ? atoi(f[2].c_str()) : 0;
    if (amount <= 0 || amount > 1000000)
      return "usage: give_cats <1..1000000>";
    if (!speaker)
      return "no player character";
    int before = 0, after = 0;
    try {
      before = speaker->getMoney();
      speaker->takeMoney(-amount);
      after = speaker->getMoney();
    } catch (...) {
      return "money change failed";
    }
    SyncPlayerCatsValue(speaker, true, "test_inbox");
    Log("TEST_INBOX: give_cats id=" + f[0] + " amount=" + ToString(amount) +
        " before=" + ToString(before) + " after=" + ToString(after));
    ok = true;
    return "cats " + ToString(before) + " -> " + ToString(after);
  }
  if (cmd == "give_item") {
    if (f.size() < 3 || f[2].empty())
      return "usage: give_item <name> [count]";
    int count = f.size() >= 4 ? atoi(f[3].c_str()) : 1;
    if (count <= 0 || count > 50)
      return "count must be 1..50";
    if (!speaker || !world->theFactory)
      return "no player character or item factory";
    std::string error;
    GameData *data = FindTestInboxItemData(world, f[2], error);
    if (!data)
      return error;
    Inventory *inventory = speaker->getInventory();
    if (!inventory)
      return "player has no inventory";
    int added = 0;
    for (int i = 0; i < count; ++i) {
      Item *item = nullptr;
      try {
        item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1,
                                             nullptr);
      } catch (...) {
        item = nullptr;
      }
      if (!item)
        break;
      bool placed = false;
      try {
        placed = inventory->addItem(item, 1, false, true);
      } catch (...) {
        placed = false;
      }
      if (!placed)
        break;
      ++added;
    }
    Log("TEST_INBOX: give_item id=" + f[0] + " item=" + data->name +
        " requested=" + ToString(count) + " added=" + ToString(added));
    ok = added > 0;
    return (ok ? "" : "nothing added (inventory full?) ") + std::string("item=") +
           data->name + " added=" + ToString(added) + "/" + ToString(count);
  }
  return "unknown command: " + cmd;
}''')

print("patch_test_inbox_give: applied")
