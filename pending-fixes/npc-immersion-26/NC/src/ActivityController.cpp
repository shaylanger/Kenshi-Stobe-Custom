#include "ActivityController.h"
#include "../legacy-v1/ActivityController.h"
#include "ActivityTransport.h"
#include "ActivityPolicySupport.h"
#include "ActivityRuntimeBindings.h"
#include "ActivityHandBack.h"
#include "ActivityDanger.h"
#include "ActivityEventTracker.h"
#include "ActivityStatusSnapshot.h"
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
namespace ActivityStatusSnapshot = Stobe::ActivityStatusSnapshot;
SRWLOCK activityLock=SRWLOCK_INIT;
struct Message { Agreement grant; std::string id,world;unsigned revision;bool revoke;Message():revision(0),revoke(false){} };
std::deque<Message> inbox;
std::string publishedWorld,publishedStatus="[]";
std::string publishedObserverStatus="{\"activities\":[],\"truncated\":false,\"unsupported\":[]}";
std::map<std::string,ActivityStatusSnapshot::Row> publishedRows;
bool publishedRowsTruncated=false;
bool publishedRowsInvalid=false;
Clock publishedClock=0;
DWORD publishedAtTick=0;
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
HandBackHost handBackHost;
Events::Tracker eventTracker;
std::map<std::string,DWORD> nextDangerAt;
std::map<std::string,DangerFacts> lastDanger;
std::string NewEpoch() {
 GUID id;if(FAILED(CoCreateGuid(&id)))return std::string();
 std::ostringstream out;out<<std::hex<<std::setfill('0')<<std::setw(8)<<id.Data1
 <<std::setw(4)<<id.Data2<<std::setw(4)<<id.Data3;
 for(int i=0;i<8;++i)out<<std::setw(2)<<static_cast<unsigned>(id.Data4[i]);return out.str();
}
const char* PhaseName(Phase p) {
 switch(p){case Dormant:return "dormant";case Routing:return "routing";case Searching:return "searching";case Travelling:return "travelling";
 case Performing:return "performing";case Verifying:return "verifying";case Complete:return "complete";
 case Cancelled:return "cancelled";default:return "failed";}
}
const char* CommandName(Command c) {
 switch(c){case Travel:return "travel";case RouteTravel:return "route_travel";case Attack:return "attack";
 case WorkResource:return "work_resource";case TakeItem:return "take_item";default:return "unknown";}
}
// Structured in-progress events (threat / injury / progress / arrival / hand-back) for the server's situated
// dialogue. Observations only: nothing here changes what the goal does.
void EmitEvents(GameWorld* world,Clock now,const Agreement& a,Phase phase,bool clean,bool goalAvail,const GoalStatusSnapshot& goal,const HandBackView& hb) {
 const bool ended=phase==Complete||phase==Cancelled||phase==Failed;
 Events::Observation o;o.agreementId=a.id;o.nowMs=GetTickCount();
 o.phase=!clean&&ended?"cleanup_pending":PhaseName(phase);
 o.resource=a.resourceId;o.routeLabel=a.routeLabel;o.quantity=a.quantity;
 if(goalAvail){o.delivered=goal.delivered;o.routePending=goal.hasPendingRequest&&goal.pendingCommand==RouteTravel;}
 o.handBackReturning=hb.returning;o.handBackCount=hb.status=="delivered"?hb.amount:0;
 if(phase!=Cancelled&&phase!=Failed&&phase!=Dormant&&(phase!=Complete||hb.holds)) {
  DWORD& due=nextDangerAt[a.id];
  if(!due||(LONG)(o.nowMs-due)>=0) {
   due=o.nowMs+2000;DangerFacts facts;
   std::vector<unsigned> quarry=a.agreedTargets;
   if(!ObserveDanger(world,a.actor,a.requester,quarry,goalAvail&&goal.hasTarget?goal.currentTarget:0,facts))facts=DangerFacts();
   lastDanger[a.id]=facts;
  }
  const DangerFacts& d=lastDanger[a.id];
  o.actorHealthValid=d.actorHealthValid;o.actorPercent=d.actorPercent;o.requesterHealthValid=d.requesterHealthValid;o.requesterPercent=d.requesterPercent;
  o.threatObserved=d.threatObserved;o.threatSerial=d.threatSerial;o.threatName=d.threatName;o.threatDistance=d.threatDistance;
 }
 std::vector<Events::Event> events;eventTracker.Observe(o,events);
 for(size_t n=0;n<events.size();++n)QueueActivityEvent(events[n].agreementId,a.actor,a.requester,static_cast<unsigned long>(now),events[n].json);
}
void Publish(GameWorld* world,Clock now) {
 std::vector<ActivityStatusSnapshot::Row> rows;
 std::map<std::string,ActivityStatusSnapshot::Row> byId;
 std::ostringstream legacy;legacy<<"[";bool legacyComma=false;
 bool invalidRow=false, indexTruncated=false, rowsTruncated=false;
 for(std::map<std::string,Agreement>::const_iterator i=accepted.begin();i!=accepted.end();++i){
  Phase phase;std::string reason;if(!runtime->Status(i->first,phase,reason)){
   std::map<std::string,std::string>::const_iterator denied=rejected.find(i->first);if(denied==rejected.end())continue;phase=Failed;reason=denied->second;
  }
  const bool clean=runtime->CleanupComplete(i->first);
  const bool ended=phase==Complete||phase==Cancelled||phase==Failed;
  GoalStatusSnapshot goal;const bool goalAvail=runtime->Snapshot(i->first,goal);
  // Hand-back (server switch `handback`): the published phase stays "handing_back" until the result
  // reached the requester or the NPC kept it; the terminal report is therefore never sent early.
  HandBackView hb;handBackHost.Step(i->second,phase==Complete,ended,clean,goalAvail?goal.delivered:0,hb);
  const char* shownPhase=hb.holds?"handing_back":(!clean&&ended?"cleanup_pending":PhaseName(phase));
  EmitEvents(world,now,i->second,phase,clean,goalAvail,goal,hb);
  if(legacyComma)legacy<<",";legacyComma=true;
  legacy<<"{\"id\":\""<<Stobe::Text::EscapeJSON(i->first)<<"\",\"worldId\":\""<<i->second.worldId
    <<"\",\"actor\":"<<i->second.actor<<",\"requester\":"<<i->second.requester
    <<",\"kind\":\""<<(i->second.kind==Hunt?"Hunt":i->second.kind==Mine?"Mine":"ClearGroup")
    <<"\",\"phase\":\""<<shownPhase
    <<"\",\"reason\":\""<<Stobe::Text::EscapeJSON(reason)<<"\",\"cleanupComplete\":"<<(clean?"true":"false")
    <<",\"gameTs\":"<<now<<",\"revision\":"<<revisions[i->first]
    <<",\"handBackStatus\":\""<<hb.status<<"\",\"handBackReason\":\""<<Stobe::Text::EscapeJSON(hb.reason)<<"\",\"handBackAmount\":"<<hb.amount<<"}";
  ActivityStatusSnapshot::Row row;
  row.id=i->second.id; row.worldId=i->second.worldId;
  row.revision=revisions[i->first]; row.actor=i->second.actor; row.requester=i->second.requester;
  row.kind=i->second.kind==Hunt?"Hunt":i->second.kind==Mine?"Mine":"ClearGroup";
  row.scopeVersion=i->second.scopeVersion; row.campQualified=i->second.campQualified;
  if(row.campQualified) {
   row.campZoneCandidateId=i->second.campZoneCandidateId;
   row.campZoneDigest=i->second.campZoneDigest;
   std::string campReason; row.campLiveProofValid=bindings && bindings->VerifyGrant(i->second,now,campReason);
  }
  row.sourceId=i->second.sourceId; row.resourceId=i->second.resourceId;
  row.quantity=i->second.quantity; row.agreedTargets=i->second.agreedTargets;
  row.routeCandidateId=i->second.routeCandidateId; row.routeWorldId=i->second.routeWorldId;
  row.routeKind=i->second.routeKind; row.routeLabel=i->second.routeLabel; row.routeActor=i->second.routeActor;
  row.phase=shownPhase;
  row.reason=reason; row.cleanupComplete=clean; row.gameTs=now;
  row.goalStateAvailable=goalAvail;
  if(row.goalStateAvailable) {
   row.hasTarget=goal.hasTarget; row.currentTarget=goal.currentTarget;
   row.currentCandidateId=goal.currentCandidateId; row.hasPendingAction=goal.hasPendingRequest;
   row.pendingCommand=goal.hasPendingRequest?CommandName(goal.pendingCommand):"";
   row.pendingRequestId=goal.pendingRequestId; row.delivered=goal.delivered; row.terminal=goal.terminal;
   row.completedTargets=goal.completedTargets; row.confirmedDeadTargets=goal.confirmedDeadTargets;
   row.nativeEvidenceAvailable=goal.nativeEvidenceAvailable;row.operationTracked=goal.operationTracked;
   row.nativeReceiptStatus=goal.nativeReceiptStatus;row.nativeReceiptReason=goal.nativeReceiptReason;
   row.nativeTaskName=goal.nativeTaskName;row.nativeActionName=goal.nativeActionName;
   row.nativeTarget=goal.nativeTarget;row.nativeTaskKey=goal.nativeTaskKey;
   row.nativeTaskSubject=goal.nativeTaskSubject;row.nativeActionKey=goal.nativeActionKey;
   row.nativeActionSubject=goal.nativeActionSubject;row.ownedTaskMatches=goal.ownedTaskMatches;
   row.currentActionMatchesTarget=goal.currentActionMatchesTarget;
   row.targetInFixedSetKnown=goal.targetInFixedSetKnown;row.targetInFixedSet=goal.targetInFixedSet;
   row.targetHostilityKnown=goal.targetHostilityKnown;row.currentTargetHostile=goal.currentTargetHostile;
   row.mineAttributionAvailable=goal.mineAttributionAvailable;row.mineLeaseIdentityMatches=goal.mineLeaseIdentityMatches;
   row.mineActor=goal.mineActor;row.mineBuilding=goal.mineBuilding;row.mineItem=goal.mineItem;
   row.mineOutputBaseline=goal.mineOutputBaseline;row.mineOutputExpected=goal.mineOutputExpected;
   row.mineOutputCount=goal.mineOutputCount;row.mineOutputCountConsistent=goal.mineOutputCountConsistent;
   row.mineCreditedOutput=goal.mineCreditedOutput;row.mineContributionObserved=goal.mineContributionObserved;
  }
  std::string encoded;
  if(!ActivityStatusSnapshot::SerializeRow(row,encoded)) {
   invalidRow=true; byId.clear(); rows.clear(); break;
  }
  if(byId.size()<ActivityStatusSnapshot::kMaxIndexedRows) byId[row.id]=row;
  else indexTruncated=true;
  if(rows.size()<=ActivityStatusSnapshot::kMaxRows) rows.push_back(row);
  else rowsTruncated=true;
 }
 legacy<<"]";
 std::string snapshot;
 const bool ok=!invalidRow&&ActivityStatusSnapshot::SerializeAll(currentEpoch,now,rows,snapshot,indexTruncated||rowsTruncated);
 AcquireSRWLockExclusive(&activityLock);publishedWorld=currentEpoch;publishedClock=now;
 publishedAtTick=GetTickCount();publishedRows.swap(byId);publishedRowsTruncated=indexTruncated;publishedRowsInvalid=invalidRow;
 publishedStatus=legacy.str();
 publishedObserverStatus=ok?snapshot:ActivityStatusSnapshot::Error("snapshot_unavailable");
 ReleaseSRWLockExclusive(&activityLock);
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
std::string ActivityControllerStatusJson(){
 AcquireSRWLockShared(&activityLock);std::string s=publishedStatus;ReleaseSRWLockShared(&activityLock);
 const std::string legacy=ActivityControllerStatusJsonV1Legacy();
 if(legacy.size()<=2)return s;if(s.size()<=2)return legacy;
 s.erase(s.size()-1);s+=legacy.substr(1);return s;
}
std::string ActivityControllerStatusSnapshotJson(const std::string& id){
 if(id.empty()) {
  std::string s,world;DWORD published;
  AcquireSRWLockShared(&activityLock);s=publishedObserverStatus;world=publishedWorld;published=publishedAtTick;ReleaseSRWLockShared(&activityLock);
  if(world.empty()||!published)return ActivityStatusSnapshot::Error("snapshot_unavailable");
  if(s.find("{\"error\":")==0)return s;
  std::string withAge;const DWORD age=GetTickCount()-published;
  return ActivityStatusSnapshot::AddSnapshotAge(s,age,withAge)?withAge:ActivityStatusSnapshot::Error("stale_snapshot");
 }
 if(!ActivityStatusSnapshot::ValidId(id)) return ActivityStatusSnapshot::Error("invalid_activity_id");
 ActivityStatusSnapshot::Row row;bool found=false,truncated=false,invalid=false;std::string world;DWORD published;
 AcquireSRWLockShared(&activityLock);
 world=publishedWorld;published=publishedAtTick;
 truncated=publishedRowsTruncated;invalid=publishedRowsInvalid;
 std::map<std::string,ActivityStatusSnapshot::Row>::const_iterator i=publishedRows.find(id);
 if(i!=publishedRows.end()){row=i->second;found=true;}
 ReleaseSRWLockShared(&activityLock);
 if(world.empty()||!published)return ActivityStatusSnapshot::Error("snapshot_unavailable");
 if(invalid)return ActivityStatusSnapshot::Error("snapshot_unavailable");
 if(!found)return ActivityStatusSnapshot::Error(truncated?"snapshot_index_truncated":"activity_not_found");
 std::string json,withAge;const DWORD age=GetTickCount()-published;
 if(!ActivityStatusSnapshot::SnapshotAgeValid(age))return ActivityStatusSnapshot::Error("stale_snapshot");
 if(!ActivityStatusSnapshot::SerializeOne(row,json)||!ActivityStatusSnapshot::AddSnapshotAge(json,age,withAge))
  return ActivityStatusSnapshot::Error("snapshot_unavailable");
 return withAge;
}
std::string CaptureActivityChatFacts(unsigned actor,unsigned requester){
 AcquireSRWLockShared(&activityLock);bool stable=!epochInvalid&&!publishedWorld.empty();ReleaseSRWLockShared(&activityLock);
 if(!stable||!bindings||!currentWorld||currentEpoch.empty())return "{}";
 return bindings->ProposalFacts(actor,requester);
}
void ResetActivityController(const char* reason){
 // Caller may already have an unstable world. Never dereference its objects.
 AcquireSRWLockExclusive(&activityLock);epochInvalid=true;publishedWorld.clear();publishedStatus="[]";publishedObserverStatus="{\"activities\":[],\"truncated\":false,\"unsupported\":[]}";publishedRows.clear();publishedRowsTruncated=false;publishedRowsInvalid=false;publishedClock=0;publishedAtTick=0;inbox.clear();ReleaseSRWLockExclusive(&activityLock);
 Stobe::Activity::ResetActivityTransport();
 ResetActivityControllerV1(reason);
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
  ResetMineLeases();accepted.clear();revisions.clear();rejected.clear();nextDecisionAt=0;handBackHost.Clear();eventTracker.Clear();nextDangerAt.clear();lastDanger.clear();
  AcquireSRWLockExclusive(&activityLock);epochInvalid=false;inbox.clear();ReleaseSRWLockExclusive(&activityLock);
 }
 bindings->Bind(world,currentEpoch,now);handBackHost.Bind(world,currentEpoch,now);
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
  nextDecisionAt=decisionNow+500;runtime->Tick(world,currentEpoch,now);lastStableClock=now;Publish(world,now);
 }
 UpdateActivityControllerV1(world);
 Stobe::Activity::UpdateActivityTransport();
}
