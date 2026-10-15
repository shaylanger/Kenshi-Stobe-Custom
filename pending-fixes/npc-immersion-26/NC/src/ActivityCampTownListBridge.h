#pragma once

#include "ActivityCampTownReader.h"
#include <string>
#include <vector>

namespace Stobe { namespace ActivityCampNative {

// Entry enumeration is deliberately invoked synchronously from the game
// update hook. The implementation rejects calls from every other thread.
class CurrentGameTownListEnumerator : public ITownListEnumerator {
public:
  bool SnapshotTownListEntries(std::vector<RootObject*>& out);
};

// Owns the reader source, opaque IDs and the short-lived registry. It stores
// copied DTOs only; native game pointers never escape a single snapshot call.
class ActivityCampCatalog {
public:
  ActivityCampCatalog();
  ~ActivityCampCatalog();
  void BeginScope(const std::string& worldId, const std::string& sessionId);
  void Invalidate();
  bool Discover(unsigned long long gameTime, std::vector<ZoneCandidate>& out);
  bool Resolve(const std::string& candidateId, unsigned long long gameTime,
               unsigned long long maxAge, ZoneCandidate& out);
  bool DigestConsent(const ZoneCandidate& zone,
      const std::vector<unsigned long long>& fixedTargets, std::string& digest);
  bool IsWithinNativeBorders(const TownBaseFacts& anchor,
      float x, float y, float z, bool& inside);
  bool OnGameThread() const;
private:
  CurrentGameTownListEnumerator entries_;
  TownListBackedSource source_;
  class SecureOpaqueIdSource;
  SecureOpaqueIdSource* ids_;
  Registry* registry_;
  ActivityCampCatalog(const ActivityCampCatalog&);
  ActivityCampCatalog& operator=(const ActivityCampCatalog&);
};

} }
