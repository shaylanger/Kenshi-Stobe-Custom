#!/usr/bin/env python3
"""unblockfake_b.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_b_selftest.sh. Answers the u-rowsB-specific calls (FAILED-count query, rig_stop/rig_launch,
the DLL gate, the ub:bgstatus forms), sends rb:-tagged calls to reloadfake_b.py and everything else to reloadfake.py (-> tripfake.py -> fakelane.py).
Extra scenario keys (env FAKE_SCEN): failed_count (int)  launch_fail (bool)  gate (line)  bgforms ([[lines] per ub:bgstatus call, last repeats]). Counter file FAKE_STATE+'.ub'."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.ub'
st = json.load(open(sp)) if os.path.isfile(sp) else {'bg': 0}
here = os.path.dirname(os.path.abspath(__file__))
if kind == 'sql' and 'count(*)' in body and '"status":"FAILED"' in body:
    print(scen.get('failed_count', 0)); sys.exit(0)
if kind == 'h':
    if 'rig_stop' in body:
        print('restart: stop\nrestart: stopped rc=0'); sys.exit(0)
    if 'rig_launch' in body:
        print('restart: launch x'); 
        if not scen.get('launch_fail'):
            print('restart: launched')
        sys.exit(0)
    if 'ub:bgstatus' in body:
        seq = scen.get('bgforms', [['ERROR: no character named: status']])
        i = st['bg']; st['bg'] += 1; json.dump(st, open(sp, 'w'))
        print('\n'.join(seq[min(i, len(seq) - 1)])); sys.exit(0)
    if 'contract-bodyguard' in body and '| head -2' in body:
        print(scen.get('gate', 'Cind [Hungry Bandit] has_contract=0')); sys.exit(0)
mod = 'reloadfake_b.py' if re.search(r'rb:\w+', body) else 'reloadfake.py'
r = subprocess.run([sys.executable, os.path.join(here, mod), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
