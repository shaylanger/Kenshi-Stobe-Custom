#!/usr/bin/env python3
"""unblockscen_23a2.py <name>   scenario JSON for unblockfake_23a2.py (unblock_23a2_selftest.sh). Base = unblockscen_sfk.py sfk23-pass / sfk23-failed (tripscen 23a-pass steps).
Names: a2-pass a2-hub-pass a2-reaccept a2-reaccept3 a2-lead a2-proposed-forever a2-notanchored a2-ypre a2-cleared a2-nostart a2-obs0 a2-late-drop a2-air a2-failed"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
n = sys.argv[1]


def base(name):
    return json.loads(subprocess.run([sys.executable, os.path.join(HERE, 'unblockscen_sfk.py'), name], capture_output=True, text=True, check=True).stdout)


S = base('sfk23-failed' if n == 'a2-failed' else 'sfk23-pass')
st = S['steps']      # [s1 propose, s2 accept(+OWNED_TRAVEL log), s3 arrival, s4 following]
NOACC = {'reply': "I'm already headed that way."}
S.update(start='quiet', native='ok', accepted_after_say=2)
if n in ('a2-pass', 'a2-failed'):
    pass
elif n == 'a2-hub-pass':
    S['start'] = 'hub'
elif n == 'a2-reaccept':      # s2 leaves the agreement PROPOSED (op35 a3), s2c accepts
    S['steps'] = [st[0], NOACC, st[1]] + st[2:]; S['accepted_after_say'] = 3
elif n == 'a2-reaccept3':     # accepted only by the third attempt (s2c)
    S['steps'] = [st[0], NOACC, NOACC, st[1]] + st[2:]; S['accepted_after_say'] = 4
elif n == 'a2-lead':          # accepted but the native start only follows "Lead the way." (s2b)
    S['steps'] = [st[0], dict(st[1], log=[]), st[1]] + st[2:]; S['native'] = 'lead'
elif n == 'a2-proposed-forever':
    S['steps'] = [st[0], NOACC, NOACC, NOACC]; S['accepted_after_say'] = 0
elif n == 'a2-notanchored':
    S['tp_ignored'] = True
elif n == 'a2-ypre':          # anchored, but Cind's height is off right before the stage (call 3 = the pre-stage where)
    S['start'] = 'hub'; S['wcall_pos'] = {'3': '-50970.0,1533.0,2965.0'}
elif n == 'a2-cleared':       # op35 a1: START then ORDER_ENDED 0.4 s later
    S['native'] = 'cleared'
elif n == 'a2-nostart':
    S['native'] = 'none'; S['steps'] = [st[0], dict(st[1], log=[]), NOACC] + st[2:]
elif n == 'a2-obs0':
    S['native'] = 'obs0'
elif n == 'a2-late-drop':     # alive after the accept, cleared before the stage teleport
    S['native'] = 'drops_late'
elif n == 'a2-air':           # op35 a2: the stage teleport leaves Cind at y=1570.8
    S['stage_air'] = True
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(S))
