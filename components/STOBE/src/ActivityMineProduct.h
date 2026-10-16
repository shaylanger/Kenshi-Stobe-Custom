#pragma once
// NC12 (row 25-b): pure decision for "what does this natural mine node produce".
// Natural mine nodes (special function 27) have no ProductionBuilding, so the product is taken
// from what the node's own inventory already holds, else from the item references of its game data.
// No game types, so it is testable offline.
#include <string>
#include <vector>
namespace Stobe { namespace ActivityMine {
struct ProductInputs {
 std::vector<std::string> stored;    // stringID of every item stored in the node inventory
 bool storedBad;                     // a stored item was null or had no data
 std::vector<std::string> dataItems; // distinct item stringIDs referenced by the node's game data
 std::string expected;               // item the agreement names, "" = resolve only
 ProductInputs():storedBad(false) {}
};
// Returns "" on success (item = product, how = "inventory" | "gamedata"), else the failing clause.
inline std::string ResolveNaturalProduct(const ProductInputs& in,std::string& item,std::string& how) {
 item.clear();how.clear();
 if(in.storedBad) return "stored_item_null_or_nodata";
 std::string found;
 for(size_t i=0;i<in.stored.size();++i) {
  if(in.stored[i].empty()) return "stored_item_null_or_nodata";
  if(found.empty()) found=in.stored[i];
  else if(found!=in.stored[i]) return "natural_mixed_items";
 }
 if(!found.empty()) how="inventory";
 else {
  if(in.dataItems.empty()) return "natural_product_unresolved";
  if(in.dataItems.size()>1) return "natural_product_ambiguous";
  found=in.dataItems[0]; how="gamedata";
 }
 if(!in.expected.empty() && in.expected!=found) return "natural_product_mismatch";
 item=found;
 return "";
}
}}
