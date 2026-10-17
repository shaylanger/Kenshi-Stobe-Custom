#!/usr/bin/env python3
"""unblockfake_sffb4.py <kind h|w|sql> <body>   OFFLINE lane simulator for unblock_sffb4_selftest.sh (row 11-b recipe v4). Answers the sffb4-tagged calls and delegates everything else to
unblockfake_sffb.py (-> unblockfake_sfk.py -> unblockfake_a.py -> ...). Extra scenario keys (env FAKE_SCEN; counters in FAKE_STATE + '.sffb4'; every list = one answer per call, the last repeats):
  combat_age ('<type>|<age s>' of the newest combat/combatend row, per `sffb4:age` call; '' = no row)  evage ('<age s>|<kind>' of the newest situated_event per `sffb4:evage` call)
  claimage (age s of the newest situated_remark_claim per `sffb4:claimage` call)  scene_seq (list of bool per `sfk:scene` call: strays listed)  unprotect_fail (bool)  shay_missing (bool: `where Shay` errors)
Tags: `# sffb4:unprotect` `/* sffb4:age */` `/* sffb4:evage */` `/* sffb4:claimage */`. Never touches a game, ssh or DB."""
import json
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sffb4'
st = json.load(open(sp)) if os.path.isfile(sp) else {}
here = os.path.dirname(os.path.abspath(__file__))


def pick(key, default):
    seq = scen.get(key, default)
    i = st.get(key, 0)
    st[key] = i + 1
    json.dump(st, open(sp, 'w'))
    return seq[min(i, len(seq) - 1)]


def out(lines):
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


if kind == 'h':
    if 'sffb4:unprotect' in body:
        out(['ERROR: no character named' if scen.get('unprotect_fail') else 'Hungry Bandit protect=off protected=1'])
    if 'sfk:scene' in body and 'scene_seq' in scen:
        out(['Felk #3229492224/6 [Holy Nation Outlaws] pos=2,2,2 dist=35.2 race=Greenlander'] if pick('scene_seq', [False]) else [])
    if 'stobe-auto where Shay </dev/null' in body and scen.get('shay_missing'):
        out(['ERROR: no character named: Shay'])
elif kind == 'sql':
    if 'sffb4:age' in body:
        out([pick('combat_age', ['combatend|60'])])
    if 'sffb4:evage' in body:
        out([pick('evage', ['9999|-'])])
    if 'sffb4:claimage' in body:
        out([str(pick('claimage', [9999]))])
r = subprocess.run([sys.executable, os.path.join(here, 'unblockfake_sffb.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
