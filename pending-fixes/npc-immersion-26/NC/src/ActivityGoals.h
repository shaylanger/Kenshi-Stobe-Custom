#pragma once
#include <string>
#include <vector>

namespace Stobe { namespace Activity {
typedef unsigned long long Clock;
enum Kind { Hunt, Mine, ClearGroup };
enum Phase { Dormant, Routing, Searching, Travelling, Performing, Verifying, Complete, Cancelled, Failed };
enum Command { Travel, RouteTravel, Attack, WorkResource, TakeItem };

// Created by the trusted agreement layer, never directly from model output.
// Movement agreements cannot be substituted for this explicit activity grant.
struct Agreement {
  std::string id, worldId, sourceId, resourceId;
  // Authenticated protocol-v2 scope evidence retained for exact native travel dispatch.
  std::string scopeDigest, dispatchEnvelope;
  // Exact native source discovered before proposal/acceptance. This reference
  // is independent from the route candidate and remains bound through dispatch.
  std::string discoveryCandidateId;
  unsigned int discoveryTargetSerial;
  // Independent native route candidate. Never an activity-source candidate.
  std::string routeCandidateId, routeWorldId, routeKind, routeLabel;
  float routeX, routeY, routeZ;
  unsigned int actor, requester, routeActor;
  // Opaque native camp-zone token plus a canonical digest of the exact site
  // facts and fixed targets. Both are included in the server's signed scope.
  unsigned int scopeVersion;
  bool campQualified;
  std::string campZoneCandidateId, campZoneDigest;
  // Server switch (top-level envelope flag `handback`, default false): after completion the NPC walks the result to the requester.
  bool handBack;
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

// Copy-only state owned by Goal. This snapshot intentionally contains no
// native object pointers and does not expose or mutate host/action state.
struct GoalStatusSnapshot {
  Phase phase;
  Command pendingCommand;
  std::string reason, currentCandidateId, pendingRequestId;
  std::string nativeReceiptStatus, nativeReceiptReason, nativeTaskName, nativeActionName;
  std::string mineItem;
  unsigned int currentTarget, delivered;
  unsigned int nativeTarget, nativeTaskSubject, nativeActionSubject;
  unsigned int mineActor, mineBuilding, mineOutputBaseline, mineOutputExpected, mineOutputCount, mineCreditedOutput;
  int nativeTaskKey, nativeActionKey;
  bool hasTarget, hasPendingRequest, terminal;
  bool targetHostilityKnown, currentTargetHostile, nativeEvidenceAvailable;
  bool operationTracked, ownedTaskMatches, currentActionMatchesTarget, targetInFixedSetKnown, targetInFixedSet;
  bool mineAttributionAvailable, mineLeaseIdentityMatches, mineOutputCountConsistent, mineContributionObserved;
  std::vector<unsigned int> completedTargets, confirmedDeadTargets;
  GoalStatusSnapshot() : phase(Dormant), pendingCommand(Travel), currentTarget(0),
      delivered(0), nativeTarget(0), nativeTaskSubject(0), nativeActionSubject(0),
      mineActor(0), mineBuilding(0), mineOutputBaseline(0), mineOutputExpected(0), mineOutputCount(0),
      mineCreditedOutput(0), nativeTaskKey(-1), nativeActionKey(-1), hasTarget(false),
      hasPendingRequest(false), terminal(false), targetHostilityKnown(false),
      currentTargetHostile(false), nativeEvidenceAvailable(false), operationTracked(false),
      ownedTaskMatches(false), currentActionMatchesTarget(false), targetInFixedSetKnown(false), targetInFixedSet(false),
      mineAttributionAvailable(false), mineLeaseIdentityMatches(false), mineOutputCountConsistent(false), mineContributionObserved(false) {}
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
  virtual bool DispatchRoute(const Agreement&, const Request&, std::string& reason) { reason="route_dispatch_unavailable"; return false; }
  virtual Receipt Poll(const std::string& requestId) = 0;
  virtual Receipt PollRoute(const std::string&) { Receipt r; r.status=Receipt::Rejected; r.reason="route_status_unavailable"; return r; }
  // Remove only the order/job identified by this request's owned fingerprint.
  // False means cleanup is unconfirmed; do not dispatch a replacement then.
  virtual bool CancelOwned(const std::string& requestId) = 0;
  virtual bool CancelRoute(const std::string&) { return false; }
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
  void Snapshot(GoalStatusSnapshot&) const;
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
  bool IssueRoute(Host&);
  bool Release(Host&);
  void Stop(Phase, Host&, const std::string&);
  void Replan(Clock, Host&, const std::string&);
};
} }
