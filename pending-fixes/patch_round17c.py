#!/usr/bin/env python3
"""Server round 17c: "resume/try again" also restarts a BLOCKED work goal
(KenshiFP round 17 accepts RESUME on BLOCKED).

Usage: patch_round17c.py <StobeServer root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "lib" / "task_goal_functions.php"
s = f.read_text()
old = "[$actor, match($command){'PAUSE'=>'{ACTIVE}','RESUME'=>'{PAUSED}',default=>'{ACTIVE,PAUSED}'}]"
new = "[$actor, match($command){'PAUSE'=>'{ACTIVE}','RESUME'=>'{PAUSED,BLOCKED}',default=>'{ACTIVE,PAUSED}'}]"
assert s.count(old) == 1, "anchor"
f.write_text(s.replace(old, new))
print("patched", f)
