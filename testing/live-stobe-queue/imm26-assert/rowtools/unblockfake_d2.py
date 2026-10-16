#!/usr/bin/env python3
"""unblockfake_d2.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_d2_selftest.sh: answers the d2 hearsay-presence grep (scenario key `hearsay`: match count, default 2)
and delegates everything else to unblockfake_d.py. Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'w' and 'u3:hearsay' in body:
    print(json.load(open(os.environ['FAKE_SCEN'])).get('hearsay', 2))
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'unblockfake_d.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
