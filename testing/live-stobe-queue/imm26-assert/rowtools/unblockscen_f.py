#!/usr/bin/env python3
"""unblockscen_f.py <name>   scenario JSON for unblockfake_f.py (unblock_f_selftest.sh); bases from tripscen.py 13c-* (via unblockscen_b.py).
Names: f13c-pass f13c-timeout-old-dll f13c-timeout-native f13c-notreconciled f13c-failed-defect | f13cneg-completed-pass f13cneg-failed-pass f13cneg-failed-row f13cneg-notreconciled f13cneg-failed-defect"""
import json
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]
AID = 'trip-aaa'


def base(name):
    return json.loads(subprocess.run([sys.executable, os.path.join(here, 'unblockscen_b.py'), name], capture_output=True, text=True, check=True).stdout)


def agr(rowid, status, phase='', reason='', rel='', dest='Squin'):
    return f'{rowid}|{status}|{phase}|{reason}|{rel}|{AID}|{dest}'


ACC = [agr(7001, 'ACCEPTED', 'accepted')]
START = '[10:00:00] NATIVE_TRAVEL_START target=requested_reachable participation_bound=1 goal=-62380,330,16250'
FINISH = '[10:01:10] NATIVE_TRAVEL_FINISH phase=completed reason=measured_route_arrival planar=11.2'
PHASE = '[10:01:10] NATIVE_TRAVEL phase=completed arrived=1 participation_qualified=1'
PHASEF = '[10:01:10] NATIVE_TRAVEL phase=failed arrived=0 participation_qualified=0 reason=agreement_expired'
OBS = '[10:01:08] NATIVE_TRAVEL_OBS planar=12.0 moving=1'
EXTRA = [{'reply': 'Good walk.'}, {'reply': 'Still here.'}]


def mk(sc, term, nend=True, dump=None, agrs=None, sx=None, award=None):
    S = base(sc)
    S['steps'] = S['steps'] + EXTRA
    S['term_seq'] = term
    S['nend'] = [FINISH] if nend else []
    S['ndump'] = dump if dump is not None else ([START, FINISH, PHASE] if nend else [])
    S['nobs'] = [OBS] if (dump is None and nend) else []
    if agrs is not None:
        S['agr'] = agrs
    if sx is not None:
        S['sx'] = sx
    if award is not None:
        S['award'] = award
    return S


if n == 'f13c-pass':
    S = mk('13c-pass', ['', 'C'])
elif n == 'f13c-timeout-old-dll':
    S = mk('13c-pass', [''], nend=False, dump=[])
elif n == 'f13c-timeout-native':
    S = mk('13c-pass', [''], nend=False, dump=[START])
elif n == 'f13c-notreconciled':
    S = mk('13c-pass', [''], agrs=[ACC, ACC], sx=[[], []], award=[])
elif n == 'f13c-failed-defect':
    S = mk('13c-pass', ['', 'F'], dump=[START, '[10:01:10] NATIVE_TRAVEL_ORDER_ENDED planar=150'], agrs=[ACC, [agr(7009, 'FAILED', 'failed', 'native_order_ended_before_goal', 'false')] + ACC], sx=[[], []], award=[])
elif n == 'f13cneg-completed-pass':
    S = mk('13c-neg-pass', ['', 'C'])
elif n == 'f13cneg-failed-pass':
    S = mk('13c-neg-pass', ['', 'F'], dump=[START, PHASEF], agrs=[ACC, [agr(7009, 'FAILED', 'failed', 'agreement_expired', 'false')] + ACC], sx=[[], []], award=[])
elif n == 'f13cneg-failed-row':    # a sharedexp row appears although the trip did not complete
    S = mk('13c-neg-pass', ['', 'F'], dump=[START, PHASEF], agrs=[ACC, [agr(7009, 'FAILED', 'failed', 'agreement_expired', 'false')] + ACC],
           sx=[[], ['sharedexp:0123abcd|kept_promise|3|true']], award=[])
elif n == 'f13cneg-notreconciled':
    S = mk('13c-neg-pass', [''], agrs=[ACC, ACC], sx=[[], []], award=[])
elif n == 'f13cneg-failed-defect':
    S = mk('13c-neg-pass', ['', 'F'], dump=[START, '[10:01:10] NATIVE_TRAVEL_ORDER_ENDED planar=150'], agrs=[ACC, [agr(7009, 'FAILED', 'failed', 'native_order_ended_before_goal', 'false')] + ACC], sx=[[], []], award=[])
else:
    sys.exit('unknown scenario ' + n)
print(json.dumps(S))
