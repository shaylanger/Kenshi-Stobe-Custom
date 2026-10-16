#!/usr/bin/env python3
"""tripscen.py <name>   prints the tripfake.py scenario JSON used by trip-selftest.sh (synthetic data modelled on the real rows of the
i3/i4 runs: travel_agreement ACCEPTED/COMPLETED/FAILED/ENDED, stobe_state, N2_ABANDON, social_effect)."""
import json
import sys

AID = 'trip-aaa'


def row(status, dest='Squin', **kw):
    d = {'status': status, 'kind': 'guide', 'destination': dest, 'agreement_id': AID, 'plan_hash': 'f03be997'}
    d.update(kw)
    return 'travel-v1:1:2:' + json.dumps(d, separators=(',', ':'))


def agr(rowid, status, phase='', reason='', rel='', dest='Squin'):
    return f'{rowid}|{status}|{phase}|{reason}|{rel}|{AID}|{dest}'


def state(faction, first='none', goal='NULL_TASK', jobs=''):
    return json.dumps({'name': 'x', 'faction': faction, 'ai': {'first_order': first, 'current_goal': goal, 'permajobs': ([jobs] if jobs else [])}})


NATIVE = ['OWNED_TRAVEL start accepted=1 reason=native_owned_order_assigned']
S1 = {'reply': 'Squin is southwest.', 'full': [['travel_agreement', row('PROPOSED')]]}
S2 = {'reply': 'I lead, you follow.', 'full': [['travel_agreement', row('ACCEPTED')]], 'log': NATIVE}
ACC = [agr(7001, 'ACCEPTED', 'accepted')]
SHAY = state('Nameless')
CIND = state('Traders Guild')
n = sys.argv[1]
S = {}
if n == '23a-pass':
    S = {'steps': [S1, S2, {'reply': 'Walk is done, then.'}], 'agr': [ACC, [agr(7009, 'COMPLETED', 'completed', '', 'true')] + ACC],
         'state': {'Shay': [SHAY], 'Cind': [CIND]}}
elif n == '23a-fail':     # failed instead of completed, controller left, two acknowledgements
    S = {'steps': [S1, S2, {'reply': 'Walk is done, then.'}], 'agr': [ACC, [agr(7009, 'FAILED', 'failed', 'native_order_ended_before_goal', 'false')] + ACC],
         'state': {'Shay': [SHAY], 'Cind': [state('Traders Guild', 'follow', 'FOLLOW')]}}
elif n == '23a-noaccept':
    S = {'steps': [{'reply': 'No.'}, {'reply': 'No.'}, {'reply': 'No.'}], 'agr': [[]], 'state': {'Shay': [SHAY], 'Cind': [CIND]}}
elif n == '23a-lead':     # accept turn without the native start line -> s2b "Lead the way." is said
    S = {'steps': [S1, dict(S2, log=[]), {'reply': 'Squin it is.', 'log': NATIVE}, {'reply': 'Walk is done, then.'}],
         'agr': [ACC, [agr(7009, 'COMPLETED', 'completed', '', 'true')] + ACC], 'state': {'Shay': [SHAY], 'Cind': [CIND]}}
elif n == '23a-fallback':  # first wording gets no PROPOSED row -> s1b
    S = {'steps': [{'reply': 'I need a concrete offer.'}, S1, S2, {'reply': 'Walk is done, then.'}],
         'agr': [ACC, [agr(7009, 'COMPLETED', 'completed', '', 'true')] + ACC], 'state': {'Shay': [SHAY], 'Cind': [CIND]}}
elif n in ('20a-pass', '20a-fail'):
    s4 = [['travel_agreement', row('ENDED')]] if n == '20a-pass' else []
    S = {'steps': [S1, S2, {'reply': 'We already agreed on Squin.'}, {'reply': 'Fine, changed.', 'full': s4}], 'agr': [ACC, [agr(7010, 'ENDED')] + ACC]}
elif n in ('20b-gated', '20b-pass', '20b-nofail'):
    reason = 'native_path_or_actor_failure' if n == '20b-pass' else 'native_order_identity_changed'
    fin = [] if n == '20b-nofail' else [agr(7011, 'FAILED', 'failed', reason, 'false')]
    S = {'steps': [S1, S2, {'reply': "Squin didn't take. The route dropped out from under us."}], 'agr': [ACC, fin + ACC]}
elif n in ('23c-pass', '23c-fail'):
    cind_after = state('Traders Guild')
    malzin = [state('Nameless'), state('Drifters' if n == '23c-pass' else 'Nameless'), state('Drifters' if n == '23c-pass' else 'Nameless')]
    S = {'steps': [S1, S2, {'reply': "If you're leaving, say so plain."}, {'reply': "Fine. I'm gone.", 'log': ['ACTION_EXEC: LEAVE Malzin']}, {'reply': 'Suit yourself.'}],
         'agr': [ACC, ACC, [agr(7012, 'ENDED')] + ACC], 'state': {'Cind': [CIND, cind_after], 'Malzin': malzin}}
elif n in ('23d-pass', '23d-nojob'):
    S = {'steps': [S1, S2, {'reply': "Suit yourself. Squin's off.", 'log': ['OWNED_TRAVEL release reason=owned_order_removed_native_end_pending']}],
         'agr': [ACC, [agr(7013, 'ENDED')] + ACC], 'state': {'Cind': [state('Traders Guild', 'none', 'NULL_TASK', 'Operating machine' if n == '23d-pass' else '')]}}
elif n in ('24a-pass', '24a-fail'):
    p = 'Known places you can name: Stumble Inn, Squin'
    s1 = {'reply': 'Stumble Inn, for the quiet.', 'prompt': p}
    if n == '24a-fail':
        s1['full'] = [['travel_agreement', row('PROPOSED', 'Stumble Inn')]]
    S = {'steps': [s1, {'reply': 'Fogmen country.'}]}
elif n in ('13b-pass', '13b-nofire', '13b-ctlfire', '13b-noN2'):
    prox = 'N2_PROXIMITY: leaver=Cind partner=Malzin dist=12'
    ab = 'N2_ABANDON: leaver=Shay partner=Malzin state=knocked_out dist=45 seconds=33 held=919'
    se = '(5,Malzin,abandoned_in_danger,-19,Shay)'
    S = {'steps': [], 'se': [[], [se], [se]], 'se_count': 1, 'n2': [[prox, ab], [prox]]}
    if n == '13b-nofire':
        S['n2'] = [[prox], [prox]]; S['se'] = [[], [], []]; S['se_count'] = 0
    if n == '13b-ctlfire':
        S['n2'] = [[prox, ab], [prox, ab]]
    if n == '13b-noN2':
        S['n2'] = [[], []]; S['se'] = [[], [], []]; S['se_count'] = 0
elif n.startswith('08d-'):
    TID = 'd32f118d423bf225010baac3ef4dedfc'

    def fu(status='open', reason=None, kind='personal_plan'):
        d = {'topic_id': TID, 'kind': kind, 'status': status, 'source_quote': 'I need to sell my furs in Squin before winter.', 'created_gamets': 100}
        if reason:
            d['closed_reason'] = reason
        return 'followup-v1:aa:' + TID + ':' + json.dumps(d, separators=(',', ':'))
    TOP = {'reply': 'Furs, in this cold?', 'full': [['social_followup', fu()]]}
    NOTOP = {'reply': 'Hm.', 'full': []}
    S3 = {'reply': 'Walk is done, then.'}
    open_row = 'social_followup|1|' + fu().split(':', 3)[3]
    closed_row = 'social_followup|2|' + fu('closed', 'outcome_completed').split(':', 3)[3]
    claim_row = 'situated_remark_claim|3|' + json.dumps({'actor_serial': 1, 'event_id': 'followup:' + TID + ':1'})
    bored = ['BORED_EVENT dispatched Cind->Shay mode=director']
    S = {'steps': [TOP, S1, S2, S3], 'agr': [ACC, [agr(7009, 'COMPLETED', 'completed', '', 'true')] + ACC], 'state': {'Shay': [SHAY], 'Cind': [CIND]},
         'fu': [[open_row], [open_row, closed_row]], 'fu_closed': 1, 'bored': bored}
    if n == '08d-s0b':      # first wording creates no topic -> s0b "I want ..." does
        S['steps'] = [NOTOP, TOP, S1, S2, S3]
    elif n == '08d-notopic':
        S['steps'] = [NOTOP, NOTOP, S1, S2, S3]
    elif n == '08d-open':    # claim ticks happened but the topic is still open
        S['fu'] = [[open_row], [open_row]]; S['fu_closed'] = 0
    elif n == '08d-noticks':
        S['fu'] = [[open_row], [open_row]]; S['fu_closed'] = 0; S['bored'] = []
    elif n == '08d-claim':   # closed, but a situated_remark_claim row for the topic was still written
        S['fu'] = [[open_row], [open_row, closed_row, claim_row]]
    elif n == '08d-notrip':  # trip failed instead of completing
        S['agr'] = [ACC, [agr(7009, 'FAILED', 'failed', 'native_order_ended_before_goal', 'false')] + ACC]
        S['fu'] = [[open_row], [open_row]]; S['fu_closed'] = 0
else:
    sys.exit('unknown scenario ' + n)
print(json.dumps(S))
