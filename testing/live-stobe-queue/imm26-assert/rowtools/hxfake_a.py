#!/usr/bin/env python3
"""hxfake_a.py <kind h|w|sql> <body>   OFFLINE lane simulator for hxa-selftest.sh (hardening rows 01-bx 01-cx 02-cx).  Answers what those rows add (H-AFF set/read, faction
profile + faction_relation_state, stranger list `chars 3000`, stobe_state in_combat, imm26_npc_principle rows, stobe_npcinfo, profile text) and delegates everything else to
hxfake.py (-> fakelane.py).  Own state: FAKE_STATE + '.hxa'.  Scenario keys (env FAKE_SCEN json) on top of hxfake's:
  chars [names]            names printed by `chars 3000` (default: Shay, Cind, Rethar Dax, Bob Smith)       fac {name-substring: faction}  (default '<first word> Faction')
  rel {faction: value}     directed relation faction->Nameless (default 0)                                    entries [name-substring]  those strangers already have a Shay entry (aff -30)
  combat [name-substring]  stobe_state of those names says in_combat true                                     norelwrite  relation UPDATE/INSERT has no effect
  noprinciple              the imm26_npc_principle table stays empty                                          profile_rewrite  the profile text changes after the first reply
  panel text               info panel text (default mentions slavery)                                          panel_err  stobe_npcinfo answers `ERROR unknown command`"""
import json
import os
import re
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
scen = json.load(open(os.environ['FAKE_SCEN']))
sp = os.environ['FAKE_STATE'] + '.hxa'
st = json.load(open(sp)) if os.path.isfile(sp) else {'aff': {}, 'rel': {}, 'prin': False, 'says': 0, 'prof': 0}


def out(*lines):
    json.dump(st, open(sp, 'w'))
    print('\n'.join(lines))
    sys.exit(0)


def fac_of(name):
    for k, v in scen.get('fac', {}).items():
        if k in name:
            return v
    return name.split()[0] + ' Faction'


if kind == 'w' and 'haff.php' in body:
    m = re.search(r"haff\.php '([^']*)' '([^']*)' (\S+) (\S+)", body)
    if m:
        npc, v, typ = m.group(1), m.group(3), m.group(4)
        if typ != 'read':
            st['aff'][npc] = int(v)
        ent = next((e for e in scen.get('entries', []) if e in npc), None)
        aff = st['aff'].get(npc, -30 if ent else None)
        after = '[]' if aff is None else '[{"Shay":{"aff":%d,"type":"platonic"}}]' % aff
        out(json.dumps({'npc': npc, 'counterpart': 'Shay', 'before': []})[:-1] + ', "after": ' + after + '}')
if kind == 'sql':
    if body.startswith("select trim(regexp_replace(coalesce(faction,'')"):
        nm = re.search(r"name='([^']*)'", body).group(1)
        out('Nameless' if nm == 'Shay' else fac_of(nm))
    if body.startswith('select relation from faction_relation_state'):
        src = re.search(r"lower\(source_name\)=lower\('([^']*)'\)", body).group(1)
        v = st['rel'].get(src, scen.get('rel', {}).get(src))
        out('' if v is None else str(v))
    if body.startswith('update faction_relation_state set relation='):
        v = re.search(r'relation=(-?[0-9.]+)', body).group(1)
        src = re.search(r"lower\(source_name\)=lower\('([^']*)'\)", body).group(1)
        if not scen.get('norelwrite'):
            st['rel'][src] = float(v)
        out('UPDATE 1')
    if body.startswith('delete from imm26_npc_principle'):
        st['prin'] = False
        out('DELETE 1')
    if body.startswith('select npc_name,topic,stance,strength,source from imm26_npc_principle'):
        nm = re.search(r"npc_name='([^']*)'", body).group(1)
        out(f'{nm}|slavery|opposed|firm|profile' if (st['prin'] and 'Cind' in nm) else '')
    if body.startswith('select * from imm26_npc_principle'):
        nm = re.search(r"npc_name='([^']*)'", body).group(1)
        out(f'7|k:{nm}|{nm}|slavery|opposed|firm|profile|ev|h|1|2|0|0' if (st['prin'] and 'Cind' in nm) else '')
    if 'from core_npc c left join core_npc_master' in body:
        st['prof'] += 1
        base_txt = scen.get('profile', 'Proud and stubborn | raised in the dust | wants a farm | blunt | bandit')
        if scen.get('profile_rewrite') and st['says'] >= 2:
            base_txt += ' REWRITTEN'
        out(base_txt)
if kind == 'h':
    if 'stobe-auto chars 3000' in body:
        names = scen.get('chars', ['Shay', 'Cind [Hungry Bandit]', 'Rethar Dax', 'Bob Smith'])
        out(*sorted(set(names)))   # the row's sed pipeline is not executed by the fake: its output (one name per line) is what the row sees
    if 'stobe-auto stobe_state' in body:
        nm = re.search(r"stobe_state '?([^'\n]*?)'? </dev/null", body)
        n = nm.group(1) if nm else ''
        if any(c in n for c in scen.get('combat', [])):
            out('{"in_combat": true}')
        out('{"in_combat": false}')
    if 'stobe_npcinfo read' in body:
        out('ERROR unknown command' if scen.get('panel_err') else scen.get('panel', "NPC INFO | Cind [Hungry Bandit] | WHAT YOU'VE LEARNED: she will not take part in slavery"))
    if 'stobe_npcinfo' in body:
        out('ok')
    if 'stobe_say' in body:
        st['says'] += 1
        mm = re.search(r'captive', body)
        if mm and not scen.get('noprinciple'):
            st['prin'] = True
        json.dump(st, open(sp, 'w'))
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hxfake.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
sys.stderr.write(r.stderr)
