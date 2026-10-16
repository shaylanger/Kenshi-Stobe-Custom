// Offline tests for Stobe::ActivityWild::Verdict (NC8 ProvenWild relaxation).
#include "ActivityWildVerdict.h"
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
 f=Wild(); f.homeBuilding=true; Expect("home building",f,"animal_not_wild_ownership");
 f=Wild(); f.occupiedTown=true; Expect("occupied town",f,"animal_not_wild_ownership");
 f=Wild(); f.slaves=true; Expect("slaves",f,"animal_not_wild_ownership");
 f=Wild(); f.stuff=true; Expect("stuff",f,"animal_not_wild_ownership");
 f=Wild(); f.factionNotReal=false; f.baseTown=true; Expect("faction clause reported first",f,"animal_not_wild_real_faction");
 printf(fails?"RESULT NC8-WILD-TESTS FAIL %d\n":"RESULT NC8-WILD-TESTS PASS 14/14\n",fails);
 return fails?1:0;
}
