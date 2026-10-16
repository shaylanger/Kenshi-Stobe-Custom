#!/usr/bin/env python3
"""imm26-sfP = NC22 + Hunt grant import no longer demands LIVE sight of the offer's exact animal (row 26-d, 4080-i4 NC20).

Usage: python3 sfPedit.py <tree>      (tree has src/ = NC22 sources; edits src/ActivityRuntimeBindings.cpp in place, CRLF-safe)

Cause (see inbox\\operators\\sfP.txt): the server (imm26-u4, ActivityService.php $resolve, phase 'accept', Hunt only) accepts ANY currently observed
same-source animal when the offered animal wandered or went out of sight, but the native ConcreteRuntimeBindings::ImportGrant re-checks
canISeeThisGuy(<the offer's exact animal>) at the moment the grant arrives. The NPC turns to face the speaker while the player answers, so the
exact animal (100 deg off her new facing in 26-d) is no longer in her view cone and the grant is rejected as activity_discovery_reference_source_mismatch.
Live sight of the exact animal is still required where it matters (route arrival -> NativeHost::Candidates / Discover visible+reachable, Revalidate, Refresh).
ClearGroup keeps its import-time sight clause. A reject now logs ACTIVITY_GRANT_SOURCE_DIAG with the per-clause values.
"""
import sys, io

tree = sys.argv[1]


def load(p):
    s = io.open(p, encoding="utf-8", newline="").read()
    return s, ("\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n")


def sub(s, nl, old, new):
    old = old.replace("\n", nl)
    new = new.replace("\n", nl)
    assert s.count(old) == 1, "anchor count %d: %r" % (s.count(old), old[:90])
    return s.replace(old, new)


p = tree + "/src/ActivityRuntimeBindings.cpp"
s, nl = load(p)
assert "ACTIVITY_GRANT_SOURCE_DIAG" not in s, "sfP already applied"
s = sub(s, nl,
        '  Character* target=(Character*)discoveredObject;\n'
        '  if(!target->getGameData() || !actor->getSensoryData() || !actor->getSensoryData()->canISeeThisGuy(target) ||\n'
        '     (a.kind==Hunt && (target->getGameData()->stringID!=a.sourceId || !target->isAnimal())) ||\n'
        '     (a.kind==ClearGroup && (GroupSource(target)!=a.sourceId ||\n'
        '       std::find(a.agreedTargets.begin(),a.agreedTargets.end(),a.discoveryTargetSerial)==a.agreedTargets.end()))) {\n'
        '   reason="activity_discovery_reference_source_mismatch"; return false;\n'
        '  }\n',
        '  Character* target=(Character*)discoveredObject;\n'
        '  // imm26-sfP (row 26-d): a Hunt grant arrives 10-35 s after the offer, after the NPC turned to face the speaker, and the server (imm26-u4) accepts any\n'
        '  // currently observed same-source animal at ACCEPT. So the offer\'s exact animal need not be in her view cone at import; it stays bound by candidate id,\n'
        '  // serial and pointer identity above, and live sight is still required at dispatch (NativeHost::Candidates/Revalidate, Discover, Refresh). ClearGroup keeps it.\n'
        '  if(!target->getGameData() || !actor->getSensoryData() ||\n'
        '     (a.kind!=Hunt && !actor->getSensoryData()->canISeeThisGuy(target)) ||\n'
        '     (a.kind==Hunt && (target->getGameData()->stringID!=a.sourceId || !target->isAnimal())) ||\n'
        '     (a.kind==ClearGroup && (GroupSource(target)!=a.sourceId ||\n'
        '       std::find(a.agreedTargets.begin(),a.agreedTargets.end(),a.discoveryTargetSerial)==a.agreedTargets.end()))) {\n'
        '   try {\n'
        '    std::ostringstream d; d<<"ACTIVITY_GRANT_SOURCE_DIAG agreement="<<a.id<<" kind="<<(a.kind==Hunt?"Hunt":"ClearGroup")<<" target="<<a.discoveryTargetSerial\n'
        '     <<" gameData="<<(target->getGameData()!=NULL?1:0)<<" sensory="<<(actor->getSensoryData()!=NULL?1:0)\n'
        '     <<" sees="<<((actor->getSensoryData() && actor->getSensoryData()->canISeeThisGuy(target))?1:0)\n'
        '     <<" animal="<<(target->isAnimal()?1:0)\n'
        '     <<" sidMatch="<<((target->getGameData() && target->getGameData()->stringID==a.sourceId)?1:0);\n'
        '    Log(d.str());\n'
        '   } catch(...) { /* Diagnostics never change the grant outcome. */ }\n'
        '   reason="activity_discovery_reference_source_mismatch"; return false;\n'
        '  }\n')
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("sfPedit OK: " + p)
