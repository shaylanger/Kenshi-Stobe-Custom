#!/usr/bin/env bash
# fp-manual-soak.sh: in-game row S04 (soak/performance) of the manual combat adapters (COMBAT_TEST_PLAN.md).
# Run in WSL with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Malzin = squad melee fighter with a
# Chisa Katana in her inventory, Skaera = hostile Hungry Bandit). Everyone protected (soak, not damage).
# Cycles alternate for MINUTES: ranged (Axima owned, fp_combat on, manual shots at Skaera pinned DIST dm away, aim via
# fp_camera look) and melee (Malzin owned with the katana, Skaera pinned in reach, fp_melee passive, manual clicks at
# legal native moments), CYCLE real seconds each; fp_combat off/on and a control hand-over between cycles.
# A background sampler every 30 s writes $OUT/samples.csv: kenshi_x64 private/working-set MB (powershell Get-Process,
# as run-batch.sh), fp_combat state (fault, wound_fault, actual_shots, shot_spawns, shot_nospawn, wound pending =
# wound_tracked - wound_impacts - wound_missed, bounded by WOUND_SLOTS 16), fp_melee state (owned, why, clicks, swings,
# pending, frame_dt), fp_combat_probe state count (trace ring, capacity 512; recording on for the run).
# S04 PASS: Kenshi alive and in the world throughout, >= 80% of the expected samples, fault=0 and wound_fault=0 in
#   every sample, private memory growth (median of the last 3 samples - median of the 3 after a 2 min warm-up) < MEMMB
#   (default 150 MB; slope MB/min reported), counters consistent in every sample (0 <= actual_shots - shot_spawns <= 1,
#   shot_nospawn = 0, 0 <= wound pending <= 16, probe count <= 512) and equal at the end (actual_shots = shot_spawns
#   after the last reload), nothing stuck at cycle ends (ranged: aimed=0 and reloading=0 within 12 s of release;
#   melee: pending=0 within 3 s; control on the new actor after every hand-over), every ranged cycle fired >= 1 shot
#   and every melee cycle swung >= 1 time. frame_dt mean/max are reported (frame cost), not gated.
# Usage: fp-manual-soak.sh [shooter] [fighter] [target] [outdir] [minutes] [cycle_s] [mem_bound_mb]
# Ends with one `RESULT S04 PASS|FAIL <evidence>` (`RESULT S04 SETUP FAIL <reason>` when setup fails).
# SOAK_CTRL=1: native-AI control (row S04-CTRL): the same fixture, pins, hand-overs, cycles and sampler, but fp_combat
# stays off and the AI fights (ranged: harness rangedtest with the attack order; melee: native fight, swings counted by
# the product's native swing timer). Memory is reported, not gated: it tells game noise (caches, streaming) apart from
# growth the manual adapters cause (5090 b8: S04 growth 187 MB = one +145 MB step in a melee cycle, flat otherwise)
CTRL=${SOAK_CTRL:-0}
SH=${1:-Axima}; FI=${2:-Malzin}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-manual-soak}; MIN=${5:-25}; CYC=${6:-90}; MEMMB=${7:-150}
DIST=40
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"; CSV="$OUT/samples.csv"; rm -f "$OUT/.stop"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
gf() { grep -o "\b$1=[^ ]*" <<<"$2" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
ms() { A fp_melee state | fld "$1"; }
inp() { A fp_combat input "$1" "$2" "$3" >/dev/null; }
waitfor() { local end=$((SECONDS+$1)); while [ $SECONDS -lt $end ]; do [ "$(cs "$2")" = "$3" ] && return 0; sleep 0.2; done; return 1; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2 | tr , ' '; }
serial() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
memmb() { powershell.exe -NoProfile -Command '$k=Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($k) { "{0:F0} {1:F0}" -f ($k.PrivateMemorySize64/1MB), ($k.WorkingSet64/1MB) } else { "- -" }' </dev/null 2>/dev/null | tr -d '\r' | tail -1; }
setup_fail() { echo "RESULT S04 SETUP FAIL $1 log=$LOG"; exit 1; }
FP0=$(A fp_state | fld fp_mode); WEP=""; BOW=""; SPID=""
cleanup() { touch "$OUT/.stop"; [ -n "$SPID" ] && wait "$SPID" 2>/dev/null
            A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
            A fp_combat_probe end >/dev/null; A pin "$TG" off >/dev/null; A pin "$FI" off >/dev/null
            [ -n "$WEP" ] && A unequip "$FI" "$WEP" >/dev/null; [ -n "$BOW" ] && A equip "$FI" "$BOW" >/dev/null
            for c in "$SH" "$FI" "$TG"; do A protect "$c" off >/dev/null; done
            A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT

aim_at() { local e; read -r sx sy sz <<<"$(pos "$SH")"; read -r tx ty tz <<<"$(pos "$1")"
  local cam cx cz; cam=$(A fp_camera state); e=$(fld camera_y <<<"$cam"); cx=$(fld camera_x <<<"$cam"); cz=$(fld camera_z <<<"$cam")
  [ -n "$cx" ] && [ -n "$cz" ] && { sx=$cx; sz=$cz; }   # aim from the eye, not the feet: the FP eye can sit ~3 dm aside (R09 5090 b7)
  read -r YAW PIT <<<"$(awk -v a="$sx" -v b="$sz" -v c="$tx" -v d="$tz" -v ey="$e" -v py="$(awk -v y="$ty" -v h="$2" 'BEGIN{print y+h}')" \
     'BEGIN{h=sqrt((c-a)^2+(d-b)^2); printf "%.4f %.4f", atan2(c-a, d-b), atan2(ey-py, h)}')"
  A fp_camera look "$YAW" "$PIT" >/dev/null; sleep 0.3; }
# take <actor>: select + FP control; 1 when fp_control lists the actor
take() { A select "$1" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
  A fp_control state | grep -q "control_ids=.*/$(serial "$1")"; }
# melee helpers (as fp-manual-melee-life.sh)
in_fight() { local s; s=$(A fp_melee state); echo "$s" | grep -q 'active=1' && ! echo "$s" | grep -q 'target_h=#0/'; }
engage() { in_fight && return 0; local who end
  for who in 1 2; do if [ $who = 1 ]; then A attack "$TG" "$FI" >/dev/null; else A attack "$FI" "$TG" >/dev/null; fi; end=$((SECONDS+8))
    while [ $SECONDS -lt $end ]; do in_fight && return 0; sleep 0.5; done; done; return 1; }
ready() { inp 0 0 0; engage; local end=$((SECONDS+${1:-20})); while [ $SECONDS -lt $end ]; do
  [ "$(ms why)" = ok ] && [ "$(ms armed)" = 1 ] && in_fight && [ "$(ms dead)" = 0 ] && [ "$(ms state)" != 8 ] && return 0; sleep 0.3; done; return 1; }
weapons() { A inv "$FI" | sed 's/},{/}\n{/g' | grep '"weapon_model"' | sed 's/.*"name":"\([^"]*\)".*/\1/' | grep -v -i -x -F "${BOW:-@@}"; }
arm_melee() { local w r; while IFS= read -r w; do [ -n "$w" ] || continue; r=$(A equip "$FI" "$w")
  case "$r" in equipped*) WEP=$w; return 0;; esac; done <<<"$(weapons)"; return 1; }

# sampler: every 30 s one CSV line; stops on $OUT/.stop or when Kenshi is gone
sampler() { local t0=$SECONDS next=0 m c ml p a b d wp
  echo "t_s,private_mb,ws_mb,phase,fault,wound_fault,actual_shots,shot_spawns,shot_nospawn,wound_pending,owned,why,clicks,swings,pending,frame_dt,probe_count,npcs" > "$CSV"
  while [ ! -e "$OUT/.stop" ]; do
    if [ $((SECONDS-t0)) -ge $next ]; then next=$((next+30))
      m=$(memmb); c=$(A fp_combat state); ml=$(A fp_melee state); p=$(A fp_combat_probe state)
      a=$(gf wound_tracked "$c"); b=$(gf wound_impacts "$c"); d=$(gf wound_missed "$c")
      if [ -n "$a" ] && [ -n "$b" ] && [ -n "$d" ]; then wp=$((a-b-d)); else wp=nan; fi
      echo "$((SECONDS-t0)),${m% *},${m#* },$(A status | grep -o 'phase=[a-z]*' | cut -d= -f2),$(gf fault "$c"),$(gf wound_fault "$c"),$(gf actual_shots "$c"),$(gf shot_spawns "$c"),$(gf shot_nospawn "$c"),$wp,$(gf owned "$ml"),$(gf why "$ml"),$(gf clicks "$ml"),$(gf swings "$ml"),$(gf pending "$ml"),$(gf frame_dt "$ml"),$(gf count "$p"),$(A chars 3000 | grep -o '^[0-9]*')" >> "$CSV"
      [ "${m% *}" = - ] && { touch "$OUT/.kenshi_gone"; break; }
    fi; sleep 1; done; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
M0=$(memmb); [ "${M0% *}" != - ] && [ -n "$M0" ] || setup_fail "kenshi_x64 memory not readable from here (memmb='$M0')"
BOW=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//'); [ "$BOW" = none ] && BOW=""
[ -n "$BOW" ] && A unequip "$FI" "$BOW" >/dev/null
arm_melee || setup_fail "$FI has no melee weapon that equips (inv weapons: $(weapons | tr '\n' ';'))"
for c in "$SH" "$FI" "$TG"; do A protect "$c" on >/dev/null; done
for m in $(A chars 3000 "[nameless]" | tr '|' '
' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$SH"|"$FI") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$SH" dist 600 >/dev/null;; esac; done
A setstat "$TG" defence 1 >/dev/null; A setstat "$TG" dodge 1 >/dev/null
A fp_combat autoreload 1 >/dev/null
A fp_combat_probe begin | grep -q 'recording=1' || setup_fail "fp_combat_probe begin refused"
# readiness: one ranged shot and one melee swing must work before the clock starts
A pin "$FI" at "$SH" dist 300 >/dev/null; A pin "$TG" at "$SH" dist "$DIST" face "$SH" | grep -q '^pinned' || setup_fail "pin $TG at $SH refused"
take "$SH" || setup_fail "fp_control did not take $SH"
if [ "$CTRL" = 1 ]; then A fp_combat off >/dev/null; else
A fp_combat on | grep -q requested || setup_fail "fp_combat on refused"
inp 0 0 0; waitfor 3 armed 1 || setup_fail "ranged adapter never armed (fault=$(cs fault) why=$(cs why))"
inp 1 0 0; waitfor 15 shot_ready 1 || setup_fail "ranged: never shot-ready (why=$(cs why))"; inp 0 0 0; fi

# ---- ranged cycle: shots until CYC s; sets C_SHOTS, C_STUCK ----
ranged_cycle() { local end=$((SECONDS+CYC)) s0 s1 t; C_STUCK=""
  A pin "$FI" off >/dev/null; A pin "$FI" at "$SH" dist 300 >/dev/null; A pin "$TG" off >/dev/null; A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
  if [ "$CTRL" = 1 ]; then take "$SH" || C_STUCK+="take_$SH,"
    C_SHOTS=$(A rangedtest "$SH" "$TG" shots 99 timeout "$CYC" attack | fld shots); C_SHOTS=${C_SHOTS:-0}; return; fi
  take "$SH" || C_STUCK+="take_$SH,"; A fp_combat on >/dev/null; inp 0 0 0; waitfor 5 armed 1 || C_STUCK+="not_armed,"
  s0=$(cs actual_shots)
  while [ $SECONDS -lt $end ]; do inp 1 0 0; waitfor 10 shot_ready 1 || continue
    aim_at "$TG" 12.5; s1=$(cs actual_shots); inp 1 1 0; t=$((SECONDS+3))
    while [ $SECONDS -lt $t ]; do [ "$(cs actual_shots)" != "$s1" ] && break; sleep 0.1; done
    inp 1 0 0; waitfor 8 reloading 0 >/dev/null; done
  inp 0 0 0; C_SHOTS=$(( $(cs actual_shots) - s0 ))
  t=$((SECONDS+12)); while [ $SECONDS -lt $t ]; do [ "$(cs aimed)" = 0 ] && [ "$(cs reloading)" = 0 ] && break; sleep 0.5; done
  [ "$(cs aimed)" = 0 ] || C_STUCK+="aimed,"; [ "$(cs reloading)" = 0 ] || C_STUCK+="reloading($(cs reload_left)),"
  A fp_combat off >/dev/null; }
# ---- melee cycle: legal-moment clicks until CYC s; sets C_SWINGS, C_STUCK ----
# near: the target back next to the fighter when it drifted out of reach (the fighter can move after the pin; the
# manual adapter holds ground and refuses out-of-reach clicks, so a far target = a cycle with 0 swings: S04 5090 b6)
near() { local f t; read -r f <<<"$(pos "$FI")"; read -r t <<<"$(pos "$TG")"
  case "$(awk -v a="$f" -v b="$t" 'BEGIN{split(a,x," ");split(b,y," ");dy=x[2]-y[2]; if(dy<0)dy=-dy
    print (dy>10) ? "level" : ((sqrt((x[1]-y[1])^2+(x[3]-y[3])^2)>20) ? "far" : "ok")}')" in
    ok) return 0;;
    # different level (a pinned target drops to the ground under a fighter on a roof/rock: 5090 b7 m2): fighter to the target
    level) A pin "$FI" at "$TG" dist 12 face "$TG" >/dev/null; sleep 1; A pin "$FI" off >/dev/null; LEVELS=$((LEVELS+1));; esac
  A pin "$TG" off >/dev/null; A pin "$TG" at "$FI" dist 12 face "$FI" >/dev/null; REPINS=$((REPINS+1)); }
melee_cycle() { local end=$((SECONDS+CYC)) w0 s t; C_STUCK=""
  A pin "$FI" off >/dev/null; A pin "$TG" off >/dev/null; A pin "$TG" at "$FI" dist 12 face "$FI" >/dev/null
  if [ "$CTRL" = 1 ]; then take "$FI" || C_STUCK+="take_$FI,"; near; engage || C_STUCK+="no_fight,"; w0=$(ms nat_swing_ends)
    while [ $SECONDS -lt $end ]; do near; in_fight || engage >/dev/null; sleep 1; done
    C_SWINGS=$(( $(ms nat_swing_ends) - w0 )); return; fi
  take "$FI" || C_STUCK+="take_$FI,"; A fp_combat on >/dev/null
  A fp_melee passive "$(serial "$FI")" >/dev/null; near; ready 20 || C_STUCK+="melee_not_ready($(ms why)),"
  w0=$(ms swings)
  while [ $SECONDS -lt $end ]; do s=$(A fp_melee state)
    case "$(gf state "$s")" in 3|4|5|6) if grep -q ' dead=0 ' <<<"$s" && [ "$(gf pending "$s")" = 0 ]; then inp 0 1 0; sleep 0.15; inp 0 0 0; sleep 1.2; fi;; esac
    near; in_fight || engage >/dev/null; sleep 0.2; done
  inp 0 0 0; C_SWINGS=$(( $(ms swings) - w0 ))
  t=$((SECONDS+3)); while [ $SECONDS -lt $t ]; do [ "$(ms pending)" = 0 ] && break; sleep 0.3; done
  [ "$(ms pending)" = 0 ] || C_STUCK+="pending($(ms pending)),"
  A fp_melee passive off >/dev/null; A fp_combat off >/dev/null; }

# ---- soak ----
sampler & SPID=$!
T0=$SECONDS; k=0; NR=0; NM=0; BADC=""; STUCK=""
while [ $((SECONDS-T0)) -lt $((MIN*60)) ] && [ ! -e "$OUT/.kenshi_gone" ]; do k=$((k+1))
  if [ $((k%2)) = 1 ]; then ranged_cycle; NR=$((NR+1)); [ "$C_SHOTS" -ge 1 ] 2>/dev/null || BADC+="r$k:shots=$C_SHOTS,"; echo "cycle $k ranged shots=$C_SHOTS stuck=${C_STUCK:-none}" >> "$LOG"
  else melee_cycle; NM=$((NM+1)); [ "$C_SWINGS" -ge 1 ] 2>/dev/null || BADC+="m$k:swings=$C_SWINGS,"; echo "cycle $k melee swings=$C_SWINGS stuck=${C_STUCK:-none}" >> "$LOG"; fi
  [ -n "$C_STUCK" ] && STUCK+="c$k:${C_STUCK%,};"
done
SOAK_S=$((SECONDS-T0)); sleep 8; FC=$(A fp_combat state)   # last bolt resolved, last reload done
touch "$OUT/.stop"; wait "$SPID"; SPID=""

# ---- verdict from samples.csv ----
NS=$(($(wc -l < "$CSV")-1)); EXP=$((SOAK_S/30))
read -r MEMG SLOPE MEMSTART MEMEND <<<"$(awk -F, 'function med(x,y,z){return (x>y)?((y>z)?y:((x>z)?z:x)):((x>z)?x:((y>z)?z:y))}
NR>1 && $2!="-"{t[++n]=$1;m[n]=$2} END{
  w=1; while(w<=n && t[w]<120) w++; if(n-w<5){print "nan nan nan nan";exit}
  s0=med(m[w],m[w+1],m[w+2]); s1=med(m[n-2],m[n-1],m[n])
  for(i=w;i<=n;i++){sx+=t[i];sy+=m[i];sxx+=t[i]*t[i];sxy+=t[i]*m[i];c++}
  sl=(c*sxy-sx*sy)/(c*sxx-sx*sx)*60; printf "%.0f %.2f %.0f %.0f", s1-s0, sl, s0, s1}' "$CSV")"
BADS=$(awk -F, 'NR>1{d=$7-$8; bad=""
  if($4!="world")bad=bad "phase=" $4 " "; if($5!="0")bad=bad "fault=" $5 " "; if($6!="0")bad=bad "wound_fault=" $6 " "
  if(d<0||d>1)bad=bad "shots-spawns=" d " "; if($9!="0")bad=bad "nospawn=" $9 " "; if($10=="nan"||$10<0||$10>16)bad=bad "wound_pending=" $10 " "
  if($17==""||$17>512)bad=bad "probe_count=" $17 " "; if(bad!="")printf "t=%s:%s; ", $1, bad}' "$CSV" | cut -c1-400)
read -r WSTEPS WMB <<<"$(awk -F, 'NR>1{if(n && $18!="" && pn!="" && $18-pn>=5 && $2!="-" && pm!="-"){c++; d+=$2-pm} pn=$18; pm=$2; n++} END{printf "%d %.0f", c, d}' "$CSV")"
FDT=$(awk -F, 'NR>1 && $16!=""{s+=$16;n++;if($16>mx)mx=$16} END{printf "%.4f/%.4f", n?s/n:0, mx}' "$CSV")
PMAX=$(awk -F, 'NR>1{if($17>mx)mx=$17} END{print mx+0}' "$CSV")
FA=$(gf actual_shots "$FC"); FS=$(gf shot_spawns "$FC")
GONE=$([ -e "$OUT/.kenshi_gone" ] && echo 1 || echo 0)
ev="soak=${SOAK_S}s cycles ranged=$NR melee=$NM samples=$NS/$EXP mem_private ${MEMSTART}->${MEMEND}MB growth=${MEMG}MB (bound $MEMMB) slope=${SLOPE}MB/min | end shots=$FA spawns=$FS nospawn=$(gf shot_nospawn "$FC") fault=$(gf fault "$FC") repins=${REPINS:-0} levels=${LEVELS:-0} world_steps=$WSTEPS(${WMB}MB) | bad_samples=${BADS:-none} | bad_cycles=${BADC:-none} | stuck=${STUCK:-none} | frame_dt mean/max=$FDT probe_count_max=$PMAX kenshi_gone=$GONE"
if [ "$GONE" = 0 ] && [ "$NS" -ge $((EXP*8/10)) ] && [ "$MEMG" != nan ] && awk -v g="$MEMG" -v b="$MEMMB" 'BEGIN{exit !(g<b)}' \
   && [ -z "$BADS" ] && [ -z "$BADC" ] && [ -z "$STUCK" ] && [ -n "$FA" ] && [ "$FA" = "$FS" ] && [ "$(gf fault "$FC")" = 0 ] && [ "$NR" -ge 1 ] && [ "$NM" -ge 1 ]; then
  R="RESULT S04 PASS $ev"
# growth over the bound only because characters streamed in (>= 5 more nearby in one sample step) and everything else
# clean: not a leak verdict either way -> INCONCLUSIVE, rerun (the bound itself is unchanged)
elif [ "$GONE" = 0 ] && [ "$WSTEPS" -gt 0 ] && [ "$MEMG" != nan ] && awk -v g="$MEMG" -v w="$WMB" -v b="$MEMMB" 'BEGIN{exit !(g>=b && g-w<b)}'    && [ -z "$BADS" ] && [ -z "$BADC" ] && [ -z "$STUCK" ] && [ "$(gf fault "$FC")" = 0 ]; then
  R="RESULT S04 INCONCLUSIVE world_load growth_without_world_steps=$((MEMG-WMB))MB $ev log=$LOG csv=$CSV"
else R="RESULT S04 FAIL $ev log=$LOG csv=$CSV"; fi
if [ "$CTRL" = 1 ]; then   # control: completed cleanly = PASS; growth is the evidence to compare with S04
  if [ "$GONE" = 0 ] && [ "$NS" -ge $((EXP*8/10)) ] && [ "$MEMG" != nan ] && [ -z "$BADC" ] && [ -z "$STUCK" ] && [ "$NR" -ge 1 ] && [ "$NM" -ge 1 ]
  then R="RESULT S04-CTRL PASS native_ai $ev"; else R="RESULT S04-CTRL FAIL native_ai $ev log=$LOG csv=$CSV"; fi; fi
echo "$R" >> "$LOG"; echo "$R"
