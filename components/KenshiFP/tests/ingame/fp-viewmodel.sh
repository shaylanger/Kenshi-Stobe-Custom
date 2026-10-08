#!/usr/bin/env bash
# fp-viewmodel.sh: KenshiFP Gate 6 viewmodel rows PT13/PT14 (COMBAT_TEST_PLAN.md) on a kah-fpxbow copy
# (Axima = crossbow player, Malzin = mate with a melee weapon). Helpers + setup are fp-playtest.sh's (same build).
#  PT13  crossbow: physical R draw -> fp_vm state=ready, hand within VM_TOL deg of the ready target, melee=0, tilt~0;
#        RMB held -> state=aiming on the aim target; one injected shot -> state=reloading seen
#  PT14  sword (bow off, sword from the mate): R draw -> ready on target, melee=1, tilt >= 20; RMB held -> blocking on
#        the block target; physical LMB -> a new "[vm] swing" log line with u_end >= 0.5; test pose sw_pose 0 / 1 ->
#        hand on the arc's start / end points (fp_vm sw_e0 sw_a0 / sw_e1 sw_a1 defaults -8,24 / -30,-12)
# Screenshots (vm-*.png, harness shots dir) are listed in a NOTE line: PT17 (overall look) is judged from them.
# Usage: fp-viewmodel.sh [player] [mate] [hostile] [outdir]. Env: ROWS, KFPLOG, VM_TOL (4).
# Leaves the fixture changed (a shot fired, items moved): reload it after.
# Usage: fp-playtest.sh [player] [mate] [hostile] [outdir] (defaults: $PLAYER/$MATE or Axima/Malzin, Skaera,
# /tmp/fp-playtest). Env: ROWS (space/comma list), KFPLOG, STILL_MAX (3), SPIKE_MAX (1.5), FAR_NPC.
# Leaves the fixture changed (player KO'd/carried, Skaera KO'd, items moved): reload it after.
SH=${1:-${PLAYER:-Axima}}; MT=${2:-${MATE:-Malzin}}; TG=${3:-${HOSTILE:-Skaera}}; OUT=${4:-/tmp/fp-viewmodel}
KDIR=/mnt/d/Steam/steamapps/common/Kenshi; KFPLOG=${KFPLOG:-$KDIR/KenshiFP.log}
STILL_MAX=${STILL_MAX:-3}; SPIKE_MAX=${SPIKE_MAX:-1.5}; FAR_NPC=${FAR_NPC:-}
ROWS=${ROWS:-"PT13 PT14"}; ROWS=${ROWS//,/ }
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
note() { echo "$*" >> "$LOG"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cam() { A fp_camera state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
fps() { A fp_state | fld "$1"; }
ks() { A fp_keys state | fld "$1"; }
cs() { A fp_combat state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
notko() { ! isko "$1"; }
d2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0<b+0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
inc() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && b!="" && b+0>a+0)}'; }     # inc <before> <after>: rose
want() { case " $ROWS " in *" $1 "*) return 0;; esac; return 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
uname_() { tr ' =' '__' <<<"$1"; }
kfplines() { tail -n +"$((LN0+1))" "$KFPLOG" 2>/dev/null | tr -d '\r'; }       # KenshiFP.log since the test start
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
finish() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
# setup_fail <reason>: every wanted row not yet reported gets `FAIL setup: <reason>`
setup_fail() { local r; for r in $ROWS; do printf '%s\n' "${RESULTS[@]}" | grep -q "^RESULT $r " || row "$r" FAIL "setup: $1"; done; finish; exit 1; }
# rows_fail <reason> <rows...>: the listed wanted rows fail on a setup reason
rows_fail() { local why=$1 r; shift; for r in "$@"; do want "$r" && row "$r" FAIL "setup: $why"; done; }

# ---- physical input (input isolation) ----
mclick() { A mouse_inject "$1" click "${2:-80}" >/dev/null; sleep "$(awk -v m="${2:-80}" 'BEGIN{printf "%.2f", (m+250)/1000}')"; }
mdown() { A mouse_inject "$1" down >/dev/null; }
mup() { A mouse_inject "$1" up >/dev/null; }
rkey() { A key_inject r tap 120 >/dev/null; sleep 0.35; }
altkey() { A key_inject 0xa4 tap 120 >/dev/null; sleep 0.4; }      # Left Alt = KenshiFP free-cursor toggle

# ---- view / control ----
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
mode() { A fp_mode "$1" >/dev/null; waitf 4 fp_is "$([ "$1" = on ] && echo 1 || echo 0)"; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; mode on; A fp_control take >/dev/null; waitf 4 ctl_is "$1"; }
cursor_ok() { [ "$(fps cursor_hidden)" = 1 ]; }
look() { A fp_camera look "$1" "${2:-0}" >/dev/null; sleep 0.3; }
SKY=-0.9
sky() { look "$(cam yaw)" "$SKY"; }
# aim_pt <viewer> <x y z> <height dm>: FP camera from the eye at a world point + height; aim_at <viewer> <npc> <height>
aim_pt() { local V=$1 sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$V")"; read -r tx ty tz <<<"$2"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$3" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
aim_at() { aim_pt "$1" "$(pos "$2")" "$3"; }
# pick_on <viewer> <npc>: aim until the crosshair pick reports the npc (bounded: heights 13 10 7, 2 tries each)
pick_on() { local H; for H in 13 10 7; do for _ in 1 2; do aim_at "$1" "$2" "$H"; A fp_keys pick >/dev/null; sleep 0.3
  PK=$(A fp_keys pick show); [ "$(fld result <<<"$PK")" = "$(uname_ "$(live_name "$2")")" ] && return 0; done; done; return 1; }
live_name() { local n; n=$(A where "$1" | sed -n 's/^\(.*\) #[0-9][0-9]*\/[0-9][0-9]* .*/\1/p' | head -1); echo "${n:-$1}"; }
menu_close() { [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null; sleep 0.3; }
toggles() { local i; for i in $(seq 1 "$1"); do mode off; sleep 0.5; mode on; sleep 0.5; done; }
in_fight() { A fp_melee state | grep -q 'active=1' && ! A fp_melee state | grep -q 'target_h=#0/'; }
not_fight() { ! in_fight; }
kis() { [ "$(ks "$1")" = "$2" ]; }
kge() { ge "$(ks "$1")" "$2"; }
csis() { [ "$(cs "$1")" = "$2" ]; }
csge() { ge "$(cs "$1")" "$2"; }

# ---- equipment (as fp-controls.sh: the fixture player carries a crossbow only; melee comes from the mate) ----
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
bow_now() { A rangedinfo "$SH" | fld bow; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$SH" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
GIVEN=""
give_melee() { local w r; [ -n "$(weapons)" ] && return 0
  w=$(A inv "$MT" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -n "$w" ] || { note "SETUP give_melee: $MT has no melee weapon either"; return 1; }
  r=$(A transfer "$MT" "$SH" "$w")
  case "$r" in transferred*) ;; *) r=$(A unequip "$MT" "$w")
    case "$r" in *ground*) r=$(A pickup "$SH" "$w" now);; *) r=$(A transfer "$MT" "$SH" "$w");; esac;; esac
  note "SETUP give_melee $w from $MT: $(cut -c1-120 <<<"$r")"; [ -n "$(weapons)" ] && GIVEN=$w; }
# bow_off: unequip the bow; a full inventory drops it: the mate parks it (BOW_DROPPED=2) or it stays on the ground (1)
BOW_DROPPED=0
bow_off() { local r; [ "$(bow_now)" = none ] && return 0; r=$(A unequip "$SH" "$(bow_now)")
  case "$r" in *ground*) BOW_DROPPED=1; r=$(A pickup "$MT" "$BOWN" now); note "SETUP bow parked on $MT: $(cut -c1-120 <<<"$r")"
    case "$r" in *ERROR*) ;; *) BOW_DROPPED=2;; esac;; esac; [ "$(bow_now)" = none ]; }
bow_on() { [ "$(bow_now)" != none ] && return 0; [ -n "$BOWN" ] || return 1
  [ "$BOW_DROPPED" = 2 ] && { note "SETUP bow back from $MT: $(A transfer "$MT" "$SH" "$BOWN" | cut -c1-120)"; BOW_DROPPED=0; }
  [ "$BOW_DROPPED" = 1 ] && { note "SETUP bow pickup: $(A pickup "$SH" "$BOWN" now | cut -c1-120)"; BOW_DROPPED=0; }
  A equip "$SH" "$BOWN" | grep -q '^equipped'; }
draw_to() { kis drawn "$1" && return 0; rkey; waitf 4 kis drawn "$1"; }

# ---- restore on exit ----
FP0=""; DIST0=""; AR0=""; PASSIVE0=""; PINNED=""; WEP=""; BOWN=""; ISO_SET=0; LN0=0
cleanup() { A mouse_inject right up >/dev/null; A mouse_inject left up >/dev/null; A fp_move none >/dev/null
  A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null; [ -n "$AR0" ] && A fp_combat autoreload "$AR0" >/dev/null
  [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null
  for c in $PINNED; do A pin "$c" off >/dev/null; done
  [ -n "$PASSIVE0" ] && A combatmode "$SH" passive "$([ "$PASSIVE0" = 1 ] && echo on || echo off)" >/dev/null
  [ -n "$WEP" ] && A unequip "$SH" "$WEP" >/dev/null; [ -n "$BOWN" ] && bow_on >/dev/null
  [ -n "$GIVEN" ] && A transfer "$SH" "$MT" "$GIVEN" >/dev/null
  for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
  A select "$SH" >/dev/null; A fp_control take >/dev/null
  A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
  [ -n "$FP0" ] && A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null
  [ "$ISO_SET" = 1 ] && A input_isolation off >/dev/null; }
trap cleanup EXIT

# ---- setup (bounded checks) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ -r "$KFPLOG" ] || setup_fail "KenshiFP.log not readable at $KFPLOG (set KFPLOG=)"
LN0=$(wc -l < "$KFPLOG")
K=$(A fp_keys state)
grep -q 'speed_now=' <<<"$K" && grep -q 'mmb_self=' <<<"$K" || setup_fail "KenshiFP fp_keys state has no Gate 6 fields (needs 74b3408+): $(cut -c1-80 <<<"$K")"
grep -q '\bhook=1\b' <<<"$K" || setup_fail "fp_keys hook=0 (playerControl hook not installed)"
A fp_keys ctl | grep -q '^ctl shown=' || setup_fail "fp_keys ctl missing (needs 968a5f6+)"
A fp_combat state | grep -q 'spread_n=' || setup_fail "fp_combat state has no spread_n (needs 095837f+)"
if ! A input_isolation status | grep -q 'isolation=on'; then A input_isolation on >/dev/null; ISO_SET=1
  A input_isolation status | grep -q 'isolation=on' || setup_fail "input isolation would not turn on (mouse_inject/key_inject need it)"; fi
FP0=$(fps fp_mode); DIST0=$(cam target); AR0=$(cs auto_reload)
BOWN=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
A speed 1 hold >/dev/null; A fp_move none >/dev/null; A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
PASSIVE0=$(A combatmode "$SH" | fld passive); A combatmode "$SH" passive on >/dev/null
TGH=""; if A where "$TG" | grep -q 'pos='; then TGH=$(A where "$TG" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  A pin "$TGH" at "$SH" dist 600 >/dev/null && PINNED+=" $TGH"; fi
take "$SH" || setup_fail "could not take $SH ($(A fp_control state | cut -c1-160))"
A fp_camera distance 0 >/dev/null

# ---- viewmodel ----
VM_TOL=${VM_TOL:-4}; SHOTS=""
A fp_vm state | grep -q 'hooked=1' || setup_fail "fp_vm hooked=0 or missing (needs KenshiFP e515843+): $(A fp_vm state | cut -c1-100)"
A fp_vm on >/dev/null
trap 'A fp_vm set sw_pose -1 >/dev/null; cleanup' EXIT
vfld() { A fp_vm state | fld "$1"; }
# vm_on <state>: vm in that state with the hand within VM_TOL deg of its target
vm_on() { local V; V=$(A fp_vm state); [ -z "$1" ] || [ "$(fld state <<<"$V")" = "$1" ] || return 1
  awk -v t="$(fld target <<<"$V")" -v e="$(fld elev <<<"$V")" -v a="$(fld az <<<"$V")" -v k="$VM_TOL" \
    'BEGIN{split(t,x,","); de=e-x[1]; da=a-x[2]; if(de<0)de=-de; if(da<0)da=-da; exit !(e!="" && t!="" && de<=k && da<=k)}'; }
vm_is() { [ "$(vfld state)" = "$1" ]; }
vev() { A fp_vm state | grep -oE '\b(state|elev|az|target|melee|tilt|swing|swu|swings)=[^ ]*' | tr '\n' ' '; }
shot() { local p; p=$(A screenshot "vm-$1" | grep -oE '[^ ]*\.png' | head -1); SHOTS+=" ${p##*[\/]}"; }
tilt_ge() { ge "$(vfld tilt)" "$1"; }

# ---- PT13: crossbow ready / aim / reload ----
BOWOK=0; [ -n "$BOWN" ] && [ "$(bow_now)" != none ] && BOWOK=1
if want PT13; then if [ $BOWOK = 0 ]; then row PT13 FAIL "setup: no crossbow on $SH"; else
  draw_to 1 || note "SETUP PT13: R did not draw (drawn=$(ks drawn))"
  waitf 5 vm_on ready; R1=$(vm_on ready && echo 1 || echo 0); E1=$(vev); shot xbow-ready
  T1=$(vfld tilt); M1=$(vfld melee)
  look "$(cam yaw)" 0.05; mdown right; waitf 4 vm_on aiming; R2=$(vm_on aiming && echo 1 || echo 0); E2=$(vev); shot xbow-aim; mup right; sleep 0.4
  A fp_combat input 1 0 0 >/dev/null; waitf 8 csis armed 1; RL=0
  if waitf 20 csis shot_ready 1; then S=$(cs actual_shots); A fp_combat input 1 1 0 >/dev/null; waitf 3 csge actual_shots $((S+1))
    A fp_combat input 1 0 0 >/dev/null; waitf 8 vm_is reloading && { RL=1; sleep 0.5; shot xbow-reload; }; fi
  A fp_combat input 0 0 0 >/dev/null; A fp_combat physical >/dev/null
  ev="ready: $E1| aim: $E2| reload_seen=$RL"
  ok=1; [ "$R1" = 1 ] && [ "$M1" = 0 ] && awk -v t="$T1" 'BEGIN{exit !(t!="" && t<1 && t>-1)}' && [ "$R2" = 1 ] && [ $RL = 1 ] || ok=0
  judge PT13 $ok "$ev"; draw_to 0; fi; fi

# ---- PT14: sword ready / block / swing / arc ----
if want PT14; then draw_to 0
  give_melee || note "SETUP: could not give $SH a melee weapon"; bow_off || note "SETUP: bow would not unequip ($(bow_now))"
  if ! arm_melee; then row PT14 FAIL "setup: no melee weapon equips on $SH (inv: $(weapons | tr '\n' ';'))"; else
    draw_to 1 || note "SETUP PT14: R did not draw (drawn=$(ks drawn))"
    waitf 5 vm_on ready; waitf 3 tilt_ge 20; R1=$(vm_on ready && echo 1 || echo 0); E1=$(vev); M1=$(vfld melee); T1=$(vfld tilt); shot sword-ready
    look "$(cam yaw)" 0.05; mdown right; waitf 4 vm_on blocking; R2=$(vm_on blocking && echo 1 || echo 0); E2=$(vev); shot sword-block; mup right; sleep 0.5
    SW0=$(kfplines | grep -c '\[vm\] swing'); mclick left; waitf 4 eval '[ "$(kfplines | grep -c "\[vm\] swing")" -gt "$SW0" ]'
    SWL=$(kfplines | grep '\[vm\] swing' | tail -1); [ "$(kfplines | grep -c '\[vm\] swing')" -gt "$SW0" ] || SWL=""
    UE=$(grep -o 'u_end=[0-9.]*' <<<"$SWL" | cut -d= -f2)
    A fp_vm set sw_pose 0 >/dev/null; sleep 1; P0=$(vm_on "" && echo 1 || echo 0); T0=$(vfld target); shot sword-swing0
    A fp_vm set sw_pose 0.5 >/dev/null; sleep 1; shot sword-swing05
    A fp_vm set sw_pose 1 >/dev/null; sleep 1; P1=$(vm_on "" && echo 1 || echo 0); TE=$(vfld target); shot sword-swing1
    A fp_vm set sw_pose -1 >/dev/null
    ev="ready: $E1| block: $E2| swing_line='$(cut -c1-80 <<<"$SWL")' | pose0 on=$P0 target=$T0 pose1 on=$P1 target=$TE"
    ok=1; [ "$R1" = 1 ] && [ "$M1" = 1 ] && ge "$T1" 20 && [ "$R2" = 1 ] && [ -n "$SWL" ] && ge "$UE" 0.5 || ok=0
    [ "$P0" = 1 ] && [ "$T0" = "-8.0,24.0" ] && [ "$P1" = 1 ] && [ "$TE" = "-30.0,-12.0" ] || ok=0
    judge PT14 $ok "$ev"; draw_to 0; fi; fi

echo "NOTE PT17 viewmodel screenshots (harness shots dir):$SHOTS" >> "$LOG"
finish; echo "NOTE PT17 screenshots:$SHOTS"
