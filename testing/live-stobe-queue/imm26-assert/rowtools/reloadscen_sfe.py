#!/usr/bin/env python3
"""reloadscen_sfe.py <name>   scenario JSON for reload-sfe-selftest.sh (synthetic rows modelled on real 19-a / wpR1 evidence; hashes computed with seed24c.plan_hash).
Names: a24c-pass a24c-goalgone a24c-lost a24c-hashbad a24c-noown a24c-insertfail  f26-pass f26-retry f26-nooffer f26-scenebad f26-nocamp f26-reject f26-targets-changed f26-lost f26-zone-same f26-zone-dropped f26-scenelost"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from seed24c import plan_hash  # noqa: E402


def jd(o):
    return json.dumps(o, separators=(',', ':'))


AID = 'trip-resume-aaaa'
PT = {'x': -62380.0, 'y': 330.0, 'z': 16250.0, 'label': 'Stumble Inn', 'source': 'visited_location'}
H_GUIDE = plan_hash('1', '2', 'guide', 'npc', PT)
H_SAME = plan_hash('1', '2', 'same_route', 'npc', PT)
START = 'OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned request_id=%s'
RG = {'region': 'Vain', 'goal_type': 'regional_outing', 'seeded': True, 'seeded_by': 'imm26-sfE2', 'endpoint_source': 'seeded_resume_fixture'}


def trow(status, phase, rid, gen, world, kind='guide', rg=None, h=None, **ex):
    d = {'status': status, 'kind': kind, 'destination': 'Stumble Inn', 'destination_point': PT, 'agreement_id': AID, 'plan_hash': h or (H_GUIDE if kind == 'guide' else H_SAME),
         'expires_gamets': 99999, 'accepted_by': ['Cind', 'Shay'], 'leader': 'npc', 'accepted_gamets': 500,
         'execution': dict({'phase': phase, 'request_id': rid, 'world_id': world, 'session_generation': gen}, **ex)}
    if rg:
        d['regional_goal'] = rg
    return 'travel-v1:1:2:' + jd(d)


def dump(*rows):
    return [f'{rid}|travel_agreement|{data}' for rid, data in rows]


def state(first='MOVE_CUS_ORDERED', dest=(PT['x'], PT['y'], PT['z']), goal='GOTO'):
    return jd({'name': 'Cind', 'faction': 'Traders Guild', 'ai': {'first_order': first, 'current_goal': goal, 'destination': list(dest)}})


def step(reply, **k):
    return dict({'reply': reply}, **k)


def act(i, world, status, kind='Hunt', res='42243-rebirth.mod', qty='1', rstate='', rof='', rcont='', rcount='', targets='', camp=''):
    return '|'.join([i, world, '111', '222', '1', status, kind, res, qty, rstate, rof, rcont, rcount, targets, camp])


n = sys.argv[1]
S = {}
if n.startswith('a24c-'):
    hb = 'ab' * 32 if n == 'a24c-hashbad' else None
    trip_req = trow('ACCEPTED', 'requested', 'req-old', 1, 'world-old', h=hb)
    trip_run = trow('ACCEPTED', 'running', 'req-old', 1, 'world-old', h=hb)
    seeded = trow('ACCEPTED', 'running', 'req-old', 1, 'world-old', kind='same_route', rg=RG)
    prg = None if n == 'a24c-goalgone' else RG
    if n == 'a24c-lost':
        post = [(111, trow('FAILED', 'failed', 'req-old', 1, 'world-old', kind='same_route', rg=RG, reason='destination_not_resumable'))]
    else:
        post = [(111, trow('ACCEPTED', 'interrupted_by_load', None, None, None, kind='same_route', rg=prg, interrupted_gamets=500)),
                (112, trow('ACCEPTED', 'requested', 'req-new', 2, 'world-new', kind='same_route', rg=prg)),
                (113, trow('ACCEPTED', 'running', 'req-new', 2, 'world-new', kind='same_route', rg=prg))]
    trip_rows = [(90, trip_req), (95, trip_run)]
    seed_rows = trip_rows + [(96, seeded)]
    if n == 'a24c-noown':   # the native trip never started: no OWNED_TRAVEL line in s2 or s3
        S = {'steps': [step('Stumble Inn, aye.', full=[['travel_agreement', trow('PROPOSED', 'proposed', None, None, None)]]),
                       step('Lead on.', full=[['travel_agreement', trip_req]]), step('Not that way.')],
             'agr_dumps': [dump(*trip_rows), dump(*trip_rows)]}
    else:
        S = {'steps': [step('Stumble Inn, aye.', full=[['travel_agreement', trow('PROPOSED', 'proposed', None, None, None)]]),
                       step('Lead on.', full=[['travel_agreement', trip_req]], log=[START % 'req-old']),
                       step('We were heading there.', log=[START % 'req-new'] if n != 'a24c-lost' else []),
                       step('Right behind you.')],
             'agr_dumps': [dump(*trip_rows), dump(*seed_rows), dump(*seed_rows, *post)],
             'follow': [state(), state()] if n != 'a24c-lost' else [state('none'), state('none')],
             'insert_ok': n != 'a24c-insertfail'}
elif n.startswith('f26-'):
    W1, W2 = 'epoch-1', 'epoch-2'
    A1, A2 = 'activity-aaaa', 'activity-bbbb'
    # fix26fcamp: the zone id/digest are world+session scoped, so the continuation shows a NEW zone (f26-zone-same = server kept the old one, f26-zone-dropped = lost it)
    camp = '' if n == 'f26-nocamp' else '{"candidateId":"v1:' + 'a' * 48 + '","scopeDigest":"' + 'b' * 64 + '"}'
    camp2 = camp if n in ('f26-nocamp', 'f26-zone-same') else ('' if n == 'f26-zone-dropped' else '{"candidateId":"v1:' + 'c' * 48 + '","scopeDigest":"' + 'd' * 64 + '"}')
    tg = '[11,12,13]'
    p = act(A1, W1, 'proposed', 'ClearGroup', targets=tg, camp=camp)
    a = act(A1, W1, 'accepted', 'ClearGroup', targets=tg, camp=camp)
    old = act(A1, W1, 'superseded', 'ClearGroup', rstate='ended', rcont=A2, targets=tg, camp=camp)
    new = act(A2, W2, 'accepted', 'ClearGroup', rstate='resumed', rof=A1, rcount='1', targets='[11,12]' if n == 'f26-targets-changed' else tg, camp=camp2)
    outs = [[f'{A1}|1|false|{W1}'], [f'{A1}|1|false|{W1}', f'{A2}|1|false|{W2}']]
    if n == 'f26-lost':
        S = {'steps': [step('Shall we clear them?'), step('Good.'), step('What job?')], 'act': [[p], [a], [a]], 'out': [outs[0]], 'actlog': [[], []]}
    elif n == 'f26-retry':
        S = {'steps': [step('Which bandits?'), step('Shall we clear them out together?'), step('Good.'), step('Still on it.')], 'act': [[], [p], [a], [old, new]], 'out': outs,
             'actlog': [[], ['ACTIVITY resume start accepted']]}
    elif n == 'f26-nooffer':
        S = {'steps': [step('Which camp?')] * 4, 'act': [[]], 'out': outs, 'actlog': [[]]}
    elif n == 'f26-reject':
        S = {'steps': [step('Shall we clear them?'), step('Good.')], 'act': [[p], [act(A1, W1, 'failed', 'ClearGroup', targets=tg, camp=camp)]], 'out': outs,
             'actlog': [['ACTIVITY start rejected: requester_now_hostile']]}
    else:
        S = {'steps': [step('Shall we clear them out together?'), step('Good.'), step('Still on it.')], 'act': [[p], [a], [old, new]], 'out': outs,
             'actlog': [[], ['ACTIVITY resume start accepted']]}
    S['sees'] = n != 'f26-scenebad'
    if n == 'f26-scenelost':
        S['alive'] = 1
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
