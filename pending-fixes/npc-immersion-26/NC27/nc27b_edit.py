#!/usr/bin/env python3
"""NC27 part B (imm26-huntA1, Shay 2026-10-16): when an agreed activity FAILS the NPC says so right away (the line carries the reason).
Usage: python3 nc27b_edit.py <tree-root>     (tree-root contains src/; idempotent: a second run refuses)
Path (no parallel channel): terminal `report` (status failed, allow-listed reason, already sent today) -> server stores the situated event
(plan_changed + outcome text with the reason) -> NEW: after the server ACCEPTED the failed report, ActivityTransport queues an
EndingSpeechRequest; the game thread (UpdateActivityController) asks the actor for one targeted optional turn via the existing
Stobe::UI::TriggerOptionalBoredTurn (same call the N2 proximity watch uses); the server's bored.php claims the event and the NPC speaks.
Retry/expiry policy: src/ActivityEndingSpeech.h (unit-tested).
"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
MARK = 'NC27B'

def load(rel):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return p, (s.replace('\r\n', '\n') if crlf else s), crlf

def edit(rel, pairs):
    p, s, crlf = load(rel)
    if MARK in s:
        print(rel + ': already applied (NC27B marker)'); return False
    for a, b in pairs:
        assert s.count(a) == 1, rel + ': anchor missing or duplicated: ' + a[:90]
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)
    print(rel + ': patched'); return True

changed = []
changed.append(edit('src/ActivityTransport.h', [
("#include <string>\n", "#include <string>\n#include <vector>\n"),
("void UpdateActivityTransport();",
 """// NC27B: a FAILED activity's terminal report was accepted by the server (the failure outcome is stored as a situated event there).
// Game thread drains these and asks the actor for the "I am giving up" line. Bounded (16), cleared on reset.
struct EndingSpeechRequest { std::string agreementId; unsigned actor, requester; EndingSpeechRequest():actor(0),requester(0){} };
bool TakeEndingSpeech(std::vector<EndingSpeechRequest>& out);
void UpdateActivityTransport();"""),
]))
changed.append(edit('src/ActivityTransport.cpp', [
(" std::vector<unsigned long long> acknowledgements;\n std::string world; Clock now;",
 " std::vector<unsigned long long> acknowledgements;\n std::vector<EndingSpeechRequest> endingSpeech; // NC27B\n std::string world; Clock now;"),
("S().reported.clear();S().acknowledgements.clear();S().lastPoll=0;S().polling=false;}",
 "S().reported.clear();S().acknowledgements.clear();S().endingSpeech.clear();S().lastPoll=0;S().polling=false;}"),
("  if(SignedRequest(report.str(),job.turn.epoch,response)){Lock lock;if(S().world==job.turn.world)S().reported[id]=revision;}\n",
 """  if(SignedRequest(report.str(),job.turn.epoch,response)){Lock lock;if(S().world==job.turn.world){S().reported[id]=revision;
   // NC27B: the server accepted a FAILED terminal report -> the NPC must say it gives up (and why) without waiting for a random bored turn.
   if(phase=="failed" && S().endingSpeech.size()<16){EndingSpeechRequest e;e.agreementId=id;e.actor=context.actor;e.requester=context.requester;S().endingSpeech.push_back(e);}}}
"""),
("void QueueActivityEvent(const std::string& agreementId,unsigned actor,unsigned requester,unsigned long gameNow,const std::string& eventJson) {",
 "bool TakeEndingSpeech(std::vector<EndingSpeechRequest>& out) {Lock lock;if(S().endingSpeech.empty())return false;out.insert(out.end(),S().endingSpeech.begin(),S().endingSpeech.end());S().endingSpeech.clear();return true;}\nvoid QueueActivityEvent(const std::string& agreementId,unsigned actor,unsigned requester,unsigned long gameNow,const std::string& eventJson) {"),
]))
changed.append(edit('src/ActivityController.cpp', [
('#include "Utils.h"\n',
 '#include "Utils.h"\n#include "ActivityEndingSpeech.h" // NC27B\n#include "AudioPlayback.h"\n#include "ChatBox.h"\n#include "Globals.h"\n#include "Interaction.h"\n#include "KenshiAiCompat.h"\n#include <kenshi/Character.h>\n#include <kenshi/GameWorld.h>\n'),
("}\n}\nbool QueueActivityGrant(const Stobe::Activity::Agreement& grant,unsigned revision){\n",
 """}
// NC27B (Shay 2026-10-16): when an activity FAILS the NPC tells the requester at once that it gives up and why (a Hunt that found nothing,
// timed out, lost its target...). The server stored the outcome (with the reason) as a situated event when it accepted the failed report;
// here the game thread asks for ONE targeted optional turn, the same path the N2 proximity watch uses, instead of waiting for a random
// bored turn. Retry/expiry policy: ActivityEndingSpeech.h.
struct EndingSpeechJob { Stobe::Activity::EndingSpeechRequest r; DWORD queued, due; };
std::deque<EndingSpeechJob> endingSpeechJobs;
bool EndingSpeechGatesOpen() {
 return g_enableBoredEvents && Stobe::Interaction::Allowed() && !IsTtsPlaybackActive() &&
  !Stobe::UI::IsDirectorSceneActive() && !Stobe::UI::IsAiRequestActive();
}
void ServiceEndingSpeech(GameWorld* world) {
 std::vector<Stobe::Activity::EndingSpeechRequest> fresh;
 if(Stobe::Activity::TakeEndingSpeech(fresh)) for(size_t n=0;n<fresh.size();++n) {
  EndingSpeechJob j;j.r=fresh[n];j.queued=GetTickCount();j.due=j.queued+Stobe::Activity::EndingSpeechPolicy::kSettleMs;
  if(endingSpeechJobs.size()<16)endingSpeechJobs.push_back(j);
 }
 if(endingSpeechJobs.empty()||!world)return;
 bool open=EndingSpeechGatesOpen();const DWORD tick=GetTickCount();
 for(std::deque<EndingSpeechJob>::iterator i=endingSpeechJobs.begin();i!=endingSpeechJobs.end();) {
  const Stobe::Activity::EndingSpeechPolicy::Action act=Stobe::Activity::EndingSpeechPolicy::Decide(tick,i->queued,i->due,open);
  if(act==Stobe::Activity::EndingSpeechPolicy::Expire){
   Log("ACTIVITY_GIVEUP_SPEECH: expired without dispatch id="+i->r.agreementId);i=endingSpeechJobs.erase(i);continue;
  }
  if(act==Stobe::Activity::EndingSpeechPolicy::Dispatch){
   bool sent=false;
   try {
    Character* npc=Stobe::KenshiAi::ResolveCharacter(world,i->r.actor);Character* listener=Stobe::KenshiAi::ResolveCharacter(world,i->r.requester);
    if(npc&&listener&&npc->getHandle().serial==i->r.actor&&listener->getHandle().serial==i->r.requester&&
       !npc->isDead()&&!npc->isUnconcious()&&!listener->isDead())
     sent=Stobe::UI::TriggerOptionalBoredTurn(world,npc,listener,std::string());
   } catch(...) {sent=false;}
   Log(std::string("ACTIVITY_GIVEUP_SPEECH: ")+(sent?"dispatched":"not dispatched")+" id="+i->r.agreementId);
   if(sent){open=false;i=endingSpeechJobs.erase(i);continue;}
   i->due=Stobe::Activity::EndingSpeechPolicy::NextDue(tick);
  }
  ++i;
 }
}
}
bool QueueActivityGrant(const Stobe::Activity::Agreement& grant,unsigned revision){
"""),
("ResetMineLeases();accepted.clear();", "ResetMineLeases();endingSpeechJobs.clear();accepted.clear();"),
(" Stobe::Activity::UpdateActivityTransport();\n}", " Stobe::Activity::UpdateActivityTransport();\n ServiceEndingSpeech(world); // NC27B\n}"),
]))
# the pure policy header is a new file
dst = os.path.join(root, 'src', 'ActivityEndingSpeech.h')
src = os.path.join(here, 'ActivityEndingSpeech.h')
if not os.path.exists(dst):
    shutil.copyfile(src, dst); print('src/ActivityEndingSpeech.h: created'); changed.append(True)
else:
    print('src/ActivityEndingSpeech.h: exists')
if not any(changed):
    sys.exit(3)
