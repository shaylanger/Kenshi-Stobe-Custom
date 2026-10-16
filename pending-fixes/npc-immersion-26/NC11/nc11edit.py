import sys,io
root=sys.argv[1]
def edit(path,old,new,count=1):
    if path.startswith('both:'):
        for d,t in (('src',''),('legacy-v1','.v1')):
            edit(d+'/'+path[5:],old,new.replace('@V@',t),count)
        return
    new=new.replace('@V@','')
    p=root+'/'+path
    s=io.open(p,'r',encoding='utf-8',newline='').read()
    crlf='\r\n' in s
    if crlf:
        old=old.replace('\n','\r\n'); new=new.replace('\n','\r\n')
    assert s.count(old)==count,(path,old[:60],s.count(old))
    s=s.replace(old,new)
    io.open(p,'w',encoding='utf-8',newline='').write(s)

# ---- 1. Mine exact_output_unavailable diag
edit('both:ActivityPolicySupport.cpp','''unsigned Count(InventorySection* section) {''','''// NC11 diagnostic only: names the first ExactSection clause that fails (same order as ExactSection),
// with the compared ids/values. Rate limited per building (about 5 s). Never changes the outcome.
void DiagExact(Building* b,const std::string& item,const char* entry) {
 try {
  static std::map<unsigned,long> last;
  const unsigned serial=b ? b->getHandle().serial:0;
  const long now=(long)std::clock();
  std::map<unsigned,long>::iterator it=last.find(serial);
  if(it!=last.end() && now>=it->second && now-it->second<=5L*CLOCKS_PER_SEC) return;
  last[serial]=now; if(last.size()>512) last.clear();
  std::ostringstream o; std::string clause="unknown";
  o<<"ACTIVITY_MINE_EXACT_DIAG node="<<serial<<" entry="<<entry<<" item="<<item;
  if(!b) clause="building_null";
  else {
   o<<" bsid="<<(b->getGameData()?b->getGameData()->stringID:std::string("?"))<<" special="<<static_cast<int>(b->_NV_getSpecialFunction())
    <<" destroyed="<<(b->_NV_isDestroyed()?1:0);
   ProductionBuilding* pb=b->_NV_getProductionBuilding();
   StorageBuilding::ConsumptionItem* product=pb ? pb->getProductionItem():NULL;
   Inventory* inventory=b->getInventory();
   o<<" production="<<(pb?1:0)<<" product="<<(product?1:0)<<" productItem="<<((product&&product->item)?product->item->stringID:std::string("null"))
    <<" productSection="<<((product&&product->inventorySection)?1:0)<<" inventory="<<(inventory?1:0);
   if(static_cast<int>(b->_NV_getSpecialFunction())!=27) clause="special_function_not_27";
   else if(b->_NV_isDestroyed()) clause="destroyed";
   else if(!pb) clause="no_production_building";
   else if(!product) clause="no_production_item";
   else if(!product->item) clause="product_item_null";
   else if(product->item->stringID.empty()) clause="product_item_id_empty";
   else if(product->item->stringID!=item) clause="product_item_id_mismatch";
   else if(!product->inventorySection) clause="product_section_null";
   else if(!inventory) clause="building_inventory_null";
   else if(product->inventorySection->getInventory()!=inventory) clause="section_inventory_mismatch";
   else {
    const lektor<Item*>& all=inventory->getAllItems();
    o<<" storedItems="<<all.size();
    clause="all_items_ok_unexpected";
    for(unsigned i=0;i<all.size();++i) {
     const bool nul=!all.stuff[i], nodata=!nul && !all.stuff[i]->data;
     const std::string sid=(nul||nodata)?std::string("?"):all.stuff[i]->data->stringID;
     const bool in=(nul||nodata)?false:product->inventorySection->hasItem(all.stuff[i]);
     if(nul||nodata||sid!=item||!in) {
      o<<" badIdx="<<i<<" badItem="<<sid<<" nullItem="<<(nul?1:0)<<" inOutputSection="<<(in?1:0);
      clause=(nul||nodata)?"stored_item_null_or_nodata":(sid!=item?"stored_item_foreign_id":"stored_item_not_in_output_section");
      break;
     }
    }
   }
  }
  o<<" clause="<<clause;
  ::Log(o.str());
 } catch(...) {}
}
unsigned Count(InventorySection* section) {''')
edit('both:ActivityPolicySupport.cpp','''  if(!product || !product->item || product->item->stringID.empty() ||
     !ExactSection(b,product->item->stringID)) {reason="exact_output_unavailable";return false;}''','''  if(!product || !product->item || product->item->stringID.empty() ||
     !ExactSection(b,product->item->stringID)) {
   DiagExact(b,(product && product->item)?product->item->stringID:std::string(),"MineSourcePermitted@V@");
   reason="exact_output_unavailable";return false;}''')

# ---- 3. requester_now_hostile diag
edit('both:ActivityRuntimeBindings.cpp','''#include <windows.h>
''','''#include <windows.h>
#include <kenshi/Faction.h>
#include <kenshi/FactionRelations.h>
''')
edit('both:ActivityRuntimeBindings.cpp',''' if(actor->isEnemy(requester,true) || requester->isEnemy(actor,true)) { reason="requester_now_hostile"; return false; }''',''' if(actor->isEnemy(requester,true) || requester->isEnemy(actor,true)) { NC11HostileDiag(actor,requester,a.id); reason="requester_now_hostile"; return false; }''')
edit('both:ActivityRuntimeBindings.cpp','''bool ConcreteRuntimeBindings::VerifyGrant(const Agreement& a,Clock now,std::string& reason) {''','''namespace {
// NC11 diagnostic only: why enmity holds between actor and requester. Rate limited per actor (about 5 s).
void NC11HostileDiag(Character* actor,Character* requester,const std::string& agreement) {
 try {
  static std::map<unsigned,DWORD> last; const DWORD now=GetTickCount();
  const unsigned as=actor->getHandle().serial;
  std::map<unsigned,DWORD>::iterator it=last.find(as);
  if(it!=last.end() && now-it->second<5000) return;
  last[as]=now; if(last.size()>256) last.clear();
  std::ostringstream s; s<<"ACTIVITY_HOSTILE_DIAG ns=Activity@V@ agreement="<<agreement<<" actor="<<as;
  Character* ch[2]={actor,requester}; const char* tag[2]={"actor","requester"};
  for(unsigned n=0;n<2;++n) {
   Character* c=ch[n]; Faction* f=NULL; Character* other=ch[1-n];
   s<<" "<<tag[n]<<"Name="<<(c->getName().substr(0,40))<<" "<<tag[n]<<"Serial="<<c->getHandle().serial;
   try { f=c->getFaction(); s<<" "<<tag[n]<<"Faction="<<((f&&f->data)?f->data->stringID:std::string("?"))<<" "<<tag[n]<<"FactionName="<<(f?f->getName().substr(0,40):std::string("?")); } catch(...) {}
   try { Faction* of=other->getFaction();
    if(f && of && f->relations) s<<" "<<tag[n]<<"RelToOther="<<f->relations->getFactionRelation(of); } catch(...) {}
   try { const hand t=c->getAttackTarget(); s<<" "<<tag[n]<<"AttackTarget="<<((t.isValid()&&!t.isNull())?(long)t.serial:0L)
    <<" "<<tag[n]<<"InCombat="<<(c->isInCombatMode(true,true)?1:0); } catch(...) {}
  }
  s<<" actorEnemyOfReq="<<(actor->isEnemy(requester,true)?1:0)<<" reqEnemyOfActor="<<(requester->isEnemy(actor,true)?1:0);
  Log(s.str());
 } catch(...) {}
}
}
bool ConcreteRuntimeBindings::VerifyGrant(const Agreement& a,Clock now,std::string& reason) {''')

# ---- 2. camp-discover diag
edit('src/ActivityRuntimeBindings.cpp','''bool ConcreteRuntimeBindings::VerifyGrant(const Agreement& a,Clock now,std::string& reason) {''','''namespace {
std::string NC11FactionText(Character* c) {
 try { Faction* f=c->getFaction(); if(!f) return "faction=none";
  return std::string("faction=")+(f->data?f->data->stringID:std::string("?"))+" factionName="+f->getName().substr(0,40)+" notReal="+(f->isNotARealFaction()?"1":"0"); } catch(...) { return "faction=?"; }
}
// NC11 diagnostic only (row 14-c): formal TownBase entries the camp catalog sees from the actor, rate limited per actor (5 s).
void NC11CampZonesDiag(ActivityCampNative::ActivityCampCatalog& cat,Character* actor,bool discoverOk,const std::vector<ActivityCampNative::ZoneCandidate>& zones) {
 try {
  static std::map<unsigned,DWORD> last; const DWORD now=GetTickCount(); const unsigned as=actor->getHandle().serial;
  std::map<unsigned,DWORD>::iterator it=last.find(as);
  if(it!=last.end() && now-it->second<5000) return;
  last[as]=now; if(last.size()>256) last.clear();
  const Ogre::Vector3 ap=actor->getPosition();
  std::ostringstream s; s<<"ACTIVITY_CAMP_DIAG stage=zones actor="<<as<<" discoverOk="<<(discoverOk?1:0)<<" formalTownBases="<<zones.size()
   <<" actorPos="<<ap.x<<","<<ap.y<<","<<ap.z<<" actorSees "<<NC11FactionText(actor);
  for(size_t z=0;z<zones.size() && z<6;++z) {
   const ActivityCampNative::TownBaseFacts& t=zones[z].town; bool inside=false;
   const bool ok=cat.IsWithinNativeBorders(t,ap.x,ap.y,ap.z,inside);
   const float dx=ap.x-t.x,dz=ap.z-t.z;
   s<<" | zone"<<z<<"="<<t.knownName.substr(0,40)<<" sid="<<t.gameDataSid<<" type="<<t.townType<<" radius="<<t.radius<<" dist="<<std::sqrt(dx*dx+dz*dz)
    <<" actorInside="<<(ok?(inside?1:0):-1);
  }
  Log(s.str());
 } catch(...) {}
}
// NC11 diagnostic only (row 14-c): per hostile ClearGroup target, why a formal zone does or does not qualify. Rate limited per target (5 s).
void NC11CampGroupDiag(GameWorld* world,ActivityCampNative::ActivityCampCatalog& cat,Character* actor,Character* target,const std::vector<ActivityCampNative::ZoneCandidate>& zones,const std::vector<unsigned>& group,const char* stage) {
 try {
  static std::map<unsigned,DWORD> last; const DWORD now=GetTickCount(); const unsigned ts=target->getHandle().serial;
  std::map<unsigned,DWORD>::iterator it=last.find(ts);
  if(it!=last.end() && now-it->second<5000) return;
  last[ts]=now; if(last.size()>256) last.clear();
  std::ostringstream s; s<<"ACTIVITY_CAMP_DIAG stage="<<stage<<" actor="<<actor->getHandle().serial<<" target="<<ts<<" targetName="<<target->getName().substr(0,40)
   <<" "<<NC11FactionText(target)<<" groupTargets="<<group.size()<<" formalTownBases="<<zones.size();
  try { Faction* af=actor->getFaction(); Faction* tf=target->getFaction(); if(af&&tf&&af->relations) s<<" relActorToTarget="<<af->relations->getFactionRelation(tf); } catch(...) {}
  const Ogre::Vector3 tp=target->getPosition();
  for(size_t z=0;z<zones.size() && z<6;++z) {
   bool inA=false,inT=false; const ActivityCampNative::TownBaseFacts& t=zones[z].town;
   const bool okA=cat.IsWithinNativeBorders(t,actor->getPosition().x,actor->getPosition().y,actor->getPosition().z,inA);
   const bool okT=cat.IsWithinNativeBorders(t,tp.x,tp.y,tp.z,inT);
   unsigned membersInside=0,membersResolved=0;
   for(size_t k=0;k<group.size();++k) { Character* m=KenshiAi::ResolveCharacter(world,group[k]); bool in=false; if(!m) continue; ++membersResolved;
    if(cat.IsWithinNativeBorders(t,m->getPosition().x,m->getPosition().y,m->getPosition().z,in) && in) ++membersInside; }
   s<<" | zone"<<z<<"="<<t.knownName.substr(0,30)<<" actorInside="<<(okA?(inA?1:0):-1)<<" targetInside="<<(okT?(inT?1:0):-1)<<" membersInside="<<membersInside<<"/"<<membersResolved;
  }
  Log(s.str());
 } catch(...) {}
}
}
bool ConcreteRuntimeBindings::VerifyGrant(const Agreement& a,Clock now,std::string& reason) {''')
edit('src/ActivityRuntimeBindings.cpp',''' (void)campCatalog_.Discover(now_,zones);''',''' const bool nc11DiscoverOk=campCatalog_.Discover(now_,zones);
 NC11CampZonesDiag(campCatalog_,actor,nc11DiscoverOk,zones);''')
edit('src/ActivityRuntimeBindings.cpp','''      if(groupTargets.empty() || groupTargets.size()>32 || target->getHandle().serial!=groupTargets.front()) continue;''','''      if(groupTargets.empty() || groupTargets.size()>32 || target->getHandle().serial!=groupTargets.front()) { NC11CampGroupDiag(world_,campCatalog_,actor,target,zones,groupTargets,"group_targets_rejected"); continue; }''')
edit('src/ActivityRuntimeBindings.cpp','''       if(matches==1) {
        proposedCamp=zones[matchIndex]; proposedCampQualified=true;
       }
      }''','''       if(matches==1) {
        proposedCamp=zones[matchIndex]; proposedCampQualified=true;
       }
       if(matches!=1) NC11CampGroupDiag(world_,campCatalog_,actor,target,zones,groupTargets,matches?"zone_ambiguous":"no_zone_qualifies");
      } else NC11CampGroupDiag(world_,campCatalog_,actor,target,zones,groupTargets,"no_formal_zone");''')
