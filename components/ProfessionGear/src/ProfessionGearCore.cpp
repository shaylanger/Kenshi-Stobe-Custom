
#include "ProfessionGearCore.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <iomanip>
#include <sstream>

namespace PGP {

RuleConfig::RuleConfig()
    : enabled(true), autoClassify(true), globalChance(1.0f),
      npcRoleMultiplier(1.35f), playerCraftMultiplier(1.15f),
      poorNpcMultiplier(0.20f), maxAffixes(2) {}

std::string Lower(const std::string& value) {
  std::string out = value;
  for (size_t i = 0; i < out.size(); ++i)
    out[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(out[i])));
  return out;
}

std::string Trim(const std::string& value) {
  size_t a = value.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = value.find_last_not_of(" \t\r\n");
  return value.substr(a, b - a + 1);
}

static bool Has(const std::string& h, const char* n) {
  return h.find(n) != std::string::npos;
}

std::string StatName(ProfessionStat stat) {
  switch (stat) {
    case STAT_LABOURING: return "Labouring";
    case STAT_SCIENCE: return "Science";
    case STAT_ENGINEERING: return "Engineering";
    case STAT_ROBOTICS: return "Robotics";
    case STAT_WEAPON_SMITH: return "Weapon Smithing";
    case STAT_ARMOUR_SMITH: return "Armour Smithing";
    case STAT_CROSSBOW_SMITH: return "Crossbow Smithing";
    case STAT_MEDIC: return "Medic";
    case STAT_TURRETS: return "Turrets";
    case STAT_FARMING: return "Farming";
    case STAT_COOKING: return "Cooking";
    case STAT_ATHLETICS: return "Athletics";
    case STAT_SWIMMING: return "Swimming";
    case STAT_PERCEPTION: return "Perception";
    case STAT_STEALTH: return "Stealth";
    case STAT_ASSASSINATION: return "Assassination";
    case STAT_LOCKPICKING: return "Lockpicking";
    case STAT_THIEVERY: return "Thievery";
    default: return "None";
  }
}

ProfessionStat ParseStat(const std::string& value) {
  const std::string v = Lower(Trim(value));
  if (v=="labouring" || v=="laboring") return STAT_LABOURING;
  if (v=="science") return STAT_SCIENCE;
  if (v=="engineering") return STAT_ENGINEERING;
  if (v=="robotics") return STAT_ROBOTICS;
  if (v=="weapon smithing" || v=="weapon_smithing") return STAT_WEAPON_SMITH;
  if (v=="armour smithing" || v=="armor smithing" || v=="armour_smithing") return STAT_ARMOUR_SMITH;
  if (v=="crossbow smithing" || v=="crossbow_smithing") return STAT_CROSSBOW_SMITH;
  if (v=="medic" || v=="medicine") return STAT_MEDIC;
  if (v=="turrets") return STAT_TURRETS;
  if (v=="farming") return STAT_FARMING;
  if (v=="cooking") return STAT_COOKING;
  if (v=="athletics") return STAT_ATHLETICS;
  if (v=="swimming") return STAT_SWIMMING;
  if (v=="perception") return STAT_PERCEPTION;
  if (v=="stealth") return STAT_STEALTH;
  if (v=="assassination") return STAT_ASSASSINATION;
  if (v=="lockpicking") return STAT_LOCKPICKING;
  if (v=="thievery") return STAT_THIEVERY;
  return STAT_NONE;
}

std::string TagName(ItemTag tag) {
  switch (tag) {
    case TAG_TOOL_FARMING: return "TOOL_FARMING";
    case TAG_TOOL_MINING: return "TOOL_MINING";
    case TAG_TOOL_RESEARCH: return "TOOL_RESEARCH";
    case TAG_TOOL_ENGINEERING: return "TOOL_ENGINEERING";
    case TAG_TOOL_ROBOTICS: return "TOOL_ROBOTICS";
    case TAG_TOOL_MEDIC: return "TOOL_MEDIC";
    case TAG_TOOL_WEAPON_SMITH: return "TOOL_WEAPON_SMITH";
    case TAG_TOOL_ARMOUR_SMITH: return "TOOL_ARMOUR_SMITH";
    case TAG_TOOL_CROSSBOW_SMITH: return "TOOL_CROSSBOW_SMITH";
    case TAG_TOOL_COOKING: return "TOOL_COOKING";
    case TAG_HEAD_FARMING: return "HEAD_FARMING";
    case TAG_HEAD_MINING: return "HEAD_MINING";
    case TAG_HEAD_RESEARCH: return "HEAD_RESEARCH";
    case TAG_BODY_RESEARCH: return "BODY_RESEARCH";
    case TAG_BODY_ENGINEERING: return "BODY_ENGINEERING";
    case TAG_BODY_MEDIC: return "BODY_MEDIC";
    case TAG_BODY_SMITH: return "BODY_SMITH";
    case TAG_GLOVES_WORK: return "GLOVES_WORK";
    case TAG_BOOTS_WORK: return "BOOTS_WORK";
    case TAG_BOOTS_TRAVEL: return "BOOTS_TRAVEL";
    case TAG_PACK_ORE: return "PACK_ORE";
    case TAG_PACK_CROP: return "PACK_CROP";
    case TAG_PACK_CONSTRUCTION: return "PACK_CONSTRUCTION";
    case TAG_PACK_MEDICAL: return "PACK_MEDICAL";
    case TAG_PACK_TRADE: return "PACK_TRADE";
    case TAG_PACK_TECH: return "PACK_TECH";
    case TAG_TURRET_GEAR: return "TURRET_GEAR";
    case TAG_SCOUT_GEAR: return "SCOUT_GEAR";
    case TAG_STEALTH_GEAR: return "STEALTH_GEAR";
    default: return "NONE";
  }
}

ItemTag ParseTag(const std::string& value) {
  const std::string v = Lower(Trim(value));
  for (int i = TAG_TOOL_FARMING; i <= TAG_STEALTH_GEAR; ++i) {
    ItemTag t = static_cast<ItemTag>(i);
    if (Lower(TagName(t)) == v) return t;
  }
  return TAG_NONE;
}

int QualityTier(float q) {
  if (q < 0.15f) return 0;
  if (q < 0.30f) return 1;
  if (q < 0.48f) return 2;
  if (q < 0.66f) return 3;
  if (q < 0.82f) return 4;
  if (q < 0.94f) return 5;
  return 6;
}

void TierRange(int tier, float& minP, float& maxP) {
  static const float mins[] = {2,3,5,7,10,13,16};
  static const float maxs[] = {4,6,9,12,16,20,25};
  if (tier < 0) tier = 0;
  if (tier > 6) tier = 6;
  minP = mins[tier]; maxP = maxs[tier];
}

float TierAffixChance(int tier) {
  static const float c[] = {.20f,.30f,.45f,.60f,.75f,.88f,.96f};
  if (tier < 0) tier = 0;
  if (tier > 6) tier = 6;
  return c[tier];
}

static void AddTag(std::vector<ItemTag>& out, ItemTag t) {
  if (t != TAG_NONE && std::find(out.begin(),out.end(),t)==out.end()) out.push_back(t);
}

std::vector<ItemTag> Classify(const ItemDescriptor& item,
                              const std::map<std::string,std::vector<ItemTag> >& overrides,
                              const std::set<std::string>& exclusions) {
  std::vector<ItemTag> out;
  const std::string id = Lower(item.baseId);
  if (exclusions.count(id)) return out;
  std::map<std::string,std::vector<ItemTag> >::const_iterator it = overrides.find(id);
  if (it != overrides.end()) return it->second;
  const std::string n = Lower(item.name+" "+item.category+" "+item.slot);

  if (Has(n,"hoe") || Has(n,"sickle") || Has(n,"farm tool")) AddTag(out,TAG_TOOL_FARMING);
  if (Has(n,"pickaxe") || Has(n,"pick axe") || Has(n,"mining tool")) AddTag(out,TAG_TOOL_MINING);
  if (Has(n,"lab coat") || Has(n,"research coat")) AddTag(out,TAG_BODY_RESEARCH);
  if (Has(n,"research") || Has(n,"science") || Has(n,"laboratory")) AddTag(out,TAG_TOOL_RESEARCH);
  if (Has(n,"engineer") || Has(n,"construction tool") || Has(n,"tool belt")) AddTag(out,TAG_TOOL_ENGINEERING);
  if (Has(n,"robotic") || Has(n,"robotics")) AddTag(out,TAG_TOOL_ROBOTICS);
  if (Has(n,"medic") || Has(n,"medical") || Has(n,"doctor") || Has(n,"first aid")) AddTag(out,TAG_TOOL_MEDIC);
  if (Has(n,"weapon smith")) AddTag(out,TAG_TOOL_WEAPON_SMITH);
  if (Has(n,"armour smith") || Has(n,"armor smith")) AddTag(out,TAG_TOOL_ARMOUR_SMITH);
  if (Has(n,"crossbow smith")) AddTag(out,TAG_TOOL_CROSSBOW_SMITH);
  if (Has(n,"cooking") || Has(n,"chef")) AddTag(out,TAG_TOOL_COOKING);
  if (Has(n,"straw hat")) AddTag(out,TAG_HEAD_FARMING);
  if (Has(n,"miner") && (Has(n,"hat") || Has(n,"helmet") || Has(n,"goggle"))) AddTag(out,TAG_HEAD_MINING);
  if ((Has(n,"research") || Has(n,"science")) && (Has(n,"goggle") || Has(n,"glass") || Has(n,"visor"))) AddTag(out,TAG_HEAD_RESEARCH);
  if (Has(n,"glove") && (Has(n,"work") || Has(n,"industrial"))) AddTag(out,TAG_GLOVES_WORK);
  if (Has(n,"boot") && (Has(n,"work") || Has(n,"industrial"))) AddTag(out,TAG_BOOTS_WORK);
  if (Has(n,"boot") && (Has(n,"travel") || Has(n,"scout") || Has(n,"runner"))) AddTag(out,TAG_BOOTS_TRAVEL);
  if (Has(n,"ore pack") || Has(n,"mining pack")) AddTag(out,TAG_PACK_ORE);
  if (Has(n,"crop pack") || Has(n,"farm pack")) AddTag(out,TAG_PACK_CROP);
  if (Has(n,"construction pack") || Has(n,"builder pack")) AddTag(out,TAG_PACK_CONSTRUCTION);
  if (Has(n,"medical pack") || Has(n,"medic pack")) AddTag(out,TAG_PACK_MEDICAL);
  if (Has(n,"trade pack") || Has(n,"caravan pack")) AddTag(out,TAG_PACK_TRADE);
  if (Has(n,"research pack") || Has(n,"tech pack")) AddTag(out,TAG_PACK_TECH);
  if (Has(n,"turret") && (Has(n,"goggle") || Has(n,"visor") || Has(n,"gear"))) AddTag(out,TAG_TURRET_GEAR);
  if (Has(n,"scout") || Has(n,"ranger")) AddTag(out,TAG_SCOUT_GEAR);
  if (Has(n,"stealth") || Has(n,"infiltrat")) AddTag(out,TAG_STEALTH_GEAR);
  return out;
}

static void AddStat(std::vector<ProfessionStat>& out, ProfessionStat s) {
  if (s!=STAT_NONE && std::find(out.begin(),out.end(),s)==out.end()) out.push_back(s);
}

std::vector<ProfessionStat> AllowedStats(const std::vector<ItemTag>& tags) {
  std::vector<ProfessionStat> out;
  for (size_t i=0;i<tags.size();++i) {
    switch(tags[i]) {
      case TAG_TOOL_FARMING: case TAG_HEAD_FARMING: case TAG_PACK_CROP: AddStat(out,STAT_FARMING); break;
      case TAG_TOOL_MINING: case TAG_HEAD_MINING: case TAG_PACK_ORE: AddStat(out,STAT_LABOURING); break;
      case TAG_TOOL_RESEARCH: case TAG_HEAD_RESEARCH: case TAG_BODY_RESEARCH: case TAG_PACK_TECH:
        AddStat(out,STAT_SCIENCE); AddStat(out,STAT_ROBOTICS); break;
      case TAG_TOOL_ENGINEERING: case TAG_BODY_ENGINEERING: case TAG_PACK_CONSTRUCTION:
        AddStat(out,STAT_ENGINEERING); AddStat(out,STAT_LABOURING); break;
      case TAG_TOOL_ROBOTICS: AddStat(out,STAT_ROBOTICS); AddStat(out,STAT_ENGINEERING); break;
      case TAG_TOOL_MEDIC: case TAG_BODY_MEDIC: case TAG_PACK_MEDICAL: AddStat(out,STAT_MEDIC); break;
      case TAG_TOOL_WEAPON_SMITH: AddStat(out,STAT_WEAPON_SMITH); break;
      case TAG_TOOL_ARMOUR_SMITH: case TAG_BODY_SMITH: AddStat(out,STAT_ARMOUR_SMITH); AddStat(out,STAT_WEAPON_SMITH); break;
      case TAG_TOOL_CROSSBOW_SMITH: AddStat(out,STAT_CROSSBOW_SMITH); break;
      case TAG_TOOL_COOKING: AddStat(out,STAT_COOKING); break;
      case TAG_GLOVES_WORK: AddStat(out,STAT_LABOURING); AddStat(out,STAT_ENGINEERING); break;
      case TAG_BOOTS_WORK: AddStat(out,STAT_LABOURING); AddStat(out,STAT_ATHLETICS); break;
      case TAG_BOOTS_TRAVEL: case TAG_SCOUT_GEAR: AddStat(out,STAT_ATHLETICS); AddStat(out,STAT_PERCEPTION); break;
      case TAG_TURRET_GEAR: AddStat(out,STAT_TURRETS); AddStat(out,STAT_PERCEPTION); break;
      case TAG_STEALTH_GEAR: AddStat(out,STAT_STEALTH); AddStat(out,STAT_LOCKPICKING); break;
      case TAG_PACK_TRADE: AddStat(out,STAT_ATHLETICS); break;
      default: break;
    }
  }
  return out;
}

bool IsProfessionStat(ProfessionStat s) { return s>STAT_NONE && s<=STAT_THIEVERY; }

unsigned int Hash32(const std::string& text) {
  unsigned int h=2166136261u;
  for(size_t i=0;i<text.size();++i){h^=(unsigned char)text[i];h*=16777619u;}
  return h?h:0x9e3779b9u;
}

float UnitRoll(unsigned int& s) {
  if(!s)s=0x9e3779b9u;
  s^=s<<13; s^=s>>17; s^=s<<5;
  return (float)(s&0x00FFFFFFu)/16777215.0f;
}

AffixRecord RollAffixes(const ItemDescriptor& item,const RoleProfile& role,
                        const RuleConfig& cfg,const std::vector<ItemTag>& tags,
                        const std::string& key,unsigned int seed,bool crafted) {
  AffixRecord out; out.instanceKey=key; out.baseId=item.baseId; out.tier=QualityTier(item.quality);
  if(!cfg.enabled || item.stackable || tags.empty()) return out;
  std::vector<ProfessionStat> pool=AllowedStats(tags);
  if(pool.empty()) return out;
  float chance=TierAffixChance(out.tier)*cfg.globalChance;
  if(role.slave || role.wealth01<.15f) chance*=cfg.poorNpcMultiplier;
  if(role.primary!=STAT_NONE && std::find(pool.begin(),pool.end(),role.primary)!=pool.end()) chance*=cfg.npcRoleMultiplier;
  if(crafted) chance*=cfg.playerCraftMultiplier;
  if(chance>1) chance=1;
  unsigned int state=seed^Hash32(key)^Hash32(item.baseId);
  if(UnitRoll(state)>chance) return out;
  float lo,hi; TierRange(out.tier,lo,hi);
  int count=1;
  if(cfg.maxAffixes>1 && out.tier>=4 && pool.size()>1 && UnitRoll(state)<.28f) count=2;
  if(count>cfg.maxAffixes) count=cfg.maxAffixes;
  std::vector<ProfessionStat> rem=pool;
  for(int i=0;i<count && !rem.empty();++i){
    size_t idx=(size_t)(UnitRoll(state)*rem.size()); if(idx>=rem.size()) idx=rem.size()-1;
    ProfessionStat st=rem[idx];
    if(role.primary!=STAT_NONE && std::find(rem.begin(),rem.end(),role.primary)!=rem.end() && UnitRoll(state)<.70f){
      st=role.primary; idx=(size_t)(std::find(rem.begin(),rem.end(),st)-rem.begin());
    }
    float p=lo+(hi-lo)*UnitRoll(state); p=(float)((int)(p*10+.5f))/10.0f;
    out.affixes.push_back(Affix(st,p)); rem.erase(rem.begin()+idx);
  }
  return out;
}

float AggregatePercent(const std::vector<AffixRecord>& records, ProfessionStat stat) {
  float total=0;
  for(size_t i=0;i<records.size();++i)
    for(size_t j=0;j<records[i].affixes.size();++j)
      if(records[i].affixes[j].stat==stat) total+=records[i].affixes[j].percent;
  return total;
}

std::string SerializeRecord(const AffixRecord& r) {
  std::ostringstream s; s<<r.instanceKey<<'\t'<<r.baseId<<'\t'<<r.tier<<'\t';
  for(size_t i=0;i<r.affixes.size();++i){if(i)s<<',';s<<(int)r.affixes[i].stat<<':'<<std::fixed<<std::setprecision(1)<<r.affixes[i].percent;}
  return s.str();
}

bool ParseRecord(const std::string& line, AffixRecord& out) {
  std::vector<std::string> f; size_t st=0;
  for(;;){size_t p=line.find('\t',st);if(p==std::string::npos){f.push_back(line.substr(st));break;}f.push_back(line.substr(st,p-st));st=p+1;}
  if(f.size()!=4 || f[0].empty()) return false;
  out=AffixRecord();out.instanceKey=f[0];out.baseId=f[1];out.tier=std::atoi(f[2].c_str());
  if(f[3].empty()) return true;
  st=0;
  while(st<f[3].size()){
    size_t c=f[3].find(',',st); std::string tok=f[3].substr(st,c==std::string::npos?std::string::npos:c-st);
    size_t col=tok.find(':'); if(col==std::string::npos) return false;
    int sn=std::atoi(tok.substr(0,col).c_str()); float p=(float)std::atof(tok.substr(col+1).c_str());
    if(sn<=STAT_NONE || sn>STAT_THIEVERY || p<-100 || p>500) return false;
    out.affixes.push_back(Affix((ProfessionStat)sn,p));
    if(c==std::string::npos) break; st=c+1;
  }
  return true;
}

} // namespace PGP
