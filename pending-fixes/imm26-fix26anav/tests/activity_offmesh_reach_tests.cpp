// imm26-fix26anav behaviour test (row 26-a NC31): Stobe::ActivityReach::OffMeshShortRange, the pure decision ConcreteRuntimeBindings::Refresh
// uses when a visible Hunt target is close but the actor reports isOnNavmesh()==0 (pathExists cannot be asked).
// Build: g++ -std=gnu++11 -I<src dir> activity_offmesh_reach_tests.cpp
#include "ActivityOffMeshReach.h"
#include <cstdio>
#include <cmath>
using Stobe::ActivityReach::OffMeshShortRange;
static int fails=0;
#define CHECK(c) do{ if(!(c)){ std::printf("FAIL %s:%d %s\n",__FILE__,__LINE__,#c); ++fails; } }while(0)
int main(){
  // run 26-a-nc31: goat 31 u (d2=961.3) from an off-mesh, visible actor, dy small -> reachable now (was current_native_path_unconfirmed).
  CHECK(OffMeshShortRange(true,false,true,true,30.0,7.8,2.4));
  CHECK(OffMeshShortRange(true,false,true,true,-31.0,0.0,0.0) && OffMeshShortRange(true,false,true,true,0.0,-35.0,0.0));
  // range boundary 35 u planar
  CHECK(Stobe::ActivityReach::kOffMeshShortRange==35.0);
  CHECK(OffMeshShortRange(true,false,true,true,35.0,0.0,0.0) && !OffMeshShortRange(true,false,true,true,35.01,0.0,0.0));
  CHECK(!OffMeshShortRange(true,false,true,true,25.0,25.0,0.0));   // 35.36
  CHECK(!OffMeshShortRange(true,false,true,true,200.0,0.0,0.0));
  // vertical limit
  CHECK(OffMeshShortRange(true,false,true,true,10.0,0.0,12.0) && OffMeshShortRange(true,false,true,true,10.0,0.0,-12.0));
  CHECK(!OffMeshShortRange(true,false,true,true,10.0,0.0,12.5) && !OffMeshShortRange(true,false,true,true,10.0,0.0,-40.0));
  // every other gate must hold: only Hunt, only an off-mesh actor (an on-mesh actor keeps the pathExists verdict), visible, target on/near mesh
  CHECK(!OffMeshShortRange(false,false,true,true,5.0,0.0,0.0));
  CHECK(!OffMeshShortRange(true,true,true,true,5.0,0.0,0.0));
  CHECK(!OffMeshShortRange(true,false,false,true,5.0,0.0,0.0));
  CHECK(!OffMeshShortRange(true,false,true,false,5.0,0.0,0.0));
  // garbage never counts
  CHECK(!OffMeshShortRange(true,false,true,true,std::sqrt(-1.0),0.0,0.0));
  CHECK(!OffMeshShortRange(true,false,true,true,0.0,std::sqrt(-1.0),0.0));
  CHECK(!OffMeshShortRange(true,false,true,true,0.0,0.0,std::sqrt(-1.0)));
  CHECK(!OffMeshShortRange(true,false,true,true,1e30,1e30,0.0));
  std::printf("failures=%d\n",fails);
  return fails?1:0;
}
