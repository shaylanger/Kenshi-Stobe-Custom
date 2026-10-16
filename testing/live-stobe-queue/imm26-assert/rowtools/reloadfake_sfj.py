#!/usr/bin/env python3
"""reloadfake_sfj.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-sfj-selftest.sh: adds a distance model for the chase recipe of reloaddefs_sfj.sh and delegates everything else to
reloadfake.py (-> tripfake.py -> fakelane.py). Scenario keys (env FAKE_SCEN json) on top of reloadfake.py's: chase_d = [[start, end], ...] one pair per chase in order (ctrl, pre, post);
`stobe-auto where` reports `start` after the Shay teleport (body has `order Shay HOLD_POSITION`), `end` after the `stobe-auto speed 3` call, 8 once the NPC was teleported to Shay.
Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sj'
st = json.load(open(sp)) if os.path.isfile(sp) else {'i': -1, 'phase': 'near'}
cd = scen.get('chase_d')


def save():
    json.dump(st, open(sp, 'w'))


if kind == 'h' and cd:
    if 'order Shay HOLD_POSITION' in body and re.search(r'teleport Shay -?\d', body):
        st['i'] += 1
        st['phase'] = 'start'
        save()
    elif 'stobe-auto speed 3' in body and st['i'] >= 0:
        st['phase'] = 'end'
        save()
    elif re.search(r'teleport (?!Shay )\S.* Shay\b', body):
        st['phase'] = 'near'
        save()
    if re.search(r'stobe-auto where', body) and not scen.get('npc_missing'):
        pair = cd[min(max(st['i'], 0), len(cd) - 1)]
        d = 8.0 if st['phase'] == 'near' else float(pair[0] if st['phase'] == 'start' else pair[1])
        print(f"Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist={d}")
        sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
