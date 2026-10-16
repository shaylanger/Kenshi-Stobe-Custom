#!/usr/bin/env python3
"""reloadscen_sf26bd.py <name>   scenario JSON for reload-sf26bd-selftest.sh = a reloadscen_sfi.py scenario + the sb_* keys of reloadfake_sf26bd.py.
Names: 26dx-pass 26d-pass (people ok) | 26dx-nopeople (Malzin missing from every dispatched people=) | 26dx-nodispatch | 26d-far (NPC 288.6 u away after the load, regroup names Malzin)
       26d-wrongtp (the regroup teleport names Cind) | cancel-pass (hunt26b-cancel: record cancelled) | cancel-fail (record failed) | cancel-nopeople"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
base = {'26dx-nopeople': '26dx-pass', '26dx-nodispatch': '26dx-pass', '26d-far': '26d-pass', '26d-wrongtp': '26d-pass',
        'cancel-pass': '26dx-pass', 'cancel-fail': '26dx-pass', 'cancel-nopeople': '26dx-pass'}.get(n, n)
S = json.loads(subprocess.run([sys.executable, os.path.join(here, 'reloadscen_sfi.py'), base], capture_output=True, text=True, check=True).stdout)
if n == '26dx-nopeople' or n == 'cancel-nopeople':
    S['sb_people'] = [['Shay|971557632']]
elif n == '26dx-nodispatch':
    S['sb_no_dispatch'] = True
elif n == '26d-far':
    S['sb_far_after_load'] = True
elif n == '26d-wrongtp':
    S['sb_far_after_load'] = True
    S['sb_wrong_tp'] = True
if n.startswith('cancel'):
    pre = '|'.join(['activity-1', 'w1', '111', '222', '2', 'accepted', 'Hunt', 'goat', '1', '', '', '', '', '', ''])
    post = '|'.join(['activity-1', 'w1', '111', '222', '3', 'cancelled' if n != 'cancel-fail' else 'failed', 'Hunt', 'goat', '1', '', '', '', '', '', ''])
    S['act'] = [[pre], [post]]
    S['actlog'] = [['ACTIVITY_END_DIAG where=chat_cancel toPhase=cancelled cleanupComplete=1']]
print(json.dumps(S))
