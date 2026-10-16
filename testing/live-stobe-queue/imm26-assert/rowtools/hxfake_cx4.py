#!/usr/bin/env python3
"""hxfake_cx4.py <kind h|w|sql> <body>   OFFLINE lane simulator for hx-selftest_cx4.sh: hxfake.py plus the cx4 commands.
  save check (hx4lib.sh)  -> `SAVE-OK`, or `SAVE-MISSING <dir>` when the scenario has save_missing, `SAVE-UNKNOWN ...` when env FAKE_SAVE_UNKNOWN is set
  stobe-auto stobe_state  -> {"unconscious":true,...} (scenario ko_fail: false)   ;   stobe-auto ko -> `knocked out ... for N s`"""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
if kind == 'h':
    if 'SAVE-OK' in body:
        if os.environ.get('FAKE_SAVE_UNKNOWN'):
            print('SAVE-UNKNOWN no save folder under /x')
        elif scen.get('save_missing'):
            m = re.search(r'save/([^"]+)"', body)
            print('SAVE-MISSING /fake/save/' + (m.group(1) if m else '?'))
        else:
            print('SAVE-OK')
        sys.exit(0)
    if 'stobe_state' in body and 'stobe_say' not in body:
        print('{"unconscious":%s,"first_order":"none","current_goal":"none","dead":false}' % ('false' if scen.get('ko_fail') else 'true'))
        sys.exit(0)
    if re.search(r'stobe-auto ko ', body):
        print('knocked out Hungry Bandit for 900.0 s')
        sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hxfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
sys.exit(r.returncode)
