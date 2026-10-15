#pragma once

// Isolated candidate contract for camp-scoped Clear. This header deliberately
// has no Kenshi SDK includes; the separate ActivityCampTownReader translation
// unit owns the game-thread ABI boundary and fails closed on unsupported roots.

#include <algorithm>
#include <cmath>
#include <float.h>
#include <iomanip>
#include <locale>
#include <sstream>
#include <string>
#include <vector>

namespace Stobe { namespace ActivityCampNative {

enum TownType { Nest=0, Outpost=1, Town=2, Village=3, Ruins=4,
                SlaveCamp=5, Military=6, Prison=7, NestMarker=8, Poi=9, NullTown=10 };

struct TownBaseFacts {
  // runtimeSerial mirrors handleSerial for quick indexing; the full handle
  // tuple below is the authoritative runtime identity.
  unsigned long long runtimeSerial;
  unsigned int handleContainer, handleContainerSerial, handleIndex,
               handleSerial, handleType;
  std::string gameDataSid;
  std::string knownName;
  unsigned int townType;
  float x, y, z, radius;
  TownBaseFacts() : runtimeSerial(0), handleContainer(0), handleContainerSerial(0),
    handleIndex(0), handleSerial(0), handleType(0), townType(0),
    x(0), y(0), z(0), radius(0) {}
};

struct TargetFacts {
  unsigned long long serial;
  float x, y, z;
  bool active, visible, hostileToActor, protectedTarget, pathConfirmed,
       insideNativeBorders;
  TargetFacts() : serial(0), x(0), y(0), z(0), active(false), visible(false),
    hostileToActor(false), protectedTarget(true), pathConfirmed(false),
    insideNativeBorders(false) {}
};

inline bool IsFormalCampType(unsigned int type) {
  return type == Outpost || type == SlaveCamp || type == Military;
}
inline bool Finite(float v) {
#if defined(_MSC_VER)
  return _finite(static_cast<double>(v)) != 0;
#else
  return std::isfinite(static_cast<double>(v)) != 0;
#endif
}
inline bool ValidFacts(const TownBaseFacts& f) {
  return f.runtimeSerial != 0 && f.handleSerial != 0 &&
    f.runtimeSerial == f.handleSerial && !f.gameDataSid.empty() &&
    f.gameDataSid.size() <= 256 && !f.knownName.empty() && f.knownName.size() <= 256 &&
    IsFormalCampType(f.townType) && Finite(f.x) && Finite(f.y) && Finite(f.z) &&
    Finite(f.radius) && f.radius >= 25.0f && f.radius <= 2000.0f;
}

// Implemented only by a separately ABI-reviewed game-thread bridge. It must
// return exact TownBase facts from the current world; no LLM/user strings enter.
class ITownBaseSource {
public:
  virtual ~ITownBaseSource() {}
  virtual bool SnapshotFormalTownBases(std::vector<TownBaseFacts>& out) = 0;
  virtual bool IsWithinNativeBorders(const TownBaseFacts& anchor,
      float x, float y, float z, bool& inside) = 0;
};

// Safe production default until a supported SDK primitive is verified.
class UnsupportedTownBaseSource : public ITownBaseSource {
public:
  bool SnapshotFormalTownBases(std::vector<TownBaseFacts>& out) {
    out.clear(); return false;
  }
  bool IsWithinNativeBorders(const TownBaseFacts&,float,float,float,bool& inside) {
    inside=false; return false;
  }
};

// ID source must provide collision-resistant opaque tokens. No token is issued
// if the host lacks that facility; deterministic counters alone are insufficient.
class IOpaqueIdSource {
public:
  virtual ~IOpaqueIdSource() {}
  virtual bool Next(const std::string& worldScope, const std::string& sessionScope,
                    unsigned long long sequence, std::string& out) = 0;
};

// Digest provider is intentionally injected so the protocol can use the host's
// approved SHA-256/HMAC implementation without dragging one into this candidate.
class IConsentDigest {
public:
  virtual ~IConsentDigest() {}
  virtual bool Sha256Hex(const std::string& canonical, std::string& out) = 0;
};

struct ZoneCandidate {
  std::string zoneCandidateId; // versioned, opaque, session/world scoped
  std::string worldScope;
  std::string sessionScope;
  TownBaseFacts town;
  unsigned long long observedAt;
  ZoneCandidate() : observedAt(0) {}
};

inline bool SameFacts(const TownBaseFacts& a, const TownBaseFacts& b) {
  return a.runtimeSerial == b.runtimeSerial && a.handleContainer == b.handleContainer &&
    a.handleContainerSerial == b.handleContainerSerial && a.handleIndex == b.handleIndex &&
    a.handleSerial == b.handleSerial && a.handleType == b.handleType &&
    a.gameDataSid == b.gameDataSid &&
    a.knownName == b.knownName && a.townType == b.townType && a.x == b.x &&
    a.y == b.y && a.z == b.z && a.radius == b.radius;
}

class Registry {
public:
  Registry(ITownBaseSource& source, IOpaqueIdSource& ids)
    : source_(source), ids_(ids), sequence_(0) {}

  // A new world OR loaded playthrough/session invalidates all prior references.
  void BeginScope(const std::string& world, const std::string& session) {
    if (world != world_ || session != session_) candidates_.clear();
    world_ = world; session_ = session;
  }
  void Invalidate() { candidates_.clear(); world_.clear(); session_.clear(); }

  bool Discover(unsigned long long now, std::vector<ZoneCandidate>& out) {
    out.clear();
    if (world_.empty() || session_.empty() || !now) return false;
    std::vector<TownBaseFacts> found;
    if (!source_.SnapshotFormalTownBases(found)) return false;
    for (std::size_t old=0; old<candidates_.size();) {
      if (now<candidates_[old].observedAt || now-candidates_[old].observedAt>=86400)
        candidates_.erase(candidates_.begin()+old);
      else ++old;
    }
    for (std::size_t i=0; i<found.size(); ++i) {
      if (!ValidFacts(found[i])) continue;
      ZoneCandidate c; c.worldScope=world_; c.sessionScope=session_;
      c.town=found[i]; c.observedAt=now;
      bool reused=false;
      for (std::size_t j=0; j<candidates_.size(); ++j) {
        ZoneCandidate& old=candidates_[j];
        if (old.worldScope==world_ && old.sessionScope==session_ &&
            old.observedAt<=now && now-old.observedAt<86400 &&
            SameFacts(old.town,found[i])) {
          c=old; reused=true; break;
        }
      }
      if (reused) { out.push_back(c); continue; }
      ++sequence_;
      if (candidates_.size() >= 256) break;
      if (!ids_.Next(world_,session_,sequence_,c.zoneCandidateId) ||
          c.zoneCandidateId.size()<16 || c.zoneCandidateId.size()>128 ||
          c.zoneCandidateId.compare(0,3,"v1:") != 0) continue;
      bool duplicate=false;
      for (std::size_t j=0; j<candidates_.size(); ++j)
        if (candidates_[j].zoneCandidateId == c.zoneCandidateId) { duplicate=true; break; }
      if (duplicate) continue;
      candidates_.push_back(c); out.push_back(c);
    }
    return true;
  }

  bool Resolve(const std::string& id, unsigned long long now,
               unsigned long long maxAge, ZoneCandidate& out) {
    if (id.empty() || !now || !maxAge) return false;
    for (std::size_t i=0; i<candidates_.size(); ++i) {
      const ZoneCandidate& c=candidates_[i];
      if (c.zoneCandidateId != id) continue;
      if (c.worldScope != world_ || c.sessionScope != session_ ||
          now < c.observedAt || now-c.observedAt >= maxAge) return false;
      std::vector<TownBaseFacts> current;
      if (!source_.SnapshotFormalTownBases(current)) return false;
      for (std::size_t j=0; j<current.size(); ++j) {
        if (current[j].runtimeSerial == c.town.runtimeSerial &&
            ValidFacts(current[j]) && SameFacts(current[j],c.town)) {
          out=c; return true;
        }
      }
      return false;
    }
    return false;
  }

private:
  ITownBaseSource& source_;
  IOpaqueIdSource& ids_;
  std::string world_, session_;
  unsigned long long sequence_;
  std::vector<ZoneCandidate> candidates_;
};

inline std::vector<unsigned long long> SelectBoundedHostiles(
    const ZoneCandidate& c, const std::vector<TargetFacts>& targets) {
  std::vector<unsigned long long> ids;
  if (!ValidFacts(c.town) || c.zoneCandidateId.empty()) return ids;
  const float radius = c.town.radius < 1200.0f ? c.town.radius : 1200.0f;
  for (std::size_t i=0; i<targets.size(); ++i) {
    const TargetFacts& t=targets[i];
    if (!t.serial || !t.active || !t.visible || !t.hostileToActor ||
        t.protectedTarget || !t.pathConfirmed || !t.insideNativeBorders ||
        !Finite(t.x) || !Finite(t.y) || !Finite(t.z)) continue;
    const float dx=t.x-c.town.x, dz=t.z-c.town.z;
    if (dx*dx+dz*dz <= radius*radius) ids.push_back(t.serial);
  }
  std::sort(ids.begin(),ids.end());
  ids.erase(std::unique(ids.begin(),ids.end()),ids.end());
  if (ids.empty() || ids.size()>32) ids.clear();
  return ids;
}

// Refreshes the engine-owned border fact from the current source before target
// selection/execution. On lookup failure it clears the fact and fails closed.
inline bool ObserveNativeBorder(ITownBaseSource& source,
    const ZoneCandidate& zone, TargetFacts& target) {
  target.insideNativeBorders=false;
  bool inside=false;
  if (!ValidFacts(zone.town) || !Finite(target.x) || !Finite(target.y) ||
      !Finite(target.z) || !source.IsWithinNativeBorders(
        zone.town,target.x,target.y,target.z,inside)) return false;
  target.insideNativeBorders=inside;
  return true;
}

inline std::string ConsentCanonical(const ZoneCandidate& c,
                                    const std::vector<unsigned long long>& targets) {
  std::ostringstream s;
  s.imbue(std::locale::classic());
  s << "activity-camp-consent-v1\n" << std::setprecision(9)
    << c.zoneCandidateId.size() << ':' << c.zoneCandidateId
    << c.worldScope.size() << ':' << c.worldScope
    << c.sessionScope.size() << ':' << c.sessionScope
    << c.observedAt << ':'
    << c.town.runtimeSerial << ':' << c.town.handleContainer << ':'
    << c.town.handleContainerSerial << ':' << c.town.handleIndex << ':'
    << c.town.handleSerial << ':' << c.town.handleType << ':'
    << c.town.gameDataSid.size() << ':' << c.town.gameDataSid
    << c.town.knownName.size() << ':' << c.town.knownName
    << c.town.townType << ':' << c.town.x << ':' << c.town.y << ':'
    << c.town.z << ':' << c.town.radius << ':';
  std::vector<unsigned long long> sorted=targets;
  std::sort(sorted.begin(),sorted.end());
  for (std::size_t i=0; i<sorted.size(); ++i) s << sorted[i] << ',';
  return s.str();
}

inline bool BuildConsentDigest(const ZoneCandidate& c,
    const std::vector<unsigned long long>& targets, IConsentDigest& digest,
    std::string& out) {
  out.clear();
  if (!ValidFacts(c.town) || c.zoneCandidateId.size()<16 ||
      c.zoneCandidateId.size()>128 || c.zoneCandidateId.compare(0,3,"v1:") != 0 ||
      c.worldScope.empty() || c.worldScope.size()>128 ||
      c.sessionScope.empty() || c.sessionScope.size()>128 ||
      targets.empty() || targets.size()>32) return false;
  std::vector<unsigned long long> sorted=targets;
  std::sort(sorted.begin(),sorted.end());
  if (!sorted[0] || std::adjacent_find(sorted.begin(),sorted.end()) != sorted.end()) return false;
  if (!digest.Sha256Hex(ConsentCanonical(c,sorted),out) || out.size()!=64) return false;
  for (std::size_t i=0; i<out.size(); ++i)
    if (!((out[i]>='0' && out[i]<='9') || (out[i]>='a' && out[i]<='f') ||
          (out[i]>='A' && out[i]<='F'))) { out.clear(); return false; }
  return true;
}

inline bool VerifyConsentRoundTrip(const ZoneCandidate& displayed,
    const ZoneCandidate& accepted, const std::vector<unsigned long long>& shown,
    const std::vector<unsigned long long>& acceptedTargets,
    IConsentDigest& digest, const std::string& displayedDigest) {
  if (displayed.zoneCandidateId != accepted.zoneCandidateId ||
      displayed.worldScope != accepted.worldScope ||
      displayed.sessionScope != accepted.sessionScope ||
      displayed.observedAt != accepted.observedAt ||
      !SameFacts(displayed.town,accepted.town) || shown.empty() ||
      shown.size()>32) return false;
  std::vector<unsigned long long> a=shown, b=acceptedTargets;
  std::sort(a.begin(),a.end()); std::sort(b.begin(),b.end());
  if (a != b || std::adjacent_find(a.begin(),a.end()) != a.end() || !a[0]) return false;
  std::string actual;
  return BuildConsentDigest(accepted,b,digest,actual) && actual==displayedDigest;
}

} } // namespace Stobe::ActivityCampNative
