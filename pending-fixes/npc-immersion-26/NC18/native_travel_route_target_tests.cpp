// NC18 offline fixture for NativeTravelRouteTarget.h (g++ -std=c++14 -I<src> native_travel_route_target_tests.cpp).
#include "NativeTravelRouteTarget.h"
#include <cstdio>
#include <cmath>
#include <limits>
using namespace Stobe::NativeTravelRouteTarget;

static int checks = 0, failures = 0;
#define CHECK(c) do { ++checks; if (!(c)) { ++failures; std::printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

// A world with a walled pocket: the requested point (inside x in [-100,100], z in [-100,100]) is NOT connected to the NPC;
// everything with z >= 120 (outside the wall) is connected.
struct Terrain { double h; double operator()(float, float) const { return h; } };
struct NanTerrain { double operator()(float, float) const { return std::numeric_limits<double>::quiet_NaN(); } };
struct Snap { bool ok; bool operator()(const Pt &q, Pt &o) const { o = q; return ok; } };
struct Reach {
  int mode; // 0 = pocket rule, 1 = everything reachable, 2 = unknown always, 3 = pocket + unknown after 2 probes
  int calls;
  Reach(int m) : mode(m), calls(0) {}
  int operator()(const Pt &p) {
    ++calls;
    if (mode == 1) return 1;
    if (mode == 2) return -1;
    if (mode == 3 && calls > 2) return -1;
    return p.z >= 120.0f ? 1 : 0;
  }
};

int main() {
  // 1. arrival rules (19-d numbers: stopped 146 u planar / 71 u above; 13-c: 152 u planar)
  CHECK(NearPoint(Pt(0, 0, 0), Pt(5, 20, 5), kArriveRadius));
  CHECK(!NearPoint(Pt(0, 0, 0), Pt(9, 0, 0), kArriveRadius));
  CHECK(NearPoint(Pt(0, 0, 0), Pt(12, 30, 5), kEngineEndRadius));
  CHECK(!NearPoint(Pt(-62371.1f, 399.5f, 16490.6f), Pt(-62341.0f, 328.8f, 16346.8f), kEngineEndRadius));
  CHECK(!NearPoint(Pt(-62464.4f, 337.4f, 16498.7f), Pt(-62461.0f, 328.8f, 16346.8f), kEngineEndRadius));
  CHECK(!NearPoint(Pt(0, 0, 0), Pt(0, 41, 0), kArriveRadius));      // vertical slop is bounded
  CHECK(NearPoint(Pt(0, 0, 0), Pt(0, 39, 0), kArriveRadius));
  CHECK(!NearPoint(Pt(0, 0, 0), Pt(std::numeric_limits<float>::quiet_NaN(), 0, 0), 100));
  CHECK(!NearPoint(Pt(0, 0, 0), Pt(std::numeric_limits<float>::infinity(), 0, 0), 1e30));
  CHECK(RouteNear(false, Pt(0, 0, 0), Pt(900, 0, 900), Pt(1, 0, 1), kArriveRadius));   // route: leader irrelevant
  CHECK(!RouteNear(true, Pt(0, 0, 0), Pt(900, 0, 900), Pt(1, 0, 1), kArriveRadius));   // follow: leader must be there
  CHECK(RouteNear(true, Pt(0, 0, 0), Pt(2, 0, 2), Pt(1, 0, 1), kArriveRadius));

  // 2. reachable request is kept untouched (one probe)
  { Terrain t = {0}; Snap s = {true}; Reach r(1);
    Choice c = Choose(Pt(10, 5, 10), 0, t, s, r);
    CHECK(c.verdict == KEEP_REQUESTED && c.probes == 1 && c.point.x == 10 && c.point.y == 5 && c.drift == 0); }
  // 3. unknown reachability never changes the order
  { Terrain t = {0}; Snap s = {true}; Reach r(2);
    Choice c = Choose(Pt(10, 5, 10), 0, t, s, r);
    CHECK(c.verdict == KEEP_UNKNOWN && c.probes == 1 && c.point.z == 10); }
  // 4. unreachable pocket -> nearest reachable ring point on the NPC side (bearing +z), within kMaxDrift, terrain y
  { Terrain t = {321.5}; Snap s = {true}; Reach r(0);
    Choice c = Choose(Pt(0, 328.8f, 0), 1.5707963268, t, s, r);   // NPC lies toward +z
    CHECK(c.verdict == ADJUSTED);
    CHECK(c.point.z >= 120.0f && c.drift <= kMaxDrift && c.drift > 100.0);
    CHECK(std::fabs(c.point.y - 321.5f) < 0.01f);
    CHECK(c.probes <= kMaxProbes);
    CHECK(Planar(c.point, Pt(0, 0, 0)) <= kMaxDrift); }
  // 5. substitute on the far side of the pocket is not preferred: bearing -z first tries the wrong side, still finds +z
  { Terrain t = {0}; Snap s = {true}; Reach r(0);
    Choice c = Choose(Pt(0, 0, 0), -1.5707963268, t, s, r);
    CHECK(c.verdict == ADJUSTED && c.point.z >= 120.0f && c.probes <= kMaxProbes); }
  // 6. nothing reachable within the drift -> NONE_FOUND, order stays on the request (honest failure later)
  { Terrain t = {0}; Snap s = {true}; Reach r(0);
    Choice c = Choose(Pt(0, 0, -400), 0, t, s, r);                 // pocket far from any reachable z >= 120
    CHECK(c.verdict == NONE_FOUND && c.point.z == -400 && c.probes <= kMaxProbes); }
  // 7. no navmesh point near any candidate -> no further probes, NONE_FOUND
  { Terrain t = {0}; Snap s = {false}; Reach r(0);
    Choice c = Choose(Pt(0, 0, 0), 0, t, s, r);
    CHECK(c.verdict == NONE_FOUND && r.calls == 1); }
  // 8. unknown mid-search stops the search (never trust a guess)
  { Terrain t = {0}; Snap s = {true}; Reach r(3);
    Choice c = Choose(Pt(0, 0, 0), 1.5707963268, t, s, r);
    CHECK(c.verdict == NONE_FOUND && c.note == "probe_unknown" && r.calls == 3); }
  // 9. terrain unknown (NaN) -> candidates skipped, request kept
  { NanTerrain t; Snap s = {true}; Reach r(0);
    Choice c = Choose(Pt(0, 0, 0), 0, t, s, r);
    CHECK(c.verdict == NONE_FOUND && c.point.z == 0 && r.calls == 1); }
  // 10. non-finite request is rejected without probing
  { Terrain t = {0}; Snap s = {true}; Reach r(1);
    Choice c = Choose(Pt(std::numeric_limits<float>::quiet_NaN(), 0, 0), 0, t, s, r);
    CHECK(c.verdict == KEEP_UNKNOWN && r.calls == 0 && c.note == "requested_not_finite"); }
  // 11. probe budget is respected
  { Terrain t = {0}; Snap s = {true}; Reach r(0);
    Choice c = Choose(Pt(0, 0, -5000), 0, t, s, r);
    CHECK(r.calls <= kMaxProbes); }

  std::printf("RESULT NC18_ROUTE_TARGET_TESTS %s checks=%d failures=%d\n", failures ? "FAIL" : "PASS", checks, failures);
  return failures ? 1 : 0;
}
