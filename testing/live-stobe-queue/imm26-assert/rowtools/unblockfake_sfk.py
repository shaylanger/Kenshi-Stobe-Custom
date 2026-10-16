#!/usr/bin/env python3
"""unblockfake_sfk.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sfk_selftest.sh (rows 23-a / 11-b recipe v2). Answers the sfK-specific calls and delegates the rest to
unblockfake_f.py (scenario key chain == 'f', the 23-a rows: native-walk helpers) or unblockfake_a.py (11-b rows).
Extra scenario keys (env FAKE_SCEN; counters in FAKE_STATE + '.sfk'): crowded (bool: strangers always listed by `chars`)  fight_fail (bool)  update_fail (bool)  calm_wrong (bool: the calm
teleport names another serial)  ko_counts (list per `sfk:ko` call, last repeats)  destpoint ('x y z': the newest agreement carries that destination_point).
Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sfk'
st = json.load(open(sp)) if os.path.isfile(sp) else {'ko': 0}
here = os.path.dirname(os.path.abspath(__file__))


def out(lines):
    print('\n'.join(lines))
    sys.exit(0)


SQUAD = 'Shay #1/1 [Nameless] pos=0,0,0 dist=0.0 | Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=9.0 | Malzin #2740478464/2 [Nameless] pos=1,1,2 dist=9.5'
if kind == 'h':
    if 'sfk:scene' in body:   # the filtered pipeline output of sfk_scene (strangers only; the real pipeline runs on the lane)
        out(['Rethar Dax #5/1 [Outlaw Watch] pos=2,2,2 dist=30.0 race=x'] if scen.get('crowded') else [])
    if 'stobe-auto chars' in body:
        extra = ' | Rethar Dax #5/1 [Outlaw Watch] pos=2,2,2 dist=30.0 race=x' if scen.get('crowded') else ''
        out(['%d within 300.0: %s%s' % (3 + (1 if extra else 0), SQUAD, extra)])
    if 'sfk:ko' in body:
        seq = scen.get('ko_counts', [0])
        i = st['ko']; st['ko'] += 1; json.dump(st, open(sp, 'w'))
        out([str(seq[min(i, len(seq) - 1)])])
    if 'stobe-auto fight' in body:
        if scen.get('fight_fail'):
            out(['same faction (Traders Guild): move one first with faction <npc> <faction>'])
        out(['Cind [Hungry Bandit] [Traders Guild] and Vren [Dust Bandits] fight (factions set to -100)'])
    m = re.search(r"stobe-auto teleport '#(\d+/\d+)' ", body)
    if m:
        ser = '999/9' if scen.get('calm_wrong') else m.group(1)
        out(['teleported: Hungry Bandit #%s [Dust Bandits] pos=-53200.0,957.0,4893.0 dist=2993.4 moved=1 off_target=0.0 method=teleport' % ser, 'Cind [Hungry Bandit] ordered NULL_TASK (has_orders=0)'])
elif kind == 'sql':
    if body.startswith('update eventlog'):
        out(['ERROR: simulated update failure'] if scen.get('update_fail') else ['UPDATE 1'])
    if body.startswith("select data from eventlog where type='travel_agreement' order by rowid desc limit 1") and scen.get('destpoint'):
        x, y, z = scen['destpoint'].split()
        out(['{"agreement_id":"trip-aaa","destination_point":{"x":%s,"y":%s,"z":%s},"status":"ACCEPTED"}' % (x, y, z)])
mod = 'unblockfake_f.py' if scen.get('chain') == 'f' else 'unblockfake_a.py'
r = subprocess.run([sys.executable, os.path.join(here, mod), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
