#!/usr/bin/env python3
"""hunt26ascen.py <name>   scenario JSON for hunt26afake.py / reload-sf26ad-selftest.sh (hunt26a-run.sh).
Names: pass (no Katana at start; Raw Meat x2 after; accepted, accepted, completed) | pass-katana (Katana already carried) | failed (accepted then failed/timeout, the op9p symptom)
       noinv (completed but nothing gained) | proposed (the Yes never lands) | nopart (completed, delivered, but participationOutcome empty)"""
import json
import sys

n = sys.argv[1]
KAT = '{"items":[{"name":"Katana"}]}'
MEAT = '{"items":[{"name":"Katana"},{"name":"Raw Meat","count":2}]}'
ACC = 'activity-new1|2|accepted|||1866-gamedata.base|1'
DONE = 'activity-new1|5|completed||delivered|1866-gamedata.base|1'
FAIL = 'activity-new1|4|failed|timeout|not_completed|1866-gamedata.base|1'
S = {'inv': ['{"items":[]}', KAT, MEAT], 'rec': [ACC, ACC, DONE], 'out': ['t'], 'goats': ['#11/1 Goat [Herbivore] dist=5\n#12/1 Goat [Herbivore] dist=6']}
if n == 'pass-katana':
    S['inv'] = [KAT, KAT, MEAT]
elif n == 'failed':
    S['rec'] = [ACC, FAIL]
elif n == 'noinv':
    S['inv'] = [KAT]
elif n == 'proposed':
    S['rec'] = ['activity-new1|1|proposed|||1866-gamedata.base|1']
elif n == 'nopart':
    S['rec'] = [ACC, 'activity-new1|5|completed|||1866-gamedata.base|1']
print(json.dumps(S))
