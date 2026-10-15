#pragma once

// Stable, SDK-free interface for a KenshiTownCompat consumer. Include this
// from ordinary shim translation units; only ActivityCampTownReader.cpp may
// include Town.h. The opaque pointer MUST originate from the current
// TownList::getAllTowns() enumeration on the game thread.

#include "ActivityCampNativeAdapter.h"

class RootObject;

namespace Stobe { namespace ActivityCampNative {

// Copies exact SDK-read facts to the adapter DTO. False means no candidate.
bool ReadFormalCampTown(RootObject* townListEntry, TownBaseFacts* out);

// Uses the TownBase native border test; false on invalid pointer/coordinates.
bool IsPointInsideTownBorders(RootObject* townListEntry,
                              float x, float y, float z, bool* inside);

// The host shim implements this using its current TownList::getAllTowns()
// lektor. The callback is invoked synchronously on the game thread.
class ITownListEnumerator {
public:
  virtual ~ITownListEnumerator() {}
  virtual bool SnapshotTownListEntries(std::vector<RootObject*>& out) = 0;
};

class TownListBackedSource : public ITownBaseSource {
public:
  explicit TownListBackedSource(ITownListEnumerator& entries) : entries_(entries) {}
  bool SnapshotFormalTownBases(std::vector<TownBaseFacts>& out);
  bool IsWithinNativeBorders(const TownBaseFacts& anchor,
      float x, float y, float z, bool& inside);
private:
  ITownListEnumerator& entries_;
};

} }
