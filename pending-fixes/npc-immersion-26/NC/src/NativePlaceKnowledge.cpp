// Keep full Town/Building SDK ABI isolated from KenshiBuildingCompat.h users.
#include "NativePlaceKnowledge.h"
#include <kenshi/Character.h>
#include <kenshi/Town.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <map>
#include <float.h>

namespace {
std::string SafeName(std::string name) {
  for (size_t i=0;i<name.size();++i) if ((unsigned char)name[i]<32 || name[i]==';' || name[i]=='|' || name[i]=='@') name[i]=' ';
  if (name.size()>70) name.resize(70);
  return name;
}
bool FinitePoint(const Ogre::Vector3 &p) {
  return _finite(p.x)&&_finite(p.y)&&_finite(p.z)&&
      std::abs(p.x)<10000000&&std::abs(p.y)<10000000&&std::abs(p.z)<10000000;
}
void Append(TownBase *town,unsigned int mapSerial,std::map<unsigned int,NativeKnownPlace> &known) {
  if (!town || reinterpret_cast<uintptr_t>(town)<=0x1000) return;
  NativeKnownPlace p; p.serial=town->getHandle().serial; p.mapSerial=mapSerial;
  p.name=SafeName(mapSerial?town->getName():town->getKnownName()); p.point=town->getPosition();
  if (p.serial && !p.name.empty() && FinitePoint(p.point)) known[p.serial]=p;
}
}
void CaptureNativeKnownPlaces(Character *actor,std::vector<NativeKnownPlace> &places) {
  places.clear();
  if (!actor) return;
  std::map<unsigned int,NativeKnownPlace> known;
  unsigned int currentTownSerial=0;
  TownBase *currentTown=0;
  try {
    currentTown=actor->getCurrentTownLocation();
    if (currentTown) currentTownSerial=currentTown->getHandle().serial;
  } catch (...) {}
  // The actor's actual current town is first-hand coarse-place knowledge,
  // independent of whether they carry a chart. mapSerial=0 marks that source.
  if (currentTown) Append(currentTown,0,known);
  // Read only the acting NPC's actual carried charts. Never consume them,
  // reveal towns globally or infer personal visits from player discovery.
  try {
    Inventory *inventory=actor->getInventory();
    if (inventory) {
      const lektor<Item *> &items=inventory->getAllItems();
      for (uint32_t i=0;i<items.size() && i<256;++i) {
        try {
          Item *item=items.stuff[i];
          if (!item || item->getDataType()!=MAP_ITEM) continue;
          MapItem *chart=static_cast<MapItem *>(item);
          const unsigned int mapSerial=item->getHandle().serial;
          if (!mapSerial) continue;
          for (size_t j=0;j<chart->townsHandles.size() && j<32;++j) {
            try {
              TownBase *town=chart->townsHandles[j].getTown();
              if (town && town->getHandle().serial!=currentTownSerial) Append(town,mapSerial,known);
            } catch (...) {}
          }
        } catch (...) {}
      }
    }
  } catch (...) {}
  for (std::map<unsigned int,NativeKnownPlace>::const_iterator it=known.begin();it!=known.end();++it) places.push_back(it->second);
}
bool ValidateNativeKnownPlace(Character *actor,unsigned int serial,unsigned int mapSerial,const Ogre::Vector3 &point,const std::string &name) {
  std::vector<NativeKnownPlace> places; CaptureNativeKnownPlaces(actor,places);
  for (size_t i=0;i<places.size();++i) {
    const NativeKnownPlace &p=places[i];
    if (p.serial==serial && p.mapSerial==mapSerial && p.name==name && p.point.squaredDistance(point)<=0.25f) return true;
  }
  return false;
}
