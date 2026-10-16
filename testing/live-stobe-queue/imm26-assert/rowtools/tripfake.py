#!/usr/bin/env python3
"""tripfake.py <kind h|w|sql> <body>   OFFLINE lane simulator for the trip-family rows (trip-selftest.sh); delegates everything it does not
know to fakelane.py. Extra scenario keys (env FAKE_SCEN json; counters in FAKE_STATE + '.trip'):
  state {name-substring: [stobe_state JSON per call]}   agr [[agreement dump lines per tr_agr call]]   n2 [[N2 log lines per tr_n2_log call]]
  se [[social_effect text rows per tr_se call]]   se_count (count(*) answer)   malzin (False -> `where Malzin` fails)
Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.trip'
st = json.load(open(sp)) if os.path.isfile(sp) else {'state': {}, 'agr': 0, 'n2': 0, 'se': 0}


def save():
    json.dump(st, open(sp, 'w'))


def out(lines):
    save()
    print('\n'.join(lines))
    sys.exit(0)


if kind == 'h':
    if 'stobe-auto where' in body and "where 'Malzin" in body:
        out(["Malzin [Drifters] #77/1 [Nameless] pos=-50960.0,1533.0,2960.0 dist=12.0"] if scen.get('malzin', True) else ['ERROR not found'])
    if 'stobe_state' in body and scen.get('state'):
        for name, seq in scen['state'].items():
            if f"stobe_state '{name}" in body:
                st['state'][name] = st['state'].get(name, 0) + 1
                out([seq[min(st['state'][name] - 1, len(seq) - 1)]])
        out(['{}'])
    if 'N2_ABANDON|N2_PROXIMITY' in body and 'cut -c1-300 | tail -40' in body:
        st['n2'] += 1
        seq = scen.get('n2', [[]])
        out(seq[min(st['n2'] - 1, len(seq) - 1)])
elif kind == 'sql':
    if body.startswith('select rowid||'):
        st['agr'] += 1
        seq = scen.get('agr', [[]])
        out(seq[min(st['agr'] - 1, len(seq) - 1)])
    if 'select se::text' in body:
        st['se'] += 1
        seq = scen.get('se', [[]])
        out(seq[min(st['se'] - 1, len(seq) - 1)])
    if 'select count(*) from social_effect se' in body:
        out([str(scen.get('se_count', 0))])
    if body.startswith('delete from eventlog'):
        out(['DELETE 0'])
save()
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fakelane.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
