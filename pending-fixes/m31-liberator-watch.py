#!/usr/bin/env python3
"""m31 REL p7-05: a fast lock pick was not credited to the liberator.

Batch P: Daphnilis picked Rel Nima's shackles 7 s after the order (lockpicking 100, speed 2), Stobe logged
"chains off, still a slave, nobody worked the lock: not freed". The liberator's task is sampled only by the 3 s
world-event sweep, so a pick that starts and ends between two samples leaves no lib memo.
Fix: while capture is on, every 250 ms read the current task of the player's squad members (at most 16, cheap) and
keep the lock/shackle memo (libSubjectSerial/libTask/libTick) the 60 s liberator lookup already reads; log each new
(actor, task, subject) once. The chains-off check also passes the victim's alias serial (an order given before a
re-squad targets the old handle), as EmitSlaveryEvent already does.

usage: python3 m31-liberator-watch.py <STOBE-src root>   (asserts anchors; refuses to apply twice)
"""
import sys

root = sys.argv[1]
p = root + '/src/main.cpp'
s = open(p, encoding='utf-8', errors='surrogateescape').read()
if 'REL_LIB_WATCH_M31' in s:
    sys.exit('already applied')

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, ('anchor count %d' % n, old[:80])
    s = s.replace(old, new)

# 1) the fast squad liberation watch, before the 3 s sweep throttle
rep("""  DWORD nowTick = GetTickCount();
  SocialFlushAidSessions(nowTick);
  if (nowTick - g_lastNpcWorldEventSweepTick < kNpcWorldEventSweepIntervalMs) {
    return;
  }""",
"""  DWORD nowTick = GetTickCount();
  SocialFlushAidSessions(nowTick);
  SocialLiberationWatch(world, nowTick); // REL_LIB_WATCH_M31
  if (nowTick - g_lastNpcWorldEventSweepTick < kNpcWorldEventSweepIntervalMs) {
    return;
  }""")

rep("""static void RunNpcWorldEventSweepUnsafe(GameWorld *world, Character *selection) {
""",
"""// REL_LIB_WATCH_M31: a squad member's lock/shackle task is sampled every 250 ms (the 3 s sweep missed a 7 s pick at
// speed 2, batch P p7-05), into the same memo SocialFindLiberator reads. Squad only (<= 16): the player frees people.
static DWORD g_lastLiberationWatchTick = 0;
static void SocialLiberationWatch(GameWorld *world, DWORD nowTick) {
  if (!SocialCaptureEnabled() || nowTick - g_lastLiberationWatchTick < 250)
    return;
  g_lastLiberationWatchTick = nowTick;
  if (!world || !world->player)
    return;
  uint32_t n = world->player->playerCharacters.size();
  for (uint32_t i = 0; i < n && i < 16; ++i) {
    Character *member = world->player->playerCharacters[i];
    if (!member || (uintptr_t)member < 0x1000)
      continue;
    unsigned int serial = 0;
    try {
      serial = member->getHandle().serial;
    } catch (...) {
      serial = 0;
    }
    if (!serial)
      continue;
    hand subject;
    TaskType task = ResolveCurrentNpcTaskSafe(member, subject);
    if (!IsLiberationTask((int)task) || !subject.isValid() || subject.isNull() || !subject.serial)
      continue;
    NpcWorldEventState &state = g_npcWorldEventStateBySerial[serial];
    bool changed = state.libSubjectSerial != subject.serial || state.libTask != (int)task ||
                   nowTick - state.libTick > 60000;
    state.libSubjectSerial = subject.serial;
    state.libTask = (int)task;
    state.libTick = nowTick;
    if (changed)
      Log("EVENT_SCAN: liberation task serial=" + ToString(serial) + " name=" + ResolveCharacterNameSafe(member) +
          " task=" + ToString((int)task) + " subject=" + ToString(subject.serial));
  }
}

static void RunNpcWorldEventSweepUnsafe(GameWorld *world, Character *selection) {
""")

# 2) chains-off check: the alias serial too
rep("""        if (slaveStateNow != (int)IS_SLAVE || SocialFindLiberator(serial, 0, 0, t))""",
"""        if (slaveStateNow != (int)IS_SLAVE || SocialFindLiberator(serial, SocialAliasSerial(SocialEntityFor(npc)), 0, t))""")

open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)
print('applied', p)
