#!/usr/bin/env python3
"""unblockfake_sfs.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sfs_selftest.sh (08-d v2): unblockfake_a.py plus the scenario key
  bored_after1 (lines answering the `# after tick 1` stobelog grep of rd_08d v2; default none).  Everything else is delegated.  Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'h' and '# after tick 1' in body:
    scen = json.load(open(os.environ['FAKE_SCEN']))
    lines = scen.get('bored_after1', [])
    if lines:
        print('\n'.join(lines))
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'unblockfake_a.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
