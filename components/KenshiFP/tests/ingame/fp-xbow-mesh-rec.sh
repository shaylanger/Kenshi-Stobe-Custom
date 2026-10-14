#!/usr/bin/env bash
# fp-xbow-mesh-rec.sh [shooter] [target] [out] (WSL, Kenshi in the world on kah-fpxbow): row XBMESHV = row XBMESH
# (fp-xbow-mesh.sh, unchanged: phases A first draw / B re-arm after the native sheathe / D adapter draw of the holstered
# bow; aim, fired, reload, ready each) filmed whole at 1600x900 30 fps, with the take sampler (fp ui_state/loaded lines =
# the review pack's state switches) and a review pack (review-pack.py --full: 1 fps sheets + 8 fps at every switch).
# Video evidence for "FP crossbow without its stock while RELOADING" (Shay 2026-10-10, fix kfp-xbow-drawsec).
# Ends with ONE line: RESULT XBMESHV PASS|FAIL <XBMESH evidence> video=<mp4> pack=<INDEX.txt>
# (PASS = XBMESH PASS + video recorded + pack built; the review of the pack is the coordinator's/agent's verdict).
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-xbow-mesh-rec}
HERE="$(cd "$(dirname "$0")" && pwd)"; KM="${HERE%/components/KenshiFP/tests/ingame}"
mkdir -p "$OUT"; cd "$OUT" || exit 1
PF_ROW=XBMESHV; . "$HERE/take-preflight.sh"
. "$KM/components/KenshiFP/animlab/take-sample.sh"
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
stobe-auto status | grep -q phase=world || pf_fail "not in world"
PF_ON_FAIL='stobe-auto chatter on >/dev/null 2>&1'; trap 'stobe-auto chatter on >/dev/null 2>&1' EXIT
stobe-auto chatter off >/dev/null 2>&1
# preflight before filming: rig/capture, display awake, day, nobody but the target dummy within 20 m, harness latency
# (pf_clean also knocks out the hostile target dummy: the bow only needs a direction, fp-xbow-mesh.sh never needs it up)
read -r PX PZ <<<"$(stobe-auto where "$SH" | sed -n 's/.*pos=\([-0-9.]*\),[-0-9.]*,\([-0-9.]*\).*/\1 \2/p')"
[ -n "$PZ" ] || pf_fail "no position for $SH"
pf_rig; pf_display; pf_day; pf_clean "$PX" "$PZ"; sleep 2; pf_area "$SH" "$TG"; pf_latency
pf_iso >/dev/null; stobe-auto mouse_inject at $(( ${RES_W:-1600} - 5 )) 4 >/dev/null 2>&1   # isolation on, virtual cursor parked in the sky (hover name tags)
rm -f rec.stop
( while [ ! -f rec.stop ]; do sleep 0.1; done; echo q ) | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 \
  -framerate 30 -t 420 -i "$PF_TITLE" $(venc_args 20 veryfast) xbmesh.mp4 &
FP=$!; T0=$(date +%s.%N); sleep 0.8
take_sample_start ev.txt "$T0" "$SH" "$TG"
bash "$HERE/fp-xbow-mesh.sh" "$SH" "$TG" "$OUT/mesh" > mesh.txt 2>&1
take_sample_stop; sleep 1.5; touch rec.stop; wait $FP; rm -f rec.stop
R=$(grep -m1 '^RESULT XBMESH ' mesh.txt); [ -n "$R" ] || R="RESULT XBMESH FAIL no RESULT line ($(tail -1 mesh.txt))"
ev=${R#RESULT XBMESH }; ev=${ev%% shots:*}
[ -s xbmesh.mp4 ] || { echo "RESULT XBMESHV FAIL no video (ffmpeg) xbmesh=$ev"; exit 1; }
python3 "$KM/tools/automation/review-pack.py" xbmesh.mp4 pack --ts ev.txt --full > pack.log 2>&1 \
  || { echo "RESULT XBMESHV FAIL review-pack failed (pack.log) xbmesh=$ev video=$OUT/xbmesh.mp4"; exit 1; }
case "$R" in "RESULT XBMESH PASS"*) echo "RESULT XBMESHV PASS $ev video=$OUT/xbmesh.mp4 pack=$OUT/pack/INDEX.txt" ;;
  *) echo "RESULT XBMESHV FAIL $ev video=$OUT/xbmesh.mp4 pack=$OUT/pack/INDEX.txt"; exit 1 ;; esac
