#!/bin/bash
# ffx-cap.sh: drop-in for "$FFX" (ffmpeg.exe) that turns window grabs into occlusion-proof window capture.
# capture-fix 2026-10-11: ffmpeg gdigrab films the SCREEN area of the game window, so on the 5090 (background game,
# Shay working on the same PC) any window over the game was recorded (pf_open "openground open=0.00").
# Every call is passed to the real ffmpeg unchanged, EXCEPT one with `-f gdigrab ... -i title=<t>` when the capture mode is
# wgc: then wgccap.exe (Kenshi-Automation-Harness/tools/wgccap, Windows Graphics Capture on the GPU, client area, no
# cursor, never focuses the window) streams raw BGRA at the same -framerate (default ntsc like gdigrab) into a named pipe and
# ffmpeg reads `-f rawvideo -pix_fmt bgr0 -video_size WxH -framerate F -i \\.\pipe\..` instead. Everything else (output
# options, venc_args/h264_nvenc, -t, 'q' on stdin, file names) stays as the caller wrote it, so the output file has the
# same size/fps/length as a gdigrab take. -draw_mouse / -show_region are dropped (WGC: cursor off).
# Capture mode: KAH_CAPTURE=wgc|gdigrab, else line 1 of $CR/KenshiTestRuns/capture.default, else gdigrab.
# FFX_REAL = the real ffmpeg.exe (set by rig-env.sh / take-preflight.sh). Works in WSL (5090) and Git Bash (4080).
# A wgc start failure (window not found, minimized, no WGC) prints `ffx-cap: wgc failed: <why>` on stderr and exits 1:
# never a silent fallback to gdigrab (that is the occluded take this exists to stop).
CRR=${CR:-/mnt/c}; [ -d "$CRR" ] || CRR=/c
REAL=${FFX_REAL:-$CRR/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
mode=${KAH_CAPTURE:-}
[ -z "$mode" ] && [ -f "$CRR/KenshiTestRuns/capture.default" ] && mode=$(head -1 "$CRR/KenshiTestRuns/capture.default" | tr -d '\r ')
args=("$@"); gdi=0; title=""
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[i]}" = -f ] && [ "${args[i+1]}" = gdigrab ] && gdi=1
  [ "${args[i]}" = -i ] && case "${args[i+1]}" in title=*) title=${args[i+1]#title=};; esac
done
[ "$mode" = wgc ] && [ $gdi = 1 ] && [ -n "$title" ] || exec "$REAL" "$@"

CAP=""
for c in "$CRR/KenshiModding/Kenshi-Automation-Harness/tools/wgccap/out/wgccap.exe" "$CRR/KAH/bin/wgccap.exe"; do
  [ -f "$c" ] && { CAP=$c; break; }; done
[ -n "$CAP" ] || { echo "ffx-cap: wgc failed: wgccap.exe not found (build Kenshi-Automation-Harness/tools/wgccap/build.bat)" >&2; exit 1; }
fps=ntsc; new=()
for ((i = 0; i < ${#args[@]}; i++)); do
  a=${args[i]}
  case "$a" in
    -f) [ "${args[i+1]}" = gdigrab ] && { i=$((i+1)); continue; }; new+=("$a");;
    -draw_mouse|-show_region|-offset_x|-offset_y) i=$((i+1));;
    -framerate) fps=${args[i+1]}; i=$((i+1));;
    -i) case "${args[i+1]}" in title=*) new+=(@CAPIN@); i=$((i+1));; *) new+=("$a");; esac;;
    *) new+=("$a");;
  esac
done
pipe='\\.\pipe\kahcap-'"$$-$RANDOM"
info=$(mktemp 2>/dev/null || echo /tmp/ffx-cap.$$); err=$info.err
( cd /tmp 2>/dev/null; exec "$CAP" --title "$title" --fps "$fps" --pipe "$pipe" ) > "$info" 2> "$err" < /dev/null &
CP=$!
size=""
for _ in $(seq 1 100); do
  l=$(head -1 "$info" 2>/dev/null | tr -d '\r')
  case "$l" in READY*) size=$(echo "$l" | awk '{print $2}'); break;; ERROR*) break;; esac
  kill -0 $CP 2>/dev/null || { l=$(head -1 "$info" | tr -d '\r'); break; }
  sleep 0.05
done
if [ -z "$size" ]; then
  echo "ffx-cap: wgc failed: ${l:-no answer from wgccap in 5 s} $(head -c 200 "$err" 2>/dev/null)" >&2
  kill $CP 2>/dev/null; rm -f "$info" "$err"; exit 1
fi
final=()
for a in "${new[@]}"; do
  if [ "$a" = @CAPIN@ ]; then final+=(-f rawvideo -pix_fmt bgr0 -video_size "$size" -framerate "$fps" -thread_queue_size 64 -i "$pipe")
  else final+=("$a"); fi
done
exec 3<&0
"$REAL" "${final[@]}" <&3 & FP=$!
trap 'kill -TERM $FP 2>/dev/null' TERM INT HUP
wait $FP; rc=$?
# a TERM trap returns from wait early: wait for ffmpeg to finish writing the file
kill -0 $FP 2>/dev/null && wait $FP && rc=$?
for _ in $(seq 1 40); do kill -0 $CP 2>/dev/null || break; sleep 0.05; done
kill $CP 2>/dev/null
[ -n "${FFX_CAP_LOG:-}" ] && { echo "$(date +%T) title=$title fps=$fps size=$size rc=$rc"; cat "$err"; } >> "$FFX_CAP_LOG"
rm -f "$info" "$err"
exit $rc
