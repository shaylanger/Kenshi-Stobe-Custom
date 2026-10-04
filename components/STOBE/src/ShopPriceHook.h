#pragma once
// Item 104: Kenshi's own shop prices follow the trader's relationship toward
// the trading squad member (ShopPricing.h has the math, the server contract is
// pending-fixes/relationship-pricing-interface.md).
//
// Hooked: the item value functions the trade code prices with
// (InventoryItemBase/Weapon/Armour/BlueprintItem/MapItem::getValueSingle(bool
// isPlayer); isPlayer=true is the price the player pays, false what the trader
// pays). They only change while a player trade is going on (an open
// trade-for-money window, or inside Inventory::buyItem between a squad member
// and an NPC). r comes from a local cache filled by a background thread from
// relationship_pricing.php; a missing entry means vanilla until it arrives.

#include <string>
#include <windows.h>

class Character;

namespace Stobe {
namespace ShopPrice {

// Installs the value hooks (call once from startPlugin, KenshiLib loaded).
void Install(HMODULE kenshiLib);

// Inventory::buyItem wrapper: call BeginBuy before the original with the two
// sides resolved to characters (null if a side isn't a character, e.g. shop
// storage). Returns true when the trade must be refused (r <= -80): then
// don't call the original, return null. Always call EndBuy afterwards.
bool BeginBuy(Character *buyer, Character *seller);
void EndBuy();

// Drops all cached r values (load/new game).
void ClearCache();

// Test command stobe_shopprice: forget and refetch r for (trader, player),
// reply with what is cached right now.
std::string DebugRefresh(Character *trader, Character *player);

} // namespace ShopPrice
} // namespace Stobe
