#pragma once

#include <climits>
#include <cstdlib>
#include <string>
#include <vector>

namespace Stobe {
namespace Harness {

struct TestInboxTargetRef {
  bool isReference;
  bool valid;
  unsigned int serial;
  unsigned int index;
  TestInboxTargetRef()
      : isReference(false), valid(false), serial(0), index(0) {}
};

inline bool ParseTestInboxTargetNumber(const std::string &text,
                                       unsigned int &value) {
  if (text.empty())
    return false;
  unsigned int parsed = 0;
  for (size_t i = 0; i < text.size(); ++i) {
    if (text[i] < '0' || text[i] > '9')
      return false;
    const unsigned int digit = static_cast<unsigned int>(text[i] - '0');
    if (parsed > (UINT_MAX - digit) / 10)
      return false;
    parsed = parsed * 10 + digit;
  }
  value = parsed;
  return true;
}

// Stobe chat test commands accept the same stable handle printed by KAH chars:
// #serial/index. A bare #serial is intentionally unsupported because serials
// can be shared by distinct live characters.
inline TestInboxTargetRef ParseTestInboxTargetRef(const std::string &text) {
  TestInboxTargetRef ref;
  if (text.empty() || text[0] != '#')
    return ref;
  ref.isReference = true;
  const std::string body = text.substr(1);
  const size_t slash = body.find('/');
  if (slash == std::string::npos || body.find('/', slash + 1) != std::string::npos)
    return ref;
  ref.valid = ParseTestInboxTargetNumber(body.substr(0, slash), ref.serial) &&
              ParseTestInboxTargetNumber(body.substr(slash + 1), ref.index);
  return ref;
}

inline bool MatchesTestInboxTargetRef(unsigned int serial, unsigned int index,
                                      const TestInboxTargetRef &ref) {
  return ref.isReference && ref.valid && serial == ref.serial &&
         index == ref.index;
}

template <typename Target> struct TestInboxTargetCandidate {
  Target target;
  std::string normalizedName;
  unsigned int serial;
  unsigned int index;
  float distance;
};

template <typename Target>
inline const TestInboxTargetCandidate<Target> *ClosestNamedTarget(
    const std::vector<TestInboxTargetCandidate<Target>> &candidates,
    const std::string &normalizedName) {
  const TestInboxTargetCandidate<Target> *best = nullptr;
  for (size_t i = 0; i < candidates.size(); ++i) {
    const TestInboxTargetCandidate<Target> &candidate = candidates[i];
    if (candidate.normalizedName == normalizedName &&
        (!best || candidate.distance < best->distance))
      best = &candidate;
  }
  return best;
}

// Preserve the pre-existing name resolution choice: nearest exact name from
// the update list wins. Nearby-object results are a fallback only when that
// list has no exact match.
template <typename Target>
inline const TestInboxTargetCandidate<Target> *ResolveNamedTarget(
    const std::vector<TestInboxTargetCandidate<Target>> &updateList,
    const std::vector<TestInboxTargetCandidate<Target>> &nearbyObjects,
    const std::string &normalizedName) {
  const TestInboxTargetCandidate<Target> *match =
      ClosestNamedTarget(updateList, normalizedName);
  return match ? match : ClosestNamedTarget(nearbyObjects, normalizedName);
}

template <typename Target>
inline const TestInboxTargetCandidate<Target> *ResolveHandleTarget(
    const std::vector<TestInboxTargetCandidate<Target>> &updateList,
    const std::vector<TestInboxTargetCandidate<Target>> &nearbyObjects,
    const TestInboxTargetRef &ref) {
  for (size_t i = 0; i < updateList.size(); ++i)
    if (MatchesTestInboxTargetRef(updateList[i].serial, updateList[i].index, ref))
      return &updateList[i];
  for (size_t i = 0; i < nearbyObjects.size(); ++i)
    if (MatchesTestInboxTargetRef(nearbyObjects[i].serial,
                                  nearbyObjects[i].index, ref))
      return &nearbyObjects[i];
  return nullptr;
}

} // namespace Harness
} // namespace Stobe
