#!/usr/bin/env python3
"""sfrscen.py <name>   scenario JSON for sfrfake.py (sfr_selftest.sh, sfrrun.sh --dry). Bases: 22-b from unblockscen_sfk.py sfk23-pass (real-walk trip: chain 'f'), 20-a from tripscen.py
20a-pass / 20a-fail / 20a-s4b-pass, 23-b a bare "Follow me." turn.
Names: sfr23-pass sfr23-noexp sfr23-early sfr23-stall sfr23-ini-missing sfr23-ini-stuck sfr23-ticks-after sfr23-nofollow
       sfr22-pass sfr22-second-tick sfr22-noevent sfr22-two-claims sfr22-silent-speaks sfr22-timeout sfr22-http
       sfr20-pass sfr20-fail sfr20-s4b-pass sfr20-stuck sfr20-far-fail sfr20-far-pass"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]


def run(script, name):
    return json.loads(subprocess.run([sys.executable, os.path.join(HERE, script), name], capture_output=True, text=True, check=True).stdout)


def jd(o):
    return json.dumps(o, separators=(',', ':'))


SER = 2529907200
EVT = '501|situated_event|' + jd({'event_id': 'arrival:trip-aaa', 'kind': 'arrival', 'actor_serial': SER})
CLM1 = '502|situated_remark_claim|' + jd({'actor_serial': SER, 'event_id': 'arrival:trip-aaa', 'kind': 'arrival'})
CLM2 = '503|situated_remark_claim|' + jd({'actor_serial': SER, 'event_id': 'arrival:trip-aaa', 'kind': 'arrival'})
CLAIMED = '[2026-10-16 12:00:00] Targeted optional request: situated remark claimed (arrival)'
NOTHING = '[2026-10-16 12:00:30] Targeted optional request: nothing claimable'

if n.startswith('sfr23-'):
    S = {'steps': [{'reply': 'Right, I follow you.'}]}
    if n == 'sfr23-noexp':
        S['no_expiry'] = True
    elif n == 'sfr23-early':
        S['early_expiry'] = True
    elif n == 'sfr23-stall':
        S['stall'] = True
    elif n == 'sfr23-ini-missing':
        S['ini_missing'] = True
    elif n == 'sfr23-ini-stuck':
        S['ini_stuck'] = True
    elif n == 'sfr23-ticks-after':
        S['ticks_after_expiry'] = 3
    elif n == 'sfr23-nofollow':
        S['no_follow'] = True
    elif n != 'sfr23-pass':
        raise SystemExit('unknown scenario ' + n)
elif n.startswith('sfr22-'):
    S = run('unblockscen_sfk.py', 'sfk23-timeout' if n == 'sfr22-timeout' else 'sfk23-pass')
    S['sit_by_tick'] = [[EVT, CLM1]]
    S['tlog'] = [[CLAIMED], [NOTHING]]
    if n == 'sfr22-second-tick':      # tick 1: nothing in the log yet (stale snapshot), tick 2 claims, the silent tick says nothing
        S['sit_by_tick'] = [[], [EVT, CLM1]]
        S['tlog'] = [[NOTHING], [CLAIMED], [NOTHING]]
    elif n == 'sfr22-noevent':
        S['sit_by_tick'] = [[]]
        S['tlog'] = [[NOTHING]]
    elif n == 'sfr22-two-claims':
        S['sit_by_tick'] = [[EVT, CLM1, CLM2]]
    elif n == 'sfr22-silent-speaks':
        S['sit_by_tick'] = [[EVT, CLM1], [EVT, CLM1, CLM2]]
        S['tlog'] = [[CLAIMED], [CLAIMED]]
    elif n == 'sfr22-http':
        S['stream'] = [['', 'HTTP=000']]
    elif n not in ('sfr22-pass', 'sfr22-timeout'):
        raise SystemExit('unknown scenario ' + n)
elif n.startswith('sfr20-'):
    S = run('tripscen.py', {'sfr20-fail': '20a-fail', 'sfr20-far-fail': '20a-fail', 'sfr20-s4b-pass': '20a-s4b-pass'}.get(n, '20a-pass'))
    S['drift'] = 2           # after the accept turn the NPC walks away (the real 5090-i3/4080 behaviour: 81 -> 637 u)
    if n == 'sfr20-stuck':
        S['stuck'] = True
    elif n == 'sfr20-far-fail':   # placement passed but the NPC was outside TalkRadius when the turn was resolved
        S['far_at_say'] = 200.0
    elif n == 'sfr20-far-pass':
        S['far_at_say'] = 200.0
    elif n not in ('sfr20-pass', 'sfr20-fail', 'sfr20-s4b-pass'):
        raise SystemExit('unknown scenario ' + n)
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
