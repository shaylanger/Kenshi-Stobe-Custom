#!/usr/bin/env python3
"""sfxscen.py <name>   scenario JSON (for sfxfake.py) used by sfx_selftest.sh (12-d v2).  Cind carries a Katana; Shay a Machete.
Names: pass-s3      s1 refuses (real gate line in s1 server), s2 refuses with a STALE line before its own send, s3 gives the Katana -> PASS
       declined     three clean aff85 asks all refused, s1 server only has gate_relative / "threshold" noise -> GATED LLM-DECLINED, gate "not exercised"
       contam       no transfer and the s2 prompt carries the old sword-ask history line -> SETUP-FAIL contaminated
       aff40-leak   s1 gives the Katana at aff40 -> FAIL aff40_refused_no_transfer
       blocked85    no transfer and the gate block line appears in s2 -> FAIL aff85_not_blocked_by_gate"""
import json
import sys

n = sys.argv[1]
CLEAN = 'Shay is the player. Recorded experience (data): none'
HIST = '- Shay, speaking to Cind [Hungry Bandit]: Can I have your sword as a gift?\n- Cind [Hungry Bandit], speaking to Shay: No.'
NOISE = 'native_kinds ["landmark","gate_relative"] "threshold":0.35 gate=complete'
BLOCK = 'Blocked low-trust outsider from giving equipped gear to player'
ref = lambda t, **k: dict({'reply': t, 'prompt': CLEAN, 'server': ''}, **k)
s = {'inv0': {'SHAY': {'Machete': 1}, 'CIND': {'Katana': 1}}}
if n == 'pass-s3':
    s['steps'] = [ref('No. That junk blade is all I have.', server=BLOCK),
                  ref('Still no, my blade is my life.', stale='If you need a weapon, the shops here sell them.'),
                  ref('Fine, take it. Look after it.', give=['Katana'])]
elif n == 'declined':
    s['steps'] = [ref('No.', server=NOISE), ref('No, my blade is my life.'), ref('Not the sword.'), ref('Ask someone else.')]
elif n == 'contam':
    s['steps'] = [ref('No.'), ref('Still no. Same answer as before.', prompt=CLEAN + '\n' + HIST), ref('No.', prompt=CLEAN + '\n' + HIST), ref('No.', prompt=CLEAN + '\n' + HIST)]
elif n == 'aff40-leak':
    s['steps'] = [ref('Fine, take it.', give=['Katana']), ref('No.'), ref('No.'), ref('No.')]
elif n == 'blocked85':
    s['steps'] = [ref('No.'), ref('Here you go.', server=BLOCK), ref('No.'), ref('No.')]
else:
    raise SystemExit('unknown scenario ' + n)
print(json.dumps(s))
