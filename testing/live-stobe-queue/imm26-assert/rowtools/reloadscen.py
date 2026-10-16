#!/usr/bin/env python3
"""reloadscen.py <name>   prints the reloadfake.py scenario JSON for reload-selftest.sh (synthetic rows modelled on the wpR1/wpR3 deploy notes).
Names: 24c-goalgone 26d-pass 26d-old 26d-reject 26d-nooffer 26d-samewid 26d-complete 26d-nocomplete 26dx-pass 26dx-bad 26e-pass 26e-notrebound 26e-reject 26f-pass
       24c-pass 24c-noregion 24c-lost 23e-pass 23e-lost 23e-nopre 27a-pass 27a-lost 27a-noorder 27a-statuserr 27a-statuserr-lost 27a-ctrl-approaches 27a-pre-wander 27a-post-standoff-edge 08e-pass 08e-lost 08e-noclaim 08e-noclaim-noticks 08e-double 20d-pass 20d-nopending 20d-lost"""
import json
import sys


def jd(o):
    return json.dumps(o, separators=(',', ':'))


AID = 'trip-resume-aaaa'
HASH = 'ab' * 32
PT = {'x': -62380.0, 'y': 330.0, 'z': 16250.0, 'label': 'Vain'}
START = 'OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned request_id=%s'
RG = {'region': 'Vain', 'goal_type': 'regional_outing'}


def act(i, world, status, kind='Hunt', res='42243-rebirth.mod', qty='1', rstate='', rof='', rcont='', rcount='', targets='', camp=''):
    return '|'.join([i, world, '111', '222', '1', status, kind, res, qty, rstate, rof, rcont, rcount, targets, camp])


def row(status, phase, rid, gen, world, aid=AID, dest='Vain', rg=RG, **ex):
    d = {'status': status, 'kind': 'same_route', 'destination': dest, 'destination_point': PT, 'agreement_id': aid, 'plan_hash': HASH,
         'expires_gamets': 99999, 'accepted_by': ['Cind', 'Shay'], 'leader': 'npc',
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


n = sys.argv[1]
S = {}
W1, W2 = 'epoch-1', 'epoch-2'
A1, A2 = 'activity-aaaa', 'activity-bbbb'


def job(kind='Hunt', **kw):
    t = dict(targets='[11,12,13,14,15]') if kind == 'ClearGroup' else {}
    p = act(A1, W1, 'proposed', kind, **t)
    a = act(A1, W1, 'accepted', kind, **t)
    old = act(A1, W1, 'superseded', kind, rstate='ended', rcont=A2, **t)
    new = act(A2, W2, 'accepted', kind, rstate='resumed', rof=A1, rcount='1', **t)
    s = {'steps': [step('Shall we hunt for 1 Raw Meat together?'), step('Good. One goat, then we stop.'), step('Still on it, on our way.')],
         'act': [[p], [a], [old, new]], 'out': [[f'{A1}|1|false|{W1}'], [f'{A1}|1|false|{W1}', f'{A2}|1|false|{W2}']], 'actlog': [[], ['ACTIVITY resume start accepted']]}
    s.update(kw)
    return s


if n == '26d-pass':
    S = job()
elif n == '26d-old':    # today's behaviour: the accepted record is orphaned in the old world, no continuation
    S = job(act=[[act(A1, W1, 'proposed')], [act(A1, W1, 'accepted')], [act(A1, W1, 'accepted')]], out=[[f'{A1}|1|false|{W1}']])
elif n == '26d-reject':  # the known 26-a blocker: accept does not land
    S = job(act=[[act(A1, W1, 'proposed')], [act(A1, W1, 'failed')]], steps=[step('Shall we hunt?'), step('Good.')],
            actlog=[['ACTIVITY start rejected: requester_now_hostile']])
elif n == '26d-nooffer':
    S = job(act=[[]], steps=[step('I have no beast in sight.')])
elif n == '26d-samewid':
    S = job(act=[[act(A1, W1, 'proposed')], [act(A1, W1, 'accepted')], [act(A1, W1, 'superseded', rcont=A2), act(A2, W1, 'accepted', rstate='resumed', rof=A1, rcount='1')]],
            out=[[f'{A1}|1|false|{W1}'], [f'{A1}|1|false|{W1}', f'{A2}|1|false|{W1}']])
elif n in ('26d-complete', '26d-nocomplete'):
    fin = act(A2, W2, 'completed' if n == '26d-complete' else 'accepted', rstate='resumed', rof=A1, rcount='1')
    S = job()
    S['act'].append([act(A1, W1, 'superseded', rstate='ended', rcont=A2), fin])
    S['out'].append(S['out'][-1])
elif n in ('26dx-pass', '26dx-bad'):
    c = act(A1, W1, 'cancelled', rstate='')
    post = [c] if n == '26dx-pass' else [c, act('activity-cccc', W2, 'accepted', rstate='resumed', rof=A1, rcount='1')]
    S = {'steps': [step('Shall we hunt?'), step('Good.'), step('Cancelled, then.'), step('We are not on any job.')],
         'act': [[act(A1, W1, 'proposed')], [c], post], 'out': [[f'{A1}|1|false|{W1}'], [f'{A1}|1|false|{W1}']], 'actlog': [[], []]}
elif n in ('26e-pass', '26e-notrebound', '26e-reject'):
    p1 = act(A1, W1, 'proposed')
    p2 = act(A1, W2, 'proposed', rstate='resumed') if n != '26e-notrebound' else p1
    p3 = act(A1, W2, 'accepted', rstate='resumed') if n != '26e-notrebound' else p1
    S = {'steps': [step('Shall we hunt for 1 Raw Meat together?'), step('Shall we travel to hunt 1 Raw Meat, then?'), step('Good.')],
         'act': [[p1], [p2], [p3 if n != '26e-reject' else p2]], 'out': [[f'{A1}|1|false|{W1}']],
         'actlog': [['ACTIVITY start rejected: requester_now_hostile'] if n == '26e-reject' else []]}
elif n == '26f-pass':
    S = job('ClearGroup')
elif n in ('24c-pass', '24c-noregion', '24c-lost', '24c-goalgone'):
    rg = None if n == '24c-noregion' else RG
    PRE = [(90, row('ACCEPTED', 'requested', 'req-old', 1, 'world-old', rg=rg)), (95, row('ACCEPTED', 'running', 'req-old', 1, 'world-old', rg=rg))]
    if n == '24c-lost':
        post = [(111, row('FAILED', 'failed', 'req-old', 1, 'world-old', reason='destination_not_resumable'))]
    else:
        prg = None if n == '24c-goalgone' else rg
        post = [(111, row('ACCEPTED', 'interrupted_by_load', None, None, None, rg=prg, interrupted_gamets=500)), (112, row('ACCEPTED', 'requested', 'req-new', 2, 'world-new', rg=prg)),
                (113, row('ACCEPTED', 'running', 'req-new', 2, 'world-new', rg=prg))]
    S = {'steps': [step('Vain, the general area, sounds good.', full=[['region_plan', jd({'stage': 'route_ready', 'region': 'Vain'})]]),
                   step('Shall we go there?', full=[['travel_agreement', row('PROPOSED', 'proposed', None, None, None, rg=rg)]]),
                   step('Lead on.', full=[['travel_agreement', PRE[0][1]]], log=[START % 'req-old']),
                   step('We were heading toward Vain.', log=[START % 'req-new'] if n != '24c-lost' else []), step('Right behind you.')],
         'region': [[f'80|region_plan|{jd({"stage": "route_ready"})}']], 'agr_dumps': [dump(*PRE), dump(*PRE, *post)],
         'follow': [state(), state()] if n != '24c-lost' else [state('none'), state('none')]}
elif n in ('23e-pass', '23e-lost', '23e-nopre'):
    tick = 'FOLLOW_TICK: follower=Cind target=Shay'
    pre = ['HOOK_MSG_PROC: FOLLOW target resolved Cind', tick] if n != '23e-nopre' else []
    post = [tick] if n == '23e-pass' else []
    S = {'steps': [step('Alright, I will follow you.')], 'follow_log': [pre, post], 'closes': [True, n == '23e-pass']}
elif n in ('27a-pass', '27a-lost', '27a-noorder', '27a-ctrl-approaches', '27a-pre-wander', '27a-post-standoff-edge'):
    # 27A-FIX: chase_d = [start, end] u per chase in order control (no contract) / pre / post. A bodyguard ends at its 50-67 u stand-off (<= RW_BG_NEAR 100), a non-follower stays ~200 u.
    bg_state = state(first='present', goal='BODYGUARD')
    keep = n not in ('27a-lost', '27a-noorder')
    cd = {'27a-pass': [[200, 200], [200, 60], [200, 66]], '27a-lost': [[200, 200], [200, 60], [200, 195]], '27a-noorder': [[200, 200], [200, 60], [200, 195]],
          '27a-ctrl-approaches': [[200, 60], [200, 60], [200, 66]],        # the unhired NPC walks to Shay anyway: the chase proves nothing -> SETUP-FAIL
          '27a-pre-wander': [[200, 200], [200, 190], [200, 66]],           # the pre leg never closes
          '27a-post-standoff-edge': [[200, 200], [200, 67.3], [200, 100]]}[n]   # real stand-off 67.3 pre; post exactly at the limit still passes
    S = {'steps': [], 'bg': [['Cind bodyguard Shay hours=24'] if n != '27a-noorder' else ['no contract'],
                             ['Cind bodyguard Shay hours=23'] if keep else ['no contract']],
         'follow': [bg_state if n != '27a-noorder' else state('none', goal='NONE'), bg_state if keep else state('none', goal='NONE'), bg_state],
         'closes': [True, True, keep], 'chase_d': cd}
elif n in ('27a-statuserr', '27a-statuserr-lost'):   # the real 27-a result: hire answered has_contract=1, the status query answered a harness ERROR, state_* has no BODYGUARD
    err = ['ERROR: no character named: status']
    S = {'steps': [], 'bgset': ['Cind [Hungry Bandit] has_contract=1 package=Bodyguard (5090-gamedata.base) hirer=Shay hours_left=24.0'], 'bg': [err, err],
         'follow': [state('none', goal='OTHER')] * 3, 'closes': [True, True, n == '27a-statuserr'],
         'chase_d': [[200, 200], [200, 60], [200, 66 if n == '27a-statuserr' else 195]]}
elif n in ('08e-pass', '08e-lost', '08e-noclaim', '08e-noclaim-noticks', '08e-double'):
    fu = {'topic_id': 't1', 'kind': 'personal_plan', 'status': 'open', 'ask_count': 0, 'not_before_gamets': 3600, 'expires_gamets': 600000}
    fu1 = dict(fu, ask_count=1, not_before_gamets=90000)
    c1 = '301|situated_remark_claim|' + jd({'actor_serial': 1, 'event_id': 'followup:t1:1'})
    claims = [[], [c1], [c1]] if n in ('08e-pass', '08e-lost') else ([[], [], []] if n in ('08e-noclaim', '08e-noclaim-noticks') else [[c1, c1.replace('301', '302')]] * 3)
    S = {'steps': [step('Take care with that armor.', full=[['social_followup', 'followup-v1:x:y:' + jd(fu)]])],
         'fu': [['201|social_followup|followup-v1:x:y:' + jd(fu)], [] if n == '08e-lost' else ['201|social_followup|followup-v1:x:y:' + jd(fu)],
                ['201|social_followup|followup-v1:x:y:' + jd(fu), '202|social_followup|followup-v1:x:y:' + jd(fu1)]],
         'claim': claims, 'bored': 100, 'ticks': 0 if n == '08e-noclaim-noticks' else 3}
elif n in ('20d-pass', '20d-nopending', '20d-lost'):
    old = row('ACCEPTED', 'running', 'req-old', 1, 'world-old', dest='Squin', rg=None)
    ended = row('ENDED', 'ended', 'req-old', 1, 'world-old', dest='Squin', rg=None)
    pend = '501|travel_alternatives|alt-v1:x:{"pending_change":{"old_agreement_id":"%s","offer":{"destination":"the Stumble Inn"}}}' % AID
    nopend = '502|travel_alternatives|alt-v1:x:{"options":[]}'
    S = {'steps': [step('Squin it is.', full=[['travel_agreement', row('PROPOSED', 'proposed', None, None, None, dest='Squin', rg=None)]]),
                   step('Lead on.', full=[['travel_agreement', old]], log=[START % 'req-old']),
                   step('We already agreed on Squin, say so plainly.'),
                   step('Fine, the Stumble Inn it is.', full=[['travel_agreement', ended if n != '20d-lost' else old]])],
         'alt': [[pend] if n != '20d-nopending' else [nopend], [pend] if n == '20d-pass' else [nopend], [nopend]],
         'agr_dumps': [dump((90, old)), dump((90, old), (120, ended))],
         'agr': [[f'120|ENDED|ended||true|{AID}|Squin']]}
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
