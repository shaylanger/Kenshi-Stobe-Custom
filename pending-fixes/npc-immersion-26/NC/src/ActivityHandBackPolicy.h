#pragma once
// Pure logic (no Kenshi SDK): the post-completion "hand the result to the requester" step.
// Server switch: envelope flag `handback` (Agreement::handBack). When false nothing moves.
// The goal state machine is untouched: this runs after the goal is complete and its native
// order is released (cleanupComplete), holds the published phase as "handing_back", walks the
// NPC to the requester (owned FOLLOW order), moves exactly the delivered amount of the exact
// resource, then releases the follow. It never invents success: any failure leaves the items
// with the NPC and says so ("kept_by_npc").
#include <string>
namespace Stobe { namespace Activity { namespace HandBack {

enum Stage { Idle, Approach, Releasing, Done };
enum Action { ActNone, ActStartFollow, ActTransfer, ActReleaseFollow };

struct Input {
 bool enabled;            // server asked for hand-back
 bool delivers;           // Hunt/Mine (ClearGroup has nothing to hand over)
 bool goalComplete;       // goal reached Complete
 bool goalEnded;          // complete / cancelled / failed
 bool cleanupComplete;    // native order released
 unsigned delivered;      // goal.delivered
 unsigned inActorInventory; // exact resource currently in the actor's inventory
 bool actorAvailable, requesterAvailable;
 float distance;          // actor-requester (game units)
 bool followStarted;      // an owned follow order exists (set by the host after ActStartFollow succeeded)
 bool followFailed;       // lifecycle reports failed/cancelled before the transfer
 bool followReleased;     // lifecycle reports the owned order fully released
 unsigned long nowMs;
 Input() : enabled(false), delivers(false), goalComplete(false), goalEnded(false), cleanupComplete(false), delivered(0),
  inActorInventory(0), actorAvailable(true), requesterAvailable(true), distance(1e9f), followStarted(false),
  followFailed(false), followReleased(false), nowMs(0) {}
};
struct Output {
 Action action; unsigned amount;
 Output() : action(ActNone), amount(0) {}
};

class Machine {
public:
 static float NearDistance() { return 12.0f; }
 static unsigned long TimeoutMs() { return 120000; }
 static unsigned long ReleaseTimeoutMs() { return 15000; }
 static unsigned long RetryMs() { return 2000; }
 static unsigned MaxTransferAttempts() { return 3; }
 Machine() : stage_(Idle), startedMs_(0), phaseMs_(0), lastTransferMs_(0), attempts_(0), amount_(0), startAsked_(false),
  needRelease_(false), status_("pending") {}

 Output Step(const Input& in) {
  Output out;
  if (stage_ == Done) return out;
  if (stage_ == Releasing) { StepRelease(in, out); return out; }
  if (stage_ == Idle) {
   if (!in.goalEnded || !in.cleanupComplete) return out; // goal still running: nothing to hold yet
   if (!in.enabled) { Finish("not_applicable", "handback_not_requested", 0, in); return Wait(in, out); }
   if (!in.delivers || in.delivered == 0) { Finish("not_applicable", "nothing_to_hand_over", 0, in); return Wait(in, out); }
   if (!in.goalComplete) { Finish("kept_by_npc", "activity_not_completed", 0, in); return Wait(in, out); }
   amount_ = in.delivered < in.inActorInventory ? in.delivered : in.inActorInventory;
   if (amount_ == 0) { Finish("kept_by_npc", "reward_not_in_actor_inventory", 0, in); return Wait(in, out); }
   stage_ = Approach; startedMs_ = in.nowMs; phaseMs_ = in.nowMs;
  }
  // Approach
  if (!in.actorAvailable || !in.requesterAvailable) { Finish("kept_by_npc", "actor_or_requester_unavailable", 0, in); return Wait(in, out); }
  if (in.nowMs - startedMs_ > TimeoutMs()) { Finish("kept_by_npc", "handback_timeout", 0, in); return Wait(in, out); }
  const unsigned stock = in.inActorInventory < amount_ ? in.inActorInventory : amount_;
  if (stock == 0) { Finish("kept_by_npc", "reward_not_in_actor_inventory", 0, in); return Wait(in, out); }
  if (in.distance <= NearDistance()) {
   if (attempts_ > 0 && in.nowMs - lastTransferMs_ < RetryMs()) return out;
   ++attempts_; lastTransferMs_ = in.nowMs; out.action = ActTransfer; out.amount = stock; return out;
  }
  if (!startAsked_) { startAsked_ = true; out.action = ActStartFollow; return out; }
  if (in.followFailed) { Finish("kept_by_npc", "follow_failed", 0, in); return Wait(in, out); }
  return out; // walking
 }
 // Host feedback.
 void FollowStartResult(bool ok, const std::string& why, const Input& in) {
  if (ok) return;
  Finish("kept_by_npc", "follow_rejected:" + why, 0, in);
  startAsked_ = true; needRelease_ = true; // the host decides via followStarted/followReleased
 }
 void TransferResult(bool ok, unsigned moved, const std::string& why, const Input& in) {
  if (ok && moved > 0) { Finish("delivered", "exact_resource_handed_to_requester", moved, in); return; }
  if (attempts_ >= MaxTransferAttempts()) Finish("kept_by_npc", "transfer_failed:" + why, 0, in);
 }
 Stage CurrentStage() const { return stage_; }
 bool Finished() const { return stage_ == Done; }
 bool Returning() const { return stage_ == Approach && startAsked_; }
 // Hold the published phase until the whole step is finished (including the follow release).
 bool HoldsTerminal() const { return stage_ != Done && stage_ != Idle; }
 bool Active() const { return stage_ == Approach || stage_ == Releasing; }
 const std::string& Status() const { return status_; }
 const std::string& Reason() const { return reason_; }
 unsigned Amount() const { return amount_; }

private:
 Stage stage_; unsigned long startedMs_, phaseMs_, lastTransferMs_; unsigned attempts_, amount_;
 bool startAsked_, needRelease_; std::string status_, reason_;
 void Finish(const char* status, const std::string& reason, unsigned moved, const Input& in) {
  status_ = status; reason_ = reason; if (moved) amount_ = moved; else if (status_ != "delivered") amount_ = 0;
  if (stage_ == Approach && (startAsked_ || in.followStarted)) { stage_ = Releasing; phaseMs_ = in.nowMs; needRelease_ = true; }
  else stage_ = Done;
 }
 Output& Wait(const Input&, Output& out) { return out; }
 void StepRelease(const Input& in, Output& out) {
  if (in.followReleased || !in.followStarted || in.nowMs - phaseMs_ > ReleaseTimeoutMs()) { stage_ = Done; return; }
  out.action = ActReleaseFollow;
 }
};
} } }
