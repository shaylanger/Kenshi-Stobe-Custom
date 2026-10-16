# NC25 source test (row 22-b): a terminal owned-travel transition must queue the actor and the main loop must push one
# immediate context snapshot with reason 'travel_terminal' (so the server ingests the receipt / situated arrival event).
# Usage: python3 native_travel_terminal_push_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
rd = lambda n: io.open(src + '/' + n, encoding='utf-8').read()
cpp, hdr, main = rd('NativeTravelLifecycle.cpp'), rd('NativeTravelLifecycle.h'), rd('main.cpp')
fails = []
if 'TakeTerminalActors' not in hdr: fails.append('header lacks TakeTerminalActors')
m = re.search(r'void Emit\(Receipt &r.*?\n\}\n', cpp, re.S)
emit = m.group(0) if m else ''
if not m: fails.append('Emit() not found')
if 'terminalActors.push_back' not in emit: fails.append('Emit does not queue terminal actors')
if not re.search(r'changed\s*&&\s*terminal', emit): fails.append('queue must be once per transition (changed && terminal)')
if 'std::find(terminalActors' not in emit: fails.append('queue must dedupe actors')
if 'terminalActors.size() <' not in emit: fails.append('queue must be bounded')
if 'std::vector<unsigned int> TakeTerminalActors()' not in cpp: fails.append('TakeTerminalActors not defined')
if '#include <algorithm>' not in cpp: fails.append('algorithm not included')
t = re.search(r'NativeTravelLifecycle::Tick\(world.*?ApplyFollowTargets\(world\);', main, re.S)
blk = t.group(0) if t else ''
if not t: fails.append('main loop Tick..ApplyFollowTargets block not found')
if 'TakeTerminalActors()' not in blk or '"travel_terminal"' not in blk: fails.append('main loop does not push travel_terminal after Tick')
if main.count('"travel_terminal"') != 1: fails.append('travel_terminal must have exactly one caller')
if 'false);' not in blk or 'PushImmediateContextSnapshot(terminalNpc, "travel_terminal", false)' not in blk: fails.append('push must be asynchronous (synchronous=false)')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
