#!/usr/bin/env python3
"""unblockscen_sffb4.py <name>   scenario JSON for unblockfake_sffb4.py (unblock_sffb4_selftest.sh). Base = unblockscen_sffb.py ko-pass (v3 sfk11-pass fu sequence, cstate T,T,F,F) + server-log lines that show
the follow-up claim path (tlog per tick: c1b, c1a, c2) + the v4 keys. Names:
  pass native-false-eventlog-true native-false-no-rows calm-eventlog-fresh no-scope no-path plain-people unprotect-fail strays-cleared strays-stay events-fresh events-age-out claim-cooldown
  mut-claim-nosnap mut-claim-snap mut-no-claim-after"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]
S = json.loads(subprocess.run([sys.executable, os.path.join(HERE, 'unblockscen_sffb.py'), 'ko-pass'], capture_output=True, text=True, check=True).stdout)
T, F = '{"in_combat": true}', '{"in_combat": false}'
TID = 't1'


def jd(o):
    return json.dumps(o, separators=(',', ':'))


fu0 = {'topic_id': TID, 'kind': 'personal_plan', 'status': 'open', 'ask_count': 0, 'not_before_gamets': 1, 'expires_gamets': 600000}
fu1 = dict(fu0, ask_count=1)
fuA = dict(fu0, not_before_gamets=3600)   # the first dump is taken before the not_before edit


def fu(d):
    return '201|social_followup|followup-v1:x:y:' + jd(d)


c1 = '301|situated_remark_claim|' + jd({'actor_serial': 1, 'event_id': 'followup:%s:1' % TID})
GATE = ['[2026-10-16 01:00:00] [DEBUG] social_followup_claim null: gate:attention_gate | {"actor":"Cind","request_id":"r"}',
        '[2026-10-16 01:00:00] [INFO] Targeted optional request: nothing claimable | {"speaker":"Cind"}']
SENT = ['[2026-10-16 01:02:00] [INFO] Director bored turn claimed a social remark']
S['tlog'] = [GATE, GATE, SENT]
if n == 'pass':
    pass
elif n == 'native-false-eventlog-true':   # the 4080-i4 defect: every state read says false while the eventlog has fresh combat rows
    S['cstate'] = [F, F, F, F]
    S['combat_age'] = ['combat|5', 'combat|7', 'combatend|60', 'combatend|60']
elif n == 'native-false-no-rows':         # false reads and NO combat rows: the override must not invent a fight
    S['cstate'] = [F, F, F, F]
    S['combat_age'] = ['combatend|60']
    S['combat_rows'] = 0
elif n == 'calm-eventlog-fresh':          # calm polls say false but combat rows keep coming: the fight is NOT over
    S['cstate'] = [T, T, F, F, F]
    S['combat_age'] = ['combat|4']   # the age is only read for a `false`: every calm poll sees a fresh combat row
elif n == 'no-scope':
    L = ['[2026-10-16 01:00:00] [DEBUG] social_followup_claim null: no_social_scope | {"actor":"Cind"}', GATE[1]]
    S['tlog'] = [L, L, SENT]
elif n == 'no-path':
    S['tlog'] = [[GATE[1]], [GATE[1]], SENT]
elif n == 'plain-people':
    S['shay_missing'] = True
elif n == 'unprotect-fail':
    S['unprotect_fail'] = True
elif n == 'strays-cleared':
    S['scene_seq'] = [False, True, False]
elif n == 'strays-stay':
    S['scene_seq'] = [False, True, True]
elif n == 'events-fresh':
    S['evage'] = ['40|threat']
elif n == 'events-age-out':
    S['evage'] = ['40|threat', '90|threat', '130|-']
elif n == 'claim-cooldown':
    S['claimage'] = [100, 150, 190]
elif n == 'mut-claim-nosnap':
    S['claim'] = [[c1], [c1], [c1]]
    S['fu'] = [[fu(fuA)], [fu(fu0)], [fu(fu1)], [fu(fu1)], [fu(fu1)]]
elif n == 'mut-claim-snap':
    S['claim'] = [[], [c1], [c1]]
    S['fu'] = [[fu(fuA)], [fu(fu0)], [fu(fu0)], [fu(fu1)], [fu(fu1)]]
elif n == 'mut-no-claim-after':
    S['claim'] = [[], [], []]
    S['fu'] = [[fu(fuA)], [fu(fu0)], [fu(fu0)], [fu(fu0)], [fu(fu0)]]
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
