#!/usr/bin/env python3
"""Stobe.dll round 17d (bug 59): read lifelike_initiative.flag.

The server (negotiation directives) and KenshiFP (goal finished/blocked near the
player) write RE_Kenshi\\mods\\Stobe\\lifelike_initiative.flag to ask for an
NPC-initiated turn, but STOBE 1.3.1 has no reader, so nothing happened (run 4:
Malzin walked back after finishing her goal and said nothing). Poll it once a
second; when present, delete it and arm the bored/initiative event (same path the
lifelike event initiative uses). Log: LIFELIKE_INITIATIVE: flag ...

Usage: patch_dll_round17d.py <STOBE-src root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "src" / "main.cpp"
s = f.read_text()
pairs = [
    ("static void UpdateTestInbox(GameWorld *world, Character *sel) {\n",
     """// Server/KenshiFP ask for an NPC-initiated turn by writing lifelike_initiative.flag.
static void UpdateLifelikeInitiativeFlag() {
  static DWORD lastPoll = 0;
  DWORD now = GetTickCount();
  if (now - lastPoll < 1000)
    return;
  lastPoll = now;
  const std::string path = GetTestInboxDir() + "\\\\lifelike_initiative.flag";
  if (GetFileAttributesA(path.c_str()) == INVALID_FILE_ATTRIBUTES)
    return;
  DeleteFileA(path.c_str());
  if (!g_enableBoredEvents) {
    Log("LIFELIKE_INITIATIVE: flag ignored (bored events disabled)");
    return;
  }
  EnterCriticalSection(&g_stateMutex);
  g_triggerBoredEvent = true;
  LeaveCriticalSection(&g_stateMutex);
  Log("LIFELIKE_INITIATIVE: flag consumed, initiative turn armed");
}

static void UpdateTestInbox(GameWorld *world, Character *sel) {
"""),
    ("  UpdateTestInbox(worldUi, sel);\n",
     "  UpdateTestInbox(worldUi, sel);\n  UpdateLifelikeInitiativeFlag();\n"),
]
for old, new in pairs:
    assert s.count(old) == 1, f"anchor: {old[:50]!r}"
    s = s.replace(old, new)
f.write_text(s)
print("patched", f)
