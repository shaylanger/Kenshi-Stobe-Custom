#!/usr/bin/env python3
"""reloadfake_sff.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-sff-selftest.sh (reloaddefs_sff.sh anchor ping-pong chase). Models positions: Shay and the NPC start at the same
point; `teleport Shay x y z` puts Shay at (x, y + tele_dy[k], z) (k = number of Shay teleports so far, the last list entry repeats: a cliff = a positive dy), `teleport '<npc>' Shay` puts the NPC on
Shay, `stobe-auto where Shay` / `where '<npc>'` print their pos=. The NPC `dist=` comes from the scenario key chase_d = [[start, end], ...] (one pair per chase: ctrl, pre, post) exactly like
reloadfake_sfj.py: `start` after a Shay teleport (the NPC stays where it was; after `speed 3` a closing pair puts it `end` u from Shay), `end` after `stobe-auto speed 3`, 8 after the NPC was put on Shay. Everything else goes to reloadfake.py. Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sf'
P0 = [-53092.0, 990.5, 4842.3]
st = json.load(open(sp)) if os.path.isfile(sp) else {'nsp': 0, 'ntp': 0, 'phase': 'near', 'shay': P0, 'npc': P0}
cd = scen.get('chase_d')
dys = scen.get('tele_dy', [0])


def save():
    json.dump(st, open(sp, 'w'))


def fmt(p):
    return ','.join(str(round(v, 1)) for v in p)


if kind == 'h' and cd:
    body = chr(10).join(l for l in body.split(chr(10)) if not l.startswith('[ -n "" ]'))   # conditional lines the real shell skips (tr_quiet: TR_SCENE unset)
    for m in re.finditer(r'teleport Shay (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+)', body):
        dy = dys[min(st['ntp'], len(dys) - 1)]
        st['ntp'] += 1
        st['shay'] = [float(m.group(1)), float(m.group(2)) + dy, float(m.group(3))]
        st['phase'] = 'start'
    if re.search(r"teleport (?!Shay )\S.* Shay\b", body):
        st['npc'] = list(st['shay'])
        st['phase'] = 'near'
    if 'stobe-auto speed 3' in body:
        pr = cd[min(st['nsp'], len(cd) - 1)]
        if pr[1] < pr[0]:   # a follower closes in: the NPC ends pr[1] u from Shay (along x)
            st['npc'] = [st['shay'][0] + pr[1], st['shay'][1], st['shay'][2]]
        st['nsp'] += 1
        st['phase'] = 'end'
    save()
    if re.search(r'stobe-auto where Shay', body):
        print(f"Shay [Player] #1/0 pos={fmt(st['shay'])} dist=0.0")
        sys.exit(0)
    if re.search(r'stobe-auto where', body) and not scen.get('npc_missing'):
        pair = cd[min(max(st['nsp'] if st['phase'] != 'end' else st['nsp'] - 1, 0), len(cd) - 1)]
        d = 8.0 if st['phase'] == 'near' else float(pair[0] if st['phase'] == 'start' else pair[1])
        print(f"Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos={fmt(st['npc'])} dist={d}")
        sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
