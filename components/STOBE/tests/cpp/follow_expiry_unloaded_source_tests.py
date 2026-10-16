# NC25 source test (row 23-b): the legacy FOLLOW expiry (FollowExpiryGameHours) must run BEFORE the loaded-follower guard
# (FindCharacterBySerial only sees the world update list), cache squad status, restore later, and log FOLLOW_DIAG.
# Usage: python3 follow_expiry_unloaded_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
main = io.open(src + '/main.cpp', encoding='utf-8').read()
utils = io.open(src + '/Utils.cpp', encoding='utf-8').read()
fails = []
m = re.search(r'static void ApplyFollowTargets\(GameWorld \*world\) \{.*?\nstatic void ApplyTravelTargets', main, re.S)
body = m.group(0) if m else ''
if not m: fails.append('ApplyFollowTargets not found')
iexp = body.find('Log("FOLLOW_EXPIRED: follower=')
iguard = max(body.find('if (!followerLoaded'), body.find('if (!follower ||'))
if iexp < 0: fails.append('FOLLOW_EXPIRED log missing')
if iguard < 0: fails.append('loaded guard not found')
if iexp >= 0 and iguard >= 0 and iexp > iguard: fails.append('expiry runs AFTER the loaded guard (unloaded follower never expires)')
for need in ('s_followSquadCache', 's_followRestorePending', 'FOLLOW_DIAG', 'RestoreAfterFollowExpiry', 'ShouldExpire('):
    if need not in body and not (need == 'RestoreAfterFollowExpiry' and 'static void RestoreAfterFollowExpiry' in main):
        fails.append('missing ' + need)
if 'FollowExpiryGameHours' not in utils or 'ReadLayeredIniInt' not in utils[utils.find('FollowExpiryLimitGameSeconds'):utils.find('FollowExpiryLimitGameSeconds')+700]:
    fails.append('FollowExpiryGameHours ini key not read through ReadLayeredIniInt')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
