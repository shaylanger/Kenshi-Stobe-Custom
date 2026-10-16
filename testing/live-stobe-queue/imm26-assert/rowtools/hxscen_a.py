#!/usr/bin/env python3
"""hxscen_a.py <name>   prints the hxfake_a.py scenario JSON used by hxa-selftest.sh (base = hxscen.py base + the family-A defaults)."""
import json
import os
import subprocess
import sys

n = sys.argv[1]
base = json.loads(subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hxscen.py'), 'base'], capture_output=True, text=True).stdout)
base['rel'] = {'Rethar Faction': 20.0, 'Bob Faction': 20.0}
base['steps'] = [dict(base['steps'][0]) for _ in range(60)]   # 01-bx = 19 says, 02-cx = 8, 01-cx = 12
s = base
if n == 'base':           pass
elif n == 'rel-inband':   s['rel'] = {'Bob Faction': -80.0, 'Rethar Faction': 65.0}
elif n == 'norelwrite':   s['norelwrite'] = True
elif n == 'samefac':      s['fac'] = {'Rethar': 'Same Faction', 'Bob': 'Same Faction'}
elif n == 'nostranger':   s['entries'] = ['Rethar', 'Bob']
elif n == 'combat':       s['combat'] = ['Rethar']
elif n == 'noseed':       s['seed'] = ''
elif n == 'noprinciple':  s['noprinciple'] = True
elif n == 'profile_rewrite': s['profile_rewrite'] = True
elif n == 'panel_err':    s['panel_err'] = True
elif n == 'panel_silent': s['panel'] = 'NPC INFO | Cind [Hungry Bandit] | WHAT YOU HAVE LEARNED: nothing yet'
elif n == 'noreply':      s['steps'] = s['steps'][:1]
else: raise SystemExit(f'unknown scenario {n}')
print(json.dumps(s))
