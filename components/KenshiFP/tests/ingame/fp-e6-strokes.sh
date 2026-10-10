#!/bin/bash
# fp-e6-strokes.sh <out dir> <name> [strokes "0 1 2"] [reps 2]   (WSL; stobe-auto on PATH; Kenshi running windowed)
# E6 review take: katana drawn at zoom 0 on open ground (kah-fpxbow take spot, daytime, clear sky), each scripted stroke
# forced in turn (`fp_vm set stroke n`) and swung <reps> times under a "Stroke n: <name>" label; the stroke mask is
# restored to the default 0x1 afterwards. Evidence: take-sample.sh + takecheck.py, fp_vm rec dump judged by the
# animlab per stroke (inline, metrics/arc, churn, blade) and `stroke --overhead 2`.
# Output in <out dir>: <name>.mp4 .lab .ev.txt .vmrec.txt .lab.txt; last line: RESULT E6-<name> PASS|FAIL <evidence>
OUT=$1; N=$2; STROKES=${3:-0 1 2}; REPS=${4:-2}
[ -n "$OUT" ] && [ -n "$N" ] || { echo "usage: fp-e6-strokes.sh <out dir> <name> [strokes] [reps]"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT"; cd "$OUT" || exit 2
SH=Axima; SPOT="-54190 633 4380"
HARN=/mnt/c/KenshiModding/Kenshi-Automation-Harness; HERE=/mnt/c/KenshiModding/components/KenshiFP; L=$HARN/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi; SHOTS=$KDIR/mods/AutomationHarness/shots
SNAME=(diagonal backhand overhead rising)
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
fail(){ echo "RESULT E6-$N FAIL $*"; A fp_vm set stroke -1 >/dev/null; A fp_vm set strokes 1 >/dev/null; [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { echo q >&7 2>/dev/null; wait $FP; }; exit 1; }
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
ready(){ [ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }; }
# ---- setup: fresh load, pins, daytime, take spot, katana, hostiles, sky
A load kah-fpxbow | cut -c1-80; sleep 8
for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
h=$(A time | grep -o 'time=[0-9]*'); h=$((10#${h#time=}))
if [ $h -lt 10 ] || [ $h -gt 13 ]; then A speed 50 hold >/dev/null; for i in $(seq 1 200); do sleep 2; h=$(A time | grep -o 'time=[0-9]*'); h=$((10#${h#time=})); [ $h -ge 10 ] && [ $h -le 13 ] && break; done; A speed 1 hold >/dev/null; fi
A teleport $SH $SPOT >/dev/null; sleep 2
for s in $(A chars 5000 | tr '|' '\n' | grep -E "Bandits|Outlaws|Hungry|Bandit" | grep -v " KO\| DEAD" | grep -o "#[0-9]*/[0-9]*"); do A kill "$s" >/dev/null; done
for c in $SH Malzin; do A health $c 100 >/dev/null; done
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 0 0.05 >/dev/null; sleep 1; A screenshot e6-skyck >/dev/null
sky=$("$FFX" -hide_banner -loglevel error -y -i "$(wslpath -w "$SHOTS/e6-skyck.png")" -vf "crop=1600:120:0:30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | awk '{print ($3 > $1+25 ? "clear" : "hazy")}')
[ "$sky" = clear ] || fail "setup: sky $sky"
A fp_camera look 3.14 0.05 >/dev/null; ready; [ "$(st)" = ready ] || fail "setup: katana not ready (state=$(st))"
A fp_vm state | grep -q 'class=melee\|class=0' || echo "note: $(A fp_vm state | grep -o 'class=[a-z0-9]*' | head -1)"
A fp_vm set strokes 15 >/dev/null
# ---- take
: > "$N.lab"; rm -f "/tmp/kfp-$N.ffin"; mkfifo "/tmp/kfp-$N.ffin"
"$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 300 -i "title=Kenshi 1.0.65 - x64 (Newland)" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$N.mp4" < "/tmp/kfp-$N.ffin" & FP=$!
exec 7>"/tmp/kfp-$N.ffin"
. $HERE/animlab/take-sample.sh
A fp_vm rec on >/dev/null
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
lab "Katana ready, zoom 0"; sleep 1.5
for s in $STROKES; do
  A fp_vm set stroke $s >/dev/null
  lab "Stroke $s: ${SNAME[$s]} (LMB) x$REPS"
  for r in $(seq 1 $REPS); do A fp_keys press lmb 60 >/dev/null; sleep 2.4; done
done
A fp_vm set stroke -1 >/dev/null; A fp_vm set strokes 1 >/dev/null; sleep 0.5
lab end; echo q >&7; exec 7>&-; take_sample_stop; wait $FP; FP=
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-e6-$N.txt"; A fp_vm rec dump "vmrec-e6-$N.txt" >/dev/null; sleep 2; cp "$KDIR/vmrec-e6-$N.txt" "$N.vmrec.txt" || fail "no vmrec dump"
"$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
ok=1; echo "$TC" | grep -q "RESULT PASS" || ok=0
: > "$N.lab.txt"
for s in $STROKES; do for c in inline metrics churn blade; do
  r=$(python3 $L/animlab.py --only-stroke $s $c "$N.vmrec.txt" 2>&1 | grep -E "^(inline|arc|churn|blade) " | head -1)
  echo "stroke $s $r" >> "$N.lab.txt"
  # stroke 0 blade snap/seen = documented baseline exception (approved stroke, keys untouched)
  [ "$s" = 0 ] && [ "${r%% *}" = blade ] && continue
  echo "$r" | grep -q " PASS" || ok=0
done; done
SK=$(python3 $L/animlab.py stroke --overhead 2 "$N.vmrec.txt" 2>&1 | grep '^stroke ' | head -1); echo "$SK" >> "$N.lab.txt"; echo "$SK" | grep -q "^stroke PASS" || ok=0
SW=$(grep -o "\[vm\] swing #[0-9]* stroke [0-9]" $KDIR/KenshiFP.log | tail -$(( $(echo $STROKES | wc -w) * REPS )) | awk '{print $NF}' | tr '\n' ',')
echo "RESULT E6-$N $([ $ok = 1 ] && echo PASS || echo FAIL) takecheck=[$TC] strokes_logged=$SW $(grep -c FAIL "$N.lab.txt") lab FAILs (see $OUT/$N.lab.txt) len=$(cat "$N.video-len.txt")"
