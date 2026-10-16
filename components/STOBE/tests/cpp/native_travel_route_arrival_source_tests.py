# NC18 source test: native-owned travel must refine an unreachable route target, judge arrival by planar distance
# (not 3D AtAgreedEndpoint, which fails when the server destination y is far below terrain) and log its decisions.
# Usage: python3 native_travel_route_arrival_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
cpp = io.open(src + '/NativeTravelLifecycle.cpp', encoding='utf-8').read()
fails = []
m = re.search(r'bool Start\(GameWorld.*?\nbool ReleaseOwned', cpp, re.S)
start = m.group(0) if m else ''
if not m: fails.append('Start() body not found')
t = re.search(r'\nvoid Tick\(.*', cpp, re.S)
tick = t.group(0) if t else ''
if not t: fails.append('Tick() not found')
for need in ('Rt::Choose(', 'NATIVE_TRAVEL_START', 'r.reqX = requestedX'):
    if need not in start: fails.append('Start missing ' + need)
if 'if (!target)' not in start: fails.append('Start must refine only route targets (not follow)')
for need in ('Rt::RouteNear(', 'kArriveRadius', 'kEngineEndRadius', 'NATIVE_TRAVEL_OBS', 'NATIVE_TRAVEL_ORDER_ENDED', 'NATIVE_TRAVEL_FINISH'):
    if need not in tick: fails.append('Tick missing ' + need)
if 'AtAgreedEndpoint' in tick: fails.append('Tick still uses 3D AtAgreedEndpoint arrival')
if 'NATIVE_TRAVEL: task=' not in cpp: fails.append('Emit does not log phase changes')
if '#include "NativeTravelRouteTarget.h"' not in cpp: fails.append('route target header not included')
if not re.search(r'#pragma push_macro\("max"\)', cpp): fails.append('min/max macro guard around Ogre includes missing')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
