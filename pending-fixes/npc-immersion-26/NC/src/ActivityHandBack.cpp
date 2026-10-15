#include "ActivityHandBack.h"
#include "ActivityHandBackPolicy.h"
#include "KenshiAiCompat.h"
#include "NativeTravelLifecycle.h"
#include "PlaythroughSession.h"
#include <kenshi/Character.h>
#include <kenshi/GameData.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <kenshi/GameWorld.h>
#include <kenshi/util/hand.h>
#include <algorithm>
#include <cmath>
#include <float.h>
#include <windows.h>
namespace Stobe { namespace Activity {
struct HandBackHost::Entry {
 HandBack::Machine machine; std::string requestId, task; bool followIssued;
 Entry() : followIssued(false) {}
};
namespace {
unsigned Count(Inventory* inventory, const std::string& sid) {
 if (!inventory || sid.empty()) return 0;
 unsigned n = 0;
 const lektor<Item*>& items = inventory->getAllItems();
 for (unsigned i = 0; i < items.size(); ++i) {
  Item* item = items.stuff[i];
  if (item && item->data && item->data->stringID == sid) n += static_cast<unsigned>(std::max(1, item->quantity));
 }
 return n;
}
Item* FirstUnequipped(Inventory* inventory, const std::string& sid) {
 const lektor<Item*>& items = inventory->getAllItems();
 for (unsigned i = 0; i < items.size(); ++i) {
  Item* x = items.stuff[i];
  if (x && x->data && x->data->stringID == sid && !x->isEquipped) return x;
 }
 return NULL;
}
bool Alive(Character* c, unsigned serial) { return c && c->getHandle().serial == serial && !c->isDead(); }
// Moves up to `amount` of the exact resource from the actor's inventory into the requester's.
// Same detach / give / verify-count pattern as NativeExecutor::Transfer; any doubt is a failure.
bool TransferToRequester(Character* actor, Character* requester, const std::string& sid, unsigned amount,
                         unsigned& moved, std::string& reason) {
 moved = 0;
 Inventory* source = actor ? actor->getInventory() : NULL;
 Inventory* target = requester ? requester->getInventory() : NULL;
 if (!source || !target || source == target || sid.empty() || !amount) { reason = "inventory_unavailable"; return false; }
 const unsigned beforeSource = Count(source, sid), beforeTarget = Count(target, sid);
 if (beforeSource < amount) { reason = "reward_not_in_actor_inventory"; return false; }
 for (unsigned guard = 0; moved < amount && guard < 8; ++guard) {
  Item* item = FirstUnequipped(source, sid);
  if (!item) { reason = "exact_resource_item_absent"; break; }
  const unsigned take = std::min(amount - moved, static_cast<unsigned>(std::max(1, item->quantity)));
  Item* detached = source->removeItemDontDestroy_returnsItem(item, static_cast<int>(take), false);
  if (!detached) { reason = "detach_rejected"; break; }
  bool accepted = false;
  try { accepted = requester->giveItem(detached, false, false); } catch (...) {}
  if (!accepted) {
   bool restored = false;
   try { restored = source->addItem(detached, static_cast<int>(take), false, false); } catch (...) {}
   reason = restored ? "recipient_full" : "transfer_rollback_unconfirmed";
   break;
  }
  moved += take;
 }
 const unsigned afterSource = Count(source, sid), afterTarget = Count(target, sid);
 if (afterTarget != beforeTarget + moved || beforeSource != afterSource + moved) {
  reason = "transfer_postcondition_failed"; moved = 0; return false;
 }
 if (moved == 0) { if (reason.empty()) reason = "no_item_moved"; return false; }
 reason = "exact_resource_handed_to_requester"; return true;
}
}
HandBackHost::HandBackHost() : world_(NULL), now_(0) {}
HandBackHost::~HandBackHost() { Clear(); }
void HandBackHost::Bind(GameWorld* world, const std::string& worldId, Clock gameNow) { world_ = world; worldId_ = worldId; now_ = gameNow; }
void HandBackHost::Forget(const std::string& id) {
 std::map<std::string, Entry*>::iterator i = entries_.find(id);
 if (i == entries_.end()) return;
 delete i->second; entries_.erase(i);
}
void HandBackHost::Clear() {
 for (std::map<std::string, Entry*>::iterator i = entries_.begin(); i != entries_.end(); ++i) delete i->second;
 entries_.clear();
}
void HandBackHost::Step(const Agreement& a, bool goalComplete, bool goalEnded, bool cleanupComplete, unsigned delivered, HandBackView& view) {
 view = HandBackView();
 Entry*& slot = entries_[a.id];
 if (!slot) { slot = new Entry(); slot->requestId = a.id + ":hb"; }
 Entry& e = *slot;
 HandBack::Input in;
 in.enabled = a.handBack; in.delivers = a.kind != ClearGroup; in.goalComplete = goalComplete; in.goalEnded = goalEnded;
 in.cleanupComplete = cleanupComplete; in.delivered = delivered; in.nowMs = GetTickCount();
 Character* actor = NULL; Character* requester = NULL;
 if (world_ && !e.machine.Finished() && goalEnded && cleanupComplete) {
  try {
   actor = KenshiAi::ResolveCharacter(world_, a.actor);
   requester = KenshiAi::ResolveCharacter(world_, a.requester);
   in.actorAvailable = Alive(actor, a.actor) && !actor->isUnconcious();
   in.requesterAvailable = Alive(requester, a.requester);
   if (in.actorAvailable) in.inActorInventory = Count(actor->getInventory(), a.resourceId);
   if (in.actorAvailable && in.requesterAvailable) {
    const float d2 = actor->getPosition().squaredDistance(requester->getPosition());
    if (_finite(d2)) in.distance = std::sqrt(d2);
   }
  } catch (...) { in.actorAvailable = false; }
 }
 if (e.followIssued || e.machine.Active()) {
  std::string phase, why, task; bool arrived = false, released = false;
  if (NativeTravelLifecycle::InspectRequest(a.actor, a.requester, a.id, e.requestId, a.worldId, PlaythroughSession::Generation(),
        a.scopeDigest, phase, why, task, arrived, released)) {
   in.followStarted = true; in.followReleased = released; e.task = task; e.followIssued = true;
   in.followFailed = phase != "running" && phase != "dispatching";
  }
 }
 const HandBack::Output out = e.machine.Step(in);
 try {
  if (out.action == HandBack::ActStartFollow && actor && requester) {
   std::string why;
   const Ogre::Vector3 p = requester->getPosition();
   e.followIssued = true;
   const bool ok = NativeTravelLifecycle::Start(world_, actor, a.requester, requester, p.x, p.y, p.z, a.id, e.requestId, a.worldId,
     a.scopeDigest, a.dispatchEnvelope.empty() ? std::string("handback:") + a.id : a.dispatchEnvelope,
     static_cast<long long>(now_) + 900, static_cast<long long>(now_), why);
   std::string phase, why2, task; bool arrived = false, released = false;
   if (NativeTravelLifecycle::InspectRequest(a.actor, a.requester, a.id, e.requestId, a.worldId, PlaythroughSession::Generation(),
         a.scopeDigest, phase, why2, task, arrived, released)) { in.followStarted = true; e.task = task; }
   e.machine.FollowStartResult(ok, why, in);
  } else if (out.action == HandBack::ActTransfer && actor && requester) {
   unsigned moved = 0; std::string why;
   const bool ok = TransferToRequester(actor, requester, a.resourceId, out.amount, moved, why);
   e.machine.TransferResult(ok, moved, why, in);
  } else if (out.action == HandBack::ActReleaseFollow && !e.task.empty()) {
   std::string why;
   NativeTravelLifecycle::ReleaseOwned(world_, a.actor, a.requester, a.id, e.requestId, a.worldId, PlaythroughSession::Generation(),
     a.scopeDigest, e.task, why);
  }
 } catch (...) {
  e.machine.TransferResult(false, 0, "hand_back_exception", in);
 }
 view.holds = e.machine.HoldsTerminal();
 view.returning = e.machine.Returning();
 view.finished = e.machine.Finished(); view.status = e.machine.Status(); view.reason = e.machine.Reason(); view.amount = e.machine.Amount();
}
} }
