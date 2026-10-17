#!/usr/bin/env python3
"""unblockfake_sff.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sff_selftest.sh: answers the forced-line command (marker `sff:share`; scenario key `share` = text lines, default a
created-row answer) and delegates everything else to unblockfake_sfz.py. `unblockfake_sff.py --scen <name>` prints the scenario JSON (extends unblockscen_sfz.py sz-never).
Scenarios: sf-pass (forced line seeds the row) sf-norow (hook created nothing, Cind has no eligible row) sf-unnamed (eligible but the line names nobody) sf-real (REAL pair request fires on try 2)
           sf-realfail (2 real tries fail, forced line seeds) sf-nohearsay (lane lacks the hearsay fix) sf-php127 (php missing on the lane).
Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HEARD = '9001|Wren [Trader]|Shay|heard_from|Cind [Hungry Bandit]|1|hearsay|5001'
GOSSIP = '[2026-10-16 09:00:00] [INFO] NPC gossip passed on | {"speaker":"Cind","shared":[{"listener":"Wren","about":"Shay","source":"Cind","delta":-2}]}'
JOK = '{"speaker":"Cind [Hungry Bandit]","speaker_id":11,"listener":"Wren [Trader]","listener_id":12,"gamets":5000,"scope":"c/3","text":"I saw Shay attack Malzin","eligible":1,"eligible_named":["5001:Shay>Malzin"],"shared":[{"listener":"Wren [Trader]","about":"Shay","source":"Cind [Hungry Bandit]","delta":-2}]}'
JNO0 = '{"speaker":"Cind [Hungry Bandit]","speaker_id":11,"listener":"Wren [Trader]","listener_id":12,"gamets":5000,"scope":"c/3","text":"x","eligible":0,"eligible_named":[],"shared":[]}'
JNO1 = '{"speaker":"Cind [Hungry Bandit]","speaker_id":11,"listener":"Wren [Trader]","listener_id":12,"gamets":5000,"scope":"c/3","text":"x","eligible":1,"eligible_named":[],"shared":[]}'

if sys.argv[1] == '--scen':
    n = sys.argv[2]
    base = 'sz-nohearsay' if n == 'sf-nohearsay' else 'sz-never'
    S = json.loads(subprocess.run([sys.executable, os.path.join(HERE, 'unblockscen_sfz.py'), base], capture_output=True, text=True, check=True).stdout)
    if n == 'sf-pass':
        S['brow'] = [[HEARD]]; S['share'] = [JOK, 'SHARERC=0']
    elif n == 'sf-norow':
        S['brow'] = [[]]; S['share'] = [JNO0, 'SHARERC=1']
    elif n == 'sf-unnamed':
        S['brow'] = [[]]; S['share'] = [JNO1, 'SHARERC=1']
    elif n == 'sf-real':
        S['brow'] = [[], [HEARD]]; S['tlog'] = [[], [GOSSIP]]; S['share'] = [JOK, 'SHARERC=0']
    elif n == 'sf-realfail':
        S['brow'] = [[], [], [HEARD]]; S['tlog'] = [[]]; S['share'] = [JOK, 'SHARERC=0']
    elif n == 'sf-php127':
        S['brow'] = [[]]; S['share'] = ['bash: php: command not found', 'SHARERC=127']
    elif n == 'sf-nohearsay':
        pass
    else:
        raise SystemExit('unknown scenario ' + n)
    print(json.dumps(S))
    sys.exit(0)

kind, body = sys.argv[1], sys.argv[2]
if kind == 'w' and 'sff:share' in body:
    print('\n'.join(json.load(open(os.environ['FAKE_SCEN'])).get('share', [JOK, 'SHARERC=0'])))
    sys.exit(0)
r = subprocess.run([sys.executable, os.path.join(HERE, 'unblockfake_sfz.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
