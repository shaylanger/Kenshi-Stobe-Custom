# imm26 fixS1sleep (row 15-bx witness S1): the fight audience (Utils.cpp CollectEventPeopleFromAnchor) must drop dead / KO /
# asleep bystanders, and the asleep predicate must be ONE shared helper (StobeAsleepState.h) also used by main.cpp's
# SocialCollectWitnesses (no second copy of the IN_BED / SLEEP_ON_FLOOR / isSleeping test).
# Usage: python3 fight_audience_asleep_source_tests.py <src dir>
import io, re, sys
src = sys.argv[1]
def rd(n):
    try: return io.open(src + '/' + n, encoding='utf-8').read()
    except IOError: return ''
utils, main, hdr = rd('Utils.cpp'), rd('main.cpp'), rd('StobeAsleepState.h')
fails = []
m = re.search(r'static void CollectEventPeopleFromAnchor\(.*?\n}\n', utils, re.S)
body = m.group(0) if m else ''
if not m: fails.append('CollectEventPeopleFromAnchor not found')
if 'StobeCharacterDownOrAsleep(other)' not in body: fails.append('audience loop does not call StobeCharacterDownOrAsleep(other)')
i_f = body.find('StobeCharacterDownOrAsleep(other)'); i_app = body.find('TryAppendEventPersonBySerial')
if i_f >= 0 and (i_app < 0 or i_f > i_app): fails.append('asleep filter runs AFTER the person is appended')
if 'if (StobeCharacterDownOrAsleep(other)) {\n      continue;' not in body.replace('\r\n', '\n'): fails.append('filter does not skip (continue) the sleeper')
if '#include "StobeAsleepState.h"' not in utils: fails.append('Utils.cpp does not include StobeAsleepState.h')
# the actor / target are appended by BuildEventPeopleJson BEFORE the collector, so a KO victim stays in the list
b = re.search(r'static std::string BuildEventPeopleJson\(.*?\n}\n', utils, re.S)
bb = b.group(0) if b else ''
if not bb or bb.find('resolvedTargetSerial,') < 0 or bb.find('resolvedTargetSerial,') > bb.find('CollectEventPeopleFromAnchor('):
    fails.append('actor/target no longer appended before the collector')
if not hdr: fails.append('StobeAsleepState.h missing')
else:
    for need in ('IN_BED', 'SLEEP_ON_FLOOR', 'USE_BED', 'PS_KO', 'PS_PLAYING_DEAD', 'isSleeping', 'isDead()', 'isUnconcious()'):
        if need not in hdr: fails.append('helper lacks ' + need)
    if 'inline bool StobeCharacterAsleepOrDown(' not in hdr or 'inline bool StobeCharacterDownOrAsleep(' not in hdr:
        fails.append('helper functions missing')
mw = re.search(r'static void SocialCollectWitnesses\([^;]*?\) \{.*?\n}\n', main.replace('\r\n', '\n'), re.S)
mb = mw.group(0) if mw else ''
if not mw: fails.append('SocialCollectWitnesses not found')
if 'StobeCharacterAsleepOrDown(w, &taskId, &prone, &sleeping)' not in mb: fails.append('SocialCollectWitnesses does not use the shared helper')
for dup in ('SLEEP_ON_FLOOR', 'IN_BED', 'isSleeping'):
    if dup in mb: fails.append('SocialCollectWitnesses still has its own copy of ' + dup)
if re.search(r'^static TaskType ResolveCurrentNpcTaskSafe', main, re.M): fails.append('ResolveCurrentNpcTaskSafe still static (header cannot link to it)')
if len(re.findall(r'^TaskType ResolveCurrentNpcTaskSafe\(Character \*npc, hand &subjectOut\) \{', main, re.M)) != 1: fails.append('non-static ResolveCurrentNpcTaskSafe definition missing')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
