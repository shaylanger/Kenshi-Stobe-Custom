#!/usr/bin/env python3
"""imm26-fix19erecipe: 19-e recipe teleports Cind next to Shay right before s4 and verifies the distance. Usage: patch.py <rowtools dir>"""
import os
import sys

d = sys.argv[1]
p = os.path.join(d, 'reloaddefs_b.sh')
s = open(p, newline='').read()
a = """  # the one chat line: first post-load turn = the resume turn
  rl_say 4 "Where were we going?" || return $?
"""
assert s.count(a) == 1, 'anchor s4'
b = """  # 19-e recipe fix (fix19erecipe): the 30 s quiet window lets her wander (107.6 u at s4 = beyond the 80 u people-list limit -> 'Trip resume wait' why=not_in_people); put her next to Shay right before s4
  rb_19e_close || return $?
  # the one chat line: first post-load turn = the resume turn
  rl_say 4 "Where were we going?" || return $?
"""
s = s.replace(a, b)
h = "rd_19e() {"
assert s.count(h) == 1, 'anchor rd_19e'
fn = '''rb_19e_close() {   # teleport the NPC to Shay and verify (where) she is <= ${ROW_19E_MAXDIST:-40} u away right before s4; else rc 3 + RL_REASON (SETUP-FAIL). Evidence: $EV/near_s4.txt
  local max="${ROW_19E_MAXDIST:-40}" n w d try
  RL_NPC_ID=""; rd_need_npc || return 3
  n=$(rl_q "$RL_NPC_FULL")
  for try in 1 2; do
    echo "try $try: before dist=${RL_DIST:-?}" >> "$EV/near_s4.txt"
    printf 'stobe-auto teleport %s Shay </dev/null | head -1\\n' "$n" | lt_h >> "$EV/near_s4.txt" 2>&1
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep 2
    w=$(printf 'stobe-auto where %s </dev/null 2>&1 | head -1 # rb:near19e\\n' "$n" | lt_h 2>&1 | head -1)
    d=$(echo "$w" | sed -nE 's/.* dist=([0-9.]+).*/\\1/p' | head -1)
    echo "try $try: after teleport where=$w" >> "$EV/near_s4.txt"
    if [ -n "$d" ] && awk -v d="$d" -v m="$max" 'BEGIN{exit !(d+0<=m+0)}'; then echo "near_s4 ok dist=$d (<= $max)" >> "$EV/near_s4.txt"; RL_DIST="$d"; return 0; fi
  done
  RL_REASON="19-e recipe: $RL_NPC_FULL is ${d:-unreadable} u from Shay after 2 teleports (limit $max u; the resume needs her inside the 80 u people list at s4); not a product failure, see $EV/near_s4.txt"
  return 3
}

'''
s = s.replace(h, fn + h)
open(p, 'w', newline='').write(s)

p = os.path.join(d, 'reloadfake_b.py')
s = open(p).read()
a = """    elif tag == 'money':
        print('ok')
"""
assert s.count(a) == 1, 'anchor fake'
s = s.replace(a, a + """    elif tag == 'near19e':   # `where <npc>` right before the 19-e resume turn; scen 'near19e' = [dist per call] (default 12.0)
        print("Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist=%s" % nxt('near19e', 12.0))
""")
open(p, 'w').write(s)
print('patched')
