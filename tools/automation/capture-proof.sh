#!/bin/bash
# capture-proof.sh <out dir> [secs]   (capture-fix 2026-10-11; run as a list row on a rig with the game in the world on
# open ground, e.g. save kah-fpstudio):  CAPPROOF | kah-fpstudio | Axima | Malzin | 300 | bash {CR}/KenshiModding/tools/automation/capture-proof.sh {OUT}/capproof
# Proves window capture is occlusion-proof: the game window is covered by an opaque magenta window (cover-window.ps1:
# topmost, never activated, exactly over the client area); then
#   control  a 1 s ffmpeg gdigrab clip must be magenta (the cover works; this is what failed the 5090 takes)
#   wgc      a ${2:-3} s clip through ffx-cap.sh (KAH_CAPTURE=wgc) must be the game: frames.py openground PASS, not
#            magenta, size = the game's render size, length within 0.5 s of the asked length, h264
# One line: RESULT CAPPROOF PASS|FAIL <evidence>. With PASS on the 5090, `echo wgc > C:\KenshiTestRuns\capture.default`
# makes window capture the default for every take (rig-env.sh / take-preflight.sh pf_capmode).
OUT=${1:?out dir}; SECS=${2:-3}
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$H/rig-env.sh"
. "${CR}/KenshiModding/components/KenshiFP/tests/ingame/take-preflight.sh"
pf_begin CAPPROOF; pf_outdir "$OUT"
REALF=${FFX_REAL:-$FFX}; CAPF="$CR/KenshiModding/tools/automation/ffx-cap.sh"
TITLE=${WIN_TITLE:-Kenshi 1.0.65 - x64 (Newland)}
ps(){ powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$@" </dev/null 2>&1 | tr -d '\r'; }
KCTL='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'
restore(){ [ "$RIG" = 4080 ] || ps "$KCTL" ontop "$( [ "$(pf_capmode)" = wgc ] && echo off || echo on )" >/dev/null
  powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='powershell.exe'\" | Where-Object { \$_.CommandLine -like '*cover-window.ps1*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" </dev/null >/dev/null 2>&1
  rm -f "$CR/KenshiTestRuns/cover-window.state"; }
PF_ON_FAIL=restore
rgb(){ "$REALF" -hide_banner -loglevel error -nostdin -i "$(wslpath -w "$1")" -vf "scale=1:1:flags=area" -frames:v 1 -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | xargs; }
DRY=${DR_T0:+1}   # dryrun.sh row (fake game/ffmpeg): every step runs, the colour/frame verdicts are not judged
magenta(){ [ -n "$DRY" ] && { [ "$2" = want ]; return; }; echo "$1" | awk 'NF==3{exit !($1>150 && $2<90 && $3>150)} {exit 1}'; }

pf_rig; pf_day
[ "$RIG" = 4080 ] || ps "$KCTL" ontop off | head -1
CW=$(wslpath -w "$H/cover-window.ps1")
powershell.exe -NoProfile -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$CW','-Seconds','$((SECS + 25))','-Title','\"$TITLE\"'" </dev/null >/dev/null 2>&1
[ -n "$DRY" ] && echo 'COVER 0,0 1600x900' > "$CR/KenshiTestRuns/cover-window.state"
for i in $(seq 1 40); do [ -f "$CR/KenshiTestRuns/cover-window.state" ] && break; sleep 0.25; done
[ -f "$CR/KenshiTestRuns/cover-window.state" ] || pf_fail "cover window did not open"
cov=$(cat "$CR/KenshiTestRuns/cover-window.state" | tr -d '\r'); sleep 1.5
( cd /tmp && "$REALF" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 10 -t 1 -i "title=$TITLE" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$(wslpath -w "$OUT/control-gdigrab.mp4")" ) </dev/null
c=$(rgb "$OUT/control-gdigrab.mp4")
magenta "$c" want || pf_fail "cover not effective: the gdigrab control clip is rgb($c), not magenta ($cov)"
t0=$(date +%s)
( cd /tmp && KAH_CAPTURE=wgc FFX_REAL="$REALF" "$CAPF" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t "$SECS" \
    -i "title=$TITLE" $(venc_args 23) "$(wslpath -w "$OUT/wgc.mp4")" ) </dev/null 2> "$OUT/wgc.err"
rc=$?; restore
[ $rc = 0 ] && [ -s "$OUT/wgc.mp4" ] || { pf_result FAIL "wgc recording failed rc=$rc: $(head -c 200 "$OUT/wgc.err")"; exit 1; }
w=$(rgb "$OUT/wgc.mp4")
pr=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration -of default=nw=1 "$OUT/wgc.mp4" | tr '\n' ' ')
dur=$(echo "$pr" | grep -o 'duration=[0-9.]*' | cut -d= -f2); wd=$(echo "$pr" | grep -o 'width=[0-9]*' | cut -d= -f2); ht=$(echo "$pr" | grep -o 'height=[0-9]*' | cut -d= -f2)
og=$(python3 "$PF_LAB/frames.py" openground "$OUT/wgc.mp4" 2>&1 | tail -1)
why=""
magenta "$w" && why="$why wgc clip is magenta (rgb $w);"
[ -n "$DRY" ] || echo "$og" | grep -q PASS || why="$why openground: $og;"
[ -n "$DRY" ] || awk -v d="${dur:-0}" -v s="$SECS" 'BEGIN{exit !(d >= s-0.5 && d <= s+0.5)}' || why="$why length ${dur}s for ${SECS}s;"
[ -n "$DRY" ] || [ "${wd}x${ht}" = "${RES_W:-1600}x${RES_H:-900}" ] || why="$why size ${wd}x${ht} != render ${RES_W:-1600}x${RES_H:-900};"
if [ -z "$why" ]; then pf_result PASS "covered ($cov) gdigrab rgb($c) magenta; wgc rgb($w) $og | $pr| out=$OUT"
else pf_result FAIL "$why gdigrab rgb($c) | $pr| out=$OUT"; fi
