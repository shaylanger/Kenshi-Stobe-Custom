#!/usr/bin/env python3
"""reloadfake_b.py <kind h|w|sql> <body>   OFFLINE lane simulator for the set-B reload rows (reloadselftest_b.sh); delegates everything it does not know to
tripfake.py (-> fakelane.py). Statements of reloaddefs_b.sh carry a `rb:<tag>` marker so the answers are deterministic. Scenario keys (env FAKE_SCEN json):
  deals [lines per rb:deal call]  clocks [lines per rb:clock call]  nows [numbers per rb:now call]  effects [lines]  price  fired [ints per rb:fired call]
  probe [json per rb:probe call]  silent [ints per rb:silentpoll call]  turns [lines]  gamets.   Counters live in FAKE_STATE + '.rb'. Never touches a game or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.rb'
st = json.load(open(sp)) if os.path.isfile(sp) else {}


def nxt(key, default=None):
    seq = scen.get(key)
    if not seq:
        return default
    i = st.get('n_' + key, 0)
    st['n_' + key] = i + 1
    json.dump(st, open(sp, 'w'))
    return seq[min(i, len(seq) - 1)]


m = re.search(r'rb:(\w+)', body)
tag = m.group(1) if m else ''
if kind == 'sql' and tag:
    if tag == 'deal':
        print(nxt('deals', ''))
    elif tag == 'clock':
        print(nxt('clocks', ''))
    elif tag == 'now':
        print(nxt('nows', 1000))
    elif tag == 'effects':
        print('\n'.join(scen.get('effects', [])))
    elif tag == 'price':
        print(scen.get('price', 353))
    elif tag == 'gamets':
        print(scen.get('gamets', 5000))
    sys.exit(0)
if kind == 'w' and tag:
    if tag == 'fired':
        print(nxt('fired', 0))
    elif tag == 'probe':
        print(nxt('probe', '{}'))
    elif tag == 'pauselog':
        print('\n'.join(scen.get('pauselog', [])))
    sys.exit(0)
if kind == 'h' and tag:
    if tag == 'silentpoll':
        print(nxt('silent', 0))
    elif tag == 'turns':
        print('\n'.join(scen.get('turns', [])))
    elif tag == 'money':
        print('ok')
    sys.exit(0)
here = os.path.dirname(os.path.abspath(__file__))
r = subprocess.run([sys.executable, os.path.join(here, 'tripfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
