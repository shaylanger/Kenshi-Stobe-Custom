#!/usr/bin/env python3
"""unblockfake_sffb.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sffb_selftest.sh (row 11-b recipe v3). Answers the sffb-tagged calls and delegates everything else to
unblockfake_sfk.py (-> unblockfake_a.py -> ...). Extra scenario keys (env FAKE_SCEN; counters in FAKE_STATE + '.sffb'):
  ko_fail (bool: `stobe-auto ko` answers an error)   track (list per `sffb:track` call, last repeats: a distance like '20' or 'ERROR' = target not found)
Tags: `# sffb:ko` `# sffb:track` `# sffb:recall`. Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sffb'
st = json.load(open(sp)) if os.path.isfile(sp) else {'track': 0}
here = os.path.dirname(os.path.abspath(__file__))

if kind == 'h':
    if 'sffb:ko' in body:
        print('ERROR: unknown command ko' if scen.get('ko_fail') else 'knocked out Hungry Bandit for 900.0 s')
        sys.exit(0)
    if 'sffb:track' in body:
        seq = scen.get('track', ['20'])
        i = st['track']; st['track'] += 1; json.dump(st, open(sp, 'w'))
        v = seq[min(i, len(seq) - 1)]
        print('ERROR: target not found' if v == 'ERROR' else 'Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=%s' % v)
        sys.exit(0)
    if 'sffb:recall' in body:
        print('teleported: Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=0,0,0 dist=3.0 moved=1 off_target=0.0 method=teleport')
        sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(here, 'unblockfake_sfk.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
