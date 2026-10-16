#!/usr/bin/env python3
"""reloadscen_b.py <name>   prints the reloadfake_b.py scenario JSON for reloadselftest_b.sh (set-B reload rows 14-e 13-f 13-g 10-e 19-e 19-f).
Synthetic evidence shaped like the real rows (deal snapshot lines of reloaddefs_b.sh rb_snap_deal, travel-v1 agreement rows of resume_scen.py).
Every defect variant breaks exactly ONE assertion (named in reloadselftest_b.sh) so each check is shown to be able to fail alone.
Names:
  14e-pass 14e-expired 14e-newid 14e-noshift 14e-bigshift 14e-noshifts 14e-weak 14e-notopen 14e-nobread 14e-notperformed 14e-fired1
  13g-pass 13g-direct 13g-notcomplete 13g-nocatsleg 13g-nokept 13g-keptbig 13g-broken 13g-expired 13g-newid 13g-noshift 13g-sameclock 13g-notpending 13g-noprice
  13f-pass 13f-notbreached 13f-nobroken 13f-brokenbig 13f-keptpromise
  10e-pass 10e-samesession 10e-ingestoff 10e-norescope 10e-scopechanged 10e-othersave 10e-older 10e-unmet 10e-control
  19e-pass 19e-pass-noint 19e-early-start 19e-early-rows 19e-chat-no-resume 19e-no-start-on-chat 19e-dup 19e-wrongdest 19e-nostate 19e-nostart
  19f-pass 19f-cap-default-fails 19f-capmode-pass 19f-dup-start 19f-wrongcount 19f-newagr 19f-cap-notterminal 19f-cap-newtravel 19f-cap-loop"""
import json
import sys

AID = 'trip-resume-aaaa'
HASH = 'ab' * 32
PT = {'x': -62380.0, 'y': 330.0, 'z': 16250.0, 'label': 'Squin'}
START = 'OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned request_id=%s'
SH = [{'load_token': 'tokA', 'shift_s': 540}]
PEND = 'GIVE_ITEM:PENDING,GIVE_CATS:PENDING'
NPCV = 'GIVE_ITEM:VERIFIED,GIVE_CATS:PENDING'


# ---------------------------------------------------------------- deals
def dl(i='C1', st='AWAITING_PERFORMANCE', shift=0, age=5, terms=NPCV, shifts=None):
    return '|'.join([i, st, str(shift), str(age), terms, json.dumps(shifts if shifts is not None else [], separators=(',', ':'))])


def e14(o):
    s1 = dl('C1', o.get('s1st', 'COUNTERED'), 0, 3, PEND)
    bd = dl('C1', o.get('s1st', 'COUNTERED'), 0, 543, PEND)
    post = dl(o.get('postid', 'C1'), o.get('poststatus', 'COUNTERED'), 540, 45, PEND, SH)
    end = dl('C1', o.get('endst', 'AWAITING_PERFORMANCE'), o.get('endshift', 540), 60, o.get('endterms', NPCV), o.get('endshifts', SH))
    return {'deals': [s1, bd, post, end], 'nows': [1000, 1000 + o.get('gap', 120)], 'fired': [0, o.get('fired', 2)],
            'steps': [{'reply': 'Not for free: bread now, and you pay me after.'}, {'reply': 'Deal then.', 'give': ['Bread'] if o.get('bread', True) else []}],
            'inv0': {'SHAY': {}, 'CIND': {'Bread': 3}}, 'pauselog': ['Deal clocks paused across a load: gap=540s']}


def effects(kind, **o):
    if kind == 'g':
        rows = o.get('effects', ['5000|kept_promise|2|deal:D1|1'])
    else:
        rows = o.get('effects', ['5000|broken_promise|-10|deal:D1|1'])
    return rows


def paylater(kind, o):
    s1st = o.get('s1st', 'PROPOSED')
    s1 = dl('D1', s1st, 0, 2, PEND)
    pre = dl('D1', o.get('prest', 'AWAITING_PERFORMANCE'), 0, 5, o.get('preterms', NPCV))
    post = dl(o.get('postid', 'D1'), o.get('poststatus', 'AWAITING_PERFORMANCE'), 300, 9, NPCV, SH)
    if kind == 'g':
        endst, endterms = o.get('endst', 'COMPLETE'), o.get('endterms', 'GIVE_ITEM:VERIFIED,GIVE_CATS:VERIFIED')
    else:
        endst, endterms = o.get('endst', 'BREACHED_PLAYER'), o.get('endterms', NPCV)
    end = dl('D1', endst, o.get('endshift', 300), 40, endterms, SH)
    pre_n = 10 if o.get('prest', 'AWAITING_PERFORMANCE') != 'AWAITING_PERFORMANCE' else 1   # rb_poll_deal polls 10 x when the pending state is never reached
    deals = [s1] + [pre] * pre_n + [post, post, end]
    steps = ([{'reply': 'Fine, bread now.'}, {'reply': 'Deal then.', 'give': ['Bread']}] if s1st in ('PROPOSED', 'COUNTERED') else [{'reply': 'Fine, bread now.', 'give': ['Bread']}]) + [{'reply': 'Of course.'}]
    d = {'deals': deals, 'steps': steps, 'inv0': {'SHAY': {}, 'CIND': {'Bread': 3}}, 'effects': effects(kind, **o), 'price': o.get('price', 20),
         'clocks': o.get('clocks', ['tokA|x|1700', 'tokB|x|1900']), 'pauselog': ['Deal clocks paused across a load: gap=300s'], 'gamets': 5000}
    return d


# ---------------------------------------------------------------- 10-e
CAMP = 'ab' * 16


def scope(epoch, sess):
    return {'campaign_id': CAMP, 'timeline_epoch': str(epoch), 'native_session_id': sess}


def p10(o):
    pre = {'mode': 'scope', 'scope': scope(100, 's-old'), 'ingest_mode': 'enabled', 'rescope_enabled': True}
    cases = {'same_campaign_later_load': {'status': 'AWAITING_PLAYER', 'note': 'exact_restitution_awaiting_player', 'returned_null': False},
             'other_save': {'status': 'IMPOSSIBLE', 'note': 'exact_restitution_scope_changed', 'returned_null': False},
             'older_epoch': {'status': 'IMPOSSIBLE', 'note': 'exact_restitution_scope_changed', 'returned_null': False},
             'unprovable_after_reload': {'status': 'IMPOSSIBLE', 'note': 'exact_restitution_unprovable_after_reload', 'returned_null': False},
             'same_load_deadline_control': {'status': 'UNMET', 'note': 'exact_receipt_deadline_passed', 'returned_null': False}}
    for k, v in o.get('cases', {}).items():
        cases[k] = v
    live = o.get('live', scope(200, 's-new'))
    ev = {'mode': 'eval', 'live': live, 'ingest_mode': o.get('ingest', 'enabled'), 'rescope_enabled': o.get('rescope', True), 'cases': cases}
    return {'probe': [json.dumps(pre), json.dumps(ev), json.dumps(dict(pre, scope=live))]}


# ---------------------------------------------------------------- trips (modelled on resume_scen.py)
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
TURNS = ['resolved_speaker=Cind', 'ACTION_EXEC: SAY [Cind]: We are still on our way to Squin. (NPC)', START % 'req-new']


S4 = {'reply': 'We were heading to Squin.', 'log': [START % 'req-new']}


def e19(o):   # lazy resume: steps s1 s2 [s3] then the ONE post-load chat line s4; dumps = [agr_pre, agr_ctl (quiet window), agr_all]
    return {'steps': o.get('steps', [S1, S2, S4]), 'follow': [o.get('state', state())], 'silent': o.get('silent', [0]),
            'agr_dumps': [dump(*PRE), o.get('ctl', dump(*PRE, INT)), o.get('all', dump(*PRE, INT, REQ, RUN))]}


def f19(o):
    n, mode, cap = 4, o.get('mode', 'target'), o.get('cap', 3)
    rows, dumps, steps, follow = [], [dump(*PRE)], [S1, S2], []
    extra_all = o.get('extra_all', [])
    for i in range(1, n + 1):
        failed = i > cap
        counts = o.get('counts', {})
        if failed and o.get('failed_kind', 'failed') == 'failed':
            rows.append((200 + i * 10, row('FAILED', 'failed', 'req-%d' % (i - 1), i, 'world-%d' % (i - 1), resume_failure='resume_count', resume_count=cap)))
        elif failed:   # cap-notterminal: the trip keeps running past the cap
            rows.append((200 + i * 10, row('ACCEPTED', 'running', 'req-%d' % i, i + 1, 'world-%d' % i, resume_count=i)))
        else:
            rows.append((200 + i * 10, row('ACCEPTED', 'running', 'req-%d' % i, i + 1, 'world-%d' % i, resume_count=counts.get(i, i))))
        if failed and i == o.get('loop_at', -1):
            rows.append((201 + i * 10, row('PROPOSED', 'proposed', None, None, None, aid='trip-new-bbbb')))
        dumps.append(dump(*PRE, *rows))
        starts = [START % ('req-%d' % i)] if (not failed or o.get('newtravel_at') == i) else []
        if i in o.get('dup_at', []):
            starts = starts * 2
        steps.append({'reply': 'We are on our way.' if starts else 'I am not going on.', 'log': starts})
        follow.append(state() if not failed else state('none'))
    allrows = [r for r in rows if json.loads(r[1].split(':', 3)[3]).get('agreement_id') == AID] + extra_all
    dumps.append(dump(*PRE, *allrows))
    return {'steps': steps, 'follow': follow, 'agr_dumps': dumps}


n = sys.argv[1]
S = None
if n == '14e-pass':
    S = e14({})
elif n == '14e-expired':
    S = e14({'poststatus': 'EXPIRED'})
elif n == '14e-newid':
    S = e14({'postid': 'C9'})
elif n == '14e-noshift':
    S = e14({'endshift': 0})
elif n == '14e-bigshift':
    S = e14({'endshift': 1300})
elif n == '14e-noshifts':
    S = e14({'endshifts': []})
elif n == '14e-weak':
    S = e14({'gap': 30})
elif n == '14e-notopen':
    S = e14({'s1st': 'ACCEPTED'})
elif n == '14e-nobread':
    S = e14({'bread': False})
elif n == '14e-notperformed':
    S = e14({'endst': 'ACCEPTED', 'endterms': PEND})
elif n == '14e-fired1':
    S = e14({'fired': 1})
elif n == '13g-pass':
    S = paylater('g', {})
elif n == '13g-direct':
    S = paylater('g', {'s1st': 'AWAITING_PERFORMANCE'})
elif n == '13g-notcomplete':
    S = paylater('g', {'endst': 'AWAITING_PERFORMANCE', 'endterms': 'GIVE_ITEM:VERIFIED,GIVE_CATS:VERIFIED'})
elif n == '13g-nocatsleg':
    S = paylater('g', {'endterms': 'GIVE_ITEM:VERIFIED,GIVE_CATS:PENDING'})
elif n == '13g-nokept':
    S = paylater('g', {'effects': []})
elif n == '13g-keptbig':
    S = paylater('g', {'effects': ['5000|kept_promise|7|deal:D1|1']})
elif n == '13g-broken':
    S = paylater('g', {'effects': ['5000|kept_promise|2|deal:D1|1', '5001|broken_promise|-8|deal:D1|1']})
elif n == '13g-expired':
    S = paylater('g', {'poststatus': 'EXPIRED'})
elif n == '13g-newid':
    S = paylater('g', {'postid': 'D9'})
elif n == '13g-noshift':
    S = paylater('g', {'endshift': 0})
elif n == '13g-sameclock':
    S = paylater('g', {'clocks': ['tokA|x|1700', 'tokA|x|1900']})
elif n == '13g-notpending':
    S = paylater('g', {'prest': 'ACCEPTED', 'preterms': PEND})
elif n == '13g-noprice':
    S = paylater('g', {'price': ''})
elif n == '13f-pass':
    S = paylater('f', {})
elif n == '13f-notbreached':
    S = paylater('f', {'endst': 'AWAITING_PERFORMANCE'})
elif n == '13f-nobroken':
    S = paylater('f', {'effects': []})
elif n == '13f-brokenbig':
    S = paylater('f', {'effects': ['5000|broken_promise|-30|deal:D1|1']})
elif n == '13f-keptpromise':
    S = paylater('f', {'effects': ['5000|broken_promise|-10|deal:D1|1', '5001|kept_promise|2|deal:D1|1']})
elif n == '10e-pass':
    S = p10({})
elif n == '10e-samesession':
    S = p10({'live': scope(100, 's-old')})
elif n == '10e-ingestoff':
    S = p10({'ingest': 'off'})
elif n == '10e-norescope':
    S = p10({'rescope': False})
elif n == '10e-scopechanged':
    S = p10({'cases': {'same_campaign_later_load': {'status': 'IMPOSSIBLE', 'note': 'exact_restitution_scope_changed', 'returned_null': False}}})
elif n == '10e-othersave':
    S = p10({'cases': {'other_save': {'status': 'AWAITING_PLAYER', 'note': '', 'returned_null': False}}})
elif n == '10e-older':
    S = p10({'cases': {'older_epoch': {'status': 'AWAITING_PLAYER', 'note': '', 'returned_null': False}}})
elif n == '10e-unmet':
    S = p10({'cases': {'unprovable_after_reload': {'status': 'UNMET', 'note': 'exact_receipt_deadline_passed', 'returned_null': False}}})
elif n == '10e-control':
    S = p10({'cases': {'same_load_deadline_control': {'status': 'IMPOSSIBLE', 'note': 'exact_restitution_unprovable_after_reload', 'returned_null': False}}})
elif n == '19e-pass':
    S = e19({})
elif n == '19e-pass-noint':      # the quiet window leaves the dump untouched (no interrupted row before the chat): still correct
    S = e19({'ctl': dump(*PRE)})
elif n == '19e-early-start':     # the NPC ran off during the quiet window (immediate resume on load): wrong under the lazy rule
    S = e19({'silent': [1]})
elif n == '19e-early-rows':      # no native start logged, but the agreement already moved to requested/running before any chat
    S = e19({'ctl': dump(*PRE, INT, REQ, RUN)})
elif n == '19e-chat-no-resume':  # the chat turn does not resume anything (today's gap): several assertions fail
    S = e19({'steps': [S1, S2, {'reply': 'I am not sure.'}], 'all': dump(*PRE, INT)})
elif n == '19e-no-start-on-chat':   # isolated: the chat turn logs no start, the rest of the evidence is the resumed chain
    S = e19({'steps': [S1, S2, {'reply': 'We were heading to Squin.'}]})
elif n == '19e-dup':
    S = e19({'steps': [S1, S2, dict(S4, log=[START % 'req-new', START % 'req-new2'])]})
elif n == '19e-wrongdest':
    S = e19({'state': state(dest=(1, 2, 3))})
elif n == '19e-nostate':
    S = e19({'state': state('none')})
elif n == '19e-nostart':
    S = e19({'steps': [S1, dict(S2, log=[]), {'reply': 'Fine.'}, S4]})
elif n == '19f-pass':
    S = f19({'cap': 99})
elif n == '19f-cap-default-fails':   # today's build: the 4th reload ends the trip FAILED resume_count, target mode wants all 4 to resume
    S = f19({'cap': 3})
elif n == '19f-capmode-pass':        # run with --mode cap --cap 2: reloads 1-2 resume, reload 3 ends honestly
    S = f19({'cap': 2, 'mode': 'cap'})
elif n == '19f-dup-start':
    S = f19({'cap': 99, 'dup_at': [2]})
elif n == '19f-wrongcount':
    S = f19({'cap': 99, 'counts': {3: 1}})
elif n == '19f-newagr':
    S = f19({'cap': 99, 'extra_all': [(900, row('PROPOSED', 'proposed', None, None, None, aid='trip-new-bbbb'))]})
elif n == '19f-cap-notterminal':
    S = f19({'cap': 2, 'mode': 'cap', 'failed_kind': 'running'})
elif n == '19f-cap-newtravel':
    S = f19({'cap': 2, 'mode': 'cap', 'newtravel_at': 3})
elif n == '19f-cap-loop':
    S = f19({'cap': 2, 'mode': 'cap', 'loop_at': 3})
if S is None:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
