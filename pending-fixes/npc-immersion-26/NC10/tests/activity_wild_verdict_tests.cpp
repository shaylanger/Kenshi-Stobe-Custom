// Offline tests for Stobe::ActivityWild::Verdict (NC8 ProvenWild relaxation).
#include "../src/ActivityWildVerdict.h"
#include <cstdio>
#include <cstring>
using namespace Stobe::ActivityWild;
static int fails=0;
static void Expect(const char* name,const WildFacts& f,const char* want){
 const char* got=Verdict(f);
 if(strcmp(got,want)){printf("FAIL %s: got '%s' want '%s'\n",name,got,want);++fails;}
 else printf("ok   %s -> '%s'\n",name,got);
}
static WildFacts Wild(){WildFacts f;f.identity=f.factionNotReal=f.fundamentalNone=f.animalsOnly=f.roaming=true;return f;}
int main(){
 WildFacts f=Wild(); Expect("natural wild herd (no template clauses involved)",f,"");
 f=Wild(); f.identity=false; Expect("identity unavailable",f,"animal_not_wild_identity_unavailable");
 f=Wild(); f.factionNotReal=false; Expect("real faction",f,"animal_not_wild_real_faction");
 f=Wild(); f.fundamentalNone=false; Expect("fundamental npc type",f,"animal_not_wild_real_faction");
 f=Wild(); f.animalsOnly=false; Expect("mixed platoon",f,"animal_not_wild_squad_type");
 f=Wild(); f.trader=true; Expect("trader",f,"animal_not_wild_squad_type");
 f=Wild(); f.roaming=false; Expect("not roaming",f,"animal_not_wild_squad_type");
 f=Wild(); f.baseTown=true; Expect("base town",f,"animal_not_wild_ownership");
 f=Wild(); f.homeTown=true; Expect("home town",f,"animal_not_wild_ownership");
 f=Wild(); f.homeBuilding=true; Expect("home building alone (NC10: roaming wild herds always have it)",f,"");
 f=Wild(); f.homeBuilding=true; f.homeTown=true; Expect("home building + home town still owned",f,"animal_not_wild_ownership");
 f=Wild(); f.homeBuilding=true; f.factionNotReal=false; Expect("home building does not rescue a real faction",f,"animal_not_wild_real_faction");
 f=Wild(); f.homeBuilding=true; f.trader=true; Expect("home building does not rescue a trader",f,"animal_not_wild_squad_type");
 f=Wild(); f.occupiedTown=true; Expect("occupied town",f,"animal_not_wild_ownership");
 f=Wild(); f.slaves=true; Expect("slaves",f,"animal_not_wild_ownership");
 f=Wild(); f.stuff=true; Expect("stuff",f,"animal_not_wild_ownership");
 f=Wild(); f.factionNotReal=false; f.baseTown=true; Expect("faction clause reported first",f,"animal_not_wild_real_faction");
 {
  WildFacts g; g.baseTown=true; g.stuff=true;
  std::string fl=Flags(g);
  if(fl!="baseTown=1 homeTown=0 homeBuilding=0 occupiedTown=0 slaves=0 stuff=1"){printf("FAIL Flags: %s\n",fl.c_str());++fails;} else printf("ok   Flags -> '%s'\n",fl.c_str());
  std::string z=Flags(WildFacts());
  if(z!="baseTown=0 homeTown=0 homeBuilding=0 occupiedTown=0 slaves=0 stuff=0"){printf("FAIL Flags zero: %s\n",z.c_str());++fails;} else printf("ok   Flags zero\n");
 }
 printf(fails?"RESULT NC10-WILD-TESTS FAIL %d\n":"RESULT NC10-WILD-TESTS PASS (NC8 clauses, homeBuilding no longer ownership, Flags)\n",fails);
 return fails?1:0;
}
