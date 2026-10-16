# NC23 source test (row 26-a): Hunt/Attack cleanup never completed while the NPC's own combat AI kept fighting a retaliating target,
# because CancelOwned required NativeEnded (goal/action/movement idle) for Attack too. Fails on NC22, passes on NC23.
# Usage: python3 attack_cleanup_source_tests.py <src dir>
import io, os, re, sys
src = sys.argv[1]
p = src + '/ActivityNativeExecutor.cpp'
s = io.open(p, encoding='utf-8').read() if os.path.exists(p) else ''
fails = []
m = re.search(r'bool NativeExecutor::CancelOwned\(.*?\n\}\n', s, re.S)
body = m.group(0) if m else ''
if not body: fails.append('CancelOwned not found')
if 'ACTIVITY_CANCEL_DIAG' not in s: fails.append('no ACTIVITY_CANCEL_DIAG log')
for br in ('capture_mismatch', 'cancel_refused', 'native_not_ended', 'actor_mismatch', 'no_orders_receiver'):
    if '"' + br + '"' not in body: fails.append('false return without named branch: ' + br)
if re.search(r'if\(!NativeEnded\(actor,op\)\)', body): fails.append('NativeEnded still required unconditionally (must be skipped for Attack)')
if not re.search(r'!attack\s*&&\s*!NativeEnded\(actor,op\)', body): fails.append('NativeEnded must be kept for non-Attack (Travel/WorkResource)')
if 'op.request.command==Attack' not in body: fails.append('Attack branch missing')
if 'orders->orders.list[k]' not in body or 'op.owned.runtimePointer' not in body: fails.append('own-order presence check missing')
if 'GetTickCount' not in s or '<5000' not in s: fails.append('diag not rate-limited')
if 'void Log(const std::string &msg);' not in s: fails.append('Log declaration missing')
if 'CaptureOwned(actor,op,false)' not in body or 'TryCancelOwnedOrder' not in body: fails.append('non-attack path must still validate + cancel the owned order')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
