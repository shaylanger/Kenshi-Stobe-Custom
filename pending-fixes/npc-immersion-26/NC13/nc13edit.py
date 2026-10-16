# NC13 = NC12 + ACTIVITY_SIGHT_DIAG (diagnostic only, no behaviour change).
# Usage: python3 nc13edit.py <NC12-tree-root>   (root contains src/ and legacy-v1/); edits src/ActivityRuntimeBindings.cpp only.
import sys,io
root=sys.argv[1]
def edit(path,old,new,count=1):
    p=root+'/'+path
    s=io.open(p,'r',encoding='utf-8',newline='').read()
    crlf='\r\n' in s
    if crlf:
        old=old.replace('\n','\r\n'); new=new.replace('\n','\r\n')
    assert s.count(old)==count,(path,old[:60],s.count(old))
    s=s.replace(old,new)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
P='src/ActivityRuntimeBindings.cpp'

# 1. trace members + ctor init
edit(P,'const char* gate; std::string actorSid,requesterSid;\n',
 'const char* gate; std::string actorSid,requesterSid;\n'
 ' unsigned huntEmitted,animals; bool scanned; double hour; std::vector<std::string> animalLines; // NC13 ACTIVITY_SIGHT_DIAG\n')
edit(P,'charSphere(0),buildingSphere(0),gate("world") {}','charSphere(0),buildingSphere(0),gate("world"),huntEmitted(0),animals(0),scanned(false),hour(-1.0) {}')

# 2. per-animal collector + summary logger (before the destructor)
edit(P,' ~ProposalTrace() {\n  try {\n   if(emitted) return;\n',
r''' // NC13: diagnostic only. Reads sensory state of one animal; never alters the proposal outcome.
 void Animal(Character* a,Character* t,bool haveVisible,bool visible) {
  try {
   ++animals; if(animalLines.size()>=8) return;
   std::ostringstream s; s<<"serial="<<t->getHandle().serial;
   try { const Ogre::Vector3 ap=a->getPosition(),tp=t->getPosition(); const double dx=ap.x-tp.x,dy=ap.y-tp.y,dz=ap.z-tp.z; s<<" dist="<<sqrt(dx*dx+dy*dy+dz*dz); } catch(...) { s<<" dist=err"; }
   try { s<<" dead="<<t->isDead()<<" ko="<<t->isUnconcious(); } catch(...) { s<<" dead=err"; }
   SensoryData* sd=a->getSensoryData();
   if(!sd) { s<<" sd=null"; }
   else {
    if(haveVisible) s<<" canISee="<<visible; else s<<" canISee=n/a";
    try { s<<" canIHear="<<sd->canIHearThisGuy(t); } catch(...) { s<<" canIHear=err"; }
    try { SeenSomeone* d=sd->getDataFor(t); if(d) s<<" data=1 dCanSee="<<d->canSee<<" dCanHear="<<d->canHear<<" fov="<<d->FOVScore; else s<<" data=0"; } catch(...) { s<<" data=err"; }
   }
   animalLines.push_back(s.str());
  } catch(...) { }
 }
 void SightDiag(Character* a,Character* r) {
  try {
   if(huntEmitted || !scanned) return;
   static std::map<unsigned,DWORD> lastSight; const DWORD now=GetTickCount();
   std::map<unsigned,DWORD>::iterator it=lastSight.find(actor);
   if(it!=lastSight.end() && now-it->second<5000) return;
   lastSight[actor]=now;
   std::ostringstream s; s<<"ACTIVITY_SIGHT_DIAG actor="<<actor<<" requester="<<requester<<" hour="<<hour
    <<" sphereCharacter="<<charSphere<<" animals="<<animals<<" logged="<<animalLines.size()<<" sightDrops="<<sightDrops<<" typeDrops="<<typeDrops
    <<" emitted="<<emitted<<" huntEmitted="<<huntEmitted;
   try { SensoryData* sd=a?a->getSensoryData():NULL; if(sd) s<<" actorSeen="<<sd->seen.size()<<" actorVision="<<sd->getVisionRange(false)<<" actorVisionTown="<<sd->getVisionRange(true); else s<<" actorSd=null"; } catch(...) { s<<" actorSd=err"; }
   try { SensoryData* sd=r?r->getSensoryData():NULL; if(sd) s<<" requesterSeen="<<sd->seen.size()<<" requesterVision="<<sd->getVisionRange(false); else s<<" requesterSd=null"; } catch(...) { s<<" requesterSd=err"; }
   Log(s.str());
   for(size_t i=0;i<animalLines.size();++i) { std::ostringstream l; l<<"ACTIVITY_SIGHT_DIAG animal actor="<<actor<<" "<<animalLines[i]; Log(l.str()); }
  } catch(...) { }
 }
 ~ProposalTrace() {
  try {
   if(emitted) return;
''')

# 3. pass 0: scanned flag, animal collection (before and after the sight gate), hunt counter, hour
edit(P,'if(pass) trace.buildingSphere=objects.size(); else trace.charSphere=objects.size();','if(pass) trace.buildingSphere=objects.size(); else { trace.charSphere=objects.size(); trace.scanned=true; }')
edit(P,'''     if(target==actor || target==requester || !actor->getSensoryData()) { ++trace.sightDrops; continue; }
     const bool visible=actor->getSensoryData()->canISeeThisGuy(target);
     if(!visible) { ++trace.sightDrops; continue; }''','''     if(target==actor || target==requester || !actor->getSensoryData()) { if(target!=actor && target!=requester && target->isAnimal()) trace.Animal(actor,target,false,false); ++trace.sightDrops; continue; }
     const bool visible=actor->getSensoryData()->canISeeThisGuy(target);
     if(target->isAnimal()) trace.Animal(actor,target,true,visible);
     if(!visible) { ++trace.sightDrops; continue; }''')
edit(P,"++emitted; trace.emitted=emitted; std::ostringstream fixedTargets;","++emitted; trace.emitted=emitted; if(kind[0]=='H') ++trace.huntEmitted; std::ostringstream fixedTargets;")
edit(P," ProposalTrace trace(actorSerial,requesterSerial,candidates_.size());\n"," ProposalTrace trace(actorSerial,requesterSerial,candidates_.size());\n try { trace.hour=fmod(world_->getTimeStamp_inGameHours().getTotalHours(),24.0); } catch(...) {}\n")
