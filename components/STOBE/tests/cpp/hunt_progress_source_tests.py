# imm26 huntA (NC27) source test: wiring of the Hunt progress-by-damage signal and the give-up line.
# Fails on NC25/NC26 src (no NC27 edits); passes after nc27a_edit.py + nc27b_edit.py.  Usage: python3 hunt_progress_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
def rd(n): return io.open(src + '/' + n, encoding='utf-8', newline='').read().replace('\r\n', '\n')
goals, bind, tr, ctl, danger = rd('ActivityGoals.cpp'), rd('ActivityRuntimeBindings.cpp'), rd('ActivityTransport.cpp'), rd('ActivityController.cpp'), rd('ActivityDanger.cpp')
fails = []
# 1. damage block: Hunt only, own pending Attack only, same target, resets lastProgress_, sits BEFORE the timeout check
i = goals.find('NC27A (Shay')
j = goals.find('activity_no_verified_progress', i if i >= 0 else 0)
if i < 0 or j < i:
    fails.append('NC27A damage block missing or after the timeout check')
else:
    blk = goals[i:j]
    for need, why in (('terms_.kind == Hunt', 'Hunt-only guard'), ('pendingCommand_ == Attack', 'own Attack order only'),
                      ('healthSerial_ == target_.serial', 'same-target comparison'), ('f.target.healthValid', 'unreadable health = no reset'),
                      ('lastProgress_ = now;', 'timer reset'), ('ACTIVITY_PROGRESS_DIAG reset=target_damage', 'diag line')):
        if need not in blk: fails.append('damage block lacks ' + why + ' (' + need + ')')
# 2. the signal is read for Hunt only, via the flesh reader
if not re.search(r'if\(a\.kind==Hunt\)\s*t\.healthValid=TargetFleshTotal\(target,t\.health\)', bind): fails.append('Refresh does not read target flesh for Hunt only')
if 'bool TargetFleshTotal(' not in danger: fails.append('TargetFleshTotal not defined in ActivityDanger.cpp')
# 3. give-up line: queued only for a FAILED report accepted by the server, serviced from the game-thread update, cleared on Reset
if not re.search(r'if\(phase=="failed" && S\(\)\.endingSpeech\.size\(\)<16\)', tr): fails.append('EndingSpeechRequest not queued only for phase=="failed"')
if 'ServiceEndingSpeech(world); // NC27B' not in ctl: fails.append('ServiceEndingSpeech not called from UpdateActivityController')
if 'endingSpeechJobs.clear();' not in ctl: fails.append('Reset does not clear endingSpeechJobs')
if 'TriggerOptionalBoredTurn(' not in ctl: fails.append('give-up speech does not use the existing targeted optional bored turn')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
