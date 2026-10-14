#include "ActivityGoals.h"
#include <algorithm>
#include <sstream>

namespace Stobe { namespace Activity {
Agreement::Agreement() : actor(0), requester(0), kind(Hunt), quantity(0),
 maximumTargets(1), maximumReplans(3), expiresAt(0), noProgressTimeout(0) {}
Target::Target() : serial(0), visible(false), reachable(false), hostile(false),
 legalHunt(false), resourceUsable(false), lootPermitted(false), dead(false),
 defeated(false), harvestable(false), hasRequestedItem(false) {}
Facts::Facts() : actorLoaded(false), actorAlive(false), actorConscious(false),
 revoked(true), conflictingOrder(true), inventorySpace(false), arrived(false),
 pathFailed(false), delivered(0) {}
Receipt::Receipt() : status(Pending) {}
Goal::Goal() : phase_(Dormant), stopPhase_(Dormant), stopPending_(false), replanPending_(false), lastProgress_(0), lastNow_(0), delivered_(0),
 replans_(0), sequence_(0), pendingCommand_(Travel) {}

bool Goal::Start(const Agreement& terms, Clock now, Host& host) {
  if (phase_ != Dormant) return false; // One agreement per instance; no id reuse.
  std::string denial;
  if (terms.id.empty() || terms.worldId.empty() || !terms.actor || !terms.requester ||
      terms.expiresAt <= now ||
      !terms.noProgressTimeout || !terms.maximumTargets || terms.maximumTargets > 64 ||
      terms.maximumReplans > 16 || terms.sourceId.empty() ||
      (terms.kind != Hunt && terms.kind != Mine && terms.kind != ClearGroup) ||
      ((terms.kind == Hunt || terms.kind == Mine) &&
       (!terms.quantity || terms.quantity > 1000 || terms.resourceId.empty())) ||
      (terms.kind == ClearGroup && (terms.agreedTargets.empty() ||
                                   terms.agreedTargets.size() > terms.maximumTargets)) ||
      !host.Authorized(terms, now, denial)) {
    reason_ = denial.empty() ? "invalid_activity_agreement" : denial;
    return false;
  }
  std::vector<unsigned int> targets = terms.agreedTargets;
  std::sort(targets.begin(), targets.end());
  if (std::find(targets.begin(), targets.end(), 0) != targets.end() ||
      std::adjacent_find(targets.begin(), targets.end()) != targets.end() ||
      std::find(targets.begin(), targets.end(), terms.actor) != targets.end() ||
      std::find(targets.begin(), targets.end(), terms.requester) != targets.end()) {
    reason_ = "invalid_agreed_target_set"; return false;
  }
  terms_ = terms;
  phase_ = Searching;
  lastNow_ = lastProgress_ = now;
  reason_ = "activity_agreed";
  return true;
}

bool Goal::Release(Host& host) {
  if (pending_.empty()) return true;
  if (!host.CancelOwned(pending_)) return false;
  pending_.clear();
  return true;
}
void Goal::Stop(Phase phase, Host& host, const std::string& why) {
  stopPending_=true; stopPhase_=phase; stopReason_=why; replanPending_=false;
  if (!Release(host)) { reason_ = "owned_order_cleanup_pending: " + why; return; }
  stopPending_=false;
  phase_ = phase;
  reason_ = why;
}
void Goal::Cancel(Host& host, const std::string& why) { Stop(Cancelled, host, why); }
bool Goal::Suitable(const Target& t) const {
  if (!t.serial || t.serial == terms_.actor || t.serial == terms_.requester ||
      (terms_.kind != ClearGroup && t.sourceId != terms_.sourceId) || !t.visible || !t.reachable || t.candidateId.empty() ||
      std::find(attempted_.begin(), attempted_.end(), t.serial) != attempted_.end()) return false;
  if (terms_.kind == Mine) return t.resourceUsable;
  if (terms_.kind == ClearGroup)
    return t.hostile && !t.dead && !t.defeated &&
      std::find(terms_.agreedTargets.begin(), terms_.agreedTargets.end(), t.serial) != terms_.agreedTargets.end();
  return t.harvestable ? (t.lootPermitted && t.hasRequestedItem) : (!t.dead && t.legalHunt);
}
bool Goal::Issue(Command command, Host& host) {
  Request r;
  std::ostringstream id;
  id << terms_.id << ":" << ++sequence_;
  r.id = id.str(); r.agreementId = terms_.id; r.actor = terms_.actor;
  r.target = target_.serial; r.candidateId = target_.candidateId;
  r.resourceId = terms_.resourceId;
  r.quantity = terms_.quantity > delivered_ ? terms_.quantity - delivered_ : 0;
  r.command = command;
  std::string why;
  pending_ = r.id; pendingCommand_ = command; // Retain even partial failed dispatch for cleanup.
  if (!host.Dispatch(terms_, r, why)) { reason_ = why.empty() ? "dispatch_rejected" : why; return false; }
  pending_ = r.id; pendingCommand_ = command;
  return true;
}
void Goal::Replan(Clock now, Host& host, const std::string& why) {
  replanPending_=true; replanReason_=why;
  if (!Release(host)) { reason_ = "owned_order_cleanup_pending: " + why; return; }
  replanPending_=false;
  if (target_.serial) attempted_.push_back(target_.serial);
  if (++replans_ > terms_.maximumReplans || attempted_.size() >= terms_.maximumTargets) {
    phase_ = Failed; reason_ = why; return;
  }
  target_ = Target(); phase_ = Searching; reason_ = why;
  // Replanning is not progress: retain the last independently verified progress time.
  (void)now;
}

void Goal::Tick(Clock now, Host& host) {
  if (stopPending_) { Stop(stopPhase_,host,stopReason_); return; }
  if (phase_ == Dormant || phase_ == Complete || phase_ == Cancelled) return;
  if (phase_ == Failed) { if (!pending_.empty()) Release(host); return; }
  std::string denial;
  if (now < lastNow_ || now >= terms_.expiresAt || !host.Authorized(terms_, now, denial)) {
    Stop(Cancelled, host, denial.empty() ? "agreement_expired_or_clock_reset" : denial); return;
  }
  lastNow_ = now;
  if (replanPending_) { Replan(now,host,replanReason_); return; }
  Facts f = host.Observe(terms_, target_.serial);
  if (f.worldId != terms_.worldId || !f.actorLoaded || !f.actorAlive || !f.actorConscious ||
      f.revoked || f.conflictingOrder) {
    Stop(Cancelled, host, "actor_world_authority_or_order_changed"); return;
  }
  if (f.delivered < delivered_) { Stop(Failed, host, "progress_counter_regressed"); return; }
  if (f.delivered > delivered_) { delivered_ = f.delivered; lastProgress_ = now; }
  if (terms_.kind != ClearGroup && delivered_ >= terms_.quantity) {
    Stop(Complete, host, "agreed_quantity_delivered"); return;
  }

  if (terms_.kind != ClearGroup && !f.inventorySpace) {
    Stop(Failed, host, "inventory_full"); return;
  }
  // Independently defeated agreed members count only on fresh identity-bound
  // observation; missing/despawned characters never count as defeated.
  if (terms_.kind == ClearGroup) {
    for (size_t i=0; i<terms_.agreedTargets.size(); ++i) {
      unsigned int serial=terms_.agreedTargets[i];
      bool already=std::find(completed_.begin(), completed_.end(), serial)!=completed_.end();
      Facts member=host.Observe(terms_,serial);
      if (member.worldId==terms_.worldId && member.target.serial==serial &&
          member.target.visible && (member.target.dead || member.target.defeated)) {
        if(member.target.dead && std::find(confirmedDead_.begin(),confirmedDead_.end(),serial)==confirmedDead_.end())confirmedDead_.push_back(serial);
        if(!already) { completed_.push_back(serial); attempted_.push_back(serial); lastProgress_=now; }
      } else if(already && (std::find(confirmedDead_.begin(),confirmedDead_.end(),serial)==confirmedDead_.end() ||
          (member.worldId==terms_.worldId && member.target.serial==serial && member.target.visible))) {
        completed_.erase(std::remove(completed_.begin(),completed_.end(),serial),completed_.end());
        attempted_.erase(std::remove(attempted_.begin(),attempted_.end(),serial),attempted_.end());
      }
    }
    if (completed_.size()==terms_.agreedTargets.size()) {
      Stop(Complete,host,"agreed_targets_defeated"); return;
    }
  }
  if (now - lastProgress_ >= terms_.noProgressTimeout) {
    Stop(Failed, host, "activity_no_verified_progress"); return;
  }
  if (phase_ == Searching) {
    const std::vector<Target> candidates = host.Candidates(terms_);
    for (size_t i = 0; i < candidates.size(); ++i) {
      if (Suitable(candidates[i])) { target_ = candidates[i];
        // A later search with no candidates must not erase the actionable
        // reason that caused this replan. Clear it only after a replacement
        // target has actually passed the policy gate.
        replanReason_.clear();
        if (Issue(Travel, host)) phase_ = Travelling;
        else Replan(now, host, reason_);
        return;
      }
    }
    const std::string noTargetReason = replanReason_.empty()
      ? "no_observed_suitable_reachable_target"
      : replanReason_ + "; no_observed_suitable_reachable_target";
    Stop(Failed, host, noTargetReason); return;
  }
  if (f.target.serial != target_.serial || f.target.sourceId != target_.sourceId || !f.target.visible) {
    Replan(now, host, "target_unavailable_or_identity_changed"); return;
  }
  // Preserve the agreed registry point until the host explicitly revalidates it.
  target_.dead = f.target.dead; target_.defeated = f.target.defeated;
  target_.hostile = f.target.hostile; target_.legalHunt = f.target.legalHunt;
  target_.lootPermitted = f.target.lootPermitted;
  target_.hasRequestedItem = f.target.hasRequestedItem; target_.harvestable = f.target.harvestable;
  target_.resourceUsable = f.target.resourceUsable;
  if (f.pathFailed) { Replan(now, host, "path_failed"); return; }
  if (terms_.kind == ClearGroup && (target_.dead || target_.defeated)) {
    if (!Release(host)) { reason_="owned_order_cleanup_pending"; return; }
    if (std::find(completed_.begin(), completed_.end(), target_.serial)==completed_.end()) { completed_.push_back(target_.serial); attempted_.push_back(target_.serial); }
    lastProgress_ = now;
    if (completed_.size() == terms_.agreedTargets.size()) { Stop(Complete, host, "agreed_targets_defeated"); return; }
    phase_ = Searching; target_ = Target(); return;
  }
  if ((terms_.kind == ClearGroup && !target_.hostile) ||
      (terms_.kind == Hunt && !target_.harvestable && !target_.legalHunt) ||
      (terms_.kind == Mine && !target_.resourceUsable)) {
    Replan(now, host, "target_no_longer_authorized_or_usable"); return;
  }
  // A fresh legally harvestable target ends the owned hunt attack before the
  // dispatch policy would correctly refuse another attack on that target.
  if (!pending_.empty() && pendingCommand_ == Attack && terms_.kind == Hunt && target_.harvestable) {
    if (!Release(host)) { reason_="owned_order_cleanup_pending";return; }
    phase_=Verifying;
  }
  if (!pending_.empty()) {
    Receipt receipt = host.Poll(pending_);
    if (receipt.status == Receipt::Pending) {
      // Killing is not completion: stop the owned attack before harvesting.
      if (!(pendingCommand_ == Attack && terms_.kind == Hunt && target_.harvestable)) return;
    } else if (receipt.status == Receipt::Rejected || receipt.status == Receipt::Interrupted) {
      Replan(now, host, receipt.reason.empty() ? "action_interrupted" : receipt.reason); return;
    }
    if (!Release(host)) { reason_="owned_order_cleanup_pending"; return; }
    phase_ = Verifying;
    if (pendingCommand_ == Travel && !f.arrived) { Replan(now, host, "arrival_not_verified"); return; }
    if (pendingCommand_ == TakeItem) { reason_="harvest_transfer_verified_recheck_remaining"; return; }
    if (pendingCommand_ == WorkResource) { reason_="resource_transfer_verified_recheck_quantity"; return; }
    if (pendingCommand_ == Attack && !target_.dead && !target_.defeated && !target_.harvestable) {
      Replan(now, host, "attack_ended_without_verified_result"); return;
    }
  }
  Command next = WorkResource;
  if (terms_.kind != Mine) {
    if (terms_.kind == Hunt && target_.harvestable) {
      if (!target_.lootPermitted || !target_.hasRequestedItem) { Replan(now, host, "requested_loot_unavailable_or_not_permitted"); return; }
      next = TakeItem;
    } else next = Attack;
  }
  if (Issue(next, host)) phase_ = Performing;
  else Replan(now, host, reason_);
}
} }
