#include "ActivityCandidatePolicy.h"
#include <cassert>

using namespace Stobe::Activity;

static ClearGroupMemberEvidence Member(unsigned serial) {
  ClearGroupMemberEvidence row;
  row.serial = serial;
  row.visible = row.hostile = row.active = row.finitePosition = row.pathConfirmed = true;
  row.protectedTarget = false;
  return row;
}

int main() {
  // A lower serial with no native path cannot mask the reachable group member.
  std::vector<ClearGroupMemberEvidence> evidence;
  ClearGroupMemberEvidence unreachable = Member(10);
  unreachable.pathConfirmed = false;
  evidence.push_back(unreachable);
  evidence.push_back(Member(20));
  std::vector<unsigned> targets = SelectClearGroupTargets(evidence);
  assert(targets.size() == 1 && targets[0] == 20);

  // Every observation and safety predicate is required for a fixed target.
  evidence.clear(); evidence.push_back(Member(0));
  assert(SelectClearGroupTargets(evidence).empty());
  const unsigned rejectedSerials[] = {30, 31, 32, 33, 34, 35};
  for (unsigned i = 0; i < 6; ++i) {
    ClearGroupMemberEvidence row = Member(rejectedSerials[i]);
    switch (i) {
      case 0: row.visible = false; break;
      case 1: row.hostile = false; break;
      case 2: row.protectedTarget = true; break;
      case 3: row.active = false; break;
      case 4: row.finitePosition = false; break;
      case 5: row.pathConfirmed = false; break;
    }
    evidence.clear(); evidence.push_back(row);
    assert(SelectClearGroupTargets(evidence).empty());
  }

  // Results are canonical and duplicate native observations do not expand scope.
  evidence.clear();
  evidence.push_back(Member(22)); evidence.push_back(Member(21)); evidence.push_back(Member(22));
  targets = SelectClearGroupTargets(evidence);
  assert(targets.size() == 2 && targets[0] == 21 && targets[1] == 22);

  // Never emit an agreement that exceeds the controller's fixed 32-target cap.
  evidence.clear();
  for (unsigned i = 1; i <= 33; ++i) evidence.push_back(Member(i));
  assert(SelectClearGroupTargets(evidence).empty());
  return 0;
}
