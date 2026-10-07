#!/usr/bin/env bash
# fp-manual-melee.sh: in-game rows of the manual melee adapter (COMBAT_TEST_PLAN.md Gate 4, kfp_combat_melee.inc).
# Run in WSL with Kenshi in the world on kah-fpxbow right after load (Malzin = squad melee fighter already fighting
# Skaera = hostile Hungry Bandit). Input: `fp_combat input <block> <swing> 0` (same controller path as RMB/LMB).
# Evidence: `fp_combat state` melee counters (swings = native AttackState::initialise runs we allowed, ai_refused = AI
# initiative refused, rejected = illegal clicks, blocks/block_ok), `fp_melee state` (state/technique), the target's
# flesh per body part (`hp`) and the fighter's melee attack base skill (`stat`).
# Rows: M00 ownership (no input -> no own swing, AI refused), M01 click -> native swing + impact, M02 spam can't raise
# the rate, M07 no queued/inherited click, M09-CHASE swings through a forced chase lock, M03 block request, M05 XP from manual hits, M06 out-of-reach click whiffs
# in place (no remote chase).
# Usage: fp-manual-melee.sh [fighter] [target] [outdir]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
FI=${1:-Malzin}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-melee}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | tail -1 | cut -d= -f2; }          # tail: melee fields follow the ranged ones
cs() { A fp_combat state | fld "$1"; }
ms() { A fp_melee state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" 0 >/dev/null; }
flesh() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | awk '{s+=$1}END{printf "%.1f", s}'; }
skill() { A stat "$FI" attack | grep -o 'base=[0-9.]*' | head -1 | cut -d= -f2; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_melee force_chase off >/dev/null; A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A pin "$TG" off >/dev/null; [ -n "$WEP" ] && A unequip "$FI" "$WEP" >/dev/null
            A protect "$FI" off >/dev/null; A protect "$TG" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
# click: one injected LMB edge (press 0.15 s, release)
click() { inp 0 1; sleep 0.15; inp 0 0; }
# in_fight: the controlled fighter's native CombatClass is active with a target
in_fight() { local s; s=$(A fp_melee state); echo "$s" | grep -q 'active=1' && ! echo "$s" | grep -q 'target_h=#0/'; }
# melee weapon: kah-fpxbow's fighter wields only a crossbow; the katana sits in the main inventory, so without an
# explicit equip every "manual" swing was unarmed martial arts (4080 batch 4: no attack XP, attack/strength rows flat).
# equip's reply proves the weapon is wielded ("equipped ..."). WEP = the wielded melee weapon.
weapons() { A inv "$FI" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$FI" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
# close: hold the target ~1.2 m in front of the fighter. Manual melee leaves spacing to the player (no AI approach
# moves the owned fighter, M06) and the test has no WASD, so the target is brought into reach instead.
close() { A pin "$TG" at "$FI" dist "${1:-12}" face "$FI" | grep -q '^pinned'; }
# engage: a live native fight with a target (after a KO or a load the fight can end: 4080 batch 4 M08-KO..LIMB all
# ran with active=0 target_h=#0). The hostile's attack order first, the fighter's own attack order as the fallback.
engage() { in_fight && return 0; local who end
  for who in 1 2; do if [ $who = 1 ]; then A attack "$TG" "$FI" >/dev/null; else A attack "$FI" "$TG" >/dev/null; fi; end=$((SECONDS+8))
    while [ $SECONDS -lt $end ]; do in_fight && return 0; sleep 0.5; done; done; return 1; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
BOWN=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
[ "$(A rangedinfo "$FI" | fld bow)" = none ] || A unequip "$FI" "$(A rangedinfo "$FI" | fld bow)" >/dev/null
arm_melee || setup_fail "$FI has no melee weapon that equips (inv weapons: $(weapons | tr '\n' ';'))"
A protect "$FI" on >/dev/null                        # the fighter must survive; the target stays unprotected (hp deltas)
# every other squad member far away + protected, so only the fighter hits the target
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$FI") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$FI" dist 600 >/dev/null;; esac; done
A health "$TG" 100 >/dev/null; A setstat "$FI" attack 5 >/dev/null   # low skill: XP per hit shows at 1 decimal
# the target can't parry a 5-attack fighter at its own defence (4080 m1: 4 swings, 0 hits): defence/dodge 1
A setstat "$TG" defence 1 >/dev/null; A setstat "$TG" dodge 1 >/dev/null
A select "$FI" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$FI" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $FI"
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0
close || setup_fail "pin $TG in reach of $FI refused"
engage || setup_fail "$FI not in a native fight with $TG (why=$(ms why) active=$(ms active) target_h=$(ms target_h))"
for _ in $(seq 1 40); do [ "$(ms why)" = ok ] && in_fight && break; sleep 0.5; done
[ "$(ms why)" = ok ] || setup_fail "melee adapter not ok (ranged why=$(A fp_combat state | grep -o 'why=[^ ]*' | head -1) melee why=$(ms why) ready=$(ms manual_ready))"
in_fight || setup_fail "$FI not in native melee combat with a target"
# no AI attack aimed at the fighter starts (test switch): no auto-block in manual mode, so its hits would stumble-lock the
# fighter and reject the clicks (4080 batch 2); M03 switches it back on, it needs a real attacker
PS=$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')
A fp_melee passive "$PS" | grep -q "passive on" || setup_fail "fp_melee passive $PS refused"

# ---- M00 ownership: 12 s with no input -> no swing of ours, AI initiative refused, target unhurt by the fighter ----
# (M03b: autoblock_refused = AI auto-blocks refused with RMB up; reported here, it rises only if the target attacks)
S0=$(ms swings); R0=$(ms ai_refused); AB0=$(ms autoblock_refused); H0=$(flesh "$TG"); sleep 12
S1=$(ms swings); R1=$(ms ai_refused); AB1=$(ms autoblock_refused); H1=$(flesh "$TG")
ev="idle 12s: swings $S0->$S1 ai_refused $R0->$R1 autoblock_refused $AB0->$AB1 $TG flesh $H0->$H1"
if [ "$S1" = "$S0" ] && [ "$R1" -gt "$R0" ] && awk -v a="$H0" -v b="$H1" 'BEGIN{exit !(b>=a-0.5)}'; then row M00 PASS "$ev"; else row M00 FAIL "$ev"; fi

# ---- M01 click -> native swing within 1 s, impact on the target within 4 s; M05 attack XP over the manual hits ----
# latency = the product's own click-edge -> native swing start time (last_latency_ms, real ms): a harness command
# takes ~0.3 s, so wall-clock timing around click/poll measured the test, not the game (4080 batch 4: 1.2-1.4 s)
K0=$(skill); hits=0; lat=""; swung=0; maxlat=0; O0=$(ms out_of_reach); E0=$(ms expired); J0=$(ms rejected)
for i in 1 2 3 4 5; do
  A health "$TG" 100 >/dev/null; sleep 0.3; H0=$(flesh "$TG"); S0=$(ms swings)
  for _ in $(seq 1 20); do [ "$(ms dead)" = 0 ] && [ "$(ms state)" != 8 ] && break; sleep 0.1; done      # click at a legal moment
  click; got=0
  for _ in $(seq 1 20); do [ "$(ms swings)" != "$S0" ] && { got=1; break; }; sleep 0.05; done
  if [ $got = 1 ]; then swung=$((swung+1)); l=$(ms last_latency_ms); lat+="$l "
    awk -v a="$l" -v m="$maxlat" 'BEGIN{exit !(a>m)}' && maxlat=$l; fi
  sleep 3; H1=$(flesh "$TG"); awk -v a="$H0" -v b="$H1" 'BEGIN{exit !(b<a-0.5)}' && hits=$((hits+1))
done
# M05 top-up: `stat` prints one decimal and one hit adds ~0.07 XP (4080 m09 mca: 1 hit, 5.1->5.1), so click
# on (max 10 more) until 3 manual hits have landed before reading the skill
m05hits=$hits
for _ in $(seq 1 10); do [ "$m05hits" -ge 3 ] && break
  A health "$TG" 100 >/dev/null; sleep 0.3; H0=$(flesh "$TG")
  for _ in $(seq 1 20); do [ "$(ms dead)" = 0 ] && [ "$(ms state)" != 8 ] && break; sleep 0.1; done
  click; sleep 3; H1=$(flesh "$TG"); awk -v a="$H0" -v b="$H1" 'BEGIN{exit !(b<a-0.5)}' && m05hits=$((m05hits+1))
done
K1=$(skill)
ev="5 clicks ($WEP): swung=$swung latency_ms=[${lat% }] hits=$hits out_of_reach+$(( $(ms out_of_reach)-O0 )) expired+$(( $(ms expired)-E0 )) rejected+$(( $(ms rejected)-J0 )) technique=$(ms technique)"
if [ "$swung" -ge 4 ] && [ "$hits" -ge 1 ] && awk -v m="$maxlat" 'BEGIN{exit !(m<=1000)}'; then row M01 PASS "$ev"; else row M01 FAIL "$ev"; fi
ev="attack base $K0->$K1 over $m05hits manual hits ($WEP)"
if [ "$m05hits" -ge 1 ] && awk -v a="$K0" -v b="$K1" 'BEGIN{exit !(b>a)}'; then row M05 PASS "$ev"; else row M05 FAIL "$ev"; fi

# ---- M02 spam: 15 clicks in 3 s can't start more swings than the native swing allows ----
# The clicks come from the product's spam switch (game thread, 200 ms period): wrapper-driven clicks cost ~0.3 s per
# harness call, so 5090 batch 1's "3 s" spam really took ~12 s (8 swings + 7 rejected = native pace, not a bug).
# Native pace proof, per pair (product fields): no swing starts while the previous one is still in CHOP (early_starts=0)
# and every start-to-start gap is >= that previous swing's own CHOP length (min_swing_slack >= 0). 4080 batch 11 compared
# min_swing_gap 0.941 s with last_swing_len 1.304 s: two different swings (technique lengths vary 0.7-1.4 s), not a bug.
A health "$TG" 100 >/dev/null; S0=$(ms swings); C0=$(ms clicks); J0=$(ms rejected)
A fp_melee spam 15 200 | grep -q "spam on" || setup_fail "fp_melee spam refused (needs KenshiFP >= 62464E5D)"
end=$((SECONDS+10)); while [ $SECONDS -lt $end ] && [ "$(ms spam_left)" != 0 ]; do sleep 0.5; done
sleep 1; s=$(A fp_melee state); S1=$(echo "$s" | fld swings); C1=$(echo "$s" | fld clicks); J1=$(echo "$s" | fld rejected)
G=$(echo "$s" | fld min_swing_gap); L=$(echo "$s" | fld last_swing_len); ES=$(echo "$s" | fld early_starts); SN=$(echo "$s" | fld slack_n)
SK=$(echo "$s" | fld min_swing_slack); US=$(echo "$s" | fld unfinished_starts)
ev="spam 15x200ms: clicks $C0->$C1 swings $S0->$S1 rejected $J0->$J1 early_starts=$ES slack_n=$SN min_swing_slack=${SK}s (min_swing_gap=${G}s last_swing_len=${L}s unfinished_starts=$US)"
if [ -z "$ES" ] || [ -z "$SN" ]; then setup_fail "fp_melee state has no early_starts/slack_n (needs the round-4 KenshiFP)"; fi
if [ $((C1-C0)) -ge 14 ] && [ $((S1-S0)) -ge 1 ] && [ $((S1-S0)) -le 5 ] && [ $((J1-J0)) -ge 5 ] && [ "$ES" = 0 ] &&
   { [ $((S1-S0)) -lt 2 ] || { [ "$SN" -ge 1 ] && awk -v k="$SK" 'BEGIN{exit !(k>=-0.02)}'; }; }; then row M02 PASS "$ev"; else row M02 FAIL "$ev"; fi

# ---- M07 no inherited click: after the spam, 2 s idle -> no extra swing, nothing pending ----
sleep 0.5; S0=$(ms swings); sleep 2; S1=$(ms swings); P=$(ms pending)
ev="after spam idle 2s: swings $S0->$S1 pending=$P"
if [ "$S1" = "$S0" ] && [ "$P" = 0 ]; then row M07 PASS "$ev"; else row M07 FAIL "$ev"; fi

# ---- M09-CHASE chase lock: with the native chase lock forced each tick (state 11/next 10, `fp_melee force_chase`),
#      pending clicks must still start swings (chase drop -> swing, chase_swings) instead of expiring (4080 m09: the
#      pending click went back to STARTUP -> 10 every frame, swings stalled while chase_drops climbed) ----
A health "$TG" 100 >/dev/null
s=$(A fp_melee state); S0=$(echo "$s" | fld swings); D0=$(echo "$s" | fld chase_drops); W0=$(echo "$s" | fld chase_swings); F0=$(echo "$s" | fld forced_chase)
[ -n "$W0" ] && [ -n "$F0" ] || setup_fail "fp_melee state has no chase_swings/forced_chase (needs KenshiFP with the M09 chase fix)"
A fp_melee force_chase on | grep -q "force_chase on" || setup_fail "fp_melee force_chase refused"
A fp_melee spam 50 200 | grep -q "spam on" || { A fp_melee force_chase off >/dev/null; setup_fail "fp_melee spam refused"; }
end=$((SECONDS+16)); while [ $SECONDS -lt $end ] && [ "$(ms spam_left)" != 0 ]; do sleep 0.5; done
sleep 1; A fp_melee force_chase off >/dev/null
s=$(A fp_melee state); S1=$(echo "$s" | fld swings); D1=$(echo "$s" | fld chase_drops); W1=$(echo "$s" | fld chase_swings); F1=$(echo "$s" | fld forced_chase)
X=$(echo "$s" | fld expired)
ev="force_chase spam 50x200ms: forced_chase $F0->$F1 chase_drops $D0->$D1 chase_swings $W0->$W1 swings $S0->$S1 expired=$X"
if [ "$F1" -gt "$F0" ] && [ "$D1" -gt "$D0" ] && [ $((W1-W0)) -ge 3 ] && [ $((S1-S0)) -ge 3 ]; then row M09-CHASE PASS "$ev"; else row M09-CHASE FAIL "$ev"; fi

# ---- M03 block (RMB only): the target attacks again (passive off); 10 s RMB up -> the fighter's native state never
#      enters BLOCK/REACTION_BLOCK (AI auto-block refused); 15 s RMB held -> it does, and no own swing starts.
#      block_ok (native check_block from the click path) is reported only: it is skipped while already blocking ----
# samples <s>: state samples every ~0.3 s; echoes "<block samples> <stumble samples> <total>". Spacing: the target's
# hits stumble the fighter back and nothing walks it forward again (no AI approach while owned, M06; no WASD in the
# test), while the pinned target only moves 1.5 m off its spot: 5090 batch 2 had stumbles only early in the RMB-up
# half and none while RMB was held (blocking_h=#0, 0/26 block states). The target is re-pinned in reach every ~6
# samples outside BLOCK/REACTION_BLOCK/STUMBLE, like a player stepping back in.
samples() { local end=$((SECONDS+$1)) b=0 t=0 n=0 st; while [ $SECONDS -lt $end ]; do st=$(ms state)
  case "$st" in 1|2) b=$((b+1));; 8) t=$((t+1));; *) [ $((n % 6)) = 5 ] && close;; esac; n=$((n+1)); sleep 0.2; done; echo "$b $t $n"; }
gap() { local a b; a=$(A where "$FI" | grep -o 'pos=[^ ]*' | cut -d= -f2); b=$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2)
  awk -v a="$a" -v b="$b" 'BEGIN{split(a,p,",");split(b,q,",");printf "%.1f", sqrt((p[1]-q[1])^2+(p[3]-q[3])^2)}'; }
A fp_melee passive off >/dev/null; close; sleep 2
A health "$FI" 100 >/dev/null; AB0=$(ms autoblock_refused); GU=$(gap); read -r UB UT UN <<<"$(samples 10)"; AB1=$(ms autoblock_refused)
B0=$(ms blocks); O0=$(ms block_ok); S0=$(ms swings)
close; GH=$(gap); inp 1 0; read -r HB HT HN <<<"$(samples 15)"; inp 0 0; GE=$(gap)
B1=$(ms blocks); O1=$(ms block_ok); S1=$(ms swings)
A fp_melee passive "$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')" >/dev/null
ev="rmb up 10s (gap=${GU}dm): block_states=$UB/$UN stumble=$UT/$UN autoblock_refused $AB0->$AB1 | rmb held 15s (gap=${GH}->${GE}dm): block_states=$HB/$HN stumble=$HT/$HN blocks $B0->$B1 block_ok $O0->$O1 swings $S0->$S1"
if [ "$UB" = 0 ] && [ "$AB1" -gt "$AB0" ] && [ "$HB" -ge 3 ] && [ $((B1-B0)) -ge 1 ] && [ "$S1" = "$S0" ]; then row M03 PASS "$ev"; else row M03 FAIL "$ev"; fi

# ---- M06 out-of-reach click: target pinned 8 m away -> no swing, no walk to the target (whiff in place) ----
pos2() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}'; }
dist() { awk -v a="$1" -v b="$2" -v c="$3" -v d="$4" 'BEGIN{printf "%.1f", sqrt((c-a)^2+(d-b)^2)}'; }
# settle: the M03 attacker phase can leave the fighter in a native STUMBLE (anim-driven recoil, 4080 b28: 13 dm
# "idle drift" sampled while state=8): wait (max 12 s) until it is out of CHOP/STUMBLE and holds still for 1 s,
# else SETUP FAIL instead of a drift verdict
A pin "$TG" at "$FI" dist 80 face "$FI" >/dev/null; sleep 2; ST_END=$((SECONDS+12)); settled=0
while [ $SECONDS -lt $ST_END ]; do read -r sx sz <<<"$(pos2 "$FI")"; sleep 1; read -r sx2 sz2 <<<"$(pos2 "$FI")"
  case "$(ms state)" in 0|8) ;; *) awk -v d="$(dist "$sx" "$sz" "$sx2" "$sz2")" 'BEGIN{exit !(d<=1)}' && { settled=1; break; };; esac; done
[ $settled = 1 ] || { for r in "${RESULTS[@]}"; do echo "$r"; done; echo "RESULT SETUP FAIL M06: fighter not settled after 12 s (state=$(ms state)) log=$LOG"; exit 1; }
HH0=$(ms hold_halts)
read -r x0 z0 <<<"$(pos2 "$FI")"; read -r tx0 tz0 <<<"$(pos2 "$TG")"; sleep 2; read -r x1 z1 <<<"$(pos2 "$FI")"; D0=$(dist "$x0" "$z0" "$x1" "$z1")
S0=$(ms swings); O0=$(ms out_of_reach); J0=$(ms rejected); E0=$(ms expired); click; sleep 2
read -r x2 z2 <<<"$(pos2 "$FI")"; read -r tx2 tz2 <<<"$(pos2 "$TG")"; D1=$(dist "$x1" "$z1" "$x2" "$z2"); S1=$(ms swings); O1=$(ms out_of_reach); J1=$(ms rejected); E1=$(ms expired)
A pin "$TG" off >/dev/null
ev="target 8m: idle_drift=${D0}dm click_drift=${D1}dm swings $S0->$S1 out_of_reach $O0->$O1 rejected $J0->$J1 expired $E0->$E1 approach_refused=$(ms approach_refused) chase_frames=$(ms chase_frames) hold_halts=$HH0->$(ms hold_halts) target_drift=$(dist "$tx0" "$tz0" "$tx2" "$tz2")dm gap=$(dist "$x2" "$z2" "$tx2" "$tz2")dm"
# player controls spacing: no AI approach while owned (idle drift <= 1 m), the click whiffs in place
if [ "$S1" = "$S0" ] && [ $(( (O1-O0) + (J1-J0) + (E1-E0) )) -ge 1 ] && awk -v a="$D0" -v b="$D1" 'BEGIN{exit !(a<=10 && b<=10)}'; then row M06 PASS "$ev"; else row M06 FAIL "$ev"; fi

for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
