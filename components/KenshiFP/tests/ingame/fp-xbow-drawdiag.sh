#!/usr/bin/env bash
# fp-xbow-drawdiag.sh [shooter] [target] [out] (WSL, Kenshi in the world on kah-fpxbow): row XBDRAW, diag for the
# invisible FP crossbow after the combat adapter draws a holstered bow (XBMESH phase D: no arms/bow on screen,
# fp_vm stretch maxed 1.60,3.00, X1 map residual ~25 after every "[combat] crossbow draw", ~0 after native draws).
# Snapshots (fp_vm state stretch + shoulder/wrist camera numbers, fp_vm bones Spine local quats) while aiming after:
#   N  = the loaded-drawn bow (native draw at load), R = R holster + R draw, D = R holster + adapter draw,
#   DR = R holster + R draw after D (does the native path recover it?).
# Ends with: RESULT XBDRAW PASS|FAIL <per-phase stretch/spine evidence>  (PASS = in every phase the shoulders in camera
# numbers keep their sides (Lsh.x < Rsh.x; broken D: 1.11 vs -1.61 = map turned away); FAIL names the phases that didn't).
# dryrun: norec   (state reads only, no video)
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-drawdiag}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
now_s() { date +%s; }
waitfor() { local end=$(( $(now_s)+$1 )); while [ "$(now_s)" -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
PF_ROW=XBDRAW; . "$(dirname "$0")/take-preflight.sh"
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; }
trap cleanup EXIT
EV=""; BAD=""
arm() { A select "$SH" >/dev/null; A fp_mode on >/dev/null
  for _ in $(seq 1 10); do sleep 0.5; A fp_state | grep -q 'fp_mode=1' && break; done
  A fp_control take >/dev/null; A fp_camera distance 0 >/dev/null; A fp_combat autoreload 1 >/dev/null
  pf_combat_on || pf_fail "$PF_WHY"
  inp 0 0 0; waitfor 6 armed 1 || pf_fail "adapter never armed (why=$(cs why))"; sleep 1.0; }
# snap <tag>: aim, wait shot_ready, read the viewmodel geometry + spine locals
snap() { local vs st sp
  inp 1 0 0; waitfor 16 shot_ready 1 || { EV+=" $1:no_shot_ready(why=$(cs why))"; BAD+=" $1"; inp 0 0 0; return; }
  sleep 1.0; A fp_vm gun >/dev/null; vs=$(A fp_vm state)
  st=$(fld stretch <<<"$vs"); sp=$(A fp_vm bones Spine | tr '|' '\n' | grep -oE 'Spine[0-9]? q=[^ ]*' | tr ' ' ':' | tr '\n' ';')
  EV+=" $1:vm=$(fld state <<<"$vs")/stretch=$st/Lsh=$(fld Lsh <<<"$vs")/Rsh=$(fld Rsh <<<"$vs")/Rwr=$(fld Rwr <<<"$vs")/oerr=$(fld oerr <<<"$vs")/spine=${sp%;}"
  awk -v l="$(fld Lsh <<<"$vs")" -v r="$(fld Rsh <<<"$vs")" 'BEGIN{if(l==""||r=="") exit 1; split(l,a,","); split(r,b,","); exit !(a[1] < b[1])}' || BAD+=" $1"
  inp 0 0 0; sleep 0.8; }
rholster() { cleanup; pf_iso >/dev/null; sleep 3
  [ "$(pf_st)" = holstered ] || { A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || pf_fail "$1: R holster: state=$(pf_st)"; }
  sleep 1.5; }
rdraw() { A key_inject r tap 120 >/dev/null; local e=$(( $(now_s)+6 )) s=holstered
  while [ "$(now_s)" -lt $e ]; do s=$(pf_st); [ -n "$s" ] && [ "$s" != holstered ] && break; sleep 0.2; done
  [ -n "$s" ] && [ "$s" != holstered ] || pf_fail "$1: R draw: crossbow never in hand (vm=$s)"; sleep 1.5; }

A status | grep -q phase=world || pf_fail "not in world"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || pf_fail "$SH has no ranged weapon"
pf_day
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null
arm; snap N
rholster R; rdraw R; arm; snap R
rholster D; arm; snap D
# pin test: the C3 gun pin moves the node above the string entity every frame; with boltpin 0 does the broken D state recover?
A fp_vm set boltpin 0 >/dev/null; sleep 1.0; snap D0; A fp_vm set boltpin 1 >/dev/null
rholster DR; rdraw DR; arm; snap DR
KL=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
EV+=" x1res=$(grep -a 'X1 fp' "$KL" 2>/dev/null | tail -4 | grep -o 'res=[0-9.]*' | cut -d= -f2 | tr '\n' ',' )"
pf_game_done
A protect "$TG" off >/dev/null
if [ -z "$BAD" ]; then echo "RESULT XBDRAW PASS$EV"
else echo "RESULT XBDRAW FAIL bad=${BAD# }$EV log=$LOG"; fi
