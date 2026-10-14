#pragma once

#include <sstream>
#include <string>

// Pure identity/evidence rules shared by the native travel executor and its
// portable regression fixture. Engine mutations remain in NativeTravelLifecycle.
namespace Stobe { namespace NativeTravelReceiptPolicy {

struct Scope {
  unsigned int actor;
  unsigned int speaker;
  std::string agreement;
  std::string request;
  std::string world;
  std::string task;
  Scope() : actor(0), speaker(0) {}
};

enum DuplicateResult {
  DUPLICATE_NEW = 0,
  DUPLICATE_EXACT_ACCEPTED,
  DUPLICATE_EXACT_UNCERTAIN,
  DUPLICATE_CONFLICT
};

inline std::string RequestKey(const std::string &agreement,
                              const std::string &request) {
  // Length prefixes keep arbitrary token boundaries unambiguous.
  std::ostringstream out;
  out << agreement.size() << ":" << agreement << request.size() << ":" << request;
  return out.str();
}

inline DuplicateResult ClassifyDuplicate(bool exists,
                                         const std::string &savedEnvelope,
                                         const std::string &incomingEnvelope,
                                         bool dispatchAccepted) {
  if (!exists) return DUPLICATE_NEW;
  if (savedEnvelope != incomingEnvelope) return DUPLICATE_CONFLICT;
  return dispatchAccepted ? DUPLICATE_EXACT_ACCEPTED : DUPLICATE_EXACT_UNCERTAIN;
}

inline bool MatchesCurrentScope(const Scope &receipt, unsigned int actor,
                                unsigned int speaker,
                                const std::string &agreement,
                                const std::string &request,
                                const std::string &currentWorld) {
  return receipt.actor == actor && receipt.speaker == speaker &&
         receipt.agreement == agreement && receipt.request == request &&
         !currentWorld.empty() && receipt.world == currentWorld;
}

inline bool MatchesRelease(const Scope &receipt, unsigned int actor,
                           unsigned int speaker,
                           const std::string &agreement,
                           const std::string &currentWorld,
                           const std::string &task,
                           bool freshlyObservedNativeAbsence) {
  return freshlyObservedNativeAbsence && receipt.actor == actor &&
         receipt.speaker == speaker && receipt.agreement == agreement &&
         !currentWorld.empty() && receipt.world == currentWorld &&
         !task.empty() && receipt.task == task;
}

inline bool AtAgreedEndpoint(float x, float y, float z,
                             float targetX, float targetY, float targetZ) {
  const double dx = static_cast<double>(x) - targetX;
  const double dy = static_cast<double>(y) - targetY;
  const double dz = static_cast<double>(z) - targetZ;
  const double squared = dx * dx + dy * dy + dz * dz;
  // NaN fails the self-comparison and infinities exceed the finite bound.
  return squared == squared && squared <= 64.0;
}

inline bool RouteArrival(bool follow, float actorX, float actorY, float actorZ,
                         float leaderX, float leaderY, float leaderZ,
                         float targetX, float targetY, float targetZ) {
  if (!AtAgreedEndpoint(actorX, actorY, actorZ, targetX, targetY, targetZ))
    return false;
  return !follow || AtAgreedEndpoint(leaderX, leaderY, leaderZ,
                                     targetX, targetY, targetZ);
}

} } // namespace Stobe::NativeTravelReceiptPolicy
