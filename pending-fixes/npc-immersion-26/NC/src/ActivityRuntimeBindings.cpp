#include "ActivityRuntimeBindings.h"
#include "ActivityDiscoveryRef.h"
#include "ActivityCandidatePolicy.h"
#include "ActivityPolicySupport.h"
#include "LocalTravel.h"
#include "PlaythroughSession.h"
#include "NativeTravelLifecycle.h"
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
std::string ProposalQuote(const std::string&);
std::string GroupSource(Character* member) {
 ActivePlatoon* group=member?member->getPlatoon():NULL;
 return group && group->me && group->me->squadTemplate?group->me->squadTemplate->stringID:std::string();
}
bool Equal(const Agreement& a,const Agreement& b) {
 return a.id==b.id && a.worldId==b.worldId && a.actor==b.actor && a.requester==b.requester &&
 a.discoveryCandidateId==b.discoveryCandidateId && a.discoveryTargetSerial==b.discoveryTargetSerial &&
 a.sourceId==b.sourceId && a.resourceId==b.resourceId && a.kind==b.kind && a.quantity==b.quantity &&
 a.maximumTargets==b.maximumTargets && a.maximumReplans==b.maximumReplans &&
 a.expiresAt==b.expiresAt && a.noProgressTimeout==b.noProgressTimeout && a.agreedTargets==b.agreedTargets &&
 a.routeCandidateId==b.routeCandidateId && a.routeWorldId==b.routeWorldId && a.routeKind==b.routeKind &&
 a.routeLabel==b.routeLabel && a.routeX==b.routeX && a.routeY==b.routeY && a.routeZ==b.routeZ && a.routeActor==b.routeActor &&
 a.scopeVersion==b.scopeVersion && a.campQualified==b.campQualified &&
 a.campZoneCandidateId==b.campZoneCandidateId && a.campZoneDigest==b.campZoneDigest &&
 a.scopeDigest==b.scopeDigest && a.dispatchEnvelope==b.dispatchEnvelope;
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
 std::ostringstream session; session<<id<<":"<<PlaythroughSession::Generation();
 campCatalog_.BeginScope(id,session.str());
}
bool ConcreteRuntimeBindings::ValidateCampTarget(const Agreement& a,Character* target,
 const ActivityCampNative::ZoneCandidate& zone,std::string& reason) {
 if(!a.campQualified) return true;
 ActivityCampNative::ZoneCandidate current;
 if(!world_ || a.worldId!=worldId_ || a.campZoneCandidateId!=zone.zoneCandidateId ||
    zone.worldScope!=worldId_ || !ActivityCampNative::ValidFacts(zone.town) ||
    !campCatalog_.Resolve(a.campZoneCandidateId,now_,86400,current) ||
    !ActivityCampNative::SameFacts(current.town,zone.town) || current.sessionScope!=zone.sessionScope) {
  reason="camp_world_or_session_scope_changed"; return false;
 }
 if(!target || !target->isValid() || target->getHandle().serial==0) { reason="camp_target_identity_unavailable"; return false; }
 const Ogre::Vector3 p=target->getPosition(); bool inside=false;
 if(!campCatalog_.IsWithinNativeBorders(zone.town,p.x,p.y,p.z,inside) || !inside) {
  reason="camp_target_left_native_borders"; return false;
 }
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
 if(!actor || !actor->isEnemy(target,true)) { reason="camp_target_not_currently_hostile"; return false; }
 if(IsProtectedActivityTarget(actor,target,reason)) { reason="camp_target_is_protected"; return false; }
 std::vector<unsigned long long> fixed;
 for(size_t i=0;i<a.agreedTargets.size();++i) fixed.push_back(a.agreedTargets[i]);
 std::string liveDigest;
 if(!campCatalog_.DigestConsent(zone,fixed,liveDigest) || liveDigest!=a.campZoneDigest) {
  reason="camp_consent_scope_digest_mismatch"; return false;
 }
 return true;
}
bool ConcreteRuntimeBindings::ImportGrant(const Agreement& a,unsigned revision,std::string& reason) {
 if(!world_ || a.id.empty() || a.worldId!=worldId_ || !a.actor || !a.requester || a.actor==a.requester || !revision ||
 !ValidDiscoveryReference(a.discoveryCandidateId,a.discoveryTargetSerial) ||
 a.sourceId.empty() || a.expiresAt<=now_ || !a.maximumTargets || a.maximumTargets>64 || a.maximumReplans>16 || a.quantity>1000 || !a.noProgressTimeout ||
 a.routeCandidateId.empty() || a.routeCandidateId.size()>96 || a.routeWorldId!=a.worldId || a.routeActor!=a.actor ||
 a.routeLabel.empty() || a.routeLabel.size()>120 || !_finite(a.routeX) || !_finite(a.routeY) || !_finite(a.routeZ) ||
 (a.kind!=Hunt && a.kind!=Mine && a.kind!=ClearGroup) ||
 (a.kind!=ClearGroup && (a.sourceId.empty() || a.resourceId.empty() || !a.quantity)) ||
 (a.campQualified && (a.kind!=ClearGroup || a.scopeVersion!=3 ||
    a.campZoneCandidateId.size()<16 || a.campZoneCandidateId.size()>128 ||
    a.campZoneDigest.size()!=64)) ||
 (!a.campQualified && a.scopeVersion!=1) ||
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
 // The server's reference must resolve to the precise source candidate emitted
 // by this native world, actor and requester, while that observation is fresh.
 std::map<std::string,Candidate>::iterator discovered=candidates_.find(a.discoveryCandidateId);
 const bool found=discovered!=candidates_.end();
 const bool actorAndRequesterMatch=found && discovered->second.actorIdentity!=NULL && discovered->second.requesterIdentity!=NULL;
 if(!CanBindDiscoveryReference(a.discoveryCandidateId,a.discoveryTargetSerial,
    found?discovered->second.point.facts.candidateId:std::string(),
    found?discovered->second.point.facts.serial:0,found,found && discovered->second.agreement.empty(),
    actorAndRequesterMatch,now_,found?discovered->second.observedAt:now_)) {
  reason="activity_discovery_reference_missing_malformed_mismatched_or_stale"; return false;
 }
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor); Character* requester=KenshiAi::ResolveCharacter(world_,a.requester);
 if(!actor || !requester || !requester->isPlayerCharacter()) { reason="grant_identity_unavailable"; return false; }
 if(actor!=discovered->second.actorIdentity || requester!=discovered->second.requesterIdentity) {
  reason="activity_discovery_reference_actor_or_requester_mismatch"; return false;
 }
 if(a.campQualified && (!discovered->second.campQualified ||
    discovered->second.fixedTargets!=a.agreedTargets ||
    discovered->second.campZone.zoneCandidateId!=a.campZoneCandidateId ||
    discovered->second.campZoneDigest!=a.campZoneDigest)) {
  reason="camp_scope_not_bound_to_native_displayed_proposal"; return false;
 }
 if(!LocalTravel::ValidateForDispatch(world_,actor,a.routeCandidateId,a.routeX,a.routeY,a.routeZ,a.routeLabel,reason)) return false;
 RootObject* discoveredObject=NULL;
 if(a.kind==Mine) discoveredObject=(RootObject*)Resource(a,a.discoveryTargetSerial);
 else discoveredObject=(RootObject*)KenshiAi::ResolveCharacter(world_,a.discoveryTargetSerial);
 if(!discoveredObject || discoveredObject!=discovered->second.identity ||
    discoveredObject->getHandle().serial!=a.discoveryTargetSerial) {
  reason="activity_discovery_reference_identity_unavailable"; return false;
 }
 if(a.kind==Mine) {
  Building* mine=(Building*)discoveredObject;
  std::string produced;
  if(!mine->getGameData() || mine->getGameData()->stringID!=a.sourceId ||
     !MineSourcePermitted(mine,actor,produced,reason) || produced!=a.resourceId) {
   reason="activity_discovery_reference_source_mismatch"; return false;
  }
 } else {
  Character* target=(Character*)discoveredObject;
  if(!target->getGameData() || !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(target) ||
     (a.kind==Hunt && (target->getGameData()->stringID!=a.sourceId || !target->isAnimal())) ||
     (a.kind==ClearGroup && (GroupSource(target)!=a.sourceId ||
       std::find(a.agreedTargets.begin(),a.agreedTargets.end(),a.discoveryTargetSerial)==a.agreedTargets.end()))) {
   reason="activity_discovery_reference_source_mismatch"; return false;
  }
 }
 Grant g; g.scope=a; g.revision=revision; g.actorIdentity=actor; g.requesterIdentity=requester;
 if(a.campQualified) {
  ActivityCampNative::ZoneCandidate current;
  std::vector<unsigned long long> fixed;
  for(size_t n=0;n<a.agreedTargets.size();++n) fixed.push_back(a.agreedTargets[n]);
  if(!campCatalog_.Resolve(a.campZoneCandidateId,now_,86400,current) ||
     !ActivityCampNative::SameFacts(current.town,discovered->second.campZone.town) ||
     current.worldScope!=worldId_ || current.sessionScope!=discovered->second.campZone.sessionScope ||
     !campCatalog_.DigestConsent(current,fixed,g.scope.campZoneDigest) ||
     g.scope.campZoneDigest!=a.campZoneDigest) { reason="camp_zone_identity_or_digest_not_current"; return false; }
  g.campZone=current;
 }
 ActivePlatoon* agreedGroup=NULL;
 if(a.kind==ClearGroup) for(size_t i=0;i<a.agreedTargets.size();++i) {
  Character* member=KenshiAi::ResolveCharacter(world_,a.agreedTargets[i]);
  if(!member || !member->getGameData() || !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(member) || (!a.campQualified && GroupSource(member)!=a.sourceId)) { reason="fixed_target_not_observed_at_grant"; return false; }
  if(!a.campQualified && agreedGroup && agreedGroup!=member->getPlatoon()) { reason="fixed_targets_cross_native_groups"; return false; }
  if(a.campQualified && !ValidateCampTarget(a,member,g.campZone,reason)) return false;
  agreedGroup=member->getPlatoon(); g.fixedIdentity[a.agreedTargets[i]]=member; g.fixedSource[a.agreedTargets[i]]=member->getGameData()->stringID;
 }
 discovered->second.agreement=a.id;
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
 if(a.campQualified) {
  Grant& grant=it->second;
  if(grant.campZone.zoneCandidateId!=a.campZoneCandidateId ||
     grant.fixedIdentity.size()!=a.agreedTargets.size()) { reason="camp_native_binding_missing"; return false; }
  for(size_t i=0;i<a.agreedTargets.size();++i) {
   Character* target=KenshiAi::ResolveCharacter(world_,a.agreedTargets[i]);
   std::map<unsigned,Character*>::iterator fixed=grant.fixedIdentity.find(a.agreedTargets[i]);
   if(fixed==grant.fixedIdentity.end() || !target || target!=fixed->second ||
      !ValidateCampTarget(a,target,grant.campZone,reason)) return false;
  }
 }
 return true;
}
bool ConcreteRuntimeBindings::CampScopeCurrentForCleanup(const Agreement& a,unsigned targetSerial,std::string& reason) {
 if(!a.campQualified) return true;
 std::map<std::string,Grant>::iterator it=grants_.find(a.id);
 if(!world_ || a.worldId!=worldId_ || it==grants_.end() ||
    !Equal(a,it->second.scope) || it->second.campZone.zoneCandidateId!=a.campZoneCandidateId ||
    std::find(a.agreedTargets.begin(),a.agreedTargets.end(),targetSerial)==a.agreedTargets.end()) {
  reason="camp_scope_binding_unavailable_during_cleanup"; return false;
 }
 Grant& grant=it->second;
 for(size_t i=0;i<a.agreedTargets.size();++i) {
  Character* target=KenshiAi::ResolveCharacter(world_,a.agreedTargets[i]);
  std::map<unsigned,Character*>::iterator fixed=grant.fixedIdentity.find(a.agreedTargets[i]);
  if(fixed==grant.fixedIdentity.end() || !target || target!=fixed->second ||
     !ValidateCampTarget(a,target,grant.campZone,reason)) return false;
 }
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
  if(a.campQualified) {
   std::map<std::string,Grant>::iterator grant=grants_.find(a.id);
   if(grant==grants_.end() || !ValidateCampTarget(a,target,grant->second.campZone,reason)) return false;
  }
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
 // Activities remain bound to the exact source the user and server agreed to.
 // A nearby substitute is never silently selected after route travel.
 NativeDestination agreed; std::map<std::string,Candidate>::const_iterator source=candidates_.find(a.discoveryCandidateId);
 if(source==candidates_.end() || source->second.agreement!=a.id ||
    source->second.point.facts.serial!=a.discoveryTargetSerial ||
    !Resolve(a,a.discoveryTargetSerial,a.discoveryCandidateId,agreed,reason) || !agreed.facts.visible || !agreed.facts.reachable)
  return result;
 result.push_back(agreed); return result;
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
     member->getGameData()->stringID!=g.fixedSource[serial] || !actor || !actor->getSensoryData() ||
     !actor->getSensoryData()->canISeeThisGuy(member) ||
     (a.campQualified && !ValidateCampTarget(a,member,g.campZone,reason))) {
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
bool ConcreteRuntimeBindings::DispatchRoute(const Agreement& a,const Request& r,std::string& reason) {
 if(!VerifyGrant(a,now_,reason) || r.command!=RouteTravel || r.agreementId!=a.id || r.actor!=a.actor || r.target!=0 ||
    r.candidateId!=a.routeCandidateId || a.routeActor!=a.actor || a.routeWorldId!=worldId_) {
  if(reason.empty())reason="route_request_scope_mismatch";return false;
 }
 Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
 if(!actor || !LocalTravel::ValidateForDispatch(world_,actor,a.routeCandidateId,a.routeX,a.routeY,a.routeZ,a.routeLabel,reason))return false;
 if(a.scopeDigest.size()!=64 || a.scopeDigest.find_first_not_of("0123456789abcdef")!=std::string::npos ||
    a.dispatchEnvelope.empty()) { reason="authenticated_activity_v2_scope_missing"; return false; }
 if(NativeTravelLifecycle::Start(world_,actor,a.requester,NULL,a.routeX,a.routeY,a.routeZ,a.id,r.id,a.worldId,
   a.scopeDigest,a.dispatchEnvelope,static_cast<long long>(a.expiresAt),static_cast<long long>(now_),reason))return true;
 // Start may reject after addOrder partially mutated. A recorded exact request
 // remains owned until PollRoute/CancelRoute confirms its native cleanup.
 std::string phase,why,task;bool arrived=false,released=false;
 if(NativeTravelLifecycle::InspectRequest(a.actor,a.requester,a.id,r.id,a.worldId,PlaythroughSession::Generation(),a.scopeDigest,phase,why,task,arrived,released)) {
  reason="route_dispatch_recorded_cleanup_required";return true;
 }
 return false;
}
Receipt ConcreteRuntimeBindings::PollRoute(const Agreement& a,const std::string& id) {
 Receipt out;std::string phase,why,task;bool arrived=false,released=false;
 if(!NativeTravelLifecycle::InspectRequest(a.actor,a.requester,a.id,id,a.worldId,PlaythroughSession::Generation(),a.scopeDigest,phase,why,task,arrived,released)) {
  out.status=Receipt::Rejected;out.reason="route_request_missing_or_identity_changed";return out;
 }
 if(phase=="running" || phase=="dispatching" || !released) {
  out.status=Receipt::Pending;out.reason=arrived?"route_arrived_cleanup_pending":why;return out;
 }
 if(phase=="completed" && arrived && released) { out.status=Receipt::Succeeded;out.reason="verified_route_arrival_and_cleanup";return out; }
 out.status=(phase=="cancelled"?Receipt::Interrupted:Receipt::Rejected);
 out.reason=why.empty()?"route_did_not_reach_verified_endpoint":why;return out;
}
bool ConcreteRuntimeBindings::CancelRoute(const Agreement& a,const std::string& id) {
 if(a.campQualified) { std::string scopeReason; (void)CampScopeCurrentForCleanup(a,a.discoveryTargetSerial,scopeReason); }
 std::string phase,why,task;bool arrived=false,released=false;
 if(!NativeTravelLifecycle::InspectRequest(a.actor,a.requester,a.id,id,a.worldId,PlaythroughSession::Generation(),a.scopeDigest,phase,why,task,arrived,released))return false;
 if(released)return true;
 if(task.empty())return false;
 return NativeTravelLifecycle::ReleaseOwned(world_,a.actor,a.requester,a.id,id,a.worldId,PlaythroughSession::Generation(),a.scopeDigest,task,why) ||
        NativeTravelLifecycle::InspectRequest(a.actor,a.requester,a.id,id,a.worldId,PlaythroughSession::Generation(),a.scopeDigest,phase,why,task,arrived,released) && released;
}
} }





namespace Stobe { namespace Activity {
namespace {
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
 std::ostringstream out; out << "{\"candidates\":["; bool first=true;
 for(std::map<std::string,Candidate>::iterator old=candidates_.begin();old!=candidates_.end();) {
  if(old->second.agreement.empty() && (now_<old->second.observedAt || now_-old->second.observedAt>86400)) candidates_.erase(old++); else ++old;
 }
 if(!world_ || worldId_.empty()) return "{\"candidates\":[]}";
 Character* actor=KenshiAi::ResolveCharacter(world_,actorSerial);
 Character* requester=KenshiAi::ResolveCharacter(world_,requesterSerial);
 if(!actor || !requester) return "{\"candidates\":[]}";
 if(!requester->isPlayerCharacter() || actor==requester || actor->isDead() || actor->isUnconcious()) return "{\"candidates\":[]}";
 const KenshiAi::CharacterSnapshot snapshot=KenshiAi::CaptureCharacter(world_,actorSerial);
 const bool conflict=snapshot.order.orderCount>0;
 CharMovement* movement=actor->getMovement(); HavokCharacter* avatar=movement?movement->havokCharacter:NULL;
 if(!world_->navmesh || !avatar) return "{\"candidates\":[]}";
 if(!avatar->isOnNavmesh()) return "{\"candidates\":[]}";
 std::vector<ActivityCampNative::ZoneCandidate> zones;
 (void)campCatalog_.Discover(now_,zones);
 unsigned emitted=0;
 std::map<ActivePlatoon*,std::vector<unsigned> > clearGroupTargets;
 std::set<ActivePlatoon*> clearGroupsScanned;
 for(unsigned pass=0;pass<2;++pass) {
  lektor<RootObject*> objects; world_->getObjectsWithinSphere(objects,actor->getPosition(),600.0f,pass?BUILDING:CHARACTER,96,(RootObject*)actor);
  for(unsigned i=0;i<objects.size() && emitted<32;++i) {
   try {
    RootObject* object=objects.stuff[i]; if(!object || !object->getGameData()) continue;
    const Ogre::Vector3 p=object->getPosition();
    if(!_finite(p.x)||!_finite(p.y)||!_finite(p.z)) continue;
    bool hostile=false,protectedTarget=false,permitted=false; const char* kind=""; std::string resourceId; std::string proposalSource=object->getGameData()->stringID; std::vector<unsigned> groupTargets;
    ActivityCampNative::ZoneCandidate proposedCamp; bool proposedCampQualified=false;
    std::string why;
    if(!pass) {
     Character* target=(Character*)object;
     if(target==actor || target==requester || !actor->getSensoryData()) continue;
     const bool visible=actor->getSensoryData()->canISeeThisGuy(target);
     if(!visible) continue;
     hostile=actor->isEnemy(target,true);
     if(!target->isAnimal() && !hostile) continue;
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
      // A formal zone is exposed only when the NPC and every fixed hostile
      // target are currently inside that exact native TownList entry.
      if(!zones.empty() && groupTargets.size()<=32) {
       std::vector<unsigned long long> fixed;
       for(size_t k=0;k<groupTargets.size();++k) fixed.push_back(groupTargets[k]);
       unsigned matches=0;
       size_t matchIndex=0;
       for(size_t z=0;z<zones.size();++z) {
        bool actorInside=false;
        if(!campCatalog_.IsWithinNativeBorders(zones[z].town,actor->getPosition().x,actor->getPosition().y,actor->getPosition().z,actorInside) || !actorInside) continue;
        bool allInside=true;
        for(size_t k=0;k<groupTargets.size();++k) {
         Character* member=KenshiAi::ResolveCharacter(world_,groupTargets[k]); bool inside=false;
         if(!member || !member->isValid() || member->isDead() || member->isUnconcious() ||
            !actor->isEnemy(member,true) || IsProtectedActivityTarget(actor,member,why) ||
            !actor->getSensoryData()->canISeeThisGuy(member) ||
            !campCatalog_.IsWithinNativeBorders(zones[z].town,member->getPosition().x,member->getPosition().y,member->getPosition().z,inside) || !inside) { allInside=false; break; }
        }
        if(!allInside) continue;
        std::string digest;
        if(!campCatalog_.DigestConsent(zones[z],fixed,digest)) continue;
        ++matches; matchIndex=z;
       }
       if(matches==1) {
        proposedCamp=zones[matchIndex]; proposedCampQualified=true;
       }
      }
     }
    } else {
     Building* b=(Building*)object;
     if(b->_NV_getSpecialFunction()!=BF_MINE_NATURAL || b->_NV_isBroken() || b->_NV_isDestroyed()) continue;
     kind="Mine";
     // Read-only exact production/ownership check. Attribution lease begins only at dispatch.
     permitted=MineSourcePermitted(b,actor,resourceId,why); protectedTarget=!permitted;
    }
    const int rawPath=world_->navmesh->pathExists(avatar,p);
    if(rawPath!=1) continue;
    const unsigned serial=object->getHandle().serial;
    if(!serial) continue;
    std::string stableToken;
    for(std::map<std::string,Candidate>::iterator prior=candidates_.begin();prior!=candidates_.end();++prior) {
     const Candidate& old=prior->second;
     if(old.agreement.empty() && old.actorIdentity==actor && old.requesterIdentity==requester && old.identity==object &&
        old.point.facts.serial==serial && old.point.facts.sourceId==proposalSource &&
        old.campQualified==proposedCampQualified && (!proposedCampQualified ||
        (old.fixedTargets==groupTargets && old.campZone.zoneCandidateId==proposedCamp.zoneCandidateId))) { stableToken=prior->first; break; }
    }
    std::ostringstream token;
    if(!stableToken.empty()) token<<stableToken;
    else { if(candidates_.size()>=2048) continue; token<<"activity-proposal:"<<actorSerial<<":"<<++sequence_; }
    Candidate c; c.agreement=""; c.identity=object; c.actorIdentity=actor; c.requesterIdentity=requester; c.observedAt=now_;
    c.campQualified=proposedCampQualified; if(proposedCampQualified) {
     c.campZone=proposedCamp; std::vector<unsigned long long> fixed;
     for(size_t k=0;k<groupTargets.size();++k) fixed.push_back(groupTargets[k]);
     if(!campCatalog_.DigestConsent(c.campZone,fixed,c.campZoneDigest)) c.campQualified=false;
    }
    c.fixedTargets=groupTargets; c.point.facts.serial=serial;
    c.point.facts.sourceId=proposalSource; c.point.facts.candidateId=token.str();
    c.point.x=p.x;c.point.y=p.y;c.point.z=p.z; candidates_[token.str()]=c;
    if(!first) out<<','; first=false; ++emitted; std::ostringstream fixedTargets; for(size_t member=0;member<groupTargets.size();++member) { if(member) fixedTargets<<','; fixedTargets<<groupTargets[member]; }
    out << "{\"kind\":"<<ProposalQuote(kind)<<",\"sourceId\":"<<ProposalQuote(c.point.facts.sourceId)
     <<",\"resourceId\":"<<ProposalQuote(resourceId)<<",\"targetSerial\":"<<serial<<",\"candidateId\":"<<ProposalQuote(token.str())
     <<",\"pathReachable\":true,\"observedNow\":true,\"suitable\":"<<(permitted?"true":"false")
     <<",\"activityPermitted\":"<<(permitted?"true":"false")<<",\"protectedTarget\":"<<(protectedTarget?"true":"false")
     <<",\"hostile\":"<<(hostile?"true":"false")<<",\"conflictingOrder\":"<<(conflict?"true":"false")
     <<",\"x\":"<<p.x<<",\"y\":"<<p.y<<",\"z\":"<<p.z;
    if(c.campQualified) out<<",\"campZone\":{\"candidateId\":"<<ProposalQuote(c.campZone.zoneCandidateId)<<",\"scopeDigest\":"<<ProposalQuote(c.campZoneDigest)<<"},\"campZoneLabel\":"<<ProposalQuote(c.campZone.town.knownName);
    out<<",\"agreedTargets\":["<<fixedTargets.str()<<"]"
     <<",\"scopeLabel\":"<<ProposalQuote(std::string(kind)=="ClearGroup"?(c.campQualified?"only the currently observed hostile targets inside this named formal zone":"currently observed hostile members of this native group"):"observed exact source")<<",\"policyReason\":"<<ProposalQuote(why)<<"}";
   } catch(...) { /* One unloaded entity never turns into assumed permission. */ }
  }
 }
 out << "]}"; return out.str();
}
} }








