# NC17 source test: NativeTravelLifecycle::Start must decide actor availability through
# NativeTravelReceiptPolicy::ClassifyStartActor (squad companion allowed with a player requester) and must not keep the
# unconditional `faction->isThePlayer()` refusal. Usage: python3 activity_player_faction_partner_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
cpp = io.open(src + '/NativeTravelLifecycle.cpp', encoding='utf-8').read()
hdr = io.open(src + '/NativeTravelReceiptPolicy.h', encoding='utf-8').read()
fails = []
m = re.search(r'bool Start\(GameWorld.*?\n}\nbool ReleaseOwned', cpp, re.S)
if not m: fails.append('Start() body not found'); body = ''
else: body = m.group(0)
if 'ClassifyStartActor(' not in body: fails.append('Start does not call ClassifyStartActor')
if re.search(r'\(faction\s*&&\s*faction->isThePlayer\(\)\)\s*\|\|', body): fails.append('Start still refuses player-faction actors unconditionally')
if 'npc_has_existing_orders_or_unavailable:' not in body: fails.append('Start reason lacks the diagnostic suffix')
for need in ('START_ACTOR_HAS_PLAYER_ORDERS', 'START_ACTOR_HAS_ORDERS', 'START_ACTOR_DOWN', 'START_ACTOR_NO_ORDERS_RECEIVER'):
    if need not in hdr: fails.append('policy lost ' + need)
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
