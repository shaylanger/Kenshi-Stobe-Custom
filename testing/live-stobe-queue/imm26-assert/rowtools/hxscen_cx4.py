#!/usr/bin/env python3
"""hxscen_cx4.py <name>   scenario JSON for hx-selftest_cx4.sh: everything of hxscen_cx3.py plus
  i3replies : the REAL replies of the i3 run (E1 E3 empty-roster uncertainty, N2 'If you meant just us, no') and the H sleeper line of a KO'd NPC: must PASS with assert_principle_cx4.py
  i3moving  : same replies, but the H prompt still says 'doing:moving' (the v3 scene defect): must still FAIL roster_has_sleeper (the check is not weakened)
  justus    : N2 replies 'Yes, it is just us.' (a real alone claim with 4 NPCs visible): must FAIL
  yesalone  : E2 replies 'Yes, we are completely alone here.': must FAIL (checked with the cx4 assert)
  nohedge   : E1 replies 'Sure, it is quiet.' (no uncertainty at all): must FAIL
  kofail    : stobe_state keeps answering unconscious:false (hxfake_cx4.py): the H gate must SETUP-FAIL
  savemissing : the base save folder does not exist (hxfake_cx4.py answers SAVE-MISSING)"""
import json
import os
import subprocess
import sys

n = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
extra = ('i3replies', 'i3moving', 'justus', 'yesalone', 'nohedge', 'kofail', 'savemissing')
s = json.loads(subprocess.run([sys.executable, os.path.join(here, 'hxscen_cx3.py'), 'base' if n in extra else n], capture_output=True, text=True, check=True).stdout)
E1 = 'No, we are not. I saw Sela and Sythna put you on the ground earlier today, and I have no eyes on who is around right now. If you want to speak plainly, keep your voice down and stay close to me.'
E3 = 'I cannot promise that. I have no eyes on who is around right now, and I am not going to tell you a thing is private when I cannot see it. Keep your voice low and stay close to me.'
N2 = 'Brannoc, Tessik, Valo - all three still within sight, moving about. If you meant just us, no. If you meant nobody at all, also no.'
KO = 'Dorn Vale (female) | doing:unconscious (knocked out, cannot talk) | condition:- Blood: In good health'


def setp(i, line):
    s['steps'][i]['prompt'] = s['steps'][i]['prompt'].replace('Dorn Vale | asleep on the ground, not visible as awake', line)


if n in ('i3replies', 'i3moving'):
    s['steps'][0]['reply'] = E1
    s['steps'][2]['reply'] = E3
    s['steps'][7]['reply'] = N2
    for i in (3, 4, 5):
        setp(i, KO if n == 'i3replies' else 'Dorn Vale (female) | doing:moving | condition:- Blood: In good health')
elif n == 'justus':
    s['steps'][7]['reply'] = 'Yes, it is just us.'
elif n == 'yesalone':
    s['steps'][1]['reply'] = 'Yes, we are completely alone here.'
elif n == 'nohedge':
    s['steps'][0]['reply'] = 'Sure, it is quiet.'
elif n == 'kofail':
    s['ko_fail'] = True
elif n == 'savemissing':
    s['save_missing'] = True
print(json.dumps(s))
