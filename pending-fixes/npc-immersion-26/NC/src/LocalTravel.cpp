#include "LocalTravel.h"
#include "Globals.h"
#include "Utils.h"
#include "KenshiBuildingCompat.h"
#include "KenshiTownIdentity.h"
#include <kenshi/AI/AI.h>
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/CharMovement.h>
#include <kenshi/GameWorld.h>
#include <kenshi/HavokCharacter.h>
#include <kenshi/NavMesh.h>
#include <kenshi/SensoryData.h>
#include <kenshi/GameData.h>
#include <kenshi/RaceData.h>
#include <kenshi/Faction.h>
#include "NativePlaceKnowledge.h"
#include <kenshi/util/UtilityT.h>
#include <ogre/OgreQuaternion.h>
#include <algorithm>
#include <set>
#include <map>
#include <vector>
#include <sstream>
#include <iomanip>
#include <ctime>
#include <cmath>
#include <float.h>
#include <objbase.h>

namespace Stobe { namespace LocalTravel {
namespace {
// Active candidates expire after ten minutes. Retained lineage permits only
// fresh native re-observation at consented dispatch; it never validates stale data.
const DWORD kLifetimeMs = 600000;
const DWORD kLineageLifetimeMs = 1800000;
const DWORD kMemoryMs = 1800000;
const float kLocalRange = 1800.0f;
// Technical query bounds, not a preference for a particular journey distance.
const float kPlaceRange = 20000.0f;
const float kLandmarkRange = 8000.0f;
const float kUnitsPerMetre = 10.0f;
const size_t kMaxCandidates = 32;
struct Source {
  std::string kind, name, templateId, raceId, factionId, observation;
  unsigned int serial;
  bool hostile;
  time_t lastSeen;
  Source() : serial(0), hostile(false), lastSeen(0) {}
};
struct Candidate {
  unsigned int actor;
  GameWorld *world;
  Ogre::Vector3 point;
  std::string id, label, evidence, kind;
  std::string direction, anchorName, anchorType, relation, terrain, town;
  unsigned int anchorSerial;
  Ogre::Vector3 anchorPoint;
  bool hasAnchorPoint;
  float maxRange;
  unsigned int mapSerial;
  std::string knowledge;
  float distance, elevation;
  int guardCount;
  Source source;
  DWORD created;
  time_t observed;
  Candidate() : actor(0), world(nullptr), anchorSerial(0), hasAnchorPoint(false), maxRange(kLocalRange), mapSerial(0), distance(0), elevation(0),
      guardCount(0), created(0), observed(0) {}
};
struct Sighting { Ogre::Vector3 point; Source source; DWORD tick; };
struct Anchor {
  Ogre::Vector3 point;
  std::string name, type;
  unsigned int serial;
  float distance;
  Source source;
  Anchor() : serial(0), distance(0) {}
};
bool Nearer(const Anchor &a, const Anchor &b) { return a.distance < b.distance; }
struct Snapshot {
  DWORD created;
  Ogre::Vector3 origin;
  std::vector<Candidate> candidates;
};
std::map<std::string, Candidate> registry;
std::map<unsigned int, Snapshot> snapshots;
std::map<unsigned int, std::map<unsigned int, Sighting> > sightings;
unsigned long sequence = 0;
std::string sessionId;
struct Lock {
  Lock() { EnterCriticalSection(&g_stateMutex); }
  ~Lock() { LeaveCriticalSection(&g_stateMutex); }
};
// Called with g_stateMutex held. A process-unique ID prevents saved server
// offers from accidentally matching a new registry after restarting the game.
bool EnsureSessionId() {
  if (!sessionId.empty()) return true;
  GUID guid;
  if (FAILED(CoCreateGuid(&guid))) return false;
  std::ostringstream value;
  value << std::hex << std::setfill('0') << std::setw(8) << guid.Data1
        << std::setw(4) << guid.Data2 << std::setw(4) << guid.Data3;
  for (size_t i = 0; i < 8; ++i) value << std::setw(2) << (unsigned int)guid.Data4[i];
  sessionId = value.str();
  return true;
}
bool Finite(const Ogre::Vector3 &p) {
  return _finite(p.x) && _finite(p.y) && _finite(p.z) &&
      std::abs(p.x) < 10000000 && std::abs(p.y) < 10000000 && std::abs(p.z) < 10000000;
}
float HorizontalDistance(const Ogre::Vector3 &a, const Ogre::Vector3 &b) {
  const float x = a.x-b.x, z = a.z-b.z;
  return std::sqrt(x*x+z*z);
}
std::string SafeText(std::string value, size_t maximum = 100) {
  for (size_t i=0; i<value.size(); ++i)
    if ((unsigned char)value[i]<32 || value[i]==';' || value[i]=='|' || value[i]=='@') value[i]=' ';
  if (value.size()>maximum) value.resize(maximum);
  return value;
}
std::string DataId(GameData *data) {
  return data ? SafeText(data->stringID, 160) : std::string();
}
// Native MapScreen::worldToMapCoords (Steam 1.0.65, RVA 48B950):
// increasing X moves right/east, increasing Z moves down/south on the map.
std::string Bearing(const Ogre::Vector3 &delta) {
  static const char *names[] = {"east", "southeast", "south", "southwest",
      "west", "northwest", "north", "northeast"};
  float angle = std::atan2(delta.z, delta.x);
  int sector = (int)std::floor(angle / 0.78539816339f + 0.5f);
  return names[(sector+8)%8];
}
bool IsGuard(Character *other) {
  AI *ai = other ? other->getAI() : nullptr;
  AITaskSytem *tasks = ai ? ai->getTaskSystem() : nullptr;
  if (!tasks) return false;
  const TaskType key = tasks->getCurrentGoal().key();
  return key == STAND_AT_GUARD_NODE_HOMEBUILDING_IN_OUT ||
      key == STAND_AT_BUILDING_GUARD_NODE ||
      key == STAND_AT_GUARD_NODE_HOMETOWN_OUTSIDE ||
      key == STAND_AT_GUARD_NODE_HOMEBUILDING_INDOORS_ONLY;
}
bool Project(GameWorld *world, Ogre::Vector3 requested, Ogre::Vector3 &point) {
  if (!Finite(requested)) return false;
  const float height = UtilityT::getTerrainHeight(requested.x, requested.z);
  if (!_finite(height)) return false;
  requested.y = height;
  return world->navmesh->getClosestPoint(requested, 45.0f, 1.0f, false, point) == 1 &&
      Finite(point) && HorizontalDistance(point, requested) <= 35.0f &&
      std::abs(point.y-height) <= 15.0f && !UtilityT::isIndoorsFast(point);
}
std::string Terrain(const Ogre::Vector3 &origin, const Ogre::Vector3 &point) {
  if (point.y-origin.y < 30.0f) return "ground";
  // A ridge claim needs a measured elongated terrain crest, not just a high
  // navmesh point (which could be a roof or bridge). Two perpendicular profiles
  // are enough for this deliberately local description, never a named ridge.
  const Ogre::Vector3 axes[] = {Ogre::Vector3::UNIT_X, Ogre::Vector3::UNIT_Z};
  for (size_t i=0; i<2; ++i) {
    const Ogre::Vector3 along=axes[i], across=axes[1-i];
    const Ogre::Vector3 a=point+along*180, b=point-along*180;
    const Ogre::Vector3 c=point+across*100, d=point-across*100;
    const float ha=UtilityT::getTerrainHeight(a.x,a.z), hb=UtilityT::getTerrainHeight(b.x,b.z);
    const float hc=UtilityT::getTerrainHeight(c.x,c.z), hd=UtilityT::getTerrainHeight(d.x,d.z);
    if (_finite(ha)&&_finite(hb)&&_finite(hc)&&_finite(hd) &&
        std::abs(ha-point.y)<25 && std::abs(hb-point.y)<25 &&
        point.y-hc>30 && point.y-hd>30) return "ridge_crest";
  }
  return "high_ground";
}
HavokCharacter *Avatar(Character *actor) {
  CharMovement *movement = actor ? actor->getMovement() : nullptr;
  return movement ? movement->havokCharacter : nullptr;
}
bool PathConfirmed(GameWorld *world, Character *actor, const Ogre::Vector3 &point) {
  if (!world || !world->navmesh || !Finite(point)) return false;
  HavokCharacter *avatar = Avatar(actor);
  // Native pathExists returns 1 only after connectivity succeeds; -1 means
  // the navmesh read lock is unavailable, 0 means invalid/no path. No orders.
  return avatar && avatar->isOnNavmesh() && world->navmesh->pathExists(avatar, point) == 1;
}
std::string Json(const std::vector<Candidate> &items) {
  std::ostringstream out;
  out << std::setprecision(9) << "[";
  for (size_t i = 0; i < items.size(); ++i) {
    const Candidate &c = items[i];
    if (i) out << ",";
    out << "{\"id\":\"" << c.id << "\",\"actor_serial\":" << c.actor
        << ",\"label\":\"" << EscapeJSON(c.label) << "\",\"x\":" << c.point.x
        << ",\"y\":" << c.point.y << ",\"z\":" << c.point.z
        << ",\"kind\":\"" << c.kind << "\",\"observed\":true,\"observed_unix\":"
        << static_cast<long long>(c.observed)
        << ",\"reachability\":\"path_confirmed\",\"knowledge_provenance\":\"" << EscapeJSON(c.knowledge)
        << "\",\"evidence\":\""
        << EscapeJSON(c.evidence) << "\",\"spatial\":{\"direction\":\"" << c.direction
        << "\",\"anchor_name\":\"" << EscapeJSON(c.anchorName)
        << "\",\"anchor_type\":\"" << c.anchorType
        << "\",\"anchor_serial\":" << c.anchorSerial
        << ",\"relation\":\"" << c.relation << "\",\"terrain\":\"" << c.terrain
        << "\",\"town_name\":\"" << EscapeJSON(c.town)
        << "\",\"distance\":" << c.distance << ",\"elevation_delta\":" << c.elevation
        << ",\"guard_count\":" << c.guardCount
        << ",\"path_evidence\":\"current navmesh connectivity; endpoint relationship only, not a verified path corridor\"}";
    if (!c.source.kind.empty()) {
      const Source &s=c.source;
      out << ",\"source\":{\"kind\":\"" << s.kind
          << "\",\"display_name\":\"" << EscapeJSON(s.name)
          << "\",\"template_id\":\"" << EscapeJSON(s.templateId)
          << "\",\"race_id\":\"" << EscapeJSON(s.raceId)
          << "\",\"faction_id\":\"" << EscapeJSON(s.factionId)
          << "\",\"target_serial\":" << s.serial
          << ",\"hostile_to_actor\":" << (s.hostile?"true":"false")
          << ",\"observation\":\"" << s.observation
          << "\",\"last_seen_unix\":" << static_cast<long long>(s.lastSeen) << "}";
    }
    out << "}";
  }
  out << "]";
  return out.str();
}
}

void Reset() {
  Lock lock;
  registry.clear();
  snapshots.clear();
  sightings.clear();
  // Never reuse an issued id after a save/world transition.
}

std::string CandidatesJson(GameWorld *world, Character *actor, bool forceRefresh) {
  try {
    if (!world || !actor || !world->navmesh) return "[]";
    const unsigned int serial = actor->getHandle().serial;
    if (!serial) return "[]";
    const Ogre::Vector3 origin = actor->getPosition();
    if (!Finite(origin)) return "[]";
    const DWORD now = GetTickCount();
    {
      Lock lock;
      auto cached = snapshots.find(serial);
      if (!forceRefresh && cached != snapshots.end() && now - cached->second.created < 30000 &&
          origin.squaredDistance(cached->second.origin) < 900)
        return Json(cached->second.candidates);
      for (auto it = snapshots.begin(); it != snapshots.end();) {
        if (now - it->second.created >= kLifetimeMs) snapshots.erase(it++);
        else ++it;
      }
      for (auto it = registry.begin(); it != registry.end();) {
        if (now - it->second.created >= kLineageLifetimeMs) registry.erase(it++);
        else ++it;
      }
      for (auto owner=sightings.begin(); owner!=sightings.end();) {
        for (auto it=owner->second.begin(); it!=owner->second.end();) {
          if (now-it->second.tick>=kMemoryMs) owner->second.erase(it++);
          else ++it;
        }
        if (owner->second.empty()) sightings.erase(owner++);
        else ++owner;
      }
    }
    Snapshot snapshot;
    snapshot.created = now;
    snapshot.origin = origin;
    std::vector<Anchor> landmarks, gates, guards, sources;
    // Loaded geometry is deliberately distinguished from native visual sensing.
    // This reads public nearby exterior structures, not interiors/inventories.
    lektor<RootObject *> nearbyBuildings, broaderBuildings;
    world->getObjectsWithinSphere(nearbyBuildings, origin, 1000.0f, BUILDING, 96, (RootObject *)actor);
    world->getObjectsWithinSphere(broaderBuildings, origin, kLandmarkRange, BUILDING, 192, (RootObject *)actor);
    std::vector<RootObject *> buildings;
    std::set<unsigned int> buildingSerials;
    for (uint32_t i=0;i<nearbyBuildings.size();++i) buildings.push_back(nearbyBuildings.stuff[i]);
    for (uint32_t i=0;i<broaderBuildings.size();++i) buildings.push_back(broaderBuildings.stuff[i]);
    for (size_t i=0; i<buildings.size(); ++i) {
      try {
        Building *building=(Building *)buildings[i];
        if (!building || (uintptr_t)building<0x1000 || building->_NV_isDestroyed()) continue;
        const BuildingClassType type=building->_NV_getBuildingClass();
        const BuildingFunction function=building->_NV_getSpecialFunction();
        Anchor a;
        a.point=building->getPosition();
        if (!Finite(a.point)) continue;
        a.distance=HorizontalDistance(origin,a.point);
        a.name=SafeText(building->getName(),70);
        a.serial=building->getHandle().serial;
        if (!a.serial || a.name.empty() || !buildingSerials.insert(a.serial).second) continue;
        if (type==BCTYPE_GATEWAY && a.distance<=1000.0f) { a.type="gate"; gates.push_back(a); }
        else if (type==BCTYPE_SHELL_WITH_INTERIOR) { a.type="building"; landmarks.push_back(a); }
        if ((function==BF_MINE || function==BF_MINE_NATURAL || type==BCTYPE_FARM) &&
            a.distance<=250.0f && !building->_NV_isBroken() && !UtilityT::isIndoorsFast(a.point)) {
          a.type="resource";
          a.source.kind="resource";
          a.source.name=a.name;
          a.source.serial=a.serial;
          a.source.templateId=DataId(building->getGameData());
          a.source.observation="loaded_nearby";
          a.source.lastSeen=time(NULL);
          sources.push_back(a);
        }
      } catch (...) {}
    }
    lektor<RootObject *> actors;
    const float visibleRange=(g_visionRange>0 && g_visionRange<1200)?g_visionRange:600.0f;
    world->getObjectsWithinSphere(actors, origin, visibleRange, CHARACTER, 96, (RootObject *)actor);
    SensoryData *senses=actor->getSensoryData();
    for (uint32_t i=0; i<actors.size(); ++i) {
      try {
        Character *other=(Character *)actors.stuff[i];
        if (!other || other==actor || !senses || !senses->canISeeThisGuy(other)) continue;
        Anchor a;
        a.point=other->getPosition();
        if (!Finite(a.point)) continue;
        a.distance=HorizontalDistance(origin,a.point);
        a.serial=other->getHandle().serial;
        a.name=SafeText(other->getName(),70);
        if (!a.serial || a.name.empty()) continue;
        if (IsGuard(other)) { a.type="guard"; guards.push_back(a); }
        const bool hostile=actor->isEnemy(other,true);
        if (other->isAnimal() || hostile) {
          a.type=other->isAnimal()?"creature":"hostile_group";
          a.source.kind=a.type;
          a.source.name=a.name;
          a.source.serial=a.serial;
          a.source.templateId=DataId(other->getGameData());
          RaceData *race=other->getRace();
          a.source.raceId=race?DataId(race->data):std::string();
          Faction *faction=other->getFaction();
          a.source.factionId=faction?DataId(faction->data):std::string();
          a.source.hostile=hostile;
          a.source.observation="visible";
          a.source.lastSeen=time(NULL);
          sources.push_back(a);
        }
      } catch (...) {}
    }
    std::sort(landmarks.begin(),landmarks.end(),Nearer);
    std::sort(gates.begin(),gates.end(),Nearer);
    std::sort(guards.begin(),guards.end(),Nearer);
    std::sort(sources.begin(),sources.end(),Nearer);
    std::string townName;
    Ogre::Vector3 townCentre;
    float townRadius=0;
    try {
      RootObject *town=(RootObject *)actor->getCurrentTownLocation();
      int alarm=0;
      if (town && ReadTownRuntimeStatus(town,&alarm,&townRadius) &&
          _finite(townRadius) && townRadius>0 && townRadius<10000) {
        townCentre=town->getPosition();
        townName=SafeText(town->getName(),70);
        if (!Finite(townCentre)) { townName.clear(); townRadius=0; }
      }
    } catch (...) { townName.clear(); townRadius=0; }
    unsigned int pathQueries=0;
    auto add = [&](Candidate c, const Ogre::Vector3 &requested) -> bool {
      if (snapshot.candidates.size()>=kMaxCandidates || pathQueries>=40 ||
          HorizontalDistance(origin,requested)>c.maxRange) return false;
      Ogre::Vector3 point;
      if (!Project(world,requested,point) || HorizontalDistance(origin,point)<40 ||
          HorizontalDistance(origin,point)>c.maxRange) return false;
      ++pathQueries;
      if (!PathConfirmed(world,actor,point)) return false;
      // A projected point must still satisfy its advertised endpoint relation.
      if (c.relation=="outside_town_radius" &&
          (HorizontalDistance(point,townCentre)<=townRadius+20 ||
           Bearing(point-townCentre)!=Bearing(requested-townCentre))) return false;
      if (c.hasAnchorPoint && (c.relation=="beyond_observed_position" || c.relation=="beyond_gate_position")) {
        Ogre::Vector3 bearing=c.anchorPoint-origin; bearing.y=0;
        if (bearing.squaredLength()<1) return false;
        bearing.normalise();
        Ogre::Vector3 beyond=point-c.anchorPoint; beyond.y=0;
        if (beyond.dotProduct(bearing)<20) return false;
      }
      if (c.kind=="terrain" && Terrain(origin,point)!=c.terrain) return false;
      c.actor = serial;
      c.world = world;
      c.point = point;
      c.created = now;
      c.observed = time(NULL);
      c.direction=Bearing(point-origin);
      const size_t bearingLabel=c.label.rfind(" to the ");
      if (bearingLabel!=std::string::npos) c.label=c.label.substr(0,bearingLabel)+" to the "+c.direction;
      c.distance=HorizontalDistance(origin,point)/kUnitsPerMetre;
      c.elevation=(point.y-origin.y)/kUnitsPerMetre;
      // A known_place is itself a town: its town_name is its own name, not the town the actor stands in.
      c.town=(c.kind=="known_place" && !c.anchorName.empty())?c.anchorName:townName;
      c.label=SafeText(c.label,115);
      c.evidence += " Endpoint projected onto outdoor terrain-connected navmesh and connectivity checked; no safety, permission, or target persistence guarantee.";
      {
        Lock lock;
        if (!EnsureSessionId()) return false;
        std::ostringstream id;
        id << "local:" << sessionId << ":" << serial << ":" << ++sequence;
        c.id = id.str();
        registry[c.id] = c;
      }
      snapshot.candidates.push_back(c);
      return true;
    };
    auto nearAnchor = [&](const Anchor &a, bool beyond) -> Ogre::Vector3 {
      Ogre::Vector3 away=a.point-origin; away.y=0;
      if (away.squaredLength()<1) away=Ogre::Vector3::UNIT_X;
      away.normalise();
      return a.point+away*(beyond?100.0f:-55.0f);
    };
    // Prioritize meaningful named places before compass samples can use budget.
    // A town is known from the actor's current town or a carried chart.
    // Global discovery and other squads' loaded towns do not confer knowledge.
    std::vector<NativeKnownPlace> knownPlaces;
    CaptureNativeKnownPlaces(actor,knownPlaces);
    std::map<unsigned int,NativeKnownPlace> knowledge;
    std::vector<Anchor> places;
    for (size_t i=0;i<knownPlaces.size();++i) {
      const NativeKnownPlace &known=knownPlaces[i];
      Anchor a; a.point=known.point; a.serial=known.serial;
      a.name=SafeText(known.name,70); a.type=known.mapSerial?"carried_map":"current_town";
      a.distance=HorizontalDistance(origin,a.point);
      if (!a.serial || a.name.empty() || !Finite(a.point) || a.distance>kPlaceRange) continue;
      places.push_back(a); knowledge[a.serial]=known;
    }
    std::sort(places.begin(),places.end(),Nearer);
    for (size_t i=0;i<places.size() && i<8;++i) {
      const Anchor &a=places[i]; Candidate c; c.kind="known_place";
      c.maxRange=kPlaceRange; c.anchorName=a.name; c.anchorType="town";
      c.anchorSerial=a.serial; c.anchorPoint=a.point; c.hasAnchorPoint=true;
      c.mapSerial=knowledge[a.serial].mapSerial;
      c.knowledge=a.type=="carried_map"?"actor_carried_map; no personal visit or road knowledge implied":"actor_current_town; no personal prior visit implied";
      c.relation="approach_known_town"; c.label="approach "+a.name;
      c.evidence="Actual native named town and position. Knowledge: "+c.knowledge+". Only this loaded endpoint's present connectivity is proven, not a regional road route.";
      add(c,nearAnchor(a,false));
    }
    for (size_t i=0;i<landmarks.size() && i<6;++i) {
      const Anchor &a=landmarks[i]; Candidate c; c.kind="landmark";
      c.maxRange=kLandmarkRange; c.anchorName=a.name; c.anchorType=a.type;
      c.anchorSerial=a.serial; c.anchorPoint=a.point; c.hasAnchorPoint=true;
      c.relation="near_exterior"; c.label="outside "+a.name+" to the "+Bearing(a.point-origin);
      c.knowledge="loaded_nearby_geometry; not visual sensing or personal visit proof";
      c.evidence="Actual nearby loaded public building exterior; no occupants, contents, permission, personal visit or visibility claim.";
      add(c,nearAnchor(a,false));
    }
    // Memory stores observations, never the continued existence of an animal,
    // enemy, or resource. Reissued search points get a new path check and ID.
    std::vector<Sighting> remembered;
    {
      Lock lock;
      auto &memory=sightings[serial];
      for (size_t i=0; i<sources.size(); ++i) {
        Sighting s; s.point=sources[i].point; s.source=sources[i].source; s.tick=now;
        memory[s.source.serial]=s;
      }
      for (auto it=memory.begin(); it!=memory.end();) {
        if (now-it->second.tick>=kMemoryMs) memory.erase(it++);
        else { if (it->second.tick!=now) remembered.push_back(it->second); ++it; }
      }
      while (memory.size()>48) memory.erase(memory.begin());
    }
    std::set<std::string> sourceTypes;
    for (size_t i=0; i<sources.size() && sourceTypes.size()<6; ++i) {
      const Anchor &a=sources[i];
      const std::string type=a.source.kind+":"+a.source.templateId+":"+a.source.raceId+":"+a.source.factionId;
      if (sourceTypes.count(type)) continue;
      Candidate c; c.kind="observed_source"; c.source=a.source;
      c.anchorName=a.name; c.anchorType=a.type; c.anchorSerial=a.serial; c.relation="near";
      c.label="near "+a.name+" to the "+Bearing(a.point-origin);
      c.evidence=a.source.observation=="visible"?
          "Native NPC vision currently detects this actual actor. Hostility is the engine's actor-relative result, not inferred from a name. Travel only, no attack or harvest.":
          "An intact exterior resource structure is loaded within 25 metres. This is nearby object data, not proof of visual line of sight, access rights, or remaining yield. Travel only.";
      if (add(c,nearAnchor(a,false))) sourceTypes.insert(type);
    }
    for (size_t i=0; i<guards.size() && i<2; ++i) {
      const Anchor &a=guards[i]; Candidate c; c.kind="guard_relative";
      c.anchorName=a.name; c.anchorType="guard"; c.anchorSerial=a.serial;
      c.anchorPoint=a.point; c.hasAnchorPoint=true;
      c.guardCount=1; c.relation="beyond_observed_position";
      c.label="ground beyond "+a.name+" to the "+Bearing(a.point-origin);
      c.evidence="A character visible to the NPC has a native guard-post goal. Endpoint lies farther along the bearing through that guard's observed position; the navigation path itself is not asserted to pass them.";
      add(c,nearAnchor(a,true));
    }
    for (size_t i=0; i<gates.size() && i<2; ++i) {
      const Anchor &a=gates[i]; Candidate c; c.kind="gate_relative";
      c.anchorName=a.name; c.anchorType="gate"; c.anchorSerial=a.serial;
      c.anchorPoint=a.point; c.hasAnchorPoint=true;
      c.relation="beyond_gate_position";
      c.label="ground beyond "+a.name+" to the "+Bearing(a.point-origin);
      c.evidence="Loaded exterior structure is an actual gateway building. Endpoint is beyond its position along the NPC-to-gate bearing. Gate opening and passage permission are not guaranteed.";
      add(c,nearAnchor(a,true));
    }
    const Ogre::Vector3 directions[] = {Ogre::Vector3(1,0,0),Ogre::Vector3(0.7071f,0,0.7071f),
      Ogre::Vector3(0,0,1),Ogre::Vector3(-0.7071f,0,0.7071f),Ogre::Vector3(-1,0,0),
      Ogre::Vector3(-0.7071f,0,-0.7071f),Ogre::Vector3(0,0,-1),Ogre::Vector3(0.7071f,0,-0.7071f)};
    if (!townName.empty()) for (size_t i=0; i<8; i+=2) {
      Candidate c; c.kind="town_boundary"; c.anchorName=townName; c.anchorType="town";
      c.relation="outside_town_radius";
      c.label="outside "+townName+" on its "+Bearing(directions[i])+" side";
      c.evidence="Endpoint lies beyond the native town centre/radius boundary. This is an administrative radius, not a claim that the path crosses a gate or wall.";
      add(c,townCentre+directions[i]*(townRadius+100.0f));
    }
    for (size_t i=0; i<8; ++i) {
      // Two scales let a genuine rise farther away win over flat close ground.
      Candidate best; Ogre::Vector3 bestPoint; bool have=false;
      for (int scale=0; scale<2; ++scale) {
        Ogre::Vector3 point;
        if (!Project(world,origin+directions[i]*(scale?1100.0f:400.0f),point)) continue;
        const std::string terrain=Terrain(origin,point);
        if (!have || (terrain!="ground" && best.terrain=="ground") || terrain=="ridge_crest") {
          have=true; bestPoint=point; best.terrain=terrain;
        }
      }
      if (!have) continue;
      best.kind="terrain"; best.relation="toward";
      const std::string feature=best.terrain=="ridge_crest"?"local ridge crest":best.terrain=="high_ground"?"higher ground":"ground";
      best.label=feature+" to the "+Bearing(bestPoint-origin);
      best.evidence=best.terrain=="ridge_crest"?
          "Native terrain samples show a raised elongated crest: both along-crest samples remain within 2.5 metres of the centre, both side samples drop over 3 metres. This is a local measured crest, not a named regional landmark.":
          best.terrain=="high_ground"?"Native terrain height is at least 3 metres above the NPC. No ridge morphology or lookout safety is inferred.":
          "Actual local terrain sample in this compass direction; no landmark, resource or safety is inferred.";
      add(best,bestPoint);
    }
    std::sort(remembered.begin(), remembered.end(), [&origin](const Sighting &a, const Sighting &b) {
      return HorizontalDistance(origin,a.point)<HorizontalDistance(origin,b.point);
    });
    size_t rememberedAdded=0;
    for (size_t i=0; i<remembered.size() && rememberedAdded<4 && pathQueries<40; ++i) {
      const Sighting &s=remembered[i]; Candidate c; c.kind="remembered_source"; c.source=s.source;
      c.source.observation="remembered"; c.anchorName=s.source.name; c.anchorType=s.source.kind;
      c.anchorSerial=s.source.serial; c.relation="search_last_seen_position";
      c.label="search near the last known "+s.source.name+" location";
      c.evidence="This NPC previously observed the source here in this world session. It is not currently confirmed; travel means search this area, not that the source is still present.";
      if (add(c,s.point)) ++rememberedAdded;
    }
    {
      Lock lock;
      snapshots[serial] = snapshot;
    }
    return Json(snapshot.candidates);
  } catch (...) {
    Log("LOCAL_TRAVEL: candidate query unavailable");
    return "[]";
  }
}

bool Validate(GameWorld *world, Character *actor, const std::string &id,
              float x, float y, float z, const std::string &label, std::string &reason) {
  reason.clear();
  try {
    Candidate saved;
    {
      Lock lock;
      auto it = registry.find(id);
      if (it == registry.end()) { reason = "local_plan_expired_or_unknown"; return false; }
      saved = it->second;
    }
    if (!actor || actor->getHandle().serial != saved.actor || world != saved.world) {
      reason = "local_plan_actor_mismatch"; return false;
    }
    if (GetTickCount() - saved.created >= kLifetimeMs) {
      reason = "local_plan_expired"; return false;
    }
    const Ogre::Vector3 requested(x,y,z);
    if (!Finite(requested) || requested.squaredDistance(saved.point) > 0.25f || label != saved.label) {
      reason = "local_plan_destination_mismatch"; return false;
    }
    if (saved.kind=="landmark" && saved.hasAnchorPoint) {
      lektor<RootObject *> anchors;
      world->getObjectsWithinSphere(anchors,saved.anchorPoint,20.0f,BUILDING,32,(RootObject *)actor);
      bool valid=false;
      for (uint32_t i=0;i<anchors.size();++i) {
        Building *building=(Building *)anchors.stuff[i];
        if (building && !building->_NV_isDestroyed() && building->getHandle().serial==saved.anchorSerial &&
            SafeText(building->getName(),70)==saved.anchorName &&
            building->getPosition().squaredDistance(saved.anchorPoint)<=0.25f) { valid=true; break; }
      }
      if (!valid) { reason="local_plan_landmark_changed"; return false; }
    }
    if (saved.kind=="known_place") {
      if (!ValidateNativeKnownPlace(actor,saved.anchorSerial,saved.mapSerial,saved.anchorPoint,saved.anchorName)) {
        reason="local_plan_named_anchor_or_knowledge_changed"; return false;
      }
    }

    if (HorizontalDistance(actor->getPosition(),saved.point)>saved.maxRange+400 || !PathConfirmed(world, actor, saved.point)) {
      reason = "local_plan_no_longer_reachable"; return false;
    }
    return true;
  } catch (...) {
    reason = "local_plan_validation_unavailable";
    return false;
  }
}

bool ValidateForDispatch(GameWorld *world, Character *actor, const std::string &id,
                         float x, float y, float z, const std::string &label,
                         std::string &reason) {
  if (Validate(world, actor, id, x, y, z, label, reason)) return true;
  if (reason != "local_plan_expired" && reason != "local_plan_expired_or_unknown") return false;
  Candidate original;
  {
    Lock lock;
    std::map<std::string,Candidate>::const_iterator it=registry.find(id);
    if (it==registry.end()) { reason="local_plan_expired_or_unknown"; return false; }
    original=it->second;
  }
  if (!actor || !world || original.actor!=actor->getHandle().serial || original.world!=world) {
    reason="local_plan_actor_mismatch"; return false;
  }
  const Ogre::Vector3 requested(x,y,z);
  if (!Finite(requested) || requested.squaredDistance(original.point)>0.25f || label!=original.label) {
    reason="local_plan_destination_mismatch"; return false;
  }
  // Re-run native observation, projection, and connectivity for the exact same
  // endpoint. Caller data selects a stored endpoint; it never supplies a route.
  const unsigned int serial=actor->getHandle().serial;
  { Lock lock; snapshots.erase(serial); }
  CandidatesJson(world,actor,true);
  std::string refreshedId;
  {
    Lock lock;
    std::map<unsigned int,Snapshot>::const_iterator observed=snapshots.find(serial);
    if (observed==snapshots.end()) { reason="local_plan_refresh_not_reobserved"; return false; }
    for (size_t i=0;i<observed->second.candidates.size();++i) {
      const Candidate &fresh=observed->second.candidates[i];
      if (fresh.id!=id && fresh.actor==original.actor && fresh.world==world &&
          GetTickCount()-fresh.created<kLifetimeMs && fresh.kind==original.kind &&
          fresh.label==original.label && fresh.point.squaredDistance(original.point)<=0.25f &&
          fresh.anchorSerial==original.anchorSerial && fresh.mapSerial==original.mapSerial &&
          fresh.knowledge==original.knowledge) { refreshedId=fresh.id; break; }
    }
  }
  if (refreshedId.empty()) { reason="local_plan_refresh_not_reobserved"; return false; }
  return Validate(world,actor,refreshedId,x,y,z,label,reason);
}

bool ValidateForDispatch(GameWorld *world, Character *actor, const std::string &id,
                         float x, float y, float z, const std::string &label,
                         const std::string &kind, std::string &reason) {
  Candidate saved;
  {
    Lock lock;
    std::map<std::string,Candidate>::const_iterator it=registry.find(id);
    if(it==registry.end()) { reason="local_plan_expired_or_unknown"; return false; }
    saved=it->second;
  }
  if(kind.empty() || saved.kind!=kind) { reason="local_plan_kind_mismatch"; return false; }
  return ValidateForDispatch(world,actor,id,x,y,z,label,reason);
}

} }
