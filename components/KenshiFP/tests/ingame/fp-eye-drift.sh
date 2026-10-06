#!/usr/bin/env bash
# fp-eye-drift.sh: row FP-EYE. The FP eye height must not creep up while a ranged weapon is held aimed
# (bug: aim animation translated the manually-controlled spine bones every frame, eye +0.4 dm per shot cycle).
# Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user). Holds aim, fires N manual shots
# into the ground ahead, compares eye height over the feet (fp_camera state camera_y - where y) at aim start and end.
# Evidence also: head_above / spine_pos_fixes (fp_camera state, KenshiFP fp-eye-drift build), actual_shots delta.
# Usage: fp-eye-drift.sh [shooter] [shots] [outdir]. Ends with `RESULT FP-EYE PASS|FAIL <evidence>`.
SH=${1:-Axima}; N=${2:-10}; OUT=${3:-/tmp/fp-eye-drift}; LIMIT=${EYE_DRIFT_LIMIT:-1.0}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
setup_fail() { echo "RESULT FP-EYE FAIL setup: $1 log=$LOG"; exit 1; }
# eye: "<camera_y - feet_y> <head_above> <spine_pos_fixes>" (median-free: one read, camera idles while aimed)
eye() { local c y; c=$(A fp_camera state); y=$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d, -f2)
  awk -v cy="$(fld camera_y <<<"$c")" -v fy="$y" -v ha="$(fld head_above <<<"$c")" -v fx="$(fld spine_pos_fixes <<<"$c")" \
    'BEGIN{ if (cy=="" || fy=="") print "nan"; else printf "%.3f %s %s\n", cy-fy, (ha==""?"na":ha), (fx==""?"na":fx) }'; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
A where "$SH" | grep -q 'pos=' || setup_fail "$SH not found"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null
# everyone else nearby protected + pinned away (out of the line of fire, no melee on the shooter)
for m in $(A chars 3000 "[nameless]" | tr '|' '\n' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  [ "$m" = "$SH" ] && continue; A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null; done
for m in ${EYE_AWAY:-Skaera}; do   # the fixture's hostile NPC
  A where "$m" | grep -q 'pos=' && { A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 500 >/dev/null; }; done
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null; A fp_combat on >/dev/null; inp 0 0 0; sleep 0.5
YAW=$(A fp_camera state | fld yaw); A fp_camera look "${YAW:-0}" 0.15 >/dev/null   # slightly down: bolts hit the ground ahead
E_IDLE=$(eye)
inp 1 0 0; waitfor 10 shot_ready 1 || setup_fail "not shot_ready after aim (why=$(cs why))"
sleep 2; E0=$(eye); S0=$(cs actual_shots)
[ "${E0%% *}" != nan ] || setup_fail "no camera_y/where y (eye=$E0)"

# ---- N shots with the aim held throughout ----
for i in $(seq 1 "$N"); do
  waitfor 12 shot_ready 1 || { echo "shot $i not ready" >> "$LOG"; continue; }
  s=$(cs actual_shots); inp 1 1 0; end=$((SECONDS+3))
  while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s" ] && break; sleep 0.1; done
  inp 1 0 0; echo "shot $i eye=$(eye)" >> "$LOG"
  waitfor 10 reloading 0 >/dev/null
done
sleep 2; E1=$(eye); S1=$(cs actual_shots); inp 0 0 0
SHOTS=$(( ${S1:-0} - ${S0:-0} ))
D=$(awk -v a="${E0%% *}" -v b="${E1%% *}" 'BEGIN{printf "%.3f", b-a}')
EV="drift=${D}dm eye0=${E0%% *} eye1=${E1%% *} idle=${E_IDLE%% *} head_above0=$(cut -d' ' -f2 <<<"$E0") head_above1=$(cut -d' ' -f2 <<<"$E1") spine_pos_fixes=$(cut -d' ' -f3 <<<"$E1") shots=$SHOTS/$N"
[ "$SHOTS" -ge "$N" ] || { echo "RESULT FP-EYE FAIL setup: only $SHOTS/$N shots fired $EV log=$LOG"; exit 1; }
if awk -v d="$D" -v l="$LIMIT" 'BEGIN{exit !(d<l && d>-l)}'; then echo "RESULT FP-EYE PASS $EV"
else echo "RESULT FP-EYE FAIL $EV log=$LOG"; fi
