#!/usr/bin/env python3
"""patch27a.py <rowtools dir>   imm26-fix27a: row 27-a recipe/assertion fix (diagnosis: agents/out/imm26-inv-27a/latest.md "Smallest fix").
Idempotent (marker 27A-FIX in every touched file; already patched = skipped), every anchor asserted (exactly once) before ANY file is written."""
import os
import sys

D = sys.argv[1]
MARK = '27A-FIX'


def rf(n):
    return open(os.path.join(D, n), encoding='utf-8', newline='').read()


def sub(txt, old, new, name):
    nl = chr(13) + chr(10)
    if nl in txt:   # CRLF files (unblockscen_b.py): anchors and replacements follow the file
        old, new = old.replace(chr(10), nl), new.replace(chr(10), nl)
    assert txt.count(old) == 1, f'{name}: anchor not found exactly once ({txt.count(old)}): {old[:70]!r}'
    return txt.replace(old, new)


out = {}

# ---------------------------------------------------------------- reloadcheck_a.py
t = rf('reloadcheck_a.py')
if MARK not in t:
    t = sub(t, "ACTIVE = ('proposed', 'accepted')\n",
            "ACTIVE = ('proposed', 'accepted')\n"
            "BG_NEAR = float(os.environ.get('RW_BG_NEAR', '100'))   # 27A-FIX: bodyguard end-of-chase limit (u). The native Bodyguard package keeps a stand-off of ~50-67 u, so the legacy-FOLLOW 35 u never fits; a non-follower stays ~RW_AWAY_BG (200) u away\n",
            'reloadcheck_a ACTIVE')
    t = sub(t, "    if not need(v, ev, 'bg_post.txt', 'state_post.txt', 'chase_pre.txt', 'chase_post.txt', 'state_after_chase.txt'):\n        return\n"
               "    a0, a1 = chase(ev, 'chase_pre.txt')\n"
               "    v.ck('pre_load_bodyguard_follows', a0 is not None and a1 is not None and a1 <= 35, f'{a0} -> {a1}')\n"
               "    b0, b1 = chase(ev, 'chase_post.txt')\n"
               "    closes = b1 is not None and b0 is not None and b1 <= 35 and b1 < b0\n",
            "    if not need(v, ev, 'bg_post.txt', 'state_post.txt', 'chase_ctrl.txt', 'chase_pre.txt', 'chase_post.txt', 'state_after_chase.txt'):\n        return\n"
            "    # 27A-FIX negative control: the SAME chase before the hire (no contract). If that NPC approaches Shay anyway, 'closes the distance' proves nothing.\n"
            "    c0, c1 = chase(ev, 'chase_ctrl.txt')\n"
            "    if c0 is None or c1 is None or c0 < 60 or c1 < 0.8 * c0:\n"
            "        return v.setup_fail(f'NPC approaches Shay without a contract (control chase {c0} -> {c1}; needs end >= 0.8 x start and start >= 60) - the bodyguard chase cannot discriminate (needs: recipe)')\n"
            "    a0, a1 = chase(ev, 'chase_pre.txt')\n"
            "    v.ck('pre_load_bodyguard_follows', a0 is not None and a1 is not None and a1 <= BG_NEAR, f'{a0} -> {a1} (limit {BG_NEAR:g}; control {c0} -> {c1})')\n"
            "    b0, b1 = chase(ev, 'chase_post.txt')\n"
            "    closes = b1 is not None and b0 is not None and b1 <= BG_NEAR and b1 < b0\n",
            'reloadcheck_a c_27a')
    out['reloadcheck_a.py'] = t

# ---------------------------------------------------------------- rd_27a (reloaddefs_a.sh + unblockdefs_b.sh)
CTRL = ('  # 27A-FIX negative control: the same chase BEFORE the hire (no contract) -> chase_ctrl.txt; the checker needs it to NOT approach. Then the NPC is put back next to Shay.\n'
        '  rw_chase ctrl || return $?\n'
        '  rd19_place near || return $?\n'
        '  nq=$(rl_q "$RL_NPC_FULL")\n')
for fn in ('reloaddefs_a.sh', 'unblockdefs_b.sh'):
    t = rf(fn)
    if MARK in t:
        continue
    t = sub(t, 'rd_27a() {\n  local nq; rw_prep || return $?\n',
            'rd_27a() {\n  local nq RW_AWAY="${RW_AWAY_BG:-200}"   # 27A-FIX: 200 u (not the 80 u default): a follower ends <= ~70 u, a non-follower stays >= ~200 u; rw_chase reads RW_AWAY (dynamic scope)\n  rw_prep || return $?\n', fn + ' head')
    t = sub(t, '  lt_h <<EOT > "$EV/bg_set.txt" 2>&1\n', CTRL + '  lt_h <<EOT > "$EV/bg_set.txt" 2>&1\n', fn + ' bg_set')
    out[fn] = t


# ---------------------------------------------------------------- fakes + scenarios + selftests
t = rf('reloadfake.py')
if MARK not in t:
    t = sub(t, "        st['away'] = True\n        out([])\n",
            "        st['away'] = True\n        st['phase'], st['ci'] = 'start', st['speed3']   # 27A-FIX: scenario key chase_d = [[start, end] per chase: control, pre, post]\n        out([])\n", 'reloadfake teleport')
    t = sub(t, "        st['speed3'] += 1\n", "        st['speed3'] += 1\n        st['phase'] = 'end'\n", 'reloadfake speed3')
    t = sub(t, "    if 'stobe-auto where' in body and not scen.get('npc_missing'):\n",
            "    if re.search(r\"teleport '[^']*' Shay\", body):\n        st['phase'] = None   # the NPC was put next to Shay again\n        out([])\n"
            "    if 'stobe-auto where' in body and not scen.get('npc_missing') and scen.get('chase_d') and st.get('phase'):\n"
            "        cd = scen['chase_d']\n"
            "        d = cd[min(st['ci'], len(cd) - 1)][0 if st['phase'] == 'start' else 1]\n"
            "        out([f\"Cind [Hungry Bandit] #2529907200/2 [Traders Guild] pos=-50970.0,1533.0,2965.0 dist={d}\"])\n"
            "    if 'stobe-auto where' in body and not scen.get('npc_missing'):\n", 'reloadfake where')
    out['reloadfake.py'] = t

t = rf('reloadscen.py')
if MARK not in t:
    old = """elif n in ('27a-pass', '27a-lost', '27a-noorder'):
    bg_state = state(first='present', goal='BODYGUARD')
    S = {'steps': [], 'bg': [['Cind bodyguard Shay hours=24'] if n != '27a-noorder' else ['no contract'],
                             ['Cind bodyguard Shay hours=23'] if n == '27a-pass' else ['no contract']],
         'follow': [bg_state if n != '27a-noorder' else state('none', goal='NONE'), bg_state if n == '27a-pass' else state('none', goal='NONE'), bg_state],
         'closes': [True, n == '27a-pass']}
"""
    new = """elif n in ('27a-pass', '27a-lost', '27a-noorder', '27a-ctrl-approaches', '27a-pre-wander', '27a-post-standoff-edge'):
    # 27A-FIX: chase_d = [start, end] u per chase in order control (no contract) / pre / post. A bodyguard ends at its 50-67 u stand-off (<= RW_BG_NEAR 100), a non-follower stays ~200 u.
    bg_state = state(first='present', goal='BODYGUARD')
    keep = n not in ('27a-lost', '27a-noorder')
    cd = {'27a-pass': [[200, 200], [200, 60], [200, 66]], '27a-lost': [[200, 200], [200, 60], [200, 195]], '27a-noorder': [[200, 200], [200, 60], [200, 195]],
          '27a-ctrl-approaches': [[200, 60], [200, 60], [200, 66]],        # the unhired NPC walks to Shay anyway: the chase proves nothing -> SETUP-FAIL
          '27a-pre-wander': [[200, 200], [200, 190], [200, 66]],           # the pre leg never closes
          '27a-post-standoff-edge': [[200, 200], [200, 67.3], [200, 100]]}[n]   # real stand-off 67.3 pre; post exactly at the limit still passes
    S = {'steps': [], 'bg': [['Cind bodyguard Shay hours=24'] if n != '27a-noorder' else ['no contract'],
                             ['Cind bodyguard Shay hours=23'] if keep else ['no contract']],
         'follow': [bg_state if n != '27a-noorder' else state('none', goal='NONE'), bg_state if keep else state('none', goal='NONE'), bg_state],
         'closes': [True, True, keep], 'chase_d': cd}
"""
    t = sub(t, old, new, 'reloadscen 27a')
    t = sub(t, "         'follow': [state('none', goal='OTHER')] * 3, 'closes': [True, n == '27a-statuserr']}\n",
            "         'follow': [state('none', goal='OTHER')] * 3, 'closes': [True, True, n == '27a-statuserr'],\n"
            "         'chase_d': [[200, 200], [200, 60], [200, 66 if n == '27a-statuserr' else 195]]}\n", 'reloadscen statuserr')
    t = sub(t, "27a-statuserr-lost 08e-pass", "27a-statuserr-lost 27a-ctrl-approaches 27a-pre-wander 27a-post-standoff-edge 08e-pass", 'reloadscen doc')
    out['reloadscen.py'] = t

t = rf('reload-selftest.sh')
if MARK not in t:
    anchor = 'expect 27-a-status-error-and-no-chase-fails 27a-statuserr-lost 27-a "RESULT 27-a FAIL" "order_present_after_load,post_load_bodyguard_closes_distance"\n'
    t = sub(t, anchor, anchor + r"""# 27A-FIX: bodyguard stand-off 50-67 u passes (<= RW_BG_NEAR 100), control chase + 200 u away
expect 27-a-control-approaches-setup-fail 27a-ctrl-approaches 27-a "RESULT 27-a SETUP-FAIL" "without a contract"
expect 27-a-pre-leg-never-closes 27a-pre-wander 27-a "RESULT 27-a FAIL" "pre_load_bodyguard_follows"
expect 27-a-standoff-edge-passes 27a-post-standoff-edge 27-a "RESULT 27-a PASS" "order_present_after_load"
scen 27a-pass; r=$(RW_BG_NEAR=35 run 27-a $L); case "$r" in "RESULT 27-a FAIL"*) chk 27-a-old-limit-35-fails-the-stand-off ok;; *) chk 27-a-old-limit-35-fails-the-stand-off bad "$r";; esac
scen 27a-pass; run 27-a $L >/dev/null
[ "$(grep -c 'teleport Shay -50770 ' "$KAH_ROW_FAKE_LOG")" -ge 3 ] && chk 27-a-three-chases-200u-away ok || chk 27-a-three-chases-200u-away bad "$(grep -c 'teleport Shay' "$KAH_ROW_FAKE_LOG")"
[ "$(grep -n 'teleport Shay -' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'contract-bodyguard .* Shay hours' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" ] && chk 27-a-control-chase-before-hire ok || chk 27-a-control-chase-before-hire bad
[ -s "$EVB/27-a/chase_ctrl.txt" ] && chk 27-a-chase-ctrl-written ok || chk 27-a-chase-ctrl-written bad
scen 27a-pass; r=$(RW_AWAY_BG=150 run 27-a $L >/dev/null; grep -c 'teleport Shay -50820 ' "$KAH_ROW_FAKE_LOG"); [ "$r" -ge 3 ] && chk 27-a-away-env-override ok || chk 27-a-away-env-override bad "$r"
""", 'reload-selftest')
    out['reload-selftest.sh'] = t

t = rf('unblock_b_selftest.sh')
if MARK not in t:
    anchor = 'expect 27-a-pass 27a-pass 27-a PASS "order_present_after_load"\n'
    t = sub(t, anchor, anchor + r"""# 27A-FIX: control chase before the hire, 200 u away, stand-off 50-67 u passes
expect 27-a-control-approaches 27a-ctrl-approaches 27-a SETUP-FAIL "without a contract"
expect 27-a-standoff-edge 27a-post-standoff-edge 27-a PASS "order_present_after_load"
scen 27a-pass; run 27-a $L >/dev/null
[ "$(grep -c 'teleport Shay -50770 ' "$KAH_ROW_FAKE_LOG")" -ge 3 ] && chk 27-a-three-chases-200u-away ok || chk 27-a-three-chases-200u-away bad
[ "$(grep -n 'teleport Shay -' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'contract-bodyguard .* Shay hours' "$KAH_ROW_FAKE_LOG" | head -1 | cut -d: -f1)" ] && chk 27-a-control-chase-before-hire ok || chk 27-a-control-chase-before-hire bad
[ -s "$KAH_ROWS_BASE/imm26-4080-i4/rows/27-a/chase_ctrl.txt" ] && chk 27-a-chase-ctrl-written ok || chk 27-a-chase-ctrl-written bad
""", 'unblock_b_selftest')
    out['unblock_b_selftest.sh'] = t

t = rf('unblockscen_b.py')
if MARK not in t:
    t = sub(t, "    elif n == '27a-allforms-fail':\n",
            "    elif n in ('27a-ctrl-approaches', '27a-post-standoff-edge'):   # 27A-FIX\n        S = base('reloadscen.py', n); S['bgforms'] = [[HAS1 % '24.0'], [HAS1 % '23.0']]\n    elif n == '27a-allforms-fail':\n", 'unblockscen_b')
    t = sub(t, "27a-lost 27a-nodll 27a-noorder\"\"\"", "27a-lost 27a-nodll 27a-noorder 27a-ctrl-approaches 27a-post-standoff-edge\"\"\"", 'unblockscen doc')
    out['unblockscen_b.py'] = t

for k, v in out.items():
    open(os.path.join(D, k), 'w', encoding='utf-8', newline='').write(v)
print('patch27a: patched %s' % (', '.join(sorted(out)) or 'nothing (already applied)'))
