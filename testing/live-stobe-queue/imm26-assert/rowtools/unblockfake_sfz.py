#!/usr/bin/env python3
"""unblockfake_sfz.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sfz_selftest.sh: answers the sfz per-NPC chance seam statements (markers u3:sznpcold|sznpcset|sznpcrest;
scenario key `npcold`, default 'unset') and delegates everything else to unblockfake_d2.py. Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'sql' and 'u3:sznpcold' in body:
    print(json.load(open(os.environ['FAKE_SCEN'])).get('npcold', 'unset'))
    sys.exit(0)
if kind == 'sql' and ('u3:sznpcset' in body or 'u3:sznpcrest' in body):
    print('UPDATE 1')
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'unblockfake_d2.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
