// imm26 huntA1 (Shay 2026-10-16): Hunt no-progress timeout behaviour of Stobe::Activity::Goal.
//  - a long walk to the agreed route (minutes) is never timed out, arrival resets the timer
//  - an attack that lowers the hunted animal's health resets the timer; no damage -> fails with activity_no_verified_progress
//  - health drops that are not our attack (travelling, other target, unreadable health) never reset it
// Build (WSL): g++ -std=gnu++11 -include cmath '-D_finite(x)=std::isfinite(x)' -I../../src activity_hunt_progress_tests.cpp ../../src/ActivityGoals.cpp
#include "ActivityGoals.h"
#include <cstdio>
#include <cstdlib>

using namespace Stobe::Activity;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { ++failures; std::printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

static const Clock kTimeout = 10000;

class FakeHost : public Host {
public:
  Facts facts; Target animal; Receipt routeReceipt, pollReceipt;
  unsigned candidateSearches; std::vector<Command> commands;
  FakeHost() : candidateSearches(0) {
    facts.worldId = "world-1"; facts.actorLoaded = facts.actorAlive = facts.actorConscious = true;
    facts.revoked = facts.conflictingOrder = false; facts.inventorySpace = true; facts.arrived = true;
    animal.serial = 77; animal.sourceId = "bone_wolf"; animal.candidateId = "c77";
    animal.visible = animal.reachable = animal.legalHunt = true;
    animal.healthValid = true; animal.health = 400.0f;
    routeReceipt.status = Receipt::Pending; pollReceipt.status = Receipt::Pending;
  }
  bool Authorized(const Agreement&, Clock, std::string&) { return true; }
  Facts Observe(const Agreement&, unsigned target) { Facts f = facts; if (target) f.target = animal; return f; }
  std::vector<Target> Candidates(const Agreement&) { ++candidateSearches; return std::vector<Target>(1, animal); }
  bool Dispatch(const Agreement&, const Request& r, std::string&) { commands.push_back(r.command); return true; }
  bool DispatchRoute(const Agreement&, const Request& r, std::string&) { commands.push_back(r.command); return true; }
  Receipt Poll(const std::string&) { return pollReceipt; }
  Receipt PollRoute(const std::string&) { return routeReceipt; }
  bool CancelOwned(const std::string&) { return true; }
  bool CancelRoute(const std::string&) { return true; }
};

static Agreement HuntTerms() {
  Agreement a; a.id = "agreement-1"; a.worldId = "world-1"; a.sourceId = "bone_wolf"; a.resourceId = "raw_meat";
  a.actor = 10; a.requester = 20; a.kind = Hunt; a.quantity = 1; a.maximumTargets = 3; a.maximumReplans = 3;
  a.expiresAt = 1000000; a.noProgressTimeout = kTimeout;
  a.discoveryCandidateId = "disc-1"; a.discoveryTargetSerial = 77;
  a.routeCandidateId = "route-1"; a.routeWorldId = "world-1"; a.routeActor = 10; a.routeKind = "known_place";
  a.routeLabel = "hunting ground"; a.routeX = 1.0f; a.routeY = 2.0f; a.routeZ = 3.0f;
  return a;
}

// Drive a goal to the Performing phase with an owned Attack pending; returns the clock of the last tick.
static Clock ReachAttack(Goal& g, FakeHost& h, Clock t0) {
  CHECK(g.Start(HuntTerms(), t0, h));
  Clock t = t0 + 1; g.Tick(t, h);                                  // Routing -> route dispatched
  CHECK(g.State() == Travelling);
  h.routeReceipt.status = Receipt::Succeeded; t += 1; g.Tick(t, h); // route arrival -> Searching, progress reset
  CHECK(g.State() == Searching);
  t += 1; g.Tick(t, h);                                             // Searching -> Travel to the animal
  CHECK(g.State() == Travelling);
  h.pollReceipt.status = Receipt::Succeeded; t += 1; g.Tick(t, h);  // arrived -> Verifying
  h.pollReceipt.status = Receipt::Pending;   t += 1; g.Tick(t, h);  // Attack issued
  CHECK(g.State() == Performing);
  CHECK(!h.commands.empty() && h.commands.back() == Attack);
  return t;
}

int main() {
  // 1. A very long walk to the agreed area is not a "no progress" failure; arrival gives a full timer.
  {
    FakeHost h; Goal g; CHECK(g.Start(HuntTerms(), 0, h));
    g.Tick(1, h); CHECK(g.State() == Travelling);
    for (Clock t = 500; t <= 5 * kTimeout; t += 500) { g.Tick(t, h); CHECK(g.State() == Travelling); }
    h.routeReceipt.status = Receipt::Succeeded; g.Tick(5 * kTimeout + 1, h);
    CHECK(g.State() == Searching);
    g.Tick(5 * kTimeout + 2, h);                              // target found, travel to it
    CHECK(g.State() == Travelling);
    g.Tick(5 * kTimeout + 2 + kTimeout - 100, h);             // still inside the timer that started at arrival
    CHECK(g.State() == Travelling);
  }
  // 2. Control: attack that never lands = still fails after the (new, longer) timeout with the standard reason.
  {
    FakeHost h; Goal g; Clock t = ReachAttack(g, h, 100);
    g.Tick(t + kTimeout - 200, h); CHECK(g.State() == Performing);
    g.Tick(t + kTimeout + 50, h);
    CHECK(g.State() == Failed);
    CHECK(g.Reason() == "activity_no_verified_progress");
  }
  // 3. Landing hits resets the timer: health drops every ~half timeout, hunt survives far beyond one timeout.
  {
    FakeHost h; Goal g; Clock t = ReachAttack(g, h, 100);
    g.Tick(t + 1, h);                                         // baseline observation, full health
    Clock now = t + 1;
    for (int i = 0; i < 6; ++i) {
      now += kTimeout / 2; h.animal.health -= 20.0f; g.Tick(now, h);
      CHECK(g.State() == Performing);
    }
    CHECK(now - t > 2 * kTimeout);                            // would have failed twice without damage resets
    // damage stops: the timeout counts from the LAST hit
    now += kTimeout - 10; g.Tick(now, h); CHECK(g.State() == Performing);
    now += 20; g.Tick(now, h);
    CHECK(g.State() == Failed); CHECK(g.Reason() == "activity_no_verified_progress");
  }
  // 4. Health that does not drop (unchanged or healing) never resets.
  {
    FakeHost h; Goal g; Clock t = ReachAttack(g, h, 100);
    g.Tick(t + 1, h);
    h.animal.health += 50.0f; g.Tick(t + kTimeout / 2, h);    // healing
    h.animal.health -= 0.2f;  g.Tick(t + kTimeout - 100, h);  // below the 0.5 noise floor
    g.Tick(t + kTimeout + 50, h);
    CHECK(g.State() == Failed);
  }
  // 5. Unreadable health (healthValid=false) fails closed: no reset.
  {
    FakeHost h; Goal g; Clock t = ReachAttack(g, h, 100);
    g.Tick(t + 1, h);
    h.animal.healthValid = false; h.animal.health = 1.0f;
    g.Tick(t + kTimeout - 100, h);
    g.Tick(t + kTimeout + 50, h);
    CHECK(g.State() == Failed);
  }
  // 6. A health drop while NOT attacking (walking to the animal) does not count; the baseline just follows it.
  {
    FakeHost h; Goal g; CHECK(g.Start(HuntTerms(), 0, h));
    g.Tick(1, h); h.routeReceipt.status = Receipt::Succeeded; g.Tick(2, h); g.Tick(3, h);   // Travelling toward the animal
    CHECK(g.State() == Travelling);
    h.animal.health = 300.0f; g.Tick(kTimeout / 2, h);
    h.animal.health = 200.0f; g.Tick(kTimeout - 100, h);
    h.animal.health = 100.0f; g.Tick(2 + kTimeout + 50, h);   // timer started at route arrival (t=2)
    CHECK(g.State() == Failed); CHECK(g.Reason() == "activity_no_verified_progress");
  }
  if (failures) { std::printf("RESULT activity_hunt_progress FAIL %d\n", failures); return 1; }
  std::printf("RESULT activity_hunt_progress PASS\n");
  return 0;
}
