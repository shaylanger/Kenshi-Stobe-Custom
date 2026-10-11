#!/bin/bash
# fp-hand-ab.sh <out dir> [along 0.70] [across 0.85]   (WSL on the 5090; RIG=4080 via rig-env.sh)
# Hand-size A/B for Shay (spec-videos style): the same katana pose/camera filmed twice in one session, LEFT with
# `fp_vm set hand_scale 1 1` (current hand), RIGHT with `fp_vm set hand_scale <along> <across>` (smaller hand; the
# weapon prop is compensated, so it must keep its size and place). Each side: ready 2.5 s, one LMB swing, RMB block
# 2 s, ready 2 s. Zoom 0 at the E6 open-ground spot of kah-fpxbow, daytime, clear sky, area clean, chatter off.
# Needs a KenshiFP build with pending-fixes/kfp-hand-scale.py (`fp_vm set hand_scale` answers "hand_scale along=..").
# Evidence: hand-{A,B}.{mp4,lab,ev.txt,state.txt} + takecheck per side; hand-ab.mp4 = side by side, normal speed then
# 4x slower; the weapon must not move between sides (fp_vm state mp/mf at ready, A vs B, printed).
# Last line: RESULT HAND-AB PASS|FAIL <evidence>   (PASS = both sides recorded, scale taken, takechecks PASS)
for d in /mnt/c /c; do [ -f $d/KenshiModding/tools/automation/rig-env.sh ] && { . $d/KenshiModding/tools/automation/rig-env.sh; break; }; done
OUT=$1; HA=${2:-0.70}; HC=${3:-0.85}; ROW=HAND-AB
[ -n "$OUT" ] || { echo "RESULT $ROW FAIL setup: no out dir"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-$([ "${RIG:-5090}" = 4080 ] && echo rig4080 || echo 5090-operator)}
SH=Axima; SPOT="-54190 633 4380"
HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; L=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
ready(){ [ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }; }
restore(){ A fp_vm set hand_scale 1 1 >/dev/null; A fp_keys release rmb >/dev/null; A chatter on >/dev/null; }
PF_ROW=$ROW; PF_ON_FAIL='restore; [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { echo q >&7 2>/dev/null; wait $FP; }'
. $HERE/tests/ingame/take-preflight.sh
pf_begin "$ROW"
pf_outdir "$OUT"; cd "$OUT" || pf_fail "cd $OUT"
# ---- setup: fresh load, squad pinned out of frame, time, spot, raiders, katana
pf_load   # studio fixture kah-fpstudio where installed, else kah-fpxbow (take-preflight.sh; PF_SAVE=<save> forces one)
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null; A chatter off >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
r=$(A fp_vm set hand_scale 1 1); grep -q 'hand_scale along=' <<<"$r" || pf_fail "KenshiFP has no hand_scale switch (reply: $(cut -c1-80 <<<"$r"))"
pf_rig; pf_display; pf_day
r=$(A teleport $SH $SPOT); grep -q 'moved=1' <<<"$r" || pf_fail "teleport $SH $SPOT: $(cut -c1-100 <<<"$r")"; sleep 2
pf_clean ${SPOT%% *} ${SPOT##* } 3000
A health $SH 100 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.05 >/dev/null; sleep 1
pf_area $SH "Malzin|Tassilo|Shay"
ready; [ "$(st)" = ready ] || pf_fail "katana not ready (state=$(st))"
pf_nofight; sleep 1.5
pf_open 3
. $HERE/animlab/take-sample.sh
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; if type take_mark >/dev/null 2>&1; then take_mark "$*"; fi; }
take(){ # $1 = A|B, $2 $3 = scale
  N=hand-$1
  r=$(A fp_vm set hand_scale $2 $3); grep -q "hand_scale along=" <<<"$r" || { restore; pf_result FAIL "hand_scale $2 $3 not taken: $(cut -c1-80 <<<"$r")"; exit 1; }
  echo "side $1: $r"
  A fp_camera look 3.14 0.05 >/dev/null; ready; sleep 1.5; A fp_vm state > "$N.state.txt"
  : > "$N.lab"; rm -f "/tmp/kfp-$N.ffin"; mkfifo "/tmp/kfp-$N.ffin"
  "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 60 -i "title=${WIN_TITLE:-Kenshi 1.0.65 - x64 (Newland)}" $(venc_args 18 veryfast) "$N.mp4" < "/tmp/kfp-$N.ffin" & FP=$!
  exec 7>"/tmp/kfp-$N.ffin"
  T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
  lab "Katana ready, hand_scale $2 $3"; sleep 2.5
  lab "LMB: swing"; A fp_keys press lmb 60 >/dev/null; sleep 2.6
  lab "RMB held: block"; A fp_keys press rmb 2400 >/dev/null; sleep 2.0
  lab "RMB released: ready"; sleep 2.6
  lab end; echo q >&7; exec 7>&-; take_sample_stop; _TS_RUN=; wait $FP; FP=; rm -f "/tmp/kfp-$N.ffin"
  ( TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
    echo "takecheck $1: $TC"; echo "$TC" > "$N.tc.txt" ) &   # checks run in the background while the next side records
}
take A 1 1
take B "$HA" "$HC"
restore
pf_game_done   # game part over (both sides recorded, hand scale restored): run-batch.sh starts the next row
wait   # background takechecks of both sides
# weapon place at ready, A vs B (must match: prop compensated)
WA=$(grep -o ' mp=[^ ]* mf=[^ ]*' hand-A.state.txt | head -1); WB=$(grep -o ' mp=[^ ]* mf=[^ ]*' hand-B.state.txt | head -1)
# ---- side by side: label each half, normal speed then 4x slower (spec-videos layout)
DA=$("$FFX" -hide_banner -i hand-A.mp4 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}')
DB=$("$FFX" -hide_banner -i hand-B.mp4 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}')
D=$(awk -v a="$DA" -v b="$DB" 'BEGIN{print (a<b?a:b)}')
FONT="C\\:/Windows/Fonts/arial.ttf"
"$FFX" -hide_banner -loglevel error -y -i hand-A.mp4 -i hand-B.mp4 -filter_complex \
 "[0:v]trim=0:$D,setpts=PTS-STARTPTS,scale=960:540,drawtext=fontfile='$FONT':text='LEFT  current hand (1.00 x 1.00)':x=20:y=20:fontsize=30:fontcolor=yellow:box=1:boxcolor=black@0.6[a];\
[1:v]trim=0:$D,setpts=PTS-STARTPTS,scale=960:540,drawtext=fontfile='$FONT':text='RIGHT  smaller hand ($HA along x $HC across)':x=20:y=20:fontsize=30:fontcolor=yellow:box=1:boxcolor=black@0.6[b];\
[a][b]hstack,split[n][s0];[s0]setpts=4*PTS,drawtext=fontfile='$FONT':text='4x slower':x=w-200:y=h-50:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.6[s];[n][s]concat=n=2:v=1" \
 $(venc_args 18 veryfast) hand-ab.mp4 || { pf_result FAIL "compose failed"; exit 1; }
ok=1; for s in A B; do grep -q 'RESULT PASS\|take PASS' hand-$s.tc.txt || ok=0; done
PF_DONE=1; echo "RESULT $ROW $(pf_grade $ok "$(cat hand-A.tc.txt hand-B.tc.txt)") scaleB=$HA,$HC weaponA=[$WA] weaponB=[$WB] takecheckA=[$(cat hand-A.tc.txt)] takecheckB=[$(cat hand-B.tc.txt)] video=$OUT/hand-ab.mp4$(pf_recwarn "$(cat hand-A.tc.txt hand-B.tc.txt)")"
