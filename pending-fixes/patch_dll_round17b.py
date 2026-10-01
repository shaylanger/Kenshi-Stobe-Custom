#!/usr/bin/env python3
"""Stobe.dll round 17b (test inbox): `say` never makes the target talk to herself.

When the selected character is the target (e.g. Malzin selected, `say Malzin ...`),
the speaker falls back to another player character (the squad leader first).
Seen in run 4: "speaker=Malzin target=Malzin" and a confused reply.

Usage: patch_dll_round17b.py <STOBE-src root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "src" / "main.cpp"
s = f.read_text()
old = """    if (!narratorMode && !target)
      return "target not found: " + f[2];
    std::string speakerName, speakerSerial, targetName, targetSerial;
"""
new = """    if (!narratorMode && !target)
      return "target not found: " + f[2];
    if (target && target == speaker && world && world->player) {
      for (size_t i = 0; i < world->player->playerCharacters.size(); ++i) {
        Character *pc = world->player->playerCharacters[i];
        if (pc && pc != target) {
          speaker = pc;
          break;
        }
      }
      if (speaker == target)
        return "speaker and target are the same character";
    }
    std::string speakerName, speakerSerial, targetName, targetSerial;
"""
assert s.count(old) == 1, "anchor"
f.write_text(s.replace(old, new))
print("patched", f)
