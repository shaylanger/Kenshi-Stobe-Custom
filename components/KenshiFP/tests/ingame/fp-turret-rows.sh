#!/bin/bash
# fp-turret-rows.sh <row T2|T3|T5> <out dir> [shooter Axima]   (WSL on the 5090, Git Bash on the 4080: RIG=5090|4080)
# NON-FIRING FP turret confirm rows on kah-fpturret-e (launch: kah-fpturret-e), no recording (# gfx: low lists OK).
# NOTHING here fires the turret (no LMB, no fp_combat input fire): turret shots are crash-quarantined until the crossbow
# TDR confirm is clean (turret-fp 2026-10-11).
#   T2  aim: seated + powered, look left / right / up / down -> TurretBuilding cur_dir yaw follows the camera (dx sign
#       flips, |change| >= 0.3), aim_valid=1, aim_err_deg <= 15 after settling.
#   T3  reload without firing: `fp_turret unload` (patch kfp-turret-unload) empties the gun -> reload starts
#       (reload_left > 0) -> ammo 1/1 within reload_max + 4 s, reloads +1; power cut pauses it (reload_left frozen).
#   T5  R while seated: R (key_inject, the real key path) -> r_ignored +1, still on=1, HUD not drawn (no personal
#       crossbow); then W leaves the turret (on=0, leaves +1, HUD holstered).
# Prints exactly one line: RESULT TUR-<row> PASS|FAIL <evidence>
for d in /mnt/c /c; do [ -f $d/KenshiModding/tools/automation/rig-env.sh ] && { . $d/KenshiModding/tools/automation/rig-env.sh; break; }; done
R=$1; OUT=$2; SH=${3:-Axima}; ROW=TUR-$R
case "$R" in T2|T3|T5) ;; *) echo "RESULT $ROW FAIL setup: row must be T2|T3|T5 (usage: fp-turret-rows.sh <row> <out> [shooter])"; exit 2;; esac
[ -n "$OUT" ] && mkdir -p "$OUT" && cd "$OUT" || { echo "RESULT $ROW FAIL setup: out dir '$OUT' not usable"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-$([ "${RIG:-5090}" = 4080 ] && echo rig4080 || echo kfp-fixer)}
SAVE=${TURRET_SAVE:-kah-fpturret-e}; TX=-54055; TZ=7300
LOG=$PWD/$R.log; : > "$LOG"
A(){ stobe-auto "$@" </dev/null 2>&1; }
ft(){ A fp_turret | tr -d '\r' | tr ' ' '\n' | grep -E "^(on|why|ammo|reload_left|reload_max|aim_valid|cur_dir|aim_err_deg|shots|reloads|r_ignored|draw_refused|enters|leaves)=" | tr '\n' ' '; }
fv(){ ft | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2; }
say(){ echo "$*" >> "$LOG"; }
done_(){ A chatter on >/dev/null; echo "RESULT $ROW $1 $2 log=$LOG"; exit 0; }
fail(){ A chatter on >/dev/null; echo "RESULT $ROW FAIL setup: $* log=$LOG"; exit 1; }

# ---- setup: fixture reload, squad parked + KO, manual combat on (the turret module runs in its tick), turret powered
A fp_camera distance 0 >/dev/null
A load "$SAVE" | cut -c1-100 >> "$LOG"
for i in $(seq 1 60); do sleep 3; A status | grep -q "phase=ingame\|phase=world\|in_game" && break; done
A wait-world | tail -1 | cut -c1-100 >> "$LOG"
A input_isolation status | grep -q "isolation=on" || A input_isolation on >/dev/null
A input_isolation status | grep -q "isolation=on" || fail "input isolation would not turn on (key_inject needs it)"
A chatter off >/dev/null
A pin Malzin at -53900 650 4800 >/dev/null; A pin Tassilo at -53940 650 4800 >/dev/null; A pin Shay at -53980 650 4800 >/dev/null
sleep 2; for n in Malzin Shay; do A ko $n 900 >/dev/null; done
A select $SH >/dev/null; A fp_control take >/dev/null
A fp_combat input 0 0 0 >/dev/null; A fp_combat on >/dev/null; sleep 0.5
A fp_combat state | grep -q "enabled=1" || fail "manual combat off ($(A fp_combat state | grep -o 'enabled=[^ ]* fault=[^ ]*'))"
A power 'Harpoon Turret' on radius 3000 >/dev/null; A power 'Harpoon Turret' supply radius 3000 | grep -o "has_power=[^ ]*" >> "$LOG"
A fp_move w 1200 >/dev/null; sleep 2; A teleport $SH $TX 690 $TZ >/dev/null; sleep 2
A fp_combat physical >/dev/null; A fp_camera look 0.22 -0.075 >/dev/null
A order $SH USE_TURRET building "Harpoon Turret" >/dev/null
for i in $(seq 1 30); do [ "$(fv on)" = 1 ] && break; sleep 0.5; done
say "seated: $(ft)"; [ "$(fv on)" = 1 ] || fail "not seated 15 s after USE_TURRET ($(ft | cut -c1-80))"
for i in $(seq 1 24); do [ "$(fv ammo)" = 1/1 ] && break; sleep 0.5; done
ft | grep -q "why=no_power\|power" && say "power state: $(A turret 'Harpoon Turret' radius 3000 | grep -o 'power[^ ]*' | head -2 | tr '\n' ' ')"

case $R in
T2)
  look(){ A fp_camera look $1 $2 >/dev/null; sleep 2.5; c=$(fv cur_dir); e=$(fv aim_err_deg); v=$(fv aim_valid); say "look $1 $2: cur_dir=$c err=$e valid=$v"; echo "$c $e $v"; }
  read cl el vl < <(look 0.63 -0.07); read cr er vr < <(look -0.17 -0.07)
  read cu eu vu < <(look 0.22 0.20); read cd ed vd < <(look 0.22 -0.20)
  [ "$(fv on)" = 1 ] || done_ FAIL "left the turret during aim ($(ft | cut -c1-80))"
  V=$(awk -v a="$cl" -v b="$cr" -v el="$el" -v er="$er" 'BEGIN{split(a,p,",");split(b,q,",");dx=q[1]-p[1];dz=q[3]-p[3];ch=sqrt(dx*dx+dz*dz);
     ok=(ch>=0.3 && (el+0<=15) && (er+0<=15));printf "%s change=%.3f", ok?"PASS":"FAIL", ch}')
  [ "$vl$vr$vu$vd" = 1111 ] || V="FAIL aim_valid=$vl$vr$vu$vd ${V#* }"
  done_ ${V%% *} "${V#* } left=$cl right=$cr err_l=$el err_r=$er err_up=$eu err_down=$ed (yaw only natively)";;
T3)
  r0=$(fv reloads); a0=$(fv ammo)
  U=$(A fp_turret unload); say "unload: $U"
  echo "$U" | grep -q "turret unload ammo" || fail "fp_turret unload not in this build (needs kfp-turret-unload): $U"
  sleep 0.5; rl=$(fv reload_left); mx=$(fv reload_max); say "after unload: $(ft)"
  awk -v r="$rl" 'BEGIN{exit !(r>0)}' || done_ FAIL "no reload started after unload (ammo=$(fv ammo) reload_left=$rl)"
  # power cut pauses the reload (native: no power = no reload)
  sleep 1; A power 'Harpoon Turret' unsupply radius 3000 >/dev/null; A power 'Harpoon Turret' off radius 3000 >/dev/null; sleep 1
  p1=$(fv reload_left); sleep 2; p2=$(fv reload_left); say "power off: reload_left $p1 -> $p2 ($(fv why))"
  A power 'Harpoon Turret' on radius 3000 >/dev/null; A power 'Harpoon Turret' supply radius 3000 >/dev/null
  PZ=$(awk -v a="$p1" -v b="$p2" 'BEGIN{print (a==b)?"paused":"ran"}')
  t0=$SECONDS; lim=$(awk -v m="$mx" 'BEGIN{printf "%d", m+5}')
  while [ $((SECONDS-t0)) -lt $lim ]; do [ "$(fv ammo)" = 1/1 ] && break; sleep 0.25; done
  dt=$((SECONDS-t0)); r1=$(fv reloads); a1=$(fv ammo); say "end: $(ft) shots=$(fv shots)"
  [ "$(fv shots)" = 0 ] || done_ FAIL "a shot was counted in a no-fire row (shots=$(fv shots))"
  if [ "$a1" = 1/1 ] && [ "$r1" -gt "$r0" ] && [ "$PZ" = paused ]; then done_ PASS "ammo $a0 -> 0 (unload) -> $a1 in ~${dt}s after power back (reload_max ${mx}s), reloads $r0 -> $r1, power cut paused it ($p1 -> $p2), no shot"
  else done_ FAIL "ammo=$a1 reloads $r0 -> $r1 power-cut=$PZ ($p1 -> $p2) after ${dt}s (reload_max $mx)"; fi;;
T5)
  i0=$(fv r_ignored); l0=$(fv leaves)
  A key_inject r tap 120 >/dev/null; sleep 1.5
  i1=$(fv r_ignored); on=$(fv on); hud=$(A fp_keys state | grep -o 'hud_text=[^ ]*'); vm=$(A fp_keys state | grep -o 'vm_state=[^ ]*\|drawn=[^ ]*' | head -2 | tr '\n' ' ')
  say "after R: $(ft) $hud $vm"
  A fp_move w 500 >/dev/null; for i in $(seq 1 20); do [ "$(fv on)" = 1 ] || break; sleep 0.2; done; sleep 1
  l1=$(fv leaves); on2=$(fv on); hud2=$(A fp_keys state | grep -o 'hud_text=[^ ]*'); say "after W: $(ft) $hud2"
  ok=1; [ "$i1" -gt "$i0" ] || ok=0; [ "$on" = 1 ] || ok=0; echo "$hud" | grep -qi "drawn\|aim\|ready" && ok=0
  [ "$on2" = 0 ] && [ "$l1" -gt "$l0" ] || ok=0; echo "$hud2" | grep -q "holstered" || ok=0
  done_ $([ $ok = 1 ] && echo PASS || echo FAIL) "R: r_ignored $i0 -> $i1, on=$on $hud; W: on=$on2 leaves $l0 -> $l1 $hud2";;
esac
