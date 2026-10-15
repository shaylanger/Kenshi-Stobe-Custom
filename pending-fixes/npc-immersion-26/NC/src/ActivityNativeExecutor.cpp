#include "ActivityNativeExecutor.h"
#include "ActivityPolicySupport.h"
#include "AutonomyExecutor.h"
#include "KenshiAiCompat.h"
#include "KenshiBuildingCompat.h"
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/CharBody.h>
#include <kenshi/CharMovement.h>
#include <kenshi/Tasker.h>
#include <kenshi/GameData.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <algorithm>
#include <cmath>
#include <float.h>
#include <cstdint>
namespace Stobe { namespace Activity {
namespace {
unsigned Count(Inventory* inventory, const std::string& sid) {
 if (!inventory || sid.empty()) return 0;
 unsigned n=0;
 const lektor<Item*>& items=inventory->getAllItems();
 for (unsigned i=0;i<items.size();++i) {
  Item* item=items.stuff[i];
  if (item && item->data && item->data->stringID==sid)
   n+=static_cast<unsigned>(std::max(1,item->quantity));
 }
 return n;
}
bool AliveActor(Character* actor, unsigned serial) {
 return actor && actor->getHandle().serial==serial && !actor->isDead() && !actor->isUnconcious();
}
bool SameHand(const hand& a,const hand& b) {
 return a.serial==b.serial && a.index==b.index && a.type==b.type &&
  a.container==b.container && a.containerSerial==b.containerSerial;
}
Receipt Result(Receipt::Status s, const std::string& reason) {
 Receipt r; r.status=s; r.reason=reason; return r;
}
}
NativeDestination::NativeDestination():x(0),y(0),z(0) {}
NativeExecutor::Operation::Operation():cleanupRequired(false),mineLease(false),orderCaptured(false),orderRemoved(false),orderStartTime(0),outputBaseline(0),transferRecovery(false),detached(NULL),transferSource(NULL),transferAmount(0),sourceBefore(0),recipientBefore(0) {}
NativeExecutor::NativeExecutor(NativePolicy& policy):policy_(policy),world_(NULL),now_(0) {}
bool NativeExecutor::CaptureOwned(Character* actor,Operation& op,bool initial) {
 if(!actor || !SameHand(actor->getHandle(),op.actorIdentity) || op.orderRemoved)return false;
 OrdersReceiver* orders=actor->getOrdersReciever();
 if(!orders || orders->orders.list.size()!=1)return false;
 Tasker* first=orders->orders.list.front();
 if(!first || !first->taskData || static_cast<int>(first->taskData->key)!=op.owned.taskType ||
    !SameHand(first->subject,op.subjectIdentity))return false;
 if(op.request.command==Travel) {
  const Ogre::Vector3 p=first->getLocation();
  if(!_finite(p.x)||!_finite(p.y)||!_finite(p.z) || std::fabs(p.x-op.owned.x)>0.5 ||
     std::fabs(p.y-op.owned.y)>0.5 || std::fabs(p.z-op.owned.z)>0.5)return false;
 }
 const unsigned long long pointer=reinterpret_cast<unsigned long long>(first);
 if(!initial && (!op.orderCaptured || pointer!=op.owned.runtimePointer || first->startTime!=op.orderStartTime))return false;
 if(initial) {op.owned.runtimePointer=pointer;op.owned.orderCount=1;op.orderStartTime=first->startTime;op.orderCaptured=true;}
 return true;
}
bool NativeExecutor::NativeEnded(Character* actor,const Operation& op) {
 if(!actor || !SameHand(actor->getHandle(),op.actorIdentity))return false;
 OrdersReceiver* orders=actor->getOrdersReciever();
 if(!orders || !orders->orders.list.empty())return false;
 const TaskMatch& goal=orders->getCurrentGoal();
 if(goal.taskData && SameHand(goal.subject,op.subjectIdentity) &&
    (static_cast<int>(goal.key())==op.owned.taskType || op.subjectIdentity.serial!=0))return false;
 CharBody* body=actor->getBody();if(!body)return false;
 Tasker* action=body->currentAction;
 if(action && action->taskData && SameHand(action->subject,op.subjectIdentity) &&
    (static_cast<int>(action->taskData->key)==op.owned.taskType || op.subjectIdentity.serial!=0))return false;
 CharMovement* movement=actor->getMovement();
 return movement && !movement->isCurrentlyMoving();
}
void NativeExecutor::Bind(GameWorld* world,const std::string& id,Clock now) {
 // A world change invalidates pointers; never cancel an old world's order in a new one.
 if (world_!=world || worldId_!=id) { operations_.clear(); delivered_.clear(); }
 world_=world; worldId_=id; now_=now;
}
unsigned NativeExecutor::Delivered(const std::string& id) const {
 std::map<std::string,unsigned>::const_iterator it=delivered_.find(id);
 return it==delivered_.end()?0:it->second;
}
bool NativeExecutor::Observe(const Agreement& a,Target& target,Facts& facts) {
 if (!world_ || a.worldId!=worldId_) return false;
 try {
  const KenshiAi::CharacterSnapshot actor=KenshiAi::CaptureCharacter(world_,a.actor);
  facts.actorLoaded=actor.found && actor.identityMatches;
  facts.actorAlive=facts.actorLoaded && !actor.dead;
  facts.actorConscious=facts.actorAlive && !actor.unconscious;
  facts.pathFailed=actor.pathFailed; facts.delivered=Delivered(a.id);
  Character* inventoryActor=KenshiAi::ResolveCharacter(world_,a.actor);
  // Capacity is authoritative at giveItem; presence permits an attempt, never credits progress.
  facts.inventorySpace=inventoryActor && inventoryActor->getInventory()!=NULL;
  bool owns=false;
  for (std::map<std::string,Operation>::iterator it=operations_.begin();it!=operations_.end();++it) {
   Operation& op=it->second;
   if (op.agreement.id!=a.id || !op.cleanupRequired) continue;
   Character* c=KenshiAi::ResolveCharacter(world_,a.actor);
   if (c && CaptureOwned(c,op,false)) owns=true;
   else if (actor.order.orderCount>0) facts.conflictingOrder=true;
   if (op.request.command==Travel) {
    const double dx=actor.x-op.destination.x,dy=actor.y-op.destination.y,dz=actor.z-op.destination.z;
    facts.arrived=dx*dx+dy*dy+dz*dz<=64.0;
   }
  }
  if (actor.order.orderCount>0 && !owns) facts.conflictingOrder=true;
  if (a.kind!=Mine && target.serial) {
   Character* t=KenshiAi::ResolveCharacter(world_,target.serial);
   Character* c=KenshiAi::ResolveCharacter(world_,a.actor);
   if (!t || !c || t->getHandle().serial!=target.serial) { target.visible=false; return true; }
   target.dead=t->isDead(); target.defeated=target.dead || t->isUnconcious();
   target.hostile=c->isEnemy(t,true);
   target.hasRequestedItem=Count(t->getInventory(),a.resourceId)>0;
  }
  facts.target=target; return true;
 } catch (...) { return false; }
}
bool NativeExecutor::Transfer(Operation& op,Inventory* source,std::string& reason) {
 Character* actor=KenshiAi::ResolveCharacter(world_,op.agreement.actor);
 if (!source || !AliveActor(actor,op.agreement.actor) || !SameHand(actor->getHandle(),op.actorIdentity)) { reason="inventory_unavailable"; return false; }
 Inventory* recipient=actor->getInventory();
 if (!recipient || source==recipient) { reason="invalid_transfer_inventory"; return false; }
 const std::string& sid=op.agreement.resourceId;
 const unsigned already=Delivered(op.agreement.id);
 if (already>=op.agreement.quantity || !op.request.quantity) { reason="quantity_already_satisfied"; return false; }
 const unsigned beforeSource=Count(source,sid),beforeActor=Count(recipient,sid);
 unsigned available=beforeSource;
 if (op.request.command==WorkResource) {
  if (beforeSource<=op.outputBaseline) { reason="awaiting_verified_output"; return false; }
  available=std::min(beforeSource-op.outputBaseline,MineOutputCredit(op.agreement.id));
 }
 Item* item=NULL;
 const lektor<Item*>& items=source->getAllItems();
 for(unsigned i=0;i<items.size();++i) {
  Item* x=items.stuff[i];
  if(x && x->data && x->data->stringID==sid && !x->isEquipped) { item=x; break; }
 }
 if(!item) { reason="exact_resource_item_absent"; return false; }
 const unsigned amount=std::min(std::min(op.request.quantity,op.agreement.quantity-already),
  std::min(available,static_cast<unsigned>(std::max(1,item->quantity))));
 if(!amount) { reason="no_new_output"; return false; }
 Item* detached=source->removeItemDontDestroy_returnsItem(item,static_cast<int>(amount),false);
 if(!detached) { reason="detach_rejected"; return false; }
 op.transferRecovery=true; op.detached=detached; op.transferSource=source; op.transferAmount=amount;
 op.sourceBefore=beforeSource; op.recipientBefore=beforeActor;
 bool accepted=false;
 try { accepted=actor->giveItem(detached,false,false); } catch (...) {}
 if(!accepted) {
  bool restored=false;
  try { restored=source->addItem(detached,static_cast<int>(amount),false,false); } catch (...) {}
  if(restored) {
   op.detached=NULL;
   if(Count(source,sid)==beforeSource && Count(recipient,sid)==beforeActor) { op.transferRecovery=false; op.transferSource=NULL; }
  }
  reason=restored?"recipient_full":"transfer_rollback_unconfirmed"; return false;
 }
 op.detached=NULL; // Successful add may merge/destroy the detached instance.
 const unsigned afterActor=Count(recipient,sid),afterSource=Count(source,sid);
 if(afterActor!=beforeActor+amount || beforeSource!=afterSource+amount) {
  reason="transfer_postcondition_failed"; return false;
 }
 if(op.request.command==WorkResource && !ConfirmMineOutputTaken(op.agreement.id,amount)) {reason="mine_output_credit_unconfirmed";return false;}
 op.transferRecovery=false; op.detached=NULL; op.transferSource=NULL;
 delivered_[op.agreement.id]=already+amount;
 reason="exact_resource_transfer_verified"; return true;
}
bool NativeExecutor::Dispatch(const Agreement& a,const Request& r,const NativeDestination& dest,std::string& reason) {
 if (!world_ || a.worldId!=worldId_ || now_>=a.expiresAt || r.id.empty() ||
     r.agreementId!=a.id || r.actor!=a.actor || r.target!=dest.facts.serial ||
     r.candidateId!=dest.facts.candidateId || r.resourceId!=a.resourceId ||
     r.quantity>a.quantity || operations_.count(r.id)) { reason="invalid_scoped_request"; return false; }
 for(std::map<std::string,Operation>::iterator it=operations_.begin();it!=operations_.end();++it)
  if(it->second.request.actor==a.actor && it->second.cleanupRequired) { reason="previous_owned_order_not_released"; return false; }
 Target current=dest.facts;
 if(!policy_.Revalidate(a,r,current,reason)) return false;
 if(current.serial!=r.target || current.candidateId!=r.candidateId ||
   (a.kind!=ClearGroup && current.sourceId!=a.sourceId) || !current.visible || !current.reachable) {
  reason="target_scope_or_reachability_changed"; return false;
 }
 Operation op; op.agreement=a; op.request=r; op.destination=dest; op.destination.facts=current;
 try {
  Character* actor=KenshiAi::ResolveCharacter(world_,a.actor);
  if(!AliveActor(actor,a.actor)) { reason="actor_unavailable"; return false; }
  op.actorIdentity=actor->getHandle();
  OrdersReceiver* orders=actor->getOrdersReciever();
  if(!orders || orders->hasPlayerOrders() || !orders->orders.list.empty()) { reason="existing_order"; return false; }
  Character* target=NULL; Building* resource=NULL;
  if(a.kind==Mine) {
   resource=policy_.ResolveResource(a,r.target);
   if(!resource || resource->getHandle().serial!=r.target || !resource->getGameData() ||
      resource->getGameData()->stringID!=a.sourceId) { reason="resource_identity_changed"; return false; }
  } else {
   target=KenshiAi::ResolveCharacter(world_,r.target);
   if(!target || target==actor || target->getHandle().serial!=r.target || target->isPlayerCharacter()) {
    reason="target_identity_or_protection"; return false;
   }
   if(a.kind==Hunt && (!target->isAnimal() ||
      !(current.legalHunt || (r.command!=Attack && current.lootPermitted && current.harvestable)) || !target->getGameData() ||
      target->getGameData()->stringID!=a.sourceId)) { reason="not_legal_exact_hunt_source"; return false; }
   if(a.kind==ClearGroup && (std::find(a.agreedTargets.begin(),a.agreedTargets.end(),r.target)==a.agreedTargets.end() ||
      !actor->isEnemy(target,true))) { reason="not_agreed_current_hostile"; return false; }
  }
  op.targetIdentity=resource?resource->getHandle():target->getHandle();
  if(r.command==TakeItem) {
   if(a.kind!=Hunt || !current.lootPermitted || !current.harvestable ||
      !(target->isDead() || target->isUnconcious()) ||
      actor->getPosition().squaredDistance(target->getPosition())>225.0f) { reason="loot_not_permitted_or_out_of_range"; return false; }
   operations_[r.id]=op; Operation& stored=operations_[r.id];
   if(!Transfer(stored,target->getInventory(),reason)) { stored.receipt=Result(Receipt::Rejected,reason); return false; }
   stored.receipt=Result(Receipt::Succeeded,reason); return true;
  }
  TaskType task=MOVE_CUS_ORDERED;
  hand subject;
  Ogre::Vector3 point(static_cast<float>(dest.x),static_cast<float>(dest.y),static_cast<float>(dest.z));
  if(!_finite(dest.x)||!_finite(dest.y)||!_finite(dest.z)) { reason="invalid_trusted_point"; return false; }
  if(r.command==Attack) {
   if(a.kind==Mine || !target || target->isDead() || target->isUnconcious()) { reason="attack_target_not_active"; return false; }
   // Policy must reject protected/tamed sources and any ceasefire. Never break one here.
   task=UNPROVOKED_FOCUSED_MELEE_ATTACK; subject=target->getHandle(); point=target->getPosition();
  } else if(r.command==WorkResource) {
   if(a.kind!=Mine || !current.resourceUsable || !resource || resource->_NV_getSpecialFunction()!=BF_MINE_NATURAL ||
      resource->_NV_isDestroyed() || resource->_NV_isBroken()) { reason="resource_not_usable_natural_mine"; return false; }
   resource->forceValidUsageNodesValidation();
   if(!resource->hasAnyGoodPositionMarkersLeft()) { reason="resource_occupied"; return false; }
   operations_[r.id]=op;
   if(!BeginMineLease(a.id,actor,resource,a.resourceId,reason))return false;
   op.mineLease=true;operations_[r.id].mineLease=true;
   Inventory* output=policy_.ResourceOutput(a,resource);
   if(!output) { reason="verified_output_inventory_unavailable"; return false; }
   op.outputBaseline=Count(output,a.resourceId);
   task=OPERATE_MACHINERY; subject=resource->getHandle(); point=resource->getPosition();
  } else if(r.command!=Travel) { reason="unsupported_activity_command"; return false; }
  const int jobs=orders->getPermajobCount(); const bool enabled=orders->isJobsEnabled();
  // Register before mutation so any exception retains an identifiable cleanup obligation.
  op.owned.taskType=static_cast<int>(task); op.owned.subjectSerial=r.command==Travel?0:r.target;
  op.owned.x=point.x; op.owned.y=point.y; op.owned.z=point.z;op.subjectIdentity=subject;
  op.cleanupRequired=true;
  operations_[r.id]=op; Operation& stored=operations_[r.id];
  orders->addOrder(task,subject,point,false,false);
  if(!CaptureOwned(actor,stored,true) || jobs!=orders->getPermajobCount() || enabled!=orders->isJobsEnabled()) {
   reason="owned_order_or_jobs_unconfirmed"; stored.receipt=Result(Receipt::Rejected,reason); return false;
  }
  if(r.command==Attack) actor->attackTarget(target);
  actor->reThinkCurrentAIAction();
  reason="scoped_native_order_dispatched"; return true;
 } catch (...) {
  reason="native_dispatch_exception";
  std::map<std::string,Operation>::iterator it=operations_.find(r.id);
  if(it!=operations_.end()) {
   it->second.receipt=Result(Receipt::Rejected,reason);
   // addOrder may have mutated before throwing. Record the single order from
   // this uninterrupted game-thread call; no unrelated existing order was allowed.
   try {
    Character* c=KenshiAi::ResolveCharacter(world_,a.actor);
    if(c && !it->second.orderCaptured && it->second.cleanupRequired)CaptureOwned(c,it->second,true);
   } catch (...) {}
  }
  return false;
 }
}
Receipt NativeExecutor::Poll(const std::string& id) {
 std::map<std::string,Operation>::iterator it=operations_.find(id);
 if(it==operations_.end()) return Result(Receipt::Rejected,"unknown_request");
 Operation& op=it->second;
 if(op.receipt.status!=Receipt::Pending) return op.receipt;
 try {
  Character* actor=KenshiAi::ResolveCharacter(world_,op.request.actor);
  Target current=op.destination.facts; std::string reason;
  if(now_>=op.agreement.expiresAt || !AliveActor(actor,op.request.actor) || !SameHand(actor->getHandle(),op.actorIdentity) ||
     !policy_.Revalidate(op.agreement,op.request,current,reason))
   return op.receipt=Result(Receipt::Interrupted,reason.empty()?"agreement_or_actor_unavailable":reason);
  OrdersReceiver* orders=actor->getOrdersReciever();
  // Natural task completion can remove the order before this frame's poll.
  if(op.request.command==Travel) {
   Ogre::Vector3 end(static_cast<float>(op.destination.x),static_cast<float>(op.destination.y),static_cast<float>(op.destination.z));
   if(actor->getPosition().squaredDistance(end)<=64.0f)
    return op.receipt=Result(Receipt::Succeeded,"arrived_at_scoped_point");
  }
  if(op.request.command==Attack) {
   Character* target=KenshiAi::ResolveCharacter(world_,op.request.target);
   if(target && SameHand(target->getHandle(),op.targetIdentity) && (target->isDead() || target->isUnconcious()))
    return op.receipt=Result(Receipt::Succeeded,"target_defeated");
  }
  if(!CaptureOwned(actor,op,false)) return op.receipt=Result(Receipt::Interrupted,"owned_order_changed_or_ended");
  if(op.request.command==Travel) {
   Ogre::Vector3 p(static_cast<float>(op.destination.x),static_cast<float>(op.destination.y),static_cast<float>(op.destination.z));
   if(actor->getPosition().squaredDistance(p)<=64.0f) return op.receipt=Result(Receipt::Succeeded,"arrived_at_scoped_point");
   if(KenshiAi::CaptureCharacter(world_,op.request.actor).pathFailed) return op.receipt=Result(Receipt::Interrupted,"path_failed");
  } else if(op.request.command==Attack) {
   Character* target=KenshiAi::ResolveCharacter(world_,op.request.target);
   if(!target || !SameHand(target->getHandle(),op.targetIdentity)) return op.receipt=Result(Receipt::Interrupted,"target_unloaded");
   if(target->isDead() || target->isUnconcious()) return op.receipt=Result(Receipt::Succeeded,"target_defeated");
   if(op.agreement.kind==ClearGroup && !actor->isEnemy(target,true)) return op.receipt=Result(Receipt::Interrupted,"target_no_longer_hostile");
   if(op.agreement.kind==Hunt && !current.legalHunt) return op.receipt=Result(Receipt::Interrupted,"hunt_no_longer_legal");
  } else if(op.request.command==WorkResource) {
   Building* b=policy_.ResolveResource(op.agreement,op.request.target);
   if(!b || b->getHandle().serial!=op.request.target || !current.resourceUsable ||
      actor->getPosition().squaredDistance(b->getPosition())>225.0f) return op.receipt;
   if(Transfer(op,policy_.ResourceOutput(op.agreement,b),reason)) {
    if(Delivered(op.agreement.id)>=op.agreement.quantity) return op.receipt=Result(Receipt::Succeeded,reason);
    return op.receipt;
   }
   if(reason!="awaiting_verified_output" && reason!="exact_resource_item_absent" && reason!="no_new_output")
    return op.receipt=Result(Receipt::Interrupted,reason);
  }
 } catch (...) { return op.receipt=Result(Receipt::Interrupted,"native_poll_exception"); }
 return op.receipt;
}
bool NativeExecutor::SnapshotNative(const std::string& id,GoalStatusSnapshot& out) {
 std::map<std::string,Operation>::iterator it=operations_.find(id);
 if(it==operations_.end())return false;
 Operation& op=it->second;
 out.nativeEvidenceAvailable=true;out.operationTracked=true;
 out.nativeTarget=op.request.target;out.nativeTaskKey=op.owned.taskType;
 out.nativeReceiptReason=op.receipt.reason;
 switch(op.receipt.status) {
  case Receipt::Pending:out.nativeReceiptStatus="pending";break;
  case Receipt::Succeeded:out.nativeReceiptStatus="succeeded";break;
  case Receipt::Rejected:out.nativeReceiptStatus="rejected";break;
  case Receipt::Interrupted:out.nativeReceiptStatus="interrupted";break;
 }
 if(op.request.command==Attack)out.nativeTaskName="UNPROVOKED_FOCUSED_MELEE_ATTACK";
 else if(op.request.command==WorkResource)out.nativeTaskName="OPERATE_MACHINERY";
 else if(op.request.command==TakeItem)out.nativeTaskName="verified_transfer";
 else if(op.request.command==Travel)out.nativeTaskName="MOVE_CUS_ORDERED";
 out.targetInFixedSet=op.agreement.kind==ClearGroup &&
  std::find(op.agreement.agreedTargets.begin(),op.agreement.agreedTargets.end(),op.request.target)!=op.agreement.agreedTargets.end();
 out.targetInFixedSetKnown=op.agreement.kind==ClearGroup;
 try {
  Character* actor=KenshiAi::ResolveCharacter(world_,op.request.actor);
  if(!actor || !SameHand(actor->getHandle(),op.actorIdentity))return true;
  OrdersReceiver* orders=actor->getOrdersReciever();
  out.ownedTaskMatches=op.cleanupRequired && CaptureOwned(actor,op,false);
  if(out.ownedTaskMatches && orders && !orders->orders.list.empty()) {
   Tasker* first=orders->orders.list.front();
   if(first && first->taskData) {
    out.nativeTaskKey=static_cast<int>(first->taskData->key);
    out.nativeTaskSubject=first->subject.serial;
   }
  }
  CharBody* body=actor->getBody();
  Tasker* action=body?body->currentAction:NULL;
  if(action && action->taskData) {
   out.nativeActionKey=static_cast<int>(action->taskData->key);
   out.nativeActionSubject=action->subject.serial;
   out.currentActionMatchesTarget=out.nativeActionKey==op.owned.taskType &&
    SameHand(action->subject,op.subjectIdentity) && action->subject.serial==op.request.target;
   out.nativeActionName=out.currentActionMatchesTarget?op.request.command==Attack?"UNPROVOKED_FOCUSED_MELEE_ATTACK":
    op.request.command==WorkResource?"OPERATE_MACHINERY":"native_action":"other_native_action";
  }
  if(op.agreement.kind==ClearGroup) {
   Character* target=KenshiAi::ResolveCharacter(world_,op.request.target);
   if(target && SameHand(target->getHandle(),op.targetIdentity)) {
    out.targetHostilityKnown=true;out.currentTargetHostile=actor->isEnemy(target,true);
   }
  }
  if(op.request.command==WorkResource) {
   MineLeaseSnapshot mine;
   Building* building=policy_.ResolveResource(op.agreement,op.request.target);
   out.mineAttributionAvailable=InspectMineLease(op.agreement.id,actor,building,mine);
   if(out.mineAttributionAvailable) {
    out.mineActor=mine.actorSerial;out.mineBuilding=mine.buildingSerial;out.mineItem=mine.item;
    out.mineOutputBaseline=mine.baseline;out.mineOutputExpected=mine.expectedCount;out.mineOutputCount=mine.outputCount;
    out.mineCreditedOutput=mine.creditedOutput;out.mineContributionObserved=mine.contributionObserved;
    out.mineOutputCountConsistent=mine.outputCountConsistent;
    out.mineLeaseIdentityMatches=mine.identityMatches && mine.actorSerial==op.request.actor &&
     mine.buildingSerial==op.request.target && mine.item==op.request.resourceId;
   }
  }
 } catch(...) {
  // Preserve tracked receipt identity, but leave all live native evidence at its
  // initialized unknown values when a game-thread read cannot be completed.
  out.ownedTaskMatches=false;out.currentActionMatchesTarget=false;
  out.targetHostilityKnown=false;out.mineLeaseIdentityMatches=false;
 }
 return true;
}
bool NativeExecutor::RecoverTransfer(Operation& op) {
 if(!op.transferRecovery) return true;
 try {
  Character* actor=KenshiAi::ResolveCharacter(world_,op.request.actor);
  if(!actor || !SameHand(actor->getHandle(),op.actorIdentity) || !actor->getInventory()) return false;
  Inventory* source=NULL;
  if(op.agreement.kind==Mine) {
   Building* resource=policy_.ResolveResource(op.agreement,op.request.target);
   if(resource && SameHand(resource->getHandle(),op.targetIdentity)) source=RetainedMineOutput(op.agreement.id,resource,actor);
  } else {
   Character* target=KenshiAi::ResolveCharacter(world_,op.request.target);
   if(target && SameHand(target->getHandle(),op.targetIdentity)) source=target->getInventory();
  }
  // Never access a saved inventory pointer after its owning source unloads.
  if(!source || source!=op.transferSource) return false;
  const unsigned n=Count(source,op.agreement.resourceId),m=Count(actor->getInventory(),op.agreement.resourceId);
  if(n+op.transferAmount==op.sourceBefore && m==op.recipientBefore+op.transferAmount) {
   if(op.request.command==WorkResource && !ConfirmMineOutputTaken(op.agreement.id,op.transferAmount))return false;
   delivered_[op.agreement.id]+=op.transferAmount; op.transferRecovery=false; op.detached=NULL; op.transferSource=NULL; return true;
  }
  if(n==op.sourceBefore && m==op.recipientBefore) { op.transferRecovery=false; op.detached=NULL; op.transferSource=NULL; return true; }
  if(n+op.transferAmount!=op.sourceBefore || m!=op.recipientBefore) return false;
  if(!op.detached) return false;
  if(!source->addItem(op.detached,static_cast<int>(op.transferAmount),false,false)) return false;
  op.detached=NULL;
  if(Count(source,op.agreement.resourceId)!=op.sourceBefore) return false;
  op.transferRecovery=false; op.transferSource=NULL; return true;
 } catch (...) { return false; }
}
bool NativeExecutor::CancelOwned(const std::string& id) {
 std::map<std::string,Operation>::iterator it=operations_.find(id);
 if(it==operations_.end()) return true;
 Operation& op=it->second;
 if(op.agreement.worldId!=worldId_) { op.cleanupRequired=false; return true; }
 if(op.agreement.campQualified) {
  std::string campReason;
  if(!policy_.CampScopeCurrentForCleanup(op.agreement,op.request.target,campReason) &&
     op.receipt.status==Receipt::Pending)
   op.receipt=Result(Receipt::Interrupted,"camp_scope_changed_before_cleanup");
 }
 // Stop owned activity before inventory recovery: an uncertain transfer must
 // never keep a revoked mining/combat order running.
 if(op.cleanupRequired) {
  try {
   Character* actor=KenshiAi::ResolveCharacter(world_,op.request.actor);
   if(!actor || !SameHand(actor->getHandle(),op.actorIdentity))return false;
   OrdersReceiver* orders=actor->getOrdersReciever();if(!orders)return false;
   if(!orders->orders.list.empty()) {
    // Validate actual task key, full subject, start timestamp and fixed travel
    // destination before using the shared pointer/count cancellation helper.
    if(!CaptureOwned(actor,op,false))return false;
    std::string reason;
    if(!Autonomy::TryCancelOwnedOrder(world_,op.request.actor,op.owned,reason))return false;
    op.orderRemoved=true;
   }
   // Empty order queue alone is not proof: GOAP/body/movement may still run.
   if(!NativeEnded(actor,op))return false;
   op.cleanupRequired=false;
  } catch (...) {return false;}
  if(op.receipt.status==Receipt::Pending) op.receipt=Result(Receipt::Interrupted,"owned_native_activity_ended");
 }
 if(!RecoverTransfer(op))return false;
 if(op.mineLease){EndMineLease(op.agreement.id);op.mineLease=false;}
 return true;
}
} }
