#!/usr/bin/env python3
"""NC27 part A (imm26-huntA1, Shay 2026-10-16): an attack that actually damages the hunted animal resets the Hunt no-progress timer.
Usage: python3 nc27a_edit.py <tree-root>     (tree-root contains src/; NC25 or NC26 base; idempotent: a second run refuses)
Signal: the target's summed flesh health (head, stomach, 4 limbs; MedicalSystem::HealthPartStatus::flesh, same readers as ActivityDanger)
is read where the Hunt target is observed (ConcreteRuntimeBindings::Refresh -> Target.health). Goal::Tick compares it with the value of the
previous observation of the SAME target while the owned Attack order is pending in phase Performing: a drop of more than 0.5 flesh resets
lastProgress_. Hunt only; ClearGroup / Mine logic untouched. Unreadable health (healthValid=false) = no reset (fails closed).
"""
import sys, os
root = sys.argv[1]
MARK = 'NC27A'

def load(rel):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return p, (s.replace('\r\n', '\n') if crlf else s), crlf

def edit(rel, pairs):
    p, s, crlf = load(rel)
    if MARK in s:
        print(rel + ': already applied (NC27A marker)'); return False
    for a, b in pairs:
        assert s.count(a) == 1, rel + ': anchor missing or duplicated: ' + a[:90]
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)
    print(rel + ': patched'); return True

changed = []
changed.append(edit('src/ActivityGoals.h', [
("  bool dead, defeated, harvestable, hasRequestedItem;\n  Target();",
 "  bool dead, defeated, harvestable, hasRequestedItem;\n  // NC27A: summed flesh health of the target (Hunt only; healthValid=false when unreadable). Used to detect that our attack lands.\n  bool healthValid; float health;\n  Target();"),
("  unsigned int delivered_, replans_, sequence_;",
 "  unsigned int delivered_, replans_, sequence_;\n  // NC27A: health baseline of the current Hunt target (progress by damage).\n  float lastHealth_; unsigned int healthSerial_; bool healthKnown_; Clock lastDamageLogAt_;"),
]))
changed.append(edit('src/ActivityGoals.cpp', [
(" defeated(false), harvestable(false), hasRequestedItem(false) {}",
 " defeated(false), harvestable(false), hasRequestedItem(false), healthValid(false), health(0.0f) {}"),
(" replans_(0), sequence_(0), pendingCommand_(Travel) {}",
 " replans_(0), sequence_(0), lastHealth_(0.0f), healthSerial_(0), healthKnown_(false), lastDamageLogAt_(0), pendingCommand_(Travel) {}"),
("  if (now - lastProgress_ >= terms_.noProgressTimeout) {\n    Stop(Failed, host, \"activity_no_verified_progress\"); return;",
 """  // NC27A (Shay 2026-10-16): actively hurting the hunted animal is progress. Compare the target's health with the previous observation of
  // the SAME target; only while our owned Attack order is pending (so animals hurt by others or by earlier legs never count).
  if (terms_.kind == Hunt && target_.serial && f.target.serial == target_.serial && f.target.healthValid) {
    const bool attacking = phase_ == Performing && !pending_.empty() && pendingCommand_ == Attack;
    if (attacking && healthKnown_ && healthSerial_ == target_.serial && f.target.health < lastHealth_ - 0.5f) {
      lastProgress_ = now;
      if (ActivityEndLogSink && (!lastDamageLogAt_ || now - lastDamageLogAt_ >= 30)) {
        lastDamageLogAt_ = now;
        std::ostringstream o; o<<"ACTIVITY_PROGRESS_DIAG reset=target_damage id="<<terms_.id<<" target="<<target_.serial
          <<" health="<<lastHealth_<<"->"<<f.target.health<<" now="<<now;
        try { ActivityEndLogSink(o.str()); } catch(...) {}
      }
    }
    healthKnown_ = true; healthSerial_ = target_.serial; lastHealth_ = f.target.health;
  }
  if (now - lastProgress_ >= terms_.noProgressTimeout) {
    Stop(Failed, host, \"activity_no_verified_progress\"); return;"""),
]))
changed.append(edit('src/ActivityDanger.h', [
("class GameWorld;\n", "class GameWorld;\nclass Character;\n"),
("// quarry = agreed targets",
 "// NC27A: summed flesh health of the head/stomach/limb parts (0 .. large). False when unreadable. Game thread only.\nbool TargetFleshTotal(Character* c, float& out);\n// quarry = agreed targets"),
]))
changed.append(edit('src/ActivityDanger.cpp', [
("bool ObserveDanger(GameWorld* world,unsigned actorSerial,unsigned requesterSerial,const std::vector<unsigned>& quarry,",
 """// NC27A: summed flesh of the six body parts; a landed hit lowers it. Same part set and guards as HealthPercent above.
bool TargetFleshTotal(Character* c,float& out) {
 if(!c) return false;
 try {
  MedicalSystem* med=c->getMedical();
  if(!med || (uintptr_t)med<0x1000) return false;
  MedicalSystem::HealthPartStatus* parts[6]={med->getPart((unsigned __int64)0),med->getPart((unsigned __int64)1),
   med->leftArm,med->rightArm,med->leftLeg,med->rightLeg};
  float total=0.0f; int seen=0;
  for(int i=0;i<6;++i) {
   MedicalSystem::HealthPartStatus* part=parts[i];
   if(!part || (uintptr_t)part<0x1000) continue;
   const float mx=part->maxHealth();
   if(mx>1.0f && _finite(mx) && _finite(part->flesh)) { total+=part->flesh; ++seen; }
  }
  if(!seen || !_finite(total)) return false;
  out=total; return true;
 } catch(...) { return false; }
}
bool ObserveDanger(GameWorld* world,unsigned actorSerial,unsigned requesterSerial,const std::vector<unsigned>& quarry,"""),
]))
changed.append(edit('src/ActivityRuntimeBindings.cpp', [
('#include "ActivityPolicySupport.h"\n', '#include "ActivityPolicySupport.h"\n#include "ActivityDanger.h" // NC27A TargetFleshTotal\n'),
("  t.hasRequestedItem=HasItem(target,a.resourceId);\n",
 "  t.hasRequestedItem=HasItem(target,a.resourceId);\n  if(a.kind==Hunt) t.healthValid=TargetFleshTotal(target,t.health); // NC27A progress-by-damage signal\n"),
]))
# The marker must exist in every touched file so a second run refuses: stamp it in a comment at file end.
for rel in ['src/ActivityGoals.h','src/ActivityGoals.cpp','src/ActivityDanger.h','src/ActivityDanger.cpp','src/ActivityRuntimeBindings.cpp']:
    p, s, crlf = load(rel)
    if MARK not in s:
        s = s.rstrip('\n') + '\n// NC27A: Hunt progress-by-damage (imm26-huntA1)\n'
        open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)
if not any(changed):
    sys.exit(3)
