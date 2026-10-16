#!/usr/bin/env python3
"""unblockscen_sfz.py <name>   scenario JSON for unblock_sfz_selftest.sh (extends unblockscen_d2.py d2-hub).
Names: sz-pass (2 chance-gated ticks, 2 spoken without gossip, then gossip on tick 5) sz-never (every tick reaches the speech, never gossip) sz-gateonly (every tick dies at the gate, chance 100)
       sz-seamlow (gate rolls chance 85: the seam did not apply) sz-http (every request fails) sz-npcold (a previous per-NPC override value 70 exists) sz-nohearsay (lane lacks the hearsay fix)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
HEARD = '9001|Wren [Trader]|Shay|heard_from|Cind [Hungry Bandit]|1|hearsay|5001'
GOSSIP = '[2026-10-16 09:00:00] [INFO] NPC gossip passed on | {"speaker":"Cind","shared":[{"listener":"Wren","about":"Shay","source":"Cind","delta":-2}]}'


def gate(ch):
    return '[2026-10-16 09:00:00] [INFO] Bored event skipped: chance gate | {"speaker":"Cind","roll":91,"chance":%d,"initiative_score":65}' % ch


base = 'd2-nohearsay' if n == 'sz-nohearsay' else 'd2-hub'
S = json.loads(subprocess.run([sys.executable, os.path.join(here, 'unblockscen_d2.py'), base], capture_output=True, text=True, check=True).stdout)
if n == 'sz-pass':
    S['brow'] = [[], [], [], [], [HEARD]]
    S['tlog'] = [[gate(100)], [gate(100)], [], [], [GOSSIP]]
elif n == 'sz-never':
    S['brow'] = [[]]
    S['tlog'] = [[]]
elif n == 'sz-gateonly':
    S['brow'] = [[]]
    S['tlog'] = [[gate(100)]]
elif n == 'sz-seamlow':
    S['brow'] = [[]]
    S['tlog'] = [[gate(85)]]
elif n == 'sz-http':
    S['stream'] = [['', 'HTTP=000']]
elif n == 'sz-npcold':
    S['npcold'] = '70'
    S['brow'] = [[HEARD]]
    S['tlog'] = [[GOSSIP]]
elif n == 'sz-nohearsay':
    pass
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
