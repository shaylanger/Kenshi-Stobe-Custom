#!/usr/bin/env python3
"""NC25 FIX A (row 22-b, imm26-nat25): push an immediate context snapshot ('travel_terminal') once per terminal
owned-travel transition so the server sees the receipt (completed/failed/...) and the situated arrival event.
Usage: python3 nc25a_edit.py <tree>   (edits src/NativeTravelLifecycle.{h,cpp} and src/main.cpp in place, CRLF-safe; refuses a second run)."""
import sys, io
tree = sys.argv[1]
def edit(rel, pairs, marker):
    p = tree + "/src/" + rel
    s = io.open(p, encoding="utf-8", newline="").read()
    nl = "\r\n" if s.count("\r\n") * 2 > s.count("\n") else "\n"
    assert marker not in s, "NC25 A already applied: " + rel
    for old, new in pairs:
        o2, n2 = old.replace("\n", nl), new.replace("\n", nl)
        assert s.count(o2) == 1, "anchor count %d in %s: %r" % (s.count(o2), rel, old[:70])
        s = s.replace(o2, n2)
    io.open(p, "w", encoding="utf-8", newline="").write(s)

edit("NativeTravelLifecycle.h", [(
'''void Failed(unsigned int actor, bool follow, const std::string &reason);
''',
'''void Failed(unsigned int actor, bool follow, const std::string &reason);
// NC25 (22-b): actors whose receipt entered a terminal phase since the last call (each at most once per
// transition). The main loop pushes an immediate context snapshot for each ('travel_terminal').
std::vector<unsigned int> TakeTerminalActors();
''' ), ('''#include <string>
''', '''#include <string>
#include <vector>
''')], "TakeTerminalActors")

edit("NativeTravelLifecycle.cpp", [(
'''struct Lock { Mutex &m; Lock(Mutex &value):m(value){EnterCriticalSection(&m.cs);} ~Lock(){LeaveCriticalSection(&m.cs);} };
''',
'''struct Lock { Mutex &m; Lock(Mutex &value):m(value){EnterCriticalSection(&m.cs);} ~Lock(){LeaveCriticalSection(&m.cs);} };
std::vector<unsigned int> terminalActors; // NC25: guarded by mutex; drained by TakeTerminalActors()
'''), (
'''  r.released = released; r.arrived = arrived; r.evidence = ++sequence;
  if (changed) Log(''',
'''  r.released = released; r.arrived = arrived; r.evidence = ++sequence;
  if (changed && terminal && r.actor != 0 && terminalActors.size() < 32 &&
      std::find(terminalActors.begin(), terminalActors.end(), r.actor) == terminalActors.end())
    terminalActors.push_back(r.actor); // NC25: one immediate context push per terminal transition
  if (changed) Log('''), (
'''void Failed(unsigned int actor, bool follow, const std::string &reason) {
''',
'''std::vector<unsigned int> TakeTerminalActors() {
  Lock lock(mutex);
  std::vector<unsigned int> out; out.swap(terminalActors);
  return out;
}
void Failed(unsigned int actor, bool follow, const std::string &reason) {
'''), ('''#include <vector>
''', '''#include <vector>
#include <algorithm>
''')], "TakeTerminalActors")

edit("main.cpp", [(
'''    Stobe::NativeTravelLifecycle::Tick(world, CurrentGameTsSeconds());
    ApplyFollowTargets(world);
''',
'''    Stobe::NativeTravelLifecycle::Tick(world, CurrentGameTsSeconds());
    { // NC25 (22-b): terminal owned-travel phase -> one immediate context snapshot so the server ingests the
      // receipt and detects the situated arrival event.
      std::vector<unsigned int> terminalActors = Stobe::NativeTravelLifecycle::TakeTerminalActors();
      for (size_t ti = 0; ti < terminalActors.size(); ++ti) {
        try {
          Character *terminalNpc = FindCharacterBySerial(world, terminalActors[ti]);
          if (terminalNpc && (uintptr_t)terminalNpc > 0x1000)
            PushImmediateContextSnapshot(terminalNpc, "travel_terminal", false);
        } catch (...) {
        }
      }
    }
    ApplyFollowTargets(world);
''')], "travel_terminal")
print("nc25a_edit applied")
