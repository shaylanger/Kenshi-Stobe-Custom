#pragma once

#include <algorithm>
#include <cstddef>
#include <vector>

namespace Stobe { namespace Activity {
struct ClearGroupMemberEvidence {
  unsigned serial;
  bool visible, hostile, protectedTarget, active, finitePosition, pathConfirmed;
  ClearGroupMemberEvidence()
      : serial(0), visible(false), hostile(false), protectedTarget(true), active(false),
        finitePosition(false), pathConfirmed(false) {}
};

// A fixed ClearGroup scope contains only members that can be acted on now.
// In particular, an unreachable low-serial member must not hide reachable
// members by becoming the group's representative.
inline std::vector<unsigned> SelectClearGroupTargets(
    const std::vector<ClearGroupMemberEvidence>& evidence) {
  std::vector<unsigned> targets;
  for (std::size_t i = 0; i < evidence.size(); ++i) {
    const ClearGroupMemberEvidence& member = evidence[i];
    if (!member.serial || !member.visible || !member.hostile || member.protectedTarget ||
        !member.active || !member.finitePosition || !member.pathConfirmed) continue;
    targets.push_back(member.serial);
  }
  std::sort(targets.begin(), targets.end());
  targets.erase(std::unique(targets.begin(), targets.end()), targets.end());
  if (targets.empty() || targets.size() > 32) targets.clear();
  return targets;
}
} }
