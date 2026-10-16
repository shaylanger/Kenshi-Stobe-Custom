#pragma once
// NC18: pure (engine-free) route-target and arrival rules for native-owned travel, shared by
// NativeTravelLifecycle.cpp and the portable offline fixture (tests/native_travel_route_target_tests.cpp).
//
// Problem (rows IMM-13-c, 13-c-neg, 19-d, 23-a): the destination the server sends is a town/gate point whose y and
// walkability were never checked. When that point is not connected to the NPC on the navmesh, Kenshi's MOVE order
// ends at the end of a PARTIAL path ~150 u away, and the old 3D 8 u check can never be satisfied.
// Fix: (1) at Start, if the requested point is proven unreachable, order the NPC to the nearest navmesh point that
// IS reachable (<= kMaxDrift u away) so that an ordinary arrival (<= kArriveRadius) is physically possible;
// (2) arrival is measured on the ground plane with a bounded vertical slop (the server y is not a terrain height).
// Nothing here widens the arrival radius beyond the engine's own order-completion radius.
#include <cmath>
#include <string>
#include <vector>

namespace Stobe { namespace NativeTravelRouteTarget {

const double kArriveRadius = 8.0;     // planar, same as the old 3D check
const double kEngineEndRadius = 16.0; // planar, only when the engine itself already removed the MOVE order
const double kVerticalSlop = 40.0;    // |dy| allowed (server gate y vs terrain)
const double kMaxDrift = 160.0;       // a substitute target must be this close (planar) to the requested point
const int kMaxProbes = 28;            // navmesh path probes per Start (main thread)

inline bool IsFinite(double v) { return v == v && v - v == 0.0; }

struct Pt {
  float x, y, z;
  Pt() : x(0), y(0), z(0) {}
  Pt(float a, float b, float c) : x(a), y(b), z(c) {}
};
inline bool Finite(const Pt &p) { return IsFinite(p.x) && IsFinite(p.y) && IsFinite(p.z); }
inline double Planar(const Pt &a, const Pt &b) {
  const double dx = double(a.x) - b.x, dz = double(a.z) - b.z;
  return std::sqrt(dx * dx + dz * dz);
}

// Ground-plane arrival with bounded vertical slop. NaN/inf never match.
inline bool NearPoint(const Pt &actor, const Pt &goal, double radius) {
  if (!Finite(actor) || !Finite(goal)) return false;
  const double dy = std::fabs(double(actor.y) - goal.y);
  return Planar(actor, goal) <= radius && dy <= kVerticalSlop;
}
// FOLLOW trips also need the leader at the endpoint (the NPC follows the player there).
inline bool RouteNear(bool follow, const Pt &actor, const Pt &leader, const Pt &goal, double radius) {
  return NearPoint(actor, goal, radius) && (!follow || NearPoint(leader, goal, radius));
}

enum Verdict { KEEP_REQUESTED = 0, KEEP_UNKNOWN = 1, ADJUSTED = 2, NONE_FOUND = 3 };
struct Choice {
  Verdict verdict;
  Pt point;
  int probes;
  double drift;
  std::string note;
  Choice() : verdict(KEEP_UNKNOWN), probes(0), drift(0) {}
};

inline const char *VerdictName(Verdict v) {
  switch (v) {
    case KEEP_REQUESTED: return "requested_reachable";
    case ADJUSTED: return "adjusted_to_reachable";
    case NONE_FOUND: return "no_reachable_substitute";
    default: return "reach_unknown";
  }
}

// terrain(x,z) -> height or NaN; snap(Pt q, Pt &out) -> navmesh point near q (false when none/indoors);
// reach(Pt p) -> 1 connected to the NPC, 0 proven unconnected, -1 unknown (never guess). Probes are bounded.
template <class Terrain, class Snap, class Reach>
Choice Choose(const Pt &req, double bearingRad, Terrain &terrain, Snap &snap, Reach &reach) {
  Choice c; c.point = req;
  if (!Finite(req)) { c.note = "requested_not_finite"; return c; }
  const int first = reach(req); ++c.probes;
  if (first == 1) { c.verdict = KEEP_REQUESTED; return c; }
  if (first != 0) { c.verdict = KEEP_UNKNOWN; return c; }
  // The requested point is proven unconnected. Candidates, nearest first: the terrain-projected point, then rings
  // around the requested point starting on the side facing the NPC.
  const double radii[] = { 0, 25, 60, 100, 140 };
  const double turns[] = { 0, 1.0471975512, -1.0471975512, 2.0943951024, -2.0943951024, 3.1415926536 };
  for (size_t ri = 0; ri < sizeof(radii) / sizeof(radii[0]); ++ri) {
    const size_t angles = ri == 0 ? 1 : sizeof(turns) / sizeof(turns[0]);
    for (size_t ai = 0; ai < angles; ++ai) {
      if (c.probes >= kMaxProbes) { c.verdict = NONE_FOUND; c.note = "probe_budget"; return c; }
      Pt q = req;
      if (ri > 0) {
        q.x = float(req.x + radii[ri] * std::cos(bearingRad + turns[ai]));
        q.z = float(req.z + radii[ri] * std::sin(bearingRad + turns[ai]));
      }
      const double h = terrain(q.x, q.z);
      if (!IsFinite(h)) continue;
      q.y = float(h);
      Pt s;
      if (!snap(q, s) || !Finite(s) || Planar(s, req) > kMaxDrift) continue;
      const int r = reach(s); ++c.probes;
      if (r < 0) { c.verdict = NONE_FOUND; c.note = "probe_unknown"; return c; }
      if (r == 1) { c.verdict = ADJUSTED; c.point = s; c.drift = Planar(s, req); return c; }
    }
  }
  c.verdict = NONE_FOUND; c.note = "none_within_drift";
  return c;
}

} } // namespace Stobe::NativeTravelRouteTarget
