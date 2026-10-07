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
#  C05-STAIRS    needs STAIRS="x y z yaw" (bottom of a stair, facing up it): W climbs |dy| >= 10, stops on release
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
walk() { local p0 p1 a0 a1 ms2 sp st wm; p0=$(pos "$1"); a0=$(anchor); A fps reset >/dev/null; A fp_move "$2" "$3" >/dev/null
  ms2=$(awk -v m="$3" 'BEGIN{printf "%.2f", m/2000}'); sleep "$ms2"; st=$(A fp_move state)
  sp=$( [ "$(fld moving <<<"$st")" = 1 ] && fld move_speed <<<"$st"); sleep "$ms2"; sleep 0.6
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
FP0=$(fps fp_mode); DIST0=$(cam target)
cleanup() { A fp_move none >/dev/null; A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
            for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
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
YAW=$(cam yaw); YAW=${YAW:-0}; look "$YAW" 0
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye || setup_fail "camera never at eye ($(camsum))"
H0=$(ctl controlled); IDS0=$(ctl control_ids)

# ---- C01: eye -> third person -> eye, control + WASD + camera ----
ui_clear; look "$YAW" 0; read -r M1 G1 AN1 SP1 WM1 <<<"$(walkr "$SH" w 2000)"
EYE1=$(camsum); A fp_camera distance 3 >/dev/null; waitf 6 cam_ok far; FAROK=$?; FAR=$(camsum)
H1=$(ctl controlled); YAW=$(awk -v y="$YAW" 'BEGIN{y+=3.14159; if(y>3.14159)y-=6.28318; printf "%.4f", y}'); look "$YAW" 0
read -r M2 G2 AN2 SP2 WM2 <<<"$(walkr "$SH" w 2000)"
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye; EYEOK=$?; EYE2=$(camsum); H2=$(ctl controlled); IDS2=$(ctl control_ids)
ev="fp_walk=$M1 ang=$G1 anchor=$AN1 | far[$FAR] ok=$((1-FAROK)) tp_walk=$M2 ang=$G2 anchor=$AN2 | back_eye[$EYE2] ok=$((1-EYEOK)) | controlled=$H0/$H1/$H2 ids_same=$([ "$IDS0" = "$IDS2" ] && echo 1 || echo 0)"
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
PM0=$(pos "$MT"); look "$YAW" 0; read -r M3 G3 AN3 _ <<<"$(walk "$SH" w 2000)"; DM=$(d2 "$PM0" "$(pos "$MT")")
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
D0=$(ctl take_done); look "$YAW" 0; A fp_move w 9000 >/dev/null; sleep 1.5; PS0=$(pos "$SH")
A fp_control press >/dev/null; waitf 3 ctl_is "$MT"; TOOK=$?; D1=$(ctl take_done); sleep 0.5
PS1=$(pos "$SH"); PM1=$(pos "$MT"); sleep 2; PS2=$(pos "$SH"); PM2=$(pos "$MT")
A fp_move none >/dev/null; sleep 0.8; MSTOP=$(still "$MT" 2)
WSH=$(d2 "$PS0" "$PS1"); RSH=$(d2 "$PS1" "$PS2"); WMT=$(d2 "$PM1" "$PM2")
ev="ui_press ignored=$U0->$U1 controlled_kept=$([ "$HUI" = "$H0" ] && echo 1 || echo 0) | walk_press took=$((1-TOOK)) take_done=$D0->$D1 $SH walked=$WSH after_transfer=$RSH $MT walked=$WMT stop_after_release=$MSTOP"
ok=1; [ $UIO = 0 ] && [ "$U1" -gt "$U0" ] && [ "$HUI" = "$H0" ] && [ $TOOK = 0 ] && [ "$D1" -gt "$D0" ] || ok=0
lt "$RSH" "$STILL_MAX" || ok=0; ge "$WMT" "$MOVE_MIN" || ok=0; lt "$MSTOP" "$STILL_MAX" || ok=0
judge C04-TAKE $ok "$ev"

# ---- C04-FALLBACK: other squad AI, FP off mid-walk, native order, FP on keeps the pinned actor ----
ui_clear; A fp_move none >/dev/null; A select "$SH" >/dev/null; A fp_control press >/dev/null; waitf 3 ctl_is "$SH"; BACK=$?
alive "before C04-FALLBACK"; PS0=$(pos "$SH"); read -r AIM AIMAX AIMN <<<"$(native_walk "$MT" +x)"; alive "after the $MT native walk"
SHI=$(d2 "$PS0" "$(pos "$SH")"); STILLCTL=$(ctl_is "$SH" && echo 1 || echo 0)
look "$YAW" 0; A fp_move w 9000 >/dev/null; sleep 1.5; mode off; OFF=$?; PZ=$(A status | fld paused); sleep 0.5; P1=$(pos "$SH"); sleep 2; P2=$(pos "$SH")
DMA=$(mvs dm_active); RS=$(d2 "$P1" "$P2"); A fp_move none >/dev/null; alive "after C04-FALLBACK fp_mode off (paused_at_off=${PZ:-na})"
read -r NAT NATAX NATN <<<"$(native_walk "$SH" -x)"
mode on; ON=$?; A fp_control state >/dev/null; sleep 0.5; PIN=$(ctl_is "$SH" && echo 1 || echo 0); STK=$(still "$SH" 2)
FLAG=""; [ "$PZ" = 1 ] && FLAG=" | flag=product? game paused itself right at FP off (speed hold unpaused it)"
ev="back_to_$SH=$((1-BACK)) | $MT native walk=$AIM axis=$AIMAX tries=$AIMN while $SH direct (kept=$STILLCTL moved=$SHI) | fp_off=$((1-OFF)) paused_at_off=${PZ:-na} dm_active=$DMA drift_with_w_held=$RS | native $SH walk=$NAT axis=$NATAX tries=$NATN | fp_on=$((1-ON)) pinned=$PIN drift=$STK$FLAG"
ok=1; [ $BACK = 0 ] && [ $OFF = 0 ] && [ $ON = 0 ] && [ "$STILLCTL" = 1 ] && [ "$PIN" = 1 ] && [ "$DMA" = 0 ] || ok=0
ge "$AIM" 25 || ok=0; lt "$SHI" "$STILL_MAX" || ok=0; lt "$RS" "$STILL_MAX" || ok=0; ge "$NAT" 25 || ok=0; lt "$STK" "$STILL_MAX" || ok=0
judge C04-FALLBACK $ok "$ev"

# ---- C05 lifecycle (save first: C05-INVALID changes the squad, C05-LOAD restores it) ----
alive "before C05"; ui_clear; take "$SH" >/dev/null; A save kah-fp-c05 >/dev/null; sleep 3; PSAVE=$(pos "$SH")
A status | grep -q 'last_saved=kah-fp-c05' || echo "SETUP: save kah-fp-c05 not confirmed" >> "$LOG"

# C05-KO: W held through a KO; no drive while down, same actor after, no stuck motion, fresh W walks
IDK=$(ctl control_ids); look "$YAW" 0; A fp_move w 30000 >/dev/null; A protect "$SH" off >/dev/null; A ko "$SH" 10 >/dev/null
if waitf 15 isko "$SH"; then DOWN=1; DMS=""; for _ in 1 2 3; do DMS+="$(mvs dm_active)/$(mvs is_down),"; sleep 0.7; done
  waitf 40 bash -c "! stobe-auto where '$SH' | grep -qE ' (KO|DEAD)( |\$)'"; WOKE=$?
else DOWN=0; DMS=never_down; WOKE=1; fi
A fp_move none >/dev/null; A protect "$SH" on >/dev/null; sleep 1.5; STK=$(still "$SH" 2); IDK2=$(ctl control_ids)
mode on >/dev/null; look "$YAW" 0; read -r MK _ _ _ <<<"$(walk "$SH" w 2000)"
ev="down=$DOWN dm_active/is_down_while_down=${DMS%,} woke=$((1-WOKE)) ids_same=$([ "$IDK" = "$IDK2" ] && echo 1 || echo 0) drift_after_release=$STK fresh_walk=$MK"
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
ui_clear; take "$MT"; TM=$?; PS0=$(pos "$SH"); look "$YAW" 0; A fp_move w 15000 >/dev/null; sleep 1
FR=$(A faction "$MT" "$INVALID_FACTION"); NEWID=$(grep -o '#[0-9]*' <<<"$FR" | head -1)
waitf 3 bash -c '[ "$(stobe-auto fp_control state | grep -o "\bdirect=[0-9]" | cut -d= -f2)" = 0 ]'; REL=$?
C5=$(A fp_control state); HC=$(fld controlled <<<"$C5"); sleep 2; SHD=$(d2 "$PS0" "$(pos "$SH")"); A fp_move none >/dev/null
A fp_mode on >/dev/null; sleep 1; RE=$(fps fp_mode); HR=$(ctl controlled); TRANS=$(ctl_is "$SH" && echo 1 || echo 0)
A select "$SH" >/dev/null; A fp_control take >/dev/null; mode on; REC=$?; look "$YAW" 0; read -r MI _ _ _ <<<"$(walk "$SH" w 2000)"
ev="take_$MT=$((1-TM)) faction='$(cut -c1-60 <<<"$FR")' released=$((1-REL)) controlled_after=$HC $SH moved=$SHD | fp_on_again fp_mode=$RE controlled=$HR silent_transfer=$TRANS | explicit_take=$((1-REC)) walk=$MI"
if [ $TM != 0 ] || [ -z "$NEWID" ] || grep -q ERROR <<<"$FR"; then row C05-INVALID FAIL "setup: $ev"; else
  ok=1; [ $REL = 0 ] && [ "$HC" = 0 ] && [ "$TRANS" = 0 ] && [ $REC = 0 ] || ok=0
  lt "$SHD" "$STILL_MAX" || ok=0; ge "$MI" "$MOVE_MIN" || ok=0; judge C05-INVALID $ok "$ev"; fi
fi

# C05-LOAD: W held through a load, released after; nobody walks on; camera valid; take + W walks; stops
look "$YAW" 0; A fp_move w 30000 >/dev/null; A load kah-fp-c05 >/dev/null; A wait-world >/dev/null; A fp_move none >/dev/null; A speed 1 hold >/dev/null
sleep 3; LS=$(A status | fld save); LFP=$(fps fp_mode); LH=$(ctl controlled); STK=$(still "$SH" 2); MTB=$(A where "$MT" | grep -c 'pos=')
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done; ui_clear
take "$SH"; LT=$?; A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye; LC=$?
look "$YAW" 0; read -r ML _ _ _ <<<"$(walk "$SH" w 2000)"; sleep 0.5; STK2=$(still "$SH" 2)
ev="save=$LS fp_mode=$LFP controlled=$LH drift_after_load=$STK mate_back=$MTB | take=$((1-LT)) camera_eye=$((1-LC)) [$(camsum)] walk=$ML drift_after_release=$STK2"
ok=1; [ "$LS" = kah-fp-c05 ] && [ $LT = 0 ] && [ $LC = 0 ] || ok=0
lt "$STK" "$STILL_MAX" || ok=0; ge "$ML" "$MOVE_MIN" || ok=0; lt "$STK2" "$STILL_MAX" || ok=0
judge C05-LOAD $ok "$ev"

# C05-INTERIOR: walk into a wall inside a building, wall behind the camera -> third person collision-limited
ui_clear; BL=""; for f in ${INTERIOR:-house shack bar shop hut tower home}; do BL=$(A buildings 1500 "$f" | grep -m1 'pos='); [ -n "$BL" ] && break; done
BP=$(grep -o 'pos=[^ ]*' <<<"$BL" | cut -d= -f2 | tr ',' ' ')
if [ -z "$BP" ]; then row C05-INTERIOR FAIL "setup no building matching '${INTERIOR:-house shack bar shop hut tower home}' within 1500 (set INTERIOR=<filter>)"; else
  A teleport "$SH" $BP >/dev/null; sleep 2; take "$SH" >/dev/null; A fp_camera distance 0 >/dev/null; waitf 6 cam_ok eye
  look "$YAW" 0; A fp_move w 12000 >/dev/null; WALL=0; PP=$(pos "$SH"); N=0
  for _ in $(seq 1 22); do sleep 0.5; PN=$(pos "$SH"); if lt "$(d2 "$PP" "$PN")" 0.5; then N=$((N+1)); [ $N -ge 3 ] && { WALL=1; break; }; else N=0; fi; PP=$PN; done
  A fp_move none >/dev/null; sleep 0.5
  YB=$(awk -v y="$YAW" 'BEGIN{y+=3.14159; if(y>3.14159)y-=6.28318; printf "%.4f", y}')   # face away: the wall is behind
  look "$YB" 0; A fp_camera distance 12 >/dev/null; sleep 1.5; CI=$(A fp_camera state)
  BLK=$(fld blocked <<<"$CI"); AP=$(fld applied <<<"$CI"); TT=$(fld target <<<"$CI"); AD=$(fld actual_distance <<<"$CI")
  YAW=$YB; read -r MA _ _ _ <<<"$(walk "$SH" w 1500)"; A fp_camera distance 0 >/dev/null
  ev="building='$(cut -c1-50 <<<"$BL")' wall_reached=$WALL | wall_behind target=$TT applied=$AP actual=$AD blocked=$BLK | walk_away=$MA"
  if [ $WALL = 0 ]; then row C05-INTERIOR FAIL "setup no wall reached walking 11 s: $ev"; else
    ok=1; [ "$BLK" = 1 ] && lt "$AP" "$TT" || ok=0
    awk -v a="$AD" -v p="$AP" 'BEGIN{d=a-p; if(d<0)d=-d; exit !(a!="" && d<.2)}' || ok=0
    ge "$MA" "$(awk -v m="$MOVE_MIN" 'BEGIN{print m/2}')" || ok=0; judge C05-INTERIOR $ok "$ev"; fi; fi

# C05-STAIRS: needs a known stair (STAIRS="x y z yaw")
if [ -z "$STAIRS" ]; then row C05-STAIRS FAIL "setup no stairs position in this fixture (set STAIRS=\"x y z yaw\")"; else
  read -r SX SY SZ SYAW <<<"$STAIRS"; ui_clear; A teleport "$SH" "$SX" "$SY" "$SZ" >/dev/null; sleep 2; take "$SH" >/dev/null
  YAW=$SYAW; look "$YAW" 0; P0=$(pos "$SH"); read -r MS _ _ _ <<<"$(walk "$SH" w 4000)"; P1=$(pos "$SH"); DY=$(dy "$P0" "$P1")
  STK=$(still "$SH" 2); ev="walk=$MS dy=$DY drift_after_release=$STK controlled_$SH=$(ctl_is "$SH" && echo 1 || echo 0) [$(camsum)]"
  ok=1; awk -v d="$DY" 'BEGIN{if(d<0)d=-d; exit !(d>=10)}' || ok=0; lt "$STK" "$STILL_MAX" || ok=0; ctl_is "$SH" || ok=0
  judge C05-STAIRS $ok "$ev"; fi

echo "$(ui_summary)" >> "$LOG"
for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
