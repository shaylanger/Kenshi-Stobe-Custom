// imm26-fix26a3 behaviour test (row 26-a): ActivityTravel::EndedNearPoint, the pure decision NativeExecutor::Poll/Observe use when the engine has
// removed our MOVE_CUS_ORDERED order. Build: g++ -std=gnu++11 -I<src dir> activity_travel_engine_end_tests.cpp
#include "ActivityTravelArrival.h"
#include <cstdio>
#include <cmath>
using Stobe::ActivityTravel::EndedNearPoint;
static int fails=0;
#define CHECK(c) do{ if(!(c)){ std::printf("FAIL %s:%d %s\n",__FILE__,__LINE__,#c); ++fails; } }while(0)
// The 3D 8 u test that Poll applies first (squaredDistance <= 64): reference for the "old rule" columns below.
static bool Old3D(double dx,double dy,double dz){ return dx*dx+dy*dy+dz*dz<=64.0; }
int main(){
  // run 26-a-op17 / op14g shape: engine removed the order at planar 9.0 dy 3.0 (3D 9.49): old rule says not arrived, new rule arrived.
  CHECK(!Old3D(9.0,3.0,0.0));
  CHECK(EndedNearPoint(true,9.0,0.0));
  CHECK(EndedNearPoint(true,6.1,0.0) && EndedNearPoint(true,4.8,0.0) && EndedNearPoint(true,0.0,0.0));
  CHECK(EndedNearPoint(true,-9.0,0.0) && EndedNearPoint(true,0.0,-9.0) && EndedNearPoint(true,6.4,6.4));   // sign/diagonal: planar 9.05
  // boundary = kEngineEndRadius (16 u planar, same as NativeTravelRouteTarget::kEngineEndRadius)
  CHECK(Stobe::ActivityTravel::kEngineEndRadius==16.0);
  CHECK(EndedNearPoint(true,16.0,0.0) && !EndedNearPoint(true,16.01,0.0));
  CHECK(!EndedNearPoint(true,12.0,12.0));   // 16.97
  CHECK(EndedNearPoint(true,11.0,11.0));    // 15.56
  // an order that is still listed / a foreign or replaced order is never an arrival, however near
  CHECK(!EndedNearPoint(false,0.0,0.0) && !EndedNearPoint(false,9.0,0.0));
  // far actor with the order gone stays an interruption
  CHECK(!EndedNearPoint(true,40.0,0.0) && !EndedNearPoint(true,0.0,300.0));
  // garbage never counts
  CHECK(!EndedNearPoint(true,std::sqrt(-1.0),0.0) && !EndedNearPoint(true,0.0,std::sqrt(-1.0)));
  CHECK(!EndedNearPoint(true,1e30,1e30));
  std::printf("failures=%d\n",fails);
  return fails?1:0;
}
