# NC21 source test (row 13-c, participation_bound=0): Character::getInstanceID() returns NULL for every Character
# (RootObject default; only Building overrides it), so the participation proof must bind with the identity the rest of the
# mod and the server use (uid if present else hand_<serial>), never refuse an empty uid. Fails on NC20, passes on NC21.
# Usage: python3 participation_hand_fallback_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
ev = io.open(src + '/ParticipationEvidence.h', encoding='utf-8').read()
idh = io.open(src + '/ParticipationIdentity.h', encoding='utf-8').read() if __import__('os').path.exists(src + '/ParticipationIdentity.h') else ''
life = io.open(src + '/NativeTravelLifecycle.cpp', encoding='utf-8').read()
ctx = io.open(src + '/Context.cpp', encoding='utf-8').read()
fails = []
if 'ai->uid.empty()' in ev or 'pi->uid.empty()' in ev: fails.append('Begin still refuses an empty InstanceID uid')
if 'uid!=actorStorage' in ev or 'uid!=partnerStorage' in ev: fails.append('Sample still compares the raw InstanceID uid (NULL for every Character)')
if 'ParticipationIdentity.h' not in ev: fails.append('ParticipationEvidence.h does not use ParticipationIdentity.h')
if 'Identity::StorageId(' not in ev or 'Identity::Decide(' not in ev: fails.append('Begin/Sample must use Identity::StorageId and Identity::Decide')
# The hand_ fallback must be exactly the format of Context.cpp GetStorageIDFor / the snapshot id.
if 'std::string("hand_")' not in ctx: fails.append('Context.cpp GetStorageIDFor hand_ format anchor changed; re-check ParticipationIdentity.h')
if '"hand_"' not in idh: fails.append('ParticipationIdentity.h lacks the hand_<serial> fallback')
# Identity is still pinned to the exact hand (handle) in Sample, and bound still gates qualification.
if not re.search(r'!Same\(a->getHandle\(\),actorHandle\)\|\|!Same\(p->getHandle\(\),partnerHandle\)', ev): fails.append('Sample must still pin the exact actor/partner handle')
if 'completed&&bound&&samples>=4&&now>=last&&now-last<=2&&last-first>=30' not in ev: fails.append('Freeze qualification thresholds changed')
if not re.search(r'travel\?\(actorDistance>=30&&partnerDistance>=30&&endpointProgress>=30\)', ev): fails.append('travel progress thresholds changed')
if 'ad>20.0*(now-last)+5.0||pd>20.0*(now-last)+5.0' not in ev: fails.append('teleport/jump guard changed')
if 'if(separation>35.0)' not in ev: fails.append('separation guard changed')
# Start passes the actor Character* it already holds; both log lines name the bind result.
if not re.search(r'participation\.Begin\(world, serial, speaker, expectedWorld, agreement, r\.task, true, Ogre::Vector3\(x,y,z\), actor\)', life): fails.append('Start must pass the actor Character* to Begin')
if 'participation_why=' not in life or 'participation_ids=' not in life: fails.append('NATIVE_TRAVEL_START must log participation_why and participation_ids')
if 'NATIVE_TRAVEL_PART_BIND' not in life: fails.append('lazy route-controller bind must log NATIVE_TRAVEL_PART_BIND')
if 'participation_diag=' not in life: fails.append('terminal NATIVE_TRAVEL line must log participation_diag')
if 'participation_bound=' not in life: fails.append('participation_bound= log key must remain')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
