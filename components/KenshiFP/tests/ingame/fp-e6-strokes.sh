#!/bin/bash
# fp-e6-strokes.sh <out dir> <name> [strokes "0 1 2"] [reps 2]   (WSL; stobe-auto on PATH; Kenshi running windowed)
# E6 review take: katana drawn at zoom 0 on open ground (kah-fpxbow take spot, daytime, clear sky), each scripted stroke
# forced in turn (`fp_vm set stroke n`) and swung <reps> times under a "Stroke n: <name>" label (strokes may be given
# comma-separated, "0,1,2,3": run-batch passes no quotes). CYCLE=<n> first swings n times with NO force and the game's own
# stroke mask (shipped behaviour: `[vm] swing #k stroke s (mask ..)` must cycle; CYCLE_EXPECT=0,1,2,3 = exactly these strokes, any order: the cycle position survives a reload).
# The stroke mask itself is never changed (force only overrides it; was set to 15 and "restored" to 0x1, which undid
# the shipped default).
# Evidence: take-sample.sh + takecheck.py, fp_vm rec dump judged by the
# animlab per stroke (inline, metrics/arc, churn, blade) and `stroke --overhead 2`.
# Output in <out dir>: <name>.mp4 .lab .ev.txt .vmrec.txt .lab.txt; last line: RESULT E6-<name> PASS|FAIL <evidence>
OUT=$1; N=$2; STROKES=${3:-0 1 2}; STROKES=${STROKES//,/ }; REPS=${4:-2}; CYCLE=${CYCLE:-0}; CYCLE_EXPECT=${CYCLE_EXPECT:-}
case "$STROKES" in *[!0-9[:space:]]*|"") echo "RESULT E6-$N FAIL setup: strokes '$STROKES' not a digit list (run-batch passes quotes literally: kfx-b7)"; exit 2;; esac
[ -n "$OUT" ] && [ -n "$N" ] || { echo "usage: fp-e6-strokes.sh <out dir> <name> [strokes] [reps]"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT E6-$N FAIL setup: out dir $OUT not usable"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"
HARN=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness; HERE=${CR:-/mnt/c}/KenshiModding/components/KenshiFP; L=$HARN/tools/animlab
FFX=${FFX:-${CR:-/mnt/c}/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; SHOTS=$KDIR/mods/AutomationHarness/shots
SNAME=(diagonal backhand overhead rising)
A(){ stobe-auto "$@" </dev/null 2>&1; }
fld(){ grep -o " $1=[^ ]*" | head -1 | cut -d= -f2; }
st(){ A fp_vm state | fld state; }
waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
fail(){ PF_DONE=1; echo "RESULT E6-$N FAIL $*"; A fp_vm set stroke -1 >/dev/null; A chatter on >/dev/null; [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { echo q >&7 2>/dev/null; [ -n "$E6_PIPE" ] && touch "$N.stop"; wait $FP; }; exit 1; }
PF_ROW=E6-$N; PF_ON_FAIL='A fp_vm set stroke -1 >/dev/null; [ -n "$_TS_RUN" ] \&\& take_sample_stop'; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"   # RESULT guard (shared preflight: take-preflight.sh)
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; if type take_mark >/dev/null 2>&1; then take_mark "$*"; fi; }
ready(){ [ "$(st)" = ready ] || { [ "$(st)" = holstered ] || { A key_inject r tap 120 >/dev/null; waitst holstered 6; }; A key_inject r tap 120 >/dev/null; waitst ready 6; }; }
# ---- setup: fresh load, pins, daytime, take spot, katana, hostiles, sky
pf_load   # studio fixture kah-fpstudio where installed, else kah-fpxbow (take-preflight.sh; PF_SAVE=<save> forces one)
A speed 1 hold >/dev/null; A kill "Hungry Bandit" >/dev/null; A chatter off >/dev/null   # no NPC bark text (takecheck overlay)
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
pf_clean -54190 4380 6000   # hostiles near the spot (shared preflight; was a hand-rolled bandit kill)
pf_day       # verified daytime (was a hand-rolled speed-50 loop with no final check)
A teleport $SH $SPOT >/dev/null; sleep 2
for c in $SH Malzin; do A health $c 100 >/dev/null; done
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A inv $SH | grep -q '"name":"Chisa Katana"' || { A unequip Malzin "Chisa Katana" >/dev/null; A transfer Malzin $SH "Chisa Katana" >/dev/null; A pickup $SH "Chisa Katana" radius 80 >/dev/null; }
A equip $SH "Chisa Katana" >/dev/null; sleep 1
# crash safety (2026-10-11 BSOD: every TDR was on a crossbow shot/reload frame): no crossbow equipped on anyone in the scene
for c in $SH Malzin Tassilo Shay; do A inv $c | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -iE 'bow|toothpick|harpoon|eagle' | sort -u | while read -r b; do A unequip $c "$b" >/dev/null; done; done; sleep 1
for c in $SH Malzin Tassilo Shay; do A inv $c | grep -o '"name":"[^"]*","equipped":true' | grep -iqE 'bow|toothpick|harpoon|eagle' && fail "setup: crossbow still equipped on $c (crash-safety quarantine)"; done
A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 0 0.05 >/dev/null; sleep 1; A screenshot e6-skyck >/dev/null
sky=$("$FFX" -hide_banner -loglevel error -y -i "$(wslpath -w "$SHOTS/e6-skyck.png")" -vf "crop=1600:120:0:30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | awk '{print ($3 > $1+25 ? "clear" : "hazy")}')
[ "$sky" = clear ] || fail "setup: sky $sky"
A fp_camera look 3.14 0.05 >/dev/null; pf_iso; ready; [ "$(st)" = ready ] || fail "setup: katana not ready (state=$(st))"
cl_=$(A fp_vm state | grep -o "class=[a-z0-9]*" | head -1); case "$cl_" in *xbow*|*ranged*|*bow*) A key_inject r tap 120 >/dev/null; fail "setup: drawn weapon $cl_ (crash-safety: sword only)";; esac; echo "note: $cl_"
pf_nofight; pf_open 2   # cursor parked in the sky + open ground/overlay check before filming (op-b8 e6r7: cover:ui_state/near/msgs)
# ---- take
: > "$N.lab"; rm -f "/tmp/kfp-$N.ffin"; mkfifo "/tmp/kfp-$N.ffin"
# 4080 (Git Bash): a native ffmpeg never reads "q" from an MSYS fifo -> stop it through a plain pipe (fp-zoom-sweep.sh ZS_PIPE)
E6_PIPE=""; [ "${RIG:-5090}" = 4080 ] && { E6_PIPE=1; rm -f "$N.stop"; }
if [ -n "$E6_PIPE" ]; then ( i=0; while [ ! -f "$N.stop" ] && [ $i -lt 3100 ]; do sleep 0.1; i=$((i+1)); done; echo q ) | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 300 -i "title=Kenshi 1.0.65 - x64 (Newland)" $(venc_args 18 veryfast) "$N.mp4" & FP=$!
  exec 7>/dev/null
else "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 300 -i "title=Kenshi 1.0.65 - x64 (Newland)" $(venc_args 18 veryfast) "$N.mp4" < "/tmp/kfp-$N.ffin" & FP=$!
  exec 7>"/tmp/kfp-$N.ffin"; fi
. $HERE/animlab/take-sample.sh
A fp_vm rec on >/dev/null
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
lab "Katana ready, zoom 0"; sleep 1.5
if [ "$CYCLE" -gt 0 ]; then   # shipped behaviour: no force, the game's own stroke mask picks every swing
  A fp_vm set stroke -1 >/dev/null; lab "Default strokes, no force (LMB) x$CYCLE"
  for r in $(seq 1 $CYCLE); do A fp_keys press lmb 60 >/dev/null; sleep 2.4; done
fi
for s in $STROKES; do
  A fp_vm set stroke $s >/dev/null
  lab "Stroke $s: ${SNAME[$s]} (LMB) x$REPS"
  for r in $(seq 1 $REPS); do A fp_keys press lmb 60 >/dev/null; sleep 2.4; done
done
A fp_vm set stroke -1 >/dev/null; sleep 0.5
lab end; echo q >&7; [ -n "$E6_PIPE" ] && touch "$N.stop"; exec 7>&-; take_sample_stop; wait $FP; FP=; rm -f "$N.stop"
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-e6-$N.txt"; A fp_vm rec dump "vmrec-e6-$N.txt" >/dev/null; sleep 2; cp "$KDIR/vmrec-e6-$N.txt" "$N.vmrec.txt" || fail "no vmrec dump"
NSW=$(( CYCLE + $(echo $STROKES | wc -w) * REPS ))
SWL=$(grep -o "\[vm\] swing #[0-9]* stroke [0-9] (mask 0x[0-9a-f]*" "$KDIR/KenshiFP.log" | tail -$NSW)
SW=$(awk '{print $5}' <<<"$SWL" | tr '\n' ',')
CY=; [ "$CYCLE" -gt 0 ] && CY=$(head -$CYCLE <<<"$SWL" | awk '{print $5}' | tr '\n' ',' | sed 's/,$//')
CYM=$(head -1 <<<"$SWL" | grep -o 'mask 0x[0-9a-f]*' | cut -c6-)
A fp_vm set stroke -1 >/dev/null; A chatter on >/dev/null   # restore before the game is released (op-b7: blkJ inherited stroke 3)
pf_game_done   # game part over: under run-batch.sh the next row starts while the checks below run
"$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
# full takecheck output kept in $N.takecheck.txt; the RESULT carries the last line + every failing check line (op-comb2: "sync FAIL" without detail)
python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" > "$N.takecheck.txt" 2>&1
TC=$(tail -1 "$N.takecheck.txt"); TCB=$(grep -E "^[a-z]+ FAIL " "$N.takecheck.txt" | cut -c1-160 | tr '\n' ';')
ok=1; echo "$TC" | grep -qE "^RESULT (take )?PASS" || ok=0   # takecheck prints "RESULT take PASS" (dryrun: E6 always FAILed on this)
: > "$N.lab.txt"
for s in $STROKES; do for c in inline metrics churn blade; do
  x=; [ $c = churn ] && x=--stroke   # churn also gates the stroke-start roll (maintainer ask)
  r=$(python3 $L/animlab.py --only-stroke $s $c $x "$N.vmrec.txt" 2>&1 | grep -E "^(inline|arc|churn|blade) " | head -1)
  echo "stroke $s $r" >> "$N.lab.txt"
  # stroke 0 blade snap/seen = documented baseline exception (approved stroke, keys untouched)
  [ "$s" = 0 ] && [ "${r%% *}" = blade ] && continue
  echo "$r" | grep -q " PASS" || ok=0
done; done
CYR=; if [ "$CYCLE" -gt 0 ]; then   # cycle: every swing logged, no stroke repeats before the mask is used up, exact order if asked
  nd=$(tr ',' '\n' <<<"$CY" | sort -u | grep -c .); nm=$(( $(printf '%d' "${CYM:-0x1}") )); pc=0; for b in 0 1 2 3 4 5 6 7; do [ $(( (nm >> b) & 1 )) = 1 ] && pc=$((pc+1)); done
  want=$(( CYCLE < pc ? CYCLE : pc ))
  if [ $(tr ',' '\n' <<<"$CY" | grep -c .) -ne $CYCLE ]; then CYR="cycle FAIL logged=[$CY] want $CYCLE swings"; ok=0
  elif [ $nd -lt $want ]; then CYR="cycle FAIL logged=[$CY] distinct $nd < $want (mask $CYM)"; ok=0
  elif [ -n "$CYCLE_EXPECT" ] && [ "$(tr , '\n' <<<"$CY" | sort -u | paste -sd,)" != "$(tr , '\n' <<<"$CYCLE_EXPECT" | sort -u | paste -sd,)" ]; then CYR="cycle FAIL logged=[$CY] want the set [$CYCLE_EXPECT] (mask $CYM)"; ok=0
  else CYR="cycle PASS logged=[$CY] mask $CYM"; fi; echo "$CYR" >> "$N.lab.txt"; fi
SK=$(python3 $L/animlab.py stroke --overhead 2 "$N.vmrec.txt" 2>&1 | grep '^stroke ' | head -1); echo "$SK" >> "$N.lab.txt"; echo "$SK" | grep -q "^stroke PASS" || ok=0
PF_DONE=1; echo "RESULT E6-$N $(pf_grade $ok "$TC") takecheck=[$TC${TCB:+ bad: $TCB}] (detail $OUT/$N.takecheck.txt) strokes_logged=$SW${CYR:+ $CYR} $(grep -c FAIL "$N.lab.txt") lab FAILs (see $OUT/$N.lab.txt) len=$(cat "$N.video-len.txt")$(pf_recwarn "$TC")"
