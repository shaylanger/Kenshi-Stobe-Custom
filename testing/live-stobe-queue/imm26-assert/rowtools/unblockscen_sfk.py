#!/usr/bin/env python3
"""unblockscen_sfk.py <name>   scenario JSON for unblockfake_sfk.py (unblock_sfk_selftest.sh). 23-a bases come from tripscen.py 23a-* (+ the native-walk keys of unblockscen_f.py);
11-b bases from unblockscen_a.py 11b-pass with the v2 fu sequence (fu_pre, fu_pre after the not_before edit, fu_c1b, fu_combat, fu_final).
Names: sfk23-pass sfk23-destpoint sfk23-ko-recovers sfk23-ko-attacked sfk23-timeout sfk23-failed
       sfk11-pass sfk11-claim-nosnap sfk11-crowded sfk11-spawn-noserial sfk11-calm-wrong-enemy sfk11-fight-fail sfk11-update-fail sfk11-nocalm sfk11-recombat"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]
START = '[10:00:00] NATIVE_TRAVEL_START target=requested_reachable participation_bound=1 goal=-62461,328.8,16346.8'
FINISH = '[10:01:10] NATIVE_TRAVEL_FINISH phase=completed reason=measured_route_arrival planar=11.2'


def run(script, name):
    return json.loads(subprocess.run([sys.executable, os.path.join(HERE, script), name], capture_output=True, text=True, check=True).stdout)


def jd(o):
    return json.dumps(o, separators=(',', ':'))


if n.startswith('sfk23-'):
    S = run('tripscen.py', '23a-fail' if n == 'sfk23-failed' else '23a-pass')
    S['chain'] = 'f'
    S['term_seq'] = ['F', 'F'] if n == 'sfk23-failed' else ([''] if n == 'sfk23-timeout' else ['', 'C'])
    S['nend'] = [] if n in ('sfk23-timeout', 'sfk23-failed') else [FINISH]
    S['ndump'] = [] if n == 'sfk23-timeout' else [START, FINISH]
    S['nobs'] = []
    if n == 'sfk23-destpoint':
        S['destpoint'] = '-100 200 -300'
    elif n == 'sfk23-ko-recovers':
        S['ko_counts'] = [2, 2]
    elif n == 'sfk23-ko-attacked':
        S['ko_counts'] = [2, 5]
    elif n not in ('sfk23-pass', 'sfk23-timeout', 'sfk23-failed'):
        raise SystemExit('unknown scenario ' + n)
elif n.startswith('sfk11-'):
    S = run('unblockscen_a.py', '11b-pass')
    TID = 't1'
    fu0 = {'topic_id': TID, 'kind': 'personal_plan', 'status': 'open', 'ask_count': 0, 'not_before_gamets': 3600, 'expires_gamets': 600000}
    fue = dict(fu0, not_before_gamets=1)
    fu1 = dict(fue, ask_count=1)

    def fu(d):
        return '201|social_followup|followup-v1:x:y:' + jd(d)
    S['fu'] = [[fu(fu0)], [fu(fue)], [fu(fue)], [fu(fue)], [fu(fu1)]]
    c1 = '301|situated_remark_claim|' + jd({'actor_serial': 1, 'event_id': 'followup:%s:1' % TID})
    if n == 'sfk11-claim-nosnap':
        S['claim'] = [[c1], [c1], [c1]]
        S['fu'] = [[fu(fu0)], [fu(fue)], [fu(fu1)], [fu(fu1)], [fu(fu1)]]
    elif n == 'sfk11-crowded':
        S['crowded'] = True
    elif n == 'sfk11-spawn-noserial':
        S['spawn'] = 'spawned 1/1 Hungry Bandit: Hungry Bandit race=Shek'
    elif n == 'sfk11-calm-wrong-enemy':
        S['calm_wrong'] = True
    elif n == 'sfk11-fight-fail':
        S['fight_fail'] = True
    elif n == 'sfk11-update-fail':
        S['update_fail'] = True
        S['fu'] = [[fu(fu0)]] * 5
    elif n == 'sfk11-nocalm':
        S['cstate'] = ['{"in_combat": true}'] * 3
    elif n == 'sfk11-recombat':
        S['cstate'] = ['{"in_combat": true}', '{"in_combat": true}', '{"in_combat": false}', '{"in_combat": true}']
    elif n != 'sfk11-pass':
        raise SystemExit('unknown scenario ' + n)
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
