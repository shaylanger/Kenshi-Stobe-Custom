#include "ActivityRuntimeBindings.h"
#include "ActivityCandidatePolicy.h"
#include "ActivityPolicySupport.h"
// Isolated HUNT4080 diagnostic: existing logger, no transport/config changes.
void Log(const std::string&);
#include "KenshiAiCompat.h"
#include "KenshiBuildingCompat.h"
#include <kenshi/Character.h>
#include <kenshi/Platoon.h>
#include <kenshi/CharMovement.h>
#include <kenshi/GameWorld.h>
#include <kenshi/HavokCharacter.h>
#include <kenshi/NavMesh.h>
#include <kenshi/SensoryData.h>
#include <kenshi/GameData.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <algorithm>
#include <set>
#include <sstream>
#include <float.h>
namespace Stobe { namespace Activity {
namespace {
std::string GroupSource(Character* member) {
 ActivePlatoon* group=member?member->getPlatoon():NULL;
 return group && group->me && group->me->squadTemplate?group->me->squadTemplate->stringID:std::string();
}
bool Equal(const Agreement& a,const Agreement& b) {
 return a.id==b.id && a.worldId==b.worldId && a.actor==b.actor && a.requester==b.requester &&
 a.sourceId==b.sourceId && a.resourceId==b.resourceId && a.kind==b.kind && a.quantity==b.quantity &&
 a.maximumTargets==b.maximumTargets && a.maximumReplans==b.maximumReplans &&
 a.expiresAt==b.expiresAt && a.noProgressTimeout==b.noProgressTimeout && a.agreedTargets==b.agreedTargets;
}
bool HasItem(Character* c,const std::string& sid) {
 Inventory* inv=c?c->getInventory():NULL; if(!inv || sid.empty()) return false;
 const lektor<Item*>& items=inv->getAllItems();
 for(unsigned i=0;i<items.size();++i) if(items.stuff[i] && items.stuff[i]->data && items.stuff[i]->data->stringID==sid) return true;
 return false;
}
}
ConcreteRuntimeBindings::ConcreteRuntimeBindings():world_(NULL),now_(0),sequence_(0) {}
void ConcreteRuntimeBindings::Bind(GameWorld* world,const std::string& id,Clock now) {
 if(world!=world_ || id!=worldId_ || now<now_) {
  for(std::map<std::string,Grant>::iterator it=grants_.begin();it!=grants_.end();++it) it->second.revoked=true;
  candidates_.clear();
 }
 world_=world; worldId_=id; now_=now;
}
bool ConcreteRuntimeBindings::ImportGrant(const Agreement& a,unsigned revision,std::string& reason) {
 if(!world_ || a.id.empty() || a.worldId!=worldId_ || !a.actor || !a.requester || a.actor==a.requester || !revision ||
 a.sourceId.empty() || a.expiresAt<=now_ || !a.maximumTargets || a.maximumTargets>64 || a.maximumReplans>16 || a.quantity>1000 || !a.noProgressTimeout ||
 (a.kind!=Hunt && a.kind!=Mine && a.kind!=ClearGroup) ||
 (a.kind!=ClearGroup && (a.sourceId.empty() || a.resourceId.empty() || !a.quantity)) ||
 (a.kind==ClearGroup && (a.agreedTargets.empty() || a.agreedTargets.size()>a.maximumTargets))) {
  reason="invalid_activity_scope"; return false;
 }
 std::vector<unsigned> checked=a.agreedTargets; std::sort(checked.begin(),checked.end());
 if(std::find(checked.begin(),checked.end(),0)!=checked.end() || std::adjacent_find(checked.begin(),checked.end())!=checked.end() ||
 std::find(checked.begin(),checked.end(),a.actor)!=checked.end() || std::find(checked.begin(),checked.end(),a.requester)!=checked.end()) { reason="invalid_fixed_target_set"; return false; }
 std::map<std::string,Grant>::iterator it=grants_.find(a.id);
 if(it!=grants_.end()) {
  if(it->second.revoked || !Equal(it->second.scope,a) || revision<it->second.revision) { reason="revoked_replayed_or_mutated_grant"; return false; }
  it->second.revision=revision; return true;
 }
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor); Character* requester=KenshiAi::ResolveCharacter(world_,a.requester);
 if(!actor || !requester || !requester->isPlayerCharacter()) { reason="grant_identity_unavailable"; return false; }
 Grant g; g.scope=a; g.revision=revision; g.actorIdentity=actor; g.requesterIdentity=requester;
 ActivePlatoon* agreedGroup=NULL;
 if(a.kind==ClearGroup) for(size_t i=0;i<a.agreedTargets.size();++i) {
  Character* member=KenshiAi::ResolveCharacter(world_,a.agreedTargets[i]);
  if(!member || !member->getGameData() || !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(member) || GroupSource(member)!=a.sourceId) { reason="fixed_target_not_observed_at_grant"; return false; }
  if(agreedGroup && agreedGroup!=member->getPlatoon()) { reason="fixed_targets_cross_native_groups"; return false; }
  agreedGroup=member->getPlatoon(); g.fixedIdentity[a.agreedTargets[i]]=member; g.fixedSource[a.agreedTargets[i]]=member->getGameData()->stringID;
 }
 grants_[a.id]=g; return true;
}
bool ConcreteRuntimeBindings::Revoke(const std::string& id,unsigned revision) {
 if(id.empty() || !revision) return false;
 Grant& g=grants_[id]; if(revision<g.revision) return false;
 g.revision=revision; g.revoked=true; return true;
}
bool ConcreteRuntimeBindings::VerifyGrant(const Agreement& a,Clock now,std::string& reason) {
 std::map<std::string,Grant>::iterator it=grants_.find(a.id);
 if(!world_ || a.worldId!=worldId_ || now<now_ || now>=a.expiresAt || it==grants_.end() || it->second.revoked || !Equal(a,it->second.scope)) {
  reason="activity_grant_missing_revoked_expired_or_changed"; return false;
 }
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
 Character* requester=KenshiAi::ResolveCharacter(world_,a.requester);
 if(!actor || actor!=it->second.actorIdentity || actor->getHandle().serial!=a.actor || !requester || requester!=it->second.requesterIdentity || requester->getHandle().serial!=a.requester || !requester->isPlayerCharacter()) {
  reason="activity_actor_or_requester_unavailable"; return false;
 }
 if(actor->isEnemy(requester,true) || requester->isEnemy(actor,true)) { reason="requester_now_hostile"; return false; }
 return true;
}
Building* ConcreteRuntimeBindings::Resource(const Agreement& a,unsigned serial) {
 if(!world_ || a.kind!=Mine || a.worldId!=worldId_) return NULL;
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor); if(!actor) return NULL;
 lektor<RootObject*> objects; world_->getObjectsWithinSphere(objects,actor->getPosition(),600.0f,BUILDING,128,(RootObject*)actor);
 for(unsigned i=0;i<objects.size();++i) {
  Building* b=(Building*)objects.stuff[i];
  if(b && b->getHandle().serial==serial && b->getGameData() && b->getGameData()->stringID==a.sourceId &&
   b->_NV_getSpecialFunction()==BF_MINE_NATURAL && !b->_NV_isDestroyed() && !b->_NV_isBroken()) return b;
 }
 return NULL;
}
Inventory* ConcreteRuntimeBindings::Output(const Agreement& a,Building* b) {
 if(!world_ || a.worldId!=worldId_ || !b || b->getGameData()==NULL || b->getGameData()->stringID!=a.sourceId) return NULL;
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor); std::string reason;
 return NaturalResourceOutput(b,actor,a.resourceId,true,reason);
}
bool ConcreteRuntimeBindings::Refresh(const Agreement& a,NativeDestination& d,std::string& reason) {
 if(!VerifyGrant(a,now_,reason)) return false;
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
 Ogre::Vector3 p; Target t; t.serial=d.facts.serial; t.candidateId=d.facts.candidateId;
 if(a.kind==Mine) {
  Building* b=Resource(a,t.serial); if(!b) { reason="natural_resource_not_observed"; return false; }
  t.sourceId=b->getGameData()->stringID; p=b->getPosition(); t.visible=true;
  std::string produced; t.resourceUsable=MineSourcePermitted(b,actor,produced,reason) && produced==a.resourceId;
 } else {
  Character* target=KenshiAi::ResolveCharacter(world_,t.serial);
  if(!target || target==actor || target->getHandle().serial!=t.serial || !target->getGameData() ||
   !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(target)) { reason="target_not_observed"; return false; }
  const bool protectedTarget=IsProtectedActivityTarget(actor,target,reason);
  t.sourceId=a.kind==ClearGroup?GroupSource(target):target->getGameData()->stringID; p=target->getPosition(); t.visible=true;
  t.hostile=actor->isEnemy(target,true); t.dead=target->isDead(); t.defeated=t.dead || target->isUnconcious();
  // Helper establishes actual ownership/truce protection, never name-based species guessing.
  t.legalHunt=!protectedTarget && target->isAnimal()!=NULL;
  t.harvestable=t.defeated; t.lootPermitted=t.legalHunt && t.harvestable;
  t.hasRequestedItem=HasItem(target,a.resourceId);
  if(a.kind==Hunt && (!target->isAnimal() || t.sourceId!=a.sourceId)) { reason="hunt_source_mismatch"; return false; }
  if(a.kind==ClearGroup && (std::find(a.agreedTargets.begin(),a.agreedTargets.end(),t.serial)==a.agreedTargets.end() || t.sourceId!=a.sourceId)) { reason="outside_fixed_hostile_set"; return false; }
 }
 CharMovement* movement=actor->getMovement(); HavokCharacter* avatar=movement?movement->havokCharacter:NULL;
 t.reachable=_finite(p.x)&&_finite(p.y)&&_finite(p.z)&& world_->navmesh && avatar && avatar->isOnNavmesh() && world_->navmesh->pathExists(avatar,p)==1;
 if(!t.reachable) reason="current_native_path_unconfirmed"; // Observation survives; dispatch still requires reachable.
 d.facts=t; d.x=p.x; d.y=p.y; d.z=p.z; return true;
}
std::vector<NativeDestination> ConcreteRuntimeBindings::Discover(const Agreement& a) {
 std::vector<NativeDestination> result; std::string reason;
 if(!VerifyGrant(a,now_,reason)) return result;
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
 lektor<RootObject*> objects; world_->getObjectsWithinSphere(objects,actor->getPosition(),600.0f,a.kind==Mine?BUILDING:CHARACTER,96,(RootObject*)actor);
 for(unsigned i=0;i<objects.size() && result.size()<32;++i) {
  RootObject* o=objects.stuff[i]; if(!o) continue;
  NativeDestination d; d.facts.serial=o->getHandle().serial;
  std::ostringstream token; token<<"activity:"<<a.id<<":"<<a.actor<<":"<<++sequence_; d.facts.candidateId=token.str();
  if(!Refresh(a,d,reason) || !d.facts.reachable) continue;
  Candidate c; c.agreement=a.id; c.point=d; c.identity=o; candidates_[d.facts.candidateId]=c; result.push_back(d);
 }
 return result;
}
bool ConcreteRuntimeBindings::Resolve(const Agreement& a,unsigned serial,const std::string& token,NativeDestination& out,std::string& reason) {
 // Observation-only resolution for fixed members that have not been selected.
 // Empty candidate ID never authorizes a native dispatch.
 if(token.empty() && a.kind==ClearGroup) {
  if(!VerifyGrant(a,now_,reason)) return false;
  Grant& g=grants_[a.id];
  std::map<unsigned,Character*>::iterator fixed=g.fixedIdentity.find(serial);
  Character* member=KenshiAi::ResolveCharacter(world_,serial);
  Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
  if(fixed==g.fixedIdentity.end() || !member || member!=fixed->second || !member->getGameData() ||
     member->getGameData()->stringID!=g.fixedSource[serial] || !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(member)) {
   reason="fixed_target_observation_unavailable"; return false;
  }
  out=NativeDestination(); out.facts.serial=serial; out.facts.sourceId=a.sourceId;
  out.facts.visible=true; out.facts.dead=member->isDead(); out.facts.defeated=out.facts.dead || member->isUnconcious();
  out.facts.hostile=actor->isEnemy(member,true);
  const Ogre::Vector3 p=member->getPosition(); out.x=p.x;out.y=p.y;out.z=p.z; return true;
 }
 std::map<std::string,Candidate>::iterator it=candidates_.find(token);
 if(it==candidates_.end() || it->second.agreement!=a.id || it->second.point.facts.serial!=serial) { reason="unregistered_actor_destination"; return false; }
 RootObject* current=a.kind==Mine?(RootObject*)Resource(a,serial):(RootObject*)KenshiAi::ResolveCharacter(world_,serial);
 if(!current || current!=it->second.identity) { reason="registered_source_instance_changed"; return false; }
 out=it->second.point; if(!Refresh(a,out,reason)) return false;
 if(out.facts.sourceId!=it->second.point.facts.sourceId) { reason="registered_source_identity_changed"; return false; }
 return true;
}
bool ConcreteRuntimeBindings::ActivityPermitted(const Agreement& a,const Request& r,Target& out,std::string& reason) {
 if(r.candidateId.empty() || r.agreementId!=a.id || r.actor!=a.actor || r.resourceId!=a.resourceId || r.quantity>a.quantity) { reason="request_scope_mismatch"; return false; }
 NativeDestination d; if(!Resolve(a,r.target,r.candidateId,d,reason)) return false; out=d.facts;
 if(!out.visible || !out.reachable) { reason="activity_target_not_visible_or_reachable"; return false; }
  if(a.kind!=Mine) {
  Character* actor=KenshiAi::ResolveCharacter(world_,a.actor); Character* target=KenshiAi::ResolveCharacter(world_,r.target);
  if(IsProtectedActivityTarget(actor,target,reason)) return false;
 }
 if(r.command==Travel) return true;
 if(r.command==Attack && ((a.kind==Hunt && out.legalHunt) || (a.kind==ClearGroup && out.hostile)) && !out.defeated) return true;
 if(r.command==TakeItem && a.kind==Hunt && out.lootPermitted && out.harvestable && out.hasRequestedItem) return true;
 if(r.command==WorkResource && a.kind==Mine && out.resourceUsable) return true;
 reason="activity_not_currently_permitted"; return false;
}
} }





namespace Stobe { namespace Activity {
namespace {
// Bounded same-call diagnostic only; never re-runs discovery or path checks.
struct ProposalTrace {
 unsigned actor,requester; size_t registry; unsigned emitted,exceptions,objects,sightDrops,pathDrops,capacityDrops,reused,nullDrops,finiteDrops,typeDrops,serialDrops,pathZero,pathOne,pathOther;
 bool world,actorOk,requesterOk,player,distinct,dead,unconscious,movement,avatar,navmesh,onmesh;
 unsigned charSphere,buildingSphere; const char* gate; std::string actorSid,requesterSid,focus;
 ProposalTrace(unsigned a,unsigned r,size_t n):actor(a),requester(r),registry(n),emitted(0),exceptions(0),objects(0),sightDrops(0),pathDrops(0),capacityDrops(0),reused(0),nullDrops(0),finiteDrops(0),typeDrops(0),serialDrops(0),pathZero(0),pathOne(0),pathOther(0),world(false),actorOk(false),requesterOk(false),player(false),distinct(false),dead(false),unconscious(false),movement(false),avatar(false),navmesh(false),onmesh(false),charSphere(0),buildingSphere(0),gate("world") {}
 void Focus(const char* text,bool reset=false) { try { if(reset) focus=text; else focus+=text; } catch(...) {} }
 void FocusPath(int raw,const std::string& sid) { try { std::ostringstream s; s<<" pathRaw="<<raw<<" sourceSID="; const std::string bounded=sid.substr(0,256); for(size_t i=0;i<bounded.size();++i) s<<(bounded[i]<32?'_':bounded[i]); focus+=s.str(); } catch(...) {} }
 void FocusSerial(unsigned serial) { try { std::ostringstream s; s<<" serial="<<serial; focus+=s.str(); } catch(...) {} }
 void Sids(Character* a,Character* r) { try { Character* chars[2]={a,r}; std::string* slots[2]={&actorSid,&requesterSid}; for(unsigned n=0;n<2;++n) { try { if(chars[n] && chars[n]->getGameData()) { *slots[n]=chars[n]->getGameData()->stringID.substr(0,256); for(size_t i=0;i<slots[n]->size();++i) if((*slots[n])[i]<32) (*slots[n])[i]='_'; } } catch(...) {} } } catch(...) {} }
 ~ProposalTrace() {
  try { std::ostringstream s; s<<"ACTIVITY_PROPOSAL_DIAG actor="<<actor<<" requester="<<requester<<" gate="<<gate
   <<" world="<<world<<" actorOk="<<actorOk<<" requesterOk="<<requesterOk<<" player="<<player<<" distinct="<<distinct
   <<" dead="<<dead<<" unconscious="<<unconscious<<" actorSID="<<actorSid<<" requesterSID="<<requesterSid
   <<" movement="<<movement<<" avatar="<<avatar<<" navmesh="<<navmesh<<" onmesh="<<onmesh
   <<" sphereCharacter="<<charSphere<<" sphereBuilding="<<buildingSphere<<" sphereCap=96 objects="<<objects
   <<" sightDrops="<<sightDrops<<" pathDrops="<<pathDrops<<" registryBefore="<<registry<<" capacityDrops="<<capacityDrops
   <<" reused="<<reused<<" nullDrops="<<nullDrops<<" finiteDrops="<<finiteDrops<<" typeDrops="<<typeDrops<<" serialDrops="<<serialDrops<<" pathZero="<<pathZero<<" pathOne="<<pathOne<<" pathOther="<<pathOther<<" exceptions="<<exceptions<<" emitted="<<emitted<<" focusGoat960815424="<<(focus.empty()?"not_enumerated":focus);
   Log(s.str()); } catch(...) { /* Diagnostics never change proposal outcome. */ }
 }
};
std::string ProposalQuote(const std::string& s) {
 std::ostringstream out; out << '"';
 for(size_t i=0;i<s.size();++i) {
  const unsigned char c=static_cast<unsigned char>(s[i]);
  if(c=='"' || c=='\\') out << '\\' << static_cast<char>(c);
  else if(c<32) { const char* h="0123456789abcdef"; out << "\\u00" << h[c>>4] << h[c&15]; }
  else out << static_cast<char>(c);
 }
 out << '"'; return out.str();
}
}
std::string ConcreteRuntimeBindings::ProposalFacts(unsigned actorSerial,unsigned requesterSerial) {
 ProposalTrace trace(actorSerial,requesterSerial,candidates_.size());
 std::ostringstream out; out << "{\"candidates\":["; bool first=true;
 for(std::map<std::string,Candidate>::iterator old=candidates_.begin();old!=candidates_.end();) {
  if(old->second.agreement.empty() && (now_<old->second.observedAt || now_-old->second.observedAt>86400)) candidates_.erase(old++); else ++old;
 }
 trace.world=world_!=NULL && !worldId_.empty();
 if(!trace.world) return "{\"candidates\":[]}";
 Character* actor=KenshiAi::ResolveCharacter(world_,actorSerial);
 Character* requester=KenshiAi::ResolveCharacter(world_,requesterSerial);
 trace.gate="identity"; trace.actorOk=actor!=NULL; trace.requesterOk=requester!=NULL;
 trace.Sids(actor,requester);
 if(!actor || !requester) return "{\"candidates\":[]}";
 trace.player=requester->isPlayerCharacter(); trace.distinct=actor!=requester;
 if(!trace.player || !trace.distinct) return "{\"candidates\":[]}";
 trace.dead=actor->isDead(); if(trace.dead) return "{\"candidates\":[]}";
 trace.unconscious=actor->isUnconcious(); if(trace.unconscious) return "{\"candidates\":[]}";
 const KenshiAi::CharacterSnapshot snapshot=KenshiAi::CaptureCharacter(world_,actorSerial);
 const bool conflict=snapshot.order.orderCount>0;
 CharMovement* movement=actor->getMovement(); HavokCharacter* avatar=movement?movement->havokCharacter:NULL;
 trace.gate="navigation"; trace.movement=movement!=NULL; trace.avatar=avatar!=NULL; trace.navmesh=world_->navmesh!=NULL;
 if(!world_->navmesh || !avatar) return "{\"candidates\":[]}";
 trace.onmesh=avatar->isOnNavmesh(); if(!trace.onmesh) return "{\"candidates\":[]}";
 trace.gate="enumeration";
 unsigned emitted=0;
 std::map<ActivePlatoon*,std::vector<unsigned> > clearGroupTargets;
 std::set<ActivePlatoon*> clearGroupsScanned;
 for(unsigned pass=0;pass<2;++pass) {
  lektor<RootObject*> objects; world_->getObjectsWithinSphere(objects,actor->getPosition(),600.0f,pass?BUILDING:CHARACTER,96,(RootObject*)actor);
  if(pass) trace.buildingSphere=objects.size(); else trace.charSphere=objects.size();
  for(unsigned i=0;i<objects.size() && emitted<32;++i) {
   ++trace.objects; bool focus=false;
   try {
    RootObject* object=objects.stuff[i]; if(!object || !object->getGameData()) { ++trace.nullDrops; continue; }
    try { focus=object->getHandle().serial==960815424u; } catch(...) { /* Diagnostic-only read cannot skip a candidate. */ }
    if(focus) trace.Focus("enumerated",true);
    const Ogre::Vector3 p=object->getPosition();
    if(!_finite(p.x)||!_finite(p.y)||!_finite(p.z)) { ++trace.finiteDrops; if(focus) trace.Focus("finite=0",true); continue; }
    if(focus) trace.Focus("finite=1",true);
    bool hostile=false,protectedTarget=false,permitted=false; const char* kind=""; std::string resourceId; std::string proposalSource=object->getGameData()->stringID; std::vector<unsigned> groupTargets;
    std::string why;
    if(!pass) {
     Character* target=(Character*)object;
     if(target==actor || target==requester || !actor->getSensoryData()) { ++trace.sightDrops; if(focus) trace.Focus(" sightPrerequisite=0"); continue; }
     const bool visible=actor->getSensoryData()->canISeeThisGuy(target);
     if(focus) trace.Focus(visible?" canSee=1":" canSee=0");
     if(!visible) { ++trace.sightDrops; continue; }
     hostile=actor->isEnemy(target,true);
     if(!target->isAnimal() && !hostile) { ++trace.typeDrops; if(focus) trace.Focus(" animalOrHostile=0"); continue; }
     if(focus) trace.Focus(" animalOrHostile=1");
     kind=target->isAnimal()?"Hunt":"ClearGroup";
     protectedTarget=IsProtectedActivityTarget(actor,target,why);
     permitted=!protectedTarget && !target->isDead() && !target->isUnconcious();
     if(!target->isAnimal()) {
      ActivePlatoon* platoon=target->getPlatoon();
      proposalSource=GroupSource(target); if(proposalSource.empty() || !platoon) continue;
      if(clearGroupsScanned.insert(platoon).second) {
       std::vector<ClearGroupMemberEvidence> evidence;
       for(unsigned j=0;j<objects.size();++j) {
        Character* member=(Character*)objects.stuff[j];
        if(!member || member==actor || member==requester || member->getPlatoon()!=platoon) continue;
        ClearGroupMemberEvidence row; row.serial=member->getHandle().serial;
        row.visible=actor->getSensoryData()->canISeeThisGuy(member);
        row.hostile=actor->isEnemy(member,true);
        std::string memberReason; row.protectedTarget=IsProtectedActivityTarget(actor,member,memberReason);
        row.active=!member->isDead() && !member->isUnconcious();
        const Ogre::Vector3 memberPosition=member->getPosition();
        row.finitePosition=_finite(memberPosition.x) && _finite(memberPosition.y) && _finite(memberPosition.z);
        if(row.serial && row.visible && row.hostile && !row.protectedTarget && row.active && row.finitePosition)
         row.pathConfirmed=world_->navmesh->pathExists(avatar,memberPosition)==1;
        evidence.push_back(row);
       }
       clearGroupTargets[platoon]=SelectClearGroupTargets(evidence);
      }
      groupTargets=clearGroupTargets[platoon];
      if(groupTargets.empty() || groupTargets.size()>32 || target->getHandle().serial!=groupTargets.front()) continue;
     }
    } else {
     Building* b=(Building*)object;
     if(b->_NV_getSpecialFunction()!=BF_MINE_NATURAL || b->_NV_isBroken() || b->_NV_isDestroyed()) continue;
     kind="Mine";
     // Read-only exact production/ownership check. Attribution lease begins only at dispatch.
     permitted=MineSourcePermitted(b,actor,resourceId,why); protectedTarget=!permitted;
    }
    const int rawPath=world_->navmesh->pathExists(avatar,p);
    if(rawPath==0) ++trace.pathZero; else if(rawPath==1) ++trace.pathOne; else ++trace.pathOther;
    if(focus) trace.FocusPath(rawPath,proposalSource);
    if(rawPath!=1) { ++trace.pathDrops; continue; }
    const unsigned serial=object->getHandle().serial;
    if(focus) trace.FocusSerial(serial);
    if(!serial) { ++trace.serialDrops; continue; }
    std::string stableToken;
    for(std::map<std::string,Candidate>::iterator prior=candidates_.begin();prior!=candidates_.end();++prior) {
     const Candidate& old=prior->second;
     if(old.agreement.empty() && old.actorIdentity==actor && old.requesterIdentity==requester && old.identity==object &&
        old.point.facts.serial==serial && old.point.facts.sourceId==proposalSource) { stableToken=prior->first; break; }
    }
    std::ostringstream token;
    if(!stableToken.empty()) { token<<stableToken; ++trace.reused; if(focus) trace.Focus(" reuse=1"); }
    else { if(focus) trace.Focus(" reuse=0"); if(candidates_.size()>=2048) { ++trace.capacityDrops; if(focus) trace.Focus(" capacity=full"); continue; } token<<"activity-proposal:"<<actorSerial<<":"<<++sequence_; }
    Candidate c; c.agreement=""; c.identity=object; c.actorIdentity=actor; c.requesterIdentity=requester; c.observedAt=now_; c.point.facts.serial=serial;
    c.point.facts.sourceId=proposalSource; c.point.facts.candidateId=token.str();
    c.point.x=p.x;c.point.y=p.y;c.point.z=p.z; candidates_[token.str()]=c;
    if(focus) trace.Focus(" emitted=1");
    if(!first) out<<','; first=false; ++emitted; trace.emitted=emitted; std::ostringstream fixedTargets; for(size_t member=0;member<groupTargets.size();++member) { if(member) fixedTargets<<','; fixedTargets<<groupTargets[member]; }
    out << "{\"kind\":"<<ProposalQuote(kind)<<",\"sourceId\":"<<ProposalQuote(c.point.facts.sourceId)
     <<",\"resourceId\":"<<ProposalQuote(resourceId)<<",\"targetSerial\":"<<serial<<",\"candidateId\":"<<ProposalQuote(token.str())
     <<",\"pathReachable\":true,\"observedNow\":true,\"suitable\":"<<(permitted?"true":"false")
     <<",\"activityPermitted\":"<<(permitted?"true":"false")<<",\"protectedTarget\":"<<(protectedTarget?"true":"false")
     <<",\"hostile\":"<<(hostile?"true":"false")<<",\"conflictingOrder\":"<<(conflict?"true":"false")
     <<",\"agreedTargets\":["<<fixedTargets.str()<<"],\"x\":"<<p.x<<",\"y\":"<<p.y<<",\"z\":"<<p.z
     <<",\"scopeLabel\":"<<ProposalQuote(std::string(kind)=="ClearGroup"?"currently observed hostile members of this native group":"observed exact source")<<",\"policyReason\":"<<ProposalQuote(why)<<"}";
   } catch(...) { ++trace.exceptions; if(focus) trace.Focus(" exception=1"); /* One unloaded entity never turns into assumed permission. */ }
  }
 }
 trace.gate="complete"; out << "]}"; return out.str();
}
} }








