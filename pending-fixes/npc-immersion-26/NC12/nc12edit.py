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

# ================= 1. Row 25-b: natural mine node product from inventory / game data =================
P='both:ActivityPolicySupport.cpp'
edit(P,'#include "ActivityWildVerdict.h"\n','#include "ActivityWildVerdict.h"\n#include "ActivityMineProduct.h"\n')
# MineLease ctor differs between src (has baseline) and legacy-v1 (no baseline)
edit('src/ActivityPolicySupport.cpp','''bool valid,firstEmission,contribution;
 MineLease():building(NULL),actor(NULL),buildingSerial(0),actorSerial(0),inventory(NULL),section(NULL),
 expected(0),baseline(0),credit(0),valid(true),firstEmission(true),contribution(false) {}''','''bool valid,firstEmission,contribution;
 bool natural; // NC12: node without a ProductionBuilding; growth is polled, credited by proximity
 MineLease():building(NULL),actor(NULL),buildingSerial(0),actorSerial(0),inventory(NULL),section(NULL),
 expected(0),baseline(0),credit(0),valid(true),firstEmission(true),contribution(false),natural(false) {}''')
edit('legacy-v1/ActivityPolicySupport.cpp','''bool valid,firstEmission,contribution;
 MineLease():building(NULL),actor(NULL),buildingSerial(0),actorSerial(0),inventory(NULL),section(NULL),
 expected(0),credit(0),valid(true),firstEmission(true),contribution(false) {}''','''bool valid,firstEmission,contribution;
 bool natural; // NC12: node without a ProductionBuilding; growth is polled, credited by proximity
 MineLease():building(NULL),actor(NULL),buildingSerial(0),actorSerial(0),inventory(NULL),section(NULL),
 expected(0),credit(0),valid(true),firstEmission(true),contribution(false),natural(false) {}''')
# NaturalOutput + ExactSection natural branch
edit(P,'''InventorySection* ExactSection(Building* b,const std::string& item) {
 if(!b ||''','''// NC12 (row 25-b): natural mine nodes (special 27) return NULL from _NV_getProductionBuilding(), so the
// product comes from the node's stored items, else from the item references of its game data. `item` is
// in (expected, "" = resolve only) and out (product). `how` = inventory | gamedata:<list>. `clause` is set on failure.
InventorySection* NaturalOutput(Building* b,std::string& item,std::string& how,std::string& clause) {
 how.clear();clause.clear();
 if(!b || static_cast<int>(b->_NV_getSpecialFunction())!=27 || b->_NV_isDestroyed()) {clause="natural_not_mine_node";return NULL;}
 if(b->_NV_getProductionBuilding()) {clause="has_production_building";return NULL;}
 Inventory* inventory=b->getInventory();
 if(!inventory) {clause="building_inventory_null";return NULL;}
 ActivityMine::ProductInputs in; in.expected=item;
 const lektor<Item*>& all=inventory->getAllItems();
 for(unsigned i=0;i<all.size();++i) {
  if(!all.stuff[i] || !all.stuff[i]->data) {in.storedBad=true;break;}
  in.stored.push_back(all.stuff[i]->data->stringID);
 }
 std::string list;
 GameData* gd=b->getGameData();
 if(gd) {
  unsigned scanned=0;
  for(auto it=gd->objectReferences.begin();it!=gd->objectReferences.end() && scanned<128;++it,++scanned) {
   for(size_t k=0;k<it->second.size();++k) {
    GameData* ref=it->second[k].ptr;
    if(!ref || ref->type!=ITEM || ref->stringID.empty()) continue;
    if(std::find(in.dataItems.begin(),in.dataItems.end(),ref->stringID)==in.dataItems.end()) {
     in.dataItems.push_back(ref->stringID); if(list.empty()) list=it->first;
    }
   }
  }
 }
 std::string resolved;
 clause=ActivityMine::ResolveNaturalProduct(in,resolved,how);
 if(!clause.empty()) return NULL;
 if(how=="gamedata" && !list.empty()) how+=":"+list;
 lektor<InventorySection*>& secs=inventory->getAllSections();
 InventorySection* out=NULL;
 if(all.size()) {
  for(unsigned i=0;i<secs.size() && !out;++i) if(secs.stuff[i] && secs.stuff[i]->hasItem(all.stuff[0])) out=secs.stuff[i];
  if(!out) {clause="natural_section_not_found";return NULL;}
  for(unsigned i=0;i<all.size();++i) if(!out->hasItem(all.stuff[i])) {clause="stored_item_not_in_output_section";return NULL;}
 } else {
  if(secs.size()!=1 || !secs.stuff[0]) {clause="natural_output_section_ambiguous";return NULL;}
  out=secs.stuff[0];
 }
 item=resolved;
 return out;
}
InventorySection* ExactSection(Building* b,const std::string& item) {
 if(b && static_cast<int>(b->_NV_getSpecialFunction())==27 && !b->_NV_isDestroyed() && !b->_NV_getProductionBuilding()) {
  std::string it=item,how,clause; // NC12: natural node, no ProductionBuilding
  return NaturalOutput(b,it,how,clause);
 }
 if(!b ||''')
# natural diag (rate limited) placed right before Count()
edit(P,'''unsigned Count(InventorySection* section) {''','''// NC12 diagnostic: natural-node resolution result (same ACTIVITY_MINE_EXACT_DIAG tag, new clauses
// natural_resolved_inventory / natural_resolved_gamedata on success, natural_* on failure). ~5 s per node.
void DiagNatural(Building* b,const std::string& item,const std::string& how,const std::string& clause,bool ok,const char* entry) {
 try {
  static std::map<unsigned,long> last;
  const unsigned serial=b ? b->getHandle().serial:0;
  const long now=(long)std::clock();
  std::map<unsigned,long>::iterator it=last.find(serial);
  if(it!=last.end() && now>=it->second && now-it->second<=5L*CLOCKS_PER_SEC) return;
  last[serial]=now; if(last.size()>512) last.clear();
  std::ostringstream o;
  o<<"ACTIVITY_MINE_EXACT_DIAG node="<<serial<<" entry="<<entry<<" item="<<item<<" natural=1 how="<<how;
  if(b) {
   o<<" bsid="<<(b->getGameData()?b->getGameData()->stringID:std::string("?"))<<" special="<<static_cast<int>(b->_NV_getSpecialFunction());
   Inventory* inv=b->getInventory();
   o<<" inventory="<<(inv?1:0);
   if(inv) o<<" storedItems="<<inv->getAllItems().size()<<" sections="<<inv->getAllSections().size();
   if(!ok && b->getGameData()) { // which reference lists the node data has (first 12)
    o<<" lists="; unsigned n=0;
    for(auto li=b->getGameData()->objectReferences.begin();li!=b->getGameData()->objectReferences.end() && n<12;++li,++n)
     o<<(n?",":"")<<li->first<<":"<<li->second.size();
   }
  }
  o<<" clause="<<(ok ? (how.compare(0,9,"inventory")==0 ? "natural_resolved_inventory":"natural_resolved_gamedata") : clause);
  ::Log(o.str());
 } catch(...) {}
}
unsigned Count(InventorySection* section) {''')
# Check(): natural growth
edit(P,'''bool Check(MineLease& l) {
 if(!l.valid) return false;
 if(!Identity(l) || Count(l.section)!=l.expected) {l.valid=false;return false;}
 return true;
}''','''// NC12: a natural node has no output hook, so growth of its output is polled. It is credited only while
// the lease actor is alive and within 60 units (horizontal) of the node; anything else invalidates the lease.
bool NaturalGrowth(MineLease& l,unsigned now) {
 if(!l.natural || now<=l.expected || !l.actor || !l.building || l.actor->isDead() || l.actor->isUnconcious()) return false;
 const Ogre::Vector3 a=l.actor->getPosition(), n=l.building->getPosition();
 const float dx=a.x-n.x, dz=a.z-n.z;
 if(!_finite(dx) || !_finite(dz) || dx*dx+dz*dz>60.0f*60.0f) return false;
 const unsigned grown=now-l.expected;
 if(l.credit>std::numeric_limits<unsigned>::max()-grown) return false;
 l.credit+=grown; l.expected=now; l.contribution=true; l.firstEmission=false;
 return true;
}
bool Check(MineLease& l) {
 if(!l.valid) return false;
 if(!Identity(l)) {l.valid=false;return false;}
 const unsigned now=Count(l.section);
 if(now!=l.expected && !NaturalGrowth(l,now)) {l.valid=false;return false;}
 return true;
}''')
# lease start: remember natural
edit(P,'''  MineLease l; l.id=id;l.actor=actor;l.building=b;l.item=item;''','''  MineLease l; l.id=id;l.actor=actor;l.building=b;l.item=item;l.natural=!b->_NV_getProductionBuilding();''')
# confirm taken: allow polled growth before the take
edit(P,'''  MineLease& l=i->second;
  if(!l.valid || !Identity(l) || !amount ||''','''  MineLease& l=i->second;
  if(l.valid && l.natural && Identity(l)) { // NC12: output that grew before the take is credited first
   const unsigned now=Count(l.section);
   if(now+amount>l.expected) NaturalGrowth(l,now+amount);
  }
  if(!l.valid || !Identity(l) || !amount ||''')
# MineSourcePermitted: natural branch
edit(P,'''  ProductionBuilding* production=b->_NV_getProductionBuilding();
  StorageBuilding::ConsumptionItem* product=production ? production->getProductionItem():NULL;''','''  ProductionBuilding* production=b->_NV_getProductionBuilding();
  if(!production) { // NC12 (row 25-b): natural node, product from inventory / game data
   std::string resolved,how,clause;
   InventorySection* section=NaturalOutput(b,resolved,how,clause);
   DiagNatural(b,resolved,how,clause,section!=NULL,"MineSourcePermitted@V@");
   if(!section || resolved.empty()) {reason="exact_output_unavailable";return false;}
   item=resolved;reason.clear();return true;
  }
  StorageBuilding::ConsumptionItem* product=production ? production->getProductionItem():NULL;''')

# ================= 2. Row 14-c: camp town catalog reject diagnostics =================
T='src/ActivityCampTownReader.cpp'
edit(T,'''#include <stdint.h>
#include <kenshi/Town.h>
''','''#include <stdint.h>
#include <kenshi/Town.h>
#include <ctime>
#include <map>
#include <sstream>

void Log(const std::string&);
''')
edit(T,'''bool IsUsableRoot(RootObject* root) {
  return root && reinterpret_cast<uintptr_t>(root) > 0x1000;
}
''','''bool IsUsableRoot(RootObject* root) {
  return root && reinterpret_cast<uintptr_t>(root) > 0x1000;
}

// NC12 diagnostic (row 14-c): same checks as ReadFacts, in the same order, but returns the first failing
// clause instead of a bool and fills the facts it could read. Never changes any outcome.
const char* ExplainFacts(RootObject* entry, TownBaseFacts* facts, int* dataType) {
  if (dataType) *dataType = -1;
  if (!IsUsableRoot(entry)) return "unusable_root";
  try {
    const int dt = static_cast<int>(entry->getDataType());
    if (dataType) *dataType = dt;
    if (entry->getDataType() != TOWN) return "not_TOWN_datatype";
    TownBase* town = static_cast<TownBase*>(entry);
    GameData* data = town->data;
    if (!data) return "data_null";
    if (!data->isValid()) return "data_invalid";
    if (data->stringID.empty()) return "sid_empty";
    const hand& h = town->handle;
    const Ogre::Vector3 p = town->_NV_getPosition();
    facts->runtimeSerial = h.serial; facts->handleSerial = h.serial;
    facts->gameDataSid = data->stringID;
    facts->knownName = town->getKnownName();
    facts->townType = static_cast<unsigned int>(town->townType);
    facts->x = p.x; facts->y = p.y; facts->z = p.z;
    facts->radius = town->_NV_getRadius();
    if (facts->runtimeSerial == 0) return "handle_serial_zero";
    if (facts->gameDataSid.size() > 256) return "sid_too_long";
    if (facts->knownName.empty()) return "known_name_empty";
    if (facts->knownName.size() > 256) return "known_name_too_long";
    if (!IsFormalCampType(facts->townType)) return "not_formal_type";
    if (!Finite(facts->x) || !Finite(facts->y) || !Finite(facts->z) || !Finite(facts->radius)) return "non_finite";
    if (facts->radius < 25.0f || facts->radius > 2000.0f) return "radius_out_of_range";
    return "ok";
  } catch (...) { return "exception"; }
}

// Rate limited (about 30 s): raw count, tally of town types and reject reasons over every entry, and the
// first 12 entries in detail. Grep ACTIVITY_CAMP_TOWNS_DIAG.
void DiagTownEntries(const std::vector<RootObject*>& entries, std::size_t accepted) {
  try {
    static long last = 0;
    const long now = (long)std::clock();
    if (last && now >= last && now - last < 30L * CLOCKS_PER_SEC) return;
    last = now;
    std::map<unsigned int, unsigned> typeTally;
    std::map<std::string, unsigned> reasonTally;
    std::map<int, unsigned> dataTypeTally;
    std::ostringstream detail;
    for (std::size_t i = 0; i < entries.size(); ++i) {
      TownBaseFacts f; int dt = -1;
      const char* why = ExplainFacts(entries[i], &f, &dt);
      ++reasonTally[why]; ++dataTypeTally[dt];
      if (std::string(why) != "unusable_root" && std::string(why) != "not_TOWN_datatype" &&
          std::string(why) != "data_null" && std::string(why) != "data_invalid" && std::string(why) != "sid_empty" &&
          std::string(why) != "exception") ++typeTally[f.townType];
      if (i < 12)
        detail << " | e" << i << "=" << why << " dt=" << dt << " name=" << f.knownName << " sid=" << f.gameDataSid
               << " type=" << f.townType << " r=" << f.radius << " h=" << f.runtimeSerial;
    }
    std::ostringstream o;
    o << "ACTIVITY_CAMP_TOWNS_DIAG raw=" << entries.size() << " accepted=" << accepted << " types=";
    for (std::map<unsigned int, unsigned>::const_iterator t = typeTally.begin(); t != typeTally.end(); ++t)
      o << t->first << ":" << t->second << ",";
    o << " reasons=";
    for (std::map<std::string, unsigned>::const_iterator r = reasonTally.begin(); r != reasonTally.end(); ++r)
      o << r->first << ":" << r->second << ",";
    o << " dataTypes=";
    for (std::map<int, unsigned>::const_iterator d = dataTypeTally.begin(); d != dataTypeTally.end(); ++d)
      o << d->first << ":" << d->second << ",";
    o << detail.str();
    ::Log(o.str());
  } catch (...) {}
}
''')
edit(T,'''    if (ReadFormalCampTown(entries[i],&facts)) out.push_back(facts);
  }
  return true;''','''    if (ReadFormalCampTown(entries[i],&facts)) out.push_back(facts);
  }
  DiagTownEntries(entries,out.size());
  return true;''')

# ================= 3. Row 26-a: activity end (Failed/Cancelled) diagnostics + VerifyGrant failure inputs =================
G='src/ActivityGoals.cpp'
edit(G,'''#include <algorithm>
#include <sstream>
#include <float.h>

namespace Stobe { namespace Activity {
''','''#include <algorithm>
#include <sstream>
#include <map>
#include <float.h>

namespace Stobe { namespace Activity {
// NC12: log sink set by ActivityController (keeps the portable goal tests free of a Log() link dependency).
void (*ActivityEndLogSink)(const std::string&)=0;
namespace {
// NC12 diagnostic (row 26-a): one line per distinct (where,phase,reason) per agreement when a goal is stopped,
// cancelled or fails, so an empty or unexplained reason can be traced. Never changes behaviour.
void DiagEnd(const char* where,const Agreement& t,Phase now,Phase to,const std::string& reason,const std::string& extra) {
 try {
  if(to!=Failed && to!=Cancelled) return;
  static std::map<std::string,std::string> last;
  std::ostringstream key; key<<where<<'|'<<static_cast<int>(to)<<'|'<<reason;
  std::string& l=last[t.id]; if(l==key.str()) return; l=key.str(); if(last.size()>256) last.clear();
  std::ostringstream o;
  o<<"ACTIVITY_END_DIAG where="<<where<<" id="<<t.id<<" kind="<<(t.kind==Hunt?"Hunt":t.kind==Mine?"Mine":"ClearGroup")
   <<" actor="<<t.actor<<" requester="<<t.requester<<" fromPhase="<<static_cast<int>(now)<<" toPhase="<<(to==Failed?"failed":"cancelled")
   <<" reasonEmpty="<<(reason.empty()?1:0)<<" reason="<<reason<<extra;
  if(ActivityEndLogSink) ActivityEndLogSink(o.str());
 } catch(...) {}
}
}
''')
edit(G,'''void Goal::Stop(Phase phase, Host& host, const std::string& why) {
  stopPending_=true;''','''void Goal::Stop(Phase phase, Host& host, const std::string& why) {
  { std::ostringstream x; x<<" pendingCmd="<<static_cast<int>(pendingCommand_)<<" pendingEmpty="<<(pending_.empty()?1:0)<<" replans="<<replans_
     <<" attempted="<<attempted_.size()<<" delivered="<<delivered_<<" target="<<target_.serial<<" lastReason="<<reason_;
    DiagEnd("goal_stop",terms_,phase_,phase,why,x.str()); }
  stopPending_=true;''')
edit(G,'''    phase_ = Failed; reason_ = why; return;
  }''','''    { std::ostringstream x; x<<" replans="<<replans_<<"/"<<terms_.maximumReplans<<" attempted="<<attempted_.size()<<"/"<<terms_.maximumTargets
       <<" target="<<target_.serial; DiagEnd("replan_exhausted",terms_,phase_,Failed,why,x.str()); }
    phase_ = Failed; reason_ = why; return;
  }''')
C='src/ActivityController.cpp'
edit(C,'''extern int ResolveCurrentGameTimestampSeconds(GameWorld*);
''','''extern int ResolveCurrentGameTimestampSeconds(GameWorld*);
namespace Stobe { namespace Activity { extern void (*ActivityEndLogSink)(const std::string&); } } // NC12 (ActivityGoals.cpp)
''')
edit(C,'''void UpdateActivityController(GameWorld* world){
 if(!world)return;''','''void UpdateActivityController(GameWorld* world){
 if(!world)return;
 Stobe::Activity::ActivityEndLogSink=&::Log; // NC12 diagnostic sink for ActivityGoals.cpp''')
edit(C,'''  const bool clean=runtime->CleanupComplete(i->first);
  const bool ended=phase==Complete||phase==Cancelled||phase==Failed;
  GoalStatusSnapshot goal;const bool goalAvail=runtime->Snapshot(i->first,goal);''','''  const bool clean=runtime->CleanupComplete(i->first);
  const bool ended=phase==Complete||phase==Cancelled||phase==Failed;
  GoalStatusSnapshot goal;const bool goalAvail=runtime->Snapshot(i->first,goal);
  if(phase==Failed||phase==Cancelled) { // NC12 diagnostic (row 26-a): phase + reason on every Failed/Cancelled transition
   try {
    static std::map<std::string,std::string> lastEnd;
    std::ostringstream key;key<<static_cast<int>(phase)<<'|'<<reason<<'|'<<(clean?1:0);
    std::string& prev=lastEnd[i->first];
    if(prev!=key.str()) {
     prev=key.str();if(lastEnd.size()>256)lastEnd.clear();
     std::ostringstream d;d<<"ACTIVITY_END_DIAG where=publish id="<<i->first<<" kind="<<(i->second.kind==Hunt?"Hunt":i->second.kind==Mine?"Mine":"ClearGroup")
      <<" actor="<<i->second.actor<<" requester="<<i->second.requester<<" toPhase="<<PhaseName(phase)<<" reasonEmpty="<<(reason.empty()?1:0)
      <<" reason="<<reason<<" cleanupComplete="<<(clean?1:0)<<" revision="<<revisions[i->first]<<" rejectedAtStart="<<(rejected.find(i->first)!=rejected.end()?1:0)
      <<" goalAvail="<<(goalAvail?1:0);
     if(goalAvail) d<<" goalTerminal="<<(goal.terminal?1:0)<<" hasTarget="<<(goal.hasTarget?1:0)<<" target="<<goal.currentTarget
      <<" pendingAction="<<(goal.hasPendingRequest?1:0)<<" delivered="<<goal.delivered;
     Log(d.str());
    }
   } catch(...) {}
  }''')
B='src/ActivityRuntimeBindings.cpp'
edit(B,'''namespace {
std::string NC11FactionText(Character* c) {''','''namespace {
// NC12 diagnostic (row 26-a): which VerifyGrant clause failed and its inputs. Rate limited per agreement (5 s).
void NC12VerifyDiag(const char* clause,const std::string& id,const std::string& detail) {
 try {
  static std::map<std::string,DWORD> last; const DWORD now=GetTickCount();
  std::map<std::string,DWORD>::iterator it=last.find(id);
  if(it!=last.end() && now-it->second<5000) return;
  last[id]=now; if(last.size()>256) last.clear();
  Log(std::string("ACTIVITY_VERIFY_DIAG agreement=")+id+" clause="+clause+detail);
 } catch(...) {}
}
std::string NC11FactionText(Character* c) {''')
edit(B,'''it->second.revoked || !Equal(a,it->second.scope)) {
  reason="activity_grant_missing_revoked_expired_or_changed"; return false;''','''it->second.revoked || !Equal(a,it->second.scope)) {
  { std::ostringstream d; d<<" haveWorld="<<(world_?1:0)<<" worldMatch="<<(a.worldId==worldId_?1:0)<<" now="<<now<<" bound="<<now_<<" expiresAt="<<a.expiresAt
     <<" grant="<<(it!=grants_.end()?1:0)<<" revoked="<<((it!=grants_.end()&&it->second.revoked)?1:0)<<" scopeEqual="<<((it!=grants_.end()&&Equal(a,it->second.scope))?1:0);
    NC12VerifyDiag("grant_missing_revoked_expired_or_changed",a.id,d.str()); }
  reason="activity_grant_missing_revoked_expired_or_changed"; return false;''')
edit(B,'''!requester->isPlayerCharacter()) {
  reason="activity_actor_or_requester_unavailable"; return false;''','''!requester->isPlayerCharacter()) {
  { std::ostringstream d; d<<" actorFound="<<(actor?1:0)<<" actorIdentity="<<((actor&&actor==it->second.actorIdentity)?1:0)<<" actorSerialOk="<<((actor&&actor->getHandle().serial==a.actor)?1:0)
     <<" requesterFound="<<(requester?1:0)<<" requesterIdentity="<<((requester&&requester==it->second.requesterIdentity)?1:0)
     <<" requesterSerialOk="<<((requester&&requester->getHandle().serial==a.requester)?1:0)<<" requesterIsPlayer="<<((requester&&requester->isPlayerCharacter())?1:0);
    NC12VerifyDiag("actor_or_requester_unavailable",a.id,d.str()); }
  reason="activity_actor_or_requester_unavailable"; return false;''')
