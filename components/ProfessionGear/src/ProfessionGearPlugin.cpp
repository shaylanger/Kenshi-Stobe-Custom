
#include "ProfessionGearCore.h"

#include <windows.h>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include <core/Functions.h>
#include <kenshi/Building/CraftingBuilding.h>
#include <kenshi/Character.h>
#include <kenshi/CharStats.h>
#include <kenshi/GameWorld.h>
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <kenshi/PlayerInterface.h>
#include <kenshi/util/StringPair.h>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {

CRITICAL_SECTION g_lock;
PGP::RuleConfig g_cfg;
std::map<std::string, PGP::AffixRecord> g_records;
std::map<unsigned int, std::map<PGP::ProfessionStat, float> > g_bonusCache;
std::map<std::string, std::vector<PGP::ItemTag> > g_overrides;
std::set<std::string> g_exclusions;
std::string g_dir;
std::string g_dbPath;
std::string g_logPath;
DWORD g_lastScan = 0;
bool g_dirty = false;

typedef void (*PlayerUpdateFn)(PlayerInterface*);
typedef float (*GetStatFn)(const CharStats*, StatsEnumerated, bool);
typedef void (*CraftFinishedFn)(CraftingBuilding*, Item*);
typedef void (*TooltipFn)(InventoryItemBase*, Ogre::vector<StringPair>::type&);
typedef float (*InventoryWeightFn)(Inventory*);
typedef void (*InventoryAddRemoveFn)(Inventory*, Item*);
typedef void (*InventoryUpdateFn)(Inventory*, Item*, int);

PlayerUpdateFn g_playerUpdateOrig = 0;
GetStatFn g_getStatOrig = 0;
CraftFinishedFn g_craftOrig = 0;
TooltipFn g_tipBaseOrig = 0;
TooltipFn g_tipArmourOrig = 0;
TooltipFn g_tipContainerOrig = 0;
TooltipFn g_tipCrossbowOrig = 0;
TooltipFn g_tipSwordOrig = 0;
InventoryWeightFn g_inventoryWeightOrig = 0;
InventoryAddRemoveFn g_inventoryAddOrig = 0;
InventoryAddRemoveFn g_inventoryRemoveOrig = 0;
InventoryUpdateFn g_inventoryUpdateOrig = 0;

void Log(const std::string& s) {
  std::ofstream f(g_logPath.c_str(), std::ios::app);
  if (f.is_open()) f << s << "\n";
}

std::string DirName(const std::string& p) {
  size_t x=p.find_last_of("\\/");
  return x==std::string::npos?".":p.substr(0,x);
}

std::string ItemKey(Item* item) {
  if (!item) return "";
  try { return item->getHandle().toString(); } catch (...) { return ""; }
}

std::string BaseId(Item* item) {
  if (!item || !item->data) return "";
  if (!item->data->stringID.empty()) return item->data->stringID;
  std::ostringstream s; s<<"id:"<<item->data->id; return s.str();
}

PGP::ItemDescriptor Describe(Item* item) {
  PGP::ItemDescriptor d;
  if (!item) return d;
  d.baseId=BaseId(item);
  try { d.name=item->getName(); } catch (...) {}
  if (item->data) d.category=item->data->name;
  d.quality=item->quality;
  d.equipped=item->isEquipped;
  d.container=(dynamic_cast<ContainerItem*>(item)!=0);
  d.stackable=item->quantity>1;
  d.slot=item->inventorySection;
  return d;
}

PGP::ProfessionStat MapStat(StatsEnumerated st) {
  switch(st) {
    case STAT_LABOURING:return PGP::STAT_LABOURING;
    case STAT_SCIENCE:return PGP::STAT_SCIENCE;
    case STAT_ENGINEERING:return PGP::STAT_ENGINEERING;
    case STAT_ROBOTICS:return PGP::STAT_ROBOTICS;
    case STAT_SMITHING_WEAPON:return PGP::STAT_WEAPON_SMITH;
    case STAT_SMITHING_ARMOUR:return PGP::STAT_ARMOUR_SMITH;
    case STAT_SMITHING_BOW:return PGP::STAT_CROSSBOW_SMITH;
    case STAT_MEDIC:return PGP::STAT_MEDIC;
    case STAT_TURRETS:return PGP::STAT_TURRETS;
    case STAT_FARMING:return PGP::STAT_FARMING;
    case STAT_COOKING:return PGP::STAT_COOKING;
    case STAT_ATHLETICS:return PGP::STAT_ATHLETICS;
    case STAT_SWIMMING:return PGP::STAT_SWIMMING;
    case STAT_PERCEPTION:return PGP::STAT_PERCEPTION;
    case STAT_STEALTH:return PGP::STAT_STEALTH;
    case STAT_ASSASSINATION:return PGP::STAT_ASSASSINATION;
    case STAT_LOCKPICKING:return PGP::STAT_LOCKPICKING;
    case STAT_THIEVING:return PGP::STAT_THIEVERY;
    default:return PGP::STAT_NONE;
  }
}

static bool HasTag(const std::vector<PGP::ItemTag>& tags, PGP::ItemTag tag) {
  return std::find(tags.begin(), tags.end(), tag) != tags.end();
}

std::vector<PGP::ItemTag> TagsFor(const PGP::ItemDescriptor& item) {
  const std::string id=PGP::Lower(item.baseId);
  if(g_exclusions.count(id)) return std::vector<PGP::ItemTag>();
  std::map<std::string,std::vector<PGP::ItemTag> >::const_iterator it=g_overrides.find(id);
  if(it!=g_overrides.end()) return it->second;
  if(!g_cfg.autoClassify) return std::vector<PGP::ItemTag>();
  return PGP::Classify(item,g_overrides,g_exclusions);
}

PGP::RoleProfile RoleFor(Character* c) {
  PGP::RoleProfile r;
  if (!c) return r;
  try { r.slave=(c->isSlave()!=NOT_SLAVE); } catch (...) {}
  try {
    CharStats* s=c->getStats();
    if (!s) return r;
    struct Pair { PGP::ProfessionStat p; StatsEnumerated k; };
    Pair a[]={
      {PGP::STAT_LABOURING,STAT_LABOURING},{PGP::STAT_SCIENCE,STAT_SCIENCE},
      {PGP::STAT_ENGINEERING,STAT_ENGINEERING},{PGP::STAT_ROBOTICS,STAT_ROBOTICS},
      {PGP::STAT_WEAPON_SMITH,STAT_SMITHING_WEAPON},{PGP::STAT_ARMOUR_SMITH,STAT_SMITHING_ARMOUR},
      {PGP::STAT_CROSSBOW_SMITH,STAT_SMITHING_BOW},{PGP::STAT_MEDIC,STAT_MEDIC},
      {PGP::STAT_TURRETS,STAT_TURRETS},{PGP::STAT_FARMING,STAT_FARMING},
      {PGP::STAT_COOKING,STAT_COOKING}
    };
    float best=-1;
    for(size_t i=0;i<sizeof(a)/sizeof(a[0]);++i){
      float v=g_getStatOrig?g_getStatOrig(s,a[i].k,true):s->getStat(a[i].k,true);
      if(v>best){best=v;r.primary=a[i].p;}
    }
    r.wealth01=best<=0?0.15f:(best>=80?1.0f:0.2f+best/100.0f*.8f);
    r.unique=c->isUnique();
  } catch (...) {}
  return r;
}

void SaveDb() {
  EnterCriticalSection(&g_lock);
  if (!g_dirty) { LeaveCriticalSection(&g_lock); return; }
  std::string tmp=g_dbPath+".tmp";
  std::ofstream f(tmp.c_str(),std::ios::trunc);
  if (f.is_open()) {
    f<<"# Profession Gear Progression v1\n";
    for(std::map<std::string,PGP::AffixRecord>::const_iterator i=g_records.begin();i!=g_records.end();++i)
      f<<PGP::SerializeRecord(i->second)<<"\n";
    f.close();
    DeleteFileA(g_dbPath.c_str());
    MoveFileA(tmp.c_str(),g_dbPath.c_str());
    g_dirty=false;
  }
  LeaveCriticalSection(&g_lock);
}

void LoadDb() {
  std::ifstream f(g_dbPath.c_str());
  if(!f.is_open()) return;
  std::string line;
  while(std::getline(f,line)){
    if(line.empty()||line[0]=='#') continue;
    PGP::AffixRecord r;
    if(PGP::ParseRecord(line,r)) g_records[r.instanceKey]=r;
  }
  std::ostringstream ss; ss << "loaded affixes=" << (unsigned long)g_records.size(); Log(ss.str());
}

PGP::AffixRecord* EnsureRecord(Item* item, Character* owner, bool crafted) {
  if(!item) return 0;
  std::string key=ItemKey(item);
  if(key.empty()) return 0;
  EnterCriticalSection(&g_lock);
  std::map<std::string,PGP::AffixRecord>::iterator existing=g_records.find(key);
  if(existing!=g_records.end()){ PGP::AffixRecord* p=&existing->second; LeaveCriticalSection(&g_lock); return p; }
  LeaveCriticalSection(&g_lock);

  PGP::ItemDescriptor d=Describe(item);
  std::vector<PGP::ItemTag> tags=TagsFor(d);
  if(tags.empty()) return 0;
  PGP::RoleProfile role=RoleFor(owner);
  unsigned int seed=PGP::Hash32(key+"|"+d.baseId);
  PGP::AffixRecord r=PGP::RollAffixes(d,role,g_cfg,tags,key,seed,crafted);

  EnterCriticalSection(&g_lock);
  g_records[key]=r;
  g_dirty=true;
  PGP::AffixRecord* p=&g_records[key];
  LeaveCriticalSection(&g_lock);
  return p;
}

void RebuildCharacterBonusCache(Character* c) {
  if(!c) return;
  Inventory* inv=0;
  try { inv=c->getInventory(); } catch (...) { return; }
  if(!inv) return;
  std::map<PGP::ProfessionStat,float> totals;
  const lektor<Item*>& items=inv->getAllItems();
  EnterCriticalSection(&g_lock);
  for(unsigned int i=0;i<items.size();++i){
    Item* item=items[i];
    if(!item || !item->isEquipped) continue;
    std::map<std::string,PGP::AffixRecord>::const_iterator it=g_records.find(ItemKey(item));
    if(it==g_records.end()) continue;
    for(size_t j=0;j<it->second.affixes.size();++j)
      totals[it->second.affixes[j].stat]+=it->second.affixes[j].percent;
  }
  unsigned int serial=0;
  try { serial=c->getHandle().serial; } catch (...) {}
  if(serial) g_bonusCache[serial]=totals;
  LeaveCriticalSection(&g_lock);
}

void ProcessCharacter(Character* c) {
  if(!g_cfg.enabled || !c) return;
  Inventory* inv=0;
  try { inv=c->getInventory(); } catch (...) { return; }
  if(!inv) return;
  const lektor<Item*>& items=inv->getAllItems();
  for(unsigned int i=0;i<items.size();++i) if(items[i]) EnsureRecord(items[i],c,false);
  RebuildCharacterBonusCache(c);
}

float EquippedBonus(Character* c, PGP::ProfessionStat stat) {
  if(!g_cfg.enabled || !c || stat==PGP::STAT_NONE) return 0;
  unsigned int serial=0;
  try { serial=c->getHandle().serial; } catch (...) { return 0; }
  if(!serial) return 0;
  EnterCriticalSection(&g_lock);
  std::map<unsigned int,std::map<PGP::ProfessionStat,float> >::const_iterator ci=g_bonusCache.find(serial);
  if(ci!=g_bonusCache.end()){
    std::map<PGP::ProfessionStat,float>::const_iterator bi=ci->second.find(stat);
    float value=(bi==ci->second.end())?0.0f:bi->second;
    LeaveCriticalSection(&g_lock);
    return value;
  }
  LeaveCriticalSection(&g_lock);
  RebuildCharacterBonusCache(c);
  EnterCriticalSection(&g_lock);
  ci=g_bonusCache.find(serial);
  float value=0.0f;
  if(ci!=g_bonusCache.end()){
    std::map<PGP::ProfessionStat,float>::const_iterator bi=ci->second.find(stat);
    if(bi!=ci->second.end()) value=bi->second;
  }
  LeaveCriticalSection(&g_lock);
  return value;
}

void AppendTip(InventoryItemBase* base,Ogre::vector<StringPair>::type& lines) {
  if(!g_cfg.enabled) return;
  Item* item=dynamic_cast<Item*>(base);
  if(!item) return;
  std::string key=ItemKey(item);
  EnterCriticalSection(&g_lock);
  std::map<std::string,PGP::AffixRecord>::const_iterator it=g_records.find(key);
  if(it!=g_records.end() && !it->second.affixes.empty()){
    lines.push_back(StringPair("Profession Gear",""));
    for(size_t j=0;j<it->second.affixes.size();++j){
      std::ostringstream s; s<<"+"<<it->second.affixes[j].percent<<"%";
      lines.push_back(StringPair(PGP::StatName(it->second.affixes[j].stat),s.str()));
    }
  }
  LeaveCriticalSection(&g_lock);
}

void HookPlayerUpdate(PlayerInterface* p) {
  if(g_playerUpdateOrig) g_playerUpdateOrig(p);
  DWORD now=GetTickCount();
  if(now-g_lastScan<1000) return;
  g_lastScan=now;
  GameWorld* world=0;
  HMODULE kl=GetModuleHandleA("KenshiLib.dll");
  if(kl){
    GameWorld** pp=(GameWorld**)GetProcAddress(kl,"?ou@@3PEAVGameWorld@@EA");
    if(pp) world=*pp;
  }
  if(world){
    try {
      const ogre_unordered_set<Character*>::type& chars=world->getCharacterUpdateList();
      for(ogre_unordered_set<Character*>::type::const_iterator i=chars.begin();i!=chars.end();++i) ProcessCharacter(*i);
    } catch (...) {}
  }
  SaveDb();
}

float HookGetStat(const CharStats* s,StatsEnumerated st,bool unmodified) {
  float base=g_getStatOrig?g_getStatOrig(s,st,unmodified):0;
  if(unmodified || !s || !s->me) return base;
  PGP::ProfessionStat p=MapStat(st);
  if(p==PGP::STAT_NONE) return base;
  float pct=EquippedBonus(s->me,p);
  return PGP::EffectiveStatValue(base,pct,false,150.0f);
}

float HookInventoryWeight(Inventory* inv) {
  float base = g_inventoryWeightOrig ? g_inventoryWeightOrig(inv) : 0.0f;
  if (!g_cfg.enabled || !inv || base <= 0.0f) return base;
  RootObject* owner = 0;
  try { owner = inv->getOwner(); } catch (...) { return base; }
  ContainerItem* pack = dynamic_cast<ContainerItem*>(owner);
  if (!pack) return base;
  PGP::ItemDescriptor pd = Describe(pack);
  std::vector<PGP::ItemTag> tags = TagsFor(pd);
  if (!HasTag(tags,PGP::TAG_PACK_ORE) && !HasTag(tags,PGP::TAG_PACK_CROP) &&
      !HasTag(tags,PGP::TAG_PACK_CONSTRUCTION) && !HasTag(tags,PGP::TAG_PACK_MEDICAL) &&
      !HasTag(tags,PGP::TAG_PACK_TRADE) && !HasTag(tags,PGP::TAG_PACK_TECH)) return base;
  float raw=0.0f, adjusted=0.0f;
  try {
    const lektor<Item*>& items=inv->getAllItems();
    for(unsigned int i=0;i<items.size();++i){
      if(!items[i]) continue;
      float w=items[i]->getItemWeight();
      raw+=w;
      adjusted+=w*PGP::SpecialistPackItemWeightMultiplier(tags,items[i]->getName(),BaseId(items[i]),items[i]->isTradeItem);
    }
  } catch (...) { return base; }
  if(raw<=0.0001f) return base;
  return base*(adjusted/raw);
}

void RefreshInventoryOwner(Inventory* inv) {
  if(!g_cfg.enabled || !inv) return;
  Character* c=0;
  try { c=inv->getCallbackCharacter(); } catch (...) {}
  if(c) ProcessCharacter(c);
}

void HookInventoryAdd(Inventory* inv,Item* item) {
  if(g_inventoryAddOrig) g_inventoryAddOrig(inv,item);
  RefreshInventoryOwner(inv);
}

void HookInventoryRemove(Inventory* inv,Item* item) {
  if(g_inventoryRemoveOrig) g_inventoryRemoveOrig(inv,item);
  RefreshInventoryOwner(inv);
}

void HookInventoryUpdate(Inventory* inv,Item* item,int amount) {
  if(g_inventoryUpdateOrig) g_inventoryUpdateOrig(inv,item,amount);
  RefreshInventoryOwner(inv);
}

void HookCraft(CraftingBuilding* b,Item* item) {
  Character* crafter=0;
  try { crafter=b?b->whosCrafting.getCharacter():0; } catch (...) {}
  if(item) EnsureRecord(item,crafter,true);
  if(g_craftOrig) g_craftOrig(b,item);
  if(crafter) RebuildCharacterBonusCache(crafter);
  SaveDb();
}

void TipBase(InventoryItemBase* i,Ogre::vector<StringPair>::type& l){if(g_tipBaseOrig)g_tipBaseOrig(i,l);AppendTip(i,l);}
void TipArmour(InventoryItemBase* i,Ogre::vector<StringPair>::type& l){if(g_tipArmourOrig)g_tipArmourOrig(i,l);AppendTip(i,l);}
void TipContainer(InventoryItemBase* i,Ogre::vector<StringPair>::type& l){if(g_tipContainerOrig)g_tipContainerOrig(i,l);AppendTip(i,l);}
void TipCrossbow(InventoryItemBase* i,Ogre::vector<StringPair>::type& l){if(g_tipCrossbowOrig)g_tipCrossbowOrig(i,l);AppendTip(i,l);}
void TipSword(InventoryItemBase* i,Ogre::vector<StringPair>::type& l){if(g_tipSwordOrig)g_tipSwordOrig(i,l);AppendTip(i,l);}

bool HookSymbol(HMODULE lib,const char* sym,void* detour,void** orig) {
  void* thunk=(void*)GetProcAddress(lib,sym);
  if(!thunk){Log(std::string("missing symbol ")+sym);return false;}
  intptr_t real=KenshiLib::GetRealAddress(thunk);
  if(!real){Log(std::string("no real address ")+sym);return false;}
  bool ok=KenshiLib::AddHook((void*)real,detour,orig)==KenshiLib::SUCCESS;
  Log(std::string(ok?"hooked ":"hook failed ")+sym);
  return ok;
}

void InstallHooks() {
  HMODULE lib=GetModuleHandleA("KenshiLib.dll");
  if(!lib){Log("KenshiLib.dll not loaded");return;}
  HookSymbol(lib,"?update@PlayerInterface@@QEAAXXZ",(void*)HookPlayerUpdate,(void**)&g_playerUpdateOrig);
  HookSymbol(lib,"?getStat@CharStats@@QEBAMW4StatsEnumerated@@_N@Z",(void*)HookGetStat,(void**)&g_getStatOrig);
  HookSymbol(lib,"?addFinishedCraftItem@CraftingBuilding@@QEAAXPEAVItem@@@Z",(void*)HookCraft,(void**)&g_craftOrig);
  HookSymbol(lib,"?getTotalWeight@Inventory@@QEAAMXZ",(void*)HookInventoryWeight,(void**)&g_inventoryWeightOrig);
  HookSymbol(lib,"?_sectionAddItemCallback@Inventory@@UEAAXPEAVItem@@@Z",(void*)HookInventoryAdd,(void**)&g_inventoryAddOrig);
  HookSymbol(lib,"?_sectionRemoveItemCallback@Inventory@@UEAAXPEAVItem@@@Z",(void*)HookInventoryRemove,(void**)&g_inventoryRemoveOrig);
  HookSymbol(lib,"?_sectionUpdateItemCallback@Inventory@@UEAAXPEAVItem@@H@Z",(void*)HookInventoryUpdate,(void**)&g_inventoryUpdateOrig);
  HookSymbol(lib,"?getTooltipData1@InventoryItemBase@@UEAAXAEAV?$vector@VStringPair@@V?$STLAllocator@VStringPair@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z",(void*)TipBase,(void**)&g_tipBaseOrig);
  HookSymbol(lib,"?getTooltipData1@Armour@@UEAAXAEAV?$vector@VStringPair@@V?$STLAllocator@VStringPair@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z",(void*)TipArmour,(void**)&g_tipArmourOrig);
  HookSymbol(lib,"?getTooltipData1@ContainerItem@@UEAAXAEAV?$vector@VStringPair@@V?$STLAllocator@VStringPair@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z",(void*)TipContainer,(void**)&g_tipContainerOrig);
  HookSymbol(lib,"?getTooltipData1@Crossbow@@UEAAXAEAV?$vector@VStringPair@@V?$STLAllocator@VStringPair@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z",(void*)TipCrossbow,(void**)&g_tipCrossbowOrig);
  HookSymbol(lib,"?getTooltipData1@Sword@@UEAAXAEAV?$vector@VStringPair@@V?$STLAllocator@VStringPair@@V?$CategorisedAllocPolicy@$0A@@Ogre@@@Ogre@@@std@@@Z",(void*)TipSword,(void**)&g_tipSwordOrig);
}

void LoadConfig() {
  std::ifstream f((g_dir+"\\ProfessionGear.ini").c_str());
  if(!f.is_open()) return;
  std::string line;
  while(std::getline(f,line)){
    line=PGP::Trim(line);
    if(line.empty()||line[0]=='#'||line[0]==';'||line[0]=='[') continue;
    size_t eq=line.find('='); if(eq==std::string::npos) continue;
    std::string k=PGP::Lower(PGP::Trim(line.substr(0,eq)));
    std::string v=PGP::Trim(line.substr(eq+1));
    if(k=="enabled") g_cfg.enabled=(v!="0"&&PGP::Lower(v)!="false");
    else if(k=="autoclassify") g_cfg.autoClassify=(v!="0"&&PGP::Lower(v)!="false");
    else if(k=="globalchance") g_cfg.globalChance=(float)atof(v.c_str());
    else if(k=="npcrolemultiplier") g_cfg.npcRoleMultiplier=(float)atof(v.c_str());
    else if(k=="playercraftmultiplier") g_cfg.playerCraftMultiplier=(float)atof(v.c_str());
    else if(k=="poornpcmultiplier") g_cfg.poorNpcMultiplier=(float)atof(v.c_str());
    else if(k=="maxaffixes") g_cfg.maxAffixes=atoi(v.c_str());
  }
}

void LoadRules() {
  std::ifstream f((g_dir+"\\ProfessionGear.rules").c_str());
  if(!f.is_open()) return;
  std::string line;
  while(std::getline(f,line)){
    line=PGP::Trim(line);
    if(line.empty()||line[0]=='#'||line[0]==';') continue;
    size_t a=line.find('|');
    if(a==std::string::npos) continue;
    std::string op=PGP::Lower(PGP::Trim(line.substr(0,a)));
    size_t b=line.find('|',a+1);
    std::string id=PGP::Lower(PGP::Trim(line.substr(a+1,b==std::string::npos?std::string::npos:b-a-1)));
    if(id.empty()) continue;
    if(op=="exclude") { g_exclusions.insert(id); continue; }
    if(op!="tag" || b==std::string::npos) continue;
    std::string rest=line.substr(b+1);
    std::vector<PGP::ItemTag> tags;
    size_t p=0;
    while(p<=rest.size()){
      size_t c=rest.find(',',p);
      std::string tok=rest.substr(p,c==std::string::npos?std::string::npos:c-p);
      PGP::ItemTag t=PGP::ParseTag(tok);
      if(t!=PGP::TAG_NONE) tags.push_back(t);
      if(c==std::string::npos) break;
      p=c+1;
    }
    if(!tags.empty()) g_overrides[id]=tags;
  }
}

} // anonymous

extern "C" __declspec(dllexport) void startPlugin() {
  InitializeCriticalSection(&g_lock);
  char path[MAX_PATH]={0};
  GetModuleFileNameA((HMODULE)&__ImageBase,path,MAX_PATH);
  g_dir=DirName(path);
  g_dbPath=g_dir+"\\profession_gear_affixes.tsv";
  g_logPath=g_dir+"\\ProfessionGear.log";
  DeleteFileA(g_logPath.c_str());
  Log("Profession Gear Progression 0.1.0 starting");
  LoadConfig();
  LoadRules();
  LoadDb();
  InstallHooks();
}

BOOL APIENTRY DllMain(HMODULE,DWORD,LPVOID){return TRUE;}
