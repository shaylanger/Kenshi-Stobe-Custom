#!/usr/bin/env bash
# fp-manual-melee-life.sh: in-game M08 lifecycle/crowd rows of the manual melee adapter (COMBAT_TEST_PLAN.md M08,
# kfp_combat_melee.inc). Run with Kenshi in the world on kah-fpxbow right after load (Malzin = squad melee fighter
# fighting Skaera = hostile Hungry Bandit). Input: `fp_combat input <block> <swing> 0`.
# Evidence: `fp_melee state` counters (swings/clicks/rejected/ai_refused, why, owned, armed), the target's flesh (`hp`).
# Rule under test: UI/KO/load/actor change yield to native and a click held through them never swings on return (no
# inherited click); a fresh click after return swings; unarmed and two attackers keep the adapter fault-free.
# Rows: M08-UI, M08-KO, M08-LOAD, M08-UNARMED, M08-CROWD, M08-ACTOR, M08-LIMB.
# Usage: fp-manual-melee-life.sh [fighter] [target] [outdir] [other squad member for M08-ACTOR]. Ends with one `RESULT <row> PASS|FAIL <evidence>` per row.
FI=${1:-Malzin}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-melee-life}; OT=${4:-Axima}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | tail -1 | cut -d= -f2; }
ms() { A fp_melee state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" 0 >/dev/null; }
flesh() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | awk '{s+=$1}END{printf "%.1f", s}'; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A pin "$TG" off >/dev/null; [ -n "$WEP" ] && A unequip "$FI" "$WEP" >/dev/null
            A protect "$FI" off >/dev/null; A protect "$TG" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
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
take() { A select "$FI" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null; }
# ready: release input, wait until the adapter owns a fighting fighter (why=ok, armed) and a click is legal
ready() { inp 0 0; engage; local end=$((SECONDS+${1:-20})); while [ $SECONDS -lt $end ]; do
  [ "$(ms why)" = ok ] && [ "$(ms armed)" = 1 ] && in_fight && [ "$(ms dead)" = 0 ] && [ "$(ms state)" != 8 ] && return 0; sleep 0.3; done; return 1; }
# fresh_click: one LMB edge at a legal moment; echoes the swing delta within 1.5 s (expect 1)
fresh_click() { ready 15 || { echo not_ready; return; }; local s0; s0=$(ms swings); inp 0 1; sleep 0.15; inp 0 0
  for _ in $(seq 1 15); do [ "$(ms swings)" != "$s0" ] && break; sleep 0.1; done; echo $(( $(ms swings) - s0 )); }
# legal_click: wait (<= 6 s) for a native moment where a click is legal (state STARTUP/DECISION/CIRCLE/WAIT, not in
# dead time, nothing pending), then click; echoes the swing delta or "no_window" (stumble-locked the whole time)
# The target is re-pinned in reach first: the second attacker's hits stumble the fighter away and nothing walks it back
# (no AI approach while owned, M06; no WASD in the test): 5090 batch 2 had all 4 legal clicks out_of_reach (1->5).
legal_click() { local end=$((SECONDS+6)) s; while [ $SECONDS -lt $end ]; do s=$(A fp_melee state)
  case "$(echo "$s" | fld state)" in 3|4|5|6) echo "$s" | grep -q ' dead=0 ' && [ "$(echo "$s" | fld pending)" = 0 ] && { close; fresh_click; return; };; esac
  sleep 0.1; done; echo no_window; }
# cl_click: one click generated by the product at the first legal frame (fp_melee click_legal, same predicate as a real
# click). 4080 batch 11: the wrapper's poll->click round trip (~1-2 s) let a stumble-locked fighter flip 3->8 before the
# click landed, so 4 "legal" clicks were all rejected in STUMBLE. Echoes the swing delta, no_window (no legal frame
# in 6 s), not_ready (no owned live fight) or cl_refused.
cl_click() { inp 0 0; engage; local end=$((SECONDS+10)) ok=0 s0 f0 t0 s; while [ $SECONDS -lt $end ]; do
    [ "$(ms why)" = ok ] && [ "$(ms armed)" = 1 ] && in_fight && { ok=1; break; }; sleep 0.3; done
  [ $ok = 1 ] || { echo not_ready; return; }
  s=$(A fp_melee state); s0=$(echo "$s" | fld swings); f0=$(echo "$s" | fld cl_fired); t0=$(echo "$s" | fld cl_timeouts); close
  A fp_melee click_legal 6000 | grep -q armed || { echo cl_refused; return; }
  ok=0; end=$((SECONDS+9)); while [ $SECONDS -lt $end ]; do s=$(A fp_melee state)
    [ "$(echo "$s" | fld cl_timeouts)" != "$t0" ] && { echo no_window; return; }
    [ "$(echo "$s" | fld cl_fired)" != "$f0" ] && { ok=1; break; }; sleep 0.2; done
  [ $ok = 1 ] || { echo no_window; return; }
  for _ in $(seq 1 15); do [ "$(ms swings)" != "$s0" ] && break; sleep 0.1; done; echo $(( $(ms swings) - s0 )); }
# blood: target blood (unarmed martial-arts hits: 5090 batch 1 showed blood 77.6->69.5 with every part still 100%)
blood() { A hp "$1" | grep -o 'blood=[0-9.]*' | cut -d= -f2; }
# held: hold LMB and count swings over N s (a held click must start at most the one its own edge allowed)

# ---- setup (same as fp-manual-melee.sh) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$FI" | fld bow)" = none ] || A unequip "$FI" "$(A rangedinfo "$FI" | fld bow)" >/dev/null
BOWN=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
arm_melee || setup_fail "$FI has no melee weapon that equips (inv weapons: $(weapons | tr '\n' ';'))"
A protect "$FI" on >/dev/null
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$FI") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$FI" dist 600 >/dev/null;; esac; done
A health "$TG" 100 >/dev/null; A setstat "$TG" defence 1 >/dev/null; A setstat "$TG" dodge 1 >/dev/null
take
close || setup_fail "pin $TG in reach of $FI refused"
A fp_control state | grep -q "control_ids=.*/$(A where "$FI" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $FI"
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
ready 20 || setup_fail "adapter not ready (why=$(ms why) armed=$(ms armed) manual_ready=$(ms manual_ready))"
# no AI attack aimed at the fighter starts (test switch): no auto-block in manual mode, so its hits would stumble-lock the
# fighter and reject the clicks (4080 batch 2); M03 switches it back on, it needs a real attacker
PS=$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')
A fp_melee passive "$PS" | grep -q "passive on" || setup_fail "fp_melee passive $PS refused"

# ---- M08-UI: inventory open, then LMB held + clicks -> why=not_allowed, no swing; close with LMB held -> none; fresh swings ----
S0=$(ms swings); A click INV >/dev/null; for _ in $(seq 1 12); do [ "$(ms why)" = not_allowed ] && break; sleep 0.25; done
inp 0 1; sleep 0.3; for _ in 1 2 3; do inp 0 0; sleep 0.1; inp 0 1; sleep 0.3; done
W=$(ms why); SU=$(ms swings); A click INV >/dev/null; sleep 2; SC=$(ms swings); W2=$(ms why); inp 0 0; FS=$(fresh_click)
ev="ui: why=$W swings_during=$((SU-S0)) after_close_held=$((SC-SU)) why_after=$W2 fresh_click_swings=$FS"
if [ "$W" = not_allowed ] && [ "$SU" = "$S0" ] && [ "$SC" = "$SU" ] && [ "$FS" = 1 ]; then row M08-UI PASS "$ev"; else row M08-UI FAIL "$ev"; fi

# ---- M08-KO: KO, then LMB held -> no swing while down, none inherited on waking; fresh click swings ----
ready 15; S0=$(ms swings); A protect "$FI" off >/dev/null; A ko "$FI" 6 >/dev/null   # protect clears a KO at once
for _ in $(seq 1 12); do [ "$(ms why)" = not_allowed ] && break; sleep 0.25; done; inp 0 1; sleep 1; W=$(ms why); SK=$(ms swings)
for _ in $(seq 1 60); do [ "$(ms why)" = not_allowed ] || break; inp 0 1; sleep 0.5; done
sleep 2; SW=$(ms swings); W2=$(ms why); inp 0 0; A protect "$FI" on >/dev/null; take; FS=$(fresh_click)
ev="ko: why=$W swings_down=$((SK-S0)) after_wake_held=$((SW-SK)) why_after=$W2 fresh_click_swings=$FS"
if [ "$W" = not_allowed ] && [ "$SK" = "$S0" ] && [ "$SW" = "$SK" ] && [ "$FS" = 1 ]; then row M08-KO PASS "$ev"; else row M08-KO FAIL "$ev"; fi

# ---- M08-LOAD: save mid-fight, load with LMB held -> no inherited swing, adapter re-arms, fresh click swings ----
ready 15 && PR=1 || PR=0; A save kah-fp-m08 >/dev/null; sleep 2; inp 0 1; A load kah-fp-m08 >/dev/null; A wait-world >/dev/null
S0=$(ms swings); sleep 3; SL=$(ms swings); W=$(ms why); AR=$(ms armed); inp 0 0
A protect "$FI" on >/dev/null; A setstat "$TG" defence 1 >/dev/null; A setstat "$TG" dodge 1 >/dev/null; take
A fp_combat on >/dev/null; close; ready 15; A fp_melee passive "$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')" >/dev/null; FS=$(fresh_click)   # new characters after load
ev="load: pre_save_fight=$PR held_swings_after_load=$((SL-S0)) why=$W armed=$AR fresh_click_swings=$FS"
if [ "$SL" = "$S0" ] && [ "$FS" = 1 ]; then row M08-LOAD PASS "$ev"; else row M08-LOAD FAIL "$ev"; fi

# ---- M08-UNARMED: melee weapon unequipped -> unarmed click still swings (native martial arts), hits land ----
U1=$(A unequip "$FI" "$WEP"); sleep 2; take
A health "$TG" 100 >/dev/null; sleep 0.3; H0=$(flesh "$TG"); B0=$(blood "$TG"); sw=0
for _ in 1 2 3 4; do r=$(fresh_click); [ "$r" = 1 ] && sw=$((sw+1)); sleep 2; done; H1=$(flesh "$TG"); B1=$(blood "$TG"); U2=$(A unequip "$FI" "$WEP")
A equip "$FI" "$WEP" | grep -q ERROR && { A pickup "$FI" "$WEP" now >/dev/null; sleep 1; A equip "$FI" "$WEP" >/dev/null; }; sleep 2
# U2 = the second unequip's reply: "ERROR: not equipped" proves the weapon stayed off during the clicks (expected)
ev="unarmed ('$WEP': ${U1%% *}, still_unequipped=$([[ "$U2" == *"not equipped"* ]] && echo 1 || echo 0)): 4 clicks swung=$sw $TG flesh $H0->$H1 blood $B0->$B1 why=$(ms why)"
if [[ "$U1" == unequipped* ]] && [[ "$U2" == *"not equipped"* ]] && [ "$sw" -ge 3 ] && awk -v a="$H0" -v b="$H1" -v c="$B0" -v d="$B1" 'BEGIN{exit !(b<a-0.5 || d<c-0.5)}'; then row M08-UNARMED PASS "$ev"; else row M08-UNARMED FAIL "$ev"; fi

# ---- M08-CROWD: a second hostile attacks the fighter -> adapter stays owned/ok, clicks still swing, AI refused ----
A fp_melee passive off >/dev/null   # the second attacker must really attack
SP=$(A spawn "Hungry Bandit" Drifters near "$FI" dist 5 target "$FI"); N2=$(echo "$SP" | sed -n 's/.*: \([^#]*\) #.*/\1/p' | sed 's/ *$//')
# two live attackers and no RMB block (blocking is the player's job): the fighter spends most of the time in native
# STUMBLE, where a click is rejected like the AI's own attack (5090 batch 1: 1/4 blind clicks swung, the rest rejected
# in state 8). The clicks come from the product at the first legal frame (cl_click: 4080 batch 11's wrapper-timed
# "legal" clicks all landed in STUMBLE after the poll round trip); the rejected/stumble evidence is reported.
take; sleep 4; R0=$(ms ai_refused); J0=$(ms rejected); O0=$(ms out_of_reach); E0=$(ms expired); sw=0; nw=0; nr=0; rs=""
for _ in 1 2 3 4; do r=$(cl_click); rs="$rs$r,"; case "$r" in 1) sw=$((sw+1));; no_window) nw=$((nw+1));; not_ready) nr=$((nr+1));; esac; sleep 1.5; done
sleep 3; s=$(A fp_melee state); R1=$(echo "$s" | fld ai_refused); J1=$(echo "$s" | fld rejected); OW=$(echo "$s" | fld owned); W=$(echo "$s" | fld why)
ev="crowd (spawned '${N2:-?}'): 4 product-legal clicks [${rs%,}] swung=$sw no_window=$nw not_ready=$nr cl_fired=$(echo "$s" | fld cl_fired) cl_timeouts=$(echo "$s" | fld cl_timeouts) rejected $J0->$J1 last_reject=$(echo "$s" | fld last_reject)/$(echo "$s" | fld last_reject_state) rej_stumble=$(echo "$s" | fld rej_stumble) out_of_reach $O0->$(echo "$s" | fld out_of_reach) expired $E0->$(echo "$s" | fld expired) ai_refused $R0->$R1 owned=$OW why=$W fault=$(A fp_combat state | fld fault)"
if [ -n "$N2" ] && [ "$sw" -ge 3 ] && [ "$OW" = 1 ] && [ "$W" = ok ]; then row M08-CROWD PASS "$ev"; else row M08-CROWD FAIL "$ev"; fi
[ -n "$N2" ] && A ko "$N2" 600 >/dev/null; A fp_melee passive "$PS" >/dev/null

# ---- M08-ACTOR: control moves to another squad member -> the fighter is released, its AI swings again (ai_refused
#      stops rising, target flesh drops with no input); re-take the fighter -> owned again, fresh click swings ----
ready 15; A select "$OT" >/dev/null; A fp_control take >/dev/null; sleep 1
A health "$TG" 100 >/dev/null; sleep 0.3; R0=$(ms ai_refused); H0=$(flesh "$TG"); sleep 10; R1=$(ms ai_refused); H1=$(flesh "$TG"); OW=$(ms owned)
take; sleep 2; OW2=$(ms owned); FS=$(fresh_click)
ev="control->$OT: owned=$OW ai_refused $R0->$R1 $TG flesh $H0->$H1 (AI fights) retake owned=$OW2 fresh_click_swings=$FS"
if [ "$R1" = "$R0" ] && awk -v a="$H0" -v b="$H1" 'BEGIN{exit !(b<a-0.5)}' && [ "$OW2" = 1 ] && [ "$FS" = 1 ]; then row M08-ACTOR PASS "$ev"; else row M08-ACTOR FAIL "$ev"; fi

# ---- M08-LIMB (last: permanent on this load): left arm severed -> adapter stays ok, fresh clicks still swing ----
# 4080 batch 11: click 1 swung, then the target was KO (M08-ACTOR's native fight had worn it down; cleanup said "still KO")
# and the fight ended (active=0 target_h=#0), so clicks 2-3 were not_ready. The target is protected (protect clears a KO
# at once and keeps it up) and healed; clicks come from the product at a legal frame (cl_click).
A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null
LS=$(A sever "$FI" left_arm noitem | grep -o "> [a-z]*" | tr -d "> "); sleep 2; take; A protect "$FI" on >/dev/null; sw=0; rs=""
for _ in 1 2 3; do r=$(cl_click); rs="$rs$r,"; [ "$r" = 1 ] && sw=$((sw+1)); sleep 1.5; done
ev="left arm severed (state=${LS:-?}): 3 clicks [${rs%,}] swung=$sw why=$(ms why) out_of_reach=$(ms out_of_reach) last_reject=$(ms last_reject) $TG $(A where "$TG" | grep -o 'KO\|DEAD' | head -1) fault=$(A fp_combat state | fld fault)"
if [ "$LS" = stump ] && [ "$sw" -ge 2 ]; then row M08-LIMB PASS "$ev"; else row M08-LIMB FAIL "$ev"; fi

for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
