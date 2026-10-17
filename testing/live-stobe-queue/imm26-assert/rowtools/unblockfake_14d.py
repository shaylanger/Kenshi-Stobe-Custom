#!/usr/bin/env python3
"""unblockfake_14d.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_14d_selftest.sh (row 14-d). Answers the `# d14:<tag>` calls of unblockdefs_14d.sh and the activity SQL;
everything else (where / stobe_say / prompt tail / events ...) goes to fakelane.py (scenario key `steps` = one per stobe_say: p1..pN probes, then the ask, then the accept).
Scenario keys (env FAKE_SCEN; counters in FAKE_STATE + '.d14'; a list = one answer per call, the last repeats):
  spawn (answer text)  senses (line)  members ([[lines] per d14:members call])  atkpre atkpost actlines (lines)  alive (chars_after lines)  recs ([[lines] per d14_rec call: ask, polls ...])
  outbox (lines)  where_nameless (bool: the NPC is already Nameless)
Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.d14'
st = json.load(open(sp)) if os.path.isfile(sp) else {}
here = os.path.dirname(os.path.abspath(__file__))


def pick(key, default):
    seq = scen.get(key, default)
    i = st.get(key, 0)
    st[key] = i + 1
    json.dump(st, open(sp, 'w'))
    return seq[min(i, len(seq) - 1)]


def out(lines):
    if isinstance(lines, str):
        lines = [lines]
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


m = re.search(r'# d14:(\w+)', body)
tag = m.group(1) if m else ''
if kind == 'h' and tag:
    if tag == 'where':
        out('Cind [Hungry Bandit] #2529907200/2 [%s] pos=-47333.0,730.0,-55594.0 dist=6.0' % ('Nameless' if scen.get('where_nameless', True) else 'Traders Guild'))
    if tag == 'spawn':
        out(scen['spawn'])
    if tag == 'senses':
        out(scen.get('senses', 'senses x: Cind -> Wulf sees=1 hears=1 aware=1'))
    if tag == 'members':
        out(pick('members', [[]]))
    if tag == 'atkpre':
        out(scen.get('atkpre', []))
    if tag == 'atkpost':
        out(scen.get('atkpost', []))
    if tag == 'actlines':
        out(scen.get('actlines', []))
    if tag == 'alive':
        out(scen.get('alive', []))
    out('ok')   # faction / prep / sentinel / relsent / relhost / ring / far / face
if kind == 'sql':
    if 'from stobe_activity_record where actor' in body and 'not in' in body:
        out(pick('recs', [[]]))
    if body.startswith('select id from stobe_activity_record'):
        out(scen.get('oldids', []))
    if "record->>'status' in ('proposed','accepted')" in body:
        out(scen.get('stale', []))
    if 'from stobe_activity_outbox' in body:
        out(scen.get('outbox', []))
r = subprocess.run([sys.executable, os.path.join(here, 'fakelane.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
