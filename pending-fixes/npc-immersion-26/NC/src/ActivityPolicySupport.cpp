#include "ActivityPolicySupport.h"
#include "Functions.h"
#include "KenshiBuildingCompat.h"
#include <core/Functions.h>
#include <kenshi/Character.h>
#include <kenshi/GameData.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <kenshi/Faction.h>
#include <kenshi/Platoon.h>
#include <map>
#include <algorithm>
#include <float.h>
#include <limits>
namespace Stobe { namespace Activity {
namespace {
bool HasRef(GameData* data,const char* list,const std::string& sid) {
 const Ogre::vector<GameDataReference>::type* refs=data ? data->getReferenceListIfExists(list):NULL;
 if(!refs) return false;
 for(size_t i=0;i<refs->size();++i) if((*refs)[i].sid==sid) return true;
 return false;
}
bool ProvenWild(Character* target) {
 Faction* faction=target->getFaction();
 ActivePlatoon* active=target->getPlatoon();
 if(!faction || !faction->data || !faction->isNotARealFaction() ||
    faction->fundamentalNPCType!=OT_NONE || !active || !active->isAnimalsOnly ||
    active->getIsTrader() || !active->me) return false;
 Platoon* squad=active->me;
 const Ownerships& owned=squad->ownerships;
 if(squad->getSquadType()!=SQ_ROAMING || squad->myBaseHomeTownData ||
    owned._homeTown || owned._homeBuilding.serial || owned.occupiedTown ||
    !owned.slaves.empty() || owned.stuff.size() || !squad->squadTemplate ||
    !target->getGameData()) return false;
 // Require both species membership and current faction to match explicit loaded
 // squad-template provenance. A purchased/recruited animal no longer qualifies.
 // Missing/inherited or mod-ambiguous faction provenance is deliberately refused.
 return HasRef(squad->squadTemplate,"faction",faction->data->stringID) &&
  (HasRef(squad->squadTemplate,"animals",target->getGameData()->stringID) ||
   HasRef(squad->squadTemplate,"animals2",target->getGameData()->stringID));
}
struct MineLease {
 std::string id,item;
 Building* building; Character* actor;
 unsigned buildingSerial,actorSerial;
 Inventory* inventory; InventorySection* section;
 unsigned expected,baseline,credit;
 bool valid,firstEmission,contribution;
 MineLease():building(NULL),actor(NULL),buildingSerial(0),actorSerial(0),inventory(NULL),section(NULL),
 expected(0),baseline(0),credit(0),valid(true),firstEmission(true),contribution(false) {}
};
std::map<std::string,MineLease> leases;
typedef void (__fastcall *OperateFn)(ProductionBuilding*,Character*,float);
typedef void (__fastcall *OutputFn)(ProductionBuilding*,float);
OperateFn originalOperate=NULL;
OutputFn originalOutput=NULL;
bool hookAttempted=false, hooksReady=false;

InventorySection* ExactSection(Building* b,const std::string& item) {
 if(!b || static_cast<int>(b->_NV_getSpecialFunction())!=27 ||
    b->_NV_isDestroyed() || !b->_NV_getProductionBuilding()) return NULL;
 StorageBuilding::ConsumptionItem* product=b->_NV_getProductionBuilding()->getProductionItem();
 if(!product || !product->item || product->item->stringID!=item || !product->inventorySection) return NULL;
 InventorySection* out=product->inventorySection;
 Inventory* inventory=b->getInventory();
 if(!inventory || out->getInventory()!=inventory) return NULL;
 // Executor uses inventory-level detach; allow that only when EVERY stored item
 // belongs to this exact output section. Inputs or unrelated storage fail closed.
 const lektor<Item*>& all=inventory->getAllItems();
 for(unsigned i=0;i<all.size();++i)
  if(!all.stuff[i] || !all.stuff[i]->data || all.stuff[i]->data->stringID!=item ||
     !out->hasItem(all.stuff[i])) return NULL;
 return out;
}
unsigned Count(InventorySection* section) {
 unsigned total=0;
 const Ogre::vector<InventorySection::SectionItem>::type& items=section->getItems();
 for(size_t i=0;i<items.size();++i) {
  if(!items[i].item) continue;
  const unsigned q=static_cast<unsigned>(std::max(1,items[i].item->quantity));
  if(total>std::numeric_limits<unsigned>::max()-q) throw 0;
  total+=q;
 }
 return total;
}
bool Identity(MineLease& l) {
 return l.actor && l.building && l.actor->getHandle().serial==l.actorSerial &&
 l.building->getHandle().serial==l.buildingSerial &&
 ExactSection(l.building,l.item)==l.section && l.section->getInventory()==l.inventory;
}
bool Check(MineLease& l) {
 if(!l.valid) return false;
 if(!Identity(l) || Count(l.section)!=l.expected) {l.valid=false;return false;}
 return true;
}
void __fastcall Operate(ProductionBuilding* b,Character* actor,float amount) {
 // Observe all contributors; never change native work or unrelated buildings.
 try {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i) {
   MineLease& l=i->second;
   if(l.building!=b || !l.valid) continue;
   if(!Check(l) || !actor || actor!=l.actor || actor->getHandle().serial!=l.actorSerial ||
      !_finite(amount) || amount<0) {l.valid=false;continue;}
   if(amount>0) l.contribution=true;
  }
 } catch(...) {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i)
   if(i->second.building==b) i->second.valid=false;
 }
 originalOperate(b,actor,amount);
}
void __fastcall Output(ProductionBuilding* b,float amount) {
 // Check before native output so an external deposit cannot masquerade as output.
 try {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i)
   if(i->second.building==b && i->second.valid) Check(i->second);
 } catch(...) {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i)
   if(i->second.building==b) i->second.valid=false;
 }
 originalOutput(b,amount);
 try {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i) {
   MineLease& l=i->second;
   if(l.building!=b || !l.valid) continue;
   if(!Identity(l)) {l.valid=false;continue;}
   const unsigned now=Count(l.section);
   if(now<l.expected) {l.valid=false;continue;}
   const unsigned emitted=now-l.expected;
   if(emitted) {
    // Whole first output event may include work accumulated before the lease.
    // It is deliberately never credited, even when the output was initially empty.
    if(!l.firstEmission && l.contribution && _finite(amount) && amount>0) {
     if(l.credit>std::numeric_limits<unsigned>::max()-emitted) l.valid=false;
     else l.credit+=emitted;
    }
    l.firstEmission=false; l.contribution=false;
   }
   l.expected=now;
  }
 } catch(...) {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i)
   if(i->second.building==b) i->second.valid=false;
 }
}
bool Install() {
 if(hookAttempted) return hooksReady;
 hookAttempted=true;
 const bool op=KenshiLib::AddHook((void*)KenshiLib::GetRealAddress(&ProductionBuilding::_NV_operate),
  (void*)Operate,(void**)&originalOperate)==KenshiLib::SUCCESS;
 const bool out=KenshiLib::AddHook((void*)KenshiLib::GetRealAddress(&ProductionBuilding::_NV_updateOutput),
  (void*)Output,(void**)&originalOutput)==KenshiLib::SUCCESS;
 hooksReady=op && out; return hooksReady;
}
}
bool IsProtectedActivityTarget(Character* actor,Character* target,std::string& reason) {
 if(!actor || !target || actor==target) {reason="target_identity_unavailable";return true;}
 try {
  if(target->isPlayerCharacter() || actor->getFaction()==target->getFaction() ||
     actor->isAlly(target,true) || target->isAlly(actor,true)) {reason="player_same_faction_or_ally";return true;}
  if(ShouldSuppressFactionCeasefireAttack(actor,target) || HasActivePersonalTruce(actor,target)) {
   reason="active_ceasefire";return true;
  }
  if(target->getMySlaveOwner().serial) {reason="owned_target";return true;}
  if(target->isAnimal()) {
   if(!ProvenWild(target)) {reason="animal_ownership_not_proven_wild";return true;}
   reason.clear();return false;
  }
  if(!actor->isEnemy(target,true)) {reason="non_hostile_target";return true;}
  reason.clear();return false;
 } catch(...) {reason="target_protection_unavailable";return true;}
}
bool BeginMineLease(const std::string& id,Character* actor,Building* b,const std::string& item,std::string& reason) {
 if(id.empty() || !actor || !b || item.empty()) {reason="invalid_mine_lease";return false;}
 try {
  std::map<std::string,MineLease>::iterator found=leases.find(id);
  if(found!=leases.end()) {
   MineLease& l=found->second;
   if(l.actor==actor && l.building==b && l.item==item && Check(l)) return true;
   reason="mine_lease_identity_or_contribution_changed";return false;
  }
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i)
   if(i->second.building==b || i->second.actor==actor) {reason="conflicting_mine_lease";return false;}
  std::string resolvedItem;
  if(!MineSourcePermitted(b,actor,resolvedItem,reason) || resolvedItem!=item) {
   if(reason.empty()) reason="resource_identity_changed";return false;
  }
  InventorySection* section=ExactSection(b,item);
  if(!section || !Install()) {reason="exact_output_or_observer_unavailable";return false;}
  MineLease l; l.id=id;l.actor=actor;l.building=b;l.item=item;
  l.actorSerial=actor->getHandle().serial;l.buildingSerial=b->getHandle().serial;
  l.section=section;l.inventory=section->getInventory();l.expected=Count(section);l.baseline=l.expected;
  leases[id]=l;reason.clear();return true;
 } catch(...) {reason="mine_lease_unavailable";return false;}
}
void EndMineLease(const std::string& id) {leases.erase(id);}
void ResetMineLeases() {leases.clear();}
unsigned MineOutputCredit(const std::string& id) {
 try {std::map<std::string,MineLease>::iterator i=leases.find(id);
 return i!=leases.end() && Check(i->second) ? i->second.credit:0;} catch(...) {return 0;}
}
bool InspectMineLease(const std::string& id,Character* expectedActor,Building* expectedBuilding,MineLeaseSnapshot& out) {
 out=MineLeaseSnapshot();
 try {
  std::map<std::string,MineLease>::const_iterator i=leases.find(id);
  if(i==leases.end())return false;
  const MineLease& l=i->second;
  out.found=true;out.actorSerial=l.actorSerial;out.buildingSerial=l.buildingSerial;
  out.item=l.item;out.baseline=l.baseline;out.expectedCount=l.expected;out.creditedOutput=l.credit;
  out.contributionObserved=l.contribution;
  if(!expectedActor || !expectedBuilding || l.actor!=expectedActor || l.building!=expectedBuilding) return true;
  // These reads are safe on the game thread, but deliberately do not call
  // Check(), which can invalidate the lease as a side effect.
  out.identityMatches=l.valid && l.actor && l.building &&
   l.actor->getHandle().serial==l.actorSerial && l.building->getHandle().serial==l.buildingSerial &&
   ExactSection(l.building,l.item)==l.section && l.section && l.section->getInventory()==l.inventory;
  if(out.identityMatches) {
   out.outputCount=Count(l.section);
   out.outputCountConsistent=out.outputCount==out.expectedCount;
  }
  return true;
 } catch(...) { out.identityMatches=false;out.outputCount=0;return true; }
}
bool ConfirmMineOutputTaken(const std::string& id,unsigned amount) {
 try {
  std::map<std::string,MineLease>::iterator i=leases.find(id);if(i==leases.end()) return false;
  MineLease& l=i->second;
  if(!l.valid || !Identity(l) || !amount || amount>l.credit || amount>l.expected ||
     Count(l.section)!=l.expected-amount) {l.valid=false;return false;}
  l.expected-=amount;l.credit-=amount;return true;
 } catch(...) {return false;}
}
Inventory* NaturalResourceOutput(Building* b,Character* actor,const std::string& item,bool exclusive,std::string& reason) {
 try {
  for(std::map<std::string,MineLease>::iterator i=leases.begin();i!=leases.end();++i) {
   MineLease& l=i->second;
   if(l.building==b && l.actor==actor && l.item==item && exclusive && Check(l)) {
    reason.clear();return l.inventory;
   }
  }
 } catch(...) {}
 reason="exclusive_output_lease_unavailable";return NULL;
}
Inventory* RetainedMineOutput(const std::string& id,Building* b,Character* actor) {
 try {
  std::map<std::string,MineLease>::iterator i=leases.find(id);
  if(i!=leases.end() && i->second.building==b && i->second.actor==actor && Identity(i->second)) return i->second.inventory;
 } catch(...) {}
 return NULL;
}
} }
namespace Stobe { namespace Activity {
bool MineSourcePermitted(Building* b,Character* actor,std::string& item,std::string& reason) {
 item.clear();
 try {
  if(!b || !actor || actor->isDead() || actor->isUnconcious() ||
     static_cast<int>(b->_NV_getSpecialFunction())!=27 || b->_NV_isDestroyed()) {
   reason="natural_source_unavailable";return false;
  }
  if(b->getFaction() && b->getFaction()!=actor->getFaction()) {
   reason="resource_owned_by_other_faction";return false;
  }
  ProductionBuilding* production=b->_NV_getProductionBuilding();
  StorageBuilding::ConsumptionItem* product=production ? production->getProductionItem():NULL;
  if(!product || !product->item || product->item->stringID.empty() ||
     !ExactSection(b,product->item->stringID)) {reason="exact_output_unavailable";return false;}
  item=product->item->stringID;reason.clear();return true;
 } catch(...) {reason="resource_facts_unavailable";return false;}
}
} }
