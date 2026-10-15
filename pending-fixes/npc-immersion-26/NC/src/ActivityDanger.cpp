#include "ActivityDanger.h"
#include "KenshiAiCompat.h"
#include <kenshi/Character.h>
#include <kenshi/GameWorld.h>
#include <kenshi/GameData.h>
#include <kenshi/MedicalSystem.h>
#include <kenshi/util/hand.h>
#include <algorithm>
#include <cmath>
#include <float.h>
#include <stdint.h>
namespace Stobe { namespace Activity {
DangerFacts::DangerFacts() : actorHealthValid(false),actorPercent(100),requesterHealthValid(false),requesterPercent(100),
 threatObserved(false),threatSerial(0),threatDistance(-1) {}
namespace {
// Worst of blood and the head/stomach/limb flesh fractions, 0..100. False when unreadable.
bool HealthPercent(Character* c,int& pct) {
 if(!c) return false;
 try {
  MedicalSystem* med=c->getMedical();
  if(!med || (uintptr_t)med<0x1000) return false;
  float maxBlood=med->getMaxBlood(); if(!(maxBlood>0.0f)) maxBlood=100.0f;
  float worst=100.0f*med->blood/maxBlood;
  MedicalSystem::HealthPartStatus* parts[6]={med->getPart((unsigned __int64)0),med->getPart((unsigned __int64)1),
   med->leftArm,med->rightArm,med->leftLeg,med->rightLeg};
  for(int i=0;i<6;++i) {
   MedicalSystem::HealthPartStatus* part=parts[i];
   if(!part || (uintptr_t)part<0x1000) continue;
   const float mx=part->maxHealth();
   if(mx>1.0f && _finite(mx) && _finite(part->flesh)) worst=std::min(worst,100.0f*part->flesh/mx);
  }
  if(!_finite(worst)) return false;
  pct=static_cast<int>(std::max(0.0f,std::min(100.0f,worst))+0.5f); return true;
 } catch(...) { return false; }
}
bool Listed(const std::vector<unsigned>& v,unsigned s) { return std::find(v.begin(),v.end(),s)!=v.end(); }
}
bool ObserveDanger(GameWorld* world,unsigned actorSerial,unsigned requesterSerial,const std::vector<unsigned>& quarry,
                   unsigned currentTarget,DangerFacts& out) {
 out=DangerFacts();
 if(!world || !actorSerial) return false;
 Character* actor=KenshiAi::ResolveCharacter(world,actorSerial);
 if(!actor || actor->getHandle().serial!=actorSerial) return false;
 Character* requester=requesterSerial?KenshiAi::ResolveCharacter(world,requesterSerial):NULL;
 if(requester && requester->getHandle().serial!=requesterSerial) requester=NULL;
 out.actorHealthValid=HealthPercent(actor,out.actorPercent);
 if(requester) out.requesterHealthValid=HealthPercent(requester,out.requesterPercent);
 try {
  lektor<RootObject*> objects;
  world->getObjectsWithinSphere(objects,actor->getPosition(),600.0f,CHARACTER,64,(RootObject*)actor);
  float best=FLT_MAX;
  for(unsigned i=0;i<objects.size();++i) {
   Character* c=(Character*)objects.stuff[i];
   if(!c || c==actor || c==requester) continue;
   try {
    const unsigned serial=c->getHandle().serial;
    if(!serial || serial==currentTarget || Listed(quarry,serial) || c->isDead() || c->isUnconcious()) continue;
    if(!actor->isEnemy(c,true)) continue;
    const hand victim=c->getAttackTarget();
    if(victim.serial!=actorSerial && (!requesterSerial || victim.serial!=requesterSerial)) continue;
    const float d2=actor->getPosition().squaredDistance(c->getPosition());
    if(!_finite(d2) || d2>=best) continue;
    best=d2; out.threatObserved=true; out.threatSerial=serial; out.threatName=c->getName();
    out.threatDistance=static_cast<int>(std::sqrt(d2));
   } catch(...) {}
  }
 } catch(...) {}
 return true;
}
} }
