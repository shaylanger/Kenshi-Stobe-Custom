import sys
p='/mnt/c/KenshiTestRuns/imm26-nc7/src/ActivityRuntimeBindings.cpp'
s=open(p,'rb').read().decode('utf-8')
crlf='\r\n' in s
s=s.replace('\r\n','\n')
def rep(old,new):
    global s
    assert s.count(old)==1,(old,s.count(old))
    s=s.replace(old,new)
rep('#include <float.h>\nnamespace Stobe { namespace Activity {','#include <float.h>\n#include <windows.h>\nvoid Log(const std::string&);\nnamespace Stobe { namespace Activity {')
trace='''namespace {
// NC7: ACTIVITY_PROPOSAL_DIAG, emitted (rate-limited per actor) whenever a proposal attempt yields zero candidates.
// Diagnostic only: counts and logs, never changes the proposal outcome.
struct ProposalTrace {
 unsigned actor,requester; size_t registry; unsigned emitted,exceptions,objects,sightDrops,pathDrops,capacityDrops,reused,nullDrops,finiteDrops,typeDrops,serialDrops,pathZero,pathOne,pathOther,mineTypeDrops;
 bool world,actorOk,requesterOk,player,distinct,dead,unconscious,movement,avatar,navmesh,onmesh;
 unsigned charSphere,buildingSphere; const char* gate; std::string actorSid,requesterSid;
 ProposalTrace(unsigned a,unsigned r,size_t n):actor(a),requester(r),registry(n),emitted(0),exceptions(0),objects(0),sightDrops(0),pathDrops(0),capacityDrops(0),reused(0),nullDrops(0),finiteDrops(0),typeDrops(0),serialDrops(0),pathZero(0),pathOne(0),pathOther(0),mineTypeDrops(0),world(false),actorOk(false),requesterOk(false),player(false),distinct(false),dead(false),unconscious(false),movement(false),avatar(false),navmesh(false),onmesh(false),charSphere(0),buildingSphere(0),gate("world") {}
 void Sids(Character* a,Character* r) { try { Character* chars[2]={a,r}; std::string* slots[2]={&actorSid,&requesterSid}; for(unsigned n=0;n<2;++n) { try { if(chars[n] && chars[n]->getGameData()) { *slots[n]=chars[n]->getGameData()->stringID.substr(0,256); for(size_t i=0;i<slots[n]->size();++i) if((*slots[n])[i]<32) (*slots[n])[i]='_'; } } catch(...) {} } } catch(...) {} }
 ~ProposalTrace() {
  try {
   if(emitted) return;
   static std::map<unsigned,DWORD> last; const DWORD now=GetTickCount();
   std::map<unsigned,DWORD>::iterator it=last.find(actor);
   if(it!=last.end() && now-it->second<5000) return;
   last[actor]=now;
   std::ostringstream s; s<<"ACTIVITY_PROPOSAL_DIAG actor="<<actor<<" requester="<<requester<<" gate="<<gate
   <<" world="<<world<<" actorOk="<<actorOk<<" requesterOk="<<requesterOk<<" player="<<player<<" distinct="<<distinct
   <<" dead="<<dead<<" unconscious="<<unconscious<<" actorSID="<<actorSid<<" requesterSID="<<requesterSid
   <<" movement="<<movement<<" avatar="<<avatar<<" navmesh="<<navmesh<<" onmesh="<<onmesh
   <<" sphereCharacter="<<charSphere<<" sphereBuilding="<<buildingSphere<<" sphereCap=96 objects="<<objects
   <<" sightDrops="<<sightDrops<<" typeDrops="<<typeDrops<<" mineTypeDrops="<<mineTypeDrops<<" pathDrops="<<pathDrops
   <<" registryBefore="<<registry<<" capacityDrops="<<capacityDrops<<" reused="<<reused<<" nullDrops="<<nullDrops
   <<" finiteDrops="<<finiteDrops<<" serialDrops="<<serialDrops<<" pathZero="<<pathZero<<" pathOne="<<pathOne<<" pathOther="<<pathOther
   <<" exceptions="<<exceptions<<" emitted="<<emitted;
   Log(s.str()); } catch(...) { /* Diagnostics never change proposal outcome. */ }
 }
};
}
std::string ConcreteRuntimeBindings::ProposalFacts('''
rep('std::string ConcreteRuntimeBindings::ProposalFacts(',trace)
a=s.index('std::string ConcreteRuntimeBindings::ProposalFacts(')
head,body=s[:a],s[a:]
def b(old,new):
    global body
    assert body.count(old)==1,(old,body.count(old))
    body=body.replace(old,new)
E='{\\"candidates\\":[]}'
b('std::ostringstream out; out << "{\\"candidates\\":["; bool first=true;','ProposalTrace trace(actorSerial,requesterSerial,candidates_.size());\n std::ostringstream out; out << "{\\"candidates\\":["; bool first=true;')
b(' if(!world_ || worldId_.empty()) return "'+E+'";',' trace.world=world_!=NULL && !worldId_.empty();\n if(!trace.world) return "'+E+'";')
b(' if(!actor || !requester) return "'+E+'";\n if(!requester->isPlayerCharacter() || actor==requester || actor->isDead() || actor->isUnconcious()) return "'+E+'";',
 ' trace.gate="identity"; trace.actorOk=actor!=NULL; trace.requesterOk=requester!=NULL; trace.Sids(actor,requester);\n if(!actor || !requester) return "'+E+'";\n trace.player=requester->isPlayerCharacter(); trace.distinct=actor!=requester; trace.dead=actor->isDead(); trace.unconscious=actor->isUnconcious();\n if(!trace.player || !trace.distinct || trace.dead || trace.unconscious) return "'+E+'";')
b(' if(!world_->navmesh || !avatar) return "'+E+'";\n if(!avatar->isOnNavmesh()) return "'+E+'";',
 ' trace.gate="navigation"; trace.movement=movement!=NULL; trace.avatar=avatar!=NULL; trace.navmesh=world_->navmesh!=NULL;\n if(!world_->navmesh || !avatar) return "'+E+'";\n trace.onmesh=avatar->isOnNavmesh(); if(!trace.onmesh) return "'+E+'";\n trace.gate="enumeration";')
b('  for(unsigned i=0;i<objects.size() && emitted<32;++i) {\n   try {\n    RootObject* object=objects.stuff[i]; if(!object || !object->getGameData()) continue;',
 '  if(pass) trace.buildingSphere=objects.size(); else trace.charSphere=objects.size();\n  for(unsigned i=0;i<objects.size() && emitted<32;++i) {\n   ++trace.objects;\n   try {\n    RootObject* object=objects.stuff[i]; if(!object || !object->getGameData()) { ++trace.nullDrops; continue; }')
b('if(!_finite(p.x)||!_finite(p.y)||!_finite(p.z)) continue;','if(!_finite(p.x)||!_finite(p.y)||!_finite(p.z)) { ++trace.finiteDrops; continue; }')
b('if(target==actor || target==requester || !actor->getSensoryData()) continue;','if(target==actor || target==requester || !actor->getSensoryData()) { ++trace.sightDrops; continue; }')
b('     if(!visible) continue;','     if(!visible) { ++trace.sightDrops; continue; }')
b('if(!target->isAnimal() && !hostile) continue;','if(!target->isAnimal() && !hostile) { ++trace.typeDrops; continue; }')
b('|| b->_NV_isDestroyed()) continue;','|| b->_NV_isDestroyed()) { ++trace.mineTypeDrops; continue; }')
b('    const int rawPath=world_->navmesh->pathExists(avatar,p);\n    if(rawPath!=1) continue;\n    const unsigned serial=object->getHandle().serial;\n    if(!serial) continue;',
 '    const int rawPath=world_->navmesh->pathExists(avatar,p);\n    if(rawPath==0) ++trace.pathZero; else if(rawPath==1) ++trace.pathOne; else ++trace.pathOther;\n    if(rawPath!=1) { ++trace.pathDrops; continue; }\n    const unsigned serial=object->getHandle().serial;\n    if(!serial) { ++trace.serialDrops; continue; }')
b('if(!stableToken.empty()) token<<stableToken;','if(!stableToken.empty()) { token<<stableToken; ++trace.reused; }')
b('if(candidates_.size()>=2048) continue;','if(candidates_.size()>=2048) { ++trace.capacityDrops; continue; }')
b("if(!first) out<<','; first=false; ++emitted;","if(!first) out<<','; first=false; ++emitted; trace.emitted=emitted;")
b('} catch(...) { /* One unloaded','} catch(...) { ++trace.exceptions; /* One unloaded')
b(' out << "]}"; return out.str();',' trace.gate="complete"; out << "]}"; return out.str();')
s=head+body
if crlf: s=s.replace('\n','\r\n')
open(p,'wb').write(s.encode('utf-8'))
print('ok')
