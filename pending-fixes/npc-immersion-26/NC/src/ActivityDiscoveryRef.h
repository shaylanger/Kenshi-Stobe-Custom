#pragma once
#include <string>

namespace Stobe { namespace Activity {
typedef unsigned long long DiscoveryClock;
static const DiscoveryClock kDiscoveryReferenceMaxAge = 1800;

inline bool ValidDiscoveryReference(const std::string& candidateId, unsigned int targetSerial) {
  return !candidateId.empty() && candidateId.size() <= 96 && targetSerial != 0;
}

inline bool ValidDiscoveryReferenceShape(unsigned int fieldCount,
                                        bool candidateIdPresent,
                                        bool targetSerialPresent) {
  return fieldCount == 2 && candidateIdPresent && targetSerialPresent;
}

inline bool FreshDiscoveryObservation(DiscoveryClock now, DiscoveryClock observedAt) {
  return now >= observedAt && now - observedAt < kDiscoveryReferenceMaxAge;
}

inline bool ExactDiscoveryBinding(const std::string& expectedCandidate,
                                  unsigned int expectedSerial,
                                  const std::string& observedCandidate,
                                  unsigned int observedSerial) {
  return ValidDiscoveryReference(expectedCandidate, expectedSerial) &&
         expectedCandidate == observedCandidate && expectedSerial == observedSerial;
}

// The caller supplies registry and pointer-identity evidence; this pure gate
// keeps missing, replayed, stale, or cross-actor references closed by default.
inline bool CanBindDiscoveryReference(const std::string& expectedCandidate,
                                     unsigned int expectedSerial,
                                     const std::string& observedCandidate,
                                     unsigned int observedSerial,
                                     bool candidateAvailable,
                                     bool candidateUnclaimed,
                                     bool sameActorAndRequester,
                                     DiscoveryClock now,
                                     DiscoveryClock observedAt) {
  return candidateAvailable && candidateUnclaimed && sameActorAndRequester &&
         ExactDiscoveryBinding(expectedCandidate, expectedSerial,
                               observedCandidate, observedSerial) &&
         FreshDiscoveryObservation(now, observedAt);
}
} }
