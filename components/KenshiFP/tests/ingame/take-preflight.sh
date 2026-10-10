# take-preflight.sh: shared setup checks for KenshiFP game takes (source it; WSL, stobe-auto on PATH, Kenshi running).
# Shay 2026-10-10 "game-take discipline": every take runs these BEFORE recording; a failed check prints
#   RESULT <row> FAIL setup: <reason>
# and stops the take (exit 1, no retry). Set PF_ROW=<row name> before calling (the RESULT line uses it).
#   pf_day                     game time to 10-13 h (50x until there), verified; then a clear sky in a screenshot
#   pf_clean <x> <z> [R]       pin + knock out every live non-squad NPC within R (default 3000) of x,z (Nameless kept)
#   pf_open [secs]             open ground: a short gdigrab clip judged by the lab (frames.py openground)
#   pf_ready                   drawn weapon in ready stance (R toggles), verified with fp_vm state
#   pf_loaded                  crossbow loaded: RMB held until fp_combat loaded>=1, released, loaded=1 verified
#   pf_fail <reason>           print the RESULT line and exit 1 (runs PF_ON_FAIL first if set)
PF_A(){ stobe-auto "$@" </dev/null 2>&1; }
PF_FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
PF_SHOTS=/mnt/d/Steam/steamapps/common/Kenshi/mods/AutomationHarness/shots
PF_LAB=/mnt/c/KenshiModding/Kenshi-Automation-Harness/tools/animlab
PF_TITLE="title=Kenshi 1.0.65 - x64 (Newland)"
pf_fail(){ [ -n "$PF_ON_FAIL" ] && eval "$PF_ON_FAIL"; echo "RESULT ${PF_ROW:-take} FAIL setup: $*"; exit 1; }
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
  r=$(python3 $PF_LAB/frames.py openground "$f" 2>&1 | tail -1); rm -f "$f"
  echo "$r" | grep -q "PASS" || pf_fail "open ground: $r"
  echo "pf_open ok: $r"
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
