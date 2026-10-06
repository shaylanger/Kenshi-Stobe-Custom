#!/usr/bin/env bash
# fp-manual-limbs.sh: in-game row R16 (limb-target tactical impact) of the manual ranged adapter (COMBAT_TEST_PLAN.md).
# Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Skaera = hostile Hungry Bandit).
# Production RNG (the fixture's own crossbows/perception, no low-spread diagnostic: R14-R16 rule), same distance for
# both aims. Aim heights from the victim's own bones (`fp_combat aim` reply aim=head,chest,legs).
# Phase 1 (distribution): N shots aimed at the legs, N at the torso; the target is healed before every shot (`hp` per
#   part before/after: 0 head 1 chest 2 stomach 3 left_arm 4 right_arm 5 left_leg 6 right_leg).
# Phase 2 (incapacitation): no healing; shots aimed at the legs until the target is KO (`hp` ... KO) or INCAP shots;
#   then healed, the same with torso aims. Per shot: leg flesh, `runspeed` movement_speed (the game's getMovementSpeed).
# R16 PASS is the mechanical part: >= MINHITS leg-aimed hits, leg-aimed hits land on a leg (5/6) at a rate >= LEGMIN
#   (default 0.6) and above the torso-aimed block's leg rate, and the leg incap phase really lowered leg flesh.
#   Movement-speed drop and knockdown are evidence when present (not gated: a pinned target needn't slow).
#   The balance numbers (miss rates with Wilson 95% CIs, part distribution, shots/seconds to leg-disabled and KO per
#   aim) are printed in the RESULT line and `$OUT/balance.txt`; they are observations, not pass/fail.
# Usage: fp-manual-limbs.sh [shooter] [target] [outdir] [shots_per_aim] [dist_dm] [incap_cap] [legmin]
# Ends with one `RESULT R16 PASS|FAIL <evidence>` (`RESULT R16 SETUP FAIL <reason>` when setup fails).
SH=${1:-Axima}; TG=${2:-Skaera}; OUT=${3:-/tmp/fp-manual-limbs}; N=${4:-15}; DIST=${5:-50}; INCAP=${6:-12}; LEGMIN=${7:-0.6}
MINHITS=5
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
parts() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | tr '\n' ' '; }
hurt() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s="";for(i=1;i<=n;i++){d=y[i]-x[i];if(d<-0.5)s=s (s?",":"") (i-1) "(" sprintf("%.1f",d) ")"};print s}'; }
legs() { awk -v a="$1" 'BEGIN{split(a,x," ");printf "%.1f", x[6]+x[7]}'; }
minleg() { awk -v a="$1" 'BEGIN{split(a,x," ");printf "%.1f", (x[6]<x[7])?x[6]:x[7]}'; }
isko() { A hp "$1" | grep -q ' KO '; }
speed() { A runspeed "$1" | fld movement_speed; }
wilson() { awk -v k="$1" -v n="$2" 'BEGIN{if(n==0){print "n/a";exit};p=k/n;z=1.96;d=1+z*z/n;c=(p+z*z/(2*n))/d;h=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/d;printf "%.2f[%.2f,%.2f]",p,c-h,c+h}'; }
setup_fail() { echo "RESULT R16 SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null; A pin "$TG" off >/dev/null; A protect "$TG" off >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

aim_at() { local e; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; AIM_NPC=$1; AIM_H=$2; sleep 0.4; }
# ensure_fp: FP mode/direct control/valid camera/armed adapter before every shot; a lost FP mode (5090 fp-5090-5: an
# unexplained `[input] FP mode toggled -> OFF` left camera_y=0 and every aim refused) is re-taken and counted (FPLOST)
gf() { grep -o "\b$1=[^ ]*" <<<"$2" | head -1 | cut -d= -f2; }
FPLOST=0; NOFP=0
ensure_fp() { local c; c=$(A fp_camera state)
  [ "$(gf direct "$c")" = 1 ] && [ "$(gf world_valid "$c")" = 1 ] && [ "$(cs actor)" != 0 ] && return 0
  FPLOST=$((FPLOST+1)); echo "FP LOST #$FPLOST: direct=$(gf direct "$c") world_valid=$(gf world_valid "$c"); re-taking $SH" >> "$LOG"
  A select "$SH" >/dev/null; A fp_mode on >/dev/null
  for _ in $(seq 1 10); do sleep 0.5; A fp_state | grep -q 'fp_mode=1' && break; done
  A fp_control take >/dev/null; A fp_combat on >/dev/null; inp 0 0 0; waitfor 5 armed 1 || return 1
  local end=$((SECONDS+5)); while [ $SECONDS -lt $end ]; do c=$(A fp_camera state)
    [ "$(gf direct "$c")" = 1 ] && [ "$(gf world_valid "$c")" = 1 ] && return 0; sleep 0.3; done; return 1; }
# shot [heal]: one manual shot at AIM_*; heal=1 heals + unprotects the target first and protects it after (phase 1),
# heal=0 leaves it unprotected and wounded (phase 2). Sets S_OK, S_B (parts before), S_A (parts after), S_H (hurt).
shot() { local s0; S_OK=0; S_A=$(parts "$TG"); S_B=$S_A; S_H=""
  ensure_fp || { NOFP=$((NOFP+1)); return; }
  s0=$(cs actual_shots)
  if [ "$1" = 1 ]; then A protect "$TG" off >/dev/null; A health "$TG" 100 >/dev/null; sleep 0.3; fi
  S_B=$(parts "$TG")
  inp 1 0 0; if ! waitfor 8 shot_ready 1; then S_A=$S_B; S_H=""; [ "$1" = 1 ] && A protect "$TG" on >/dev/null; return; fi
  aim_at "$AIM_NPC" "$AIM_H"; waitfor 3 shot_ready 1
  inp 1 1 0; local end=$((SECONDS+3))
  while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && { S_OK=1; break; }; sleep 0.1; done
  inp 1 0 0; sleep 2.5
  S_A=$(parts "$TG"); S_H=$(hurt "$S_B" "$S_A"); [ "$1" = 1 ] && A protect "$TG" on >/dev/null
  inp 1 0 0; waitfor 6 reloading 0 >/dev/null; }

# ---- setup (as fp-manual-hits.sh) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
A where "$TG" | grep -q 'DEAD' && setup_fail "$TG is dead"
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
A pin "$TG" at "$SH" dist "$DIST" face "$SH" | grep -q '^pinned' || setup_fail "pin $TG at ${DIST} dm refused"
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (enabled=$(cs enabled) fault=$(cs fault) why=$(cs why))"
BR=""; for _ in 1 2 3; do aim_at "$TG" 12; BR=$(A fp_combat aim); grep -q '\baim=[-0-9.]*,' <<<"$BR" && break; BR=""; sleep 0.5; done
read -r AH AC AL <<<"$(grep -o '\baim=[-0-9.,]*' <<<"$BR" | cut -d= -f2 | tr , ' ')"
[ -n "$AL" ] || setup_fail "no bone reply from fp_combat aim at $TG ($(tail -1 "$LOG" | cut -c1-160))"
SKL="dist=${DIST}dm crossbows=$(A stat "$SH" crossbows | grep -o 'effective=[0-9.]*' | cut -d= -f2) perception=$(A stat "$SH" perception | grep -o 'effective=[0-9.]*' | cut -d= -f2) aim_h=$AH/$AC/$AL"

# ---- phase 1: distribution, legs block then torso block ----
declare -A HITS FIRED LEGH DIST_P
for blk in legs torso; do ht=$AL; [ $blk = torso ] && ht=$AC; aim_at "$TG" "$ht"
  HITS[$blk]=0; FIRED[$blk]=0; LEGH[$blk]=0; DIST_P[$blk]="0 0 0 0 0 0 0"
  for _ in $(seq 1 "$N"); do shot 1; [ "$S_OK" = 1 ] || continue; FIRED[$blk]=$((FIRED[$blk]+1))
    echo "P1 $blk hurt=${S_H:-miss}" >> "$LOG"
    [ -n "$S_H" ] || continue; HITS[$blk]=$((HITS[$blk]+1))
    [[ ",$S_H" == *",5("* || ",$S_H" == *",6("* ]] && LEGH[$blk]=$((LEGH[$blk]+1))
    # part histogram: the part that lost most flesh this shot
    p=$(tr ',' '\n' <<<"$S_H" | sed 's/[()]/ /g' | sort -k2 -g | head -1 | cut -d' ' -f1)
    DIST_P[$blk]=$(awk -v d="${DIST_P[$blk]}" -v p="$p" 'BEGIN{n=split(d,x," ");x[p+1]++;s="";for(i=1;i<=n;i++)s=s (i>1?" ":"") x[i];print s}')
  done; done

# ---- phase 2: incapacitation per aim (no healing between shots) ----
declare -A TLEG TKO SKO SLEG LEG0 LEG1 SP
for blk in legs torso; do ht=$AL; [ $blk = torso ] && ht=$AC
  A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null; sleep 0.5; A protect "$TG" off >/dev/null; A health "$TG" 100 >/dev/null
  aim_at "$TG" "$ht"; p0=$(parts "$TG"); LEG0[$blk]=$(legs "$p0"); sp="$(speed "$TG")"; t0=$SECONDS; n=0; SLEG[$blk]=-; SKO[$blk]=-; TLEG[$blk]=-; TKO[$blk]=-
  tries=0; while [ $n -lt "$INCAP" ] && [ $tries -lt $((INCAP*2)) ]; do tries=$((tries+1)); shot 0; [ "$S_OK" = 1 ] || { isko "$TG" && break; continue; }; n=$((n+1))
    echo "P2 $blk shot=$n hurt=${S_H:-miss}" >> "$LOG"
    if isko "$TG"; then SKO[$blk]=$n; TKO[$blk]=$((SECONDS-t0)); break; fi
    sp+=",$(speed "$TG")"
    [ "${SLEG[$blk]}" = - ] && awk -v m="$(minleg "$S_A")" 'BEGIN{exit !(m<=0)}' && { SLEG[$blk]=$n; TLEG[$blk]=$((SECONDS-t0)); }
  done
  LEG1[$blk]=$(legs "$(parts "$TG")"); SP[$blk]=$sp
  A where "$TG" | grep -q DEAD && { echo "P2 $blk target died" >> "$LOG"; DEAD=$blk; break; }
  A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null; sleep 2
done
A protect "$TG" on >/dev/null

# ---- verdict ----
lr() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b?a/b:0}'; }
LRL=$(lr "${LEGH[legs]}" "${HITS[legs]}"); LRT=$(lr "${LEGH[torso]}" "${HITS[torso]}")
MISSL=$(wilson $(( FIRED[legs]-HITS[legs] )) "${FIRED[legs]}"); MISST=$(wilson $(( FIRED[torso]-HITS[torso] )) "${FIRED[torso]}")
BAL="miss legs=$MISSL torso=$MISST | parts(0..6) legs_aim=[${DIST_P[legs]}] torso_aim=[${DIST_P[torso]}] | incap legs: leg_disabled@${SLEG[legs]}shots/${TLEG[legs]}s ko@${SKO[legs]}shots/${TKO[legs]}s speed=${SP[legs]} | torso: leg_disabled@${SLEG[torso]:--} ko@${SKO[torso]:--}shots/${TKO[torso]:--}s speed=${SP[torso]:--}${DEAD:+ | target died in $DEAD phase}"
echo "$SKL | $BAL" > "$OUT/balance.txt"
MECH="fp_lost=$FPLOST fp_not_retaken=$NOFP leg_aim hits=${HITS[legs]}/${FIRED[legs]} on_leg=${LEGH[legs]} rate=$LRL torso_aim hits=${HITS[torso]}/${FIRED[torso]} on_leg=${LEGH[torso]} rate=$LRT legmin=$LEGMIN leg_flesh incap ${LEG0[legs]}->${LEG1[legs]} fault=$(cs fault)"
ev="$SKL | $MECH | $BAL"
if [ "$NOFP" -gt 0 ]; then R="RESULT R16 SETUP FAIL FP control lost and not re-taken on $NOFP shots | $ev log=$LOG"
elif [ "${HITS[legs]}" -ge "$MINHITS" ] && awk -v l="$LRL" -v t="$LRT" -v m="$LEGMIN" -v a="${LEG0[legs]}" -v b="${LEG1[legs]}" \
     'BEGIN{exit !(l>=m && l>t && b<a-0.5)}' && [ "$(cs fault)" = 0 ]; then R="RESULT R16 PASS $ev"
else R="RESULT R16 FAIL $ev log=$LOG"; fi
echo "$R" >> "$LOG"; echo "$R"
