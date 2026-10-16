#!/usr/bin/env python3
"""hxfake_02bd.py <kind h|w|sql> <body>   OFFLINE lane simulator for hx-selftest_02bd.sh: hxfake_a.py plus the server-log grep of rd_02bx (IMM26_PRINCIPLE_VOICED lines, count from env
FAKE_VOICED, default 4) and `wc -l` of the server log.  Everything else is delegated."""
import os
import subprocess
import sys

kind, body = sys.argv[1], sys.argv[2]
if kind == 'w' and 'IMM26_PRINCIPLE_VOICED' in body:
    for i in range(int(os.environ.get('FAKE_VOICED', '4'))):
        print('[2026-10-16 00:49:%02d] [INFO] IMM26_PRINCIPLE_VOICED: NPC stated a stance | {"npc":"Cind [Hungry Bandit]","topic":"slavery"}' % i)
    sys.exit(0)
if kind == 'w' and 'wc -l <' in body and 'stobeserver.log' in body:
    print('120')
    sys.exit(0)
sp = os.environ['FAKE_STATE'] + '.b'
flag = os.path.isfile(sp)
if kind == 'sql' and 'personality||' in body:       # principle sentence appended: the profile text then carries it (until replace(personality...) removes it again)
    import json
    import re
    base_txt = json.load(open(os.environ['FAKE_SCEN'])).get('profile', 'Proud and stubborn | raised in the dust | wants a farm | blunt | bandit')
    m = re.search(r"personality\|\|'([^']*)'", body)
    if m and m.group(1).strip() not in base_txt:     # a sentence already in the profile text changes nothing (the real UPDATE has the same effect via its NOT LIKE guard)
        open(sp, 'w').write('1')
        flag = True
if kind == 'sql' and 'replace(personality' in body:
    if flag:
        os.remove(sp)
    flag = False
r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hxfake_a.py'), kind, body], capture_output=True, text=True)
sys.stdout.write(r.stdout)
sys.stderr.write(r.stderr)
if kind == 'sql' and 'from core_npc c left join core_npc_master' in body and flag:
    sys.stdout.write(' | WITH-PRINCIPLE-SENTENCE' + chr(10))
