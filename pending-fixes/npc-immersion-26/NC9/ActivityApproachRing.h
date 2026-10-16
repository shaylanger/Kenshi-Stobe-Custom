#pragma once
// Pure ring-sample geometry for the Mine approach-point path test (NC9). No game types, testable offline.
// A natural iron/copper node is a building whose centre lies inside its own footprint hole, so
// navmesh->pathExists(avatar, centre) is 0 even when the node is reachable. We instead sample
// points on rings AROUND the node (nearest the actor first) and let the caller project each to the
// navmesh and test the path to that approach point.
#include <cmath>
namespace Stobe { namespace ActivityApproach {
enum { kRadii = 3, kAngles = 8, kCount = kRadii * kAngles };
// i in [0,kCount): ring-major (14 u, 24 u, 36 u), angles start at baseAngle (direction node->actor).
inline void Sample(float cx, float cz, float baseAngle, unsigned i, float& x, float& z) {
 static const float R[kRadii] = {14.0f, 24.0f, 36.0f};
 const unsigned ring = (i / kAngles) % kRadii, k = i % kAngles;
 const float a = baseAngle + (float)k * (6.28318530718f / (float)kAngles);
 x = cx + R[ring] * std::cos(a);
 z = cz + R[ring] * std::sin(a);
}
}}
