# imm26 fix26apoll source test (row 26-a NC32): NativeExecutor::Poll must NOT Interrupt a dispatched Attack/Travel when policy_.Revalidate fails ONLY with
# "current_native_path_unconfirmed" while our owned order is still the live order (otherwise Goal::Replan adds the goat to attempted_ and the next empty scan
# ends the Hunt). Every other Revalidate failure must still Interrupt. ACTIVITY_SCAN_DIAG (discover stage) must also print targetOnMesh/dx/dz/dy.
# Usage: python3 activity_poll_keep_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
fails = []
def rd(n):
    try: return io.open(src + '/' + n, encoding='utf-8', newline='').read()
    except IOError: fails.append('missing file ' + n); return ''
ex = rd('ActivityNativeExecutor.cpp'); bd = rd('ActivityRuntimeBindings.cpp')
m = re.search(r'Receipt NativeExecutor::Poll\(const std::string& id\) \{.*?\n\}\r?\n', ex, re.S)
poll = m.group(0) if m else ''
if not m: fails.append('NativeExecutor::Poll body not found')
# the Revalidate call must no longer be part of the unconditional early-return condition
if re.search(r'\|\|\s*\r?\n?\s*!policy_\.Revalidate\([^)]*\)\)\s*\r?\n\s*return\s+op\.receipt=Result\(Receipt::Interrupted', poll): fails.append('Revalidate still sits in the unconditional Interrupted early return')
b = re.search(r'if\(!policy_\.Revalidate\(op\.agreement,op\.request,current,reason\)\)\s*\{(.*?)\r?\n  \}\r?\n', poll, re.S)
if not b: fails.append('Poll must have an if(!policy_.Revalidate(...)) { } block')
else:
    body = b.group(1)
    if not re.search(r'reason\s*==\s*"current_native_path_unconfirmed"', body): fails.append('keep gate must compare reason == "current_native_path_unconfirmed" exactly')
    if not re.search(r'command\s*==\s*Attack\s*\|\|\s*op\.request\.command\s*==\s*Travel', body): fails.append('keep gate must be limited to Attack/Travel')
    if 'CaptureOwned(actor,op,false)' not in body: fails.append('keep gate must require the owned order to still be present (CaptureOwned(actor,op,false))')
    if 'ACTIVITY_POLL_DIAG' not in body or 'revalidate_path_unconfirmed' not in body: fails.append('POLL_DIAG line missing in the keep block')
    if not re.search(r'if\(!keepPending\)\s*return\s+op\.receipt=Result\(Receipt::Interrupted,reason\.empty\(\)\?"agreement_or_actor_unavailable":reason\);', body): fails.append('non-keep path must still return Interrupted with the Revalidate reason')
if not re.search(r'if\(now_>=op\.agreement\.expiresAt\s*\|\|\s*!AliveActor\(actor,op\.request\.actor\)\s*\|\|\s*!SameHand\(actor->getHandle\(\),op\.actorIdentity\)\)\s*\r?\n\s*return\s+op\.receipt=Result\(Receipt::Interrupted,"agreement_or_actor_unavailable"\);', poll): fails.append('expiry/alive/identity checks must still Interrupt unconditionally')
d = re.search(r'stage=discover.*?Log\(d\.str\(\)\);', bd, re.S)
diag = d.group(0) if d else ''
if not d: fails.append('discover SCAN_DIAG not found')
else:
    for k in ('targetOnMesh=', 'dx=', 'dz=', 'dy='):
        if ('<<" ' + k) not in diag: fails.append('discover SCAN_DIAG lacks ' + k)
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
