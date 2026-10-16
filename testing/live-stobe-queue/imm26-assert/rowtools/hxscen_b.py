#!/usr/bin/env python3
"""hxscen_b.py <name>   scenario JSON (for hxfake.py) used by hx-selftest_b.sh (row 05-cx).  Steps are consumed in order E1 E2 E3 H1 H2 H3 N1 N2 N3."""
import json
import sys

n = sys.argv[1]


def prompt(people):
    body = '## Nearby People Awareness\n### Person\nShay | the player\n' + ''.join(f'### Person\n{p}\n' for p in people)
    return 'Action Flags: calm\n' + body + '## Other section\nx\n'


E = prompt([])
H = prompt(['Dorn Vale | asleep on the ground, not visible as awake'])
N = prompt(['Malzin | standing nearby', 'Rik Aldo | standing nearby', 'Tess Orn | standing nearby', 'Bram Kell | standing nearby'])
HEDGE = "As far as I can see, we're alone, but I can't be sure."
s = {'reply': HEDGE, 'spawn_names': ['Dorn', 'Rik', 'Tess', 'Bram']}
ps = [E] * 3 + [H] * 3 + [N] * 3
rep = [HEDGE] * 6 + ['No, there are a few people standing right here with us.'] * 3
QS = ['Are we alone?', 'Is anyone else around here?', 'Can anyone hear us?'] * 3
if n == 'nonempty':      ps[0] = prompt(['Jetha Roe | unconscious'])
elif n == 'extras':      s['extras_left'] = 2
elif n == 'absolute':    rep[1] = 'Yes, we are completely alone here.'
elif n == 'norosterN':   ps[6:9] = [E] * 3
elif n == 'base':        pass
else: raise SystemExit(f'unknown scenario {n}')
s['nsteps'] = 9
s['steps'] = [{'reply': rep[i], 'prompt': ps[i], 'server': '', 'events': [], 'full': [['inputtext', f'Shay: {QS[i]} (talking to: Cind)']]} for i in range(9)]
print(json.dumps(s))
