#!/usr/bin/env python3
"""unblockscen_d.py <name>   prints the unblockfake_d.py scenario JSON for unblock_d_selftest.sh (row 03-b).
Names: 03b-pass 03b-retry 03b-noprompt 03b-director 03b-never 03b-http 03b-no-b 03b-no-crow 03b-demote 03b-busy-only"""
import json
import sys

n = sys.argv[1]
OK = ['{"status":"ok"}', 'HTTP=200']
BAD = ['', 'HTTP=000']
HEARD = '9001|Wren [Trader]|Shay|heard_from|Cind [Hungry Bandit]|1|hearsay|5001'
GOSSIP = '[2026-10-16 09:00:00] [INFO] NPC gossip passed on | {"speaker":"Cind","shared":[{"listener":"Wren","about":"Shay","source":"Cind","delta":-2}]}'
DIRECTOR = '[2026-10-16 09:00:00] [INFO] NPC gossip passed on | {"speaker":"Cind","shared":[{"listener":"Wren","about":"Shay"}],"via":"director"}'
PROMPT = ('<memory>\n- [hearsay from Cind [Hungry Bandit], unverified, a moment ago] heard Shay in a fight; did not see it\n</memory>\n'
          '{"game_ts":5000}')
S = {'steps': [{'reply': 'I heard something.', 'prompt': PROMPT}], 'brow': [[], [HEARD]], 'tlog': [[], [GOSSIP]], 'stream': [OK]}
if n == '03b-pass':
    S['brow'] = [[HEARD]]
    S['tlog'] = [[GOSSIP]]
elif n == '03b-retry':
    pass
elif n == '03b-noprompt':
    S['brow'] = [[HEARD]]
    S['tlog'] = [[GOSSIP]]
    S['steps'] = [{'reply': 'Hm.', 'prompt': '<memory>\n- [Shay attacked Sek] seen\n</memory>'}]
elif n == '03b-director':
    S['brow'] = [[HEARD]]
    S['tlog'] = [[DIRECTOR]]
elif n == '03b-never':
    S['brow'] = [[]]
    S['tlog'] = [[]]
elif n == '03b-http':
    S['stream'] = [BAD]
elif n == '03b-no-b':
    S['chars'] = ['Shay #1/1 [Nameless] pos=0,0,0 dist=0.0', 'Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1 dist=9.0', 'Henko #88/1 [Slaves] pos=4,4,4 dist=50.0']
elif n == '03b-no-crow':
    S['crow'] = [[]]
elif n == '03b-demote':
    S['rank'] = 12
    S['brow'] = [[HEARD]]
    S['tlog'] = [[GOSSIP]]
elif n == '03b-busy-only':
    S['counts'] = ['Rethar Dax|40|9', 'Wren [Trader]|30|1']
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
