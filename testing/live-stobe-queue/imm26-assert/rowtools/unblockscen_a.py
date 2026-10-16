#!/usr/bin/env python3
"""unblockscen_a.py <name>   prints the unblockfake_a.py scenario JSON for unblock_a_selftest.sh. 08-e / 08-d scenarios are the reloadscen.py / tripscen.py base
scenarios plus the targeted-tick keys; 11-b scenarios are built here.
Names: 08e-pass 08e-lost 08e-double 08e-http 08e-gate  08d-pass 08d-open 08d-claim 08d-notrip 08d-http 08d-neg-pass 08d-neg-closed 08d-neg-completed
       11b-pass 11b-claim-nosnap 11b-claim-snap 11b-notcombat 11b-gone 11b-nocalm 11b-http 11b-noclaim-after 11b-notopic 11b-spawnfail"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]
OK = ['{"status":"ok"}', 'HTTP=200']
BAD = ['', 'HTTP=000']
NOTHING = ['[2026-10-16 01:00:00] Targeted optional request: nothing claimable']


def base(script, name):
    return json.loads(subprocess.run([sys.executable, os.path.join(HERE, script), name], capture_output=True, text=True, check=True).stdout)


def jd(o):
    return json.dumps(o, separators=(',', ':'))


if n.startswith('08e-'):
    S = base('reloadscen.py', {'08e-http': '08e-noclaim', '08e-gate': '08e-noclaim'}.get(n, n))
    if n == '08e-http':
        S['stream'] = [BAD]
    elif n == '08e-gate':
        S['stream'] = [OK]
        S['tlog'] = [NOTHING]
elif n.startswith('08d-'):
    key = {'08d-http': '08d-pass'}.get(n, n)
    if n.startswith('08d-neg-'):
        key = '08d-open'
    S = base('tripscen.py', key)
    S['completed'] = 0 if n in ('08d-notrip',) or n.startswith('08d-neg') else 1
    if n == '08d-http':
        S['stream'] = [BAD]
    if n.startswith('08d-neg-'):
        acc = ['7001|ACCEPTED|accepted|||trip-aaa|Squin']
        S['agr'] = [acc, [acc[0].replace('ACCEPTED|accepted', 'COMPLETED|completed')] + acc] if n == '08d-neg-completed' else [acc]
        if n == '08d-neg-closed':
            S['fu'] = base('tripscen.py', '08d-pass')['fu']
elif n.startswith('11b-'):
    TID = 't1'
    fu0 = {'topic_id': TID, 'kind': 'personal_plan', 'status': 'open', 'ask_count': 0, 'not_before_gamets': 3600, 'expires_gamets': 600000}
    fu1 = dict(fu0, ask_count=1)

    def fu(d):
        return '201|social_followup|followup-v1:x:y:' + jd(d)
    c1 = '301|situated_remark_claim|' + jd({'actor_serial': 1, 'event_id': 'followup:%s:1' % TID})
    S = {'steps': [{'reply': 'Take care with that armor.', 'full': [['social_followup', 'followup-v1:x:y:' + jd(fu0)]]}],
         'fu': [[fu(fu0)], [fu(fu0)], [fu(fu0)], [fu(fu1)]],           # fu_pre, fu_c1b, fu_combat, fu_final
         'claim': [[], [], [c1]],                                       # claim_c1b, claim_c1a, claim_after
         'cstate': ['{"in_combat": true}', '{"in_combat": true}', '{"in_combat": false}'],   # combat_pre, combat, calm
         'combat_rows': 3, 'bored': 100}
    if n == '11b-claim-nosnap':
        S['claim'] = [[c1], [c1], [c1]]
        S['fu'] = [[fu(fu0)], [fu(fu1)], [fu(fu1)], [fu(fu1)]]
    elif n == '11b-claim-snap':
        S['claim'] = [[], [c1], [c1]]
        S['fu'] = [[fu(fu0)], [fu(fu0)], [fu(fu1)], [fu(fu1)]]
    elif n == '11b-notcombat':
        S['cstate'] = ['{"in_combat": false}'] * 3
        S['combat_rows'] = 0
    elif n == '11b-gone':
        S['cstate'] = ['ERROR: no character named: Cind [Hungry Bandit]'] * 3
    elif n == '11b-nocalm':
        S['cstate'] = ['{"in_combat": true}'] * 3
    elif n == '11b-http':
        S['stream'] = [BAD]
    elif n == '11b-noclaim-after':
        S['claim'] = [[], [], []]
        S['fu'] = [[fu(fu0)]] * 4
    elif n == '11b-notopic':
        S['fu'] = [[]]
        S['steps'] = [{'reply': 'Hm.', 'full': []}]
    elif n == '11b-spawnfail':
        S['spawn'] = 'ERROR: unknown template'
    elif n != '11b-pass':
        raise SystemExit('unknown scenario ' + n)
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
