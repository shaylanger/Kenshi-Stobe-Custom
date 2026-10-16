#!/usr/bin/env python3
"""reloadfake.py <kind h|w|sql> <body>   OFFLINE lane simulator for the save+load resume rows (reload-selftest.sh); delegates everything it does not know to
tripfake.py -> fakelane.py. Extra scenario keys (env FAKE_SCEN json; counters in FAKE_STATE + '.rw'; every list = one answer per call, the last repeats):
  follow (stobe_state JSON per call)  follow_log (stobe.log FOLLOW lines per rw_log call)  act (rw_act_dump)  out (rw_out_dump)  actlog (rw_log ACTIVITY)  fu (social_followup dumps)  claim (situated_remark_claim)  alt (travel_alternatives)
  region (region_plan)  bored (BORED_EVENT_CHANCE value)  bg (contract-bodyguard status answers)  closes [bool per `speed 3` call: does the NPC close the
  distance after Shay was teleported away]  Distance model: `teleport Shay <x y z>` puts the NPC 80 u away, the next `speed 3` call closes it (or not).
Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.rw'
st = json.load(open(sp)) if os.path.isfile(sp) else {'n': {}, 'away': False, 'speed3': 0}


def save():
    json.dump(st, open(sp, 'w'))


def pick(key, default=None):
    seq = scen.get(key, default if default is not None else [[]])
    i = st['n'].get(key, 0)
    st['n'][key] = i + 1
    return seq[min(i, len(seq) - 1)]


def out(lines):
    save()
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


if kind == 'w' and 'rw:srvn' in body:
    out(['100'])
if kind == 'w' and 'rw:ticks' in body:
    out(scen.get('tick_log', ['x']) if ' -c ' not in body else [str(scen.get('ticks', 3))])
if kind == 'h':
    if re.search(r'teleport Shay -?\d', body):
        st['away'] = True
        out([])
    if 'stobe-auto speed 3' in body:
        closes = scen.get('closes', [True])
        c = closes[min(st['speed3'], len(closes) - 1)]
        st['speed3'] += 1
        if c:
            st['away'] = False
        out([])
    if 'stobe-auto where' in body and not scen.get('npc_missing'):
        out([f"Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist={80.0 if st['away'] else 8.0}"])
    if 'stobe_state' in body and scen.get('follow'):
        out([pick('follow')])
    if "grep -a -E 'FOLLOW'" in body:
        out(pick('follow_log'))
    if re.search(r'contract-bodyguard.*status', body):
        out(pick('bg', [['']]))
    if 'contract-bodyguard' in body:
        out(scen.get('bgset', ['ok']))
    if "grep -a -E 'ACTIVITY'" in body:
        out(pick('actlog'))
elif kind == 'sql':
    if body.startswith('delete from stobe_activity'):
        out(['DELETE 0'])
    if 'from stobe_activity_record' in body and body.startswith('select id||'):
        out(pick('act'))
    if 'from stobe_activity_outbox' in body and body.startswith('select agreement_id||'):
        out(pick('out'))
    if 'BORED_EVENT_CHANCE' in body:
        out([str(scen.get('bored', '100'))])
    for key, t in (('fu', 'social_followup'), ('claim', 'situated_remark_claim'), ('alt', 'travel_alternatives'), ('region', 'region_plan')):
        if f"type='{t}'" in body and body.startswith('select rowid||'):
            out(pick(key))
save()
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tripfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
