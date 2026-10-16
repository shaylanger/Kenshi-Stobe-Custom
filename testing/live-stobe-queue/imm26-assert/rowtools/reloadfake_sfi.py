#!/usr/bin/env python3
"""reloadfake_sfi.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-sfi-selftest.sh: answers the extra commands of the hunt26a-scene recipes (reloaddefs_sfi.sh) and delegates
everything else to reloadfake.py (-> tripfake.py -> fakelane.py). Scenario keys: goat_ids (ids the chars answer lists), sees (bool or list per senses call: does the NPC see the goats),
spawn_empty (bool: chars lists no goat), delivered (bool: RECHAT_TIMING line shows up). Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sfi'
st = json.load(open(sp)) if os.path.isfile(sp) else {'senses': 0}
ids = scen.get('goat_ids', ['#1840332032/3', '#2189086976/3', '#3750854400/3'])
if kind == 'h':
    if 'stobe-auto spawn "wild goats"' in body:
        if scen.get('spawn_empty'):
            print('spawned 0')
            print('0 within 80.0:')
        else:
            print('spawned %d wild goats' % len(ids))
            print('%d within 80.0: ' % len(ids) + ' | '.join('Goat %s [Herbivore] pos=-49405,1664,3645 dist=20.0' % i for i in ids))
        sys.exit(0)
    if 'stobe-auto senses' in body:
        sees = scen.get('sees', True)
        if isinstance(sees, list):
            v = sees[min(st['senses'], len(sees) - 1)]
            st['senses'] += 1
            json.dump(st, open(sp, 'w'))
        else:
            v = sees
        print('sees=1 hears=1 fov=1 dist=21' if v else 'sees=0 hears=0 fov=0 dist=21')
        sys.exit(0)
    if 'stobe-auto faction' in body:
        print('Cind [Hungry Bandit] #2529907200/2 [Traders Guild]')
        sys.exit(0)
    if 'RECHAT_TIMING' in body:
        print('DELIVERY_CONFIRMED RECHAT_TIMING: follow-up dispatch scheduled' if scen.get('delivered', True) else 'DELIVERY_CONFIRMED ')
        sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
