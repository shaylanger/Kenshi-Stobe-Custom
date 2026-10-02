#pragma once

#include <map>
#include <set>
#include <string>
#include <vector>

namespace PGP {

enum ProfessionStat {
  STAT_NONE = 0,
  STAT_LABOURING,
  STAT_SCIENCE,
  STAT_ENGINEERING,
  STAT_ROBOTICS,
  STAT_WEAPON_SMITH,
  STAT_ARMOUR_SMITH,
  STAT_CROSSBOW_SMITH,
  STAT_MEDIC,
  STAT_TURRETS,
  STAT_FARMING,
  STAT_COOKING,
  STAT_ATHLETICS,
  STAT_SWIMMING,
  STAT_PERCEPTION,
  STAT_STEALTH,
  STAT_ASSASSINATION,
  STAT_LOCKPICKING,
  STAT_THIEVERY
};

enum ItemTag {
  TAG_NONE = 0,
  TAG_TOOL_FARMING,
  TAG_TOOL_MINING,
  TAG_TOOL_RESEARCH,
  TAG_TOOL_ENGINEERING,
  TAG_TOOL_ROBOTICS,
  TAG_TOOL_MEDIC,
  TAG_TOOL_WEAPON_SMITH,
  TAG_TOOL_ARMOUR_SMITH,
  TAG_TOOL_CROSSBOW_SMITH,
  TAG_TOOL_COOKING,
  TAG_HEAD_FARMING,
  TAG_HEAD_MINING,
  TAG_HEAD_RESEARCH,
  TAG_BODY_RESEARCH,
  TAG_BODY_ENGINEERING,
  TAG_BODY_MEDIC,
  TAG_BODY_SMITH,
  TAG_GLOVES_WORK,
  TAG_BOOTS_WORK,
  TAG_BOOTS_TRAVEL,
  TAG_PACK_ORE,
  TAG_PACK_CROP,
  TAG_PACK_CONSTRUCTION,
  TAG_PACK_MEDICAL,
  TAG_PACK_TRADE,
  TAG_PACK_TECH,
  TAG_TURRET_GEAR,
  TAG_SCOUT_GEAR,
  TAG_STEALTH_GEAR
};

struct Affix {
  ProfessionStat stat;
  float percent;
  Affix() : stat(STAT_NONE), percent(0.0f) {}
  Affix(ProfessionStat s, float p) : stat(s), percent(p) {}
};

struct ItemDescriptor {
  std::string baseId;
  std::string name;
  std::string slot;
  std::string category;
  float quality;
  bool equipped;
  bool stackable;
  bool container;
  ItemDescriptor() : quality(0.0f), equipped(false), stackable(false), container(false) {}
};

struct RoleProfile {
  ProfessionStat primary;
  float wealth01;
  bool slave;
  bool unique;
  RoleProfile() : primary(STAT_NONE), wealth01(0.5f), slave(false), unique(false) {}
};

struct AffixRecord {
  std::string instanceKey;
  std::string baseId;
  int tier;
  std::vector<Affix> affixes;
  AffixRecord() : tier(0) {}
};

struct RuleConfig {
  bool enabled;
  bool autoClassify;
  float globalChance;
  float npcRoleMultiplier;
  float playerCraftMultiplier;
  float poorNpcMultiplier;
  int maxAffixes;
  RuleConfig();
};

std::string Lower(const std::string& value);
std::string Trim(const std::string& value);
std::string StatName(ProfessionStat stat);
ProfessionStat ParseStat(const std::string& value);
std::string TagName(ItemTag tag);
ItemTag ParseTag(const std::string& value);

int QualityTier(float quality);
void TierRange(int tier, float& minPercent, float& maxPercent);
float TierAffixChance(int tier);

std::vector<ItemTag> Classify(const ItemDescriptor& item,
                              const std::map<std::string, std::vector<ItemTag> >& overrides,
                              const std::set<std::string>& exclusions);

std::vector<ProfessionStat> AllowedStats(const std::vector<ItemTag>& tags);
bool IsProfessionStat(ProfessionStat stat);

unsigned int Hash32(const std::string& text);
float UnitRoll(unsigned int& state);

AffixRecord RollAffixes(const ItemDescriptor& item,
                        const RoleProfile& role,
                        const RuleConfig& config,
                        const std::vector<ItemTag>& tags,
                        const std::string& instanceKey,
                        unsigned int seed,
                        bool playerCrafted);

float AggregatePercent(const std::vector<AffixRecord>& records,
                       ProfessionStat stat);

float EffectiveStatValue(float baseValue, float totalPercent, bool unmodified,
                         float hardCap);

float SpecialistPackItemWeightMultiplier(const std::vector<ItemTag>& packTags,
                                         const std::string& itemName,
                                         const std::string& itemBaseId,
                                         bool isTradeItem);

std::string SerializeRecord(const AffixRecord& record);
bool ParseRecord(const std::string& line, AffixRecord& out);

}  // namespace PGP
