#include "ActivityGoals.h"
#include <cassert>

using namespace Stobe::Activity;

class FakeHost : public Host {
public:
  Facts facts;
  Target mine;
  Receipt receipt;
  Request requests[4];
  unsigned requestCount, candidateSearchCount;
  bool rejectWork;
  FakeHost() : requestCount(0), candidateSearchCount(0), rejectWork(false) {
    mine.serial = 77; mine.sourceId = "iron_mine"; mine.candidateId = "candidate-77";
    mine.visible = mine.reachable = mine.resourceUsable = true;
    facts.worldId = "world-1"; facts.actorLoaded = facts.actorAlive = facts.actorConscious = true;
    facts.revoked = facts.conflictingOrder = false; facts.inventorySpace = true;
  }
  bool Authorized(const Agreement&, Clock, std::string&) { return true; }
  Facts Observe(const Agreement&, unsigned target) {
    Facts current = facts;
    if (target) current.target = mine;
    return current;
  }
  std::vector<Target> Candidates(const Agreement&) {
    // Model the search result explicitly. Dispatch counts are unrelated to
    // what the next native observation can see (Travel/WorkResource are not
    // candidate-search events).
    ++candidateSearchCount;
    return candidateSearchCount == 1 ? std::vector<Target>(1, mine) : std::vector<Target>();
  }
  bool Dispatch(const Agreement&, const Request& r, std::string& reason) {
    requests[requestCount++] = r;
    if (rejectWork && r.command == WorkResource) { reason = "native_resource_rejected"; return false; }
    reason.clear(); return true;
  }
  Receipt Poll(const std::string&) { Receipt done; done.status = Receipt::Succeeded; return done; }
  bool CancelOwned(const std::string&) { return true; }
};

static Agreement MineTerms() {
  Agreement a; a.id="agreement-1"; a.worldId="world-1"; a.sourceId="iron_mine";
  a.resourceId="iron_ore"; a.actor=10; a.requester=20; a.kind=Mine;
  a.quantity=1; a.maximumTargets=2; a.expiresAt=100; a.noProgressTimeout=50; return a;
}

int main() {
  {
    FakeHost host; Goal goal; Agreement a=MineTerms();
    assert(goal.Start(a, 0, host));
    goal.Tick(1, host);
    assert(host.requestCount == 1 && host.requests[0].command == Travel);
    host.facts.arrived = true;
    goal.Tick(2, host);
    assert(host.requestCount == 2 && host.requests[1].command == WorkResource);
    assert(host.requests[1].target == 77 && host.requests[1].resourceId == "iron_ore");
  }
  {
    FakeHost host; Goal goal; Agreement a=MineTerms();
    assert(goal.Start(a, 0, host));
    goal.Tick(1, host);
    host.facts.arrived = true;
    goal.Tick(2, host);
    host.rejectWork = true;
    goal.Tick(3, host);
    goal.Tick(4, host);
    assert(goal.State() == Searching);
    assert(goal.Reason() == "native_resource_rejected");
    goal.Tick(5, host);
    assert(goal.State() == Failed);
    assert(goal.Reason() == "native_resource_rejected; no_observed_suitable_reachable_target");
    assert(host.candidateSearchCount == 2); // initial source, then explicit empty replan
    assert(host.requestCount == 3); // Travel, WorkResource, retry WorkResource
  }
  return 0;
}
