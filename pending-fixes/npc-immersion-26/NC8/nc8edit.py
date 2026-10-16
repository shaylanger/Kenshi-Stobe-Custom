import sys,re
root=sys.argv[1]
for d in ('src','legacy-v1'):
    p=f'{root}/{d}/ActivityPolicySupport.cpp'
    s=open(p,newline='').read()
    a=s.index('bool ProvenWild(Character* target) {')
    b=s.index('struct MineLease {')
    new='''// Returns "" when proven wild, else a specific failing-clause reason code (NC8).
std::string WildRefusal(Character* target,std::string& note) {
 ActivityWild::WildFacts f;
 note.clear();
 Faction* faction=target->getFaction();
 ActivePlatoon* active=target->getPlatoon();
 Platoon* squad=active ? active->me : NULL;
 f.identity=faction && faction->data && active && squad && target->getGameData();
 if(!f.identity) return ActivityWild::Verdict(f);
 const Ownerships& owned=squad->ownerships;
 f.factionNotReal=faction->isNotARealFaction();
 f.fundamentalNone=faction->fundamentalNPCType==OT_NONE;
 f.animalsOnly=active->isAnimalsOnly;
 f.trader=active->getIsTrader();
 f.roaming=squad->getSquadType()==SQ_ROAMING;
 f.baseTown=squad->myBaseHomeTownData ? true:false;
 f.homeTown=owned._homeTown ? true:false;
 f.homeBuilding=owned._homeBuilding.serial!=0;
 f.occupiedTown=owned.occupiedTown ? true:false;
 f.slaves=!owned.slaves.empty();
 f.stuff=owned.stuff.size()!=0;
 // Non-blocking note: loaded squad-template provenance (no longer required).
 if(!squad->squadTemplate) note="template=none";
 else {
  const bool fr=HasRef(squad->squadTemplate,"faction",faction->data->stringID);
  const bool sp=HasRef(squad->squadTemplate,"animals",target->getGameData()->stringID) ||
   HasRef(squad->squadTemplate,"animals2",target->getGameData()->stringID);
  note=std::string("templateFactionRef=")+(fr?"1":"0")+" templateSpeciesRef="+(sp?"1":"0");
 }
 return ActivityWild::Verdict(f);
}
bool ProvenWild(Character* target,std::string& reason) {
 std::string note;
 reason=WildRefusal(target,note);
 if(reason.empty()) return true;
 // One diagnostic line per refusal, rate limited per animal (about 5 s) so proposals do not spam.
 static std::map<unsigned,long> last;
 const unsigned serial=target->getHandle().serial;
 const long now=(long)std::clock();
 std::map<unsigned,long>::iterator it=last.find(serial);
 if(it==last.end() || now-it->second>5L*CLOCKS_PER_SEC || now<it->second) {
  last[serial]=now;
  if(last.size()>512) last.clear();
  try {
   std::ostringstream o;
   Faction* faction=target->getFaction();
   o<<"ACTIVITY_WILD_REFUSED reason="<<reason<<" serial="<<serial
    <<" species="<<(target->getGameData()?target->getGameData()->stringID:std::string("?"))
    <<" faction="<<(faction&&faction->data?faction->data->stringID:std::string("?"))<<" "<<note;
   ::Log(o.str());
  } catch(...) {}
 }
 return false;
}
'''
    s=s[:a]+new+s[b:]
    old='if(!ProvenWild(target)) {reason="animal_ownership_not_proven_wild";return true;}'
    assert s.count(old)==1
    s=s.replace(old,'if(!ProvenWild(target,reason)) return true;')
    s=s.replace('#include "KenshiBuildingCompat.h"\n','#include "KenshiBuildingCompat.h"\n#include "ActivityWildVerdict.h"\n',1)
    assert 'ActivityWildVerdict.h' in s
    s=s.replace('#include <limits>\n','#include <limits>\n#include <ctime>\n#include <sstream>\n',1)
    s=s.replace('namespace Stobe { namespace','void Log(const std::string&);\nnamespace Stobe { namespace',1)
    open(p,'w',newline='').write(s)
print('ok')
