#!/usr/bin/env bash
# fp-manual-anatomy.sh: in-game row R11 (animated anatomy) of the manual ranged adapter (COMBAT_TEST_PLAN.md), split in
# three sub-rows: R11-MOVE (moving/attacking target), R11-RACE (another race), R11-LIMB (missing limb).
# Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Skaera = hostile Hungry Bandit,
# Shay = squad mate Skaera attacks in R11-MOVE). Same input/aim method as fp-manual-hits.sh (`fp_combat input`,
# `fp_camera look` from the FP eye; game units = dm). Low-spread diagnostic (crossbows/perception 100, restored after):
# R11 checks hit routing, not balance.
# Evidence per shot: the victim's flesh per part (`hp` before/after) and the adapter's wound state from `fp_combat state`
# (wound_spatial / wound_native_fallback deltas, last_part, last_group, last_src, last_rel_h = impact height over the
# feet, last_bones = head,headnub,neck,pelvis,calf heights at impact, last_fallback = why native picked).
# A hit is "consistent" when the wound went spatial, the hp loss includes last_part, and last_group fits last_rel_h vs
# the victim's own bones at impact (head >= neck-1.5; chest pelvis-1.5..headnub+1.5; stomach calf..neck+1.5;
# arms pelvis-6..headnub+6; legs <= pelvis+1.5).
#  All rows: FP control is checked before every shot (ensure_fp) and re-taken if lost (fp_lost=N in the evidence; a
#           shot where it could not be re-taken = SETUP FAIL); every shot records on_target (crosshair ray on the npc).
#  R11-MOVE PASS: target really moved (>= 3 shots with >= 2 dm displacement between aim and shot), >= 3 hits, consistent >= hits-1,
#           fault=0.
#  R11-RACE PASS: spawned race differs from the target's race, >= 3 hits, consistent >= hits-1, aimed part >= total-2,
#           no native fallback (why=anatomy means the race isn't mapped: FAIL with that evidence).
#  R11-LIMB (last, permanent on this load): target's left leg severed (`sever`, as M08-LIMB); shots at leg height
#           (lateral offsets both sides) + 2 chest controls. PASS: stump, part 5 never loses flesh, no spatial wound on
#           part 5, the missing-limb path was exercised (some wound picked group leg_l), >= 2 hits, a re-sever is
#           refused (limb still lost), fault=0, wound_fault=0, still in the world.
#           A fully severed leg has no physics shape and impacts near the hip lie inside the torso silhouette, so real
#           shots almost never pick leg_l (4080 batch 14 / 5090 batch 6: 0 of 8). Two extra shots therefore arm the
#           product's test switch `fp_combat wound force leg_l` (replaces only the pick of the next bolt; part mapping,
#           native addWound and the spatial/fallback accounting run for real) and must show last_src=forced; the
#           part-5 checks apply to every shot. Evidence splits leg_l_picked into natural/forced.
# Usage: fp-manual-anatomy.sh [shooter] [target] [mate] [outdir] [move_shots] [race_shots_per_height]
# Ends with one `RESULT <row> PASS|FAIL <evidence>` per row (`RESULT <row> SETUP FAIL <reason>` when its setup fails).
SH=${1:-Axima}; TG=${2:-Skaera}; BL=${3:-Shay}; OUT=${4:-/tmp/fp-manual-anatomy}; NMOVE=${5:-10}; NRACE=${6:-2}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
. "$(dirname "$0")/fp-ui-guard.sh" 2>/dev/null ||   # ui_guard_setup / ui_clear (an NPC dialogue blocks manual shots)
  { ui_guard_setup() { :; }; ui_clear() { return 0; }; ui_summary() { echo "ui_guard=missing"; }; }
gf() { grep -o "\b$1=[^ ]*" <<<"$2" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
parts() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | tr '\n' ' '; }   # flesh of parts 0..6
hurt() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s="";for(i=1;i<=n;i++){d=y[i]-x[i];if(d<-0.5)s=s (s?",":"") (i-1) "(" sprintf("%.1f",d) ")"};print s}'; }
wst() { A fp_combat state | grep -o '\b\(fault\|wound_fault\|wound_spatial\|wound_native_fallback\|last_part\|last_group\|last_src\|last_rel_h\|last_fallback\|last_bones\)=[^ ]*' | tr '\n' ' '; }
dist2() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,x," ");split(b,y," ");printf "%.1f", sqrt((x[1]-y[1])^2+(x[3]-y[3])^2)}'; }
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT R11 SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
BLK0=$(A combatmode "$BL" | fld block)
SK0=$(A stat "$SH" crossbows | grep -o 'base=[0-9.]*' | cut -d= -f2); PE0=$(A stat "$SH" perception | grep -o 'base=[0-9.]*' | cut -d= -f2)
SPAWN=""
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            [ -n "$SK0" ] && A setstat "$SH" crossbows "$SK0" >/dev/null; [ -n "$PE0" ] && A setstat "$SH" perception "$PE0" >/dev/null
            [ -n "$BLK0" ] && A combatmode "$BL" block "$([ "$BLK0" = 1 ] && echo on || echo off)" >/dev/null
            [ -n "$SPAWN" ] && { A pin "$SPAWN" off >/dev/null; A ko "$SPAWN" 600 >/dev/null; }
            A pin "$TG" off >/dev/null; A pin "$BL" off >/dev/null; A protect "$TG" off >/dev/null; A protect "$BL" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

# aim_at <npc> <height dm> [lateral dm]: point the FP camera at the npc's feet + height, shifted sideways (perpendicular
# to the line of sight) by lateral
aim_at() { local e; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" -v o="${3:-0}" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); if(h>0){c+=o*(d-b)/h; d-=o*(c-a)/h}; h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; AIM_NPC=$1; AIM_H=$2; AIM_L=${3:-0}; AIM_PT=""; sleep 0.4; }
# aim_pt <npc> <x> <y> <z>: point the FP camera from the camera itself at a world point (a bone of a fallen body, where
# a height above the feet means nothing); shot() re-aims at the same point (AIM_PT)
aim_pt() { local c cx cy cz; c=$(A fp_camera state); cx=$(gf camera_x "$c"); cy=$(gf camera_y "$c"); cz=$(gf camera_z "$c")
  read -r YAW PIT <<<"$(awk -v a="$cx" -v b="$cz" -v ey="$cy" -v c="$2" -v py="$3" -v d="$4"      'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; AIM_NPC=$1; AIM_PT="$2 $3 $4"; sleep 0.4; }
reaim() { if [ -n "$AIM_PT" ]; then aim_pt "$AIM_NPC" $AIM_PT; else aim_at "$AIM_NPC" "$AIM_H" "$AIM_L"; fi; }
# shot <victim...>: one manual shot at the current AIM_*; sets S_OK (1 = actual_shots rose), S_HURT[i] (hurt list per
# victim), S_MOVE (dm the aimed npc moved between the pre-aim read and the shot), W0/W1 (wound state before/after)
# ensure_fp: FP mode, direct control of the shooter, a valid FP camera and an armed adapter. 5090 run fp-5090-5: FP
# mode toggled OFF mid-run (KenshiFP.log `[input] FP mode toggled -> OFF`, a Right Alt edge, not a wrapper command),
# camera_y=0 -> every later aim had pitch -1.54 (refused) and `fp_combat aim` "aim query unavailable": R11-RACE/LIMB
# measured nothing. Lost control is re-taken and counted (FPLOST, in every row's evidence); 1 = could not re-take.
FPLOST=0
ensure_fp() { local c; c=$(A fp_camera state)
  [ "$(gf direct "$c")" = 1 ] && [ "$(gf world_valid "$c")" = 1 ] && [ "$(cs actor)" != 0 ] && return 0
  FPLOST=$((FPLOST+1)); echo "FP LOST #$FPLOST: direct=$(gf direct "$c") world_valid=$(gf world_valid "$c") actor=$(cs actor) $(A fp_state | cut -c1-60); re-taking $SH" >> "$LOG"
  A select "$SH" >/dev/null; A fp_mode on >/dev/null
  for _ in $(seq 1 10); do sleep 0.5; A fp_state | grep -q 'fp_mode=1' && break; done
  A fp_control take >/dev/null; A fp_combat on >/dev/null; inp 0 0 0; waitfor 5 armed 1 || return 1
  local end=$((SECONDS+5)); while [ $SECONDS -lt $end ]; do c=$(A fp_camera state)
    [ "$(gf direct "$c")" = 1 ] && [ "$(gf world_valid "$c")" = 1 ] && return 0; sleep 0.3; done; return 1; }
# on_target <npc>: 1 when the last `fp_combat aim` reply (AIMR) has the crosshair ray on that npc (id4 = its serial)
on_target() { local s; s=$(A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'); [ -n "$s" ] && grep -q "\bid4=$s\b" <<<"$AIMR" && echo 1 || echo 0; }
shot() { local s0 b=() v i=0 p0 p1; S_HURT=(); S_OK=0; S_MOVE=0; S_ON=0; S_FP=1
  ensure_fp || { S_FP=0; for v in "$@"; do S_HURT+=(""); done; W0=$(wst); W1=$W0; return; }
  s0=$(cs actual_shots); W0=$(wst)
  for v in "$@"; do A protect "$v" off >/dev/null; A health "$v" 100 >/dev/null; done; sleep 0.3
  for v in "$@"; do b+=("$(parts "$v")"); done
  ui_clear; inp 1 0 0; if ! { waitfor 8 shot_ready 1 || { ui_clear && inp 0 0 0 && sleep 0.4 && inp 1 0 0 && waitfor 8 shot_ready 1; }; }; then for v in "$@"; do A protect "$v" on >/dev/null; S_HURT+=(""); done; W1=$W0; return; fi
  p0=$(pos "$AIM_NPC"); if [ -n "$AIM_COL" ] && [ -z "$AIM_PT" ]; then jit_aim; else reaim; fi; waitfor 3 shot_ready 1
  AIMR=$(A fp_combat aim); echo "$AIMR" >> "$OUT/aims.txt"; S_ON=$(on_target "$AIM_NPC")
  inp 1 1 0; local end=$((SECONDS+3))
  while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && { S_OK=1; break; }; sleep 0.1; done
  p1=$(pos "$AIM_NPC"); S_MOVE=$(dist2 "$p0" "$p1")
  inp 1 0 0; sleep 2.5
  for v in "$@"; do S_HURT+=("$(hurt "${b[$i]}" "$(parts "$v")")"); i=$((i+1)); A protect "$v" on >/dev/null; done
  W1=$(wst); inp 1 0 0; waitfor 6 reloading 0 >/dev/null; }
# consistent <group> <rel_h> <bones csv>: 1 when the wound group fits the impact height vs the victim's bones
consistent() { awk -v g="$1" -v h="$2" -v b="$3" 'BEGIN{n=split(b,x,",");if(n<5||h=="nan"||x[3]=="nan"||x[4]=="nan"){print 0;exit}
  hn=(x[2]=="nan")?x[1]:x[2];nk=x[3];pv=x[4];cf=x[5];t=1.5;ok=0
  if(g=="head")ok=(h>=nk-t);else if(g=="chest")ok=(h>=pv-t&&h<=hn+t);else if(g=="stomach")ok=(h>=cf&&h<=nk+t)
  else if(g~/^arm/)ok=(h>=pv-6&&h<=hn+6);else if(g~/^leg/)ok=(h<=pv+t);print ok?1:0}'; }
# judge <victim hurt>: classify the last shot for the aimed victim; sets J (hit|miss), JS (1 spatial), JC (1 consistent),
# JD (one-line evidence); uses W0/W1
judge() { local h=$1 sd fd lp lg; J=miss; JS=0; JC=0; JW=0; JD="miss"
  [ -n "$h" ] || return 0; J=hit
  local a b c d; a=$(gf wound_spatial "$W1"); b=$(gf wound_spatial "$W0"); c=$(gf wound_native_fallback "$W1"); d=$(gf wound_native_fallback "$W0")
  sd=$(( ${a:-0} - ${b:-0} )); fd=$(( ${c:-0} - ${d:-0} )); [ $((sd+fd)) = 1 ] && JW=1
  lp=$(gf last_part "$W1"); lg=$(gf last_group "$W1")
  if [ "$sd" = 1 ] && [ "$fd" = 0 ]; then JS=1
    [[ ",$h" == *",$lp("* ]] && [ "$(consistent "$lg" "$(gf last_rel_h "$W1")" "$(gf last_bones "$W1")")" = 1 ] && JC=1
    JD="hp=$h part=$lp/$lg rel_h=$(gf last_rel_h "$W1") bones=$(gf last_bones "$W1") ok=$JC"
  else JD="hp=$h fallback=$(gf last_fallback "$W1") group=$lg sd=$sd fd=$fd"; fi; }
lowspread() { A setstat "$SH" crossbows 100 >/dev/null; A setstat "$SH" perception 100 >/dev/null; }
# bones_of <npc>: aim heights head chest legs from the victim's skeleton via `fp_combat aim` (crosshair on it)
# (no subshell: sets BAIM="head chest legs" or "", BREPLY = the last aim reply, so ensure_fp's count survives)
bones_of() { BAIM=""; BREPLY=""; for _ in 1 2 3 4; do ensure_fp || { BREPLY="FP control lost, re-take failed"; return 1; }
    aim_at "$1" "${2:-12}"; BREPLY=$(A fp_combat aim); grep -q '\baim=[-0-9.]*,' <<<"$BREPLY" && break; sleep 0.5; done
  BAIM=$(grep -o '\baim=[-0-9.,]*' <<<"$BREPLY" | cut -d= -f2 | tr , ' '); [ -n "$BAIM" ]; }
# jit_aim: with AIM_COL set (1 head, 2 chest, 3 legs of aim=head,chest,legs), re-read the aimed npc's bones right
# before the trigger and aim at that column (R11-RACE 4080 batch 14 / 5090 batch 6: the pose moved 1-3 dm between the
# settled read and the shot, e.g. head aim 12.94 with the neck at 15.21 at impact, so head aims hit the chest). First
# the crosshair as aimed (the ray usually is on the npc), else bones_of. JIT_H = height used, "stale" = no fresh read
# had the ray on the npc (then the previous aim is restored).
AIM_COL=""; JIT_H=""
jit_aim() { local r h="" h0=$AIM_H l0=$AIM_L; r=$(A fp_combat aim); AIMR=$r
  [ "$(on_target "$AIM_NPC")" = 1 ] && h=$(grep -o '\baim=[-0-9.]*,[-0-9.]*,[-0-9.]*' <<<"$r" | cut -d= -f2 | cut -d, -f"$AIM_COL")
  if [ -z "$h" ] && bones_of "$AIM_NPC" && AIMR=$BREPLY && [ "$(on_target "$AIM_NPC")" = 1 ]; then h=$(cut -d' ' -f"$AIM_COL" <<<"$BAIM"); fi
  if [ -n "$h" ]; then JIT_H=$h; aim_at "$AIM_NPC" "$h" "$l0"; else JIT_H=stale; aim_at "$AIM_NPC" "$h0" "$l0"; fi; }
# fresh_bones <npc>: bones_of with the ray on the npc, repeated until two reads 0.5 s apart agree on the head aim
# height within 1 dm (a target still in a hit reaction / sway gives stale heights: R11-RACE 4080 batch 12, Hive
# Prince head bone 13.6..18.4 dm between shots). Sets BAIM (last read) or "" when the ray never got on the npc.
fresh_bones() { local prev="" a k; for k in 1 2 3 4 5 6; do
    bones_of "$1" "${2:-12}" && AIMR=$BREPLY && [ "$(on_target "$1")" = 1 ] || { BAIM=""; sleep 0.5; continue; }
    a=$(cut -d' ' -f1 <<<"$BAIM")
    [ -n "$prev" ] && awk -v x="$a" -v y="$prev" 'BEGIN{d=x-y;exit !(d<1&&d>-1)}' && return 0
    prev=$a; sleep 0.5; done; [ -n "$BAIM" ]; }
# bonept_of <npc> <bone>: finds the npc under the crosshair at any height (standing or fallen: 12..0.8 dm above its
# feet) and reads that bone's world point from `fp_combat aim` (bw_<bone>=x,y,z; "chest" = 70% pelvis->neck).
# Sets BPT="x y z", BREPLY/AIMR = the reply; 1 when the ray never got on the npc or the bone is missing.
bonept_of() { local h r q; BPT=""; for h in 12 9 6 4 2.5 1.5 0.8; do ensure_fp || return 1
    aim_at "$1" "$h"; r=$(A fp_combat aim); BREPLY=$r; AIMR=$r; [ "$(on_target "$1")" = 1 ] || continue
    if [ "$2" = chest ]; then q=$(awk -v p="$(gf bw_pelvis "$r")" -v n="$(gf bw_neck "$r")" 'BEGIN{split(p,a,",");split(n,b,",");
        if(a[1]==""||b[1]==""||a[1]~/nan/||b[1]~/nan/)exit;printf "%.2f %.2f %.2f",a[1]+0.7*(b[1]-a[1]),a[2]+0.7*(b[2]-a[2]),a[3]+0.7*(b[3]-a[3])}')
    else q=$(gf "bw_$2" "$r" | tr , ' '); fi
    [ -n "$q" ] && [[ "$q" != *nan* ]] && { BPT=$q; return 0; }; done; return 1; }
# moving_now <npc>: 1 when the npc moves >= 1 dm within 0.5 s, polled up to 6 s (readiness: a really moving target)
moving_now() { local a b end=$((SECONDS+6)); while [ $SECONDS -lt $end ]; do a=$(pos "$1"); sleep 0.5; b=$(pos "$1")
    awk -v d="$(dist2 "$a" "$b")" 'BEGIN{exit !(d>=1)}' && return 0; done; return 1; }

# ---- setup (as fp-manual-hits.sh) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG" "$BL"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
A where "$TG" | grep -q 'DEAD' && setup_fail "$TG is dead"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null; A protect "$BL" on >/dev/null
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH"|"$BL") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
A pin "$BL" at "$SH" dist 400 >/dev/null
A pin "$TG" at "$SH" dist 30 face "$SH" | grep -q '^pinned' || setup_fail "pin $TG near $SH refused"
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (enabled=$(cs enabled) fault=$(cs fault) why=$(cs why))"
[ "$(cs wound_ready)" = 1 ] || setup_fail "wound routing not ready (wound_ready=$(cs wound_ready) wound_enabled=$(cs wound_enabled))"
TGRACE=$(A chars 3000 "$TG" | grep -o 'race=[^|]*' | head -1 | cut -d= -f2 | sed 's/ *$//')
lowspread; A fp_combat wound reset >/dev/null; ui_guard_setup

# ---- R11-MOVE: Skaera runs in on Shay (block-only, pinned 60 dm off the shooter) and swings at her ----
# odd shots: Skaera put 150 dm from Shay and sent at her, shot once she is seen moving (running target); even shots:
# Skaera at Shay, attacking. Only shots where she moved >= 2 dm between aim and shot count as moving.
read -r sx sy sz <<<"$(pos "$SH")"
A combatmode "$BL" block on >/dev/null
A pin "$BL" off >/dev/null; A pin "$BL" at "$(awk -v x="$sx" 'BEGIN{print x+60}')" "$sy" "$sz" | grep -q '^pinned' || { row R11-MOVE "SETUP" "FAIL pin $BL at 60 dm refused"; SKIPMOVE=1; }
hits=0; cons=0; moved=0; ontg=0; nofp=0; nomove=0; ev=""
if [ -z "$SKIPMOVE" ]; then
  for k in $(seq 1 "$NMOVE"); do
    if [ $((k%2)) = 1 ]; then ph=run   # put 150 dm from Shay, sent at her: shot while she really runs (readiness below)
      A pin "$TG" at "$BL" dist 150 >/dev/null; A pin "$TG" off >/dev/null; A attack "$TG" "$BL" >/dev/null
      moving_now "$TG" || { A attack "$TG" "$BL" >/dev/null; moving_now "$TG" || { nomove=$((nomove+1)); ph=run_still; }; }
    else ph=fight; A pin "$TG" off >/dev/null; A attack "$TG" "$BL" >/dev/null
      for _ in $(seq 1 40); do [ "$(awk -v d="$(dist2 "$(pos "$TG")" "$(pos "$BL")")" 'BEGIN{print (d<=25)}')" = 1 ] && break; sleep 0.25; done; fi
    bones_of "$TG"; AH=$(cut -d' ' -f2 <<<"$BAIM"); aim_at "$TG" "${AH:-12.5}"
    shot "$TG" "$BL"; judge "${S_HURT[0]}"
    [ "$S_FP" = 0 ] && nofp=$((nofp+1)); [ "$S_ON" = 1 ] && ontg=$((ontg+1))
    awk -v m="$S_MOVE" 'BEGIN{exit !(m>=2)}' && moved=$((moved+1))
    [ "$J" = hit ] && { hits=$((hits+1)); [ "$JC" = 1 ] && cons=$((cons+1)); }
    ev+="$ph:shot=$S_OK on_target=$S_ON move=$S_MOVE ${JD}; "
  done
  echo "R11-MOVE shots: $ev" >> "$LOG"
  F=$(cs fault)
  sum="moving shots=$moved/$NMOVE (>=2 dm aim->shot; run never started=$nomove) aim_on_target=$ontg hits=$hits consistent=$cons fault=$F fp_lost=$FPLOST (per-shot in log)"
  if [ "$nofp" -gt 0 ]; then row R11-MOVE SETUP "FAIL FP control lost and not re-taken on $nofp shots: $sum"
  elif [ "$moved" -lt 3 ]; then row R11-MOVE SETUP "FAIL target did not move: $sum"
  elif [ "$hits" -ge 3 ] && [ "$cons" -ge $((hits-1)) ] && [ "$F" = 0 ]; then row R11-MOVE PASS "$sum"
  else row R11-MOVE FAIL "$sum"; fi
fi
A combatmode "$BL" block "$([ "$BLK0" = 1 ] && echo on || echo off)" >/dev/null
A pin "$BL" off >/dev/null; A pin "$BL" at "$SH" dist 400 >/dev/null
A pin "$TG" at "$SH" dist 30 face "$SH" >/dev/null; sleep 1

# eye_dist <npc>: horizontal distance (whole dm) from the FP eye to the npc's feet
eye_dist() { local c t; c=$(A fp_camera state); read -r t <<<"$(pos "$1")"
  awk -v a="$(gf camera_x "$c")" -v b="$(gf camera_z "$c")" -v t="$t" 'BEGIN{split(t,y," "); if (a=="" || y[3]=="") {print 0; exit}
    printf "%d", sqrt((y[1]-a)^2+(y[3]-b)^2)}'; }
# upright <npc>: wait (<= ~10 s) until the npc stands again: head bone within 1 dm of the tallest head seen (REFH) on two
# reads in a row. A bolt staggers / knocks the target down; a lying body reads stable too, so fresh_bones aimed at the low
# pose and the target stood up before the bolt arrived (4080 b19 Shek: head bone 21.0, 22.0, 11.9, 13.5 dm; aimed_part 2/6)
REFH=""; upright() { local k h p=""; for k in $(seq 1 14); do
    if bones_of "$1"; then h=$(grep -o '\bbones=[^ ]*' <<<"$BREPLY" | cut -d= -f2 | cut -d, -f1)
      if [ -n "$h" ] && [ "$h" != nan ]; then REFH=$(awk -v a="${REFH:-0}" -v b="$h" 'BEGIN{print (b>a)?b:a}')
        if awk -v h="$h" -v r="$REFH" 'BEGIN{exit !(h>=r-1.0)}'; then [ -n "$p" ] && return 0; p=1; else p=""; fi; fi; fi
    sleep 0.7; done; return 1; }
# ---- R11-RACE: a Shek or Hive Hungry Bandit (spawn race filter), pinned at 30 dm ----
SPR=""; # Shek first: a Hive drone's idle bob moves its neck 14.4<->16.9 dm within ~1 s, more than its 1 dm head band, so
# aimed-part shots can't be placed (5090 b8: 2 head shots landed as chest; mapping consistent 5/5); hive/skeleton only as fallback
for spec in 'Hungry Bandit|shek' 'Drifter|shek' 'Hungry Bandit|shek|hive' 'Drifter|shek|hive|skeleton'; do
  t=${spec%%|*}; rf=${spec#*|}
  SPR=$(A spawn "$t" Drifters near "$SH" dist 30 count 1 race "$rf"); grep -q '^spawned 1/1' <<<"$SPR" && break; SPR=""; done
if [ -z "$SPR" ]; then row R11-RACE SETUP "FAIL no Shek/Hive/Skeleton spawn: $(tail -1 "$LOG" | cut -c1-200)"
else
  SPAWN=$(grep -o '#[0-9]*/[0-9]*' <<<"$SPR" | head -1); SRACE=$(grep -o 'race=[^,]*' <<<"$SPR" | head -1 | cut -d= -f2 | sed 's/ *rerolls.*//; s/ *$//')
  A protect "$SPAWN" on >/dev/null; A pin "$SPAWN" at "$SH" dist 30 face "$SH" >/dev/null; A pin "$TG" at "$SH" dist 500 >/dev/null; sleep 1.5
  # bones from the spawn itself: the ray must be on it (id4 = its serial), else the reply is another body's
  BAIM=""; for _ in 1 2 3; do bones_of "$SPAWN" && AIMR=$BREPLY && [ "$(on_target "$SPAWN")" = 1 ] && break; BAIM=""; sleep 1; done
  read -r AH AC AL <<<"$BAIM"
  if [ -z "$AL" ]; then row R11-RACE SETUP "FAIL no bone reply with the ray on $SRACE $SPAWN fp_lost=$FPLOST (last aim: $(cut -c1-220 <<<"$BREPLY"))"
  else hits=0; cons=0; good=0; total=0; fb=""; ev=""; ontg=0; nofp=0; tooclose=0; nup=0; REFH=
    for spec in "head 1 0" "chest 2 1" "legs 3 5,6"; do read -r name col want <<<"$spec"
      for _ in $(seq 1 "$NRACE"); do
        # aim height from the spawn's pose right now (settled), not the one read before the first shot
        # the spawn drifts inside its pin (4080 b16: 4 dm from the eye, a ray to the knee hits the capsule top): re-pin
        # at 30 dm when the eye is under 15 dm away; still too close = no shot, the row is a setup failure (too_close)
        if [ "$(eye_dist "$SPAWN")" -lt 15 ]; then A pin "$SPAWN" at "$SH" dist 30 face "$SH" >/dev/null; sleep 1.5
          [ "$(eye_dist "$SPAWN")" -lt 15 ] && { tooclose=$((tooclose+1)); ev+="$name:too_close=$(eye_dist "$SPAWN"); "; continue; }; fi
        upright "$SPAWN" || nup=$((nup+1))
        fresh_bones "$SPAWN" && ht=$(cut -d' ' -f"$col" <<<"$BAIM") || ht=$(cut -d' ' -f"$col" <<<"$AH $AC $AL")
        aim_at "$SPAWN" "$ht"; AIM_COL=$col; JIT_H=""; shot "$SPAWN"; AIM_COL=""; judge "${S_HURT[0]}"; total=$((total+1))
        [ "$S_FP" = 0 ] && nofp=$((nofp+1)); [ "$S_ON" = 1 ] && ontg=$((ontg+1))
        for w in ${want//,/ }; do [[ ",${S_HURT[0]}" == *",$w("* ]] && { good=$((good+1)); break; }; done
        [ "$J" = hit ] && { hits=$((hits+1)); [ "$JC" = 1 ] && cons=$((cons+1)); [ "$JS" = 0 ] && fb+="$(gf last_fallback "$W1"),"; }
        ev+="$name:aim_h=$ht jit_h=${JIT_H:-none} on_target=$S_ON $JD; "; done; done
    echo "R11-RACE shots: $ev" >> "$LOG"
    F=$(cs fault)
    sum="race=$SRACE (target race=${TGRACE:-?}) $SPAWN aim_h=$AH/$AC/$AL aim_on_target=$ontg/$total hits=$hits consistent=$cons aimed_part=$good/$total not_upright=$nup ref_head=$REFH fallbacks=${fb%,} fault=$F fp_lost=$FPLOST"
    if [ "$tooclose" -gt 0 ]; then row R11-RACE SETUP "FAIL reason=too_close: the spawn stayed under 15 dm from the eye on $tooclose shots: $sum"
    elif [ "$nofp" -gt 0 ]; then row R11-RACE SETUP "FAIL FP control lost and not re-taken on $nofp shots: $sum"
    elif [ -n "$TGRACE" ] && [ "$SRACE" = "$TGRACE" ]; then row R11-RACE SETUP "FAIL spawned race equals the target's: $sum"
    elif [ "$hits" -ge 3 ] && [ "$cons" -ge $((hits-1)) ] && [ "$good" -ge $((total-2)) ] && [ -z "$fb" ] && [ "$F" = 0 ]; then row R11-RACE PASS "$sum"
    else row R11-RACE FAIL "$sum"; fi
  fi
  A pin "$SPAWN" off >/dev/null; A pin "$SPAWN" at "$SH" dist 600 >/dev/null; A ko "$SPAWN" 600 >/dev/null
fi
A pin "$TG" at "$SH" dist 30 face "$SH" >/dev/null; sleep 1

# ---- R11-LIMB (last: permanent on this load): left leg severed, shots at leg height ----
LS=$(A sever "$TG" left_leg noitem | grep -o "> [a-z]*" | tr -d "> "); sleep 2
A protect "$TG" on >/dev/null; A pin "$TG" at "$SH" dist 30 face "$SH" >/dev/null; sleep 1.5
if [ "$LS" != stump ]; then row R11-LIMB SETUP "FAIL sever $TG left_leg did not give a stump (state=${LS:-?})"
# Readiness: the target (one leg gone: she may crawl) must be pinned in front, not KO, with the ray on her (bones after
# the sever, so aim heights follow her real pose). Each shot records on_target and KO; a shot with the ray off her or
# her KO is reported, never counted as evidence for the missing limb.
else A pin "$TG" at "$SH" dist 30 face "$SH" >/dev/null
  BAIM=""; for _ in 1 2 3; do bones_of "$TG" && AIMR=$BREPLY && [ "$(on_target "$TG")" = 1 ] && break; BAIM=""; sleep 1; done
  read -r AH AC AL <<<"$BAIM"
  # One leg gone: she usually falls and crawls (4080 batch 12: the ray at standing height hit the ground behind her).
  # Then aim at her live bones (world points, re-read before every shot) instead of heights above the feet.
  LIMBMODE=height
  if [ -z "$AL" ]; then
    if bonept_of "$TG" lthigh; then LIMBMODE=bones; echo "R11-LIMB: $TG not upright ($(gf prone "$BREPLY")), aiming at bone points" >> "$LOG"
    else row R11-LIMB SETUP "FAIL no bone reply with the ray on $TG after the sever (scanned 12..0.8 dm) fp_lost=$FPLOST (last aim: $(cut -c1-220 <<<"$BREPLY"))"; NOLIMB=1; fi
  fi
fi
if [ "$LS" = stump ] && [ -z "$NOLIMB" ]; then
  hits=0; p5=0; sp5=0; legl=0; leglf=0; forced=0; fbad=""; ev=""; ontg=0; nofp=0; kos=0
  if [ "$LIMBMODE" = bones ]; then SPECS=("lthigh -" "lcalf -" "lthigh -" "lcalf -" "lthigh -" "lfoot -" "chest -" "chest -" "chest - force" "chest - force")
  else SPECS=("$AL -1" "$AL 1" "$AL -1" "$AL 1" "$AL 0" "$AL 0" "$AC 0" "$AC 0" "$AC 0 force" "$AC 0 force"); fi
  for spec in "${SPECS[@]}"; do read -r ht lat fc <<<"$spec"
    A hp "$TG" | grep -q ' KO ' && { kos=$((kos+1)); A protect "$TG" on >/dev/null; sleep 2; }
    if [ "$LIMBMODE" = bones ]; then
      # live bone point; a bone that is gone with the leg (no point) falls back to the left thigh stump, then the pelvis
      bonept_of "$TG" "$ht" || bonept_of "$TG" lthigh || bonept_of "$TG" pelvis
      if [ -n "$BPT" ]; then aim_pt "$TG" $BPT; else aim_at "$TG" 2; fi
    else aim_at "$TG" "$ht" "$lat"; fi
    if [ "$fc" = force ]; then FR=$(A fp_combat wound force leg_l)
      [ "$(gf wound_force "$FR")" = leg_l ] || { fbad+="arm:$(cut -c1-40 <<<"$FR"),"; fc=""; }; fi
    shot "$TG"; judge "${S_HURT[0]}"
    if [ "$fc" = force ]; then forced=$((forced+1)); FR=$(A fp_combat wound force none)
      [ "$J" = hit ] && [ "$(gf last_src "$W1")" != forced ] && fbad+="src=$(gf last_src "$W1"),"
      [ "$J" = hit ] && [ "$JW" = 1 ] && [ "$(gf last_group "$W1")" = leg_l ] && leglf=$((leglf+1)); fi
    [ "$S_FP" = 0 ] && nofp=$((nofp+1)); [ "$S_ON" = 1 ] && ontg=$((ontg+1))
    [ "$J" = hit ] && hits=$((hits+1))
    [[ ",${S_HURT[0]}" == *",5("* ]] && p5=$((p5+1))
    [ "$JS" = 1 ] && [ "$(gf last_part "$W1")" = 5 ] && sp5=$((sp5+1))
    [ "$JW" = 1 ] && [ "$(gf last_group "$W1")" = leg_l ] && legl=$((legl+1))
    ev+="h=$ht lat=$lat${fc:+ $fc} on_target=$S_ON:$JD; "; done
  echo "R11-LIMB shots: $ev" >> "$LOG"
  RS=$(A sever "$TG" left_leg noitem); C=$(A fp_combat state); W=$(A status | grep -o 'phase=[a-z]*')
  F=$(gf fault "$C"); WF=$(gf wound_fault "$C")
  sum="left_leg=$LS aim=$LIMBMODE aim_on_target=$ontg/${#SPECS[@]} ko_before_shot=$kos fp_lost=$FPLOST hits=$hits part5_flesh_lost=$p5 spatial_part5=$sp5 leg_l_picked=$legl(natural=$((legl-leglf)),forced=$leglf/$forced) force_bad=${fbad%,} resever='$(cut -c1-60 <<<"$RS")' fault=$F wound_fault=$WF $W"
  if [ "$nofp" -gt 0 ]; then row R11-LIMB SETUP "FAIL FP control lost and not re-taken on $nofp shots: $sum"
  elif [ "$ontg" = 0 ]; then row R11-LIMB SETUP "FAIL the ray was never on $TG: $sum"
  elif [ "$hits" -ge 2 ] && [ "$p5" = 0 ] && [ "$sp5" = 0 ] && [ "$legl" -ge 1 ] && [ -z "$fbad" ] && [[ "$RS" != *"-> stump"* ]] && [ "$F" = 0 ] && [ "$WF" = 0 ] && [ "$W" = phase=world ]; then row R11-LIMB PASS "$sum"
  else row R11-LIMB FAIL "$sum"; fi
fi

echo "UI guard: $(ui_summary)" >> "$LOG"
printf '%s\n' "${RESULTS[@]}" | while read -r l; do case "$l" in *FAIL*) echo "$l log=$LOG";; *) echo "$l";; esac; done
