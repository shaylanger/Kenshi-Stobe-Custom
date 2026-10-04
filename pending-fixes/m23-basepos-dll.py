#!/usr/bin/env python3
"""m23 16-fullbase: send the player base's real town position with the base snapshot.

The server remembered "Your Outpost" coords from the last zone seen (any save: the base id
66--INGAME:-1:-1 is the same in every save), so a work goal "at Your Outpost" on Full-Base walked
Avarek to Squin (-62461,16346). Usage: m23-basepos-dll.py <STOBE-src root>
"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel
    s = p.read_text()
    for old, new in pairs:
        if new in s:
            continue
        assert s.count(old) == 1, (rel, old[:60], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)

patch("src/PlayerBaseState.h", [
    ("  bool gatesClosed;\n  int gameTs;\n  BaseDetails details;\n",
     "  bool gatesClosed;\n  bool hasTownPos;\n  float townX, townY, townZ; // m23: the base's real position (base ids repeat across saves)\n  int gameTs;\n  BaseDetails details;\n"),
])
patch("src/PlayerBaseState.cpp", [
    ("  gatesClosed = false;\n  gameTs = 0;\n  details.Clear();\n",
     "  gatesClosed = false;\n  hasTownPos = false;\n  townX = townY = townZ = 0.0f;\n  gameTs = 0;\n  details.Clear();\n"),
    ("  out.inside = true;\n  out.baseId = BuildStableBaseId(town, townPosition);\n",
     "  out.inside = true;\n  out.hasTownPos = true;\n  out.townX = townPosition.x;\n  out.townY = townPosition.y;\n  out.townZ = townPosition.z;\n  out.baseId = BuildStableBaseId(town, townPosition);\n"),
    ("       << (snapshot.batteryMode ? \"true\" : \"false\")\n",
     "       << (snapshot.batteryMode ? \"true\" : \"false\")\n"
     "       << (snapshot.hasTownPos ? \",\\\"town_x\\\":\" + ToString(snapshot.townX) + \",\\\"town_y\\\":\" + ToString(snapshot.townY) + \",\\\"town_z\\\":\" + ToString(snapshot.townZ) : std::string())\n"),
])
print("ok")
