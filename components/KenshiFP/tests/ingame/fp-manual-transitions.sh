#!/usr/bin/env bash
# fp-manual-transitions.sh: in-game S03 (COMBAT_TEST_PLAN.md): repeated switching between ranged and melee actors,
# FP on/off, manual combat on/off and save/load never leaves aim, reload, block or control stuck.
# Run with Kenshi in the world on kah-fpxbow right after load (Axima = squad crossbow user, Malzin = squad melee
# fighter, both fighting Skaera = hostile Hungry Bandit). Input: `fp_combat input <aim/block> <fire/swing> 0`.
# Per cycle: Axima aim -> shot-ready -> release (aimed=0 within 2 s, reload never stuck >12 s); Malzin melee why=ok,
# block held/released (no stuck wants-block: swings resume); FP off/on; manual combat off/on; every 2nd cycle save+load.
# Evidence: `fp_combat state` (aimed, shot_ready, reloading, fault, why), `fp_melee state` (why, owned, swings),
# `fp_control state` control_ids. Row: S03 PASS when every cycle reaches every step with fault=0.
# A step blocked or failed while `fp_state` says ui_open=1 (game UI holds FP input: dialogue, MyGUI key focus,
# panel, settings, free-cursor) is a SETUP fail (ui_why + components in the RESULT), not a product fail.
# Usage: fp-manual-transitions.sh [shooter] [fighter] [target] [outdir] [cycles, default 6].
SH=${1:-Axima}; FI=${2:-Malzin}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-manual-transitions}; N=${5:-6}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fh() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }   # ranged fields (first)
ft() { grep -o "\b$1=[^ ]*" | tail -1 | cut -d= -f2; }   # melee fields (last)
cs() { A fp_combat state | fh "$1"; }
ms() { A fp_melee state | ft "$1"; }
inp() { A fp_combat input "$1" "$2" 0 >/dev/null; }
waitcs() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.25; done; return 1; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fh fp_mode)
cleanup() { A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            for c in "$SH" "$FI" "$TG"; do A protect "$c" off >/dev/null; done; A pin "$TG" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
take() { A select "$1" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
  A fp_control state | grep -q "control_ids=.*/$(id_of "$1")"; }
look_at_target() { local sx sz tx tz
  read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
  A fp_camera look "$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')" 0.02 >/dev/null; }
prep() { for c in "$SH" "$FI" "$TG"; do A protect "$c" on >/dev/null; done
  A pin "$TG" at "$SH" dist 25 face "$SH" >/dev/null; A attack "$FI" "$TG" >/dev/null; A fp_combat autoreload 1 >/dev/null; }

A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
# the fighter must be melee-only: with a crossbow in its inventory the adapter takes the ranged path for it (4080 batch 3: owned=0)
FB=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
[ -n "$FB" ] && [ "$FB" != none ] && A unequip "$FI" "$FB" >/dev/null
prep
FAILS=(); steps=0
SETUPS=()
# ui_open diagnosis (KenshiFP fp_state: ui_why=control|key_focus|panels|settings|free + raw components)
uicomp() { echo "$1" | grep -o '\b\(ui_why\|control\|key_focus\|panels\|panel_frames\|settings\|free\)=[^ ]*' | tr '\n' ' ' | sed 's/ $//'; }
gstat() { A status | grep -o '\b\(paused\|speed\)=[^ ]*' | tr '\n' ' ' | sed 's/ $//'; }
# a step fail while the game UI held FP input (ui_open=1) is a setup fail (world event / focus), not a product fail
bad() { local st; st=$(A fp_state)
  if [ "$(echo "$st" | fh ui_open)" = 1 ]; then SETUPS+=("c$1:$2:ui_open($(uicomp "$st"))")
    echo "STEP SETUP cycle $1 $2 ui_open=1 $(uicomp "$st") $(gstat)" >> "$LOG"
  else FAILS+=("c$1:$2"); echo "STEP FAIL cycle $1 $2" >> "$LOG"; fi; }
# readiness before a step: ui_open=0 within 5 s; a stuck free-cursor/settings toggle is cleared once (fp_state free off)
ui_ready() { local st end=$((SECONDS+5)) tried=0
  while :; do st=$(A fp_state); [ "$(echo "$st" | fh ui_open)" = 0 ] && return 0
    if [ $tried = 0 ] && echo "$st" | grep -q 'ui_why=[^ ]*\(free\|settings\)'; then A fp_state free off >/dev/null; tried=1; end=$((SECONDS+2)); fi
    [ $SECONDS -ge $end ] && break; sleep 0.25; done
  SETUPS+=("c$1:$2:ui_open($(uicomp "$st"))"); echo "STEP SETUP cycle $1 $2 not ready ui_open=1 $(uicomp "$st") $(gstat)" >> "$LOG"; return 1; }
for c in $(seq 1 "$N"); do
  # ranged: take, combat on, aim to shot-ready, release -> not aimed, no stuck reload
  take "$SH" || bad "$c" take_shooter; look_at_target
  if ui_ready "$c" ranged; then
  A fp_combat on >/dev/null; inp 0 0; waitcs 4 armed 1 || bad "$c" ranged_arm
  inp 1 0; waitcs 15 shot_ready 1 || bad "$c" "shot_ready(why=$(cs why))"
  inp 0 0; waitcs 3 aimed 0 || bad "$c" aim_stuck
  waitcs 12 reloading 0 || bad "$c" reload_stuck
  fi
  [ "$(cs fault)" = 0 ] || bad "$c" ranged_fault
  # melee: take, why ok, block 2 s then release, swing still possible
  take "$FI" || bad "$c" take_fighter; A fp_melee passive "$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')" >/dev/null   # its hits would stumble-lock the fighter
  if ui_ready "$c" melee; then
  # the fight may have ended since prep (4080 b25 c2: active=0, every click rejected no_fight): re-engage first
  ok=0; for i in $(seq 1 40); do inp 0 0; s=$(A fp_melee state)
    [ "$(echo "$s" | ft why)" = ok ] && [ "$(echo "$s" | ft armed)" = 1 ] && [ "$(echo "$s" | ft active)" = 1 ] && { ok=1; break; }
    [ "$(echo "$s" | ft active)" = 1 ] || [ $((i % 10)) != 1 ] || A attack "$FI" "$TG" >/dev/null; sleep 0.3; done
  [ $ok = 1 ] || bad "$c" "melee_ready(why=$(ms why) active=$(ms active))"
  inp 1 0; sleep 2; inp 0 0; sleep 0.5; S0=$(ms swings)
  for _ in $(seq 1 10); do inp 0 1; sleep 0.15; inp 0 0; sleep 0.35; [ "$(ms swings)" != "$S0" ] && break; done
  [ "$(ms swings)" != "$S0" ] || bad "$c" no_swing_after_block
  fi
  # toggles
  A fp_mode off >/dev/null; sleep 0.5; A fp_mode on >/dev/null; sleep 0.5
  A fp_combat off >/dev/null; sleep 0.3; A fp_combat on >/dev/null; sleep 0.3
  [ "$(cs fault)" = 0 ] || bad "$c" toggle_fault
  if [ $((c % 2)) = 0 ]; then
    A save kah-fp-s03 >/dev/null; sleep 2; A load kah-fp-s03 >/dev/null
    A wait-world | grep -q -i 'world\|ok' || bad "$c" load; sleep 2; prep
  fi
  steps=$((steps+1))
done
take "$SH"; look_at_target; A fp_combat on >/dev/null; inp 0 0; sleep 1
END="aimed=$(cs aimed) reloading=$(cs reloading) fault=$(cs fault) why=$(cs why) melee_owned=$(ms owned)"
UIS=$(uicomp "$(A fp_state)")
ev="cycles=$steps/$N (2 loads each 2nd cycle) fails=${#FAILS[@]}${FAILS:+ [${FAILS[*]}]} setup_ui=${#SETUPS[@]}${SETUPS:+ [${SETUPS[*]}]} end: $END ui_end: $UIS"
# product fails win; else ui_open setup skips make it a SETUP FAIL (rerun after removing the cause), never a PASS
if [ ${#FAILS[@]} != 0 ] || [ "$steps" != "$N" ]; then V="FAIL"
elif [ ${#SETUPS[@]} != 0 ]; then V="SETUP FAIL ui_open"; else V="PASS"; fi
echo "RESULT S03 $V $ev$([ "$V" = PASS ] || echo " log=$LOG")"
echo "RESULT S03 $V $ev" >> "$LOG"
