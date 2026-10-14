#pragma once
#include <string>
#include <vector>

namespace Stobe { namespace Activity {
typedef unsigned long long Clock;
enum Kind { Hunt, Mine, ClearGroup };
enum Phase { Dormant, Searching, Travelling, Performing, Verifying, Complete, Cancelled, Failed };
enum Command { Travel, Attack, WorkResource, TakeItem };

// Created by the trusted agreement layer, never directly from model output.
// Movement agreements cannot be substituted for this explicit activity grant.
struct Agreement {
  std::string id, worldId, sourceId, resourceId;
  unsigned int actor, requester;
  Kind kind;
  unsigned int quantity, maximumTargets, maximumReplans;
  Clock expiresAt, noProgressTimeout;
  std::vector<unsigned int> agreedTargets;
  Agreement();
};
struct Target {
  unsigned int serial;
  std::string sourceId, candidateId;
  bool visible, reachable, hostile, legalHunt, resourceUsable, lootPermitted;
  bool dead, defeated, harvestable, hasRequestedItem;
  Target();
};
struct Facts {
  std::string worldId;
  bool actorLoaded, actorAlive, actorConscious, revoked, conflictingOrder;
  bool inventorySpace, arrived, pathFailed;
  // Monotonic, goal-owned delivered quantity: NOT an actor's total inventory.
  unsigned int delivered;
  Target target;
  Facts();
};
struct Request {
  std::string id, agreementId, candidateId, resourceId;
  unsigned int actor, target, quantity;
  Command command;
};
struct Receipt {
  enum Status { Pending, Succeeded, Rejected, Interrupted } status;
  std::string reason;
  Receipt();
};

// Implemented only by deliberate native integration. Every method runs on the
// game thread. Existing squad-only executor gates must remain unchanged.
class Host {
public:
  virtual ~Host() {}
  virtual bool Authorized(const Agreement&, Clock now, std::string& reason) = 0;
  virtual Facts Observe(const Agreement&, unsigned int target) = 0;
  virtual std::vector<Target> Candidates(const Agreement&) = 0;
  // Recheck source identity, ownership/crime, current hostility, registry/path,
  // actor authority and inventory immediately before every actual dispatch.
  virtual bool Dispatch(const Agreement&, const Request&, std::string& reason) = 0;
  virtual Receipt Poll(const std::string& requestId) = 0;
  // Remove only the order/job identified by this request's owned fingerprint.
  // False means cleanup is unconfirmed; do not dispatch a replacement then.
  virtual bool CancelOwned(const std::string& requestId) = 0;
};

class Goal {
public:
  Goal();
  bool Start(const Agreement&, Clock now, Host&);
  void Tick(Clock now, Host&);
  void Cancel(Host&, const std::string& reason);
  Phase State() const { return phase_; }
  bool CleanupComplete() const { return pending_.empty(); }
  const std::string& Reason() const { return reason_; }
  const Agreement& Terms() const { return terms_; }
private:
  Agreement terms_;
  Phase phase_, stopPhase_;
  bool stopPending_, replanPending_;
  std::string stopReason_, replanReason_;
  std::string reason_, pending_;
  Target target_;
  Clock lastProgress_, lastNow_;
  unsigned int delivered_, replans_, sequence_;
  std::vector<unsigned int> completed_, attempted_, confirmedDead_;
  Command pendingCommand_;
  bool Suitable(const Target&) const;
  bool Issue(Command, Host&);
  bool Release(Host&);
  void Stop(Phase, Host&, const std::string&);
  void Replan(Clock, Host&, const std::string&);
};
} }
