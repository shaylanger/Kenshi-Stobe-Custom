#!/usr/bin/env python3
"""hxscen_cx3.py <name>   scenario JSON for hx-selftest_cx3.sh: everything of hxscen_cx2.py plus
  cindfar : Cind (the NPC under test) is 5000 u from Shay before the E samples: must be SETUP-FAIL "not within 60 u of Shay" (imm26-fix15bx05cx)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = 'base' if n == 'cindfar' else n
s = json.loads(subprocess.run([sys.executable, os.path.join(here, 'hxscen_cx2.py'), base], capture_output=True, text=True, check=True).stdout)
if n == 'cindfar':
    s['pos'] = {'Cind': '-43000.0,1500.0,2960.0'}
print(json.dumps(s))
