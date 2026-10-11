#!/usr/bin/env bash
# fp-xbow-drawexp.sh [shooter] [target] [out] (WSL, Kenshi in the world on kah-fpxbow): row XBDEXP, diag for XBMESH
# phase D pin mode 36 (xbconfirm3, 468B6D06: after an R holster + the combat ADAPTER's draw the gun's string/slack/bolt
# nodes hang on the character node -> compact far bow without its bolt; after an R draw they hang on the gun node, pin=1).
# Per variant: R draw + aim (normalize, expect pin=1), R holster, `fp_combat drawexp <mask>`, arm + aim = adapter draw,
# read `fp_vm gun` pin mode while aimed. Masks (kfp-xbow-drawsec XBDEXP): 0 = current, 1 = no g_combat_setup after the
# draw, 2 = ranged combat mode 0 during drawWeapon, 8 = rc state 0 during the draw (xbdexp2 03012F04: 1/2/3/9 all pin 36);
# 32 = no ranged mode/state writes while drawing (xbdexp3 CE098A22: 32/33 pin 36), 64 = the R draw from the controls tick instead of the adapter draw.
# Ends with: RESULT XBDEXP PASS|FAIL m<mask>=pin<mode>/<shot_ready> ...  (PASS = mask 0 reproduces 36 and at least one
# other mask gives pin=1 with shot_ready; the fix candidates are the masks with pin=1).
# dryrun: norec   (state reads only, no video)
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-drawexp}; MASKS=${MASKS:-0 64 96 97}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
now_s() { date +%s; }
waitfor() { local end=$(( $(now_s)+$1 )); while [ "$(now_s)" -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
PF_ROW=XBDEXP; . "$(dirname "$0")/take-preflight.sh"
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; A fp_combat drawexp 0 >/dev/null; }
trap cleanup EXIT; trap "exit 143" TERM INT HUP   # a killed row (rig-runner kill-step, timeout) still runs cleanup: neutral fp_combat input
EV=""; GOOD=""; REPRO=0
arm() { A select "$SH" >/dev/null; A fp_mode on >/dev/null
  for _ in $(seq 1 10); do sleep 0.5; A fp_state | grep -q 'fp_mode=1' && break; done
  A fp_control take >/dev/null; A fp_camera distance 0 >/dev/null; A fp_combat autoreload 1 >/dev/null
  A fp_combat on | grep -q requested || pf_fail "fp_combat on refused"
  inp 0 0 0; sleep 0.5
  # a melee weapon in hands (the AI's combat stance pick): R + unequip it (pf_ranged_inj), then the crossbow arms
  [ "$(cs why)" = melee_in_hands ] && { pf_ranged_inj "$SH" >/dev/null || pf_fail "$PF_WHY"; EV+=" melee_put_away"; }
  waitfor 6 armed 1 || pf_fail "adapter never armed (why=$(cs why))"; sleep 1.0; }
# pin <tag>: aim until shot_ready, read the gun pin mode; echoes "<mode>/<sr>"
pin() { local sr=1 g pm
  inp 1 0 0; waitfor 16 shot_ready 1 || sr=0; sleep 1.0
  g=$(A fp_vm gun); pm=$(grep -oE '\| pin=[0-9]+ mode=[0-9]+' <<<"$g" | tail -1 | grep -oE 'mode=[0-9]+'); pm=${pm#mode=}
  inp 0 0 0; sleep 0.8; echo "${pm:-?}/sr$sr"; }
rholster() { cleanup; pf_iso >/dev/null; sleep 3
  [ "$(pf_st)" = holstered ] || { A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || pf_fail "$1: R holster: state=$(pf_st)"; }
  sleep 1.5; }
rdraw() { A key_inject r tap 120 >/dev/null; local e=$(( $(now_s)+6 )) s=holstered
  while [ "$(now_s)" -lt $e ]; do s=$(pf_st); [ -n "$s" ] && [ "$s" != holstered ] && break; sleep 0.2; done
  [ -n "$s" ] && [ "$s" != holstered ] || pf_fail "$1: R draw: crossbow never in hand (vm=$s)"; sleep 1.5; }

A status | grep -q phase=world || pf_fail "not in world"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || pf_fail "$SH has no ranged weapon"
A fp_combat drawexp 0 | grep -qE 'drawexp=0|drawexp 0 ok' || pf_fail "build without fp_combat drawexp (XBDEXP switch)"
pf_day
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null
# xbdexp3 (CE098A22): mid-row the AI put Axima in combat stance and drew her melee weapon (VM2H cat=5, "R holster cancelled
# (weapon changed)") -> R could not holster. Target passive for the row + every non-crossbow weapon unequipped up front,
# so R/the adapter only ever see the crossbow (kah-* fixture copy is reloaded per list).
PV0=$(A combatmode "$TG" | fld passive); A combatmode "$TG" passive on >/dev/null
BOW=$(A rangedinfo "$SH" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')
while IFS= read -r w; do [ -n "$w" ] && { A unequip "$SH" "$w" >/dev/null; EV+=" unequipped=${w// /_}"; }; done <<<"$(A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOW:-@@}")"
arm; EV+=" init=pin$(pin)"   # FP mode + control first (R needs them), as fp-xbow-drawdiag.sh
for m in $MASKS; do
  rholster "n$m"; rdraw "n$m"; arm; n=$(pin)          # normalize: R draw (expect pin=1)
  rholster "m$m"; A fp_combat drawexp "$m" >/dev/null; arm; r=$(pin); A fp_combat drawexp 0 >/dev/null
  EV+=" m$m=pin${r}(norm=${n%%/*})"
  [ "$m" = 0 ] && [ "${r%%/*}" = 36 ] && REPRO=1
  [ "$m" != 0 ] && [ "$r" = "1/sr1" ] && GOOD+=" $m"
done
KL=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
EV+=" drawlog=$(grep -a 'XBDEXP draw' "$KL" 2>/dev/null | tail -5 | grep -oE 'mask=[0-9]+ mode0=[0-9]+ state0=-?[0-9]+' | tr ' ' ':' | tr '\n' ',')"
pf_game_done
case "$PV0" in 1|on|true) ;; *) A combatmode "$TG" passive off >/dev/null;; esac
A protect "$TG" off >/dev/null
if [ "$REPRO" = 1 ] && [ -n "$GOOD" ]; then echo "RESULT XBDEXP PASS fix_masks=${GOOD# }$EV"
else echo "RESULT XBDEXP FAIL repro=$REPRO fix_masks=${GOOD:-none}$EV log=$LOG"; fi
