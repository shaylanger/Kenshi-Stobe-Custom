# imm26 fix26a3 source test (row 26-a): NativeExecutor::Poll and ::Observe must treat "our native Travel order is gone (order list EMPTY) and the actor
# is within ActivityTravel::kEngineEndRadius (planar) of the point" as an arrival (latched op.arrived, Succeeded "arrived_order_ended_near_point"),
# never as "owned_order_changed_or_ended"; a foreign/replaced order (list non-empty) or a far actor must stay Interrupted; Attack/WorkResource are
# untouched; the new branch logs ACTIVITY_POLL_DIAG once per operation (the missing evidence of 26-a-op17).
# Usage: python3 activity_travel_engine_end_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
fails = []
def rd(n):
    try: return io.open(src + '/' + n, encoding='utf-8').read()
    except IOError: fails.append('missing file ' + n); return ''
hdr = rd('ActivityTravelArrival.h'); cpp = rd('ActivityNativeExecutor.cpp')
if 'EndedNearPoint' not in hdr or not re.search(r'kEngineEndRadius\s*=\s*16\.0', hdr): fails.append('header lacks EndedNearPoint / kEngineEndRadius = 16.0')
if not re.search(r'if\s*\(\s*!orderListEmpty\s*\)\s*return\s+false', hdr): fails.append('EndedNearPoint must return false unless the order list is empty')
if '#include "ActivityTravelArrival.h"' not in cpp: fails.append('executor does not include ActivityTravelArrival.h')
o = re.search(r'bool NativeExecutor::Observe\(.*?\nbool NativeExecutor::Transfer', cpp, re.S)
obs = o.group(0) if o else ''
if not o: fails.append('Observe() body not found')
if not re.search(r'const bool ownedNow\s*=\s*c\s*&&\s*CaptureOwned\(c,op,false\)', obs): fails.append('Observe must compute ownedNow once from CaptureOwned')
m = re.search(r'facts\.arrived\s*=\s*op\.arrived\s*\|\|\s*dx\*dx\+dy\*dy\+dz\*dz<=64\.0\s*\|\|\s*\(\s*!ownedNow\s*&&\s*ActivityTravel::EndedNearPoint\(\s*actor\.order\.orderCount==0\s*,\s*dx\s*,\s*dz\s*\)\s*\)', obs)
if not m: fails.append('Observe facts.arrived must be op.arrived || 3D<=8 || (!ownedNow && EndedNearPoint(orderCount==0,dx,dz))')
p = re.search(r'Receipt NativeExecutor::Poll\(.*?\nbool NativeExecutor::SnapshotNative', cpp, re.S)
poll = p.group(0) if p else ''
if not p: fails.append('Poll() body not found')
b = re.search(r'if\(!CaptureOwned\(actor,op,false\)\)\s*\{(.*?)\n  \}\n', poll, re.S)
br = b.group(1) if b else ''
if not b: fails.append('Poll CaptureOwned-failure block not found (must be a braced block)')
if 'op.request.command==Travel && ActivityTravel::EndedNearPoint(' not in br: fails.append('Poll: EndedNearPoint must be gated on command==Travel')
if not re.search(r'orders\s*&&\s*orders->orders\.list\.empty\(\)', br): fails.append('Poll: list-empty must be read from the live order list (null-safe)')
if not re.search(r'if\(nearEnd\)\s*\{\s*op\.arrived=true;\s*return op\.receipt=Result\(Receipt::Succeeded,"arrived_order_ended_near_point"\);\s*\}', br): fails.append('Poll: nearEnd must latch op.arrived and return Succeeded "arrived_order_ended_near_point"')
if not re.search(r'return op\.receipt=Result\(Receipt::Interrupted,"owned_order_changed_or_ended"\);\s*$', br.strip() + '\n', re.S): fails.append('Poll: the Interrupted "owned_order_changed_or_ended" fall-through must remain last in the block')
if br.find('nearEnd)') > br.find('"owned_order_changed_or_ended"'): fails.append('Poll: Succeeded branch must precede the Interrupted return')
if 'ACTIVITY_POLL_DIAG' not in br: fails.append('Poll: ACTIVITY_POLL_DIAG line missing')
if 'CancelDiag(' in poll: fails.append('Poll must not call CancelDiag (defined after Poll; and it prefixes ACTIVITY_CANCEL_DIAG)')
if poll.count('"owned_order_changed_or_ended"') != 1: fails.append('exactly one owned_order_changed_or_ended return expected in Poll')
if len(re.findall(r'ActivityTravel::EndedNearPoint', poll)) != 1 or len(re.findall(r'ActivityTravel::EndedNearPoint', cpp)) != 2: fails.append('EndedNearPoint must be used exactly once in Poll and once in Observe')
# the 8 u arrival test must still come first in Poll
i8 = poll.find('"arrived_at_scoped_point"'); ic = poll.find('if(!CaptureOwned(actor,op,false))')
if not (0 <= i8 < ic): fails.append('the 8 u arrival check must precede the CaptureOwned-failure block')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
