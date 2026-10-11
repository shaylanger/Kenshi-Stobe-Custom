#!/usr/bin/env bash
# live-watch.sh: visual watcher for a running batch (both rigs, rig-env.sh). Samples the game window every 5 s (ffmpeg
# gdigrab, the capture path the take scripts use; a GDI read of the window: never focuses it, never sends input) and
# flags stuck menu/load screens, black screens, frozen frames, overlays, cursor and a missing window minutes before
# the row's RESULT line. CPU only (no NVENC/CUDA; ANIMLAB_GPU=0). Judge + check list: live-watch.py header.
#   live-watch.sh start <out-dir> [--every 5] [--checks black,frozen,menu,...]   detached; stops by itself at
#                       <out>/GAMEDONE or <out>/DONE (run-batch.sh), or with `stop`
#   live-watch.sh stop <out-dir>        touch <out>/live-watch.stop, wait for the summary line, print it
#   live-watch.sh status <out-dir>      open flags (live-watch.state) + the last line of live-watch.txt
#   live-watch.sh replay <video> <out-dir> [--every 5] [--checks ...]   same judge on a recording (tests/tuning)
#   live-watch.sh selftest              replays synthetic black/frozen videos + a clean corpus take, and runs the live
#                                       loop against a fake window (LW_FAKE_VIDEO); no game needed
# Output: <out>/live-watch.txt (one line per flagged frame, last line `LIVE-WATCH SUMMARY ...`), <out>/live-watch/*.jpg
# (first frame of each flag run), <out>/live-watch.state, <out>/live-watch.phase (harness `status` phase, polled every
# 30 s by a read-only query), <out>/live-watch.log.
# Not for multi-instance lanes (<out>/.instance): both games have the same window title, refused.
set -u
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$H/rig-env.sh" >/dev/null 2>&1
export ANIMLAB_GPU=0 WIN_TITLE
PY=python3
ffx_arg() { if [ "${RIG:-5090}" = 4080 ]; then cygpath -w "$FFX"; else echo "$FFX"; fi; }
cmd=${1:-}; shift || true
case "$cmd" in
start)
  O=${1:?out-dir}; shift
  [ -f "$O/.instance" ] && { echo "live-watch: refused, multi-instance lane ($O/.instance): window title ambiguous"; exit 1; }
  mkdir -p "$O"; rm -f "$O/live-watch.stop"
  if [ -f "$O/live-watch.pid" ] && kill -0 "$(cat "$O/live-watch.pid")" 2>/dev/null; then echo "live-watch: already running ($O)"; exit 0; fi
  export LW_FFMPEG=$(ffx_arg)
  # phase poller: harness `status` (read-only) every 30 s into live-watch.phase; ends with the watcher's stop files
  ( while [ ! -f "$O/GAMEDONE" ] && [ ! -f "$O/DONE" ] && [ ! -f "$O/live-watch.stop" ]; do
      ph=$(timeout 20 stobe-auto status </dev/null 2>/dev/null | grep -o 'phase=[a-z]*' | head -1 | cut -d= -f2)
      [ -n "$ph" ] && echo "$ph" > "$O/live-watch.phase"
      sleep 30
    done ) </dev/null >/dev/null 2>&1 &
  nice -n 15 $PY "$H/live-watch.py" watch "$O" --name "$(basename "$O")" "$@" </dev/null >"$O/live-watch.log" 2>&1 &
  echo $! > "$O/live-watch.pid"; disown -a 2>/dev/null
  echo "live-watch: started pid $(cat "$O/live-watch.pid") -> $O/live-watch.txt" ;;
stop)
  O=${1:?out-dir}; touch "$O/live-watch.stop"
  for _ in $(seq 30); do grep -q '^LIVE-WATCH SUMMARY' "$O/live-watch.txt" 2>/dev/null && break; sleep 1; done
  grep '^LIVE-WATCH SUMMARY' "$O/live-watch.txt" 2>/dev/null | tail -1 || echo "live-watch: no summary in $O" ;;
status)
  O=${1:?out-dir}
  if [ -s "$O/live-watch.state" ]; then now=$(date +%s); while read -r c s row; do echo "OPEN $c $((now - s))s row=$row"; done < "$O/live-watch.state"; fi
  tail -1 "$O/live-watch.txt" 2>/dev/null ;;
replay)
  V=${1:?video}; O=${2:?out-dir}; shift 2
  nice -n 15 $PY "$H/live-watch.py" replay "$V" "$O" --name "$(basename "$V")" "$@" | tail -1 ;;
selftest)
  T=$(mktemp -d /tmp/lw-self.XXXX); fail=0
  C=$CR/KenshiTestRuns/corpus/kept/kfx-b2_e6_e6fix.mp4
  # synthetic: 20 s clean take, 30 s black, 20 s clean; and 20 s clean + 90 s frozen (one frame looped)
  ffmpeg -nostdin -loglevel error -t 20 -i "$C" -f lavfi -t 30 -i color=c=black:s=1600x900:r=30 -t 20 -i "$C" \
    -filter_complex '[0:v]scale=1600:900,fps=30,setsar=1[a];[1:v]setsar=1[b];[2:v]scale=1600:900,fps=30,setsar=1[c];[a][b][c]concat=n=3:v=1[o]' \
    -map '[o]' -c:v libx264 -preset ultrafast "$T/black.mp4"
  ffmpeg -nostdin -loglevel error -t 20 -i "$C" -vf 'scale=1600:900,fps=30,tpad=stop_mode=clone:stop_duration=90' \
    -c:v libx264 -preset ultrafast "$T/frozen.mp4"
  chk() { local n=$1 want=$2 s; s=$($PY "$H/live-watch.py" replay "$T/$n.mp4" "$T/$n" --name "$n" --checks nowindow,black,frozen,menu | tail -1)
    if [[ "$s" =~ $want ]]; then echo "SELFTEST $n PASS: $s"; else echo "SELFTEST $n FAIL (want /$want/): $s"; fail=1; fi; }
  chk black ' black=1/'
  chk frozen ' frozen=1/'
  s=$($PY "$H/live-watch.py" replay "$C" "$T/clean" --name clean --checks nowindow,black,frozen,menu | tail -1)
  [[ "$s" =~ ' clean ' ]] && echo "SELFTEST clean PASS: $s" || { echo "SELFTEST clean FAIL: $s"; fail=1; }
  # capture path (capture.default=wgc): FFX = ffx-cap.sh, a non-executable .sh, must be run through bash with the gdigrab
  # window args intact (ffx-cap.sh turns them into WGC); fake ffx-cap: answers one frame of the asked scale
  printf '%s
' 'a="$*"; case "$a" in *"-f gdigrab"*"title="*) ;; *) exit 3;; esac'     's=$(echo "$a" | grep -o "scale=[0-9]*:[0-9]*"); w=${s#scale=}; h=${w#*:}; w=${w%:*}; head -c $((w*h*3)) /dev/zero' > "$T/ffx-cap.sh"
  s=$(cd "$H" && $PY -c "import importlib.util as u; sp=u.spec_from_file_location('lw', 'live-watch.py'); m=u.module_from_spec(sp); sp.loader.exec_module(m); f=m.grab_gdi('$T/ffx-cap.sh', 'Kenshi'); print('frame' if f is not None else 'none', m.ffx_cmd('$T/ffx-cap.sh')[0])")
  [ "$s" = "frame bash" ] && echo "SELFTEST wgc-path PASS: grab through ffx-cap.sh via bash" || { echo "SELFTEST wgc-path FAIL: $s"; fail=1; }
  # live loop end to end: fake window = black.mp4 on the watcher clock, stopped by a GAMEDONE file
  mkdir -p "$T/live"; echo "1 rowX 0" > "$T/live/step.pid"
  LW_FAKE_VIDEO="$T/black.mp4" $PY "$H/live-watch.py" watch "$T/live" --every 2 --checks black,frozen >/dev/null 2>&1 & p=$!
  sleep 40; touch "$T/live/GAMEDONE"; wait $p
  s=$(tail -1 "$T/live/live-watch.txt")
  if [[ "$s" =~ ' black=1/' && "$s" =~ 'stop=GAMEDONE' ]] && grep -q 'row=rowX black' "$T/live/live-watch.txt"; then echo "SELFTEST live PASS: $s"
  else echo "SELFTEST live FAIL: $s"; fail=1; fi
  rm -rf "$T"; [ $fail = 0 ] && echo "SELFTEST ALL PASS" || { echo "SELFTEST FAILED"; exit 1; } ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
