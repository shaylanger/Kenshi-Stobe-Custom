#!/usr/bin/env python3
"""unblockfake_d.py <kind h|w|sql> <body>   OFFLINE lane simulator for row 03-b (unblock_d_selftest.sh); delegates everything it does not know to unblockfake_a.py
-> reloadfake.py -> tripfake.py -> fakelane.py. Every 03-b command carries a marker `u3:<name>`. Scenario keys (env FAKE_SCEN json; counters in FAKE_STATE + '.ud';
every list = one answer per call, the last repeats):
  chars (list of chars entries)  counts (lines holder|rows|about_shay)  state (stobe_state JSON per call)  crow (lines)  sev  rank  now  chance  brow (lists of lines per call)
  stream (response lines per pair request)  tlog (server-log lines per pair request)
Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.ud'
st = json.load(open(sp)) if os.path.isfile(sp) else {}
OK = ['{"status":"ok"}', 'HTTP=200']
CHARS = ['Shay #1/1 [Nameless] pos=0,0,0 dist=0.0', 'Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=9.0', 'Rethar Dax #5/1 [Outlaw Watch] pos=2,2,2 dist=30.0',
         'Wren [Trader] #77/3 [Squin] pos=3,3,3 dist=40.0', 'Henko #88/1 [Slaves] pos=4,4,4 dist=50.0', 'Negg #-5/1 [Squin] pos=5,5,5 dist=60.0', 'Malzin #-1554488832/1 [Nameless] pos=0,0,1 dist=1.0']
HEARD = '9001|Wren [Trader]|Shay|heard_from|Cind [Hungry Bandit]|1|hearsay|5001'


def pick(key, default):
    seq = scen.get(key, default)
    i = st.get(key, 0)
    st[key] = i + 1
    json.dump(st, open(sp, 'w'))
    return seq[min(i, len(seq) - 1)]


def out(lines):
    if isinstance(lines, str):
        lines = [lines]
    if lines:
        print('\n'.join(str(x) for x in lines))
    sys.exit(0)


if kind == 'w':
    if 'u3:srvn' in body:
        out('100')
    if 'u3:stream' in body:
        out(pick('stream', [OK]))
    if 'u3:tlog' in body:
        out(pick('tlog', [[]]))
elif kind == 'h':
    if 'u3:chars' in body:
        out(' | '.join(scen.get('chars', CHARS)))
    if 'u3:state' in body:
        out(pick('state', ['{"unconscious": false, "ai": {}}']))
elif kind == 'sql':
    if 'u3:now' in body:
        out(str(scen.get('now', 5000)))
    if 'u3:chance' in body:
        out(scen.get('chance', 'unset'))
    if 'u3:counts' in body:
        out(scen.get('counts', ['Rethar Dax|40|9', 'Wren [Trader]|2|1', 'Henko|0|0']))
    if 'u3:crow' in body:
        out(pick('crow', [['5001|Shay|Malzin|saw|2|1000|1000']]))
    if 'u3:sev' in body:
        out(str(scen.get('sev', 2)))
    if 'u3:rank' in body:
        out(str(scen.get('rank', 3)))
    if 'u3:ids' in body:
        out('11,12,13')
    if 'u3:brow' in body:
        out(pick('brow', [[], [HEARD]]))
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'unblockfake_a.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
