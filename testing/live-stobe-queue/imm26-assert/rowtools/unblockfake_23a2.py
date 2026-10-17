#!/usr/bin/env python3
"""unblockfake_23a2.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_23a2_selftest.sh (tripdefs_23a2.sh, imm26-fix23arecipe). Answers the a2:-tagged calls and delegates the
rest to unblockfake_sfk.py (-> 23-a chain 'f' fakes). Scenario keys (env FAKE_SCEN; counters in FAKE_STATE + '.a2'):
  start 'quiet'|'hub'            where Shay/Cind are before the recipe (quiet = the lane-setup spot y=1533, hub = -53200 960 4860)
  tp_ignored (bool)              the hub teleport does not move anyone (op35: lane-setup --teleport did not move Cind)
  wcall_pos {"<n>": "x,y,z"}     override the n-th a2:where answer (1-based)
  stage_air (bool)               after the stage teleport (`... dist <back>`) `where` answers y=1570.8 (op35 a2)
  accepted_after_say N           the newest travel_agreement is ACCEPTED once N stobe_say calls were made (before: PROPOSED); 0/absent = never
  destpoints ["x y z", ...]    the newest agreement's destination_point after the n-th stobe_say (last repeats); needs the local-ask mode (A2_LOCAL=1)
  native 'ok'|'cleared'|'none'|'obs0'|'drops_late'|'lead'   what the stobe.log NATIVE_TRAVEL probes see (lead: START only after a say containing 'Lead the way')
Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.a2'
st = json.load(open(sp)) if os.path.isfile(sp) else {'at': scen.get('start', 'quiet'), 'says': 0, 'where': 0, 'nlog': 0, 'lead': 0}
here = os.path.dirname(os.path.abspath(__file__))
START = '[10:00:00.000] [Stobe] NATIVE_TRAVEL_START: task=order:1:2 actor=1 kind=route requested=-62461.0,328.8,16346.8'
OBS = '[10:00:02.000] [Stobe] NATIVE_TRAVEL_OBS: task=order:1:2 kind=route pos=-53200.0,960.0,4860.0 goal=-62461.0,328.8,16346.8 planar=17000.0 moving=1 orders=%d'
ENDED = '[10:00:00.400] [Stobe] NATIVE_TRAVEL_ORDER_ENDED: task=order:1:2 planar=14710.9 dy=0.0 arrived8=0 near16=0 leader_ok=1 viable=1'


def save():
    json.dump(st, open(sp, 'w'))


def out(lines):
    save()
    print('\n'.join(lines))
    sys.exit(0)


if kind == 'h':
    if 'stobe_say' in body:
        st['says'] += 1
        if 'Lead the way' in body:
            st['lead'] = 1
    if 'stobe-auto teleport' in body:
        if '-53200 960 4860' in body and not scen.get('tp_ignored'):
            st['at'] = 'hub'
        if re.search(r'teleport [^\n]* dist \d+', body):
            st['at'] = 'stage'
        save()
    if 'a2:where' in body:
        st['where'] += 1
        ov = scen.get('wcall_pos', {}).get(str(st['where']))
        if ov:
            pos = ov
        elif st['at'] == 'hub':
            pos = '-53200.0,960.0,4860.0'
        elif st['at'] == 'stage':
            pos = '-62061.0,%s,16346.8' % ('1570.8' if scen.get('stage_air') else '329.2')
        else:
            pos = '-50970.0,1533.0,2965.0'
        out(['Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=%s dist=9.0' % pos])
    if 'a2:nlog' in body:
        mode = scen.get('native', 'ok'); i = st['nlog']; st['nlog'] += 1
        if mode == 'lead' and not st['lead']:
            mode = 'none'
        elif mode == 'lead':
            mode = 'ok'
        if mode == 'drops_late' and i == 0:
            mode = 'ok'
        elif mode == 'drops_late':
            mode = 'cleared'
        if mode == 'ok':
            out(['START: 1', 'ENDED: ', 'OBS: ' + OBS % 1])
        if mode == 'cleared':
            out(['START: 1', 'ENDED: ' + ENDED, 'OBS: '])
        if mode == 'obs0':
            out(['START: 1', 'ENDED: ', 'OBS: ' + OBS % 0])
        out(['START: 0', 'ENDED: ', 'OBS: '])
elif kind == 'sql':
    if body.startswith("select data from eventlog where type='travel_agreement' order by rowid desc limit 1") and scen.get('destpoints'):   # fix23agate2: the newest agreement's destination_point follows the ask just made
        dps = scen['destpoints']; x, y, z = dps[min(max(st['says'], 1), len(dps)) - 1].split()
        out(['{"agreement_id":"trip-aaa","destination_point":{"x":%s,"y":%s,"z":%s},"status":"PROPOSED"}' % (x, y, z)])
    if 'a2:agr' in body:
        n = scen.get('accepted_after_say', 0)
        out(['ACCEPTED|requested' if n and st['says'] >= n else 'PROPOSED|proposed'])
save()
r = subprocess.run([sys.executable, os.path.join(here, 'unblockfake_sfk.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
