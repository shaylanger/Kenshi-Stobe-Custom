// ABI boundary: keep this translation unit isolated from Platoon.h, following
// the existing KenshiTownIdentity.cpp pattern. No raw offsets or vtable calls.
#include "ActivityCampTownReader.h"

#include <stdint.h>
#include <kenshi/Town.h>

namespace Stobe { namespace ActivityCampNative {
namespace {
bool IsUsableRoot(RootObject* root) {
  return root && reinterpret_cast<uintptr_t>(root) > 0x1000;
}

bool ReadFacts(RootObject* townListEntry, TownBaseFacts* out) {
  if (!IsUsableRoot(townListEntry) || !out) return false;
  // This is the supported virtual type check used by the existing town
  // readers. Do not cast until the enum says this is a TownBase-derived root.
  try {
    if (townListEntry->getDataType() != TOWN) return false;
    // Callers may pass only an entry obtained from TownList::getAllTowns on
    // the game thread. This TU alone knows the full SDK TownBase definition.
    TownBase* town=static_cast<TownBase*>(townListEntry);
    GameData* data=town->data;
    if (!data || !data->isValid() || data->stringID.empty()) return false;

    const hand& h=town->handle;
    const Ogre::Vector3 p=town->_NV_getPosition();
    TownBaseFacts facts;
    facts.runtimeSerial=h.serial;
    facts.handleContainer=h.container;
    facts.handleContainerSerial=h.containerSerial;
    facts.handleIndex=h.index;
    facts.handleSerial=h.serial;
    facts.handleType=static_cast<unsigned int>(h.type);
    facts.gameDataSid=data->stringID;
    facts.knownName=town->getKnownName();
    facts.townType=static_cast<unsigned int>(town->townType);
    facts.x=p.x; facts.y=p.y; facts.z=p.z;
    facts.radius=town->_NV_getRadius();
    if (!ValidFacts(facts)) return false;
    *out=facts;
    return true;
  } catch (...) { return false; }
}
}

bool ReadFormalCampTown(RootObject* townListEntry, TownBaseFacts* out) {
  return ReadFacts(townListEntry,out);
}

bool IsPointInsideTownBorders(RootObject* townListEntry,
                              float x, float y, float z, bool* inside) {
  TownBaseFacts verified;
  if (!inside || !Finite(x) || !Finite(y) || !Finite(z) ||
      !ReadFacts(townListEntry,&verified)) return false;
  try {
    TownBase* town=static_cast<TownBase*>(townListEntry);
    Ogre::Vector3 point(x,y,z);
    *inside=town->withinBordersRange(point,1.0f);
    return true;
  } catch (...) { *inside=false; return false; }
}

bool TownListBackedSource::SnapshotFormalTownBases(std::vector<TownBaseFacts>& out) {
  out.clear();
  std::vector<RootObject*> entries;
  if (!entries_.SnapshotTownListEntries(entries) || entries.size()>4096) return false;
  for (std::size_t i=0; i<entries.size(); ++i) {
    TownBaseFacts facts;
    if (ReadFormalCampTown(entries[i],&facts)) out.push_back(facts);
  }
  return true;
}

bool TownListBackedSource::IsWithinNativeBorders(const TownBaseFacts& anchor,
    float x, float y, float z, bool& inside) {
  inside=false;
  std::vector<RootObject*> entries;
  if (!ValidFacts(anchor) || !Finite(x) || !Finite(y) || !Finite(z) ||
      !entries_.SnapshotTownListEntries(entries) || entries.size()>4096) return false;
  RootObject* match=0;
  unsigned int matches=0;
  for (std::size_t i=0; i<entries.size(); ++i) {
    TownBaseFacts current;
    if (ReadFormalCampTown(entries[i],&current) && SameFacts(anchor,current)) {
      match=entries[i]; ++matches;
      if (matches>1) return false; // Ambiguous live identity: fail closed.
    }
  }
  if (matches != 1) return false;
  return IsPointInsideTownBorders(match,x,y,z,&inside);
}
} }
