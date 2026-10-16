#!/usr/bin/env python3
"""unblockscen_sfs.py <name>   scenario JSON (for unblockfake_sfs.py) used by unblock_sfs_selftest.sh (08-d v2).  Starts from unblockscen_a.py 08d-pass and sets the two logs:
  bored        = whole log since the request: the tick-1 ARRIVAL remark (SAY with the topic word 'Squin') + the tick marker   (what v1 checked)
  bored_after1 = only the lines after tick 1
Names: sfs-pass (arrival remark in `bored` only: v2 PASS, v1 FAIL no_npc_ask)  sfs-ask (a SAY about the furs AFTER tick 1: FAIL no_npc_ask)  sfs-open (topic not closed)
       sfs-claim (closed but a claim row for the topic exists)  sfs-neg (negative control, topic stays open)  sfs-nomark (no bored_log_after1.txt would exist: not produced here)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = {'sfs-pass': '08d-pass', 'sfs-ask': '08d-pass', 'sfs-open': '08d-open', 'sfs-claim': '08d-claim', 'sfs-neg': '08d-neg-pass'}.get(n)
if base is None:
    raise SystemExit('unknown scenario ' + n)
s = json.loads(subprocess.run([sys.executable, os.path.join(here, 'unblockscen_a.py'), base], capture_output=True, text=True, check=True).stdout)
ARRIVAL = 'ACTION_EXEC: SAY [Cind]: I\'ll be around Squin a while, take your time. (NPC)'
TICK = 'BORED_EVENT dispatched Cind->Shay mode=director'
s['bored'] = [TICK, ARRIVAL, TICK]
s['bored_after1'] = [TICK]
if n == 'sfs-ask':
    s['bored'] = [TICK, ARRIVAL, TICK, 'ACTION_EXEC: SAY [Cind]: Did you sell your furs yet? (NPC)']
    s['bored_after1'] = [TICK, 'ACTION_EXEC: SAY [Cind]: Did you sell your furs yet? (NPC)']
print(json.dumps(s))
