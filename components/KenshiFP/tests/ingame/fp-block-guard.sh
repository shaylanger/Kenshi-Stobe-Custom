#!/bin/bash
# fp-block-guard.sh <out dir> <name> [presses per orbit, default 5]   (WSL; stobe-auto on PATH; Kenshi running windowed)
# Ticket B proof + sword-z25-block review take: katana drawn on open ground (kah-fpxbow take spot), camera at zoom 25,
# view orbit 2.3 then 3.0; per orbit: ready, <n> free blocks (RMB held 2.5 s, released), a free swing and a swing cut
# into a block. Every free block must use a raised-guard technique: the KenshiFP log line "free block start ... anim='x'"
# per press is checked against the allow list (default "st", the only raised guard: kfx-b6 survey), plus the lab guard check
# (median blade elevation over block frames) on the fp_vm rec, takecheck (labels vs live state), cursor + open ground.
# Output in <out dir>: <name>.mp4 .lab .ev.txt .vmrec.txt .techs.txt; last line: RESULT BLOCKGUARD-<name> PASS|FAIL ...
OUT=$1; N=$2; REPS=${3:-5}; ALLOW=${ALLOW:-st}
[ -n "$OUT" ] && [ -n "$N" ] || { echo "usage: fp-block-guard.sh <out dir> <name> [presses per orbit]"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-kfp-fixer}
mkdir -p "$OUT" 2>/dev/null; cd "$OUT" 2>/dev/null || { echo "RESULT BLOCKGUARD-$N FAIL setup: out dir $OUT not usable"; exit 2; }
SH=Axima; SPOT="-54190 633 4380"
HARN=/mnt/c/KenshiModding/Kenshi-Automation-Harness; HERE=/mnt/c/KenshiModding/components/KenshiFP; L=$HARN/tools/animlab
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi; KLOG=$KDIR/KenshiFP.log
A(){ stobe-auto "$@" </dev/null 2>&1; }
FIFO=/tmp/kfp-$N.ffin
cleanup(){ [ -n "$_TS_RUN" ] && take_sample_stop; [ -n "$FP" ] && { echo q >&7 2>/dev/null; wait $FP; }; A fp_keys release rmb >/dev/null; A fp_keys release lmb >/dev/null; A fp_camera distance 0 >/dev/null; rm -f "$FIFO"; }
PF_ROW=BLOCKGUARD-$N; PF_ON_FAIL=cleanup; . $HERE/tests/ingame/take-preflight.sh
pf_begin "$PF_ROW"   # RESULT guard
T0=0; lab(){ echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%.2f", a-b}') $*" >> "$N.lab"; }
place(){ A teleport $SH $SPOT >/dev/null; A fp_camera distance 0 >/dev/null; A fp_camera orbit 0 >/dev/null; A fp_camera look 3.14 0.02 >/dev/null; sleep 1; }
# ---- preflight
A load kah-fpxbow | cut -c1-80; sleep 8
for i in $(seq 1 60); do sleep 3; A wait-world | grep -qE "phase=world|ready" && break; done
A speed 1 hold >/dev/null
A pin Malzin at -53900 633 6850 >/dev/null; A pin Tassilo at -53940 640 6850 >/dev/null; A pin Shay at -53980 640 6850 >/dev/null
A select $SH >/dev/null; A fp_control take >/dev/null
pf_rig; pf_display
pf_clean -54190 4380 3000
pf_day
A teleport $SH $SPOT >/dev/null; sleep 2; A health $SH 100 >/dev/null
A fp_combat physical >/dev/null; A fp_combat on >/dev/null; A combatmode $SH ranged off >/dev/null
A unequip Malzin "Chisa Katana" >/dev/null; A inv Malzin | grep -q "\"name\":\"Chisa Katana\"" && A transfer Malzin $SH "Chisa Katana" >/dev/null
A inv $SH | grep -q "\"name\":\"Chisa Katana\"" || A pickup $SH "Chisa Katana" radius 80 >/dev/null
A equip $SH "Chisa Katana" >/dev/null; sleep 1; place; pf_ready
A fp_keys set blk_allow "$ALLOW" | grep -q "blk_allow=" || pf_fail "fp_keys set blk_allow not supported by this KenshiFP build"
A fp_camera distance 25 >/dev/null; A fp_camera orbit 2.3 >/dev/null; sleep 2; pf_open 2
echo "setup ok: $(A fp_keys set blk_hold 0.45 | grep -o "fb_tech=[^ ]* \|blk_dir=[0-9]* blk_org=[0-9]*" | tr '\n' ' ')"
# ---- take
L0=$(wc -l < "$KLOG")
: > "$N.lab"; rm -f "$FIFO"; mkfifo "$FIFO" || pf_fail "mkfifo $FIFO"
"$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 400 -i "title=Kenshi 1.0.65 - x64 (Newland)" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$N.mp4" < "$FIFO" & FP=$!
exec 7>"$FIFO"
. $HERE/animlab/take-sample.sh
A fp_vm rec on >/dev/null
T0=$(date +%s.%N); take_sample_start "$N.ev.txt" "$T0" $SH "Malzin|Tassilo|Shay"; sleep 1
for o in 2.3 3.0; do
  A fp_camera orbit $o >/dev/null; lab "Zoom 25, view orbit $o: ready stance (katana drawn)"; sleep 2.5
  for k in $(seq 1 $REPS); do
    lab "RMB held: block guard (press $k)"; A fp_keys press rmb 2500 >/dev/null; sleep 2.6
    lab "RMB released: back to ready"; sleep 2.0
  done
  lab "LMB: free swing"; A fp_keys press lmb 80 >/dev/null; sleep 2.4
  lab "LMB then RMB 0.35 s later: swing cut into block"; A fp_keys press lmb 80 >/dev/null; sleep 0.35; A fp_keys press rmb 2200 >/dev/null; sleep 2.3
  lab "RMB released: back to ready"; sleep 2.0
done
lab end; echo q >&7; exec 7>&-; take_sample_stop; _TS_RUN=; wait $FP; FP=; rm -f "$FIFO"
A fp_camera distance 0 >/dev/null
A fp_vm rec off >/dev/null; rm -f "$KDIR/vmrec-blk-$N.txt"; A fp_vm rec dump "vmrec-blk-$N.txt" >/dev/null; sleep 2; cp "$KDIR/vmrec-blk-$N.txt" "$N.vmrec.txt" 2>/dev/null || echo "note: no vmrec dump"
tail -n +$((L0 + 1)) "$KLOG" | grep -o "free block start tech=[0-9A-Fa-f]* anim='[^']*'.*" > "$N.techs.txt"
NP=$(wc -l < "$N.techs.txt")
BAD=$(grep -o "anim='[^']*'" "$N.techs.txt" | sed "s/anim='//; s/'$//" | while read -r a; do echo ",$ALLOW," | grep -qi ",$a," || echo "$a"; done | sort | uniq -c | tr '\n' ' ')
TECHS=$(grep -o "anim='[^']*'" "$N.techs.txt" | sort | uniq -c | tr -s ' ' | tr '\n' ' ')
"$FFX" -hide_banner -i "$N.mp4" 2>&1 | grep -o 'Duration: [0-9:.]*' | awk -F'[: ]' '{print $3*3600+$4*60+$5}' > "$N.video-len.txt"
TC=$(python3 $L/takecheck.py --labels "$N.lab" --ev "$N.ev.txt" --rules $HERE/animlab/take-rules.txt --video "$N.mp4" 2>&1 | tail -1)
CU=$(python3 $L/frames.py cursor "$N.mp4" 2>&1 | tail -1)
OG=$(python3 $L/frames.py openground "$N.mp4" 2>&1 | tail -1)
GU=$([ -s "$N.vmrec.txt" ] && python3 $L/animlab.py guard "$N.vmrec.txt" 2>&1 | grep '^guard' | head -1)
ok=1; for r in "$TC" "$CU" "$OG" "$GU"; do echo "$r" | grep -q "PASS" || ok=0; done
[ "$NP" -ge $((2 * REPS + 2)) ] || ok=0; [ -z "$BAD" ] || ok=0
PF_DONE=1; echo "RESULT BLOCKGUARD-$N $([ $ok = 1 ] && echo PASS || echo FAIL) presses=$NP techs=[$TECHS] not_allowed=[$BAD] guard=[$GU] takecheck=[$TC] cursor=[$CU] openground=[$OG] len=$(cat "$N.video-len.txt") log=$OUT/$N.lab"
