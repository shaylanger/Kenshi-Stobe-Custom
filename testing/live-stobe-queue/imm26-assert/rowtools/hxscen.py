#!/usr/bin/env python3
"""hxscen.py <name>   prints the hxfake.py scenario JSON used by hx-selftest.sh."""
import json
import sys

n = sys.argv[1]
s = {'nsteps': 12, 'reply': 'Fine, bread now, 20 cats later.'}
if n == 'noreply':        s['nsteps'] = 1
elif n == 'spawnfail':    s['spawn_fail'] = True
elif n == 'roster4':      s['roster'] = [f'X{i} #{i}/1 [F] pos=0,0,0' for i in range(4)]
elif n == 'noseed':       s['seed'] = ''
elif n == 'nomove':       s['nomove'] = True
elif n == 'noprice':      s['reply'] = 'Hmm, I will think about it.'
elif n == 'nostarter':    s['starter_row'] = ''
elif n == 'warm':         s['tpl'] = 0
elif n == 'combat':       s['follow'] = ['{"in_combat": true}'] * 3 + ['{"in_combat": false}'] * 3
elif n == 'nocind':       s['missing'] = ['Cind']
elif n == 'far':          s['pos'] = {'Cind': '-47700.0,1500.0,2960.0'}
elif n == 'base':         pass
else: raise SystemExit(f'unknown scenario {n}')
s['steps'] = [{'reply': s['reply'], 'prompt': 'Action Flags: calm', 'server': '', 'events': [], 'full': []} for _ in range(s['nsteps'])]
print(json.dumps(s))
