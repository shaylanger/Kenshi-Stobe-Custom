#!/usr/bin/env python3
# imm26-fixS1sleep: anchor-asserting edit. Usage: python3 make_edit.py <tree root with src/>
# Adds src/StobeAsleepState.h (shared asleep/down predicate), makes main.cpp use it (same behaviour, ResolveCurrentNpcTaskSafe
# loses `static` so the header can reach it) and drops asleep/KO/dead characters from CollectEventPeopleFromAnchor (Utils.cpp).
import io, sys, os
root = sys.argv[1]
def rd(p):
    return io.open(p, encoding='utf-8', newline='').read()
def wr(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
def sub(s, old, new, label, nl):
    old = old.replace('\n', nl); new = new.replace('\n', nl)
    if s.count(old) != 1:
        print('ANCHOR FAIL', label, s.count(old)); sys.exit(2)
    return s.replace(old, new)

hp = os.path.join(root, 'src', 'StobeAsleepState.h')
if os.path.exists(hp):
    print('already applied'); sys.exit(3)

HEADER = '''// imm26 fixS1sleep: ONE asleep / down test shared by SocialCollectWitnesses (main.cpp) and the fight-audience collector
// (Utils.cpp CollectEventPeopleFromAnchor). isUnconcious() is false while sleeping (run m8), so "asleep" = in a bed, a sleeping
// task, KO / playing-dead prone state, or the AI's own StateBroadcastData::isSleeping (run m13, floor sleepers).
#pragma once
#include <kenshi/Character.h>
#include <kenshi/Enums.h>
#include <kenshi/StateBroadcastData.h>
#include <kenshi/util/YesNoMaybe.h>
#include <kenshi/util/hand.h>
#include <cstdint>

// Defined in main.cpp (reads body->currentAction->taskData->key; NULL_TASK on any failure).
TaskType ResolveCurrentNpcTaskSafe(Character *npc, hand &subjectOut);

// Outputs are optional. sleepingOut: isSleeping key 0..2, 3 = unknown. Returns true when the character is asleep or down.
inline bool StobeCharacterAsleepOrDown(Character *w, int *taskIdOut = nullptr, int *proneOut = nullptr,
                                       int *sleepingOut = nullptr) {
  if (taskIdOut) *taskIdOut = 0;
  if (proneOut) *proneOut = 0;
  if (sleepingOut) *sleepingOut = 3;
  if (!w || (uintptr_t)w < 0x1000)
    return false;
  bool asleep = false;
  try {
    hand ignoredSubject;
    TaskType task = ResolveCurrentNpcTaskSafe(w, ignoredSubject);
    int prone = (int)w->getProneState();
    if (taskIdOut) *taskIdOut = (int)task;
    if (proneOut) *proneOut = prone;
    asleep = w->inSomething == IN_BED || task == SLEEP_ON_FLOOR || task == USE_BED || prone == (int)PS_KO ||
             prone == (int)PS_PLAYING_DEAD;
    StateBroadcastData *sb = w->stateBroadcast;
    if (sb && (uintptr_t)sb > 0x1000) {
      int sleeping = (int)sb->isSleeping.key;
      if (sleeping < 0 || sleeping > 2)
        sleeping = 3;
      if (sleepingOut) *sleepingOut = sleeping;
      if (sb->isSleeping.key == YesNoMaybe::YES)
        asleep = true;
    }
  } catch (...) {
    asleep = false;
  }
  return asleep;
}

// Dead, unconscious, or asleep: such a character is not a fight witness (row 15-bx S1).
inline bool StobeCharacterDownOrAsleep(Character *w) {
  if (!w || (uintptr_t)w < 0x1000)
    return false;
  try {
    if (w->isDead() || w->isUnconcious())
      return true;
  } catch (...) {
    // unreadable state: keep the character (unchanged behaviour); the asleep test below has its own guard
  }
  return StobeCharacterAsleepOrDown(w);
}
'''
wr(hp, HEADER)

# main.cpp (CRLF)
mp = os.path.join(root, 'src', 'main.cpp'); m = rd(mp); nl = '\r\n' if '\r\n' in m else '\n'
m = sub(m, '#include <kenshi/AI/AITaskSystem.h> // REL_THEFT_CAUGHT_M18', '#include "StobeAsleepState.h" // imm26 fixS1sleep\n#include <kenshi/AI/AITaskSystem.h> // REL_THEFT_CAUGHT_M18', 'inc', nl)
m = sub(m, 'static TaskType ResolveCurrentNpcTaskSafe(Character *npc, hand &subjectOut);\n', '// imm26 fixS1sleep: non-static (declared in StobeAsleepState.h)\nTaskType ResolveCurrentNpcTaskSafe(Character *npc, hand &subjectOut);\n', 'fwd', nl)
m = sub(m, 'static TaskType ResolveCurrentNpcTaskSafe(Character *npc, hand &subjectOut) {\n', 'TaskType ResolveCurrentNpcTaskSafe(Character *npc, hand &subjectOut) {\n', 'def', nl)
old = '''    bool asleep = false;
    int taskId = 0, prone = 0, sleeping = 3; // 3 = unknown (logged as -1)
    try {
      hand ignoredSubject;
      TaskType task = ResolveCurrentNpcTaskSafe(w, ignoredSubject);
      taskId = (int)task;
      prone = (int)w->getProneState();
      asleep = w->inSomething == IN_BED || task == SLEEP_ON_FLOOR || task == USE_BED || prone == (int)PS_KO ||
               prone == (int)PS_PLAYING_DEAD;
      // Run m13: a floor sleeper's body task was not SLEEP_ON_FLOOR (logged 290); the AI's own broadcast state
      // (StateBroadcastData::isSleeping, what other characters' senses read) is the reliable flag.
      StateBroadcastData *sb = w->stateBroadcast;
      if (sb && (uintptr_t)sb > 0x1000) {
        sleeping = (int)sb->isSleeping.key;
        if (sleeping < 0 || sleeping > 2)
          sleeping = 3;
        if (sb->isSleeping.key == YesNoMaybe::YES)
          asleep = true;
      }
    } catch (...) {
      asleep = false;
    }
    if (asleep)
'''
new = '''    int taskId = 0, prone = 0, sleeping = 3; // 3 = unknown (logged as -1)
    // imm26 fixS1sleep: the asleep test is shared (StobeAsleepState.h) with the fight-audience collector.
    bool asleep = StobeCharacterAsleepOrDown(w, &taskId, &prone, &sleeping);
    if (asleep)
'''
m = sub(m, old, new, 'witness block', nl)
wr(mp, m)

# Utils.cpp (LF)
up = os.path.join(root, 'src', 'Utils.cpp'); u = rd(up); nl = '\r\n' if '\r\n' in u else '\n'
u = sub(u, '#include "StobeDrawnWeapon.h"\n', '#include "StobeDrawnWeapon.h"\n#include "StobeAsleepState.h"\n', 'inc', nl)
u = sub(u, '''    if (!IsEventAreaCompatible(anchor, other)) {
      continue;
    }
    float dist = 0.0f;''', '''    if (!IsEventAreaCompatible(anchor, other)) {
      continue;
    }
    // imm26 fixS1sleep (row 15-bx S1): a dead, knocked-out or sleeping bystander is not a witness; the list is frozen at
    // emit time, so it would otherwise keep receiving the fight events. The actor and target are added by the caller.
    if (StobeCharacterDownOrAsleep(other)) {
      continue;
    }
    float dist = 0.0f;''', 'filter', nl)
wr(up, u)
print('applied')
