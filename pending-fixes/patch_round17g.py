#!/usr/bin/env python3
"""Server round 17g (bug 56): KenshiFP gameplay actions (BODYGUARD, PATROL, ...) use
the stored-serial fallback for the actor, like goals do since round 17 (bug 45).

Run 4: "Malzin, guard me" -> BODYGUARD@Shay skipped "actor serial was unavailable"
(she was at the stone mine, outside the people list) and she said "I couldn't
actually carry that action out."

Usage: patch_round17g.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "chat_helper_functions.php"
s = f.read_text()
old = "    $actorSerial = stobeResolveLiveParticipantSerial($safeActor);\n"
new = "    $actorSerial = stobeResolveLiveParticipantSerial($safeActor, true);\n"
assert s.count(old) == 1, "anchor"
f.write_text(s.replace(old, new))
print("patched", f)
