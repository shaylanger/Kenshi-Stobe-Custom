#include "ActivityController.h"
#include "ActivityTransport.h"
#include "ActivityPolicySupport.h"
#include "ActivityRuntimeBindings.h"
#include "PlaythroughSession.h"
#include "StobeText.h"
#include "Utils.h"
#include <windows.h>
#include <objbase.h>
#include <sstream>
#include <iomanip>
#include <deque>
#include <map>
extern int ResolveCurrentGameTimestampSeconds(GameWorld*);
namespace {
using namespace Stobe::Activity;
SRWLOCK activityLock=SRWLOCK_INIT;
struct Message { Agreement grant; std::string id,world;unsigned revision;bool revoke;Message():revision(0),revoke(false){} };
std::deque<Message> inbox;
std::string publishedWorld,publishedStatus="[]";
Clock publishedClock=0;
bool epochInvalid=true;
GameWorld* currentWorld=NULL;
unsigned long currentGeneration=0;
Clock lastStableClock=0;
DWORD nextDecisionAt=0;
std::string currentEpoch;
ConcreteRuntimeBindings* bindings=NULL;
Runtime* runtime=NULL;
std::map<std::string,Agreement> accepted;
std::map<std::string,unsigned> revisions;
std::map<std::string,std::string> rejected;
std::string NewEpoch() {
 GUID id;if(FAILED(CoCreateGuid(&id)))return std::string();
 std::ostringstream out;out<<std::hex<<std::setfill('0')<<std::setw(8)<<id.Data1
 <<std::setw(4)<<id.Data2<<std::setw(4)<<id.Data3;
 for(int i=0;i<8;++i)out<<std::setw(2)<<static_cast<unsigned>(id.Data4[i]);return out.str();
}
const char* PhaseName(Phase p) {
 switch(p){case Dormant:return "dormant";case Searching:return "searching";case Travelling:return "travelling";
 case Performing:return "performing";case Verifying:return "verifying";case Complete:return "complete";
 case Cancelled:return "cancelled";default:return "failed";}
}
void Publish(Clock now) {
 std::ostringstream out;out<<"[";bool comma=false;
 for(std::map<std::string,Agreement>::const_iterator i=accepted.begin();i!=accepted.end();++i){
  Phase phase;std::string reason;if(!runtime->Status(i->first,phase,reason)){
   std::map<std::string,std::string>::const_iterator denied=rejected.find(i->first);if(denied==rejected.end())continue;phase=Failed;reason=denied->second;
  }
  const bool clean=runtime->CleanupComplete(i->first);
  if(comma)out<<",";comma=true;
  out<<"{\"id\":\""<<Stobe::Text::EscapeJSON(i->first)<<"\",\"worldId\":\""<<i->second.worldId
  <<"\",\"actor\":"<<i->second.actor<<",\"requester\":"<<i->second.requester
  <<",\"kind\":\""<<(i->second.kind==Hunt?"Hunt":i->second.kind==Mine?"Mine":"ClearGroup")
  <<"\",\"phase\":\""<<(!clean&&(phase==Complete||phase==Cancelled||phase==Failed)?"cleanup_pending":PhaseName(phase))<<"\",\"reason\":\""<<Stobe::Text::EscapeJSON(reason)
  <<"\",\"cleanupComplete\":"<<(clean?"true":"false")<<",\"gameTs\":"<<now<<",\"revision\":"<<revisions[i->first]<<"}";
 }
 out<<"]";AcquireSRWLockExclusive(&activityLock);publishedWorld=currentEpoch;publishedClock=now;publishedStatus=out.str();ReleaseSRWLockExclusive(&activityLock);
}
}
bool QueueActivityGrant(const Stobe::Activity::Agreement& grant,unsigned revision){
 AcquireSRWLockExclusive(&activityLock);
 bool ok=revision&&grant.worldId==publishedWorld&&!publishedWorld.empty()&&inbox.size()<128;
 if(ok){Message m;m.grant=grant;m.world=grant.worldId;m.id=grant.id;m.revision=revision;inbox.push_back(m);}
 ReleaseSRWLockExclusive(&activityLock);return ok;
}
bool QueueActivityRevoke(const std::string& id,const std::string& world,unsigned revision){
 AcquireSRWLockExclusive(&activityLock);bool ok=revision&&!id.empty()&&world==publishedWorld&&!world.empty()&&inbox.size()<128;
 if(ok){Message m;m.revoke=true;m.id=id;m.world=world;m.revision=revision;inbox.push_back(m);}
 ReleaseSRWLockExclusive(&activityLock);return ok;
}
std::string ActivityControllerWorldId(){AcquireSRWLockShared(&activityLock);std::string id=publishedWorld;ReleaseSRWLockShared(&activityLock);return id;}
Stobe::Activity::Clock ActivityControllerGameClock(){AcquireSRWLockShared(&activityLock);Clock n=publishedClock;ReleaseSRWLockShared(&activityLock);return n;}
std::string ActivityControllerStatusJson(){AcquireSRWLockShared(&activityLock);std::string s=publishedStatus;ReleaseSRWLockShared(&activityLock);return s;}
std::string CaptureActivityChatFacts(unsigned actor,unsigned requester){
 AcquireSRWLockShared(&activityLock);bool stable=!epochInvalid&&!publishedWorld.empty();ReleaseSRWLockShared(&activityLock);
 if(!stable||!bindings||!currentWorld||currentEpoch.empty())return "{}";
 return bindings->ProposalFacts(actor,requester);
}
void ResetActivityController(const char* reason){
 // Caller may already have an unstable world. Never dereference its objects.
 AcquireSRWLockExclusive(&activityLock);epochInvalid=true;publishedWorld.clear();publishedStatus="[]";publishedClock=0;inbox.clear();ReleaseSRWLockExclusive(&activityLock);
 Stobe::Activity::ResetActivityTransport();
 (void)reason;
}
void UpdateActivityController(GameWorld* world){
 if(!world)return;
 const int rawNow=ResolveCurrentGameTimestampSeconds(world);if(rawNow<0)return;const Clock now=static_cast<Clock>(rawNow);
 if(!bindings){bindings=new ConcreteRuntimeBindings();runtime=new Runtime(*bindings);}
 bool invalid;AcquireSRWLockShared(&activityLock);invalid=epochInvalid;ReleaseSRWLockShared(&activityLock);
 const unsigned long generation=PlaythroughSession::Generation();
 if(invalid||currentWorld!=world||currentGeneration!=generation||now<lastStableClock){
  if(currentWorld==world&&currentGeneration==generation&&now>=lastStableClock&&!currentEpoch.empty()) {
   bindings->Bind(world,currentEpoch,now);std::string why;
   if(!runtime->Reset(world,currentEpoch,now,why)){Log("ACTIVITY same-world cleanup pending: "+why);return;}
  }
  const std::string epoch=NewEpoch();if(epoch.empty())return;
  currentWorld=world;currentGeneration=generation;currentEpoch=epoch;
  // New epoch invalidates old native pointers before old goals are cancelled.
  bindings->Bind(world,currentEpoch,now);runtime->Tick(world,currentEpoch,now);
  std::string why;if(!runtime->Reset(world,currentEpoch,now,why)){Log("ACTIVITY reset cleanup unconfirmed: "+why);return;}
  ResetMineLeases();accepted.clear();revisions.clear();rejected.clear();nextDecisionAt=0;
  AcquireSRWLockExclusive(&activityLock);epochInvalid=false;inbox.clear();ReleaseSRWLockExclusive(&activityLock);
 }
 bindings->Bind(world,currentEpoch,now);
 std::deque<Message> messages;AcquireSRWLockExclusive(&activityLock);messages.swap(inbox);ReleaseSRWLockExclusive(&activityLock);
 for(size_t n=0;n<messages.size();++n){Message& m=messages[n];if(m.world!=currentEpoch)continue;
  if(m.revoke){if(bindings->Revoke(m.id,m.revision)){runtime->Cancel(m.id,"agreement_revoked");revisions[m.id]=m.revision;}continue;}
  std::string why;if(!bindings->ImportGrant(m.grant,m.revision,why)){Log("ACTIVITY grant rejected: "+why);
   if(accepted.find(m.id)==accepted.end()){accepted[m.id]=m.grant;revisions[m.id]=m.revision;rejected[m.id]=why;}continue;}
  if(accepted.find(m.id)!=accepted.end())continue;
  if(runtime->Start(m.grant,world,currentEpoch,now,why)){accepted[m.id]=m.grant;revisions[m.id]=m.revision;}
  else {Log("ACTIVITY start rejected: "+why);accepted[m.id]=m.grant;revisions[m.id]=m.revision;rejected[m.id]=why;}
 }
 const DWORD decisionNow=GetTickCount();
 if(!messages.empty()||!nextDecisionAt||(LONG)(decisionNow-nextDecisionAt)>=0){
  nextDecisionAt=decisionNow+500;runtime->Tick(world,currentEpoch,now);lastStableClock=now;Publish(now);
 }
 Stobe::Activity::UpdateActivityTransport();
}