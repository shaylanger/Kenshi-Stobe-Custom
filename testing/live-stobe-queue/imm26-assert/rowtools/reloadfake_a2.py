#!/usr/bin/env python3
"""reloadfake_a2.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-a2-selftest.sh: like reloadfake.py, but the 08-e tick counters (`# rw:ticks` bodies) are run for REAL
(bash) against the fake server log in env FAKE_SRVLOG (the lane log path in the body is replaced), so the grep pipelines themselves are tested. `# rw:srvn` answers 100 (the first 100 log
lines are 'before the load'). Everything else is delegated to reloadfake.py. Never touches a game, ssh or DB."""
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'w' and 'rw:ticks' in body and os.environ.get('FAKE_SRVLOG'):
    b = re.sub(r'^(tail -n \+\d+ )\S+', lambda m: m.group(1) + os.environ['FAKE_SRVLOG'], body.strip())
    r = subprocess.run(['bash', '-c', b], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
