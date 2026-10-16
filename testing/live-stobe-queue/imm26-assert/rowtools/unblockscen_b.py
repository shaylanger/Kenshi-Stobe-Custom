#!/usr/bin/env python3
"""unblockscen_b.py <name>   scenario JSON for unblockfake_b.py (unblock_b_selftest.sh). Bases come from tripscen.py (13-c), reloadscen_b.py (10-e), reloadscen.py (27-a).
Names: 13c-pass 13c-neg-pass 13c-uid 13c-unqualified ub13c-failed ub13c-failed-neg | 10e-restart-pass 10e-restart-samesession 10e-restart-launchfail 10e-restart-scopechanged 10e-restart-epochdown 10e-restart-epochdown-noseq 10e-inproc-same
       27a-pass 27a-formfallback 27a-allforms-fail 27a-lost 27a-nodll 27a-noorder 27a-ctrl-approaches 27a-post-standoff-edge"""
import json
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]


def base(script, name):
    return json.loads(subprocess.run([sys.executable, os.path.join(here, script), name], capture_output=True, text=True, check=True).stdout)


def rearr(S, new_session=True):
    pre, ev, post = [json.loads(x) for x in S['probe']]
    live = ev['live'] if new_session else pre['scope']
    ev = dict(ev, live=live)
    S['probe'] = [json.dumps(pre), json.dumps(dict(pre, scope=live)), json.dumps(ev)]   # pre, poll(scope), eval
    return S


if n in ('13c-pass', '13c-neg-pass', '13c-uid', '13c-unqualified'):
    S = base('tripscen.py', n)
elif n in ('ub13c-failed', 'ub13c-failed-neg'):
    S = base('tripscen.py', '13c-pass')
    S['agr'] = [S['agr'][0], ['7009|FAILED|failed|native_order_ended_before_goal|true|trip-aaa|Squin'] + S['agr'][0]]
    S['failed_count'] = 1; S['completed'] = 0; S['sx'] = [[], []]; S['award'] = []
elif n.startswith('10e-restart') or n == '10e-inproc-same':
    S = base('reloadscen_b.py', '10e-pass')
    if n == '10e-restart-pass':
        S = rearr(S)
    elif n == '10e-restart-samesession':
        S = base('reloadscen_b.py', '10e-samesession'); S = rearr(S, new_session=False)
    elif n == '10e-restart-launchfail':
        S = rearr(S); S['launch_fail'] = True
    elif n in ('10e-restart-epochdown', '10e-restart-epochdown-noseq'):   # imm26 sfC: REAL restart, native epoch 17 -> 2; load_seq 4 -> 5 (server) or absent
        S = rearr(S); pre, poll, ev = [json.loads(x) for x in S['probe']]
        seq = n == '10e-restart-epochdown'
        pre['scope'] = dict(pre['scope'], timeline_epoch='17', **({'load_seq': '4'} if seq else {}))
        ev['live'] = dict(ev['live'], timeline_epoch='2', **({'load_seq': '5'} if seq else {}))
        S['probe'] = [json.dumps(pre), json.dumps(dict(pre, scope=ev['live'])), json.dumps(ev)]
    elif n == '10e-restart-scopechanged':
        S = base('reloadscen_b.py', '10e-scopechanged'); S = rearr(S)
    # 10e-inproc-same: original order pre, eval, post with the same session
    if n == '10e-inproc-same':
        S = base('reloadscen_b.py', '10e-samesession')
elif n.startswith('27a-'):
    HAS1 = 'Cind [Hungry Bandit] has_contract=1 package=Bodyguard hours_left=%s'
    if n in ('27a-pass', '27a-formfallback', '27a-lost'):
        S = base('reloadscen.py', '27a-pass' if n != '27a-lost' else '27a-lost')
        err = ['ERROR: no character named: status']
        if n == '27a-formfallback':
            S['bgforms'] = [err, [HAS1 % '24.0'], err, [HAS1 % '23.0']]
        elif n == '27a-lost':
            S['bgforms'] = [[HAS1 % '24.0'], ['Cind [Hungry Bandit] has_contract=0']]
        else:
            S['bgforms'] = [[HAS1 % '24.0'], [HAS1 % '23.0']]
    elif n in ('27a-ctrl-approaches', '27a-post-standoff-edge'):   # 27A-FIX
        S = base('reloadscen.py', n); S['bgforms'] = [[HAS1 % '24.0'], [HAS1 % '23.0']]
    elif n == '27a-allforms-fail':
        S = base('reloadscen.py', '27a-statuserr'); S['bgforms'] = [['ERROR: no character named: status']]
    elif n == '27a-nodll':
        S = base('reloadscen.py', '27a-pass'); S['gate'] = 'ERROR: unknown command: contract-bodyguard'
    elif n == '27a-noorder':
        S = base('reloadscen.py', '27a-noorder'); S['bgforms'] = [['Cind [Hungry Bandit] has_contract=0']]
    else:
        sys.exit('unknown scenario ' + n)
else:
    sys.exit('unknown scenario ' + n)
print(json.dumps(S))
