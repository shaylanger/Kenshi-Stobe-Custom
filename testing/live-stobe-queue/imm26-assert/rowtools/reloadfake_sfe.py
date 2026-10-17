#!/usr/bin/env python3
"""reloadfake_sfe.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-sfe-selftest.sh: answers the extra commands of the 24-c / 26-f recipes (reloaddefs_sfe.sh) and
delegates everything else to reloadfake.py (-> tripfake.py -> fakelane.py). Scenario keys (env FAKE_SCEN json): bandit_ids (serial/idx ids the spawn prints), sees (bool: Cind
sees the bandits), reseat_idx (idx part the bandits get after the load), alive (bandits alive after the load, chars 600 probe), insert_ok. Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
ids = scen.get('bandit_ids', ['#3000000001/1', '#3000000002/1', '#3000000003/1', '#3000000004/1'])
if kind == 'h':
    if 'stobe-auto spawn "Dust Bandit"' in body:
        print('spawned %d Dust Bandit: ' % len(ids) + ' | '.join('Dust Bandit %s [Dust Bandits] pos=-47335,725,-55640' % i for i in ids))
        sys.exit(0)
    if 'stobe-auto senses' in body:
        print('sees=1 dist=30' if scen.get('sees', True) else 'sees=0 dist=30')
        sys.exit(0)
    if 'stobe-auto faction' in body:
        print('Cind [Hungry Bandit] #2529907200/2 [Nameless]')
        sys.exit(0)
    if 'stobe-auto chars 300 "Dust Bandit' in body:
        idx = scen.get('reseat_idx', 7)
        print('%d within 300.0: ' % len(ids) + ' | '.join('Dust Bandit %s [Dust Bandits] pos=1,1,1 dist=30.0' % re.sub(r'/\d+$', '/%d' % idx, i) for i in ids))
        sys.exit(0)
    if 'stobe-auto chars 600 "Dust Bandit' in body:   # fix26fcamp probe after the load: scenario key alive = how many of the bandits are still alive (default all)
        idx = scen.get('reseat_idx', 7); al = ids[:scen.get('alive', len(ids))]
        print('%d within 600.0: ' % len(al) + ' | '.join('Dust Bandit %s [Dust Bandits] pos=1,1,1 dist=30.0' % re.sub(r'/[0-9]+$', '/%d' % idx, i) for i in al))
        sys.exit(0)
    if 'stobe-auto chars 150 "Holy Sentinel' in body:
        print('1 within 150.0: Holy Sentinel #4000000001/1 [Holy Nation] pos=1,1,1 dist=60.0')
        sys.exit(0)
elif kind == 'sql' and body.startswith('insert into eventlog'):
    print('INSERT 0 1' if scen.get('insert_ok', True) else 'ERROR: insert failed')
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
