#!/usr/bin/env bash
# fp-xbow-aiswap.sh: row XSW, decisive repro of the R05/R06 failure (xbow-escalate 2026-10-11, 4080 lists 110/115):
# with the crossbow already in hands and the aim held at a close hostile, the AI must not swap crossbow -> melee
# (KenshiFP.log `[aim] suppressed AI sheathe (x1)` then `[combat] XBWIH melee_in_hands`, fp_combat why=melee_in_hands,
# draw_hook=0: the drawWeapon guard was not installed; fix pending-fixes/kfp-xbow-drawguard.py).
# Holds the aim for XSW_SECS (default 60) with the target pinned at XSW_DIST (default 15) facing the shooter, samples
# why/wih every second. PASS = adapter kept the crossbow (why=ok) the whole hold; FAIL names the second it swapped and
# draw_hook at the start (0 = guard not installed = the bug's precondition).
# Usage: fp-xbow-aiswap.sh [shooter] [target] [outdir]. Ends with one `RESULT $ROW PASS|FAIL <evidence>` line.
# Run on kah-fpxbow (Axima = crossbow user, Skaera = hostile Hungry Bandit). No recording (gfx low list).
ROW=${XSW_ROW:-XSW}; SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-aiswap}; SECS=${XSW_SECS:-60}; DIST=${XSW_DIST:-15}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
setup_fail() { echo "RESULT $ROW FAIL setup: $1 log=$LOG"; cleanup; exit 1; }
. "$(dirname "$0")/take-preflight.sh"; PF_A() { A "$@"; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT; trap "exit 143" TERM INT HUP

# ---- setup (no retries) ----
A status | grep -q phase=world || setup_fail "not in world"
A where "$SH" | grep -q 'pos=' || setup_fail "shooter $SH not found"
A where "$TG" | grep -q 'pos=' || setup_fail "target $TG not found"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
A protect "$TG" on >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
read -r sx sz <<<"$(A where "$SH" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
read -r tx tz <<<"$(A where "$TG" | grep -o 'pos=[^ ]*' | cut -d= -f2 | awk -F, '{print $1, $3}')"
YAW=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" 'BEGIN{printf "%.4f", atan2(c-a, d-b)}')
A fp_camera look "$YAW" 0.02 >/dev/null
pf_combat_on || setup_fail "$PF_WHY"
inp 0 0 0; pf_ranged_inj "$SH" || setup_fail "$PF_WHY"
[ "$(cs actor)" != 0 ] || setup_fail "adapter has no actor"
HOOK0=$(cs draw_hook); W0=$(cs wih)

# ---- XSW: hold the aim, sample every second ----
inp 1 0 0; waitfor 5 aimed 1 || setup_fail "not aimed after 5 s (why=$(cs why))"
# XSW_SHOOT=1: fire one bolt at the target first (110 R03: the swap came after R02/R04 shots, with the fixture's turret
# firing at the target; XSW without a shot kept the crossbow 2/2 at 15 and 8, so combat is the trigger)
SHOTS=0; if [ "${XSW_SHOOT:-0}" = 1 ]; then
  waitfor 10 shot_ready 1 || setup_fail "not shot_ready (why=$(cs why) ammo=$(cs ammo))"
  s0=$(cs actual_shots); inp 1 1 0; sleep 0.5; inp 1 0 0; SHOTS=$(( $(cs actual_shots) - s0 ))
  [ "$SHOTS" -ge 1 ] || setup_fail "the trigger did not fire (actual_shots $s0 -> $(cs actual_shots))"; fi
SW=-1; SWWHY=; t=0
while [ $t -lt "$SECS" ]; do
  sleep 1; t=$((t+1)); s=$(A fp_combat state); y=$(fld why <<<"$s"); w=$(fld wih <<<"$s")
  case "$y" in ok|reloading|drawing) ;; *) SW=$t; SWWHY="why=$y wih=$w (start wih=$W0)"; break;; esac
done
HOOK1=$(cs draw_hook); REF=$(cs draw_refused)
inp 0 0 0
pf_game_done 2>/dev/null || true
ev="hold=${SECS}s target=$TG dist=$DIST shots_first=$SHOTS draw_hook start=$HOOK0 end=$HOOK1 draw_refused=$REF"
if [ "$SW" = -1 ]; then echo "RESULT $ROW PASS $ev: crossbow kept the whole hold (why=ok) log=$LOG"
else echo "RESULT $ROW FAIL $ev: AI swapped at ${SW}s: $SWWHY log=$LOG"; fi
