# imm26-sfP source test (row 26-d): ConcreteRuntimeBindings::ImportGrant must not require LIVE sight of the offer's exact animal for a Hunt grant.
# The server (imm26-u4) accepts any currently observed same-source animal at ACCEPT, and the NPC has turned to face the speaker by then, so an import-time
# canISeeThisGuy(exact animal) rejects a grant the server already accepted (4080-i4 26-d: "ACTIVITY grant rejected: activity_discovery_reference_source_mismatch").
# Fails on NC22 and earlier; passes on NC22 + sfPedit.py. Usage: python3 hunt_grant_import_sight_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
cpp = io.open(src + '/ActivityRuntimeBindings.cpp', encoding='utf-8').read()
rt = io.open(src + '/ActivityRuntime.cpp', encoding='utf-8').read()
goals = io.open(src + '/ActivityGoals.cpp', encoding='utf-8').read()
fails = []

i = cpp.find('bool ConcreteRuntimeBindings::ImportGrant(')
j = cpp.find('bool ConcreteRuntimeBindings::Revoke(')
if i < 0 or j < i:
    print('failures=1'); print('FAIL ImportGrant not found'); sys.exit(1)
imp = cpp[i:j]
k = imp.find('Character* target=(Character*)discoveredObject;')
if k < 0:
    print('failures=1'); print('FAIL Hunt/ClearGroup target block not found in ImportGrant'); sys.exit(1)
blk = imp[k:imp.find('Grant g; g.scope=a;', k)]

# 1. the fix: no unconditional live-sight clause for the exact animal
if re.search(r'\|\|\s*!actor->getSensoryData\(\)->canISeeThisGuy\(target\)\s*\|\|', blk):
    fails.append('Hunt grant import still requires live canISeeThisGuy(target) unconditionally (26-d cause)')
if '(a.kind!=Hunt && !actor->getSensoryData()->canISeeThisGuy(target))' not in blk:
    fails.append('live sight must stay required at import for the non-Hunt kind (ClearGroup)')

# 2. the Hunt grant stays bound to the exact animal and its source
if "a.kind==Hunt && (target->getGameData()->stringID!=a.sourceId || !target->isAnimal())" not in blk:
    fails.append('Hunt import must still check source id and animal')
if 'discoveredObject!=discovered->second.identity' not in imp or 'discoveredObject->getHandle().serial!=a.discoveryTargetSerial' not in imp:
    fails.append('exact identity/serial binding of the discovery reference must stay')
if 'actor!=discovered->second.actorIdentity || requester!=discovered->second.requesterIdentity' not in imp:
    fails.append('actor/requester identity binding must stay')
if 'GroupSource(target)!=a.sourceId' not in blk or 'a.discoveryTargetSerial)==a.agreedTargets.end()' not in blk:
    fails.append('ClearGroup import clauses (group source, fixed set) must stay')
if 'canISeeThisGuy(member)' not in imp or 'fixed_target_not_observed_at_grant' not in imp:
    fails.append('ClearGroup per-member live-sight check at grant must stay')

# 3. live sight is still enforced where the NPC acts on the animal
if '!t.visible||!t.reachable' not in rt:
    fails.append('NativeHost::Candidates must still require visible+reachable')
if '!d.facts.visible||!d.facts.reachable' not in rt:
    fails.append('NativeHost::Revalidate must still require visible+reachable')
if '!agreed.facts.visible || !agreed.facts.reachable' not in cpp:
    fails.append('Bindings::Discover must still require visible+reachable')
if 'reason="target_not_observed"' not in cpp:
    fails.append('Bindings::Refresh target_not_observed missing')
if 'no_observed_suitable_reachable_target' not in goals:
    fails.append('Goal Searching must still fail without an observed suitable target')

# 4. a reject names the failing clause
if 'ACTIVITY_GRANT_SOURCE_DIAG' not in blk:
    fails.append('reject must log ACTIVITY_GRANT_SOURCE_DIAG')
else:
    for need in ('sees=', 'animal=', 'sidMatch=', 'gameData=', 'sensory='):
        if need not in blk:
            fails.append('ACTIVITY_GRANT_SOURCE_DIAG field missing: ' + need)

print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
