#!/usr/bin/env python3
"""unblockscen_sffb.py <name>   scenario JSON for unblockfake_sffb.py (unblock_sffb_selftest.sh). Base = unblockscen_sfk.py sfk11-pass (fu sequence) + the cstate/track keys below.
cstate = one stobe_state answer per call (name read, then serial retry when the first is an ERROR); order of reads: combat_pre, combat, calm polls..., calm2.
Names: ko-pass ko-still-combat-escalate-pass name-lost-serial-ok strayed-recall gone-both ko-fail far-pass"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]
S = json.loads(subprocess.run([sys.executable, os.path.join(HERE, 'unblockscen_sfk.py'), 'sfk11-pass'], capture_output=True, text=True, check=True).stdout)
T, F = '{"in_combat": true}', '{"in_combat": false}'
ERR = 'ERROR: target not found'
if n == 'ko-pass':
    S['cstate'] = [T, T, F, F]
elif n == 'ko-still-combat-escalate-pass':
    S['cstate'] = [T, T, T, F, F]
elif n == 'name-lost-serial-ok':
    S['cstate'] = [ERR, T, T, F]
elif n == 'strayed-recall':
    S['cstate'] = [T, T, T, F, F]
    S['track'] = ['300', '20']
elif n == 'gone-both':
    S['cstate'] = [ERR]
    S['track'] = ['ERROR']
elif n == 'ko-fail':
    S['cstate'] = [T, T, F, F]
    S['ko_fail'] = True
elif n == 'far-pass':
    S['cstate'] = [T, T, F, F]
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
