#!/usr/bin/env python3
"""Stobe.dll round 17e (bug 65): an initiative turn armed by lifelike_initiative.flag
may use the player as the listener.

Run 4: Malzin finished a goal, walked back, the flag was consumed, but the bored
turn was skipped "no eligible NPC listener" (only Malzin + the player nearby), so
her goal report never ran. When the turn comes from the flag and no NPC listener
exists, the player (if in earshot) becomes the listener.

Usage: patch_dll_round17e.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / "src" / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("ChatBox.cpp", [
    ("bool TriggerBoredEvent(GameWorld *world, bool forceDirectorMode,\n",
     "// Set by the lifelike_initiative.flag reader (main.cpp): the next bored turn may\n"
     "// address the player when no NPC listener is around (goal reports, bug 65).\n"
     "bool g_initiativeAllowPlayerListener = false;\n\n"
     "bool TriggerBoredEvent(GameWorld *world, bool forceDirectorMode,\n"),
    ("""  if (listenerIndices.empty()) {
    if (!targetLockedSpeaker) {
      Log("BORED_EVENT: skipped (no eligible NPC listener) speaker=" +
          speaker.name + " candidate_count=" + ToString((int)candidates.size()));
      return false;
    }
  }""",
     """  const bool allowPlayerListener = g_initiativeAllowPlayerListener;
  g_initiativeAllowPlayerListener = false;
  if (listenerIndices.empty()) {
    if (!targetLockedSpeaker) {
      if (allowPlayerListener && playerCanHear && !playerName.empty() &&
          !sameIdentity(playerName, playerSerial, speaker.name, speaker.serial)) {
        listener = playerName;
        listenerSerial = playerSerial;
        Log("BORED_EVENT: initiative turn addresses the player speaker=" + speaker.name);
      } else {
        Log("BORED_EVENT: skipped (no eligible NPC listener) speaker=" +
            speaker.name + " candidate_count=" + ToString((int)candidates.size()));
        return false;
      }
    }
  }"""),
    ("""  } else {
    size_t listenerIndex =
        listenerIndices[(size_t)(rand() % listenerIndices.size())];""",
     """  } else if (listener.empty()) {
    size_t listenerIndex =
        listenerIndices[(size_t)(rand() % listenerIndices.size())];"""),
])

patch("main.cpp", [
    ("// Server/KenshiFP ask for an NPC-initiated turn by writing lifelike_initiative.flag.\nstatic void UpdateLifelikeInitiativeFlag() {",
     "namespace Stobe { namespace UI { extern bool g_initiativeAllowPlayerListener; } } // ChatBox.cpp\n\n"
     "// Server/KenshiFP ask for an NPC-initiated turn by writing lifelike_initiative.flag.\nstatic void UpdateLifelikeInitiativeFlag() {"),
    ("  EnterCriticalSection(&g_stateMutex);\n  g_triggerBoredEvent = true;\n  LeaveCriticalSection(&g_stateMutex);\n  Log(\"LIFELIKE_INITIATIVE: flag consumed, initiative turn armed\");",
     "  EnterCriticalSection(&g_stateMutex);\n  g_triggerBoredEvent = true;\n  Stobe::UI::g_initiativeAllowPlayerListener = true;\n  LeaveCriticalSection(&g_stateMutex);\n  Log(\"LIFELIKE_INITIATIVE: flag consumed, initiative turn armed\");"),
])
