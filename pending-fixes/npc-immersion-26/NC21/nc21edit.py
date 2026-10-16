#!/usr/bin/env python3
"""NC21 = NC20 + participation proof binds with the hand_<serial> identity (row 13-c participation_bound=0).
Usage: python3 nc21edit.py <tree>   (tree has src/; run on the NC20 tree; copy ParticipationIdentity.h into src/ first).
Cause: Character::getInstanceID() is RootObject's (returns NULL for every Character), so the uid was always empty and
ParticipationEvidence::Begin refused to bind. Fix: use the id the rest of the mod/server already use (uid else hand_<serial>).
Also: Begin takes the actor Character* the caller already holds; the proof logs why it bound / why it did not qualify."""
import sys, io, os
tree = sys.argv[1]
assert os.path.exists(tree + "/src/ParticipationIdentity.h"), "copy ParticipationIdentity.h into src/ first"

def load(p):
    s = io.open(p, encoding="utf-8", newline="").read()
    return s, ("\r\n" if "\r\n" in s else "\n")

def sub(s, nl, old, new):
    old = old.replace("\n", nl); new = new.replace("\n", nl)
    assert s.count(old) == 1, "anchor count %d: %r" % (s.count(old), old[:90])
    return s.replace(old, new)

# ---------------- ParticipationEvidence.h ----------------
p = tree + "/src/ParticipationEvidence.h"
s, nl = load(p)
s = sub(s, nl, '#include "StobeText.h"\n', '#include "StobeText.h"\n#include "ParticipationIdentity.h"\n')
s = sub(s, nl, ' std::string world, agreement, task, actorStorage, partnerStorage, actorName, partnerName, frozen;\n',
        ' std::string world, agreement, task, actorStorage, partnerStorage, actorName, partnerName, frozen, bindWhy;\n')
# Diagnostics: why a run of samples was broken and the best continuous run seen (verification without a rig).
# Break reasons: 0 other, 1 separation>35, 2 sample gap>10 s / clock back, 3 state (handle/dead/ko/identity), 4 jump (teleport), 5 scope.
s = sub(s, nl, ' long long first, last;\n', ' long long first, last, bestSpan;\n unsigned brk[6];\n')
s = sub(s, nl, 'lastProgress(0),first(0),last(0),\n', 'lastProgress(0),first(0),last(0),bestSpan(0),\n')
s = sub(s, nl, 'travel(false),bound(false) {}\n', 'travel(false),bound(false) {for(int i=0;i<6;++i)brk[i]=0;}\n')
s = sub(s, nl, ' void Break() {samples=progressSamples=0;', ' void Break(int why=0) {++brk[why];samples=progressSamples=0;')
s = sub(s, nl, ''' void Begin(GameWorld*w,unsigned a,unsigned p,const std::string&wi,const std::string&ag,const std::string&ta,bool trip,const Ogre::Vector3&end) {
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
''', ''' // NC21: Character::getInstanceID() is RootObject's and returns NULL for every Character (only Building overrides it), so a
 // uid-only identity can never bind. Same id as Context.cpp GetStorageIDFor / the server's core_npc.storage_id: uid if the
 // engine ever provides one, else hand_<serial>. Identity stays pinned by the exact hand compared in Sample.
 static std::string StorageIdOf(Character*c) {
  InstanceID*i=c->getInstanceID();
  const std::string*uid=(i&&!i->uid.empty())?&i->uid:0;
  return Identity::StorageId(uid,c->getHandle().serial);
 }
 // actorHint: the actor Character* the caller already holds (avoids depending on the handle cache for the actor).
 void Begin(GameWorld*w,unsigned a,unsigned p,const std::string&wi,const std::string&ag,const std::string&ta,bool trip,const Ogre::Vector3&end,Character*actorHint=0) {
  *this=Evidence();actor=a;partner=p;world=wi;agreement=ag;task=ta;travel=trip;endpoint=end;bindWhy="exception";
  try {
   Character*ac=(actorHint&&actorHint->getHandle().serial==a)?actorHint:KenshiAi::ResolveCharacter(w,a);
   Character*pc=KenshiAi::ResolveCharacter(w,p);
   const std::string aid=ac?StorageIdOf(ac):std::string(),pid=pc?StorageIdOf(pc):std::string();
   const Identity::Verdict v=Identity::Decide(ac!=0,pc!=0,a,p,!wi.empty()&&!ag.empty()&&!ta.empty(),aid,pid);
   bindWhy=Identity::VerdictName(v,aid);
   if(v!=Identity::BIND_OK)return;
   actorStorage=aid;partnerStorage=pid;actorName=ac->getName();partnerName=pc->getName();
   actorHandle=ac->getHandle();partnerHandle=pc->getHandle();bound=true;
  }catch(...){bound=false;bindWhy="exception";}
 }
''')
s = sub(s, nl, 'if(!bound||wi!=world||now<0){Break();return;}', 'if(!bound||wi!=world||now<0){Break(5);return;}')
s = sub(s, nl, 'a->isDead()||p->isDead()||a->isUnconcious()||p->isUnconcious()){Break();return;}',
        'a->isDead()||p->isDead()||a->isUnconcious()||p->isUnconcious()){Break(3);return;}')
s = sub(s, nl, '''   InstanceID*ai=a->getInstanceID();InstanceID*pi=p->getInstanceID();
   if(!ai||!pi||ai->uid!=actorStorage||pi->uid!=partnerStorage){bound=false;Break();return;}
''', '''   if(StorageIdOf(a)!=actorStorage||StorageIdOf(p)!=partnerStorage){bound=false;Break(3);return;}
''')
s = sub(s, nl, 'if(separation>35.0){Break();return;}', 'if(separation>35.0){Break(1);return;}')
s = sub(s, nl, 'if(samples && (now<last||now-last>10||progress<lastProgress))Break();', 'if(samples && (now<last||now-last>10||progress<lastProgress))Break(2);')
s = sub(s, nl, 'if(ad>20.0*(now-last)+5.0||pd>20.0*(now-last)+5.0)Break();', 'if(ad>20.0*(now-last)+5.0||pd>20.0*(now-last)+5.0)Break(4);')
s = sub(s, nl, 'if(separation>maxSeparation)maxSeparation=separation;\n', 'if(separation>maxSeparation)maxSeparation=separation;\n   if(last-first>bestSpan)bestSpan=last-first;\n')
s = sub(s, nl, ' static std::string Q(const std::string&s){', ''' // One token (no spaces) for the NATIVE_TRAVEL log: why a proof did or did not qualify.
 std::string Diag()const {
  std::ostringstream o;o<<"samples:"<<samples<<",span:"<<(last-first)<<",best_span:"<<bestSpan<<",actor_d:"<<(long long)actorDistance
   <<",partner_d:"<<(long long)partnerDistance<<",progress:"<<(long long)endpointProgress<<",max_sep:"<<(long long)maxSeparation
   <<",brk_sep:"<<brk[1]<<",brk_jump:"<<brk[4]<<",brk_gap:"<<brk[2]<<",brk_state:"<<brk[3]<<",brk_scope:"<<brk[5]<<",brk_other:"<<brk[0];
  return o.str();
 }
 static std::string Q(const std::string&s){''')
io.open(p, "w", encoding="utf-8", newline="").write(s)

# ---------------- NativeTravelLifecycle.cpp ----------------
p = tree + "/src/NativeTravelLifecycle.cpp"
s, nl = load(p)
s = sub(s, nl, '      r.participation.Begin(world, serial, speaker, expectedWorld, agreement, r.task, true, Ogre::Vector3(x,y,z));\n',
        '      r.participation.Begin(world, serial, speaker, expectedWorld, agreement, r.task, true, Ogre::Vector3(x,y,z), actor);\n')
s = sub(s, nl, '''          " captured=" + (captured ? "1" : "0") + " participation_bound=" + (r.participation.bound ? "1" : "0"));
''', '''          " captured=" + (captured ? "1" : "0") + " participation_bound=" + (r.participation.bound ? "1" : "0") +
          " participation_why=" + r.participation.bindWhy +
          " participation_ids=" + (r.participation.bound ? r.participation.actorStorage + "," + r.participation.partnerStorage : std::string("-")));
''')
s = sub(s, nl, '''            r.participation.Begin(world, r.actor, r.speaker, r.world, r.agreement, r.task, true,
              Ogre::Vector3(routeTarget->second.x, routeTarget->second.y, routeTarget->second.z));
            r.partBegun = true;
''', '''            r.participation.Begin(world, r.actor, r.speaker, r.world, r.agreement, r.task, true,
              Ogre::Vector3(routeTarget->second.x, routeTarget->second.y, routeTarget->second.z));
            r.partBegun = true;
            Log("NATIVE_TRAVEL_PART_BIND: task=" + r.task + " actor=" + Number(r.actor) + " participation_bound=" +
                (r.participation.bound ? "1" : "0") + " participation_why=" + r.participation.bindWhy +
                " participation_ids=" + (r.participation.bound ? r.participation.actorStorage + "," + r.participation.partnerStorage : std::string("-")));
''')
s = sub(s, nl, '''                   " participation_qualified=" + (r.partBegun && r.participation.frozen.find("\\"qualified\\":true") != std::string::npos ? "1" : "0"));
''', '''                   " participation_qualified=" + (r.partBegun && r.participation.frozen.find("\\"qualified\\":true") != std::string::npos ? "1" : "0") +
                   " participation_diag=" + (r.partBegun ? r.participation.Diag() : std::string("-")));
''')
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("NC21 edit applied to " + tree)
