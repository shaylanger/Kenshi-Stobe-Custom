#!/usr/bin/env python3
"""hxscen_cx2.py <name>   scenario JSON (for hxfake.py) used by hx-selftest_cx2.sh (05-cx v2).  Starts from hxscen_b.py (steps E1 E2 E3 H1 H2 H3 N1 N2 N3) and adds:
  e2back  : Malzin walked back, the E2 and E3 prompts list her (the first 05-cx failure): must be SETUP-FAIL naming E2, never FAIL"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = 'base' if n == 'e2back' else n
s = json.loads(subprocess.run([sys.executable, os.path.join(here, 'hxscen_b.py'), base], capture_output=True, text=True, check=True).stdout)
if n == 'e2back':
    for i in (1, 2):
        s['steps'][i]['prompt'] = 'Action Flags: calm\n## Nearby People Awareness\n### Person\nShay | the player\n### Person\nMalzin (female) | standing nearby\n## Other section\nx\n'
print(json.dumps(s))
