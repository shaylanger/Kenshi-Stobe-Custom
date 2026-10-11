#!/bin/bash
# fp-turret-take.sh <out dir> [shooter Axima]   (WSL on the 5090, Git Bash on the 4080: RIG=5090|4080, rig-env.sh)
# T6 turret-fp take on the kah-fpturret-e fixture (launch: kah-fpturret-e): the shooter mans the Harpoon Turret in FP,
# aims left/right, fires at a spawned neutral dummy, reload countdown, power cut / back, walks off the turret.
# Rig-neutral repo version of the ad-hoc C:\KenshiTestRuns\f36 take (take5op.sh + t6load/away/clean/prep2/take3/vid/rec/
# render/chk.sh, f38 dayck/skyck, f24 tq.sh, f36 snaplabels.py, vidscripts/f26/mkfilt.py; speed-parity 2026-10-10) so
# either rig can run it: every file lives in <out dir> (no shared f36 dir), paths from rig-env.sh ($CR, $KDIR, $FFX), the
# recorder stops through a plain pipe (a native ffmpeg on the 4080 never reads q from an MSYS fifo).
# Preflight before recording: fixture reload, squad parked + KO, area clean, day (10-13 h) + clear sky + no storm,
# manual combat on, rig_preflight (capture live), dummy spawned + awake + pinned, turret loaded. Seat gate: not seated
# 15 s after USE_TURRET -> RESULT FAIL setup, nothing judged.
# Output in <out dir>: t6raw.mp4 (raw), turret-fp.mp4 (labels burned + centre zoom), labels.txt, ts.txt, ev.txt, review/;
# last line: RESULT T6-turret-fp PASS|FAIL [takecheck + openground + cursor + render] video=<out>/turret-fp.mp4
for d in /mnt/c /c; do [ -f $d/KenshiModding/tools/automation/rig-env.sh ] && { . $d/KenshiModding/tools/automation/rig-env.sh; break; }; done
OUT=$1; SH=${2:-Axima}; ROW=T6-turret-fp
[ -n "$OUT" ] || { echo "RESULT $ROW FAIL setup: no out dir (usage: fp-turret-take.sh <out dir> [shooter])"; exit 2; }
mkdir -p "$OUT" && cd "$OUT" || { echo "RESULT $ROW FAIL setup: out dir $OUT not usable"; exit 2; }
export KAH_OWNER=${KAH_OWNER:-$([ "${RIG:-5090}" = 4080 ] && echo rig4080 || echo kfp-fixer)}
M=${CR:-/mnt/c}/KenshiModding; HL=$M/Kenshi-Automation-Harness/tools/animlab; TI=$M/components/KenshiFP/tests/ingame
FFX=${FFX:-/mnt/c/Users/Shay/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}
SAVE=${TURRET_SAVE:-kah-fpturret-e}; TX=-54055; TZ=7300   # turret spot of kah-fpturret-e
A(){ stobe-auto "$@" </dev/null 2>&1; }
ft(){ A fp_turret | tr ' ' '\n' | grep -E "^(on|why|ammo|reload_left|reload_max|rl_state|aim_valid|aim|cur_dir|aim_err_deg|shots|refused|refuse_why|reloads|r_ignored|native_shots_suppressed|ai_updates_suppressed|enters|leaves)=" | tr '\n' ' '; echo; }
tq(){ A turret "Harpoon Turret" radius 3000 | grep -o "loaded=[^ ]* reloading=[^ ]*\|on_turret=[0-9]\|aim_target=[^ ]*\|aim_err_deg=[^ ]*\| fired=[^ ]*\|ranged=[A-Z]*\|last_shot_stat=[^ ]*" | tr '\n' ' '; echo; }
fail(){ A chatter on >/dev/null; echo "RESULT $ROW FAIL setup: $*"; exit 1; }
hour(){ local h; h=$(A time | grep -o 'time=[0-9]*'); echo $((10#${h#time=})); }
dayck(){ local h; h=$(hour); if [ "$h" -lt 10 ] || [ "$h" -gt 13 ]; then A speed 50 hold >/dev/null; for i in $(seq 1 200); do sleep 2; h=$(hour); [ "$h" -ge 10 ] && [ "$h" -le 13 ] && break; done; A speed 1 hold >/dev/null; fi; echo "$(A time | cut -c1-60)"; }
skyck(){ A fp_camera look 0 0.05 >/dev/null; sleep 1; A screenshot skyck >/dev/null; ( cd "$KDIR/mods/AutomationHarness/shots" && "$FFX" -hide_banner -loglevel error -y -i skyck.png -vf "crop=1600:120:0:30,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | od -An -tu1 ) | awk '{print "SKY", $1, $2, $3, ($3 > $1+25 ? "clear" : "hazy")}'; }
clean(){   # m88: knock out + pin every live non-squad NPC within R of the turret, so nobody walks/talks into the take
  local R=${R:-3000}
  { A chars 6000; for f in "Starving" "Dust Bandits" "Hungry" "Outlaws" "Marauder" "Shinobi"; do A chars 6000 "$f"; done; } 2>/dev/null | sed "s/^[0-9]* within [0-9.]*: //" | sed 's/ | /\n/g' | grep -v "\[Nameless\]\| KO\| DEAD" | sed -n 's/.*\(#[0-9]*\/[0-9]*\) .* pos=\([-0-9.]*\),[-0-9.]*,\([-0-9.]*\).*/\1 \2 \3/p' | sort -u | while read id x z; do
    d=$(awk -v x=$x -v z=$z -v a=$TX -v b=$TZ 'BEGIN{printf "%d", sqrt((x-a)^2+(z-b)^2)}')
    [ "$d" -lt "$R" ] || continue
    A pin "$id" >/dev/null; A ko "$id" 900 | cut -c1-60; echo "  $id d=$d"
  done
}

# ---- fixture reload (t6load) + squad away (away) + area clean
A fp_camera distance 0 >/dev/null; A fp_camera zoommode switch >/dev/null
A load "$SAVE" | cut -c1-100
for i in $(seq 1 60); do sleep 3; A status | grep -q "phase=ingame\|phase=world\|in_game" && break; done
A wait-world | tail -1 | cut -c1-100
A input_isolation status | grep -q "isolation=on" || A input_isolation on >/dev/null
A input_isolation status | grep -q "isolation=on" || fail "input isolation would not turn on (mouse_inject needs it)"
A pin Malzin at -53900 650 4800 >/dev/null; A pin Tassilo at -53940 650 4800 >/dev/null; A pin Shay at -53980 650 4800 >/dev/null
sleep 2; for n in Malzin Shay; do A ko $n 900 >/dev/null; done   # squad far behind the camera + KO: nobody joins when the harpoon hits
clean
A speed 10 hold >/dev/null; sleep 6; A speed 1 hold >/dev/null; sleep 8   # op-t6c: let a "wiped out" world message fire + fade
A select $SH >/dev/null; A fp_control take >/dev/null; dayck
# manual-combat preflight (kfp-turret, op-comb2 no-seat): the FP turret module runs inside the manual-combat tick
A fp_combat input 0 0 0 >/dev/null; A fp_combat on >/dev/null; sleep 0.5
A fp_combat state | grep -q "enabled=1" || fail "manual combat off (fp_combat on refused: $(A fp_combat state | grep -o 'enabled=[^ ]* native_ready=[^ ]* fault=[^ ]*'))"
for t in 1 2 3 4 5 6; do s=$(skyck); echo "sky $t $s"; echo "$s" | grep -q clear && break; A speed 50 hold >/dev/null; sleep 25; A speed 1 hold >/dev/null; done
# weather preflight (op-t6: a Dust Storm read "clear" by the sky check): wait out a storm via the stat weather factor
wx(){ A stat $SH perception | grep -o "weather=[0-9.]*" | cut -d= -f2; }
for t in 1 2 3 4 5 6; do w=$(wx); echo "weather $t ${w:-?}"; awk -v w="${w:-1}" "BEGIN{exit !(w>=0.99)}" && break; A speed 50 hold >/dev/null; sleep 25; A speed 1 hold >/dev/null; done
w=$(wx); awk -v w="${w:-1}" "BEGIN{exit !(w>=0.99)}" || fail "storm (weather factor $w) after 6 waits"
dayck
A chatter off >/dev/null

# ---- take prep (prep2): neutral non-squad dummy (a squad dummy shows its name tag over the centre), turret powered + loaded
dayck; clean >/dev/null
A fp_camera distance 0 >/dev/null; A select $SH >/dev/null; A fp_control take | cut -c1-50
A power 'Harpoon Turret' on radius 3000 >/dev/null; A power 'Harpoon Turret' supply radius 3000 | grep -o "has_power=[^ ]*"
A fp_move w 1200 >/dev/null; sleep 2; A teleport $SH $TX 690 $TZ | cut -c1-60; sleep 2
SP=$(A spawn "Hungry Bandit" "Tech Hunters" near $SH dist 30 count 1); D=$(grep -oE '#[0-9]+/[0-9]+' <<<"$SP" | head -1)
[ -n "$D" ] || fail "dummy spawn failed ($SP)"
echo "$D" > dummy.txt; A relation "$D" 20 >/dev/null; A setstat "$D" dodge 1 >/dev/null; A pin Tassilo at -53940 650 4800 >/dev/null
A wake $D | cut -c1-40; A health $D 100 >/dev/null; A blood $D 100% | cut -c1-60; A protect $D on | cut -c1-40; A pin $D at -54070 690 7400 face $SH | cut -c1-60
for i in $(seq 1 30); do A turret 'Harpoon Turret' radius 3000 | grep -q "loaded=1" && break; sleep 1; done; tq
for i in $(seq 1 30); do A hp $D | grep -q " KO" || break; A wake $D >/dev/null; sleep 1; done; A hp $D | cut -c1-60
A hp $D | grep -q " KO" && fail "dummy $D still KO after 30 wakes"
A fp_combat physical >/dev/null; A fp_camera look 0.22 -0.075 >/dev/null; ft | cut -c1-40; A time | cut -c1-50
rig_preflight $ROW || { A chatter on >/dev/null; exit 1; }

# ---- video steps (vid.sh; t0 = recording start)
LOGN=$(wc -l < "$KDIR/KenshiFP.log" 2>/dev/null || echo 0)
O=$PWD/labels.txt; E=$PWD/ev.txt; rm -f setup_fail.txt
steps(){
  : > $O; : > $O.snap; : > $E
  T0=$(date +%s.%N); lab(){ echo "$(awk -v a=$(date +%s.%N) -v b=$T0 "BEGIN{printf \"%.2f\", a-b}") $*" >> $O; type take_mark >/dev/null 2>&1 && take_mark "$*"; }   # sync flash per label
  # waitlab <pattern> <secs> <label> [floor t]: poll fp_keys state until the HUD shows <pattern>; fp-take-labels.py snap moves it onto the sampled switch
  waitlab(){ local t p="${4:-}" e=$((SECONDS+$2)); while :; do [ -n "$t" ] && p=$t; t=$(awk -v a=$(date +%s.%N) -v b=$T0 "BEGIN{printf \"%.2f\", a-b}"); A fp_keys state | grep -q "$1" && break; [ $SECONDS -ge $e ] && break; sleep 0.1; done; echo "${p:-$t} $3" >> $O; type take_mark >/dev/null 2>&1 && take_mark "$3"; printf '%s\t%s\t%s\n' "${4:-${p:-$t}}" "$1" "$3" >> $O.snap; }
  ev(){ echo "$(awk -v a=$(date +%s.%N) -v b=$T0 "BEGIN{printf \"%.2f\", a-b}") $1 $(ft | cut -c1-120) | $(A fp_keys state | grep -o 'hud_text=[^ ]*') | $(A hp "$D" | cut -c1-70)" >> $E; }
  now(){ awk -v a=$(date +%s.%N) -v b=$T0 "BEGIN{printf \"%.2f\", a-b}"; }
  . $M/components/KenshiFP/animlab/take-sample.sh; take_sample_start $PWD/ts.txt "$T0" $SH "$D"
  A fp_combat physical >/dev/null; A mouse_inject at 1595 4 >/dev/null   # park the virtual cursor (name tag / interact icon at centre)
  lab "Standing next to the turret (no turret state)"; A fp_camera look 0.22 -0.075 >/dev/null; ev stand; sleep 3.5
  lab "Seat: $SH mans the Harpoon Turret"; A order $SH USE_TURRET building "Harpoon Turret" >/dev/null
  notseated(){ ev "$1"; echo "$1 ($(ft | cut -c1-120))" > setup_fail.txt; lab end; take_sample_stop; exit 3; }
  for i in $(seq 1 30); do ft | grep -q "on=1" && break; sleep 0.5; done; ft | grep -q "on=1" || notseated "not seated 15 s after USE_TURRET"
  A fp_camera look 0.22 -0.075 >/dev/null; sleep 1; ev seated; for i in $(seq 1 24); do ft | grep -q "ammo=1/1" && break; sleep 0.5; done; sleep 1
  lab "Aim left (turret follows the camera)"; A fp_camera look 0.63 -0.07 >/dev/null; sleep 2.5
  lab "Aim right"; A fp_camera look -0.17 -0.07 >/dev/null; sleep 2.5
  # tur-a: pitch -0.075 aimed at the feet (harpoon into the ground short of the dummy) -> aim at the torso
  lab "Aim at the dummy"; P=-0.02; Y=0.22; for y in 0.22 0.215 0.225 0.21 0.23 0.205 0.235 0.20 0.24; do A fp_camera look $y $P >/dev/null; sleep 0.35; A fp_combat aim | grep -q "victim=[1-9a-f]" && { Y=$y; break; }; done; echo "yaw=$Y" >> $E; sleep 1.5; A fp_combat aim | grep -q "victim=[1-9a-f]" || A fp_camera look $Y $P >/dev/null; ev aimed
  lab "LMB: fire -> harpoon hits the dummy"; A mouse_inject left click 80 >/dev/null; sleep 0.6; ev fired; sleep 1.0; lab "Reloading: countdown under the crosshair"; ev hit
  waitlab "hud_text=loaded" 9 "Reloaded: LOADED"; ev loaded; sleep 2.5
  tp=$(now); A power 'Harpoon Turret' unsupply radius 3000 >/dev/null; A power 'Harpoon Turret' off radius 3000 >/dev/null; waitlab "hud_text=no" 5 "Power cut: NO POWER" $tp; sleep 1; ev nopower; A mouse_inject left click 80 >/dev/null; sleep 1.5; ev nopower_fire
  tp=$(now); A power 'Harpoon Turret' on radius 3000 >/dev/null; A power "Harpoon Turret" supply radius 3000 >/dev/null; waitlab "hud_text=loaded" 5 "Power back: LOADED" $tp; sleep 3; ev power
  ft | grep -q "on=1" || notseated "not seated before the walk-off step (left the turret early)"
  lab "W: leaves the turret"; A fp_move w 500 >/dev/null; for i in $(seq 1 20); do ft | grep -q "on=1" || break; sleep 0.2; done; ev offturret; waitlab "hud_text=holstered" 4 "Off the turret: turret HUD gone, crossbow holstered"; sleep 0.6; A fp_move s 900 >/dev/null; sleep 1.4; A fp_camera look 0.22 0.03 >/dev/null; sleep 1.5; ev left
  lab end; take_sample_stop; python3 $TI/fp-take-labels.py snap labels.txt ts.txt
}
# recorder (rec.sh): stopped by "q" through a plain pipe once the steps end (+2.5 s tail); 300 s is only a safety cap
rm -f rec.stop; A mouse_inject at 1595 4 >/dev/null   # park the virtual cursor in the sky before recording (hover name tag, take-dryrun)
( while [ ! -f rec.stop ]; do sleep 0.1; done; echo q ) | "$FFX" -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -framerate 30 -t 300 -i "title=${WIN_TITLE:-Kenshi 1.0.65 - x64 (Newland)}" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p t6raw.mp4 &
FP=$!; sleep 0.8; ( steps ); RC=$?; sleep 2.5; touch rec.stop; wait $FP; rm -f rec.stop
A chatter on >/dev/null
L=$(tail -n +$((LOGN+1)) "$KDIR/KenshiFP.log" 2>/dev/null | grep "harpoon hit\|harpoon still" | tail -1); echo "take: ${L:15:90}"
grep -o "^[0-9.]* [a-z_]*\|blood=[^ ]*\|yaw=.*" ev.txt | paste -sd' '
# seat gate: a take that never seated stops with a setup FAIL, nothing is judged/rendered
if [ -s setup_fail.txt ] || [ $RC = 3 ]; then [ -n "${GAME_DONE_FILE:-}" ] && : > "$GAME_DONE_FILE"; echo "RESULT $ROW FAIL setup: $(head -1 setup_fail.txt 2>/dev/null)"; exit 1; fi
[ -n "${GAME_DONE_FILE:-}" ] && : > "$GAME_DONE_FILE"; echo "pf_game_done: game part over, analysis next"   # run-batch moves the game on while render/checks/pack run

# ---- render (labels burned, centre x2.5 inset) + checks + review pack
cp "${CR:-/mnt/c}/Windows/Fonts/arialbd.ttf" . 2>/dev/null
E2=$(awk '$2=="end"{print $1+0.5}' labels.txt)
rm -f filt.txt; RF="RESULT render FAIL mkfilt"
if python3 $TI/fp-take-labels.py filt labels.txt ${LAG:-1.25} filt.txt; then
  F=$(tr -d '\n' < filt.txt)
  "$FFX" -hide_banner -loglevel error -y -i t6raw.mp4 -t ${E2:-59} -filter_complex "[0:v]split[a][b];[b]crop=256:144:672:378,scale=640:360:flags=lanczos,drawbox=c=yellow:t=3,drawtext=fontfile=arialbd.ttf:fontsize=22:fontcolor=yellow:x=10:y=10:text='centre x2.5'[z];[a][z]overlay=W-w-12:110,$F" -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p turret-fp.mp4 && RF="" || RF="RESULT render FAIL ffmpeg"
fi
C=$( { python3 $HL/takecheck.py --labels labels.txt --ev ts.txt --rules $M/components/KenshiFP/animlab/take-rules.txt --video turret-fp.mp4 2>&1 | tail -15; python3 $HL/frames.py openground turret-fp.mp4 2>&1 | tail -3; } | grep "^RESULT" | tr '\n' ' ')
CU=$(python3 $HL/frames.py cursor turret-fp.mp4 2>&1 | tail -1)
rm -rf review; python3 $M/tools/automation/review-pack.py turret-fp.mp4 review --ts ts.txt --labels labels.txt --offset ${LAG:-1.25} > review.log 2>&1
echo "RESULT $ROW $(echo "$C $CU $RF" | grep -q FAIL && echo FAIL || echo PASS) [$C $CU $RF] video=$PWD/turret-fp.mp4"
