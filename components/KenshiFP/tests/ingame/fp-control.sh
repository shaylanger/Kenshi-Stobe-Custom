#!/usr/bin/env bash
# fp-control.sh: in-game Gate 1 camera/control rows C01-C05 (COMBAT_TEST_PLAN.md), beyond the C00 numeric subset
# (validate_camera_control.py, merged-1/c00c). Same readbacks as C00 (fp_camera state, fp_control state) plus real
# movement: KenshiFP 32905BE5+ `fp_move <wasd|none> <ms>` holds WASD through the same fp_movement path as the keys
# (bounded, focus not needed) and `fp_control press` queues one key_take_control (F6) press (same UI gate as the key).
# Run in WSL with Kenshi in the world on kah-fpxbow right after load (Axima = squad crossbow user, Malzin = squad mate,
# Skaera = hostile Hungry Bandit, knocked out for the run so nobody fights). Speed 1, FP on, Axima controlled.
# Evidence: `where` positions (world units, ~10 per metre), fp_camera state (target/applied/actual_distance/eye/
# blocked/speed_scale/anchor_*), fp_control state (controlled/inspected/control_ids/take_*), fp_move state, fp_state.
# Rows (one `RESULT <row> PASS|FAIL <evidence>` each):
#  C01  FP eye -> third person -> eye: camera at the applied distance (|actual-applied|<.2, eye flag), same controlled
#       actor, W moves him >= MOVE_MIN along the camera forward (<35 deg) in both views, camera anchor follows him
#  C02  wheel changes target distance (out and back) with speed_scale unchanged; W displacement third person / FP
#       within 0.75..1.33; with the inventory open (ui_open=1) a wheel leaves target/applied/speed_scale unchanged
#  C03  select the mate (inspect): controlled actor and ids unchanged, inspected = mate; W moves the controlled actor
#       (mate not driven), camera anchor follows the controlled actor; the inventory opened while inspecting shows the
#       mate's name (ui widgets) and not the controlled actor's; controlled unchanged after closing
#  C04-TAKE      F6 press with the inventory open is ignored; F6 press while W is held moves control to the selected mate:
#                old actor stops (released inputs), mate walks with the held W and stops on release
#  C04-FALLBACK  native AI order to the mate works while the player is directly controlled; FP off with W held: actor
#                stops (dm_active=0), a native move order moves him (native controls back); FP on again keeps the
#                pinned actor and does not move without input
#  C05-KO        KO with W held: no drive while down (dm_active=0), same actor after waking, still after release, fresh W moves
#  C05-INVALID   controlled mate leaves the squad (`faction`, new handle) with W held: ownership released (direct=0) in
#                3 s, no silent transfer, nobody driven; explicit take of the player restores WASD
#  C05-LOAD      load (W held through the load, released after): nobody walks on, camera valid, take + W moves, stops
#  C05-INTERIOR  in a building (INTERIOR="<buildings filters>", tried in order, default "house shack bar shop hut tower home"): walk into a
#                wall, turn the camera so the wall is behind, third person: blocked=1 and applied<target; S walks away
#  C05-STAIRS    from the bottom of a stair facing up it (STAIRS="x y z yaw", else found at runtime in a Storm House the
#                run builds and removes): W climbs |dy| >= 10, stops on release
# Usage: fp-control.sh [player] [mate] [target] [outdir]. Env: MOVE_MIN (10), STILL_MAX (3), STALL_MS (250), INVALID_FACTION (Drifters),
# INTERIOR, STAIRS. Leaves the fixture changed (save kah-fp-c05 written, Skaera KO, player moved): reload it after.
SH=${1:-Axima}; MT=${2:-Malzin}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-control}
MOVE_MIN=${MOVE_MIN:-10}; STILL_MAX=${STILL_MAX:-3}; STALL_MS=${STALL_MS:-250}; INVALID_FACTION=${INVALID_FACTION:-Drifters}
INTERIOR=${INTERIOR:-}; STAIRS=${STAIRS:-}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cam() { A fp_camera state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
fps() { A fp_state | fld "$1"; }
mvs() { A fp_move state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }      # "x y z"
# nwid <filter>: widget count from the one-line `ui` reply "N widget(s) | ..." (0 if none/unparsed)
nwid() { local n; n=$(A ui "$1" | grep -o '^[0-9]* widget' | grep -o '^[0-9]*'); echo "${n:-0}"; }
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
# d2 "x y z" "x y z": horizontal distance; dy: vertical change
d2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}'; }
dy() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", q[2]-p[2]}'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0<b+0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.25; done; return 1; }
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
ui_is() { [ "$(fps ui_open)" = "$1" ]; }
mode() { A fp_mode "$1" >/dev/null; waitf 4 fp_is "$([ "$1" = on ] && echo 1 || echo 0)"; }
# take <name>: select + FP on + explicit take (harness path); true when control_ids are his
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; mode on; A fp_control take >/dev/null; ctl_is "$1"; }
# camera: wait until actual matches applied and the predicate on applied holds ("eye" | "far")
cam_ok() { local c; c=$(A fp_camera state); awk -v v="$(fld actual_valid <<<"$c")" -v a="$(fld actual_distance <<<"$c")" \
  -v p="$(fld applied <<<"$c")" -v e="$(fld eye <<<"$c")" -v w="$1" \
  'BEGIN{d=a-p; if(d<0)d=-d; ok=(v=="1" && a!="" && d<.20); if(w=="eye") ok=ok && p<.05 && e=="1"; if(w=="far") ok=ok && p>.75 && e=="0"; exit !ok}'; }
camsum() { local c; c=$(A fp_camera state); echo "target=$(fld target <<<"$c") applied=$(fld applied <<<"$c") actual=$(fld actual_distance <<<"$c") eye=$(fld eye <<<"$c") blocked=$(fld blocked <<<"$c")"; }
anchor() { local c; c=$(A fp_camera state); echo "$(fld anchor_x <<<"$c") $(fld anchor_y <<<"$c") $(fld anchor_z <<<"$c")"; }
look() { A fp_camera look "$1" "${2:-0}" >/dev/null; sleep 0.3; }
YAW=0
# walk <who> <keys> <ms>: hold keys, echo "<horizontal displacement> <angle to camera forward deg> <anchor displacement>
# <mid move_speed, sampled only while moving=1, else na> <worst frame ms during the hold (fps window), na if unknown>"
# fp_move's hold is wall-clock: a frame stall (first walk after a load ran ~15 fps with 12 s frames) shortens the walk.
# align: one short W tap so the body turns to the camera yaw before a measured walk (after a KO or a control
# transfer the body faces anywhere; the turn-in-place at tip_turn rate ate most of a 2 s walk: 4080 b30 C05-INVALID
# walk=7.67 moving ~90 deg off the look)
align() { A fp_move w 1000 >/dev/null; sleep 1.6; }
walk() { local p0 p1 a0 a1 ms2 sp st wm; p0=$(pos "$1"); a0=$(anchor); A fps reset >/dev/null; A fp_move "$2" "$3" >/dev/null
  ms2=$(awk -v m="$3" 'BEGIN{printf "%.2f", m/2000}'); sleep "$ms2"; st=$(A fp_move state)
  echo "$st" > "$OUT/last_walk_state.txt"; sp=$( [ "$(fld moving <<<"$st")" = 1 ] && fld move_speed <<<"$st"); sleep "$ms2"; sleep 0.6
  p1=$(pos "$1"); a1=$(anchor); wm=$(A fps | fld worst_ms)
  awk -v a="$p0" -v b="$p1" -v c="$a0" -v d="$a1" -v y="$YAW" -v k="$2" -v sp="$sp" -v wm="$wm" 'BEGIN{split(a,p," ");split(b,q," ");split(c,u," ");split(d,v," ")
    dx=q[1]-p[1]; dz=q[3]-p[3]; m=sqrt(dx*dx+dz*dz); fx=sin(y); fz=cos(y); if(k=="s"){fx=-fx;fz=-fz}
    ang=(m>0.01)?atan2(sqrt((dx*fz-dz*fx)^2), dx*fx+dz*fz)*57.2958:180
    am=(u[1]==""||v[1]=="")?-1:sqrt((v[1]-u[1])^2+(v[3]-u[3])^2)
    printf "%.2f %.1f %.2f %s %s\n", m, ang, am, (sp==""?"na":sp), (wm==""?"na":wm)}'; }
# walkr: walk, redone (up to WALK_TRIES walks in all) while a frame stall (worst_ms > STALL_MS) shortened the hold; the
# last walk's numbers are used (each redo logged as STALL). The assertions stay the same; a sample that is still stalled
# is reported as such by the row (b28 C02: the FP walk stalled twice, 1100 then 557 ms, ratio 1.34 = lost hold time;
# the same FP walk unstalled in C03 covered 103.65 vs third person 103.06).
WALK_TRIES=${WALK_TRIES:-3}
walkr() { local r w i=1; r=$(walk "$@"); w=$(awk '{print $5}' <<<"$r")
  while ge "$w" "$STALL_MS" && [ $i -lt "$WALK_TRIES" ]; do i=$((i+1))
    echo "STALL walk $* worst_ms=$w: redo $i/$WALK_TRIES" >> "$LOG"; r=$(walk "$@"); w=$(awk '{print $5}' <<<"$r"); done; echo "$r"; }
# native_walk <who> [axis]: native timed walk (walktime 40 walk) along the first axis that really walks (>= 25):
# a blocked path is setup, not the row (b27: Malzin +x stopped 35 m short). Echo "<displacement> <axis> <tries>".
native_walk() { local ax p0 d=0 n=0 tried=" "
  for ax in "${2:-+x}" +x -x +z -z; do case "$tried" in *" $ax "*) continue;; esac; tried+="$ax "; n=$((n+1))
    inworld || { ax=stuck; break; }   # game not in the world (Kenshi "Loading..." pause): no 180 s walk retries
    p0=$(pos "$1"); A walktime "$1" 40 "$ax" walk >/dev/null; d=$(d2 "$p0" "$(pos "$1")"); ge "$d" 25 && break; done
  echo "$d $ax $n"; }
# inworld: status phase=world. alive <where>: bounded poll (20 s) for it; a game stuck out of the world (b28: FP off
# left Kenshi paused on "Loading..." for >1 h, every walk then burned 180 s) ends the run as SETUP FAIL with the reason,
# after the rows already judged.
inworld() { A status | grep -q 'phase=world'; }
alive() { inworld && return 0; waitf 20 inworld && return 0; local s; s=$(A status)
  for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
  echo "RESULT SETUP FAIL game stuck out of the world $1 (20 s): $s log=$LOG"; echo "SETUP FAIL stuck $1: $s" >> "$LOG"; exit 1; }
# still <who> <s>: displacement over s seconds (no input expected)
still() { local p0; p0=$(pos "$1"); sleep "$2"; d2 "$p0" "$(pos "$1")"; }
# pick_yaw <who> <label>: set YAW to the one of 16 headings whose walk line (-30..130 units, covers the C01 walk back)
# passes farthest from the other two of player/mate/target. 4080 b31 C01: YAW was whatever the camera had and the walk
# passed ~5 units from the KO'd Skaera body (deflected 11 deg, move_speed 34, fp/tp ratio 0.42). Sets YAWC (clearance).
# pick_yaw "<who>[|<who2>]" <label>: with two walkers (C04-TAKE: the walk continues on the mate after the transfer),
# the heading must be clear on BOTH walk lines, each against the other characters (4080 b32/b33 C04-TAKE: the yaw
# was picked for the player only and the mate stopped after 17-46 units).
pick_yaw() { local p o c r w wl="" ol=""
  local IFS0=$IFS; IFS="|"; set -f; local ws=($1); IFS=$IFS0; set +f
  for w in "${ws[@]}"; do p=$(pos "$w" | tr ' ' ','); o=""
    for c in "$SH" "$MT" "$TG"; do [ "$c" = "$w" ] && continue; o+="$(pos "$c" | tr ' ' ',');"; done
    wl+="$p|"; ol+="$o|"; done
  r=$(awk -v wl="$wl" -v ol="$ol" 'BEGIN{nw=split(wl,W,"|"); split(ol,O,"|"); best=-1; by=0
    for(k=0;k<16;k++){y=-3.14159+k*6.28318/16; fx=sin(y); fz=cos(y); m=1e9
      for(j=1;j<=nw;j++){ if(W[j]=="") continue; split(W[j],s,","); n=split(O[j],ob,";")
        for(t=-30;t<=130;t+=10){x=s[1]+fx*t; z=s[3]+fz*t
          for(i=1;i<=n;i++){ if(ob[i]=="") continue; split(ob[i],q,","); d=sqrt((q[1]-x)^2+(q[3]-z)^2); if(d<m)m=d }}}
      if(m>best){best=m; by=y}}
    printf "%.4f %.1f\n", by, best}')
  YAW=${r%% *}; YAWC=${r##* }; echo "YAW $2 ($1): yaw=$YAW clearance=$YAWC" >> "$LOG"; }
# mvdiag: get-up/pinned inputs from the mid-hold `fp_move state` of the last walk (KenshiFP 272A573C+)
mvdiag() { local s; s=$(cat "$OUT/last_walk_state.txt" 2>/dev/null)
  echo "moving=$(fld moving <<<"$s") direct=$(fld direct_drive <<<"$s") dm=$(fld dm_active <<<"$s") speed=$(fld move_speed <<<"$s") prone=$(fld prone <<<"$s") in_bed=$(fld in_bed <<<"$s") head_above=$(fld head_above <<<"$s") stuck=$(fld stuck_frames <<<"$s") pinned=$(fld pinned <<<"$s") downed=$(fld downed <<<"$s") ko=$(fld ko <<<"$s")"; }
# native_fix <who> <axis> <home "x y z">: native_walk; if no axis walks (b28/b31 C04-FALLBACK: "never started" on all
# 4 axes at x~-54330, while b30 at z~6854 walked), note where he stood, teleport him back to <home> (his setup
# position) and try once more. Echo "<displacement> <axis> <tries> <stuck_at x,z | ->"; the row flags a stuck spot.
# natdiag <who> <why>: evidence for a native walk that never started (4080 b31/b33 C04-FALLBACK/C05-LOAD walk 0.00
# for both chars, also with FP off): where (state/pos), its jobs, buildings within 30 (inside an enclosure?).
natdiag() { { echo "NATDIAG $1 $2"; echo "  where: $(A where "$1")"; echo "  jobs: $(A jobs "$1" | tr '\n' ';' | cut -c1-600)"
  echo "  buildings: $(A buildings 30 near "$1" | tr '\n' ';' | cut -c1-900)"; } >> "$LOG"; }
native_fix() { local d ax n sp=-; read -r d ax n <<<"$(native_walk "$1" "$2")"
  if [ "$ax" != stuck ] && ! ge "$d" 25 && [ -n "$3" ]; then sp=$(pos "$1" | awk '{printf "%.0f,%.0f", $1, $3}')
    echo "SETUP: $1 native walk never started at $sp: teleport back to $3, retry" >> "$LOG"
    natdiag "$1" "never started at $sp"
    A teleport "$1" $3 >/dev/null; sleep 2; read -r d ax n <<<"$(native_walk "$1" "$2")"; n="$n+retry"
    ge "$d" 25 || natdiag "$1" "never started after the retry from $3"; fi
  echo "$d $ax $n $sp"; }
FP0=$(fps fp_mode); DIST0=$(cam target)
BUILT=""
cleanup() { A fp_move none >/dev/null; A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
            for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
            [ -n "$BUILT" ] && A unbuild Storm 2000 >/dev/null   # the C05-STAIRS house
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
A fp_move state | grep -q '^keys=' || setup_fail "KenshiFP has no fp_move (needs 32905BE5+)"
A fp_control state | grep -q 'take_presses=' || setup_fail "KenshiFP has no fp_control press (needs 32905BE5+)"
. "$(dirname "$0")/fp-ui-guard.sh" 2>/dev/null || { ui_guard_setup() { :; }; ui_clear() { return 0; }; ui_summary() { echo "ui_guard=missing"; }; }
# speed hold: the game paused itself (squad event) mid-run in b27 and froze a native walk at seconds=0.0
A speed 1 hold >/dev/null; A fp_move none >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
if A where "$TG" | grep -q 'pos='; then A protect "$TG" off >/dev/null; A ko "$TG" 3600 >/dev/null; waitf 15 isko "$TG" || echo "SETUP: $TG never KO" >> "$LOG"; fi
ui_guard_setup; ui_clear
take "$SH" || setup_fail "could not take $SH ($(A fp_control state))"
pick_yaw "$SH" C01; look "$YAW" 0
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye || setup_fail "camera never at eye ($(camsum))"
H0=$(ctl controlled); IDS0=$(ctl control_ids); HOME_SH=$(pos "$SH"); HOME_MT=$(pos "$MT")

# ---- C01: eye -> third person -> eye, control + WASD + camera ----
ui_clear; look "$YAW" 0; YAW0=$YAW; YAWC0=$YAWC; read -r M1 G1 AN1 SP1 WM1 <<<"$(walkr "$SH" w 2000)"
EYE1=$(camsum); A fp_camera distance 3 >/dev/null; waitf 6 cam_ok far; FAROK=$?; FAR=$(camsum)
H1=$(ctl controlled); YAW=$(awk -v y="$YAW" 'BEGIN{y+=3.14159; if(y>3.14159)y-=6.28318; printf "%.4f", y}'); look "$YAW" 0
read -r M2 G2 AN2 SP2 WM2 <<<"$(walkr "$SH" w 2000)"
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye; EYEOK=$?; EYE2=$(camsum); H2=$(ctl controlled); IDS2=$(ctl control_ids)
ev="yaw=$YAW0 clearance=$YAWC0 | fp_walk=$M1 ang=$G1 anchor=$AN1 | far[$FAR] ok=$((1-FAROK)) tp_walk=$M2 ang=$G2 anchor=$AN2 | back_eye[$EYE2] ok=$((1-EYEOK)) | controlled=$H0/$H1/$H2 ids_same=$([ "$IDS0" = "$IDS2" ] && echo 1 || echo 0)"
ok=1; [ $FAROK = 0 ] && [ $EYEOK = 0 ] && [ "$H0" = "$H1" ] && [ "$H1" = "$H2" ] && [ "$IDS0" = "$IDS2" ] || ok=0
for m in "$M1" "$M2"; do ge "$m" "$MOVE_MIN" || ok=0; done
for g in "$G1" "$G2"; do lt "$g" 35 || ok=0; done
# camera anchor follows the walking actor (within 25% or 3 units)
for p in "$M1:$AN1" "$M2:$AN2"; do awk -v m="${p%%:*}" -v a="${p##*:}" 'BEGIN{t=m*.25; if(t<3)t=3; d=m-a; if(d<0)d=-d; exit !(a>=0 && d<=t)}' || ok=0; done
judge C01 $ok "$ev"

# ---- C02: wheel = distance only; speed unchanged; UI wheel does not zoom ----
alive "before C02"; ui_clear; S0=$(cam speed_scale); T0=$(cam target); A fp_camera wheel -720 >/dev/null; sleep 0.8
T1=$(cam target); S1=$(cam speed_scale); A fp_camera wheel 720 >/dev/null; sleep 0.8; T2=$(cam target); S2=$(cam speed_scale)
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye
A click INV >/dev/null; waitf 4 ui_is 1; UIO=$?; TU0=$(cam target); AU0=$(cam applied); SU0=$(cam speed_scale)
A fp_camera wheel -720 >/dev/null; sleep 1; TU1=$(cam target); AU1=$(cam applied); SU1=$(cam speed_scale)
A click INV >/dev/null; waitf 4 ui_is 0; ui_clear
RATIO=$(awk -v a="$M1" -v b="$M2" 'BEGIN{printf "%.2f", (a>0)?b/a:0}')
ev="wheel target $T0->$T1->$T2 speed_scale $S0/$S1/$S2 | walk fp=$M1 tp=$M2 ratio=$RATIO move_speed fp=$SP1 tp=$SP2 worst_ms fp=$WM1 tp=$WM2 | ui_open=$((1-UIO)) ui_wheel target $TU0->$TU1 applied $AU0->$AU1 speed $SU0->$SU1"
ok=1; [ "$S0" = "$S1" ] && [ "$S1" = "$S2" ] && [ "$SU0" = "$SU1" ] || ok=0
awk -v a="$T0" -v b="$T1" -v c="$T2" 'BEGIN{exit !(b-a>.75 && b-c>.5)}' || ok=0
ROK=1; awk -v r="$RATIO" 'BEGIN{exit !(r>=.75 && r<=1.33)}' || { ok=0; ROK=0; }
if [ $UIO != 0 ]; then row C02 FAIL "setup inventory did not open (ui_open=0): $ev"
elif [ $ROK = 0 ] && { ge "$WM1" "$STALL_MS" || ge "$WM2" "$STALL_MS"; }; then row C02 FAIL "inconclusive: a walk sample is still frame-stalled after $WALK_TRIES tries (worst_ms >= $STALL_MS shortens the wall-clock hold): $ev"
else [ "$TU0" = "$TU1" ] && [ "$AU0" = "$AU1" ] || ok=0; judge C02 $ok "$ev"; fi

# ---- C03: inspect the mate without transfer ----
ui_clear; HM=$(id_of "$MT"); A select "$MT" >/dev/null
waitf 4 bash -c '[ "$(stobe-auto fp_control state | grep -o "\binspected=[^ ]*" | cut -d= -f2)" != "'"$H0"'" ]'; INSP=$?
C3=$(A fp_control state); HC=$(fld controlled <<<"$C3"); HI=$(fld inspected <<<"$C3"); IDS3=$(fld control_ids <<<"$C3")
PM0=$(pos "$MT"); pick_yaw "$SH" C03; look "$YAW" 0; read -r M3 G3 AN3 _ <<<"$(walk "$SH" w 2000)"; DM=$(d2 "$PM0" "$(pos "$MT")")
BM=$(nwid "$MT"); BS=$(nwid "$SH")
A click INV >/dev/null; waitf 4 ui_is 1; UIO=$?; sleep 0.5
NM=$(nwid "$MT"); NS=$(nwid "$SH"); HU=$(ctl controlled)
A click INV >/dev/null; waitf 4 ui_is 0; HA=$(ctl controlled); IDSA=$(ctl control_ids)
ev="inspected=$HI(changed=$((1-INSP))) controlled=$H0/$HC/$HU/$HA ids_same=$([ "$IDS0" = "$IDSA" ] && [ "$IDS0" = "$IDS3" ] && echo 1 || echo 0) | walk $SH=$M3 ang=$G3 anchor=$AN3 $MT=$DM | inv ui_open=$((1-UIO)) name widgets $MT $BM->$NM $SH $BS->$NS"
ok=1; [ $INSP = 0 ] && [ "$HC" = "$H0" ] && [ "$HU" = "$H0" ] && [ "$HA" = "$H0" ] && [ "$IDS3" = "$IDS0" ] && [ "$IDSA" = "$IDS0" ] || ok=0
ge "$M3" "$MOVE_MIN" || ok=0; lt "$DM" "$(awk -v m="$MOVE_MIN" 'BEGIN{print m/2}')" || ok=0
awk -v m="$M3" -v a="$AN3" 'BEGIN{t=m*.25; if(t<3)t=3; d=m-a; if(d<0)d=-d; exit !(a>=0 && d<=t)}' || ok=0
[ "$NM" -gt "$BM" ] && [ "$NS" -le "$BS" ] || ok=0
if [ $UIO != 0 ]; then row C03 FAIL "setup inventory did not open: $ev"; else judge C03 $ok "$ev"; fi

# ---- C04-TAKE: F6 (key_take_control) press: ignored with UI open; mid-walk transfer releases the old actor ----
ui_clear; take "$SH" >/dev/null; A select "$MT" >/dev/null; sleep 0.5
U0=$(ctl take_ui_ignored); A click INV >/dev/null; waitf 4 ui_is 1; UIO=$?; A fp_control press >/dev/null; sleep 0.8
U1=$(ctl take_ui_ignored); HUI=$(ctl controlled); A click INV >/dev/null; waitf 4 ui_is 0; ui_clear
D0=$(ctl take_done); pick_yaw "$SH|$MT" C04-TAKE; look "$YAW" 0; A fp_move w 9000 >/dev/null; sleep 1.5; PS0=$(pos "$SH")
A fp_control press >/dev/null; waitf 3 ctl_is "$MT"; TOOK=$?; D1=$(ctl take_done); sleep 0.5
PS1=$(pos "$SH"); PM1=$(pos "$MT"); sleep 2; PS2=$(pos "$SH"); PM2=$(pos "$MT")
A fp_move state > "$OUT/last_walk_state.txt"   # mvdiag: the mate's fp_move state while W is still held
A fp_move none >/dev/null; sleep 0.8; MSTOP=$(still "$MT" 2)
WSH=$(d2 "$PS0" "$PS1"); RSH=$(d2 "$PS1" "$PS2"); WMT=$(d2 "$PM1" "$PM2")
ev="ui_press ignored=$U0->$U1 controlled_kept=$([ "$HUI" = "$H0" ] && echo 1 || echo 0) | walk_press took=$((1-TOOK)) take_done=$D0->$D1 $SH walked=$WSH after_transfer=$RSH $MT walked=$WMT stop_after_release=$MSTOP clearance=$YAWC $MT[$(mvdiag)]"
ok=1; [ $UIO = 0 ] && [ "$U1" -gt "$U0" ] && [ "$HUI" = "$H0" ] && [ $TOOK = 0 ] && [ "$D1" -gt "$D0" ] || ok=0
lt "$RSH" "$STILL_MAX" || ok=0; ge "$WMT" "$MOVE_MIN" || ok=0; lt "$MSTOP" "$STILL_MAX" || ok=0
judge C04-TAKE $ok "$ev"

# ---- C04-FALLBACK: other squad AI, FP off mid-walk, native order, FP on keeps the pinned actor ----
ui_clear; A fp_move none >/dev/null; A select "$SH" >/dev/null; A fp_control press >/dev/null; waitf 3 ctl_is "$SH"; BACK=$?
alive "before C04-FALLBACK"; PS0=$(pos "$SH"); read -r AIM AIMAX AIMN AIMS <<<"$(native_fix "$MT" +x "$HOME_MT")"; alive "after the $MT native walk"
SHI=$(d2 "$PS0" "$(pos "$SH")"); STILLCTL=$(ctl_is "$SH" && echo 1 || echo 0)
pick_yaw "$SH" C04-FALLBACK; look "$YAW" 0; A fp_move w 9000 >/dev/null; sleep 1.5; mode off; OFF=$?; PZ=$(A status | fld paused); sleep 0.5; P1=$(pos "$SH"); sleep 2; P2=$(pos "$SH")
DMA=$(mvs dm_active); RS=$(d2 "$P1" "$P2"); A fp_move none >/dev/null; alive "after C04-FALLBACK fp_mode off (paused_at_off=${PZ:-na})"
read -r NAT NATAX NATN NATS <<<"$(native_fix "$SH" -x "$HOME_SH")"
mode on; ON=$?; A fp_control state >/dev/null; sleep 0.5; PIN=$(ctl_is "$SH" && echo 1 || echo 0); STK=$(still "$SH" 2)
FLAG=""; [ "$PZ" = 1 ] && FLAG=" | flag=product? game paused itself right at FP off (speed hold unpaused it)"
[ "$AIMS$NATS" != -- ] && FLAG+=" | flag=product? native walk never started at native_stuck_at=$MT:$AIMS/$SH:$NATS (retried from the setup position)"
ev="back_to_$SH=$((1-BACK)) | $MT native walk=$AIM axis=$AIMAX tries=$AIMN while $SH direct (kept=$STILLCTL moved=$SHI) | fp_off=$((1-OFF)) paused_at_off=${PZ:-na} dm_active=$DMA drift_with_w_held=$RS | native $SH walk=$NAT axis=$NATAX tries=$NATN | fp_on=$((1-ON)) pinned=$PIN drift=$STK$FLAG"
ok=1; [ $BACK = 0 ] && [ $OFF = 0 ] && [ $ON = 0 ] && [ "$STILLCTL" = 1 ] && [ "$PIN" = 1 ] && [ "$DMA" = 0 ] || ok=0
ge "$AIM" 25 || ok=0; lt "$SHI" "$STILL_MAX" || ok=0; lt "$RS" "$STILL_MAX" || ok=0; ge "$NAT" 25 || ok=0; lt "$STK" "$STILL_MAX" || ok=0
judge C04-FALLBACK $ok "$ev"

# ---- C05 lifecycle (save first: C05-INVALID changes the squad, C05-LOAD restores it) ----
alive "before C05"; ui_clear; take "$SH" >/dev/null; A save kah-fp-c05 >/dev/null; sleep 3; PSAVE=$(pos "$SH")
A status | grep -q 'last_saved=kah-fp-c05' || echo "SETUP: save kah-fp-c05 not confirmed" >> "$LOG"

# C05-KO: W held through a KO; no drive while down, same actor after, no stuck motion, fresh W walks
IDK=$(ctl control_ids); look "$YAW" 0; A fp_move w 30000 >/dev/null; A protect "$SH" off >/dev/null; A ko "$SH" 10 >/dev/null
if waitf 15 isko "$SH"; then DOWN=1; DMS=""; for _ in 1 2 3; do MST=$(A fp_move state); DMS+="$(fld dm_active <<<"$MST")/$(fld is_down <<<"$MST")/$(fld ko <<<"$MST"),"; sleep 0.7; done
  waitf 40 bash -c "! stobe-auto where '$SH' | grep -qE ' (KO|DEAD)( |\$)'"; WOKE=$?
else DOWN=0; DMS=never_down; WOKE=1; fi
A fp_move none >/dev/null; A protect "$SH" on >/dev/null; sleep 1.5; STK=$(still "$SH" 2); IDK2=$(ctl control_ids)
mode on >/dev/null; pick_yaw "$SH" C05-KO; look "$YAW" 0; align; read -r MK MKA _ _ <<<"$(walk "$SH" w 2000)"
ev="down=$DOWN dm_active/is_down/ko_while_down=${DMS%,} woke=$((1-WOKE)) ids_same=$([ "$IDK" = "$IDK2" ] && echo 1 || echo 0) drift_after_release=$STK fresh_walk=$MK ang=$MKA clearance=$YAWC walk_state[$(mvdiag)]"
if [ $DOWN = 0 ]; then row C05-KO FAIL "setup $SH never knocked out: $ev"; else
  ok=1; grep -qE '(^|,)1/' <<<"$DMS" && ok=0   # dm_active=1 while KO = still driven (is_down: evidence only)
  [ $WOKE = 0 ] && [ "$IDK" = "$IDK2" ] || ok=0; lt "$STK" "$STILL_MAX" || ok=0; ge "$MK" "$MOVE_MIN" || ok=0
  judge C05-KO $ok "$ev"; fi

# C05-INVALID: the controlled mate gets a new handle outside the squad while W is held
# setup: C05-KO can leave him displaced (b27: flung ~100 km out of the world, no walk possible). Repair once by
# reloading the C05 save; still displaced = setup failure for this row, not a C05-INVALID verdict.
near_save() { local p; p=$(pos "$SH"); [ -n "$p" ] && [ -n "$PSAVE" ] && lt "$(d2 "$PSAVE" "$p")" 500; }
SETUPI=""
if ! near_save; then DSV=$(d2 "$PSAVE" "$(pos "$SH")"); echo "SETUP: $SH is $DSV from his C05 save position: reloading kah-fp-c05" >> "$LOG"
  A load kah-fp-c05 >/dev/null; A wait-world >/dev/null; A fp_move none >/dev/null; A speed 1 hold >/dev/null
  for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done; ui_clear; take "$SH" >/dev/null
  near_save || SETUPI="setup: $SH displaced by the previous row (dist=$DSV, after reload $(d2 "$PSAVE" "$(pos "$SH")"))"
fi
if [ -n "$SETUPI" ]; then row C05-INVALID FAIL "$SETUPI log=$LOG"; else
ui_clear; take "$MT"; TM=$?; PS0=$(pos "$SH"); pick_yaw "$MT" C05-INVALID-mate; look "$YAW" 0; A fp_move w 15000 >/dev/null; sleep 1
FR=$(A faction "$MT" "$INVALID_FACTION"); NEWID=$(grep -o '#[0-9]*' <<<"$FR" | head -1)
waitf 3 bash -c '[ "$(stobe-auto fp_control state | grep -o "\bdirect=[0-9]" | cut -d= -f2)" = 0 ]'; REL=$?
C5=$(A fp_control state); HC=$(fld controlled <<<"$C5"); sleep 2; SHD=$(d2 "$PS0" "$(pos "$SH")"); A fp_move none >/dev/null
A fp_mode on >/dev/null; sleep 1; RE=$(fps fp_mode); HR=$(ctl controlled); TRANS=$(ctl_is "$SH" && echo 1 || echo 0)
A select "$SH" >/dev/null; A fp_control take >/dev/null; mode on; REC=$?; pick_yaw "$SH" C05-INVALID; look "$YAW" 0; align; read -r MI MIA _ _ <<<"$(walk "$SH" w 2000)"
ev="take_$MT=$((1-TM)) faction='$(cut -c1-60 <<<"$FR")' released=$((1-REL)) controlled_after=$HC $SH moved=$SHD | fp_on_again fp_mode=$RE controlled=$HR silent_transfer=$TRANS | explicit_take=$((1-REC)) walk=$MI ang=$MIA clearance=$YAWC walk_state[$(mvdiag)]"
if [ $TM != 0 ] || [ -z "$NEWID" ] || grep -q ERROR <<<"$FR"; then row C05-INVALID FAIL "setup: $ev"; else
  ok=1; [ $REL = 0 ] && [ "$HC" = 0 ] && [ "$TRANS" = 0 ] && [ $REC = 0 ] || ok=0
  lt "$SHD" "$STILL_MAX" || ok=0; ge "$MI" "$MOVE_MIN" || ok=0; judge C05-INVALID $ok "$ev"; fi
fi

# C05-LOAD: W held through a load, released after; nobody walks on; camera valid; take + W walks; stops
look "$YAW" 0; A fp_move w 30000 >/dev/null; A load kah-fp-c05 >/dev/null; A wait-world >/dev/null; A fp_move none >/dev/null; A speed 1 hold >/dev/null
sleep 3; LS=$(A status | fld save); LFP=$(fps fp_mode); LH=$(ctl controlled); STK=$(still "$SH" 2); MTB=$(A where "$MT" | grep -c 'pos=')
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done; ui_clear
take "$SH"; LT=$?; A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye; LC=$?
pick_yaw "$SH" C05-LOAD; look "$YAW" 0; read -r ML _ _ _ <<<"$(walk "$SH" w 2000)"; sleep 0.5; STK2=$(still "$SH" 2)
ev="save=$LS fp_mode=$LFP controlled=$LH drift_after_load=$STK mate_back=$MTB | take=$((1-LT)) camera_eye=$((1-LC)) [$(camsum)] walk=$ML drift_after_release=$STK2"
ok=1; [ "$LS" = kah-fp-c05 ] && [ $LT = 0 ] && [ $LC = 0 ] || ok=0
lt "$STK" "$STILL_MAX" || ok=0; ge "$ML" "$MOVE_MIN" || ok=0; lt "$STK2" "$STILL_MAX" || ok=0
judge C05-LOAD $ok "$ev"

# C05-INTERIOR: walk into a wall inside a building, wall behind the camera -> third person collision-limited
ui_clear; BL=""; for f in ${INTERIOR:-house shack bar shop hut tower home}; do BL=$(A buildings 1500 "$f" | grep -m1 'pos='); [ -n "$BL" ] && break; done
BP=$(grep -o 'pos=[^ ]*' <<<"$BL" | head -1 | cut -d= -f2 | tr ',' ' ')
if [ -z "$BP" ]; then row C05-INTERIOR FAIL "setup no building matching '${INTERIOR:-house shack bar shop hut tower home}' within 1500 (set INTERIOR=<filter>)"; else
  A teleport "$SH" $BP >/dev/null; sleep 2; take "$SH" >/dev/null; A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye
  look "$YAW" 0; A fp_move w 12000 >/dev/null; WALL=0; PP=$(pos "$SH"); N=0
  for _ in $(seq 1 22); do sleep 0.5; PN=$(pos "$SH"); if lt "$(d2 "$PP" "$PN")" 0.5; then N=$((N+1)); [ $N -ge 3 ] && { WALL=1; break; }; else N=0; fi; PP=$PN; done
  A fp_move none >/dev/null; sleep 0.5
  YB=$(awk -v y="$YAW" 'BEGIN{y+=3.14159; if(y>3.14159)y-=6.28318; printf "%.4f", y}')   # face away: the wall is behind
  look "$YB" 0; A fp_camera distance 30 >/dev/null; sleep 1.5; CI=$(A fp_camera state)
  BLK=$(fld blocked <<<"$CI"); AP=$(fld applied <<<"$CI"); TT=$(fld target <<<"$CI"); AD=$(fld actual_distance <<<"$CI")
  PRB=$(A fp_camera probe | grep -o 'cam=.*')   # pull-back ray per collision mask (which group the wall is in)
  YAW=$YB; read -r MA _ _ _ <<<"$(walk "$SH" w 1500)"; A fp_camera distance 0 >/dev/null
  ev="building='$(cut -c1-50 <<<"$BL")' wall_reached=$WALL | wall_behind target=$TT applied=$AP actual=$AD blocked=$BLK [$PRB] | walk_away=$MA"
  if [ $WALL = 0 ]; then row C05-INTERIOR FAIL "setup no wall reached walking 11 s: $ev"; else
    ok=1; [ "$BLK" = 1 ] && lt "$AP" "$TT" || ok=0
    awk -v a="$AD" -v p="$AP" 'BEGIN{d=a-p; if(d<0)d=-d; exit !(a!="" && d<.2)}' || ok=0
    ge "$MA" "$(awk -v m="$MOVE_MIN" 'BEGIN{print m/2}')" || ok=0; judge C05-INTERIOR $ok "$ev"; fi; fi

# C05-STAIRS: a stair start STAIRS="x y z yaw" (bottom, facing up), else found at runtime in a Storm House built 60 from
# the player (removed again by `unbuild Storm` in cleanup) by a ray scan (`fp_camera floors`: a 3-unit grid of downward
# rays over the house, every surface per cell). Ground G = the lowest height found in >= 10% of the cells, upper floor
# UP = the lowest one >= G+12 in >= 10% of them; stair cells have a surface between G+3 and UP-3; bottom = the lowest
# stair cell, yaw toward the highest, start 6 units back from the bottom on the ground floor. 4080 b33: the old
# teleport-onto-the-upper-floor search always clamped to the ground floor (y = base+4.5 at every offset/height).
STAIRS_SRC=env; STAIRS_WHY=""
find_stairs() { local r bx by bz f="$OUT/stairs_floors.txt"
  STAIRS_SRC=built; A fp_move none >/dev/null; [ -n "$PSAVE" ] && A teleport "$SH" $PSAVE >/dev/null; sleep 2
  r=$(A build "Storm House" near "$SH" dist 60)
  grep -q 'pos=' <<<"$r" || { STAIRS_WHY="build failed: $(cut -c1-80 <<<"$r")"; return 1; }
  BUILT=1; read -r bx by bz <<<"$(grep -o 'pos=[^ ]*' <<<"$r" | head -1 | cut -d= -f2 | tr ',' ' ')"; sleep 2
  stobe-auto fp_camera floors "$bx" "$bz" 30 3 "$(awk -v a="$by" 'BEGIN{print a+80}')" "$(awk -v a="$by" 'BEGIN{print a-5}')" > "$f" 2>&1
  r=$(awk -v by="$by" 'BEGIN{RS=";"} { sub(/^.*floors/,""); if (!match($0,/-?[0-9.]+,-?[0-9.]+:[-0-9.\/]+/)) next
      c=substr($0,RSTART,RLENGTH); split(c,a,":"); split(a[1],xz,","); m=split(a[2],ys,"/"); ++n; X[n]=xz[1]; Z[n]=xz[2]; prev=1e9; S[n]=""
      for(i=1;i<=m;i++){ y=ys[i]-by; if (prev-y<1.5) continue; prev=y; S[n]=S[n] " " y; b=int(y+100.5)-100; if(!((n,b) in seen)){seen[n,b]=1; cnt[b]++} } }
    END{ if(n<20){print "few_cells " n; exit} th=0.1*n; G=""
      for(b=-5;b<=80;b++) if(cnt[b]+cnt[b+1]>=th){G=b; break}
      if(G==""){print "no_ground"; exit} UP=""
      for(b=G+12;b<=80;b++) if(cnt[b]+cnt[b+1]>=th){UP=b; break}
      if(UP==""){printf "no_upper_floor ground=%d cells=%d\n", G, n; exit}
      lo=1e9; hi=-1e9; k=0
      for(c=1;c<=n;c++){ q=split(S[c],v," "); for(i=1;i<=q;i++) if(v[i]>=G+3 && v[i]<=UP-3){ k++
        if(v[i]<lo){lo=v[i]; lx=X[c]; lz=Z[c]} if(v[i]>hi){hi=v[i]; hx=X[c]; hz=Z[c]} } }
      if(k<3 || hi-lo<5){printf "no_stair_cells ground=%d upper=%d between=%d span=%.1f\n", G, UP, k, (k?hi-lo:0); exit}
      dx=hx-lx; dz=hz-lz; l=sqrt(dx*dx+dz*dz); if(l<1){print "stair_cells_stacked"; exit}
      printf "%.1f %.1f %.1f %.4f ground=%d upper=%d stair_cells=%d span=%.1f\n", lx-6*dx/l, by+G+1, lz-6*dz/l, atan2(dx,dz), G, UP, k, hi-lo}' "$f")
  echo "STAIRS house=$bx,$by,$bz scan=[$r] floors=$f" >> "$LOG"
  case "$r" in no_upper_floor*) STAIRS_WHY="built house has no upper floor surface (ray scan: $r)"; return 1;; esac
  grep -qE '^-?[0-9.]+ -?[0-9.]+ -?[0-9.]+ -?[0-9.]+ ' <<<"$r" || { STAIRS_WHY="no stair in the ray scan ($r, $f)"; return 1; }
  STAIRS=$(cut -d' ' -f1-4 <<<"$r"); return 0; }
if [ -z "$STAIRS" ] && ! find_stairs; then row C05-STAIRS FAIL "setup stairs not found ($STAIRS_SRC): $STAIRS_WHY"; else
  read -r SX SY SZ SYAW <<<"$STAIRS"; ui_clear; A teleport "$SH" "$SX" "$SY" "$SZ" >/dev/null; sleep 2; take "$SH" >/dev/null
  YAW=$SYAW; look "$YAW" 0; P0=$(pos "$SH"); read -r MS _ _ _ <<<"$(walk "$SH" w 4000)"; P1=$(pos "$SH"); DY=$(dy "$P0" "$P1")
  STK=$(still "$SH" 2); ev="stairs=$STAIRS_SRC start=[$STAIRS] walk=$MS dy=$DY drift_after_release=$STK controlled_$SH=$(ctl_is "$SH" && echo 1 || echo 0) [$(camsum)]"
  ok=1; awk -v d="$DY" 'BEGIN{if(d<0)d=-d; exit !(d>=10)}' || ok=0; lt "$STK" "$STILL_MAX" || ok=0; ctl_is "$SH" || ok=0
  judge C05-STAIRS $ok "$ev"; fi

echo "$(ui_summary)" >> "$LOG"
for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
