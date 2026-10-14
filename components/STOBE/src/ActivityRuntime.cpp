#include "ActivityRuntime.h"
#include <algorithm>
namespace Stobe { namespace Activity {
NativeHost::NativeHost(RuntimeBindings& b):bindings_(b),executor_(*this),world_(0),now_(0),frameObserved_(false){}
void NativeHost::Bind(GameWorld* w,const std::string& id,Clock now) {
 world_=w;worldId_=id;now_=now;frameObserved_=false;executor_.Bind(w,id,now);
}
bool NativeHost::Authorized(const Agreement& a,Clock now,std::string& why) {
 if(!world_||a.worldId!=worldId_||now>=a.expiresAt) {why="world_or_expiry_mismatch";return false;}
 return bindings_.VerifyGrant(a,now,why);
}
Facts NativeHost::Observe(const Agreement& a,unsigned int target) {
 Facts f;f.worldId=worldId_;std::string why;
 f.revoked=!Authorized(a,now_,why);f.conflictingOrder=false;
 Target t;
 if(target) {
   NativeDestination d;std::string candidate;
   std::map<unsigned int,NativeDestination>::const_iterator i=targets_.find(target);
   if(a.kind!=ClearGroup && i!=targets_.end())candidate=i->second.facts.candidateId;
   if(bindings_.Resolve(a,target,candidate,d,why)&&d.facts.serial==target) t=d.facts;
 }
 if(!frameObserved_){
  frameFacts_=f;Target noTarget;executor_.Observe(a,noTarget,frameFacts_);frameObserved_=true;
 }
 const bool revoked=f.revoked;f=frameFacts_;f.revoked=revoked;f.target=t;f.delivered=executor_.Delivered(a.id);return f;
}
std::vector<Target> NativeHost::Candidates(const Agreement& a) {
 std::vector<Target> out;std::string why;if(!Authorized(a,now_,why))return out;
 std::vector<NativeDestination> rows=bindings_.Discover(a);
 for(size_t n=0;n<rows.size()&&n<256;++n) {
   NativeDestination d;const Target& t=rows[n].facts;
   if(!t.serial||t.candidateId.empty()||!t.visible||!t.reachable)continue;
   if(a.kind==ClearGroup) {
     if(std::find(a.agreedTargets.begin(),a.agreedTargets.end(),t.serial)==a.agreedTargets.end())continue;
   } else if(t.sourceId!=a.sourceId)continue;
   if(!bindings_.Resolve(a,t.serial,t.candidateId,d,why)||d.facts.serial!=t.serial||
      d.facts.sourceId!=t.sourceId||d.facts.candidateId!=t.candidateId)continue;
   targets_[t.serial]=d;out.push_back(d.facts);
 }
 return out;
}
bool NativeHost::Revalidate(const Agreement& a,const Request& r,Target& out,std::string& why) {
 if(!Authorized(a,now_,why)||r.agreementId!=a.id||r.actor!=a.actor||!r.target||
    r.target==a.actor||r.target==a.requester||r.resourceId!=a.resourceId||r.quantity>a.quantity) {
   if(why.empty())why="activity_request_scope_mismatch";return false;
 }
 if(a.kind==ClearGroup&&std::find(a.agreedTargets.begin(),a.agreedTargets.end(),r.target)==a.agreedTargets.end()) {
   why="target_outside_fixed_agreement";return false;
 }
 if((a.kind==Mine&&r.command==Attack)||(a.kind!=Mine&&r.command==WorkResource)||
    (a.kind==ClearGroup&&r.command==TakeItem)) {why="command_outside_activity_scope";return false;}
 NativeDestination d;
 if(!bindings_.Resolve(a,r.target,r.candidateId,d,why)||d.facts.serial!=r.target||
    d.facts.candidateId!=r.candidateId||!d.facts.visible||!d.facts.reachable||
    (a.kind!=ClearGroup&&d.facts.sourceId!=a.sourceId))return false;
 if(!bindings_.ActivityPermitted(a,r,d.facts,why))return false;
 out=d.facts;targets_[r.target]=d;return true;
}
bool NativeHost::Dispatch(const Agreement& a,const Request& r,std::string& why) {
 Target t;if(!Revalidate(a,r,t,why))return false;
 return executor_.Dispatch(a,r,targets_[r.target],why);
}
Receipt NativeHost::Poll(const std::string& id){return executor_.Poll(id);}
bool NativeHost::CancelOwned(const std::string& id){return executor_.CancelOwned(id);}
Building* NativeHost::ResolveResource(const Agreement& a,unsigned int s){return bindings_.Resource(a,s);}
Inventory* NativeHost::ResourceOutput(const Agreement& a,Building* b){return bindings_.Output(a,b);}
Runtime::Runtime(RuntimeBindings& b):bindings_(b){}
Runtime::~Runtime(){
 for(std::map<std::string,Entry*>::iterator i=entries_.begin();i!=entries_.end();++i) {
   i->second->goal.Cancel(i->second->host,"runtime_shutdown");
   // Integration must call Reset while the old world is valid before destruction.
   delete i->second;
 }
}
bool Runtime::Start(const Agreement& a,GameWorld* w,const std::string& id,Clock now,std::string& why) {
 if(entries_.find(a.id)!=entries_.end()){why="agreement_already_seen";return false;}
 for(std::map<std::string,Entry*>::iterator i=entries_.begin();i!=entries_.end();++i) {
   const Goal& g=i->second->goal;
   if(g.Terms().actor==a.actor&&(!g.CleanupComplete()||
      (g.State()!=Complete&&g.State()!=Cancelled&&g.State()!=Failed))) {
     why="actor_has_existing_activity";return false;
   }
 }
 Entry* e=new Entry(bindings_);e->host.Bind(w,id,now);
 if(!e->goal.Start(a,now,e->host)){why=e->goal.Reason();delete e;return false;}
 entries_[a.id]=e;return true;
}
void Runtime::Tick(GameWorld* w,const std::string& id,Clock now) {
 for(std::map<std::string,Entry*>::iterator i=entries_.begin();i!=entries_.end();++i) {
   i->second->host.Bind(w,id,now);i->second->goal.Tick(now,i->second->host);
 }
}
bool Runtime::Cancel(const std::string& id,const std::string& why) {
 std::map<std::string,Entry*>::iterator i=entries_.find(id);if(i==entries_.end())return false;
 i->second->goal.Cancel(i->second->host,why);return i->second->goal.CleanupComplete();
}
bool Runtime::Reset(GameWorld* w,const std::string& id,Clock now,std::string& why) {
 bool clean=true;
 for(std::map<std::string,Entry*>::iterator i=entries_.begin();i!=entries_.end();++i) {
   i->second->host.Bind(w,id,now);i->second->goal.Cancel(i->second->host,"world_reset");
   clean=clean&&i->second->goal.CleanupComplete();
 }
 if(!clean){why="owned_order_cleanup_unconfirmed";return false;}
 for(std::map<std::string,Entry*>::iterator i=entries_.begin();i!=entries_.end();++i)delete i->second;
 entries_.clear();return true;
}
bool Runtime::CleanupComplete(const std::string& id)const {
 std::map<std::string,Entry*>::const_iterator i=entries_.find(id);return i==entries_.end()||i->second->goal.CleanupComplete();
}
bool Runtime::Status(const std::string& id,Phase& phase,std::string& why)const {
 std::map<std::string,Entry*>::const_iterator i=entries_.find(id);if(i==entries_.end())return false;
 phase=i->second->goal.State();why=i->second->goal.Reason();return true;
}
} }