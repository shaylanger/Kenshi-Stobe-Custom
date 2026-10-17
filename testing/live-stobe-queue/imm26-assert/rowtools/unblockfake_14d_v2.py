#!/usr/bin/env python3
"""unblockfake_14d_v2.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_14d_v2_selftest.sh (imm26-fix14dtool F3): answers the new `# d14:spawnfar` call (scenario key `spawnfar`, an answer
text) and delegates everything else to unblockfake_14d.py (whose `spawn` key now answers the NEAR-five spawn). Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
if kind == 'h' and re.search(r'# d14:spawnfar', body):
    scen = json.load(open(os.environ['FAKE_SCEN']))
    print(scen.get('spawnfar', 'spawned 1/1 Dust Bandit: Dust Bandit #901000001/7 race=Greenlander'))
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(here, 'unblockfake_14d.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
