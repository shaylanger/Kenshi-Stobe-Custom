#!/usr/bin/env python3
"""reloadscen_sff.py <sfj scenario name> [dy,dy,...]   scenario JSON for reloadfake_sff.py / reload-sff-selftest.sh: the reloadscen_sfj.py scenario (rows 23-e: sj23e-*) plus tele_dy = the height
added to Shay's y for the k-th Shay teleport (positive = landed on a cliff top; the last value repeats)."""
import json
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
r = subprocess.run([sys.executable, os.path.join(here, 'reloadscen_sfj.py'), sys.argv[1]], capture_output=True, text=True, check=True)
s = json.loads(r.stdout)
s['tele_dy'] = [float(v) for v in sys.argv[2].split(',')] if len(sys.argv) > 2 else [0.0]
print(json.dumps(s))
