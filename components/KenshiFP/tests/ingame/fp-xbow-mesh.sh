#!/usr/bin/env bash
# fp-xbow-mesh.sh [shooter] [target] [out] (WSL, Kenshi in the world on kah-fpxbow): row XBMESH, the FP crossbow is
# rendered whole in every state (Shay 2026-10-10 21:20: only limbs + string in FP, the stock/body gone).
# The stock is the in-hand item's own entity (worn-item map key "hands", Item::mesh); limbs/string/bolt are separate
# entities. Each check reads `fp_gear` (hands entry: mesh non-NULL, visible, at the hand prop bone) + one screenshot.
# Phase A: first draw -> aiming, fired, reloading, ready. Phase B: the filler-row sequence that lost the stock
# (fp_combat off + fp_mode off -> the native sheathe, then fp_mode on + take + fp_combat on re-arms) -> same states.
# Phase D: R holster, then the adapter draws the holstered bow (fp_combat aim) -> same states.
# Zoom 0. Ends with: RESULT XBMESH PASS|FAIL <per-check evidence> (+ shot names for the review sheet).
# dryrun: norec   (fp_gear + screenshots only, no video)
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-mesh}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
# deadlines on `date` (wall clock in game; the dryrun virtual clock stubs date, not bash SECONDS)
now_s() { date +%s; }
waitfor() { local end=$(( $(now_s)+$1 )); while [ "$(now_s)" -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
PF_ROW=XBMESH; . "$(dirname "$0")/take-preflight.sh"
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null; }
trap cleanup EXIT; trap "exit 143" TERM INT HUP   # a killed row (rig-runner kill-step, timeout) still runs cleanup: neutral fp_combat input
BAD=""; EV=""; SHOTS=""
# chk <tag>: hands entry of fp_gear must carry a live, visible stock entity at the hand
chk() { local g h m v d p pv s vs vst vw
  g=$(A fp_gear); h=$(tr '|' '\n' <<<"$g" | grep '^ *hands ' | head -1)
  m=$(fld mesh <<<"$h"); v=$(fld vis <<<"$h"); d=$(fld hand <<<"$h"); p=$(fld parts <<<"$h"); pv=$(fld partsVis <<<"$h")
  s=$(A screenshot "xbm-$1" | grep -oE '[^ ]*\.png' | head -1); SHOTS+=" ${s##*[\/]}"
  # the viewmodel must SHOW the drawn bow too (xbmesh-ok, DCCED30B: phase D hands mesh live at the hand but fp_vm
  # holstered/no arms on screen; the mesh-only check passed it): fp_vm state not holstered/off
  vs=$(A fp_vm state); vst=$(fld state <<<"$vs"); vw=$(fld w <<<"$vs"); vsr=$(fld stretch <<<"$vs"); vls=$(fld Lsh <<<"$vs"); vrs=$(fld Rsh <<<"$vs")
  # C3 gun pin (XBPIN): the bow + bolt sit at the post-IK prop only while the pin runs; xbmesh-v6 (7C886329) B/D aim showed
  # a compact, far, unloaded-looking bow (review). pin mode 35/36 = the XBPIN guard skipped it on a drawn bow.
  local gl pm; gl=$(A fp_vm gun); pm=$(grep -oE '\| pin=[0-9]+ mode=[0-9]+' <<<"$gl" | tail -1 | grep -oE 'mode=[0-9]+'); pm=${pm#mode=}
  EV+=" $1:mesh=${m:-none},vis=${v:--},hand=${d:--},parts=${pv:-0}/${p:-0},vm=${vst:-?}/${vw:-?},st=${vsr:-?},sh=${vls%%,*}/${vrs%%,*},pin=${pm:-?}"
  case "$vst" in ''|holstered|off|lower*) BAD+=" $1(vm=${vst:-?})"; return;; esac
  case "$pm" in 35|36) BAD+=" $1(pin=$pm)"; return;; esac
  # XBDRAW class: skeleton<->world map broken after the adapter draw (arms + bow off screen while the mesh is live):
  # the shoulders in camera numbers come out turned away (left shoulder RIGHT of the right one: D 1.11 vs -1.61; every
  # real ranged state -2.3..-3.5 apart). Stretch/oerr are no discriminator (reload: oerr 8.4, stretch 1.60 normal).
  awk -v l="${vls:-9}" -v r="${vrs:--9}" 'BEGIN{split(l,a,","); split(r,b,","); exit !(a[1] < b[1])}' || { BAD+=" $1(shoulders=${vls%%,*}/${vrs%%,*})"; return; }
  if [ -z "$h" ] || [ -z "$m" ] || [ "$m" = 0000000000000000 ] || [ "$v" != 1 ] || ! awk -v d="${d:-99}" 'BEGIN{exit !(d<1.0)}'; then
    BAD+=" $1"; fi; }
arm() { A select "$SH" >/dev/null; A fp_mode on >/dev/null
  for _ in $(seq 1 10); do sleep 0.5; A fp_state | grep -q 'fp_mode=1' && break; done
  A fp_control take >/dev/null; A fp_camera distance 0 >/dev/null; A fp_combat autoreload 1 >/dev/null
  pf_combat_on || pf_fail "$PF_WHY"
  inp 0 0 0; waitfor 6 armed 1 || pf_fail "adapter never armed (why=$(cs why))"; sleep 1.5; }
states() { local s0
  # an empty bow (save/previous row left it unloaded) auto-reloads on the first aim: ~6 s reload + aim (xbmesh-c: 8 s cut it)
  inp 1 0 0; waitfor 16 shot_ready 1 || pf_fail "$1: never shot_ready (loaded=$(cs ammo) reloading=$(cs reloading) why=$(cs why))"; sleep 0.6; chk "$1-aim"
  s0=$(cs actual_shots); inp 1 1 0; local end=$(( $(now_s)+3 ))
  while [ "$(now_s)" -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && break; sleep 0.1; done
  inp 1 0 0; sleep 0.2; chk "$1-fired"
  if waitfor 6 reloading 1; then sleep 1.0; chk "$1-reload"; else EV+=" $1-reload:not_seen"; BAD+=" $1-reload"; fi
  waitfor 10 reloading 0; inp 0 0 0; sleep 1.2; chk "$1-ready"; }

A status | grep -q phase=world || pf_fail "not in world"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || pf_fail "$SH has no ranged weapon"
pf_day
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null
# xbconfirm4 (83B6F8D3): Axima staggered at A-ready (vm=staggered, pin skipped): the hostile target passive for the row
PV0=$(A combatmode "$TG" | fld passive); A combatmode "$TG" passive on >/dev/null
arm; states A
# phase B: the filler-row cleanup -> setup sequence (fp-manual-*.sh) that left the hands item without its entity
cleanup; A fp_mode off >/dev/null; sleep 8
EV+=" sheathed:wih=$(A fp_combat state | fld wih)"
arm; states B
# phase D: R holster (own sheathe: bow on its back sheath), then fp_combat on + aim = the adapter's own draw of a
# holstered crossbow (drawWeapon with the item's section, kfp-xbow-drawsec) -> same states; deterministic re-arm draw
cleanup; pf_iso >/dev/null
# fp_combat off can already put the bow on its back sheath (xbmesh-c2: manual release -> native sheathe, then the R tap
# DREW it: "R draw weapon ... section='back'" and state=ready): let it settle, R only while it is still in the hands
sleep 3; [ "$(pf_st)" = holstered ] || { A key_inject r tap 120 >/dev/null; pf_waitst holstered 6 || pf_fail "R holster: state=$(pf_st)"; }
EV+=" D-holstered:$(pf_st)"; sleep 1.5
arm; states D
# zoom-25 look at the body after phase D: where the bow and the arms really are (review sheet)
A fp_camera distance 25 >/dev/null; sleep 1.5; s=$(A screenshot "xbm-D-z25" | grep -oE '[^ ]*\.png' | head -1); SHOTS+=" ${s##*[\/]}"
A fp_camera distance 0 >/dev/null
KL=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
EV+=" drawlog=$(grep -a "crossbow draw section=" "$KL" 2>/dev/null | tail -1 | grep -o "section='[^']*' ok=[0-9]" | tr -d "' " )"
case "$PV0" in 1|on|true) ;; *) A combatmode "$TG" passive off >/dev/null;; esac
A protect "$TG" off >/dev/null
if [ -z "$BAD" ]; then echo "RESULT XBMESH PASS$EV shots:$SHOTS"
else echo "RESULT XBMESH FAIL bad=${BAD# }$EV shots:$SHOTS log=$LOG"; fi
