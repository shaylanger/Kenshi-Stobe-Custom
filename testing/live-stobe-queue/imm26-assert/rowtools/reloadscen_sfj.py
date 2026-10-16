#!/usr/bin/env python3
"""reloadscen_sfj.py <name>   prints the reloadfake_sfj.py scenario JSON for reload-sfj-selftest.sh (rows 23-e and 20-d, recipes of imm26-sfJ).
Names: sj23e-pass sj23e-lost sj23e-edge-in sj23e-edge-out sj23e-ctrl-approaches sj23e-ctrl-short sj23e-pre-far sj23e-nofollow
       sj20d-pass sj20d-second sj20d-third sj20d-never sj20d-lost sj20d-nopending-after-load"""
import json
import sys

n = sys.argv[1]
AID = 'trip-resume-aaaa'
HASH = 'ab' * 32
PT = {'x': -62380.0, 'y': 330.0, 'z': 16250.0, 'label': 'Squin'}
START = 'OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned request_id=%s'


def jd(o):
    return json.dumps(o, separators=(',', ':'))


def step(reply, **k):
    return dict({'reply': reply}, **k)


def row(status, phase, rid, gen, world, aid=AID, dest='Squin'):
    d = {'status': status, 'kind': 'guide', 'destination': dest, 'destination_point': PT, 'agreement_id': aid, 'plan_hash': HASH,
         'expires_gamets': 99999, 'accepted_by': ['Cind', 'Shay'], 'leader': 'npc',
         'execution': {'phase': phase, 'request_id': rid, 'world_id': world, 'session_generation': gen}}
    return 'travel-v1:1:2:' + jd(d)


def dump(*rows):
    return [f'{rid}|travel_agreement|{data}' for rid, data in rows]


S = {}
if n.startswith('sj23e'):
    tick = 'FOLLOW_TICK: follower=Cind target=Shay'
    ok_pre = ['HOOK_MSG_PROC: FOLLOW target resolved Cind', tick]
    chase = [[120.0, 121.0], [120.0, 44.0], [118.0, 47.0]]
    post = [tick]
    pre = ok_pre
    if n == 'sj23e-lost':
        chase[2] = [120.0, 120.0]; post = []
    elif n == 'sj23e-edge-in':
        chase[1] = [120.0, 69.9]
    elif n == 'sj23e-edge-out':
        chase[1] = [120.0, 70.1]
    elif n == 'sj23e-ctrl-approaches':
        chase[0] = [120.0, 40.0]
    elif n == 'sj23e-ctrl-short':
        chase[0] = [60.0, 60.0]
    elif n == 'sj23e-pre-far':
        chase[1] = [120.0, 100.0]
    elif n == 'sj23e-nofollow':
        pre = []
    S = {'steps': [step('Alright, I will follow you.')], 'follow_log': [pre, [], post], 'chase_d': chase}
elif n.startswith('sj20d'):
    old = row('ACCEPTED', 'running', 'req-old', 1, 'world-old')
    ended = row('ENDED', 'ended', 'req-old', 1, 'world-old')
    pend = '501|travel_alternatives|alt-v1:x:{"pending_change":{"old_agreement_id":"%s","offer":{"destination":"the Stumble Inn"}}}' % AID
    nop = '502|travel_alternatives|alt-v1:x:{"options":[]}'
    prop = step('Squin it is.', full=[['travel_agreement', row('PROPOSED', 'proposed', None, None, None)]])
    lead = step('Lead on.', full=[['travel_agreement', old]], log=[START % 'req-old'])
    ask = step('Which is it: Squin or the Stumble Inn?')
    insist = step('Before we turn around, say it plain.')
    yes = step('Fine, the Stumble Inn it is.', full=[['travel_agreement', ended if n != 'sj20d-lost' else old]])
    # alt dumps in call order: alt_s3, alt_pre (one per insistence turn), alt_post, alt_after_yes
    if n == 'sj20d-pass':
        steps = [prop, lead, ask, insist, yes]; alt = [[nop], [pend], [pend], [nop]]
    elif n == 'sj20d-second':
        steps = [prop, lead, ask, insist, insist, yes]; alt = [[nop], [nop], [pend], [pend], [nop]]
    elif n == 'sj20d-third':
        steps = [prop, lead, ask, insist, insist, insist, yes]; alt = [[nop], [nop], [nop], [pend], [pend], [nop]]
    elif n == 'sj20d-never':
        steps = [prop, lead, ask, insist, insist, insist, yes]; alt = [[nop]]
    elif n == 'sj20d-nopending-after-load':
        steps = [prop, lead, ask, insist, yes]; alt = [[nop], [pend], [nop], [nop]]
    else:  # sj20d-lost: pending kept but the bare yes does not end/replace the old row
        steps = [prop, lead, ask, insist, yes]; alt = [[nop], [pend], [pend], [nop]]
    S = {'steps': steps, 'alt': alt, 'agr_dumps': [dump((90, old)), dump((90, old), (120, ended))],
         'agr': [[f'120|ENDED|ended||true|{AID}|Squin']]}
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
