#!/usr/bin/env python3
"""reloadscen_sf26ad.py <name>   scenario JSON for reload-sf26ad-selftest.sh = a reloadscen_sf26bd.py scenario with the continuation delayed (ticket 26-d).
Names: 26d-pass (continuation at once) | 26d-delayed (2 dumps after the s3 say show the old record accepted + resume.state pending, then the continuation) | 26d-never (pending forever)
       26dx-pass 26e-pass (as sf26bd / sfi)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = {'26d-delayed': '26d-pass', '26d-never': '26d-pass'}.get(n, n)
S = json.loads(subprocess.run([sys.executable, os.path.join(here, 'reloadscen_sf26bd.py'), base], capture_output=True, text=True, check=True).stdout)
if n in ('26d-delayed', '26d-never'):
    acc = S['act'][1][0].split('|')
    acc[9] = 'pending'
    pend = ['|'.join(acc)]
    post = S['act'][2]
    S['act'] = S['act'][:2] + ([pend, pend, post] if n == '26d-delayed' else [pend])
print(json.dumps(S))
