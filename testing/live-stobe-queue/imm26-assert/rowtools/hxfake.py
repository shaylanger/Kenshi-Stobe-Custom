#!/usr/bin/env python3
"""hxfake.py <kind h|w|sql> <body>   OFFLINE lane simulator for hx-selftest.sh (hardening rows); delegates what it does not know to fakelane.py.
Scenario keys (env FAKE_SCEN json; own state FAKE_STATE+'.hx'): nsteps (fakelane steps, each replies `reply`), reply, pos {name-substring: "x,y,z"},
spawn_fail, spawn_names, roster [lines], extras_ids, nomove (give/transfer change nothing), seed ('' = no row inserted), tpl (rows to copy from),
starter_row, status (contract status), profile.  Never touches a game, ssh or DB."""
import json
import os
import re
import shlex
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.hx'
st = json.load(open(sp)) if os.path.isfile(sp) else {'inv': {}, 'ids': {}, 'spawn': 0, 'ext': 0, 'speaker': 'Cind'}
FULL = {'Cind': 'Cind [Hungry Bandit]', 'Shay': 'Shay [Nameless]', 'Malzin': 'Malzin [Drifters]', 'Thoke': 'Thoke [Drifters]'}
IDS = {'Cind': '#2529907200/2', 'Shay': '#1/1', 'Malzin': '#77/1', 'Thoke': '#88/1'}
IDS.update(st.get('idmap', {}))


def out(*lines):
    json.dump(st, open(sp, 'w'))
    print('\n'.join(lines))
    sys.exit(0)


def toks(cmd):
    line = [ln for ln in body.splitlines() if cmd in ln][-1]
    return shlex.split(line.split(cmd, 1)[1].replace('</dev/null', ' ').split('|')[0].replace('2>&1', ' '))


def first(n):
    return n.split(' [')[0].split()[0]


if kind == 'h':
    one = body.lstrip().startswith('stobe-auto chars')
    if one and 'sort -u' in body:        # hxd_extras: ids to move (first pass only)
        st['ext'] += 1
        out(*(scen.get('extras_ids', ['5/1']) if st['ext'] == 1 else []))
    if one and 'wc -l' in body:
        out(str(scen.get('extras_left', 0)))
    if one and 'cut -c1-80' in body:     # roster.txt
        out(*scen.get('roster', ['Shay #1/1 [Nameless] pos=0,0,0', 'Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=1,1,1', 'Vethra [Hungry Bandit] #5/1 [HNO] pos=2,2,2']))
    if 'stobe-auto spawn' in body:
        if scen.get('spawn_fail'):
            out('ERROR no such template')
        nm = (scen.get('spawn_names') or ['Vethra', 'Korin', 'Dalla'])[st['spawn']]
        st['spawn'] += 1
        st['ids'][f'#{4 + st["spawn"]}/1'] = nm
        st.setdefault('idmap', {})[nm] = f'#{4 + st["spawn"]}/1'
        out(f'spawned 1/1 Hungry Bandit: {nm} [Hungry Bandit] #{4 + st["spawn"]}/1 race=x')
    if 'stobe-auto where' in body:
        n = first(toks('stobe-auto where')[0])
        if n in scen.get('missing', []):
            out('ERROR not found')
        full = FULL.get(n, f'{n} [Hungry Bandit]')
        iid = IDS.get(n, '#9/1')
        st['ids'][iid] = n
        pos = next((v for k, v in scen.get('pos', {}).items() if k in n), '-48000.0,1500.0,2960.0')
        out(f'{full} {iid} [Traders Guild] pos={pos} dist=9.0')
    m = re.search(r'stobe-auto (inv|give|transfer) ', body)
    if m:
        t = toks('stobe-auto ' + m.group(1))
        who = first(t[0])
        if m.group(1) == 'inv':
            out(*[''.join(f'"name":"{i}","count":1 ' for i in st['inv'].get(who, []))])
        if not scen.get('nomove'):
            if m.group(1) == 'give':
                st['inv'].setdefault(who, []).append(t[1])
            else:
                st['inv'][who] = [i for i in st['inv'].get(who, []) if i.lower() != t[2].lower()]
                st['inv'].setdefault(t[1], []).append(t[2])
        out('ok')
    if 'stobe-auto money' in body:
        out('cats 100 -> 100', 'cats 50 -> 50')
    if 'stobe_say' in body:
        mm = re.search(r'stobe_say "?(#\d+/\d+)', body)
        st['speaker'] = st['ids'].get(mm.group(1), 'Cind') if mm else 'Cind'
        json.dump(st, open(sp, 'w'))
elif kind == 'sql':
    if 'returning rowid' in body:
        out(scen.get('seed', '321'))
    if body.startswith('select count(*) from eventlog where rowid<=') and 'hand_' in body:
        out(str(scen.get('tpl', 1)))
    if 'Initiated attack' in body and body.startswith('select data'):
        out(scen.get('starter_row', 'Malzin: Initiated attack on Korin'))
    if body.startswith('select contract_id from stobe_social_contract'):
        out('c13')
    if body.startswith("select status||' '||left(term_state"):
        out('ACCEPTED GIVE_ITEM x VERIFIED')
    if body.startswith('select status from stobe_social_contract'):
        out(scen.get('status', 'COMPLETED'))
    if body.startswith('select max(gamets)'):
        out('5000')
    if body.startswith('select contract_id,status'):
        out('c13|ACCEPTED|{}')
    if 'from core_npc c left join core_npc_master' in body:
        out(scen.get('profile', 'Proud and stubborn | raised in the dust | wants a farm | blunt | bandit'))
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fakelane.py'), kind, body], capture_output=True, text=True)
o = r.stdout
if kind == 'h' and 'ACTION_EXEC' in body and 'tail -n +' in body:
    o = o.replace('SAY [Cind]', f'SAY [{st["speaker"]}]')
sys.stdout.write(o)
