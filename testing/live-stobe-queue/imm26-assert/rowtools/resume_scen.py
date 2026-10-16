#!/usr/bin/env python3
"""resume_scen.py <name>   prints the fakelane.py scenario JSON for the trip-resume rows (19-a, 19-a-nc2, 19-d) used by selftest.sh.
Synthetic rows modelled on the design (C:/KenshiTestRuns/agents/out/imm26-trip-resume-design/latest.md): the SAME agreement_id goes
ACCEPTED/running -> interrupted_by_load -> requested (new request_id/world/generation) -> running after a save + load.
Names: 19a-pass 19a-failed 19a-nostart 19a-dup-start 19a-nc-bad 19a-wrong-order 19a-accept-s3 | nc2-pass nc2-resumed | 19d-pass 19d-notdone"""
import json
import sys

AID = 'trip-resume-aaaa'
HASH = 'ab' * 32
PT = {'x': -62380.0, 'y': 330.0, 'z': 16250.0, 'label': 'Squin'}
START = 'OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned request_id=%s'


def row(status, phase, rid, gen, world, aid=AID, **ex):
    d = {'status': status, 'kind': 'guide', 'destination': 'Squin', 'destination_point': PT, 'agreement_id': aid, 'plan_hash': HASH,
         'expires_gamets': 99999, 'accepted_by': ['Cind', 'Shay'], 'leader': 'npc',
         'execution': dict({'phase': phase, 'request_id': rid, 'world_id': world, 'session_generation': gen}, **ex)}
    return 'travel-v1:1:2:' + json.dumps(d, separators=(',', ':'))


def dump(*rows):
    return [f'{rid}|travel_agreement|{data}' for rid, data in rows]


def state(first='MOVE_CUS_ORDERED', dest=(PT['x'], PT['y'], PT['z'])):
    return json.dumps({'name': 'Cind', 'faction': 'Traders Guild', 'ai': {'first_order': first, 'current_goal': 'GOTO', 'destination': list(dest)}})


PRE = [(90, row('ACCEPTED', 'requested', 'req-old', 1, 'world-old')), (95, row('ACCEPTED', 'running', 'req-old', 1, 'world-old'))]
INT = (111, row('ACCEPTED', 'interrupted_by_load', None, None, None, interrupted_gamets=500))
REQ = (112, row('ACCEPTED', 'requested', 'req-new', 2, 'world-new'))
RUN = (113, row('ACCEPTED', 'running', 'req-new', 2, 'world-new'))
S1 = {'reply': 'Squin, maybe.', 'full': [['travel_agreement', row('PROPOSED', 'proposed', None, None, None)]]}
S2 = {'reply': 'Lead on.', 'full': [['travel_agreement', row('ACCEPTED', 'requested', 'req-old', 1, 'world-old')]], 'log': [START % 'req-old']}
S4 = {'reply': 'We were heading to Squin.', 'log': [START % 'req-new']}
S5 = {'reply': 'Right behind you.'}
S6 = {'reply': 'I am not sure what you mean.'}
n = sys.argv[1]
base = {'follow': [state(), state(), state(first='none')]}
if n == '19a-pass':
    S = dict(base, steps=[S1, S2, S4, S5, S6], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n == '19a-accept-s3':   # the ACCEPTED row and the native start land in s3 ("Lead the way."), not s2: still PASS
    S = dict(base, steps=[S1, {'reply': 'Hm, maybe.'}, S2, S4, S5, S6], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n == '19a-failed':      # today's behaviour: the agreement goes FAILED on the load and a NEW proposal appears
    failed = (111, row('FAILED', 'failed', 'req-old', 1, 'world-old'))
    newp = (112, row('PROPOSED', 'proposed', None, None, None, aid='trip-other-bbbb'))
    S = dict(base, steps=[S1, S2, dict(S4, log=[]), S5, S6], agr_dumps=[dump(*PRE), dump(*PRE, failed, newp)], follow=[state('none'), state('none'), state('none')])
elif n == '19a-nostart':     # the native trip never started before the save: nothing to resume
    S = dict(base, steps=[S1, dict(S2, log=[]), {'reply': 'Fine.'}, S4, S5, S6], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n == '19a-dup-start':   # two post-load starts
    S = dict(base, steps=[S1, S2, S4, dict(S5, log=[START % 'req-new2']), S6], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n == '19a-nc-bad':      # older save: the NPC still starts a trip
    S = dict(base, steps=[S1, S2, S4, S5, dict(S6, log=[START % 'req-x'])], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n == '19a-wrong-order':  # native order is not the stored destination
    S = dict(base, steps=[S1, S2, S4, S5, S6], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)], follow=[state(), state(dest=(1, 2, 3)), state(first='none')])
elif n == 'nc2-pass':        # NPC 120 u away: no transition, no start
    S = dict(base, steps=[S1, S2, {'reply': 'Too far to talk about it.'}], agr_dumps=[dump(*PRE), dump(*PRE)])
elif n == 'nc2-resumed':
    S = dict(base, steps=[S1, S2, S4], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)])
elif n in ('19d-pass', '19d-notdone'):
    done = '' if n == '19d-notdone' else '7009|COMPLETED|completed||true|%s|Squin' % AID
    S = dict(base, steps=[S1, S2, S4, {'reply': 'We made it.'}], agr_dumps=[dump(*PRE), dump(*PRE, INT, REQ, RUN)],
             agr=[[x for x in (done, '7001|ACCEPTED|running||false|%s|Squin' % AID) if x]], follow=[state(), state(first='none')])
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
