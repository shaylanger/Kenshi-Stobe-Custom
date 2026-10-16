#pragma once
// imm26 10-f option A: a save-persistent per-item id for repair evidence.
// Mechanism (same as Profession Gear's proven ProfessionGearPersistentId, TEST_PLAN rows 314-318):
//   Item::serialiseInInventory  -> the item's saved GameData gets sdata["StobeDurableItemId"]
//   Item::loadFromSerialiseInInventory -> the id is read back and bound to the NEW runtime handle.
// Kenshi runtime handles (hand.serial) are reused after a reload, so the id is the only identity
// that survives save/load. Ids are stamped lazily (theft/transfer evidence time), never on every item.
#include <string>
#include <windows.h>

class Item;

namespace Stobe {
namespace DurableItem {

// Hook the two Item (de)serialise functions. Call once from startPlugin, KenshiLib loaded.
void Install(HMODULE kenshiLib);
// Forget all runtime bindings (load / new game / import start; items rebind as they load).
void Reset();
// Existing id of this live item, "" if none (never creates).
std::string IdOf(Item *item);
// Id of this live item; creates and binds one when missing. "" if the item is not eligible.
std::string Stamp(Item *item);

} // namespace DurableItem
} // namespace Stobe
