
#include "ProfessionGearCore.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>

static int fails=0;
static void Check(bool v,const char* name){if(!v){++fails;std::cerr<<"FAIL: "<<name<<"\n";}}
static bool Eq(float a,float b,float e=.001f){return std::fabs(a-b)<=e;}

int main(){
  using namespace PGP;

  Check(Lower("AbC")=="abc","lower");
  Check(Trim("  x \r\n")=="x","trim");
  Check(ParseStat("Farming")==STAT_FARMING,"parse farming");
  Check(ParseTag("tool_mining")==TAG_TOOL_MINING,"parse tag");

  Check(QualityTier(.0f)==0,"tier crude");
  Check(QualityTier(.29f)==1,"tier shoddy");
  Check(QualityTier(.50f)==3,"tier high");
  Check(QualityTier(.99f)==6,"tier top");
  float lo=0,hi=0; TierRange(6,lo,hi);
  Check(Eq(lo,16)&&Eq(hi,25),"tier range top");
  Check(TierAffixChance(0)<TierAffixChance(6),"chance rises");

  std::map<std::string,std::vector<ItemTag> > overrides;
  std::set<std::string> exclusions;
  ItemDescriptor hoe; hoe.baseId="mod.hoe"; hoe.name="Iron Hoe"; hoe.quality=.5f;
  std::vector<ItemTag> tags=Classify(hoe,overrides,exclusions);
  Check(std::find(tags.begin(),tags.end(),TAG_TOOL_FARMING)!=tags.end(),"hoe classification");

  ItemDescriptor pick; pick.baseId="pick"; pick.name="Heavy Pickaxe"; pick.quality=.5f;
  tags=Classify(pick,overrides,exclusions);
  Check(std::find(tags.begin(),tags.end(),TAG_TOOL_MINING)!=tags.end(),"pick classification");

  ItemDescriptor sword; sword.baseId="sword"; sword.name="Katana"; sword.category="weapon"; sword.quality=.8f;
  Check(Classify(sword,overrides,exclusions).empty(),"sword no profession affix");

  exclusions.insert("mod.hoe");
  Check(Classify(hoe,overrides,exclusions).empty(),"exclusion wins");
  exclusions.clear();

  overrides["mod.hoe"].push_back(TAG_TOOL_RESEARCH);
  tags=Classify(hoe,overrides,exclusions);
  Check(tags.size()==1 && tags[0]==TAG_TOOL_RESEARCH,"override wins");

  tags.clear(); tags.push_back(TAG_TOOL_RESEARCH);
  std::vector<ProfessionStat> stats=AllowedStats(tags);
  Check(std::find(stats.begin(),stats.end(),STAT_SCIENCE)!=stats.end(),"research science");
  Check(std::find(stats.begin(),stats.end(),STAT_ROBOTICS)!=stats.end(),"research robotics");
  Check(std::find(stats.begin(),stats.end(),STAT_FARMING)==stats.end(),"research no farming");

  RuleConfig cfg; cfg.globalChance=100.0f;
  RoleProfile farmer; farmer.primary=STAT_FARMING; farmer.wealth01=.7f;
  hoe.stackable=false;
  tags.clear(); tags.push_back(TAG_TOOL_FARMING);
  AffixRecord a=RollAffixes(hoe,farmer,cfg,tags,"instance-a",1234,false);
  Check(!a.affixes.empty(),"forced roll produces affix");
  Check(a.affixes[0].stat==STAT_FARMING,"farming roll contextual");
  Check(a.affixes[0].percent>=7 && a.affixes[0].percent<=12,"magnitude in tier");

  AffixRecord a2=RollAffixes(hoe,farmer,cfg,tags,"instance-a",1234,false);
  Check(SerializeRecord(a)==SerializeRecord(a2),"deterministic same identity");

  AffixRecord b=RollAffixes(hoe,farmer,cfg,tags,"instance-b",1234,false);
  Check(SerializeRecord(a)!=SerializeRecord(b),"different identity can differ");

  ItemDescriptor stack=hoe; stack.stackable=true;
  AffixRecord st=RollAffixes(stack,farmer,cfg,tags,"stack",1,false);
  Check(st.affixes.empty(),"stackables excluded");

  RoleProfile poor; poor.primary=STAT_FARMING; poor.slave=true; poor.wealth01=.0f;
  RuleConfig low; low.globalChance=0.0f;
  Check(RollAffixes(hoe,poor,low,tags,"poor",1,false).affixes.empty(),"zero chance none");

  std::string serial=SerializeRecord(a);
  AffixRecord parsed;
  Check(ParseRecord(serial,parsed),"parse serialized");
  Check(parsed.instanceKey==a.instanceKey && parsed.affixes.size()==a.affixes.size(),"roundtrip identity");
  Check(!ParseRecord("bad",parsed),"reject malformed");
  Check(!ParseRecord("x\ty\t1\t999:10",parsed),"reject bad stat");

  std::vector<AffixRecord> rs;
  AffixRecord r1; r1.affixes.push_back(Affix(STAT_FARMING,5)); rs.push_back(r1);
  AffixRecord r2; r2.affixes.push_back(Affix(STAT_FARMING,7)); r2.affixes.push_back(Affix(STAT_SCIENCE,4)); rs.push_back(r2);
  Check(Eq(AggregatePercent(rs,STAT_FARMING),12),"aggregate");
  Check(Eq(AggregatePercent(rs,STAT_SCIENCE),4),"aggregate other");

  unsigned int seed=42;
  for(int i=0;i<1000;++i){float u=UnitRoll(seed);Check(u>=0&&u<=1,"rng range");}

  if(fails){std::cerr<<fails<<" test(s) failed\n";return 1;}
  std::cout<<"ProfessionGearCore tests passed\n";
  return 0;
}
