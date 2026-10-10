#!/bin/bash
# fp-zoom-sweep.sh <out dir> <name> <switch|fade> <hat on|off> <xbow|sword>   (WSL; stobe-auto on PATH; Kenshi running windowed)
# Z1 zoom-sweep take, ONE weapon per take (a few minutes, independently rerunnable; Shay 2026-10-10 take discipline):
#   xbow:  crossbow idle / walk / aim (RMB), each with the mouse wheel 5 notches out and back in
#   sword: katana idle / walk / swings, same wheel sweep
# in zoommode <mode>, hat on/off. Fade mode adds a "camera held at 6 dm" segment (wall pull-in case: the band hide must
# show no own body). Preflight (take-preflight.sh) before recording: fresh load of kah-fpxbow, pins, area clean, day +
# clear sky, open ground, weapon ready, crossbow loaded (RMB held until fp_combat loaded>=1, verified); a failed check =
# RESULT ... FAIL setup: <reason>, no retry. If the crossbow is empty again before the aim segment it is reloaded on
# camera under a "Reloading" label.
# Evidence: take-sample.sh (labels vs live fp state, messages, bystanders) judged by takecheck.py with take-rules.txt,
# the lab cursor + open-ground checks on the recorded frames, fp_vm rec dump (<name>.vmrec.txt) + animlab zoomband.
# Env BANDHIDE=0: band hide off (pre-fix fade behaviour, A/B recording for the animlab zoomband check).
# Output in <out dir>: <name>.mp4 .lab .ev.txt .vmrec.txt .whl; last line: RESULT ZOOMSWEEP-<name> PASS|FAIL <evidence>
OUT=$1; N=$2; MODE=${3:-switch}; HAT=${4:-on}; WPN=${5:-xbow}
[ -n "$OUT" ] && [ -n "$N" ] && { [ "$WPN" = xbow ] || [ "$WPN" = sword ]; } || { echo "usage: fp-zoom-sweep.sh <out dir> <name> <switch|fade> <hat on|off> <xbow|sword>"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT"; cd "$OUT" || exit 2
SH=Axima; SPOT="-54190 633 4380"
HARN=/mnt/c/KenshiModding/Kenshi-Automation-Harness; HERE=/mnt/c/KenshiModding/components/KenshiFP; L=$HARN/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
loaded(){ local l; l=$(A fp_combat state | fld loaded); echo "${l:-0}"; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
FIFO=/tmp/kfp-$N.ffin
cleanup(){ [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { echo q >&7 2>/dev/null; wait $FP; }; A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; rm -f "$FIFO"; }
fail(){ cleanup; echo "RESULT ZOOMSWEEP-$N FAIL $*"; exit 1; }
PF_ROW=ZOOMSWEEP-$N; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
keep(){ A inv "$1" | grep -q "\"name\":\"$2\"" || echo "picked up $2: $(A pickup "$1" "$2" radius 60 | cut -c1-50)"; }
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
sweep(){ A fp_camera distance 0 >/dev/null; sleep 0.8
  for w in -120 -120 -120 -120 -120 0 120 120 120 120 0; do [ $w = 0 ] && { sleep 1; continue; }; A fp_camera wheel $w >/dev/null
    echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') wheel $w $(A fp_camera state | grep -o 'target=[0-9.]*\|applied=[0-9.]*\|band_hidden=[0-9]' | tr '\n' ' ')" >> "$N.whl"; sleep "${SL:-1.3}"; done; }
place(){ A teleport $SH $SPOT >/dev/null; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.05 >/dev/null; sleep 1; }
# hold RMB until a bolt is in (fp_combat loaded>=1), release, verify loaded=1 (on camera, labelled)
load_xbow(){ [ "$(loaded)" -ge 1 ] && return 0
  lab "Reloading: RMB held until the bolt is in"
  A fp_keys press rmb 20000 >/dev/null; local e=$((SECONDS+15))
  while [ $SECONDS -lt $e ] && [ "$(loaded)" -lt 1 ]; do sleep 0.3; done
  A fp_keys release rmb >/dev/null; sleep 1.0; [ "$(loaded)" = 1 ]; }
# ---- preflight: fresh load, pins, area clean, day + sky, take spot, hat
A load kah-fpxbow | cut -c1-80; sleep 8
for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done
A speed 1 hold >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take | grep -q -i "ok\|took\|fp\|transferred" || echo "fp_control take: $(A fp_control take | cut -c1-60)"
pf_clean ${SPOT%% *} $(echo $SPOT | cut -d' ' -f3) 3000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2
if [ "$HAT" = off ]; then A unequip $SH "Iron Hat" >/dev/null; sleep 0.5; A pickup Malzin "Iron Hat" near $SH radius 60 now >/dev/null
else A inv $SH | grep -q '"Iron Hat","count":1,"equipped":true' || A pickup $SH "Iron Hat" radius 60 now >/dev/null; fi
A health $SH 100 >/dev/null
hatnow=$(A inv $SH | grep -o '"Iron Hat","count":1,"equipped":[a-z]*' | grep -o 'true\|false')
[ "$HAT" = on ] && [ "$hatnow" != true ] && pf_fail "hat not equipped"
[ "$HAT" = off ] && [ "$hatnow" = true ] && pf_fail "hat still equipped"
# ---- mode + weapon
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A fp_camera zoommode "$MODE" >/dev/null; A fp_camera bandhide "${BANDHIDE:-1}" >/dev/null
A fp_camera state | grep -q "zoom_switch=$([ "$MODE" = switch ] && echo 1 || echo 0)" || pf_fail "zoommode $MODE not active"
[ "$(st)" = ready ] && { A key_inject r tap 120 >/dev/null; waitst holstered 6; }
if [ "$WPN" = xbow ]; then
  A combatmode $SH ranged on >/dev/null
  A inv $SH | grep -q "\"name\":\"Chisa Katana\"" && { A unequip $SH "Chisa Katana" >/dev/null; A inv $SH | grep -q "\"name\":\"Chisa Katana\"" && A transfer $SH Malzin "Chisa Katana" >/dev/null; }
  keep $SH "Oldworld Bow MkI"; A equip $SH "Oldworld Bow MkI" >/dev/null
else
  A combatmode $SH ranged off >/dev/null
  A unequip Malzin "Chisa Katana" >/dev/null; A inv Malzin | grep -q "\"name\":\"Chisa Katana\"" && A transfer Malzin $SH "Chisa Katana" >/dev/null
  keep $SH "Chisa Katana"; A equip $SH "Chisa Katana" >/dev/null
fi
sleep 1; place; pf_ready
cls=$(A fp_vm state | grep -o 'class=[a-z0-9]*' | head -1)
[ "$WPN" = xbow ] && { [ "$cls" = class=ranged ] || [ "$cls" = class=1 ]; } || [ "$WPN" = sword ] || echo "note: $cls"
[ "$WPN" = xbow ] && pf_loaded
place; pf_open 2
echo "setup ok: mode=$MODE hat=$HAT weapon=$WPN loaded=$(loaded) state=$(st)"
# ---- take
: > "$N.lab"; : > "$N.whl"; rm -f "$FIFO"; mkfifo "$FIFO" || pf_fail "mkfifo $FIFO"
"$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 400 -i "title=Kenshi 1.0.65 - x64 (Newland)" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p "$N.mp4" < "$FIFO" & FP=$!
exec 7>"$FIFO"
. $HERE/animlab/take-sample.sh
A fp_vm rec on >/dev/null
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
M="zoommode $MODE, hat $HAT"
if [ "$WPN" = xbow ]; then
  lab "Crossbow idle: mouse wheel out 5 notches, back in, $M"; sweep
  place; sleep 0.5; lab "Crossbow walk: mouse wheel out 5 notches, back in, $M"; A fp_move w 2600 >/dev/null & MP=$!; SL=0.12 sweep; wait $MP
  place; load_xbow || fail "crossbow not loaded before the aim segment (loaded=$(loaded))"
  [ "$(loaded)" = 1 ] || fail "aim: loaded=$(loaded)"
  lab "Crossbow aim (RMB): mouse wheel out 5 notches, back in, $M"; A fp_keys press rmb 20000 >/dev/null; ( sleep 15; A fp_keys press rmb 20000 >/dev/null ) & sleep 0.6; sweep
  lab "Crossbow back to ready (RMB released)"; A fp_keys release rmb >/dev/null; sleep 2
else
  lab "Sword idle: mouse wheel out 5 notches, back in, $M"; sweep
  place; sleep 0.5; lab "Sword walk: mouse wheel out 5 notches, back in, $M"; A fp_move w 2600 >/dev/null & MP=$!; SL=0.12 sweep; wait $MP
  place; lab "Sword swings: mouse wheel out 5 notches, back in, $M"; ( for i in $(seq 1 9); do A fp_keys press lmb 60 >/dev/null; sleep 1.9; done ) & MP=$!; sweep; wait $MP
fi
BAND=""
if [ "$MODE" = fade ]; then
  place; A fp_camera distance 6 >/dev/null; sleep 0.6; lab "Camera held at 6 dm (wall pull-in case): no own body or weapon in view"
  BAND=$(A fp_camera state | grep -o 'applied=[0-9.]*\|band_hidden=[0-9]' | tr '\n' ' '); sleep 2.5; A fp_camera distance 0 >/dev/null; sleep 1
fi
lab end; echo q >&7; exec 7>&-; take_sample_stop; _TS_RUN=; wait $FP; FP=; rm -f "$FIFO"
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-zs-$N.txt"; A fp_vm rec dump "vmrec-zs-$N.txt" >/dev/null; sleep 2; cp "$KDIR/vmrec-zs-$N.txt" "$N.vmrec.txt" 2>/dev/null || echo "note: no vmrec dump"
"$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
CU=$(python3 $L/frames.py cursor "$N.mp4" 2>&1 | tail -1)
OG=$(python3 $L/frames.py openground "$N.mp4" 2>&1 | tail -1)
ZB=$([ -s "$N.vmrec.txt" ] && python3 $L/animlab.py zoomband "$N.vmrec.txt" 2>&1 | grep '^zoomband' | head -1)
WH=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^applied=/){split($i,a,"="); if(a[2]>0.65 && a[2]<16) n++}} END{print n+0}' "$N.whl")
ok=1; for r in "$TC" "$CU" "$OG"; do echo "$r" | grep -q "PASS" || ok=0; done
[ -n "$ZB" ] && { echo "$ZB" | grep -q "PASS" || ok=0; }
[ "$MODE" = fade ] && { echo "$BAND" | grep -q "band_hidden=1" || ok=0; }
echo "RESULT ZOOMSWEEP-$N $([ $ok = 1 ] && echo PASS || echo FAIL) takecheck=[$TC] cursor=[$CU] openground=[$OG] zoomband=[$ZB] in_band_wheel_samples=$WH band6dm=[$BAND] len=$(cat "$N.video-len.txt") log=$OUT/$N.lab"
