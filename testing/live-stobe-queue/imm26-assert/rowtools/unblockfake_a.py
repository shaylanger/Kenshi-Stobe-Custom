#!/usr/bin/env python3
"""unblockfake_a.py <kind h|w|sql> <body>   OFFLINE lane simulator for the unblock rows (unblock_a_selftest.sh); delegates everything it does not know to reloadfake.py
-> tripfake.py -> fakelane.py. Extra scenario keys (env FAKE_SCEN json; counters in FAKE_STATE + '.ub'; every list = one answer per call, the last repeats):
  stream (i4_bored response lines per call; default ok + HTTP=200)  tlog (server-log lines per i4_bored call)  cstate (stobe_state JSON per u_state_combat call)
  spawn (spawn answer; 'ERROR ...' = fail)  combat_rows (count)
Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.ub'
st = json.load(open(sp)) if os.path.isfile(sp) else {}


def pick(key, default):
    seq = scen.get(key, default)
    i = st.get(key, 0)
    st[key] = i + 1
    json.dump(st, open(sp, 'w'))
    return seq[min(i, len(seq) - 1)]


def out(lines):
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


if kind == 'w':
    if 'u:srvn' in body:
        out(['100'])
    if 'u:stream' in body:
        out(pick('stream', [['{"status":"ok"}', 'HTTP=200']]))
    if 'u:tlog' in body:
        out(pick('tlog', [[]]))
elif kind == 'h':
    if 'u:state' in body:
        out([pick('cstate', ['{"in_combat": false}'])])
    if 'stobe-auto spawn "Hungry Bandit"' in body:
        out([scen.get('spawn', 'spawned 1/1 Hungry Bandit: Vren [Hungry Bandit] #77/1 [Holy Nation Outlaws] pos=1,2,3')])
elif kind == 'sql':
    if "type='combat' and rowid>" in body:
        out([str(scen.get('combat_rows', 3))])
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
