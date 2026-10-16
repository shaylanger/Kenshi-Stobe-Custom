#!/usr/bin/env python3
"""hunt26afake.py <h|w|sql> <body>   OFFLINE lane simulator for reload-sf26ad-selftest.sh (hunt26a-run.sh). Scenario JSON (env FAKE_SCEN); every list = one answer per call, the last repeats:
  inv (stobe-auto inv answers)  rec (newest-new-Hunt-record rows: 'id|rev|status|reason|part|res|qty')  out (outbox acknowledged rows)  goats (chars answer lines)
Never touches a game, ssh or DB."""
import json
import os
import re
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.h26a'
st = json.load(open(sp)) if os.path.isfile(sp) else {'n': {}}


def pick(key):
    seq = scen.get(key, [''])
    i = st['n'].get(key, 0)
    st['n'][key] = i + 1
    return seq[min(i, len(seq) - 1)]


def out(s):
    json.dump(st, open(sp, 'w'))
    if s:
        print(s)
    sys.exit(0)


if kind == 'h':
    if 'stobe-auto chars' in body:
        out(pick('goats'))
    if 'stobe-auto inv' in body:
        out(pick('inv'))
    if 'for i in' in body and 'teleport Shay' in body:   # hunt26a-run.sh v2 follow call: one dist=N line per jump (scenario key seps, default 5 x dist=9.5)
        out(pick('seps') or 'dist=9.5\ndist=9.5\ndist=9.5\ndist=9.5\ndist=9.5')
    if re.search(r'stobe-auto where ', body):
        out('Malzin #2740478464/2 [Nameless] pos=-49422.0,1661.0,3643.0 dist=0.9')
    out('ok')
if kind == 'sql':
    if 'id not in' in body:
        out(pick('rec'))
    if 'stobe_activity_outbox' in body:
        out(pick('out'))
    if body.startswith('select id from stobe_activity_record'):
        out(scen.get('old', 'activity-old1'))
    out('')
out('')
