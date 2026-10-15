#pragma once
// Main-thread-only observer. No AI commands, timers, persistence or rewards.
#include "KenshiAiCompat.h"
#include "StobeText.h"
#include <kenshi/Character.h>
#include <kenshi/InstanceID.h>
#include <cmath>
#include <float.h>
#include <sstream>

namespace Stobe { namespace Participation {
struct Evidence {
 std::string world, agreement, task, actorStorage, partnerStorage, actorName, partnerName, frozen;
 hand actorHandle, partnerHandle;
 unsigned actor, partner, samples, progressSamples, lastProgress;
 long long first, last;
 double actorDistance, partnerDistance, endpointProgress, maxSeparation, firstEndpoint;
 Ogre::Vector3 actorPos, partnerPos, endpoint;
 bool travel, bound;
 Evidence():actor(0),partner(0),samples(0),progressSamples(0),lastProgress(0),first(0),last(0),
 actorDistance(0),partnerDistance(0),endpointProgress(0),maxSeparation(0),firstEndpoint(0),travel(false),bound(false) {}
 static bool Same(const hand&a,const hand&b) {return a.serial==b.serial&&a.index==b.index&&a.type==b.type&&a.container==b.container&&a.containerSerial==b.containerSerial;}
 static bool Finite(const Ogre::Vector3&p) {return _finite(p.x)&&_finite(p.y)&&_finite(p.z);}
 static double Distance(const Ogre::Vector3&a,const Ogre::Vector3&b) {double x=a.x-b.x,y=a.y-b.y,z=a.z-b.z;return std::sqrt(x*x+y*y+z*z);}
 void Break() {samples=progressSamples=0;first=last=0;actorDistance=partnerDistance=endpointProgress=maxSeparation=0;}
 void Begin(GameWorld*w,unsigned a,unsigned p,const std::string&wi,const std::string&ag,const std::string&ta,bool trip,const Ogre::Vector3&end) {
  *this=Evidence();actor=a;partner=p;world=wi;agreement=ag;task=ta;travel=trip;endpoint=end;
  try {
   Character*ac=KenshiAi::ResolveCharacter(w,a);Character*pc=KenshiAi::ResolveCharacter(w,p);
   if(!ac||!pc||a==p||wi.empty()||ag.empty()||ta.empty())return;
   InstanceID*ai=ac->getInstanceID();InstanceID*pi=pc->getInstanceID();
   // Never use name or session-local hand_ fallback as durable identity.
   if(!ai||!pi||ai->uid.empty()||pi->uid.empty()||ai->uid==pi->uid)return;
   actorStorage=ai->uid;partnerStorage=pi->uid;actorName=ac->getName();partnerName=pc->getName();
   actorHandle=ac->getHandle();partnerHandle=pc->getHandle();bound=true;
  }catch(...){bound=false;}
 }
 void Sample(GameWorld*w,const std::string&wi,long long now,unsigned progress) {
  if(!frozen.empty())return;
  try {
   if(!bound||wi!=world||now<0){Break();return;}
   Character*a=KenshiAi::ResolveCharacter(w,actor);Character*p=KenshiAi::ResolveCharacter(w,partner);
   if(!a||!p||!Same(a->getHandle(),actorHandle)||!Same(p->getHandle(),partnerHandle)||
      a->isDead()||p->isDead()||a->isUnconcious()||p->isUnconcious()){Break();return;}
   InstanceID*ai=a->getInstanceID();InstanceID*pi=p->getInstanceID();
   if(!ai||!pi||ai->uid!=actorStorage||pi->uid!=partnerStorage){bound=false;Break();return;}
   const Ogre::Vector3 ap=a->getPosition(),pp=p->getPosition();
   if(!Finite(ap)||!Finite(pp)||!Finite(endpoint)){Break();return;}
   const double separation=Distance(ap,pp),remaining=Distance(ap,endpoint);
   if(separation>35.0){Break();return;}
   if(samples && (now<last||now-last>10||progress<lastProgress))Break();
   if(samples&&now==last)return; // Frames while paused are not participation time.
   if(samples) {
    double ad=Distance(ap,actorPos),pd=Distance(pp,partnerPos);
    if(ad>20.0*(now-last)+5.0||pd>20.0*(now-last)+5.0)Break();
    else {actorDistance+=ad;partnerDistance+=pd;if(progress>lastProgress)++progressSamples;}
   }
   if(!samples){first=now;firstEndpoint=remaining;lastProgress=progress;}
   ++samples;last=now;actorPos=ap;partnerPos=pp;lastProgress=progress;
   endpointProgress=firstEndpoint-remaining;if(separation>maxSeparation)maxSeparation=separation;
  }catch(...){Break();}
 }
 static std::string Q(const std::string&s){return std::string("\"")+Text::EscapeJSON(s)+"\"";}
 void Freeze(bool completed,long long now) {
  if(!frozen.empty())return;
  bool qualified=completed&&bound&&samples>=4&&now>=last&&now-last<=2&&last-first>=30&&
    (travel?(actorDistance>=30&&partnerDistance>=30&&endpointProgress>=30):(progressSamples>=2&&partnerDistance>=5));
  std::ostringstream o;o<<"{\"schema_version\":1,\"mode\":"<<Q(travel?"travel_accompaniment":"activity_accompaniment")
   <<",\"qualified\":"<<(qualified?"true":"false")<<",\"conscious_alive_all\":"<<(qualified?"true":"false")
   <<",\"world_id\":"<<Q(world)<<",\"agreement_id\":"<<Q(agreement)<<",\"task_id\":"<<Q(task)
   <<",\"actor_serial\":"<<actor<<",\"partner_serial\":"<<partner
   <<",\"actor_storage_id\":"<<Q(actorStorage)<<",\"partner_storage_id\":"<<Q(partnerStorage)
   <<",\"actor_name\":"<<Q(actorName)<<",\"partner_name\":"<<Q(partnerName)
   <<",\"first_gamets\":"<<first<<",\"last_gamets\":"<<last<<",\"terminal_gamets\":"<<now
   <<",\"qualified_samples\":"<<samples<<",\"progress_samples\":"<<progressSamples
   <<",\"actor_distance\":"<<actorDistance<<",\"partner_distance\":"<<partnerDistance
   <<",\"endpoint_progress\":"<<endpointProgress<<",\"max_separation\":"<<maxSeparation<<"}";frozen=o.str();
 }
 std::string Json()const{return frozen.empty()?"{\"schema_version\":1,\"qualified\":false}":frozen;}
};
} }
