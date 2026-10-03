#!/usr/bin/env python3
"""ProfessionGear: test commands through the Kenshi Automation Harness.

Registers (only if AutomationHarness.dll is loaded) for the balance runner and
live tests that need a known affix instead of a random roll:
- pg_info <npc> <item>                         the item's record (key, tier, affixes)
- pg_force_affix <npc> <item> <stat> <pct> [<stat> <pct>...] [tier n]   exact affixes
- pg_clear <npc> [item]                        remove affixes (item, or everything worn)
- pg_roll <npc> <item>                         a fresh roll under a new persistent id
- pg_bonus <npc> <stat>                        summed equipped bonus for a stat
<npc> = exact character name (player squad first); <item> = name or base id in
that character's inventory (worn items too).

Usage: patch_professiongear_harness_commands.py <ProfessionGear repo> <harness repo>  (idempotent)
"""
import shutil
import sys
from pathlib import Path

root, harness = Path(sys.argv[1]), Path(sys.argv[2])
f = root / 'src' / 'ProfessionGearPlugin.cpp'
s = f.read_text(encoding='utf-8')
if 'KahTick' in s:
    print('already patched')
    sys.exit(0)


def sub(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n}x: {old[:70]!r}'
    s = s.replace(old, new)


sub('#include <kenshi/util/StringPair.h>\n',
    '#include <kenshi/util/StringPair.h>\n#include "KenshiAutomationHarness.h" // test commands, if the harness is installed\n')

sub('void HookPlayerUpdate(PlayerInterface* p) {\n  if(g_playerUpdateOrig) g_playerUpdateOrig(p);\n',
    r'''// ---- Kenshi Automation Harness commands (TEST ONLY) ----------------------
KAH_Api g_kah;
bool g_kahConnected = false;
DWORD g_kahLastTry = 0;

GameWorld* KahWorld() {
  HMODULE kl=GetModuleHandleA("KenshiLib.dll");
  GameWorld** pp=kl ? (GameWorld**)GetProcAddress(kl,"?ou@@3PEAVGameWorld@@EA") : 0;
  return pp ? *pp : 0;
}

// Exact (case-insensitive) name; player characters first.
Character* KahFindCharacter(const std::string& name) {
  GameWorld* world=KahWorld();
  if(!world) return 0;
  const std::string wanted=PGP::Lower(name);
  Character* other=0;
  try {
    if(world->player)
      for(uint32_t i=0;i<world->player->playerCharacters.size();++i){
        Character* c=world->player->playerCharacters[i];
        if(c && PGP::Lower(c->getName())==wanted) return c;
      }
    const ogre_unordered_set<Character*>::type& chars=world->getCharacterUpdateList();
    for(ogre_unordered_set<Character*>::type::const_iterator i=chars.begin();i!=chars.end();++i)
      if(*i && PGP::Lower((*i)->getName())==wanted){ other=*i; break; }
  } catch (...) {}
  return other;
}

Item* KahFindItem(Character* c, const std::string& name) {
  Inventory* inv=0;
  try { inv=c->getInventory(); } catch (...) { return 0; }
  if(!inv) return 0;
  std::vector<Item*> items;
  CollectCharacterInventoryItems(inv,items);
  const std::string wanted=PGP::Lower(name);
  Item* partial=0;
  for(size_t i=0;i<items.size();++i){
    Item* item=items[i];
    if(!item) continue;
    std::string n, base;
    try { n=PGP::Lower(item->getName()); base=PGP::Lower(BaseId(item)); } catch (...) { continue; }
    if(n==wanted || base==wanted) return item;
    if(!partial && n.find(wanted)!=std::string::npos) partial=item;
  }
  return partial;
}

std::string KahRecordText(Item* item) {
  const std::string key=PersistentItemId(item,false);
  std::ostringstream ss;
  ss<<item->getName()<<" key="<<(key.empty()?"-":key)<<" equipped="<<(item->isEquipped?1:0);
  EnterCriticalSection(&g_lock);
  std::map<std::string,PGP::AffixRecord>::const_iterator it=key.empty()?g_records.end():g_records.find(key);
  if(it==g_records.end()) ss<<" record=none";
  else {
    ss<<" tier="<<it->second.tier<<" affixes=";
    if(it->second.affixes.empty()) ss<<"none";
    for(size_t i=0;i<it->second.affixes.size();++i)
      ss<<(i?",":"")<<PGP::StatName(it->second.affixes[i].stat)<<":"<<it->second.affixes[i].percent;
  }
  LeaveCriticalSection(&g_lock);
  return ss.str();
}

// Resolves argv[1] (npc) and argv[2] (item); writes an error to the reply.
bool KahNpcItem(int argc,const char* const* argv,KAH_Reply* r,Character*& c,Item*& item,bool needItem) {
  if(argc<2 || (needItem && argc<3)){ r->append(r,"usage: see help"); return false; }
  c=KahFindCharacter(argv[1]);
  if(!c){ r->append(r,(std::string("no character named: ")+argv[1]).c_str()); return false; }
  item=0;
  if(argc>=3 && needItem){
    item=KahFindItem(c,argv[2]);
    if(!item){ r->append(r,(c->getName()+" has no item matching: "+argv[2]).c_str()); return false; }
  }
  return true;
}

int KahInfo(const char*,int argc,const char* const* argv,KAH_Reply* r,void*) {
  Character* c; Item* item;
  if(!KahNpcItem(argc,argv,r,c,item,true)) return KAH_ERROR;
  if(!EnsureRecord(item,c,false)){ r->append(r,(KahRecordText(item)+" (not eligible for affixes)").c_str()); return KAH_OK; }
  r->append(r,KahRecordText(item).c_str());
  return KAH_OK;
}

int KahForce(const char*,int argc,const char* const* argv,KAH_Reply* r,void*) {
  Character* c; Item* item;
  if(argc<5){ r->append(r,"usage: pg_force_affix <npc> <item> <stat> <percent> [<stat> <percent>...] [tier n]"); return KAH_ERROR; }
  if(!KahNpcItem(argc,argv,r,c,item,true)) return KAH_ERROR;
  PGP::AffixRecord rec;
  int tier=-1;
  for(int i=3;i+1<argc;i+=2){
    if(PGP::Lower(argv[i])=="tier"){ tier=atoi(argv[i+1]); continue; }
    PGP::ProfessionStat st=PGP::ParseStat(argv[i]);
    if(st==PGP::STAT_NONE){ r->append(r,(std::string("unknown stat: ")+argv[i]).c_str()); return KAH_ERROR; }
    rec.affixes.push_back(PGP::Affix(st,(float)atof(argv[i+1])));
  }
  const std::string key=PersistentItemId(item,true);
  if(key.empty()){ r->append(r,"item has no persistent id"); return KAH_ERROR; }
  EnterCriticalSection(&g_lock);
  std::map<std::string,PGP::AffixRecord>::iterator it=g_records.find(key);
  rec.instanceKey=key;
  rec.baseId=BaseId(item);
  rec.tier=tier>=0?tier:(it!=g_records.end()?it->second.tier:0);
  g_records[key]=rec;
  g_dirty=true;
  LeaveCriticalSection(&g_lock);
  RebuildCharacterBonusCache(c);
  Log("harness: forced "+KahRecordText(item)+" on "+c->getName());
  r->append(r,("forced: "+KahRecordText(item)).c_str());
  return KAH_OK;
}

int KahClear(const char*,int argc,const char* const* argv,KAH_Reply* r,void*) {
  Character* c; Item* item;
  if(!KahNpcItem(argc,argv,r,c,item,argc>=3)) return KAH_ERROR;
  std::vector<Item*> targets;
  if(item) targets.push_back(item);
  else {
    Inventory* inv=c->getInventory();
    std::vector<Item*> items;
    if(inv) CollectCharacterInventoryItems(inv,items);
    for(size_t i=0;i<items.size();++i) if(items[i] && items[i]->isEquipped) targets.push_back(items[i]);
  }
  int cleared=0;
  for(size_t i=0;i<targets.size();++i){
    const std::string key=PersistentItemId(targets[i],false);
    if(key.empty()) continue;
    EnterCriticalSection(&g_lock);
    std::map<std::string,PGP::AffixRecord>::iterator it=g_records.find(key);
    if(it!=g_records.end() && !it->second.affixes.empty()){ it->second.affixes.clear(); ++cleared; g_dirty=true; }
    LeaveCriticalSection(&g_lock);
  }
  RebuildCharacterBonusCache(c);
  std::ostringstream ss;
  ss<<c->getName()<<": cleared affixes on "<<cleared<<" of "<<targets.size()<<" item(s)";
  Log("harness: "+ss.str());
  r->append(r,ss.str().c_str());
  return KAH_OK;
}

int KahRoll(const char*,int argc,const char* const* argv,KAH_Reply* r,void*) {
  Character* c; Item* item;
  if(!KahNpcItem(argc,argv,r,c,item,true)) return KAH_ERROR;
  const std::string key=GeneratePersistentItemId(item);
  BindPersistentItemId(item,key);
  if(!EnsureRecord(item,c,false)){ r->append(r,(KahRecordText(item)+" (not eligible for affixes)").c_str()); return KAH_ERROR; }
  RebuildCharacterBonusCache(c);
  Log("harness: rerolled "+KahRecordText(item));
  r->append(r,("rolled: "+KahRecordText(item)).c_str());
  return KAH_OK;
}

int KahBonus(const char*,int argc,const char* const* argv,KAH_Reply* r,void*) {
  if(argc<3){ r->append(r,"usage: pg_bonus <npc> <stat>"); return KAH_ERROR; }
  Character* c=KahFindCharacter(argv[1]);
  if(!c){ r->append(r,(std::string("no character named: ")+argv[1]).c_str()); return KAH_ERROR; }
  PGP::ProfessionStat st=PGP::ParseStat(argv[2]);
  if(st==PGP::STAT_NONE){ r->append(r,(std::string("unknown stat: ")+argv[2]).c_str()); return KAH_ERROR; }
  RebuildCharacterBonusCache(c);
  std::ostringstream ss;
  ss<<c->getName()<<" "<<PGP::StatName(st)<<" equipped_bonus="<<EquippedBonus(c,st)<<"%";
  r->append(r,ss.str().c_str());
  return KAH_OK;
}

void KahTick() {
  if(g_kahConnected) return;
  DWORD now=GetTickCount();
  if(now-g_kahLastTry<1000) return;
  g_kahLastTry=now;
  if(!KAH_Connect(&g_kah)) return;
  g_kahConnected=true;
  int n=g_kah.registerCommand("pg_info","pg_info <npc> <item>",KahInfo,0)
       +g_kah.registerCommand("pg_force_affix","pg_force_affix <npc> <item> <stat> <pct> [<stat> <pct>...] [tier n]",KahForce,0)
       +g_kah.registerCommand("pg_clear","pg_clear <npc> [item]",KahClear,0)
       +g_kah.registerCommand("pg_roll","pg_roll <npc> <item>",KahRoll,0)
       +g_kah.registerCommand("pg_bonus","pg_bonus <npc> <stat>",KahBonus,0);
  g_kah.log("ProfessionGear: test commands registered");
  std::ostringstream ss; ss<<"harness: connected, "<<n<<" commands (pg_info/pg_force_affix/pg_clear/pg_roll/pg_bonus)";
  Log(ss.str());
}

void HookPlayerUpdate(PlayerInterface* p) {
  if(g_playerUpdateOrig) g_playerUpdateOrig(p);
  KahTick();
''')

f.write_text(s, encoding='utf-8')
shutil.copy2(harness / 'include' / 'KenshiAutomationHarness.h', root / 'src' / 'KenshiAutomationHarness.h')
print('patched ProfessionGear: harness commands (pg_info/pg_force_affix/pg_clear/pg_roll/pg_bonus)')
