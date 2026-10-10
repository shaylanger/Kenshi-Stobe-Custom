# take-preflight.sh: shared setup checks for KenshiFP game takes (source it; WSL, stobe-auto on PATH, Kenshi running).
# Shay 2026-10-10 "game-take discipline": every take runs these BEFORE recording; a failed check prints
#   RESULT <row> FAIL setup: <reason>
# and stops the take (exit 1, no retry). Set PF_ROW=<row name> before calling (the RESULT line uses it).
#   pf_day                     game time to 10-13 h (50x until there), verified; then a clear sky in a screenshot
#   pf_clean <x> <z> [R]       pin + knock out every live non-squad NPC within R (default 3000) of x,z (Nameless kept)
#   pf_open [secs]             open ground: a short gdigrab clip judged by the lab (frames.py openground), no mouse cursor
#                              (frames.py cursor), no dark/black frames (ffmpeg signalstats YAVG >= PF_MIN_YAVG, default 35)
#   pf_ready                   drawn weapon in ready stance (R toggles), verified with fp_vm state
#   pf_loaded                  crossbow loaded: RMB held until fp_combat loaded>=1, released, loaded=1 verified
#   pf_fail <reason>           print the RESULT line and exit 1 (runs PF_ON_FAIL first if set)
PF_A(){ stobe-auto "$@" </dev/null 2>&1; }
PF_FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
PF_SHOTS=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}/mods/AutomationHarness/shots   # rig layer: tools/automation/rig-env.sh
PF_LAB=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness/tools/animlab
PF_TITLE="title=Kenshi 1.0.65 - x64 (Newland)"
pf_fail(){ [ -n "$PF_ON_FAIL" ] && eval "$PF_ON_FAIL"; PF_DONE=1; echo "RESULT ${PF_ROW:-take} FAIL setup: $*"; exit 1; }
pf_hour(){ local h; h=$(PF_A time | grep -o 'time=[0-9]*'); h=${h#time=}; echo $((10#${h:-0})); }
pf_day(){
  local h; h=$(pf_hour)
  if [ "$h" -lt 10 ] || [ "$h" -gt 13 ]; then
    PF_A speed 50 hold >/dev/null
    for i in $(seq 1 200); do sleep 2; h=$(pf_hour); [ "$h" -ge 10 ] && [ "$h" -le 13 ] && break; done
    PF_A speed 1 hold >/dev/null
  fi
  h=$(pf_hour); { [ "$h" -ge 10 ] && [ "$h" -le 13 ]; } || pf_fail "game time $h h, not 10-13 after 50x"
  PF_A screenshot pf-sky >/dev/null; sleep 0.5
  local rgb; rgb=$("$PF_FFX" -hide_banner -loglevel error -y -i "$(wslpath -w "$PF_SHOTS/pf-sky.png")" -vf "crop=1600:120:0:30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1)
  [ -n "$rgb" ] || pf_fail "sky check could not read the screenshot"
  echo "$rgb" | awk '{exit !($3 > $1+25)}' || pf_fail "sky not clear (rgb $rgb)"
  echo "pf_day ok: ${h} h, sky rgb$(echo $rgb)"
}
pf_clean(){
  local TX=$1 TZ=$2 R=${3:-3000} n=0
  { PF_A chars 6000; for f in "Starving" "Dust Bandits" "Hungry" "Outlaws" "Marauder" "Shinobi"; do PF_A chars 6000 "$f"; done; } 2>/dev/null \
    | sed "s/^[0-9]* within [0-9.]*: //" | sed 's/ | /\n/g' | grep -v "\[Nameless\]\| KO\| DEAD" \
    | sed -n 's/.*\(#[0-9]*\/[0-9]*\) .* pos=\([-0-9.]*\),[-0-9.]*,\([-0-9.]*\).*/\1 \2 \3/p' | sort -u > /tmp/pf-clean.$$
  while read id x z; do
    d=$(awk -v x=$x -v z=$z -v a=$TX -v b=$TZ 'BEGIN{printf "%d", sqrt((x-a)^2+(z-b)^2)}')
    [ "$d" -lt "$R" ] || continue
    PF_A pin "$id" >/dev/null; PF_A ko "$id" 900 >/dev/null; n=$((n+1))
  done < /tmp/pf-clean.$$; rm -f /tmp/pf-clean.$$
  echo "pf_clean ok: $n NPCs pinned + KO within $R of $TX,$TZ"
}
pf_open(){
  local s=${1:-2} f=/tmp/pf-open.$$.mp4 r
  ( cd /tmp && "$PF_FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 10 -t "$s" -i "$PF_TITLE" -c:v libx264 -preset veryfast -pix_fmt yuv420p "$(wslpath -w $f)" ) </dev/null
  [ -s "$f" ] || pf_fail "open-ground clip not recorded"
  r=$(python3 $PF_LAB/frames.py openground "$f" 2>&1 | tail -1)
  local c y; c=$(python3 $PF_LAB/frames.py cursor "$f" --name pf 2>&1 | tail -1)
  y=$(ffmpeg -hide_banner -nostdin -i "$f" -vf "fps=2,signalstats,metadata=print:key=lavfi.signalstats.YAVG" -f null - 2>&1 | grep -o 'YAVG=[0-9.]*' | cut -d= -f2 | sort -n | head -1); rm -f "$f"
  echo "$r" | grep -q "PASS" || pf_fail "open ground: $r"
  echo "$c" | grep -q "PASS" || pf_fail "mouse cursor in frame: $c"
  awk -v y="${y:-0}" -v m="${PF_MIN_YAVG:-35}" 'BEGIN{exit !(y >= m)}' || pf_fail "dark/black frames (min luma ${y:-?} < ${PF_MIN_YAVG:-35}): night, or the display asleep"
  echo "pf_open ok: $r | $c | min luma $y"
}
pf_st(){ PF_A fp_vm state | grep -o ' state=[^ ]*' | head -1 | cut -d= -f2; }
pf_waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(pf_st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
pf_ready(){
  [ "$(pf_st)" = ready ] && { echo "pf_ready ok"; return 0; }
  [ "$(pf_st)" = holstered ] || { PF_A key_inject r tap 120 >/dev/null; pf_waitst holstered 6; }
  PF_A key_inject r tap 120 >/dev/null; pf_waitst ready 6 || pf_fail "weapon not ready (state=$(pf_st))"
  echo "pf_ready ok"
}
pf_loaded_n(){ local l; l=$(PF_A fp_combat state | grep -o ' loaded=[^ ]*' | head -1 | cut -d= -f2); echo "${l:-0}"; }
pf_loaded(){
  [ "$(pf_loaded_n)" -ge 1 ] && { echo "pf_loaded ok (already)"; return 0; }
  PF_A fp_keys press rmb 20000 >/dev/null; local e=$((SECONDS+15))
  while [ $SECONDS -lt $e ] && [ "$(pf_loaded_n)" -lt 1 ]; do sleep 0.3; done
  PF_A fp_keys release rmb >/dev/null; sleep 1.0
  [ "$(pf_loaded_n)" = 1 ] || pf_fail "crossbow not loaded after RMB hold (loaded=$(pf_loaded_n))"
  echo "pf_loaded ok"
}

# ---- setup-miss checks (animlab-loop 2026-10-10; Setup misses list: Kenshi-Automation-Harness/docs/animlab/SETUP_MISSES.md).
# Each one would have stopped a take of the 2026-10-10 session before filming:
#   pf_begin <row>             RESULT guard: a take script that exits without a RESULT line prints
#                              `RESULT <row> FAIL setup: take script ended without a RESULT line (exit N)` (T6 kfx-b2);
#                              print the verdict with pf_result PASS|FAIL "<evidence>" (or set PF_DONE=1 after your own echo)
#   pf_outdir <dir>            out dir created + writable (kfx-b2 zs: `mkdir: File exists`, 4 takes "failed" in the wrong cwd)
#   pf_display                 display keeper running (tools/automation/display-keeper.ps1; display sleep -> black frames)
#   pf_area <me> [allow]       3 sampler rounds (take_sample.py): no non-squad char within TAKE_R m, nobody down, no new
#                              combat messages (turret-fp: "Tassilo is attacking!", bandits walking into frame)
#   pf_weapon sword|crossbow   drawn + ready (pf_ready), crossbow loaded (pf_loaded) (zoom-sweep: "aim" was a reload)
#   pf_rig                     ffmpeg present, harness answers, game renders at RES_Wx RES_H (958x510 DPI rescale), window
#   pf_open (extended)         the same clip also fails on a mouse cursor (frames.py cursor) and dark/black frames (YAVG)
#   pf_all <me> <x> <z> <weapon> [allow]   everything above in order: rig, display, day, clean, area, weapon, open
pf_result(){ echo "RESULT ${PF_ROW:-take} $1 $2"; PF_DONE=1; }
pf_begin(){ PF_ROW=$1; PF_DONE=""; trap '_pf_rc=$?; [ -n "$PF_DONE" ] || echo "RESULT ${PF_ROW:-take} FAIL setup: take script ended without a RESULT line (exit $_pf_rc)"' EXIT; }
pf_outdir(){ mkdir -p "$1" 2>/dev/null; [ -d "$1" ] || pf_fail "out dir $1 is not a directory (mkdir failed)"
  ( : > "$1/.pf-w" ) 2>/dev/null && rm -f "$1/.pf-w" || pf_fail "out dir $1 not writable"; echo "pf_outdir ok: $1"; }
pf_display(){ [ "${RIG:-5090}" = 4080 ] && { echo "pf_display skip: 4080 (rig_preflight checks its capture)"; return 0; }; local K="${CR:-/mnt/c}/KenshiModding/tools/automation/display-keeper.ps1" s w
  w=$(wslpath -w "$K" 2>/dev/null || echo "$K")
  s=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$w" -Status 2>/dev/null | tr -d '\r')
  case "$s" in "KEEPER RUNNING"*) echo "pf_display ok: $s"; return 0;; esac
  powershell.exe -NoProfile -Command "Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$w'" >/dev/null 2>&1
  local e=$((SECONDS+15)); while [ $SECONDS -lt $e ]; do sleep 1
    s=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$w" -Status 2>/dev/null | tr -d '\r'); case "$s" in "KEEPER RUNNING"*) echo "pf_display ok (started): $s"; return 0;; esac; done
  pf_fail "display keeper not running ($s): the display may sleep and gdigrab record black"; }
pf_area(){ local me=$1 allow=${2:-} ev=/tmp/pf-area.$$ bad
  KAH_DIR="${KAH_DIR:-D:\\Steam\\steamapps\\common\\Kenshi\\mods\\AutomationHarness}" python3 "${CR:-/mnt/c}/KenshiModding/components/KenshiFP/animlab/take_sample.py" \
    "$ev" "$(date +%s.%N)" "$me" "$allow" --count 3 2>/dev/null
  [ -s "$ev" ] || pf_fail "area check: no sampler output (harness down?)"
  bad=$(grep ' world ' "$ev" | tail -2 | grep -v 'near=0 .*down=0 msgs=0' | head -1 | cut -d' ' -f3-); rm -f "$ev"
  [ -z "$bad" ] || pf_fail "area not clean: $bad"; echo "pf_area ok: nobody within ${TAKE_R:-20} m, no combat messages"; }
pf_weapon(){ pf_ready; [ "$1" = crossbow ] && pf_loaded; return 0; }
pf_rig(){ local s sz
  # 4080 capture preflight (quser session Active + non-black grab) lives in tools/automation/rig-env.sh (owner 4080-filming)
  if declare -F rig_preflight >/dev/null; then rig_preflight "${PF_ROW:-take}" || { [ -n "$PF_ON_FAIL" ] && eval "$PF_ON_FAIL"; PF_DONE=1; exit 1; }; fi   # it prints its own RESULT line
  [ -x "$PF_FFX" ] || [ -f "$PF_FFX" ] || pf_fail "ffmpeg $PF_FFX missing"
  s=$(PF_A screenshot pf-rig); echo "$s" | grep -qi 'error\|timeout' && pf_fail "harness screenshot failed: $(echo "$s" | head -1 | cut -c1-100)"
  # Windows python on the 4080 (Git Bash) gets no path conversion inside -c: hand it the C:/ form
  s=$PF_SHOTS/pf-rig.png; command -v cygpath >/dev/null 2>&1 && s=$(cygpath -m "$s")
  sleep 0.5; sz=$(python3 -c "from PIL import Image; im=Image.open('$s'); print('%dx%d' % im.size)" 2>/dev/null)
  [ "$sz" = "${RES_W:-1600}x${RES_H:-900}" ] || pf_fail "game renders at ${sz:-?} not ${RES_W:-1600}x${RES_H:-900} (kenshi-ctl.ps1 fit)"
  echo "pf_rig ok: ${RIG:-5090} render $sz"; }
pf_all(){ local me=$1 x=$2 z=$3 w=$4 allow=${5:-}
  pf_rig; pf_display; pf_day; pf_clean "$x" "$z"; pf_area "$me" "$allow"; pf_weapon "$w"; pf_open 3; }
