# NC22 source test (row 14-d): ClearGroup rejected spawned wild bandits as owned_target because
# IsProtectedActivityTarget treated `getMySlaveOwner().serial != 0` as proof of ownership. Fails on NC21, passes on NC22.
# Usage: python3 activity_ownership_source_tests.py <src dir>
import io, os, re, sys
src = sys.argv[1]
def rd(n):
    p = src + '/' + n
    return io.open(p, encoding='utf-8').read() if os.path.exists(p) else ''
pol, hdr, own, bind = rd('ActivityPolicySupport.cpp'), rd('ActivityPolicySupport.h'), rd('ActivityOwnership.h'), rd('ActivityRuntimeBindings.cpp')
fails = []
m = re.search(r'bool IsProtectedActivityTarget\(.*?\n\}\n', pol, re.S)
body = m.group(0) if m else ''
if not body: fails.append('IsProtectedActivityTarget not found')
if re.search(r'if\(target->getMySlaveOwner\(\)\.serial\)\s*\{reason="owned_target"', body): fails.append('owner serial alone still protects (owned_target)')
if 'Ownership::Decide(' not in body: fails.append('IsProtectedActivityTarget must use Ownership::Decide')
if 'isSlave()' not in body or 'isChainedMode()' not in body or 'IN_PRISON' not in body: fails.append('decision must read slave state, chained mode and prison')
if '#include "ActivityOwnership.h"' not in pol: fails.append('ActivityPolicySupport.cpp lacks the ActivityOwnership.h include')
# The other protections stay in the same function, in the same order.
for needle in ('player_same_faction_or_ally', 'active_ceasefire', 'non_hostile_target', 'ProvenWild('):
    if needle not in body: fails.append('protection removed: ' + needle)
if body.find('active_ceasefire') > body.find('Ownership::Decide(') > -1: fails.append('ownership check moved before the ceasefire check')
if body.find('Ownership::Decide(') > body.find('target->isAnimal()) {') > -1: fails.append('ownership check must stay before the animal wild proof')
# Pure decision keeps its genuine-owner cases.
if '"captive_target"' not in own or '"owned_target"' not in own: fails.append('ActivityOwnership.h lacks owned_target/captive_target')
if 'if(animal) return ownerSerial' not in own: fails.append('animals must keep the strict owner-handle rule')
if 'slaveState != 0 || chained' not in own: fails.append('persons need slave state or chained mode')
# Operator evidence on the member line.
if 'OwnershipDiag(' not in bind or 'OwnershipDiag' not in hdr: fails.append('ACTIVITY_CLEARGROUP_MEMBER must log OwnershipDiag (ownerSerial slaveState chained prison animal)')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
