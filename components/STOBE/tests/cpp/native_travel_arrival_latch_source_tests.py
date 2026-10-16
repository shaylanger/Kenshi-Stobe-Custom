# imm26 fix26a source test (row 26-a): NativeExecutor::Poll must latch the Travel arrival (op.arrived) when it reports
# Succeeded, and Observe must report facts.arrived = op.arrived || within 8 u, so a later tick (owned-order cleanup retry
# after the NPC walked on) cannot flip a verified arrival into "arrival_not_verified". The latch is a plain per-Operation
# member, default false in the constructor; operations are keyed by unique request id and never serialised.
# Usage: python3 native_travel_arrival_latch_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
cpp = io.open(src + '/ActivityNativeExecutor.cpp', encoding='utf-8').read()
hdr = io.open(src + '/ActivityNativeExecutor.h', encoding='utf-8').read()
fails = []
if not re.search(r'orderRemoved\s*,\s*arrived\s*;', hdr): fails.append('Operation lacks the bool arrived member')
if not re.search(r'Operation::Operation\(\)\s*:[^{]*\barrived\(false\)', cpp): fails.append('Operation ctor does not default arrived(false)')
m = re.search(r'bool NativeExecutor::Observe\(.*?\nbool NativeExecutor::Transfer', cpp, re.S)
obs = m.group(0) if m else ''
if not m: fails.append('Observe() body not found')
if not re.search(r'facts\.arrived\s*=\s*op\.arrived\s*\|\|', obs): fails.append('Observe must OR the latched op.arrived into facts.arrived')
if 'op.cleanupRequired' not in obs.split('facts.arrived')[0]: fails.append('Observe must stay gated on op.cleanupRequired (no stale latch from finished operations)')
p = re.search(r'Receipt NativeExecutor::Poll\(.*?\nbool NativeExecutor::SnapshotNative', cpp, re.S)
poll = p.group(0) if p else ''
if not p: fails.append('Poll() body not found')
sites = re.findall(r'op\.arrived\s*=\s*true\s*;[^\n]*\n?[^\n]*?"arrived_at_scoped_point"', poll)
if len(sites) != 2: fails.append('both arrived_at_scoped_point Succeeded returns must set op.arrived first (found %d)' % len(sites))
if len(re.findall(r'"arrived_at_scoped_point"', poll)) != 2: fails.append('unexpected number of arrived_at_scoped_point returns')
if re.search(r'arrived\s*=\s*false', poll + obs): fails.append('arrived must never be cleared once latched')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
