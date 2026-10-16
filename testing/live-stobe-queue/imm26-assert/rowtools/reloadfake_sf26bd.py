#!/usr/bin/env python3
"""reloadfake_sf26bd.py <kind h|w|sql> <body>   OFFLINE lane simulator for reload-sf26bd-selftest.sh: layered over reloadfake_sfi.py. Adds: name-aware `stobe-auto where <npc>`
(Malzin / Cind; dist 8, or 288.6 while far), `teleport '<npc>' Shay` answers `teleported: <npc> #... [Nameless] ...` (sb_wrong_tp: names Cind instead), the stobe.log
"CHAT: dispatched inputtext ... people=[...]" lines. Scenario keys (added by reloadscen_sf26bd.py): sb_people (list per dispatched call of lists of names; the last repeats),
sb_no_dispatch (no such line at all), sb_far_after_load (the NPC is 288.6 u away after `stobe-auto load` until she is teleported to Shay), sb_wrong_tp. Never touches a game, ssh or DB."""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.sb'
st = json.load(open(sp)) if os.path.isfile(sp) else {'far': False, 'disp': 0}


def save():
    json.dump(st, open(sp, 'w'))


def emit(lines):
    save()
    if lines:
        print('\n'.join(lines))
    sys.exit(0)


if kind == 'h':
    if 'stobe-auto load ' in body and scen.get('sb_far_after_load'):
        st['far'] = True
        save()
    if 'CHAT: dispatched inputtext' in body:
        if scen.get('sb_no_dispatch'):
            emit([])
        seq = scen.get('sb_people', [['Shay|971557632', 'Malzin|2740478464']])
        p = seq[min(st['disp'], len(seq) - 1)]
        st['disp'] += 1
        emit(['[2026-10-16 12:20:12.998] [Stobe] CHAT: dispatched inputtext event to StobeServer stream endpoint. people=[%s]' % ','.join('"%s"' % x for x in p)])
    m = re.search(r"teleport '([^']*)' Shay", body)
    if m:
        st['far'] = False
        name = 'Cind' if scen.get('sb_wrong_tp') else m.group(1).split(' [')[0]
        emit(['teleported: %s #2740478464/2 [Nameless] pos=-49422.0,1661.0,3643.0 dist=8.0 moved=1 off_target=0.0 method=teleport' % name])
    m = re.search(r"stobe-auto where '?([^'\n]+?)'? </dev/null", body)
    if m and m.group(1) in ('Malzin', 'Cind') or (m and m.group(1).startswith(('Malzin', 'Cind'))):
        n = m.group(1).split(' [')[0]
        emit(['%s #2740478464/2 [Nameless] pos=-49422.0,1661.0,3643.0 dist=%s' % (n, '288.6' if st['far'] else '8.0')])
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'reloadfake_sfi.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
