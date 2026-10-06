#!/usr/bin/env python3
"""Wire StobeGoals (goal executor moved from KenshiFP) into a STOBE-src tree.
usage: patch_stobe.py <STOBE-src root>   (idempotent: refuses to patch twice)"""
import sys, re
root = sys.argv[1]


def rep(s, old, new, count=1):
    n = s.count(old)
    assert n == count, (n, old[:80])
    return s.replace(old, new)


p = root + '/src/main.cpp'
s = open(p, encoding='utf-8', newline='').read()
assert 'StobeGoals.h' not in s, 'already patched'
nl = '\r\n' if '\r\n' in s else '\n'
s = rep(s, '#include "StobeHarnessBridge.h"' + nl, '#include "StobeHarnessBridge.h"' + nl + '#include "StobeGoals.h"' + nl)
s = rep(s, '''  Log("LIFELIKE_INITIATIVE: flag consumed, initiative turn armed");
}
'''.replace('\n', nl), '''  Log("LIFELIKE_INITIATIVE: flag consumed, initiative turn armed");
}

// StobeGoals.cpp (moved from KenshiFP): post-STT voice range lock and lifelike danger interrupt.
float *StobeGoals_ProximityRadius(void) { return &g_proximityRadius; }
long StobeGoals_ChatInterrupt(void) {
  EnterCriticalSection(&g_stateMutex);
  g_triggerBoredEvent = false;
  LeaveCriticalSection(&g_stateMutex);
  LONG generation = BeginChatInterruptGeneration();
  Log("LIFELIKE_INTERRUPT: danger preempted chat/TTS");
  return (long)generation;
}
'''.replace('\n', nl))
s = rep(s, '''  if (!worldStable) {
    Stobe::UI::ResetNpcContextRenameAction();
'''.replace('\n', nl), '''  if (!worldStable) {
    StobeGoals_HidePanel();
    Stobe::UI::ResetNpcContextRenameAction();
'''.replace('\n', nl))
s = rep(s, '''    ApplyTravelTargets(world);
    RunQueuedItemImageSync();
'''.replace('\n', nl), '''    ApplyTravelTargets(world);
    StobeGoals_Tick(world); // work/task goals, goal panel, action/unequip requests (was KenshiFP)
    RunQueuedItemImageSync();
'''.replace('\n', nl))
open(p, 'w', encoding='utf-8', newline='').write(s)

# build lists kept consistent (build_portable.bat lives outside the repo; patched separately)
p = root + '/CMakeLists.txt'
s = open(p, encoding='utf-8', newline='').read()
if 'StobeGoals.cpp' not in s:
    m = re.search(r'^(\s*)src/StobeHarnessBridge\.cpp\s*$', s, flags=re.M)
    assert m, 'CMake anchor'
    s = s[:m.end()] + '\n' + m.group(1) + 'src/StobeGoals.cpp' + s[m.end():]
    open(p, 'w', encoding='utf-8', newline='').write(s)
p = root + '/Stobe.vcxproj'
s = open(p, encoding='utf-8', newline='').read()
if 'StobeGoals.cpp' not in s:
    m = re.search(r'^(\s*)<ClCompile Include="src\\main\.cpp" />(\r?\n)', s, flags=re.M)
    assert m, 'vcxproj anchor'
    s = s[:m.end()] + m.group(1) + '<ClCompile Include="src\\StobeGoals.cpp" />' + m.group(2) + s[m.end():]
    open(p, 'w', encoding='utf-8', newline='').write(s)
print('patched', root)
