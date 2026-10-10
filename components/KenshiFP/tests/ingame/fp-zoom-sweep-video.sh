#!/bin/bash
# fp-zoom-sweep-video.sh <out dir> [final mp4] [take names...]   (WSL; Kenshi running windowed, game lock held by the caller)
# Z1 review video from six SHORT fp-zoom-sweep.sh takes (weapon x mode: crossbow / katana, switch hat on, switch hat
# off, fade hat on). Each take runs ONCE (no retries, Shay 2026-10-10); a take whose <name>.out already ends in a PASS
# RESULT is reused, so a failed take can be fixed and rerun alone (give its name as an argument to run only that one).
# Labels burned in, concatenated to <final mp4> (default C:\KenshiTestRuns\vm-rework\zoom-sweep.mp4) only when all six
# passed. Prints one RESULT line per take and ONE last line for the video.
OUT=$1; FINAL=${2:-${CR:-/mnt/c}/KenshiTestRuns/vm-rework/zoom-sweep.mp4}; shift 2 2>/dev/null; ONLY="$*"
[ -n "$OUT" ] || { echo "usage: fp-zoom-sweep-video.sh <out dir> [final mp4] [take names...]"; exit 2; }
HERE=$(dirname "$(readlink -f "$0")")
FFX=${FFX:-${CR:-/mnt/c}/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
mkdir -p "$OUT"; cd "$OUT" || exit 2; cp -n ${CR:-/mnt/c}/Windows/Fonts/arialbd.ttf . 2>/dev/null
TAKES="zs-xbow-switch-on:switch:on:xbow zs-sword-switch-on:switch:on:sword zs-xbow-switch-off:switch:off:xbow zs-sword-switch-off:switch:off:sword zs-xbow-fade-on:fade:on:xbow zs-sword-fade-on:fade:on:sword"
ok=1; parts=()
for t in $TAKES; do IFS=: read n mode hat w <<< "$t"
  if [ -z "$ONLY" ] || [[ " $ONLY " == *" $n "* ]]; then
    grep -q "^RESULT ZOOMSWEEP-$n PASS" "$n.out" 2>/dev/null || timeout 900 bash "$HERE/fp-zoom-sweep.sh" "$OUT" "$n" "$mode" "$hat" "$w" > "$n.out" 2>&1
  fi
  r=$(grep '^RESULT' "$n.out" 2>/dev/null | tail -1); echo "${r:-RESULT ZOOMSWEEP-$n FAIL not run}"
  echo "$r" | grep -q "^RESULT ZOOMSWEEP-$n PASS" || { ok=0; continue; }   # not " PASS ": the inner "take PASS" matched FAILED takes
  # labels burned in (0.8 s display lag)
  python3 - "$n" <<'PY'
import sys
n = sys.argv[1]; rows = [l.split(' ', 1) for l in open(n + '.lab').read().strip().split('\n')]; out = []
for i in range(len(rows) - 1):
    a = float(rows[i][0]) + 0.8; b = float(rows[i + 1][0]) + 0.8 - 0.04
    open('%sl%d.txt' % (n, i), 'w').write(rows[i][1])
    out.append("drawtext=fontfile=arialbd.ttf:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10:x=(w-tw)/2:y=40:textfile=%sl%d.txt:enable='between(t,%.2f,%.2f)'" % (n, i, a, b))
open(n + '.filt', 'w').write(','.join(out))
PY
  e=$(awk '/ end$/{print $1+0.8}' "$n.lab")
  "$FFX" -hide_banner -loglevel error -y -i "$n.mp4" -filter_complex "[0:v]$(cat "$n.filt"),trim=0:$e,setpts=PTS-STARTPTS[v]" -map "[v]" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -r 30 "${n}_cut.mp4" && parts+=("${n}_cut.mp4") || ok=0
done
[ $ok = 1 ] || { echo "RESULT ZOOMSWEEP-VIDEO FAIL not all six takes passed (see $OUT/*.out)"; exit 1; }
: > zcat.txt; for p in "${parts[@]}"; do echo "file '$p'" >> zcat.txt; done
mkdir -p "$(dirname "$FINAL")"
"$FFX" -hide_banner -loglevel error -y -f concat -safe 0 -i zcat.txt -c copy "$FINAL" && echo "RESULT ZOOMSWEEP-VIDEO PASS $FINAL" || echo "RESULT ZOOMSWEEP-VIDEO FAIL concat"
