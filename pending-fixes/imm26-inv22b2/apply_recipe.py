#!/usr/bin/env python3
"""imm26-inv22b2: 22-b recipe fix. The bored tick must name the NPC exactly as the DLL does ("Cind [Hungry Bandit]"), not the bare "Cind".

usage: python3 apply_recipe.py <rowtools dir>   (e.g. C:/KenshiModding/testing/live-stobe-queue/imm26-assert/rowtools)
Edits (anchors asserted, each must match exactly once; the script refuses to run twice):
  sfr22b_bored_g.sh          i4_bored: nm = full name; profile= percent-encodes '[' and ']' (curl would glob them otherwise, and the DLL sends %5B/%5D)
  sfr22b_v3_selftest.sh      +1 check: the tick request carries profile=Cind%20%5BHungry%20Bandit%5D and people with the full name (fails before, passes after)
Do not apply while a queued/running list uses sfrrun_v3.sh (a mid-run edit kills it).
"""
import sys
root = sys.argv[1].rstrip('/\\')

def rw(name, fn):
    p = root + '/' + name
    b = open(p, 'rb').read().decode('utf-8')
    crlf = '\r\n' in b
    s = b.replace('\r\n', '\n')
    s2 = fn(s)
    assert s2 != s, name
    if crlf:
        s2 = s2.replace('\n', '\r\n')
    open(p, 'wb').write(s2.encode('utf-8'))

def rep(s, a, b):
    assert s.count(a) == 1, (a[:80], s.count(a))
    return s.replace(a, b)

def bored(s):
    assert 'imm26-inv22b2' not in s, 'already applied'
    s = rep(s, '''  nm="${RL_NPC_FULL%% \\[*}"; [ -n "$nm" ] || nm="${ROW_NPC%% \\[*}"\n''',
'''  nm="$RL_NPC_FULL"; [ -n "$nm" ] || nm="$ROW_NPC"   # imm26-inv22b2: the DLL names the speaker "Cind [Hungry Bandit]" (profile= and people=, ChatBox.cpp:5752-5754/5833-5844). The bare "Cind" resolved
  # to a stale placeholder row (no travel_lifecycle) because getNpcData is an exact-name lookup, so bored.php:186's reconcile returned at stobeCommitmentNativeSnapshot and the COMPLETED receipt was never ingested (22-b run 3).
''')
    s = rep(s, '''profile=$(printf %s "$nm" | sed 's/ /%20/g')&''',
               '''profile=$(printf %s "$nm" | sed 's/ /%20/g; s/\\[/%5B/g; s/\\]/%5D/g')&''')
    return s

def selftest(s):
    anchor = '# TRIP_13C_STAGE honoured and gate unchanged\n'
    new = '''# imm26-inv22b2: the bored tick names the NPC like the DLL (full name in profile= and people=), never the bare "Cind" (stale placeholder row, no native snapshot)
scen "$REAL_FIN" "$REAL_PHC"; o=$(run22); grep -q 'profile=Cind%20%5BHungry%20Bandit%5D' "$F" && ! grep -qE 'profile=Cind(&|%20&)' "$F" && grep -q 'Cind \\[Hungry Bandit\\]|' "$F" && chk bored-tick-uses-dll-full-name ok || chk bored-tick-uses-dll-full-name bad "$(grep -o 'profile=[^&]*' "$F" | sort -u | head -3 | tr '\\n' ' ')"
'''
    return rep(s, anchor, new + anchor)

rw('sfr22b_bored_g.sh', bored)
rw('sfr22b_v3_selftest.sh', selftest)
print('patched sfr22b_bored_g.sh + sfr22b_v3_selftest.sh in', root)
