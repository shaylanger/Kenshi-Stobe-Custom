#!/usr/bin/env bash
# fp-manual-parity.sh: Gate 3 pilot (R14 torso accuracy parity, R15 fire-rate/damage parity) of the manual ranged
# adapter (COMBAT_TEST_PLAN.md). Same shooter, target, distance, skill and weapon: N native shots (`rangedtest`, the AI
# fires on its own, target healed after each hit) vs N manual shots aimed at the chest. Hits = flesh lost on a body
# part (> 0.5, blood ignored); damage = flesh lost per hit (manual: hp before/after; native: rangedtest mean_hit_damage).
# Validity: both blocks >= 3N/4 resolved shots, native complete=1 and other_damage=0 (no melee/stray damage).
# Tolerances: R14 PASS = valid and the two Wilson 95% hit-rate intervals overlap. R15 PASS = valid, manual never
# fires faster than native (manual s/shot >= 0.9 x native game s/shot; manual runs at speed 1 so real s = game s)
# and manual dmg/hit within 25% of native mean_hit_damage (same weapon, both aimed at the torso).
# Batch 6: at 30 dm the AI shooter fought in melee (other_damage=34, 2 bolts in 600 s): DIST default 80 dm, the
# shooter holds position, and a native warm-up probe (2 shots, complete with other_damage=0) runs before either block.
# Run with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Skaera = hostile Hungry Bandit).
# Usage: fp-manual-parity.sh [shooter] [target] [blocker] [outdir] [shots] [dist_dm]. Ends with `RESULT <row> PASS|FAIL <evidence>`.
N=${5:-20}; DIST=${6:-80}
# manual ranged adapter (COMBAT_TEST_PLAN.md). Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow
# user, Skaera = hostile Hungry Bandit, Shay = squad mate used as the intervening body).
# Input: `fp_combat input <aim> <fire> <reload>`; aim: `fp_camera look <yaw> <pitch>` from the FP eye (fp_camera state
# camera_y) to a point at a given height over the target's feet (game units = dm). Evidence: the victim's flesh per body
# part (`hp`: 0 head 1 chest 2 stomach 3 left_arm 4 right_arm 5 left_leg 6 right_leg) before/after each manual shot,
# the shooter's crossbows base skill, the adapter's actual_shots.
SH=${1:-Axima}; TG=${2:-Skaera}; BL=${3:-Shay}; OUT=${4:-/tmp/fp-manual-parity}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
parts() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | tr '\n' ' '; }   # flesh of parts 0..6
# hurt <before> <after>: indices of parts that lost > 0.5 flesh, e.g. "1(-12.3)"
hurt() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s="";for(i=1;i<=n;i++){d=y[i]-x[i];if(d<-0.5)s=s (s?",":"") (i-1) "(" sprintf("%.1f",d) ")"};print s}'; }
skill() { A rangedinfo "$SH" | grep -o 'crossbows=[0-9.]*' | cut -d= -f2; }       # 4 decimals
RESULTS=()
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
setup_fail() { echo "RESULT SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode)
HOLD0=$(A combatmode "$SH" | fld hold)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            [ -n "$HOLD0" ] && A combatmode "$SH" hold "$([ "$HOLD0" = 1 ] && echo on || echo off)" >/dev/null
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

wilson() { awk -v k="$1" -v n="$2" 'BEGIN{if(n==0){print "n/a";exit};p=k/n;z=1.96;d=1+z*z/n;c=(p+z*z/(2*n))/d;h=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/d;printf "%.2f[%.2f,%.2f]",p,c-h,c+h}'; }
dmg() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s=0;for(i=1;i<=n;i++)s+=x[i]-y[i];printf "%.1f",s}'; }
# ci_overlap "<p>[lo,hi]" "<p>[lo,hi]": 1 when two Wilson intervals overlap
ci_overlap() { awk -v a="$1" -v b="$2" 'BEGIN{if(a=="n/a"||b=="n/a"){print 0;exit};sub(/.*\[/,"",a);sub(/\]/,"",a);sub(/.*\[/,"",b);sub(/\]/,"",b)
  split(a,x,",");split(b,y,",");lo=x[1]>y[1]?x[1]:y[1];hi=x[2]<y[2]?x[2]:y[2];print (lo<=hi)?1:0}'; }
# aim_at <npc> <height dm>: point the FP camera at the npc's feet + height
aim_at() { local s t e; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; AIM_NPC=$1; AIM_H=$2; sleep 0.4; }
# shot <victim...>: one manual shot; prints "<shot 0|1> <flesh lost by victim1> <hurt on victim1>|<hurt on victim2>..."
# (the loss is read before `protect on`, which heals the victim: batch 6 measured dmg_per_hit=0.0 after it)
shot() { local s0 b=() v r=""; s0=$(cs actual_shots)
  for v in "$@"; do A protect "$v" off >/dev/null; A health "$v" 100 >/dev/null; done; sleep 0.3
  for v in "$@"; do b+=("$(parts "$v")"); done
  inp 1 0 0; waitfor 8 shot_ready 1 || { echo "0 not_ready"; return; }
  aim_at "$AIM_NPC" "$AIM_H"; waitfor 3 shot_ready 1                  # the shooter can step while aiming: re-aim
  A fp_combat aim >> "$OUT/aims.txt"
  inp 1 1 0; local end=$((SECONDS+3)) ok=0
  while [ $SECONDS -lt $end ]; do [ "$(cs actual_shots)" != "$s0" ] && { ok=1; break; }; sleep 0.1; done
  inp 1 0 0; sleep 2.5
  local i=0 a d1=; for v in "$@"; do a=$(parts "$v"); r+="$(hurt "${b[$i]}" "$a")|"; [ -z "$d1" ] && d1=$(dmg "${b[$i]}" "$a")
    i=$((i+1)); A protect "$v" on >/dev/null; done
  inp 1 0 0; waitfor 6 reloading 0 >/dev/null; echo "$ok ${d1:-0} ${r%|}"; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$TG" "$BL"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
A protect "$SH" on >/dev/null; A protect "$TG" on >/dev/null; A protect "$BL" on >/dev/null   # off only around each shot
A pin "$BL" at "$SH" dist 400 >/dev/null
# every other squad member far away + protected (a mate meleeing the target or standing in the line of fire spoils it)
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH"|"$BL") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
A combatmode "$SH" hold on >/dev/null      # the native shooter must not walk in on the target
# native readiness probe (FP not owning the shooter yet): 2 AI shots must resolve with no melee/stray damage
A fp_mode off >/dev/null; sleep 1; A protect "$TG" off >/dev/null
P=$(A rangedtest "$SH" "$TG" shots 2 timeout 120 attack); A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null
[ "$(echo "$P" | fld complete)" = 1 ] && [ "$(echo "$P" | fld other_damage)" = 0 ] ||
  setup_fail "native probe at ${DIST}dm: complete=$(echo "$P" | fld complete) shots=$(echo "$P" | fld shots) other_damage=$(echo "$P" | fld other_damage) mean_dist=$(echo "$P" | fld mean_dist) ($(A rangedinfo "$SH" | grep -o 'should_use_ranged=[^ ]* in_ranged_combat=[^ ]* rc_state=[^ ]*'))"
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
A select "$SH" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$SH" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $SH"
A fp_combat autoreload 1 >/dev/null
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "adapter never armed (enabled=$(cs enabled) fault=$(cs fault) why=$(cs why))"

SKL="dist=${DIST}dm crossbows=$(A stat "$SH" crossbows | grep -o 'effective=[0-9.]*' | cut -d= -f2) perception=$(A stat "$SH" perception | grep -o 'effective=[0-9.]*' | cut -d= -f2)"

# ---- manual block first (adapter owns the shooter), chest aim, N shots ----
inp 1 0 0; waitfor 15 shot_ready 1 || setup_fail "manual: never shot-ready (why=$(cs why))"
aim_at "$TG" 12.5; mh=0; md=0; mn=0; t0=$SECONDS
for _ in $(seq 1 "$N"); do
  read -r ok d h <<<"$(shot "$TG")"; [ "$ok" = 1 ] || continue; mn=$((mn+1))
  [ -n "$h" ] && { mh=$((mh+1)); md=$(awk -v s="$md" -v d="$d" 'BEGIN{print s+d}'); }
done
MT=$((SECONDS-t0)); A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_mode off >/dev/null; A protect "$TG" off >/dev/null; sleep 2   # native = no FP control
A fp_control state | grep -q 'direct=0' || setup_fail "native: FP still owns $SH after fp_mode off ($(A fp_control state))"
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null

# ---- native block: the AI shoots on its own (rangedtest: hits watched per shot, target healed) ----
NR=$(A rangedtest "$SH" "$TG" shots "$N" timeout 600 attack)
nn=$(echo "$NR" | fld shots); nh=$(echo "$NR" | fld hits); ns=$(echo "$NR" | fld seconds); nc=$(echo "$NR" | fld complete)
no=$(echo "$NR" | fld other_damage); nd=$(echo "$NR" | fld mean_hit_damage)
mdh=$(awk -v d="$md" -v h="$mh" 'BEGIN{printf "%.1f", h?d/h:0}')
VALID=0; [ "$mn" -ge $((N*3/4)) ] && [ "$nc" = 1 ] && [ "${nn:-0}" -ge $((N*3/4)) ] && [ "$no" = 0 ] && VALID=1
MW=$(wilson "$mh" "$mn"); NW=$(wilson "$nh" "$nn")
MR="manual n=$mn hits=$mh rate=$MW real_s=$MT dmg_per_hit=$mdh"
NRs="native n=$nn hits=$nh rate=$NW game_s=$ns complete=$nc other_damage=$no dmg_per_hit=${nd:-n/a}"
# Wilson intervals overlap: max(lo) <= min(hi)
OVL=$(ci_overlap "$MW" "$NW")
ev="$SKL | $MR | $NRs | valid=$VALID ci_overlap=$OVL"
if [ "$VALID" = 1 ] && [ "$OVL" = 1 ]; then row R14 PASS "$ev"; else row R14 FAIL "$ev"; fi
# fire rate: manual s/shot >= 0.9 x native s/shot; damage: |manual - native| <= 25% of native, both > 0
SPS=$(awk -v mt="$MT" -v mn="$mn" -v ns="$ns" -v nn="${nn:-0}" 'BEGIN{if(!mn||!nn){print "n/a/n/a";exit};printf "%.1f/%.1f", mt/mn, ns/nn}')
NF=$(awk -v mt="$MT" -v mn="$mn" -v ns="$ns" -v nn="${nn:-0}" 'BEGIN{print (mn&&nn&&mt/mn>=0.9*ns/nn)?1:0}')
DMG=$(awk -v m="$mdh" -v n="${nd:-0}" 'BEGIN{print (m>0&&n>0&&m-n<=0.25*n&&n-m<=0.25*n)?1:0}')
ev="$SKL | s_per_shot manual/native=$SPS not_faster=$NF | dmg_per_hit manual=$mdh native=${nd:-n/a} within25=$DMG | valid=$VALID"
if [ "$VALID" = 1 ] && [ "$NF" = 1 ] && [ "$DMG" = 1 ]; then row R15 PASS "$ev"; else row R15 FAIL "$ev"; fi

printf '%s\n' "${RESULTS[@]}" | while read -r l; do case "$l" in *FAIL*) echo "$l log=$LOG";; *) echo "$l";; esac; done
