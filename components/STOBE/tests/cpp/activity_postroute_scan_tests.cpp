// imm26 fix26a2 (row 26-a, 2026-10-16): the Hunt candidate scan right after the route arrival.
// Field failure (run 26-a-op15, stobe.log:270): route arrival at 17:16:25.4, ONE scan at 17:16:26.67 found no observable agreed animal,
// ACTIVITY_END_DIAG where=goal_stop reason=no_observed_suitable_reachable_target attempted=0 lastReason=arrived_rescanning_activity_purpose.
// The same scan code selected the goat in run 26-a-op14g, so the scan result right after the stop is transient (sight / navmesh lock / streaming).
//  1. empty scans right after the route arrival are retried: the animal observed on a later tick is selected (Travelling), no Failed
//  2. a scan that never sees the animal still fails, bounded (16 tolerated empty scans, the 17th fails) with the standard reason
//  3. a candidate that is present but not suitable (legalHunt=false) is retried the same way, then fails the same way
//  4. control (26-c): after a target was selected and then lost, the replan search is NOT given the grace: one empty scan fails at once
// Build (WSL): g++ -std=gnu++11 -include cmath '-D_finite(x)=std::isfinite(x)' -I<src> activity_postroute_scan_tests.cpp <src>/ActivityGoals.cpp
#include "ActivityGoals.h"
#include <cstdio>

using namespace Stobe::Activity;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { ++failures; std::printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

class FakeHost : public Host {
public:
  Facts facts; Target animal; Receipt routeReceipt, pollReceipt;
  unsigned scans, appearAtScan; bool targetVisible; bool legal;
  FakeHost() : scans(0), appearAtScan(0), targetVisible(true), legal(true) {
    facts.worldId = "world-1"; facts.actorLoaded = facts.actorAlive = facts.actorConscious = true;
    facts.revoked = facts.conflictingOrder = false; facts.inventorySpace = true; facts.arrived = true;
    animal.serial = 77; animal.sourceId = "goat"; animal.candidateId = "c77";
    animal.visible = animal.reachable = true; animal.legalHunt = true;
    routeReceipt.status = Receipt::Pending; pollReceipt.status = Receipt::Pending;
  }
  bool Authorized(const Agreement&, Clock, std::string&) { return true; }
  Facts Observe(const Agreement&, unsigned target) {
    Facts f = facts; if (target) { f.target = animal; f.target.visible = targetVisible; f.target.legalHunt = legal; } return f;
  }
  std::vector<Target> Candidates(const Agreement&) {
    ++scans;
    if (appearAtScan && scans >= appearAtScan) { Target t = animal; t.legalHunt = legal; return std::vector<Target>(1, t); }
    return std::vector<Target>();
  }
  bool Dispatch(const Agreement&, const Request&, std::string&) { return true; }
  bool DispatchRoute(const Agreement&, const Request&, std::string&) { return true; }
  Receipt Poll(const std::string&) { return pollReceipt; }
  Receipt PollRoute(const std::string&) { return routeReceipt; }
  bool CancelOwned(const std::string&) { return true; }
  bool CancelRoute(const std::string&) { return true; }
};

static Agreement HuntTerms() {
  Agreement a; a.id = "agreement-1"; a.worldId = "world-1"; a.sourceId = "goat"; a.resourceId = "animal_skin";
  a.actor = 10; a.requester = 20; a.kind = Hunt; a.quantity = 1; a.maximumTargets = 3; a.maximumReplans = 3;
  a.expiresAt = 1000000; a.noProgressTimeout = 10000;
  a.discoveryCandidateId = "disc-1"; a.discoveryTargetSerial = 77;
  a.routeCandidateId = "route-1"; a.routeWorldId = "world-1"; a.routeActor = 10; a.routeKind = "landmark";
  a.routeLabel = "outside Outlaw Watch to the west"; a.routeX = 1.0f; a.routeY = 2.0f; a.routeZ = 3.0f;
  return a;
}

// Start -> route dispatched -> route Succeeded -> Searching (arrival tick, no scan yet). Returns the clock of the last tick.
static Clock ArriveAtRouteGoal(Goal& g, FakeHost& h) {
  CHECK(g.Start(HuntTerms(), 0, h));
  Clock t = 1; g.Tick(t, h); CHECK(g.State() == Travelling);
  h.routeReceipt.status = Receipt::Succeeded; t += 1; g.Tick(t, h);
  CHECK(g.State() == Searching); CHECK(g.Reason() == "arrived_rescanning_activity_purpose");
  return t;
}

int main() {
  // 1. animal observable only from the 6th scan on: the Hunt waits, then selects it.
  {
    FakeHost h; Goal g; h.appearAtScan = 6;
    Clock t = ArriveAtRouteGoal(g, h);
    for (int i = 1; i <= 5; ++i) { t += 1; g.Tick(t, h); CHECK(g.State() == Searching); CHECK(h.scans == (unsigned)i); }
    t += 1; g.Tick(t, h);
    CHECK(h.scans == 6);
    CHECK(g.State() == Travelling);              // target selected, Travel to the animal dispatched
    GoalStatusSnapshot s; g.Snapshot(s); CHECK(s.hasTarget && s.currentTarget == 77);
  }
  // 2. never observed: bounded wait, then the unchanged terminal reason.
  {
    FakeHost h; Goal g; Clock t = ArriveAtRouteGoal(g, h);
    for (int i = 1; i <= 16; ++i) { t += 1; g.Tick(t, h); CHECK(g.State() == Searching); }
    CHECK(h.scans == 16);
    t += 1; g.Tick(t, h);
    CHECK(g.State() == Failed); CHECK(g.Reason() == "no_observed_suitable_reachable_target"); CHECK(h.scans == 17);
  }
  // 3. present but not suitable (legalHunt=false): same retry, same end.
  {
    FakeHost h; Goal g; h.appearAtScan = 1; h.legal = false; Clock t = ArriveAtRouteGoal(g, h);
    for (int i = 1; i <= 16; ++i) { t += 1; g.Tick(t, h); CHECK(g.State() == Searching); }
    t += 1; g.Tick(t, h);
    CHECK(g.State() == Failed); CHECK(g.Reason() == "no_observed_suitable_reachable_target");
  }
  // 4. control (26-c): target selected, then lost -> replan search with no candidate fails on the FIRST empty scan (no grace).
  {
    FakeHost h; Goal g; h.appearAtScan = 1; Clock t = ArriveAtRouteGoal(g, h);
    t += 1; g.Tick(t, h); CHECK(g.State() == Travelling);
    h.appearAtScan = 0; h.targetVisible = false;
    t += 1; g.Tick(t, h);                       // target_unavailable_or_identity_changed -> Replan -> Searching
    CHECK(g.State() == Searching);
    const unsigned before = h.scans;
    t += 1; g.Tick(t, h);
    CHECK(h.scans == before + 1);
    CHECK(g.State() == Failed);
    CHECK(g.Reason().find("no_observed_suitable_reachable_target") != std::string::npos);
  }
  std::printf("failures=%d\n", failures);
  return failures ? 1 : 0;
}
