#!/usr/bin/env bash
# fp-controls.sh: in-game Gate 1b FP control rows (COMBAT_TEST_PLAN.md "Gate 1b"), scheme 2026-10-06, KenshiFP 6E5D502B+.
# Input: `fp_keys press <lmb|rmb|mmb|r> <ms>` (published to the same tick path as the physical buttons), `fp_keys native
# <lmb|rmb> <frames>` (synthetic native mouse flags into PlayerInterface::playerControl), `fp_keys swallow on|off`,
# `fp_combat input <aim> <fire> <reload>` (ranged adapter). Evidence: `fp_keys state` counters/ui_state/hud_*, `fp_combat
# state` (wih, fp_ui_state, actual_shots, ammo, reload_starts), `fp_camera state|probe` (trace_blocks, trace=), `fp_melee
# state` (native fight), `where`/`hp`, KenshiFP.log ([down] lines).
# Run in WSL with Kenshi in the world on a kah-fpxbow copy right after load (Axima = crossbow player, Malzin = mate,
# Skaera = hostile Hungry Bandit). Speed 1, FP on, Axima controlled.
# Rows (one `RESULT <row> PASS|FAIL <evidence>` each, log path on FAILs):
#  K01         native RMB (walk order) swallowed in FP: rmb_swallowed rises, actor still; control: swallow off moves him
#  K02         MMB on the mate: selected (last_select, inspected changed), controlled unchanged, camera not rotated
#  K03         RMB click holstered on the mate: context menu (ctx_opens+1, ctx_freed=1, free=1); `fp_state free off` relocks
#  K04         RMB held, melee drawn, on the mate: blocking, free_block_frames rising, no context menu
#  K05-HOSTILE LMB drawn on Skaera: engages+1, last_task=5, native fight on her
#  K05-UNPROV  LMB drawn on a neutral NPC (NEUTRAL=<name|#serial/index>, else the first non-squad, non-raider NPC within
#              1500 not of Axima's faction; its faction relation is set to NEUTRAL_REL (20)): last_task=61, native fight on him
#  K06         R draw: r_draws+1, wih!=0 (fp_keys live weaponInHands), still drawn after 5 s idle; R holster: r_holsters+1, wih=0
#  FB01        RMB held drawn, aimed at the sky, out of combat: blocking while held, ready after release
#  FS01        LMB drawn melee, no target, no fight: free swing started and ended (fs_prog_max>0.5), no fault, mate hp same
#  FF01        crossbow, fp_combat on, aimed at the sky: one shot (actual_shots+1, ammo-1); adapter reload: ammo back up
#  HUD01       ui_state/hud_text sampled: holstered, ready, swinging, blocking, aiming (hud_text=ui_state, hud_shown=1)
#  Z01         distance 60 outdoors: applied >= 59, actual ~ applied, blocked=0 (probe trace= as evidence)
#  DOWN01      KO with fp_move w held: within DOWN_MAX of the KO spot while down and after, no `[down] position jump`,
#              `[down] held fp_move keys dropped` logged, fp_move keys empty while down
#  Z01-INT     in a building (INTERIOR filters as fp-control.sh), wall behind, distance 30: trace_blocks rises, blocked=1
# Visual parts (screenshot / Shay): K01 walk marker, K03 menu content, HUD label look.
# Usage: fp-controls.sh [player] [mate] [hostile] [outdir]. Env: NEUTRAL, NEUTRAL_REL (20), MOVE_MIN (10), STILL_MAX (3),
# DOWN_MAX (40 dm), INTERIOR, KFPLOG (/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log), ROWS (space list, default all).
# Leaves the fixture changed (Skaera/neutral KO, relations, player moved/KO'd): reload it after.
SH=${1:-Axima}; MT=${2:-Malzin}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-controls}
MOVE_MIN=${MOVE_MIN:-10}; STILL_MAX=${STILL_MAX:-3}; DOWN_MAX=${DOWN_MAX:-40}; NEUTRAL=${NEUTRAL:-}; NEUTRAL_REL=${NEUTRAL_REL:-20}
INTERIOR=${INTERIOR:-}; KFPLOG=${KFPLOG:-/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log}
ROWS=${ROWS:-"K01 K02 K03 K06 K04 FB01 FS01 K05 HUD01 FF01 Z01 DOWN01 Z01-INT"}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cam() { A fp_camera state | fld "$1"; }
ctl() { A fp_control state | fld "$1"; }
fps() { A fp_state | fld "$1"; }
ks() { A fp_keys state | fld "$1"; }
cs() { A fp_combat state | fld "$1"; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr ',' ' '; }      # "x y z"
isko() { A where "$1" | grep -qE ' (KO|DEAD)( |$)'; }
d2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,p," ");split(b,q," ");printf "%.2f", sqrt((q[1]-p[1])^2+(q[3]-p[3])^2)}'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0<b+0)}'; }
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a!="" && a+0>=b+0)}'; }
ctl_is() { local ids id; ids=$(ctl control_ids); id=$(id_of "$1"); [ -n "$id" ] && grep -qE "(^|/)$id(/|$)" <<<"$ids"; }
want() { case " $ROWS " in *" $1 "*) return 0;; esac; return 1; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
judge() { if [ "$2" = 1 ]; then row "$1" PASS "$3"; else row "$1" FAIL "$3"; fi; }
setup_fail() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
  echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
waitf() { local end=$((SECONDS+$1)); shift; while [ $SECONDS -lt $end ]; do "$@" && return 0; sleep 0.2; done; return 1; }
cursor_ok() { [ "$(fps cursor_hidden)" = 1 ]; }
fp_is() { [ "$(fps fp_mode)" = "$1" ]; }
mode() { A fp_mode "$1" >/dev/null; waitf 4 fp_is "$([ "$1" = on ] && echo 1 || echo 0)"; }
take() { A select "$1" >/dev/null; A fp_control take >/dev/null; mode on; A fp_control take >/dev/null; ctl_is "$1"; }
cam_ok() { local c; c=$(A fp_camera state); awk -v v="$(fld actual_valid <<<"$c")" -v a="$(fld actual_distance <<<"$c")" \
  -v p="$(fld applied <<<"$c")" -v e="$(fld eye <<<"$c")" 'BEGIN{d=a-p; if(d<0)d=-d; exit !(v=="1" && a!="" && d<.20 && p<.05 && e=="1")}'; }
camsum() { local c; c=$(A fp_camera state); echo "target=$(fld target <<<"$c") applied=$(fld applied <<<"$c") actual=$(fld actual_distance <<<"$c") eye=$(fld eye <<<"$c") blocked=$(fld blocked <<<"$c") trace_blocks=$(fld trace_blocks <<<"$c")"; }
look() { A fp_camera look "$1" "${2:-0}" >/dev/null; sleep 0.3; }
# kge <field> <value>: fp_keys counter reached value; kis <field> <value>: fp_keys field equals value
kge() { ge "$(ks "$1")" "$2"; }
kis() { [ "$(ks "$1")" = "$2" ]; }
csge() { ge "$(cs "$1")" "$2"; }
csis() { [ "$(cs "$1")" = "$2" ]; }
uname_() { tr ' =' '__' <<<"$1"; }          # fpc_name writes spaces/'=' as '_'
# aim_at <npc> <height dm>: FP camera from the eye (fp_camera state camera_x/y/z) at the npc's feet + height
# (yaw = atan2(dx,dz), pitch > 0 looks down)
aim_at() { local sx sy sz tx ty tz c e YP; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  c=$(A fp_camera state); e=$(fld camera_y <<<"$c"); [ -n "$(fld camera_x <<<"$c")" ] && { sx=$(fld camera_x <<<"$c"); sz=$(fld camera_z <<<"$c"); }
  [ -n "$e" ] || e=$(awk -v y="$sy" 'BEGIN{print y+19}')
  YP=$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$ty" -v h="$2" \
     'BEGIN{L=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-(py+h), L)}')
  A fp_camera look $YP >/dev/null; sleep 0.4; }
ge_applied() { ge "$(cam applied)" 59; }
SKY=-0.9                                      # pitch looking up: no character under the crosshair
sky() { look "$(cam yaw)" "$SKY"; }
# in_fight [npc]: the controlled actor's native CombatClass is active with a target (target_h #serial)
in_fight() { local s; s=$(A fp_melee state); grep -q 'active=1' <<<"$s" || return 1
  [ -z "$1" ] && { ! grep -q 'target_h=#0/' <<<"$s"; return; }; grep -q "target_h=#$1/" <<<"$s"; }
not_fight() { ! in_fight; }
# weapons / equipment (fp-manual-melee.sh): WEP = the melee weapon equipped by arm_melee, BOWN = the crossbow name
weapons() { A inv "$SH" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOWN:-@@}"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$SH" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }
bow_now() { A rangedinfo "$SH" | fld bow; }
arm_bow() { [ -n "$WEP" ] && { A unequip "$SH" "$WEP" >/dev/null; WEP=""; }; [ "$(bow_now)" != none ] && return 0
  [ -n "$BOWN" ] || return 1
  # a full inventory drops the unequipped bow on the ground (m50 b37): pick it up again first
  [ "$BOW_DROPPED" = 1 ] && { echo "SETUP bow pickup: $(A pickup "$SH" "$BOWN" now | cut -c1-120)" >> "$LOG"; BOW_DROPPED=0; }
  A equip "$SH" "$BOWN" | grep -q '^equipped'; }
# give_melee: the fixture's player may carry no melee weapon at all (m50 b37: only armour) and the harness can't create
# weapons (m50 b38): take the mate's melee weapon (unequipped first; a full inventory drops it, then the player picks it up)
give_melee() { local w r; [ -n "$(weapons)" ] && return 0
  w=$(A inv "$MT" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | head -1 | sed 's/.*"name":"\([^"]*\)".*/\1/')
  [ -n "$w" ] || { echo "SETUP give_melee: mate $MT has no melee weapon either" >> "$LOG"; return 1; }
  r=$(A transfer "$MT" "$SH" "$w")
  case "$r" in transferred*) ;; *) r=$(A unequip "$MT" "$w")
    case "$r" in *ground*) r=$(A pickup "$SH" "$w" now);; *) r=$(A transfer "$MT" "$SH" "$w");; esac;; esac
  echo "SETUP give_melee $w from $MT: $(cut -c1-120 <<<"$r")" >> "$LOG"; [ -n "$(weapons)" ]; }
# draw_state <0|1>: R until fp_keys drawn matches (one press, bounded wait)
draw_to() { kis drawn "$1" && return 0; A fp_keys press r 120 >/dev/null; waitf 4 kis drawn "$1"; }
# HUD samples: hud <expected>: fp_keys snapshot; HUDS += "exp:ui/hud_text/shown"; HUDOK=0 on a mismatch
HUDS=""; HUDOK=1; HUDN=0
hud() { hud_eval "$1" "$(A fp_keys state)"; }
hud_eval() { local s=$2 u t h; u=$(fld ui_state <<<"$s"); t=$(fld hud_text <<<"$s"); h=$(fld hud_shown <<<"$s")
  HUDS+="$1:$u/$t/$h "; HUDN=$((HUDN+1)); [ "$u" = "$1" ] && [ "$t" = "$u" ] && [ "$h" = 1 ] && [ "$(fld hud <<<"$s")" = 1 ] || HUDOK=0; }
# hud_poll <expected> <s>: snapshots until ui_state and hud_text both match (bounded), then judge THAT snapshot
# (4080 b39: a separate sample after the wait came ~0.6 s later, after a short free swing had already ended)
hud_poll() { local s end=$((SECONDS+$2)); while :; do s=$(A fp_keys state)
  [ "$(fld ui_state <<<"$s")" = "$1" ] && [ "$(fld hud_text <<<"$s")" = "$1" ] && break; [ $SECONDS -ge $end ] && break; sleep 0.1; done
  hud_eval "$1" "$s"; }

FP0=$(fps fp_mode); DIST0=$(cam target); AR0=""; PINNED=""; WEP=""; BOWN=""
cleanup() { A fp_move none >/dev/null; A fp_keys reset >/dev/null; A fp_keys swallow on >/dev/null; A fp_keys focus off >/dev/null
            A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            [ -n "$AR0" ] && A fp_combat autoreload "$AR0" >/dev/null
            [ "$(fps free)" = 1 ] && A fp_state free off >/dev/null
            for c in $PINNED; do A pin "$c" off >/dev/null; done
            arm_bow >/dev/null
            for c in "$SH" "$MT"; do A protect "$c" off >/dev/null; done
            A fp_camera distance "${DIST0:-0}" >/dev/null; A speed 1 >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$MT"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
A fp_keys state | grep -q 'hud_text=' || setup_fail "KenshiFP has no fp_keys/HUD state (needs 6E5D502B+): $(A fp_keys state | cut -c1-80)"
A fp_keys state | grep -q '\bhook=1\b' || setup_fail "fp_keys hook=0 (playerControl hook not installed): $(A fp_keys state | cut -c1-120)"
A fp_camera state | grep -q 'trace_blocks=' || setup_fail "KenshiFP fp_camera has no trace_blocks (needs 6E5D502B+)"
A fp_combat state | grep -q 'fp_ui_state=' || setup_fail "KenshiFP fp_combat state has no fp_ui_state (needs 6E5D502B+)"
A fp_move state | grep -q '^keys=' || setup_fail "KenshiFP has no fp_move"
A fp_melee state | grep -q 'active=' || setup_fail "KenshiFP has no fp_melee state"
BOWN=$(A rangedinfo "$SH" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOWN" = none ] && BOWN=""
AR0=$(cs auto_reload)
. "$(dirname "$0")/fp-ui-guard.sh" 2>/dev/null || { ui_guard_setup() { :; }; ui_clear() { return 0; }; ui_summary() { echo "ui_guard=missing"; }; raid_sweep() { :; }; }
A speed 1 hold >/dev/null; A fp_move none >/dev/null; A fp_keys reset >/dev/null
for c in "$SH" "$MT"; do A protect "$c" on >/dev/null; done
# the hostile stays conscious for K05-HOSTILE: pinned 60 m away and kept out of the raid guard until then
TGH=""; if A where "$TG" | grep -q 'pos='; then TGH=$(A where "$TG" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  A pin "$TG" at "$SH" dist 600 >/dev/null && PINNED+=" $TG"; A hunger "$TG" 300 >/dev/null; fi
if declare -f raid_sweep >/dev/null && [ -n "$TGH" ]; then   # raid guard without the hostile row target
  eval "$(declare -f raid_sweep | sed "s|sort -u)|sort -u \| grep -v -x -F '$TGH')|")"; fi
ui_guard_setup; ui_clear
take "$SH" || setup_fail "could not take $SH ($(A fp_control state | cut -c1-160))"
A fp_camera distance 0 >/dev/null; waitf 6 cam_ok || setup_fail "camera never at eye ($(camsum))"
# a locked rig has no foreground window: KenshiFP then frees the cursor; the test switch acts as focused
[ "$(fps cursor_hidden)" = 1 ] || { A fp_keys focus on | grep -q test_focus=1 && echo "SETUP test_focus=1 (game window not foreground)" >> "$LOG"; waitf 3 cursor_ok; }
[ "$(fps cursor_hidden)" = 1 ] || setup_fail "FP cursor not hidden (look mode off: $(A fp_state)); the swallow/MMB paths need it"
H0=$(ctl controlled); IDS0=$(ctl control_ids); HOME=$(pos "$SH"); MTID=$(id_of "$MT")
A pin "$MT" at "$SH" dist 25 face "$SH" | grep -q '^pinned' && PINNED+=" $MT" || setup_fail "could not pin $MT in front of $SH"
sleep 1; draw_to 0 || setup_fail "$SH weapon would not holster (drawn=$(ks drawn))"
echo "SETUP sh=$SH mt=$MT#$MTID tg=$TG$TGH bow='$BOWN' auto_reload=$AR0 home=$HOME controlled=$H0" >> "$LOG"

# ---- K01: native RMB walk swallowed; control: swallow off ----
if want K01; then ui_clear; look "$(cam yaw)" 0.5
  S0=$(ks rmb_swallowed); N0=$(ks native_injected); P0=$(pos "$SH"); A fp_keys native rmb 20 >/dev/null; sleep 3
  S1=$(ks rmb_swallowed); N1=$(ks native_injected); DON=$(d2 "$P0" "$(pos "$SH")")
  A fp_keys swallow off >/dev/null; P0=$(pos "$SH"); A fp_keys native rmb 20 >/dev/null; sleep 4
  S2=$(ks rmb_swallowed); DOFF=$(d2 "$P0" "$(pos "$SH")"); A fp_keys swallow on >/dev/null
  A teleport "$SH" $HOME >/dev/null; sleep 1.5; take "$SH" >/dev/null
  ev="swallow_on: rmb_swallowed $S0->$S1 injected $N0->$N1 moved=$DON | swallow_off: rmb_swallowed $S1->$S2 moved=$DOFF"
  ok=1; [ $((S1-S0)) -ge 1 ] && [ "$S2" = "$S1" ] && [ $((N1-N0)) -ge 20 ] || ok=0; lt "$DON" "$STILL_MAX" || ok=0
  if [ $ok = 1 ] && ! ge "$DOFF" "$MOVE_MIN"; then row K01 FAIL "inconclusive: the control (swallow off) native RMB did not move him either (cursor ground point unknown): $ev"
  else judge K01 $ok "$ev"; fi; fi

# ---- K02: MMB select the mate, no camera rotate ----
if want K02; then ui_clear; aim_at "$MT" 13; Y0=$(cam yaw); M0=$(ks mmb_selects); C0=$(ks mmb_cam_frames)
  # readiness (bounded): the crosshair pick must report the mate before the press; the pick line goes into the evidence
  PK=""; for _ in 1 2 3 4 5 6; do A fp_keys pick >/dev/null; sleep 0.3; PK=$(A fp_keys pick show); [ "$(fld result <<<"$PK")" = "$(uname_ "$MT")" ] && break; done
  echo "K02 pre-press $PK"
  A fp_keys press mmb 200 >/dev/null; waitf 3 kge mmb_selects $((M0+1)); sleep 0.4
  K=$(A fp_keys state); Y1=$(cam yaw); C2=$(A fp_control state); HI=$(fld inspected <<<"$C2"); HC=$(fld controlled <<<"$C2"); IDS2=$(fld control_ids <<<"$C2")
  ev="mmb_selects $M0->$(fld mmb_selects <<<"$K") none=$(fld mmb_none <<<"$K") last_select=$(fld last_select <<<"$K") cam_frames $C0->$(fld mmb_cam_frames <<<"$K") yaw $Y0->$Y1 pick_before=$(fld result <<<"$PK") pick_shape=$(fld shape <<<"$PK") pick_dist=$(fld hit_dist <<<"$PK") pick_aim_ok=$(fld aim_ok <<<"$PK") | inspected=$HI controlled=$H0->$HC ids_same=$([ "$IDS0" = "$IDS2" ] && echo 1 || echo 0)"
  ok=1; [ "$(fld mmb_selects <<<"$K")" = $((M0+1)) ] && [ "$(fld last_select <<<"$K")" = "$(uname_ "$MT")" ] || ok=0
  [ "$HC" = "$H0" ] && [ "$IDS2" = "$IDS0" ] && [ -n "$HI" ] && [ "$HI" != "$H0" ] || ok=0
  ge "$(fld mmb_cam_frames <<<"$K")" $((C0+1)) || ok=0
  awk -v a="$Y0" -v b="$Y1" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(a!="" && d<.02)}' || ok=0
  judge K02 $ok "$ev"; A select "$SH" >/dev/null; take "$SH" >/dev/null; fi

# ---- K03: RMB click holstered on the mate = context menu ----
if want K03; then ui_clear; draw_to 0; aim_at "$MT" 13; O0=$(ks ctx_opens)
  A fp_keys press rmb 150 >/dev/null; waitf 3 kge ctx_opens $((O0+1)); sleep 0.3
  K=$(A fp_keys state); FR=$(fps free); A fp_state free off >/dev/null; sleep 0.5; FREED2=$(ks ctx_freed); ui_clear
  ev="ctx_opens $O0->$(fld ctx_opens <<<"$K") ctx_none=$(fld ctx_none <<<"$K") ctx_freed=$(fld ctx_freed <<<"$K") last_target=$(fld last_target <<<"$K") free=$FR drawn=$(fld drawn <<<"$K") | after free off: ctx_freed=$FREED2"
  ok=1; [ "$(fld ctx_opens <<<"$K")" = $((O0+1)) ] && [ "$(fld ctx_freed <<<"$K")" = 1 ] && [ "$FR" = 1 ] && [ "$FREED2" = 0 ] || ok=0
  [ "$(fld last_target <<<"$K")" = "$(uname_ "$MT")" ] || ok=0; judge K03 $ok "$ev"; fi

# melee weapon for K06/K04/FB01/FS01/K05 (the fixture's player wields only a crossbow)
BOW_DROPPED=0; MELEE=0; if want K06 || want K04 || want FB01 || want FS01 || want K05 || want HUD01; then
  give_melee || echo "SETUP: could not give $SH a melee weapon" >> "$LOG"
  if [ "$(bow_now)" != none ]; then r=$(A unequip "$SH" "$(bow_now)"); case "$r" in *ground*) BOW_DROPPED=1;; esac; fi
  if arm_melee; then MELEE=1; else echo "SETUP: no melee weapon equips (inv weapons: $(weapons | tr '\n' ';'))" >> "$LOG"; fi; fi
mfail() { row "$1" FAIL "setup $SH has no melee weapon that equips (inv: $(weapons | tr '\n' ';'))"; }

# ---- K06 (draw part) + HUD holstered/ready ----
K06EV=""; K06OK=1
if [ $MELEE = 1 ]; then ui_clear; draw_to 0; sky; hud holstered
  D0=$(ks r_draws); A fp_keys press r 120 >/dev/null; waitf 4 kis drawn 1; W1=$(ks wih); hud_poll ready 3
  sleep 5; K=$(A fp_keys state); W2=$(fld wih <<<"$K")
  K06EV="draw: r_draws $D0->$(fld r_draws <<<"$K") wih=$W1 after_5s drawn=$(fld drawn <<<"$K") wih=$W2 sheathe_kept=$(fld sheathe_kept <<<"$K") r_keys=$(fld r_keys <<<"$K") fail=$(fld r_draw_fail <<<"$K")"
  [ "$(fld r_draws <<<"$K")" = $((D0+1)) ] && [ "$(fld drawn <<<"$K")" = 1 ] && [ -n "$W1" ] && [ "$W1" != 0 ] && [ -n "$W2" ] && [ "$W2" != 0 ] || K06OK=0
fi

# ---- K04: RMB held drawn on the mate = block, no menu ----
if want K04; then if [ $MELEE = 0 ]; then mfail K04; else ui_clear; draw_to 1; aim_at "$MT" 13; O0=$(ks ctx_opens); B0=$(ks free_block_frames)
  A fp_keys press rmb 2000 >/dev/null; sleep 0.8; K1=$(A fp_keys state); sleep 0.6; K2=$(A fp_keys state); sleep 1; O1=$(ks ctx_opens)
  ev="ui_state=$(fld ui_state <<<"$K1")/$(fld ui_state <<<"$K2") free_block_frames $B0->$(fld free_block_frames <<<"$K1")->$(fld free_block_frames <<<"$K2") block_checks=$(fld block_checks <<<"$K2") ctx_opens $O0->$O1 drawn=$(fld drawn <<<"$K1")"
  ok=1; [ "$(fld ui_state <<<"$K1")" = blocking ] && [ "$(fld ui_state <<<"$K2")" = blocking ] && [ "$O1" = "$O0" ] || ok=0
  lt "$B0" "$(fld free_block_frames <<<"$K1")" && lt "$(fld free_block_frames <<<"$K1")" "$(fld free_block_frames <<<"$K2")" || ok=0
  judge K04 $ok "$ev"; fi; fi

# ---- FB01: free block out of combat, aimed at the sky (+ HUD blocking) ----
if want FB01 || want HUD01; then if [ $MELEE = 0 ]; then want FB01 && mfail FB01; else ui_clear; draw_to 1; sky
  waitf 15 not_fight; FI0=$(A fp_melee state | fld active); B0=$(ks free_block_frames)
  A fp_keys press rmb 2000 >/dev/null; sleep 0.8; hud blocking; K1=$(A fp_keys state); sleep 0.6; K2=$(A fp_keys state)
  sleep 1.2; waitf 3 kis ui_state ready; U3=$(ks ui_state)
  ev="fight_active=$FI0 held: ui_state=$(fld ui_state <<<"$K1")/$(fld ui_state <<<"$K2") free_block_frames $B0->$(fld free_block_frames <<<"$K1")->$(fld free_block_frames <<<"$K2") | released: ui_state=$U3"
  ok=1; [ "$FI0" = 0 ] && [ "$(fld ui_state <<<"$K1")" = blocking ] && [ "$(fld ui_state <<<"$K2")" = blocking ] && [ "$U3" = ready ] || ok=0
  lt "$B0" "$(fld free_block_frames <<<"$K1")" && lt "$(fld free_block_frames <<<"$K1")" "$(fld free_block_frames <<<"$K2")" || ok=0
  want FB01 && { if [ "$FI0" != 0 ]; then row FB01 FAIL "setup $SH still in a native fight after 15 s: $ev"; else judge FB01 $ok "$ev"; fi; }; fi; fi

# ---- FS01: free swing, no target, no fight (+ HUD swinging) ----
if want FS01 || want HUD01; then if [ $MELEE = 0 ]; then want FS01 && mfail FS01; else ui_clear; draw_to 1; sky
  waitf 15 not_fight; FI0=$(A fp_melee state | fld active); HP0=$(A hp "$MT" | grep -o 'worst=[0-9-]*%'); K0=$(A fp_keys state)
  F0=$(fld free_swings <<<"$K0"); E0=$(fld fs_ends <<<"$K0"); G0=$(fld engages <<<"$K0")
  A fp_keys press lmb 100 >/dev/null; hud_poll swinging 2
  waitf 5 kge fs_ends $((E0+1)); sleep 0.5; K=$(A fp_keys state); FI1=$(A fp_melee state | fld active); HP1=$(A hp "$MT" | grep -o 'worst=[0-9-]*%')
  ev="fight_active=$FI0->$FI1 free_swings $F0->$(fld free_swings <<<"$K") fs_prog_max=$(fld fs_prog_max <<<"$K") fs_ends $E0->$(fld fs_ends <<<"$K") fs_notech=$(fld fs_notech <<<"$K") fs_faults=$(fld fs_faults <<<"$K") fs_dead=$(fld fs_dead <<<"$K") engages $G0->$(fld engages <<<"$K") $MT hp $HP0->$HP1"
  ok=1; [ "$(fld free_swings <<<"$K")" = $((F0+1)) ] && [ "$(fld fs_ends <<<"$K")" = $((E0+1)) ] && [ "$(fld fs_faults <<<"$K")" = 0 ] && [ "$(fld fs_dead <<<"$K")" = 0 ] || ok=0
  ge "$(fld fs_prog_max <<<"$K")" 0.5 || ok=0; [ "$(fld engages <<<"$K")" = "$G0" ] && [ "$FI1" = 0 ] && [ "$HP0" = "$HP1" ] || ok=0
  want FS01 && { if [ "$FI0" != 0 ]; then row FS01 FAIL "setup $SH still in a native fight after 15 s: $ev"; else judge FS01 $ok "$ev"; fi; }; fi; fi

# ---- K05: LMB drawn on a character = vanilla attack order (hostile, then unprovoked) ----
# engage_row <row> <npc ref> <name> <task>: LMB on the npc (pinned 1.5 m in front), engages+1, last_task, native fight on him
engage_row() { local G0 K FT ser ev ok; ui_clear; draw_to 1
  A pin "$2" at "$SH" dist 15 face "$SH" | grep -q '^pinned' || { row "$1" FAIL "setup could not pin $3 in front of $SH"; return; }
  PINNED+=" $2"; sleep 1; aim_at "$2" 13; G0=$(ks engages); ser=$(A where "$2" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
  A fp_keys press lmb 100 >/dev/null; waitf 3 kge engages $((G0+1)); waitf 8 in_fight "$ser"; FT=$?; K=$(A fp_keys state)
  ev="engages $G0->$(fld engages <<<"$K") last_task=$(fld last_task <<<"$K") last_target=$(fld last_target <<<"$K") lmb_clicks=$(fld lmb_clicks <<<"$K") native_fight_on_$3=$((1-FT)) [$(A fp_melee state | grep -o 'active=[^ ]* state=[^ ]*\|target_h=[^ ]*' | tr '\n' ' ')]"
  ok=1; [ "$(fld engages <<<"$K")" = $((G0+1)) ] && [ "$(fld last_task <<<"$K")" = "$4" ] && [ "$(fld last_target <<<"$K")" = "$(uname_ "$3")" ] && [ $FT = 0 ] || ok=0
  if [ $ok = 0 ] && [ "$(fld engages <<<"$K")" = $((G0+1)) ] && [ "$(fld last_task <<<"$K")" != "$4" ]; then row "$1" FAIL "inconclusive: $3 hostility not as set up (task $(fld last_task <<<"$K"), wanted $4): $ev"
  else judge "$1" $ok "$ev"; fi
  A ko "$2" 3600 >/dev/null; A pin "$2" off >/dev/null; waitf 10 isko "$2"; }
if want K05; then if [ $MELEE = 0 ]; then mfail K05-HOSTILE; mfail K05-UNPROV; else
  if [ -n "$TGH" ] && ! isko "$TG"; then engage_row K05-HOSTILE "$TGH" "$TG" 5; else row K05-HOSTILE FAIL "setup hostile $TG missing or KO ($(A where "$TG" | cut -c1-100))"; fi
  NH=""; NN=""
  if [ -n "$NEUTRAL" ]; then NH=$(A where "$NEUTRAL" | grep -oE '#[0-9]+/[0-9]+' | head -1); NN=$(A where "$NEUTRAL" | sed 's/ #[0-9].*//')
  else SF=$(A where "$SH" | grep -o '\[[^]]*\]' | head -1); SF=${SF:-@@nofaction@@}
    L=$(A chars 1500 "!ko|!dead" | sed 's/^[0-9]* within [0-9.]*: //' | tr '|' '\n' | sed 's/^ *//' | grep 'pos=' \
        | grep -v -F "$SF" | grep -v -E "\[(${FP_RAID_RE:-@@})\]|\[\?\]" | grep -v -E "^($SH|$MT|$TG) #" | head -1)
    NH=$(grep -oE '#[0-9]+/[0-9]+' <<<"$L" | head -1); NN=$(sed 's/ #[0-9].*//' <<<"$L"); fi
  if [ -z "$NH" ]; then row K05-UNPROV FAIL "setup no neutral NPC within 1500 (not squad/raider; set NEUTRAL=<name>)"
  else A relation "$NH" "$NEUTRAL_REL" >/dev/null; echo "K05-UNPROV neutral=$NN $NH relation set $NEUTRAL_REL" >> "$LOG"; engage_row K05-UNPROV "$NH" "$NN" 61; fi
  raid_sweep; waitf 20 not_fight || echo "SETUP: still in a native fight 20 s after K05" >> "$LOG"; fi
fi
[ -n "$TGH" ] && { A pin "$TG" off >/dev/null; isko "$TG" || A ko "$TG" 3600 >/dev/null; }

# ---- K06 (holster part) ----
if want K06; then if [ $MELEE = 0 ]; then mfail K06; else ui_clear; draw_to 1; H0R=$(ks r_holsters)
  A fp_keys press r 120 >/dev/null; waitf 4 kis drawn 0; K=$(A fp_keys state); W3=$(fld wih <<<"$K")
  K06EV+=" | holster: r_holsters $H0R->$(fld r_holsters <<<"$K") drawn=$(fld drawn <<<"$K") wih=$W3 ui_state=$(fld ui_state <<<"$K")"
  [ "$(fld r_holsters <<<"$K")" = $((H0R+1)) ] && [ "$(fld drawn <<<"$K")" = 0 ] && [ "$W3" = 0 ] || K06OK=0
  judge K06 $K06OK "$K06EV"; fi; fi

# ---- crossbow: HUD aiming, FF01 free fire + reload ----
if want HUD01 || want FF01; then ui_clear; draw_to 0
  if ! arm_bow; then want FF01 && row FF01 FAIL "setup crossbow '$BOWN' would not equip"; HUDOK=0; HUDS+="aiming:no_bow "
  else sky
    if want HUD01; then A fp_keys press r 120 >/dev/null; waitf 6 kis ranged 1; waitf 4 kis drawn 1
      A fp_keys press rmb 6000 >/dev/null; hud_poll aiming 3; A fp_keys release rmb >/dev/null; sleep 0.3; draw_to 0; fi
    if want FF01; then A fp_combat autoreload 0 >/dev/null; A fp_combat on >/dev/null; A fp_combat input 0 0 0 >/dev/null
      if ! waitf 4 csis armed 1; then row FF01 FAIL "setup adapter never armed (enabled=$(cs enabled) fault=$(cs fault) why=$(cs why))"
      else sky; S0=$(cs actual_shots); R0=$(cs reload_starts); A fp_combat input 1 0 0 >/dev/null; waitf 8 csis shot_ready 1; RDY=$(cs shot_ready)
        AM0=$(cs ammo); A fp_combat input 1 1 0 >/dev/null; waitf 3 csge actual_shots $((S0+1)); A fp_combat input 1 0 0 >/dev/null; sleep 0.5
        S1=$(cs actual_shots); AM1=$(cs ammo); UI1=$(cs fp_ui_state); HA=$(cs has_ammo); RE0=$(cs reload_emits); RF0=$(cs reload_refused)
        if [ "$HA" = 0 ]; then A fp_combat input 0 0 0 >/dev/null
          row FF01 FAIL "setup: no round matching the loaded bow in inventory/backpack (has_ammo=0 ammo_type=$(cs ammo_type) ammo=$AM1); shot actual_shots $S0->$S1 ammo $AM0->$AM1"
        else
        A fp_combat input 1 0 1 >/dev/null; sleep 0.3; A fp_combat input 1 0 0 >/dev/null; waitf 4 csge reload_starts $((R0+1)); UIR=$(cs fp_ui_state)
        waitf 30 csis reloading 0; sleep 0.3; R1=$(cs reload_starts); AM2=$(cs ammo); A fp_combat input 0 0 0 >/dev/null
        ev="shot_ready=$RDY actual_shots $S0->$S1 ammo $AM0->$AM1 ui=$UI1 | reload: reload_starts $R0->$R1 emits $RE0->$(cs reload_emits) refused $RF0->$(cs reload_refused) has_ammo=$HA ui=$UIR ammo->$AM2 last_reload_timer=$(cs last_reload_timer) why=$(cs why)"
        ok=1; [ "$RDY" = 1 ] && [ "$S1" = $((S0+1)) ] && [ "$AM1" = $((AM0-1)) ] && [ "$R1" = $((R0+1)) ] && lt "$AM1" "$AM2" || ok=0
        judge FF01 $ok "$ev"; fi; fi
      A fp_combat off >/dev/null; A fp_combat physical >/dev/null; [ -n "$AR0" ] && A fp_combat autoreload "$AR0" >/dev/null; fi; fi; fi
if want HUD01; then
  if [ $HUDN -lt 5 ]; then row HUD01 FAIL "setup only $HUDN of 5 states sampled (melee=$MELEE): $HUDS"; else judge HUD01 $HUDOK "$HUDS"; fi; fi

# ---- Z01: zoom 60 outdoors ----
if want Z01; then ui_clear; A teleport "$SH" $HOME >/dev/null; sleep 1.5; take "$SH" >/dev/null; look "$(cam yaw)" 0.3
  TB0=$(cam trace_blocks); A fp_camera distance 60 >/dev/null
  waitf 10 ge_applied; sleep 0.5
  C=$(A fp_camera state); PRB=$(A fp_camera probe | grep -o 'cam=.*' | cut -c1-120)
  ev="target=$(fld target <<<"$C") applied=$(fld applied <<<"$C") actual=$(fld actual_distance <<<"$C") blocked=$(fld blocked <<<"$C") view_max=$(fld view_max <<<"$C") trace_blocks $TB0->$(fld trace_blocks <<<"$C") [$PRB]"
  ok=1; ge "$(fld applied <<<"$C")" 59 && [ "$(fld blocked <<<"$C")" = 0 ] || ok=0
  awk -v a="$(fld actual_distance <<<"$C")" -v p="$(fld applied <<<"$C")" 'BEGIN{d=a-p; if(d<0)d=-d; exit !(a!="" && d<.5)}' || ok=0
  judge Z01 $ok "$ev"; A fp_camera distance 0 >/dev/null; waitf 8 cam_ok; fi

# ---- DOWN01: KO with W held (C05-KO fix 33d0358) ----
if want DOWN01; then ui_clear
  if [ ! -r "$KFPLOG" ]; then row DOWN01 FAIL "setup KenshiFP.log not readable at $KFPLOG (set KFPLOG=)"
  else take "$SH" >/dev/null; look "$(cam yaw)" 0; LN0=$(wc -l < "$KFPLOG")
    A fp_move w 30000 >/dev/null; sleep 1; A protect "$SH" off >/dev/null; A ko "$SH" 10 >/dev/null
    if waitf 15 isko "$SH"; then PK=$(pos "$SH"); MX=0; KEYS=""
      for _ in 1 2 3 4 5; do sleep 0.8; d=$(d2 "$PK" "$(pos "$SH")"); ge "$d" "$MX" && MX=$d; KEYS+="$(A fp_move state | fld keys)," ; done
      waitf 40 bash -c "! stobe-auto where '$SH' | grep -qE ' (KO|DEAD)( |\$)'"; WOKE=$?; sleep 2
      DW=$(d2 "$PK" "$(pos "$SH")"); A fp_move none >/dev/null; A protect "$SH" on >/dev/null
      NEW=$(tail -n +"$((LN0+1))" "$KFPLOG"); JMP=$(grep -c '\[down\] position jump' <<<"$NEW"); DRP=$(grep -c '\[down\] held fp_move keys dropped' <<<"$NEW")
      SUP=$(grep -c '\[down\] suppressed' <<<"$NEW"); grep '\[down\]' <<<"$NEW" | head -20 > "$OUT/down01-log.txt"
      ev="ko_at=$(tr ' ' , <<<"$PK") max_move_down=$MX after_wake=$DW woke=$((1-WOKE)) keys_while_down=[${KEYS%,}] log: jump=$JMP keys_dropped=$DRP suppressed=$SUP ($OUT/down01-log.txt)"
      ok=1; [ "$JMP" = 0 ] && ge "$DRP" 1 && [ $WOKE = 0 ] || ok=0; lt "$MX" "$DOWN_MAX" && lt "$DW" "$DOWN_MAX" || ok=0
      grep -q '[wasd]' <<<"$KEYS" && ok=0; judge DOWN01 $ok "$ev"
    else A fp_move none >/dev/null; A protect "$SH" on >/dev/null; row DOWN01 FAIL "setup $SH never knocked out"; fi; fi; fi

# ---- Z01-INT: building interior, wall behind, trace collision ----
if want Z01-INT; then ui_clear; BL=""; for f in ${INTERIOR:-house shack bar shop hut tower home}; do BL=$(A buildings 1500 "$f" | grep -m1 'pos='); [ -n "$BL" ] && break; done
  BP=$(grep -o 'pos=[^ ]*' <<<"$BL" | head -1 | cut -d= -f2 | tr ',' ' ')
  if [ -z "$BP" ]; then row Z01-INT FAIL "setup no building matching '${INTERIOR:-house shack bar shop hut tower home}' within 1500 (set INTERIOR=<filter>)"; else
    A teleport "$SH" $BP >/dev/null; sleep 2; take "$SH" >/dev/null; A fp_camera distance 0 >/dev/null; waitf 6 cam_ok
    YAW=$(cam yaw); look "$YAW" 0; A fp_move w 12000 >/dev/null; WALL=0; PP=$(pos "$SH"); N=0
    for _ in $(seq 1 22); do sleep 0.5; PN=$(pos "$SH"); if lt "$(d2 "$PP" "$PN")" 0.5; then N=$((N+1)); [ $N -ge 3 ] && { WALL=1; break; }; else N=0; fi; PP=$PN; done
    A fp_move none >/dev/null; sleep 0.5
    YB=$(awk -v y="$YAW" 'BEGIN{y+=3.14159; if(y>3.14159)y-=6.28318; printf "%.4f", y}'); look "$YB" 0
    TB0=$(cam trace_blocks); A fp_camera distance 30 >/dev/null; sleep 1.5; CI=$(A fp_camera state); PRB=$(A fp_camera probe | grep -o 'cam=.*' | cut -c1-120)
    ev="building='$(cut -c1-50 <<<"$BL")' wall_reached=$WALL | target=$(fld target <<<"$CI") applied=$(fld applied <<<"$CI") actual=$(fld actual_distance <<<"$CI") blocked=$(fld blocked <<<"$CI") trace_blocks $TB0->$(fld trace_blocks <<<"$CI") [$PRB]"
    A fp_camera distance 0 >/dev/null
    if [ $WALL = 0 ]; then row Z01-INT FAIL "setup no wall reached walking 11 s: $ev"; else
      ok=1; [ "$(fld blocked <<<"$CI")" = 1 ] && lt "$(fld applied <<<"$CI")" "$(fld target <<<"$CI")" && lt "$TB0" "$(fld trace_blocks <<<"$CI")" || ok=0
      judge Z01-INT $ok "$ev"; fi; fi; fi

echo "$(ui_summary)" >> "$LOG"
for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done
