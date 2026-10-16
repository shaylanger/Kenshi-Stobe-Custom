#!/usr/bin/env python3
"""reloadscen_sfi.py <name>   scenario JSON for reload-sfi-selftest.sh: the set-A scenarios of reloadscen.py with ONE extra leading say step (the apology of the hunt scene, which is a
stobe_say but not a row step) plus the hunt-scene keys.
Names: 26d-pass 26d-old 26d-reject 26d-nooffer 26d-samewid 26d-complete 26d-nocomplete 26dx-pass 26dx-bad 26e-pass 26e-notrebound 26e-reject (as reloadscen.py)
       26d-blind (the NPC sees no goat: scene bad) 26d-blind-then-sees (sees on the second try) 26d-fallback (first wording gets no proposal, the fallback does) 26d-nogoats"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = {'26d-blind': '26d-pass', '26d-blind-then-sees': '26d-pass', '26d-fallback': '26d-pass', '26d-nogoats': '26d-pass'}.get(n, n)
S = json.loads(subprocess.run([sys.executable, os.path.join(here, 'reloadscen.py'), base], capture_output=True, text=True, check=True).stdout)
S['steps'] = [{'reply': 'It is forgotten.'}] + S['steps']
if n == '26d-blind':
    S['sees'] = False
elif n == '26d-blind-then-sees':
    S['sees'] = [False, False, False, True]          # try 1 (3 goats) all blind, then the second try sees
elif n == '26d-nogoats':
    S['spawn_empty'] = True
elif n == '26d-fallback':
    S['steps'].insert(1, {'reply': 'Let us agree on where we go first.'})
    S['act'] = [[]] + S['act']
print(json.dumps(S))
