#pragma once
// Pure (no game types) decision for "is this animal proven wild" so it is testable offline.
// NC8 (Shay 2026-10-15): an animal in no real faction, in an animals-only non-trader roaming
// squad with no base/home/occupied town, no slaves and no stuff IS wild. The squad template's
// faction/species refs are no longer required (they stay a non-blocking note).
#include <string>
namespace Stobe { namespace ActivityWild {
struct WildFacts {
 bool identity;          // faction, faction data, platoon, squad and game data all readable
 bool factionNotReal;    // faction->isNotARealFaction()
 bool fundamentalNone;   // faction->fundamentalNPCType==OT_NONE
 bool animalsOnly;       // platoon->isAnimalsOnly
 bool trader;            // platoon->getIsTrader()
 bool roaming;           // squad type == SQ_ROAMING
 bool baseTown;          // squad->myBaseHomeTownData
 bool homeTown;          // ownerships._homeTown
 bool homeBuilding;      // ownerships._homeBuilding.serial
 bool occupiedTown;      // ownerships.occupiedTown
 bool slaves;            // !ownerships.slaves.empty()
 bool stuff;             // ownerships.stuff.size()
 WildFacts():identity(false),factionNotReal(false),fundamentalNone(false),animalsOnly(false),
  trader(false),roaming(false),baseTown(false),homeTown(false),homeBuilding(false),
  occupiedTown(false),slaves(false),stuff(false) {}
};
// Individual ownership flags for the refusal log (NC9): which one marks a squad as owned.
inline std::string Flags(const WildFacts& f) {
 std::string o="baseTown="; o+=f.baseTown?"1":"0";
 o+=" homeTown="; o+=f.homeTown?"1":"0";
 o+=" homeBuilding="; o+=f.homeBuilding?"1":"0";
 o+=" occupiedTown="; o+=f.occupiedTown?"1":"0";
 o+=" slaves="; o+=f.slaves?"1":"0";
 o+=" stuff="; o+=f.stuff?"1":"0";
 return o;
}
// Returns "" when proven wild, else the specific failing clause as a policy reason code.
inline const char* Verdict(const WildFacts& f) {
 if(!f.identity) return "animal_not_wild_identity_unavailable";
 if(!f.factionNotReal || !f.fundamentalNone) return "animal_not_wild_real_faction";
 if(!f.animalsOnly || f.trader || !f.roaming) return "animal_not_wild_squad_type";
 if(f.baseTown || f.homeTown || f.homeBuilding || f.occupiedTown || f.slaves || f.stuff)
  return "animal_not_wild_ownership";
 return "";
}
}}
