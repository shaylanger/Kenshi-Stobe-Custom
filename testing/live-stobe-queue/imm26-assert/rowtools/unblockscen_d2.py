#!/usr/bin/env python3
"""unblockscen_d2.py <name>   scenario JSON for unblock_d2_selftest.sh (extends unblockscen_d.py 03b-pass).
Names: d2-hub (every holder busy: the fewest-rows candidate must be picked) d2-nohearsay (lane lacks stobeKnowledgeHearsayFor) d2-nob (only slaves / negative serials near Shay)
       d2-noprompt (chain ran, prompt has no hearsay line)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
S = json.loads(subprocess.run([sys.executable, os.path.join(here, 'unblockscen_d.py'), '03b-pass'], capture_output=True, text=True, check=True).stdout)
if n == 'd2-hub':
    S['counts'] = ['Rethar Dax|75|20', 'Wren [Trader]|30|1']
elif n == 'd2-nohearsay':
    S['hearsay'] = 0
elif n == 'd2-nob':
    S['chars'] = ['Shay #1/1 [Nameless] pos=0,0,0 dist=0.0', 'Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=9.0', 'Henko #88/1 [Slaves] pos=4,4,4 dist=50.0',
                  'Negg #-5/1 [Squin] pos=5,5,5 dist=60.0']
elif n == 'd2-noprompt':
    S['steps'] = [{'reply': 'Hm.', 'prompt': '<memory>\n- [Shay attacked Sek] seen\n</memory>'}]
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
