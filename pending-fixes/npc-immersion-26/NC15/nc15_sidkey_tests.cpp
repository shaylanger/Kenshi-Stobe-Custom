// NC15 offline tests: camp identity keyed on GameData sid when the handle serial is 0.
// Build: g++ -std=c++14 -I<NC15 tree>/src nc15_sidkey_tests.cpp (header has no SDK includes).
#include "ActivityCampNativeAdapter.h"
#include <cassert>
#include <cstdio>
using namespace Stobe::ActivityCampNative;

class Src : public ITownBaseSource {
public:
  std::vector<TownBaseFacts> rows;
  bool SnapshotFormalTownBases(std::vector<TownBaseFacts>& out) { out=rows; return true; }
  bool IsWithinNativeBorders(const TownBaseFacts&,float,float,float,bool& r) { r=true; return true; }
};
class Ids : public IOpaqueIdSource {
public:
  bool Next(const std::string&,const std::string&,unsigned long long seq,std::string& out) {
    std::ostringstream s; s<<"v1:"<<std::hex<<std::setfill('0')<<std::setw(24)<<seq; out=s.str(); return true; }
};
// Mirrors what ReadFacts produces for a live entry: handle fields zero, runtimeSerial = SidKey(...)
static TownBaseFacts Zero(const char* sid,float x,float z,unsigned type) {
  TownBaseFacts f; f.gameDataSid=sid; f.knownName="Camp"; f.townType=type; f.x=x; f.y=1; f.z=z; f.radius=300;
  f.runtimeSerial=SidKey(f.gameDataSid,f.x,f.z); return f;
}
int main() {
  int checks=0;
#define CK(c) do{ ++checks; if(!(c)){ std::printf("FAIL line %d: %s\n",__LINE__,#c); return 1; } }while(0)
  TownBaseFacts a=Zero("town-a",100,200,Outpost);
  CK(a.handleSerial==0 && a.runtimeSerial!=0);
  CK(ValidFacts(a));                                   // the NC14 failure: handle serial 0 was rejected
  CK(ValidFacts(Zero("t",1,2,SlaveCamp)) && ValidFacts(Zero("t",1,2,Military)));
  CK(!ValidFacts(Zero("t",1,2,Town)) && !ValidFacts(Zero("t",1,2,Village)) && !ValidFacts(Zero("t",1,2,Nest)));
  // key properties
  CK(SidKey("town-a",100,200)==SidKey("town-a",100.2f,199.8f));   // rounding
  CK(SidKey("town-a",100,200)!=SidKey("town-b",100,200));
  CK(SidKey("town-a",100,200)!=SidKey("town-a",400,200));         // same sid, other place
  CK(SidKey("",0,0)!=0);
  // runtimeSerial zero is still invalid; unequal nonzero handle serial still invalid
  TownBaseFacts z=a; z.runtimeSerial=0; CK(!ValidFacts(z));
  TownBaseFacts m=a; m.handleSerial=7; CK(!ValidFacts(m));        // mismatch with nonzero handle
  m.runtimeSerial=7; CK(ValidFacts(m));                           // legacy handle-keyed path still valid
  TownBaseFacts bad=a; bad.radius=10; CK(!ValidFacts(bad));
  bad=a; bad.knownName.clear(); CK(!ValidFacts(bad));
  bad=a; bad.gameDataSid.clear(); CK(!ValidFacts(bad));
  // registry discover + resolve with sid-keyed rows, two towns sharing a sid
  Src s; Ids ids; s.rows.push_back(a); s.rows.push_back(Zero("town-a",900,900,Outpost)); s.rows.push_back(Zero("x",5,5,Town));
  Registry r(s,ids); r.BeginScope("w","s");
  std::vector<ZoneCandidate> found; CK(r.Discover(100,found) && found.size()==2);
  ZoneCandidate res; CK(r.Resolve(found[0].zoneCandidateId,101,1000,res) && SameFacts(res.town,a));
  CK(r.Resolve(found[1].zoneCandidateId,101,1000,res) && res.town.x==900);
  s.rows[0].x=101; CK(!r.Resolve(found[0].zoneCandidateId,102,1000,res));   // moved -> rejected
  // hostile selection and border observation work on sid-keyed zones
  s.rows[0]=a; ZoneCandidate zc=found[0];
  TargetFacts t; t.serial=9; t.x=110; t.z=210; t.active=t.visible=t.hostileToActor=t.pathConfirmed=t.insideNativeBorders=true; t.protectedTarget=false;
  std::vector<TargetFacts> ts(1,t); CK(SelectBoundedHostiles(zc,ts).size()==1);
  TargetFacts t2=t; t2.insideNativeBorders=false; CK(ObserveNativeBorder(s,zc,t2) && t2.insideNativeBorders);
  std::printf("RESULT NC15_SIDKEY_TESTS PASS checks=%d failures=0\n",checks);
  return 0;
}
