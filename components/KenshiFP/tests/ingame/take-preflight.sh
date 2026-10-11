# take-preflight.sh: shared setup checks for KenshiFP game takes (source it; WSL, stobe-auto on PATH, Kenshi running).
# Shay 2026-10-10 "game-take discipline": every take runs these BEFORE recording; a failed check prints
#   RESULT <row> FAIL setup: <reason>
# and stops the take (exit 1, no retry). Set PF_ROW=<row name> before calling (the RESULT line uses it).
#   pf_day                     game time to 10-13 h (50x until there), verified; then a clear sky in a screenshot
#   pf_clean <x> <z> [R]       pin + knock out every live non-squad NPC within R (default 3000) of x,z (Nameless kept)
#   pf_open [secs]             open ground: a short gdigrab clip judged by the lab (frames.py openground), no mouse cursor
#                              (frames.py cursor), no dark/black frames (ffmpeg signalstats YAVG >= PF_MIN_YAVG, default 35)
#                              pf_ontop first: game window topmost (no focus) + unoccluded, else FAIL "window occluded by <p>"
#   pf_iso                     harness input isolation on (injected keys/mouse need it), verified
#   pf_ready                   pf_iso, then drawn weapon in ready stance (R toggles), verified with fp_vm state
#   pf_loaded                  crossbow loaded: RMB held until fp_combat loaded>=1, released, loaded=1 verified
#   pf_nofight                 melee drawn: a short RMB press must start the out-of-fight free block (KenshiFP.log
#                              'free block start'); none = the character is in a fight (native block, free swing/block off)
#   pf_fail <reason>           print the RESULT line and exit 1 (runs PF_ON_FAIL first if set)
#   pf_load [save]             load the FP studio fixture kah-fpstudio (else kah-fpxbow) and wait for the world
#   pf_latency [n] [max]       harness round trip <= max s (1.0) over n calls (game hitch = sampler gaps), in pf_all
# Non-exiting checks for multi-row scripts (return 1 and set PF_WHY; the caller prints its own setup FAIL lines):
#   pf_melee_arm <who>         equip a melee weapon (ranged one unequipped first); none -> give PF_MELEE_GIVE (default
#                              Guardless Katana, sid 923-gamedata.base) and equip it; sets PF_WEP (op-comb2: a row before
#                              had loaded kah-fpstudio where Malzin carries only a crossbow -> "no melee weapon")
#   pf_noxbow <who>...         crash safety (2026-10-11 BSOD, every TDR on a crossbow shot/reload frame): unequip every
#                              crossbow-class item (name ~ bow|toothpick|harpoon|eagle) on the named chars (missing chars
#                              skipped); returns 1 + PF_WHY if one is still equipped. Melee rows call it after arming.
#   pf_awake <who>...          heal to 100 and `wake` everyone KO (op-swa4: a swing knocked the neutral out, `health 100`
#                              keeps the KO, a KO ragdoll ignores pin -> "pin refused off=10.2"); fails if still KO after 3 s
#   pf_ranged_inj <who>        injected-input ranged rows (fp_combat on already sent): no melee weapon in the hands (rg03
#                              R10/HIT 2026-10-10/11: why=melee_in_hands, the AI had drawn a melee weapon after the previous
#                              row's fp_combat off; R tap, else unequip every melee weapon), crossbow drawn by an injected aim
#                              (adapter armed), loaded (rg03 R01: an EMPTY bow auto-reloaded 6.1 s > the row's 5 s wait), aim
#                              released; fails with PF_WHY (why/armed/loaded)
#   pf_calm <who> [keep...]    <who> in no native fight: KO its attacker + raiders within 3000 of it (keep names spared),
#                              wait <= 8 s for active=0; PF_WHY otherwise (rg-04 M08-ACTOR 2026-10-11: Dust Bandits on Axima)
#   pf_pin <who> <pin args>    pin, then wait up to 3 s for the per-frame put-back to land within 1.5 m; reason has off + KO
PF_A(){ stobe-auto "$@" </dev/null 2>&1; }
# Dead-game abort for every script that sources this file (fp-rowsel.sh gd_note, generalised): stobe-auto is wrapped, so
# the script's own A() gets it too. PF_GD_MAX (6) harness replies in a row of "is Kenshi running?" / "inbox locked by
# another client" signal the main shell, which prints `RESULT <PF_ROW|KAH_ROW|take> FAIL setup: game not responding` and
# exits at once; after that every stobe-auto call returns that reply without calling the game, so EXIT cleanups end in
# seconds (a hung game used to burn the full row timeout). Works inside $(...) subshells (counter file + kill $$).
# Scripts using fp-rowsel.sh keep its own per-row abort (gd_note defined = not counted here, only the fast return).
PF_GD_MAX=${PF_GD_MAX:-6}; PF_GD_FILE=$(mktemp 2>/dev/null || echo "/tmp/pf-gd.$$"); : > "$PF_GD_FILE"; PF_GD_PID=$$
stobe-auto(){ local r rc
  if [ -n "${GD_DEAD:-}" ] || [ "$(wc -l < "$PF_GD_FILE" 2>/dev/null || echo 0)" -ge "$PF_GD_MAX" ]; then
    echo "ERROR: game not responding (dead-game abort; is Kenshi running?)"; return 1; fi
  r=$(command stobe-auto "$@" 2>&1); rc=$?; [ -n "$r" ] && printf '%s\n' "$r"
  declare -F gd_note >/dev/null && return $rc
  case "$r" in *"is Kenshi running?"*|*"inbox locked by another client"*)
      echo "$* | $(head -1 <<<"$r" | cut -c1-80)" >> "$PF_GD_FILE"
      [ "$(wc -l < "$PF_GD_FILE")" -ge "$PF_GD_MAX" ] && kill -USR1 "$PF_GD_PID" 2>/dev/null;;
    *) [ -s "$PF_GD_FILE" ] && : > "$PF_GD_FILE";; esac; return $rc; }
pf_gd_abort(){ trap - USR1; local last; last=$(tail -1 "$PF_GD_FILE" 2>/dev/null)
  [ -n "${LOG:-}" ] && echo "GAME NOT RESPONDING: $PF_GD_MAX harness calls in a row got no answer; last: $last" >> "$LOG"
  PF_DONE=1; echo "RESULT ${PF_ROW:-${KAH_ROW:-take}} FAIL setup: game not responding ($PF_GD_MAX harness calls without an answer, last: $last)${LOG:+ log=$LOG}"; exit 1; }
declare -F gd_note >/dev/null || trap pf_gd_abort USR1
# Git Bash (4080 rig) has no wslpath: cygpath does the same
command -v wslpath >/dev/null 2>&1 || wslpath(){ [ "$1" = -w ] && shift; cygpath -w "$1"; }
# capture mode (capture-fix 2026-10-11; same rule as rig-env.sh kah_capture_mode): wgc = FFX goes through ffx-cap.sh
# (Windows Graphics Capture of the window, occlusion-proof) for scripts that never sourced rig-env.sh (5090 rows)
pf_capmode(){ local m=${KAH_CAPTURE:-}; [ -z "$m" ] && [ -f "${CR:-/mnt/c}/KenshiTestRuns/capture.default" ] && m=$(head -1 "${CR:-/mnt/c}/KenshiTestRuns/capture.default" | tr -d '\r '); echo "${m:-gdigrab}"; }
if [ "$(pf_capmode)" = wgc ]; then case "${FFX:-}" in *ffx-cap.sh) ;; *)
  export FFX_REAL=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
  export FFX=${CR:-/mnt/c}/KenshiModding/tools/automation/ffx-cap.sh;; esac; fi
PF_FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
PF_SHOTS=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}/mods/AutomationHarness/shots   # rig layer: tools/automation/rig-env.sh
PF_LAB=${CR:-/mnt/c}/KenshiModding/Kenshi-Automation-Harness/tools/animlab
for _d in ${CR:-/mnt/c} /mnt/c /c; do [ -f $_d/KenshiModding/tools/automation/venc.sh ] && { . $_d/KenshiModding/tools/automation/venc.sh; break; }; done   # venc_args: h264_nvenc, libx264 fallback
type venc_args >/dev/null 2>&1 || venc_args(){ echo "-c:v libx264 -preset ${2:-veryfast} -crf ${1:-18} -pix_fmt yuv420p"; }
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
  local rgb; rgb=$("$PF_FFX" -hide_banner -loglevel error -y -i "$(wslpath -w "$PF_SHOTS/pf-sky.png")" -vf "crop=iw:ih*2/15:0:ih/30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1)
  [ -n "$rgb" ] || pf_fail "sky check could not read the screenshot"
  echo "$rgb" | awk '{exit !($3 > $1+25)}' || pf_fail "sky not clear (rgb $rgb)"
  echo "pf_day ok: ${h} h, sky rgb$(echo $rgb)"
}
pf_clean(){
  local TX=$1 TZ=$2 R=${3:-3000} n=0
  { [ "${PF_CLEAN_RAIDERS:-0}" = 1 ] || PF_A chars 6000; for f in "Starving" "Dust Bandits" "Hungry" "Outlaws" "Marauder" "Shinobi"; do PF_A chars 6000 "$f"; done; } 2>/dev/null \
    | sed "s/^[0-9]* within [0-9.]*: //" | sed 's/ | /\n/g' | grep -v "\[Nameless\]\| KO\| DEAD" \
    | { if [ -n "${PF_CLEAN_KEEP:-}" ]; then grep -v -E "^ *(${PF_CLEAN_KEEP}) (\[|#)"; else cat; fi; } \
    | sed -n 's/.*\(#[0-9]*\/[0-9]*\) .* pos=\([-0-9.]*\),[-0-9.]*,\([-0-9.]*\).*/\1 \2 \3/p' | sort -u -k1,1 > /tmp/pf-clean.$$
  # one id once (sort -k1,1: an NPC listed by two faction queries moved between them and was pinned + KOed twice), and
  # all pins + KOs in ONE harness round trip (`many`, speed-scout 2026-10-11: ~40 single calls took ~20 s per row);
  # a client without `many` (answer count wrong) falls back to one call each
  local ids=() mc=() id x z d
  while read id x z; do
    d=$(awk -v x=$x -v z=$z -v a=$TX -v b=$TZ 'BEGIN{printf "%d", sqrt((x-a)^2+(z-b)^2)}')
    [ "$d" -lt "$R" ] || continue
    ids+=("$id"); mc+=("pin $id" "ko $id 900"); n=$((n+1))
  done < /tmp/pf-clean.$$; rm -f /tmp/pf-clean.$$
  if [ $n -gt 0 ] && [ "$(PF_A many "${mc[@]}" | wc -l)" != "${#mc[@]}" ]; then
    for id in "${ids[@]}"; do PF_A pin "$id" >/dev/null; PF_A ko "$id" 900 >/dev/null; done; fi
  echo "pf_clean ok: $n NPCs pinned + KO within $R of $TX,$TZ"
}
pf_clear(){   # per take in a multi-take sweep (kfp-twohand 03-twohand refilm 3, 2026-10-10: a dust storm rolled in after take 2:
  # Naginata filmed in it (openground sky 0 from 3 s), Warhammer/Heavy Polearm stopped by pf_open): pf_day only checks once
  # at the sweep start. Waits (50x, bounded) until the hour is 10-13 AND the sky is clear (blue > red+25), else FAIL setup.
  local i h rgb ok=0
  for i in $(seq 1 ${PF_CLEAR_TRIES:-150}); do
    h=$(pf_hour); rgb=""
    if [ "$h" -ge 10 ] && [ "$h" -le 13 ]; then
      PF_A screenshot pf-sky >/dev/null; sleep 0.5
      rgb=$("$PF_FFX" -hide_banner -loglevel error -y -i "$(wslpath -w "$PF_SHOTS/pf-sky.png")" -vf "crop=iw:ih*2/15:0:ih/30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1)
      if echo "$rgb" | awk 'NF==3{exit !($3 > $1+25)} {exit 1}'; then ok=1; break; fi
    fi
    [ $i = 1 ] && { echo "pf_clear: waiting at 50x (hour $h, sky rgb$(echo $rgb))"; PF_A speed 50 hold >/dev/null; }
    sleep 2
  done
  [ $i -gt 1 ] && PF_A speed 1 hold >/dev/null
  [ $ok = 1 ] || pf_fail "weather/time: no clear sky at 10-13 h after ${PF_CLEAR_TRIES:-150} polls (hour $h, sky rgb$(echo $rgb); dust storm?)"
  echo "pf_clear ok: ${h} h, sky rgb$(echo $rgb)$([ $i -gt 1 ] && echo " after $i polls")"
}
# pf_ontop: gdigrab films the SCREEN area of the game window (capture-fix 2026-10-11: Shay's windows over the background
# game failed every 5090 take with "openground open=0.00"). Sets the game window topmost without activating it
# (kenshi-ctl.ps1 ontop on) and checks 9 client points are the game window, else FAIL setup "window occluded by <process>".
# Skipped on the 4080 and with window capture (KAH_CAPTURE=wgc: tools/automation/ffx-cap.sh, occlusion-proof).
pf_ontop(){ local r
  [ "${RIG:-5090}" = 4080 ] && return 0
  [ "$(pf_capmode)" = wgc ] && { echo "pf_ontop skip: window capture (wgc)"; return 0; }
  r=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\kenshi-ctl.ps1' ontop on 2>&1 </dev/null | tr -d '\r' | grep '^ontop' | head -1)
  case "$r" in *unoccluded*) echo "pf_ontop ok: $r";; *"occluded by "*) pf_fail "window occluded by ${r#*occluded by }";;
    *) pf_fail "window topmost/occlusion check failed: ${r:-no answer}";; esac; }
pf_open(){
  local s=${1:-2} f=/tmp/pf-open.$$.mp4 r o
  pf_ontop
  # park the virtual cursor in the top-right corner (sky): hovering a character shows its "[name]" tag (kfx-b9 blkE overlay)
  PF_A mouse_inject at "${PF_PARK_X:-$(( ${RES_W:-1600} - 5 ))}" "${PF_PARK_Y:-4}" >/dev/null 2>&1
  ( cd /tmp && "$PF_FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 10 -t "$s" -i "$PF_TITLE" $(venc_args 23) "$(wslpath -w $f)" ) </dev/null
  [ -s "$f" ] || pf_fail "open-ground clip not recorded"
  r=$(python3 $PF_LAB/frames.py openground "$f" 2>&1 | tail -1)
  local c y; c=$(python3 $PF_LAB/frames.py cursor "$f" --name pf 2>&1 | tail -1); o=$(python3 $PF_LAB/frames.py overlay "$f" --name pf 2>&1 | tail -1)
  y=$(ffmpeg -hide_banner -nostdin -i "$f" -vf "fps=2,signalstats,metadata=print:key=lavfi.signalstats.YAVG" -f null - 2>&1 | grep -o 'YAVG=[0-9.]*' | cut -d= -f2 | sort -n | head -1); rm -f "$f"
  echo "$r" | grep -q "PASS" || pf_fail "open ground: $r"
  echo "$c" | grep -q "PASS" || pf_fail "mouse cursor in frame: $c"
  # a ui box in the left hint column (x<40) = Kenshi tutorial hint popups (Prospecting / How to research ...): the game was
  # launched before kenshi-ctl's tutorials=0 (54a22ec) and they never go away on a reused game (sword-judge 2026-10-11: 3 lists,
  # 5 rows lost to 'uibox x16,y330' on the 14:59 lane-A instance) -> ask run-batch.sh for a relaunch before the next row.
  if echo "$o" | grep -q "FAIL" && echo "$o" | grep -Eq 'uibox x([0-9]|[1-3][0-9]),'; then
    [ -n "${RELAUNCH_FILE:-}" ] && echo "tutorial hint popups on screen (game launched before tutorials=0): $o" > "$RELAUNCH_FILE"; fi
  echo "$o" | grep -q "FAIL" && pf_fail "foreign overlay in frame (name tag / bark text / popup): $o"
  awk -v y="${y:-0}" -v m="${PF_MIN_YAVG:-35}" 'BEGIN{exit !(y >= m)}' || pf_fail "dark/black frames (min luma ${y:-?} < ${PF_MIN_YAVG:-35}): night, or the display asleep"
  echo "pf_open ok: $r | $c | $o | min luma $y"
}
# pf_calm <who> [keep names...] (non-exiting, PF_WHY on failure): <who> (a squad member, e.g. the one a row hands control
# to) is in no native fight. rg-04 M08-ACTOR on the 5090 kah-fpxbow copy, 2026-10-11 33-rg04: Dust Bandits attacked Axima
# (pinned 60 m off, protected), so after `fp_control take` of Axima her adapter refused her AI swings and the global
# ai_refused rose 3258->3277 while Malzin was correctly released (4080: nobody near Axima, 17/17 PASS). Knocks out (pin
# 600 away + ko 900) the attacker in <who>'s target_h and every live raider within 3000 of <who> (pf_clean factions, keep
# names spared), then waits <= 8 s for active=0. A fight with a keep name is not cleared (PF_WHY says so).
pf_calm(){ local who=$1 s th kh k i p x z; shift; PF_WHY=""
  kh=""; for k in "$@"; do kh="$kh $(PF_A where "$k" | grep -o '#[0-9]*/[0-9]*' | head -1)"; done
  for i in $(seq 1 6); do s=$(PF_A fp_melee state "$who"); th=$(echo "$s" | grep -o ' target_h=[^ ]*' | head -1 | cut -d= -f2)
    if ! echo "$s" | grep -q ' active=1 ' || [ -z "$th" ] || [ "${th%/*}" = "#0" ]; then
      [ $i = 1 ] && echo "pf_calm ok: $who in no fight" || echo "pf_calm ok: $who out of the fight after clearing"; return 0; fi
    case " $kh " in *" $th "*) PF_WHY="$who fights a keep target $th"; return 1;; esac
    if [ $i = 1 ]; then p=$(PF_A where "$who" | grep -o 'pos=[^ ]*' | cut -d= -f2); x=${p%%,*}; z=${p##*,}
      echo "pf_calm: $who in a fight with $th, clearing raiders around it"
      [ -n "$x" ] && PF_CLEAN_RAIDERS=1 PF_CLEAN_KEEP=$(IFS='|'; echo "$*") pf_clean "$x" "$z" 3000; fi
    PF_A pin "$th" at "$who" dist 600 >/dev/null; PF_A ko "$th" 900 >/dev/null
    sleep 1.5; done
  PF_WHY="$who still in a fight (active=1 target_h=$th) after clearing raiders + its attacker"; return 1; }
pf_nofight(){   # kfx-b10 blkF: bandits/turrets beyond pf_clean put Axima in a fight, RMB gave the native fight block (presses=0)
  local k=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}/KenshiFP.log l n
  l=$(wc -l < "$k"); PF_A fp_keys press rmb 700 >/dev/null; sleep 1.5
  n=$(tail -n +$((l + 1)) "$k" | grep -c "free block start")
  [ "${n:-0}" -ge 1 ] || pf_fail "character in a fight: RMB gave no out-of-fight free block (KenshiFP.log)"
  echo "pf_nofight ok: free block started"
}
pf_st(){ PF_A fp_vm state | grep -o ' state=[^ ]*' | head -1 | cut -d= -f2; }
pf_waitst(){ local e=$((SECONDS+$2)); while [ $SECONDS -lt $e ]; do [ "$(pf_st)" = "$1" ] && return 0; sleep 0.2; done; return 1; }
# harness input isolation on (key_inject/mouse_inject are rejected without it; the 4080 ctl.ps1 launch does not
# turn it on: b4080c zs-xbow-switch-on/xbow-fade-on "weapon not ready (state=holstered)", harness.log "input isolation is off")
pf_iso(){
  PF_A input_isolation status | grep -q 'isolation=on' && return 0
  PF_A input_isolation on >/dev/null
  PF_A input_isolation status | grep -q 'isolation=on' || pf_fail "input isolation would not turn on (key_inject/mouse_inject need it)"
  echo "pf_iso ok: input isolation turned on"
}
pf_ready(){
  pf_iso
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
# PASS-REC (Shay 2026-10-10, no refilms caused only by PC load): takecheck.py prints `RESULT take PASS-REC .. rec-warn=<x>`
# when only RECORDING checks failed (sampler gaps, video length, sync lag) and no state is hidden; product checks decide.
#   pf_grade <ok 0|1> "<check RESULT lines>"   -> PASS | PASS-REC | FAIL   (ok = every product check of the wrapper)
#   pf_recwarn "<check RESULT lines>"          -> " rec-warn=a,b" or nothing (append at the END of the RESULT line)
# Row line: echo "RESULT <row> $(pf_grade $ok "$TC") <evidence>$(pf_recwarn "$TC")"
pf_grade(){ if [ "$1" != 1 ] || grep -qE 'RESULT [^ ]+ FAIL' <<<"$2"; then echo FAIL
            elif grep -qE 'RESULT [^ ]+ PASS-REC' <<<"$2"; then echo PASS-REC; else echo PASS; fi; }
pf_recwarn(){ local w; w=$(grep -oE 'rec-warn=[^] ]+' <<<"$1" | sed 's/^rec-warn=//' | tr ',' '\n' | awk 'NF && !s[$0]++' | paste -sd,)
              [ -n "$w" ] && echo " rec-warn=$w"; return 0; }
# pf_game_done: call once the take no longer needs the game (recording stopped, game-state evidence/dumps copied), BEFORE
# the offline analysis (takecheck/frames/animlab/review-pack). Under run-batch.sh ($GAME_DONE_FILE set) the batch then goes
# on with the next row while this script finishes its analysis in the background (Shay 2026-10-10: the game sat idle 5 min
# during a take's lab checks). From here on the script must not touch the game: PF_ON_FAIL (game cleanup) is dropped.
# Multi-take scripts call it only after the LAST take (earlier takes' analysis can run in the background: cmd & ... wait).
# PF_PRE_DONE (sword-judge 2026-10-11): a command run right BEFORE the game is released (e.g. fp-e6-tables.sh LT_RESET=1
# `fp_tables reset`). A cleanup after the background analysis raced the next row: it reset that row's freshly loaded
# tables (105f s3hold/s3cont filmed the compiled tables: rec hash 38943ca5 after load 1ab6f7f3).
pf_game_done(){ [ -n "${PF_PRE_DONE:-}" ] && { eval "$PF_PRE_DONE"; PF_PRE_DONE=""; : > "${PF_PRE_DONE_MARK:-/dev/null}"; }; PF_ON_FAIL=""; [ -n "${GAME_DONE_FILE:-}" ] && : > "$GAME_DONE_FILE"; echo "pf_game_done: game part over, analysis next"; return 0; }
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
  pf_rig; pf_display; pf_day; pf_clean "$x" "$z"; pf_area "$me" "$allow"; pf_weapon "$w"; pf_latency; pf_open 3; }
# pf_load [save]: load the FP studio fixture kah-fpstudio (Speed plan 6: open ground, day, no raiders, Axima with katana +
# loaded crossbow; built by fp-studio-fixture.sh, C:\KenshiTestFixtures\FP-studio) or, on a rig where it is not installed,
# kah-fpxbow (PF_SAVE=<save> or the argument forces one); waits for the world, else RESULT FAIL setup
pf_load(){ local s=${1:-${PF_SAVE:-}} d="${CR:-/mnt/c}/Users/Shay/AppData/Local/kenshi/save" i
  [ -n "$s" ] || { [ -d "$d/kah-fpstudio" ] && s=kah-fpstudio || s=kah-fpxbow; }
  # run-batch.sh just loaded this very save for this row (KAH_FRESH=<out>/.fresh-load "<save> <epoch>", written by its
  # prepare, removed after every row; speed-scout 2026-10-11: every take row loaded twice, ~30 s): use it, once
  local fs ft
  if [ -n "${KAH_FRESH:-}" ] && read -r fs ft < "$KAH_FRESH" 2>/dev/null && [ "$fs" = "$s" ] && [ $(( $(date +%s) - ${ft:-0} )) -lt "${PF_FRESH_MAX:-120}" ] \
     && PF_A status | grep -q phase=world; then
    rm -f "$KAH_FRESH"; PF_SAVE_LOADED=$s; echo "pf_load ok: $s (loaded by run-batch $(( $(date +%s) - ft )) s ago, no second load)"; return 0; fi
  # the harness reports phase=loading from the load reply on: no fixed wait needed (was sleep 8 + 3 s polls)
  PF_A load "$s" | cut -c1-80; sleep 2
  for i in $(seq 1 60); do PF_A wait-world | grep -qE "phase=world|ready" && break; sleep 1; done
  PF_A status | grep -q phase=world || pf_fail "save $s did not reach the world"
  PF_SAVE_LOADED=$s; echo "pf_load ok: $s"; }
# pf_latency [n] [max s]: harness round trip of n (8) quick calls; one slower than max (1.0 s) = the game is hitching
# (blkH 2026-10-10: a 1.5 s hole in the take sampler failed takecheck cover); stops the take before filming
pf_latency(){ local n=${1:-8} mx=${2:-1.0} i t0 t1 w=0
  for i in $(seq 1 "$n"); do t0=$(date +%s.%N); PF_A fp_vm state >/dev/null; t1=$(date +%s.%N)
    w=$(awk -v a="$t0" -v b="$t1" -v w="$w" 'BEGIN{d=b-a; printf "%.2f", (d>w?d:w)}'); done
  awk -v w="$w" -v m="$mx" 'BEGIN{exit !(w <= m)}' || pf_fail "harness round trip up to ${w} s (> ${mx} s): game hitching, the take sampler would leave gaps"
  echo "pf_latency ok: max ${w} s over $n calls"; }
# ---- non-exiting checks (PF_WHY = reason) ----
pf_melee_arm(){ local who=$1 bow w r g ws
  bow=$(PF_A rangedinfo "$who" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')
  [ -n "$bow" ] && PF_A unequip "$who" "$bow" >/dev/null
  ws=$(PF_A inv "$who" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${bow:-@@}")
  for w in "" "give"; do
    if [ "$w" = give ]; then g=${PF_MELEE_GIVE:-923-gamedata.base}
      r=$(PF_A give "$who" "$g" 1 | head -1); echo "$r" | grep -q ' got 1/' || { PF_WHY="$who has no melee weapon (carries: ${ws:-none}; ranged: ${bow:-none}) and give $g failed: $(cut -c1-90 <<<"$r")"; return 1; }
      ws=$(echo "$r" | sed -n 's/^.* got [0-9]*\/[0-9]* \(.*\) (now [0-9]*)$/\1/p'); [ -n "$ws" ] || ws=${PF_MELEE_GIVE_NAME:-Guardless Katana}; fi
    while IFS= read -r w2; do [ -n "$w2" ] || continue; r=$(PF_A equip "$who" "$w2")
      case "$r" in equipped*) PF_WEP=$w2; echo "pf_melee_arm ok: $who $w2${g:+ (given)}"; return 0;; esac; done <<<"$ws"
  done; PF_WHY="$who: no melee weapon equips (given ${g:-}: $(cut -c1-90 <<<"$r"))"; return 1; }
pf_cs(){ PF_A fp_combat state | grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
# pf_combat_on [who]: `fp_combat on` with repair (40-rangedrows 1011-0251: 15 rows "fp_combat on refused" in 3 min, harness
# "native bindings/hooks unavailable or faulted" on a reused game). A guarded native fault clears itself after 2 s (up to 3
# faults): poll + retry <= ~16 s, re-select <who> and retake FP control from the 2nd try. Still refused (native_ready=0 or a
# latched fault: only a relaunch clears it) = PF_WHY + the reason written to $RELAUNCH_FILE, so run-batch.sh relaunches the
# game before the next row instead of every later row failing the same way. 0 = manual combat on.
pf_combat_on(){ local i r s nr=? f=?
  for i in 1 2 3 4 5 6 7; do
    r=$(PF_A fp_combat on); case "$r" in *requested*) [ $i -gt 1 ] && echo "pf_combat_on: on at try $i"; return 0;; esac
    s=$(PF_A fp_combat state); nr=$(grep -o '\bnative_ready=[0-9]*' <<<"$s" | cut -d= -f2); f=$(grep -o '\bfault=[0-9]*' <<<"$s" | cut -d= -f2)
    [ "$nr" = 0 ] && break
    [ $i -ge 2 ] && { [ -n "$1" ] && PF_A select "$1" >/dev/null; PF_A fp_mode on >/dev/null; PF_A fp_control take >/dev/null; }
    sleep 2; done
  PF_WHY="fp_combat on refused after $i tries (native_ready=${nr:-?} fault=${f:-?}; latched: game relaunch requested): $(cut -c1-60 <<<"$r")"
  [ -n "${RELAUNCH_FILE:-}" ] && echo "$PF_WHY" > "$RELAUNCH_FILE"; return 1; }
pf_ranged_inj(){ local who=$1 e w r bow ws
  PF_A fp_combat input 0 0 0 >/dev/null; sleep 0.5
  if [ "$(pf_cs why)" = melee_in_hands ]; then
    PF_A input_isolation on >/dev/null; PF_A key_inject r tap 120 >/dev/null
    e=$((SECONDS+4)); while [ $SECONDS -lt $e ] && [ "$(pf_cs why)" = melee_in_hands ]; do sleep 0.3; done
    if [ "$(pf_cs why)" = melee_in_hands ]; then
      bow=$(PF_A rangedinfo "$who" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')
      ws=$(PF_A inv "$who" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${bow:-@@}")
      while IFS= read -r w; do [ -n "$w" ] && PF_A unequip "$who" "$w" >/dev/null; done <<<"$ws"; sleep 1; fi
    PF_A fp_combat input 0 0 0 >/dev/null; sleep 0.5
    [ "$(pf_cs why)" = melee_in_hands ] && { PF_WHY="melee weapon still in $who's hands after R + unequip (why=melee_in_hands)"; return 1; }
    echo "pf_ranged_inj: melee weapon put away"; fi
  # xbf-hits-r11 R11 (5090, after a save load with the katana drawn): R tap holstered the katana (no unequip), the injected
  # aim drew + loaded the crossbow (why=ok), on release the adapter said melee_in_hands with the crossbow in hands
  # (the katana stays equipped). Second pass: unequip every non-crossbow weapon, then arm again.
  local pass; for pass in 1 2; do
  [ $pass = 2 ] && { bow=$(PF_A rangedinfo "$who" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')
    ws=$(PF_A inv "$who" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${bow:-@@}")
    while IFS= read -r w; do [ -n "$w" ] && PF_A unequip "$who" "$w" >/dev/null; done <<<"$ws"; sleep 1
    echo "pf_ranged_inj: melee_in_hands after arming, unequipped: $(tr '\n' ',' <<<"$ws")"
    # xbf-hit3 (5090, after a reused game + in-place load): melee_in_hands with NO other weapon (inventory = the crossbow
    # only; the in-hands pointer != the ranged virtual's item): unequip + equip the crossbow itself to rebuild its slot
    if [ -z "$(tr -d '\n' <<<"$ws")" ] && [ -n "$bow" ] && [ "$bow" != none ]; then
      r=$(PF_A unequip "$who" "$bow"); sleep 0.5
      # xbf-hit4: a small main inventory sends it to the ground ("back -> ground"): pick it up at once (giveItem puts it
      # back in the free weapon slot or the inventory), then equip unless it already reads as the ranged weapon
      case "$r" in *ground*) r=$(PF_A pickup "$who" "$bow" now); sleep 0.5;; esac
      [ "$(PF_A rangedinfo "$who" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')" = "$bow" ] || r=$(PF_A equip "$who" "$bow"); sleep 1
      echo "pf_ranged_inj: no other weapon, crossbow re-equipped: $(cut -c1-80 <<<"$r") bow_now=$(PF_A rangedinfo "$who" | grep -o ' bow=[^=]* has_ammo' | sed 's/^ bow=//; s/ has_ammo$//')"; fi
    # rg03-0715 R10 (xbow-rows): with NO other weapon the hands still held a non-inventory object (wih=270e534e0, not the
    # crossbow 270e53f10) after the re-equip; the injected aim never draws while something is in hands (armed=0 for 14 s).
    # R holsters it (as at the start: wih=0, armed=1 why=holstered), so the arming below starts from holstered.
    if [ "$(pf_cs why)" = melee_in_hands ]; then local wih0; wih0=$(pf_cs wih)
      PF_A input_isolation on >/dev/null; PF_A key_inject r tap 120 >/dev/null
      e=$((SECONDS+4)); while [ $SECONDS -lt $e ] && [ "$(pf_cs why)" = melee_in_hands ]; do sleep 0.3; done
      echo "pf_ranged_inj: R tap after the re-equip: wih $wih0 -> $(pf_cs wih) why=$(pf_cs why)"; fi; }
  e=$((SECONDS+3)); while [ $SECONDS -lt $e ] && [ "$(pf_cs armed)" != 1 ]; do PF_A fp_combat input 0 0 0 >/dev/null; sleep 0.3; done
  if [ "$(pf_cs armed)" != 1 ] || [ "$(pf_cs loaded)" != 1 ]; then   # holstered and/or empty: an injected aim draws + auto-reloads
    PF_A fp_combat input 1 0 0 >/dev/null; e=$((SECONDS+14)); r=0
    while [ $SECONDS -lt $e ]; do
      [ "$(pf_cs armed)" = 1 ] && [ "$(pf_cs loaded)" = 1 ] && [ "$(pf_cs reloading)" = 0 ] && break
      if [ $r = 0 ] && [ $((e-SECONDS)) -lt 11 ] && [ "$(pf_cs reloading)" = 0 ] && [ "$(pf_cs loaded)" != 1 ]; then   # auto reload off: one reload press
        r=1; PF_A fp_combat input 1 0 1 >/dev/null; sleep 0.3; PF_A fp_combat input 1 0 0 >/dev/null; fi
      sleep 0.3; done
    PF_A fp_combat input 0 0 0 >/dev/null; sleep 1; fi
  [ "$(pf_cs why)" = melee_in_hands ] || break; done
  # xbr-hit-r10 R10 (5090): after the aim release the adapter read why=ui_open armed=0 for ~1 s (4 reads), then armed=1
  # loaded=1 why=ok: the single read below caught the transient. Bounded poll (3 s) before judging.
  e=$((SECONDS+3)); while [ $SECONDS -lt $e ] && ! { [ "$(pf_cs armed)" = 1 ] && [ "$(pf_cs loaded)" = 1 ]; }; do sleep 0.3; done
  [ "$(pf_cs armed)" = 1 ] && [ "$(pf_cs loaded)" = 1 ] || { PF_WHY="crossbow not drawn+loaded (armed=$(pf_cs armed) loaded=$(pf_cs loaded) reloading=$(pf_cs reloading) why=$(pf_cs why))"; return 1; }
  echo "pf_ranged_inj ok: armed=1 loaded=1"; }
pf_ko(){ PF_A hp "$1" | grep -q ' KO '; }
pf_awake(){ local c i; for c in "$@"; do [ -n "$c" ] || continue; PF_A health "$c" 100 >/dev/null; pf_ko "$c" || continue
    PF_A wake "$c" >/dev/null; for i in $(seq 1 12); do sleep 0.25; pf_ko "$c" || break; done
    pf_ko "$c" && { PF_WHY="$c stays knocked out after wake ($(PF_A hp "$c" | cut -c1-80))"; return 1; }; done; return 0; }
pf_pin(){ local who=$1 r at p i off; shift; r=$(PF_A pin "$who" "$@"); grep -q '^pinned' <<<"$r" && return 0
  at=$(grep -o ' at [-0-9.]*,[-0-9.]*,[-0-9.]* ' <<<"$r" | head -1 | sed 's/^ at //; s/ $//')
  [ -n "$at" ] || { PF_WHY="pin $who refused: $(cut -c1-100 <<<"$r")"; return 1; }
  for i in $(seq 1 12); do sleep 0.25; p=$(PF_A where "$who" | grep -o 'pos=[^ ]*' | cut -d= -f2)
    off=$(awk -v a="$p" -v b="$at" 'BEGIN{split(a,p,",");split(b,q,",");printf "%.1f", sqrt((p[1]-q[1])^2+(p[3]-q[3])^2)}')
    awk -v o="$off" 'BEGIN{exit !(o<=1.5)}' && return 0; done
  PF_WHY="pin $who stays off=$off from $at$(pf_ko "$who" && echo ' (KO: a ragdoll ignores pin)')"; return 1; }
PF_XBOW_RE='bow|toothpick|harpoon|eagle'
pf_noxbow(){ local c b seen=" " left=""; PF_WHY=""
  for c in "$@"; do [ -n "$c" ] || continue; case "$seen" in *" $c "*) continue;; esac; seen="$seen$c "
    PF_A inv "$c" | grep -o '"name":"[^"]*","equipped":true' | cut -d'"' -f4 | grep -iE "$PF_XBOW_RE" | sort -u |
      while IFS= read -r b; do PF_A unequip "$c" "$b" >/dev/null; done; done
  sleep 1
  for c in $seen; do b=$(PF_A inv "$c" | grep -o '"name":"[^"]*","equipped":true' | cut -d'"' -f4 | grep -iE "$PF_XBOW_RE" | paste -sd,)
    [ -n "$b" ] && left="$left $c:$b"; done
  [ -n "$left" ] && { PF_WHY="crossbow still equipped (crash-safety quarantine):$left"; return 1; }
  echo "pf_noxbow ok: no crossbow equipped on$seen"; return 0; }
# Step timing (speed-scout 2026-10-11, coordinator m102 "measure list START -> first row and cut it"): every pf_* step
# prints "PFTIME <step> <ms>" when it returns, so row logs show where the ~25 s of preflight per take goes
# (grep -h '^PFTIME' <out>/*.txt | awk '{s[$2]+=$3; n[$2]++} END {for (k in s) print k, n[k], s[k]/n[k]}').
# PF_PROFILE=0 turns it off. A step that ends the take (pf_fail -> exit) prints nothing.
if [ "${PF_PROFILE:-1}" = 1 ] && [ -z "${_PF_PROFILED:-}" ]; then _PF_PROFILED=1
  for _f in pf_load pf_rig pf_display pf_day pf_clean pf_area pf_weapon pf_ready pf_loaded pf_latency pf_open pf_nofight pf_noxbow pf_calm pf_clear pf_iso pf_melee_arm pf_combat_on; do
    declare -F "$_f" >/dev/null || continue
    eval "$(declare -f "$_f" | sed "1s/^$_f /_pft_$_f /")"
    eval "$_f(){ local _t=\${EPOCHREALTIME/./} _r; _pft_$_f \"\$@\"; _r=\$?; echo \"PFTIME $_f \$(( (\${EPOCHREALTIME/./} - _t) / 1000 ))\"; return \$_r; }"
  done; unset _f
fi
