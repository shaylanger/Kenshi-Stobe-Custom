#!/usr/bin/env bash
# fp-swing-hits-all.sh: KenshiFP setting swing_hits_all (F10 "Swing hits all", default OFF; Shay 2026-10-10): a manual
# FP melee swing hits every valid character in the native swing area (squad mates and neutrals too), not only the target.
# Patch pending-fixes/kfp-swing-hits-all.py (hook on CombatClass::attackImpactCheck, kfp_combat_swingall.inc).
# Run in WSL with Kenshi in the world on kah-fpxbow (Malzin = squad melee fighter, Skaera = hostile Hungry Bandit,
# Shay = squad mate used as the ally in the arc; a Tech Hunters Hungry Bandit is spawned as the neutral).
# Rows (COMBAT_TEST_PLAN.md):
#   SWA-OFF  ini swing_hits_all=0: N clicks with target, ally and neutral pinned inside the swing arc -> the target loses
#            flesh, the ally loses none (neutral hits are vanilla, reported only: SWA-NATIVE); widened stays 0
#   SWA-ON   ini swing_hits_all=1: clicks until each of the three has lost flesh (max N) -> all three hit; widened >= 1,
#            zone_targets > 1 while swinging; the neutral's reaction is whatever the game does (logged, not judged)
# Evidence: flesh per character (`hp`) before/after each swing, `fp_melee swing_all` counters, `fp_melee state`
# zone_targets / swings. Game state only, no recording:
# dryrun: norec
# Usage: fp-swing-hits-all.sh [fighter] [target] [ally] [outdir]. Env: KDIR, INI, NCLICK (default 8).
# Ends with one `RESULT <row> PASS|FAIL <evidence>` per row (setup failures: `RESULT <row> FAIL setup: <reason>`).
FI=${1:-Malzin}; TG=${2:-Skaera}; AL=${3:-Shay}; OUT=${4:-/tmp/fp-swing-hits-all}
KDIR=${KDIR:-/mnt/d/Steam/steamapps/common/Kenshi}; INI=${INI:-$KDIR/mods/KenshiFP/KenshiFP.ini}; NCLICK=${NCLICK:-8}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" </dev/null 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
# shared take preflight (pf_melee_arm / pf_awake / pf_pin: non-exiting, reason in PF_WHY); its calls go to this log too
. "$(dirname "$0")/take-preflight.sh"; PF_A() { A "$@"; }
fld() { grep -o "\b$1=[^ ]*" | tail -1 | cut -d= -f2; }
ms() { A fp_melee state | fld "$1"; }
sw() { A fp_melee swing_all | fld "$1"; }
inp() { A fp_combat input "$1" "$2" 0 >/dev/null; }
flesh() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | awk '{s+=$1}END{printf "%.1f", s}'; }
pos() { A where "$1" | grep -o 'pos=[^ ]*' | cut -d= -f2; }
lost() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(b<a-0.5)}'; }
RESULTS=(); INI_BAK=""; NE=""; WEP=""
row() { RESULTS+=("RESULT $1 $2 $3"); echo "RESULT $1 $2 $3" >> "$LOG"; }
finish() { for r in "${RESULTS[@]}"; do case "$r" in *FAIL*) echo "$r log=$LOG";; *) echo "$r";; esac; done; }
# a setup failure fails every row not yet judged, each with its own RESULT line (no retry)
setup_fail() { local r; for r in SWA-OFF SWA-ON; do printf '%s\n' "${RESULTS[@]}" | grep -q "RESULT $r " || row "$r" FAIL "setup: $1"; done; finish; exit 1; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_melee passive off >/dev/null; A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
  local c; for c in "$TG" "$AL" ${NE:+"$NE"}; do A pin "$c" off >/dev/null; done
  [ -n "$WEP" ] && A unequip "$FI" "$WEP" >/dev/null
  A protect "$FI" off >/dev/null; A protect "$AL" off >/dev/null
  [ -n "$INI_BAK" ] && [ -f "$INI_BAK" ] && { cat "$INI_BAK" > "$INI"; rm -f "$INI_BAK"; }   # truncating write keeps the hardlink
  # the spawned neutral is left knocked out, never unloaded (4080 b41: unload during a fight crashed the game)
  [ -n "$NE" ] && A ko "$NE" 3600 >/dev/null
  A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT; trap "exit 143" TERM INT HUP   # a killed row (rig-runner kill-step, timeout) still runs cleanup: neutral fp_combat input
# setini <key> <value>: replace/append one ini line in place, then wait for the hot reload (~0.5 s)
setini() { local t; t=$(grep -v -E "^$1=" "$INI"; echo "$1=$2"); printf '%s\n' "$t" > "$INI"; sleep 1.2; }
click() { inp 0 1; sleep 0.15; inp 0 0; }
in_fight() { local s; s=$(A fp_melee state); echo "$s" | grep -q 'active=1' && ! echo "$s" | grep -q 'target_h=#0/'; }
engage() { in_fight && return 0; local who end
  for who in 1 2; do if [ $who = 1 ]; then A attack "$TG" "$FI" >/dev/null; else A attack "$FI" "$TG" >/dev/null; fi; end=$((SECONDS+8))
    while [ $SECONDS -lt $end ]; do in_fight && return 0; sleep 0.5; done; done; return 1; }
# arc: target 12 dm in front of the fighter (pin ... face), ally and neutral 11 dm out at +-35 deg of the
# fighter->target line, all facing the fighter; re-pinned before every click (pin drifts, fp-manual-melee M01).
# pf_pin waits for the put-back to land (fails with off + KO in PF_WHY); victims are woken first (pf_awake)
arc() { pf_pin "$TG" at "$FI" dist 12 face "$FI" || return 1
  local f t; f=$(pos "$FI"); t=$(pos "$TG"); [ -n "$f" ] && [ -n "$t" ] || return 1
  local p; for p in "$AL:35" "$NE:-35"; do local who=${p%:*} deg=${p##*:} xyz
    xyz=$(awk -v f="$f" -v t="$t" -v d="$deg" 'BEGIN{split(f,a,",");split(t,b,",");dx=b[1]-a[1];dz=b[3]-a[3];L=sqrt(dx*dx+dz*dz);if(L<1)L=1
      r=d*3.14159265/180;c=cos(r);s=sin(r);ux=(dx*c-dz*s)/L;uz=(dx*s+dz*c)/L;printf "%.1f %.1f %.1f",a[1]+11*ux,b[2],a[3]+11*uz}')
    pf_pin "$who" at $xyz face "$FI" || return 1; done; }
gap() { awk -v a="$(pos "$FI")" -v b="$(pos "$1")" 'BEGIN{split(a,p,",");split(b,q,",");printf "%.1f", sqrt((p[1]-q[1])^2+(p[3]-q[3])^2)}'; }
# phase <row> <setting>: clicks; per click every victim healed to 100, flesh before/after; HIT_<who> counts
phase() { local rowname=$1 on=$2 i who S0 z zones="" swung=0 n=$NCLICK
  setini swing_hits_all "$on"
  [ -n "${SWA_NATIVE:-}" ] || [ "$(sw setting)" = "$on" ] || { row "$rowname" FAIL "setup: ini swing_hits_all=$on not live ($(A fp_melee swing_all))"; return 1; }
  A fp_melee swing_all reset >/dev/null; HIT_T=0; HIT_A=0; HIT_N=0
  for i in $(seq 1 "$n"); do
    # healed to 100 and woken: a swing can knock a victim out (op-swa4: the neutral KO at click 1, `health` kept the KO,
    # the KO ragdoll ignored the next pin -> "pin refused off=10.2")
    pf_awake "$TG" "$AL" "$NE" || { row "$rowname" FAIL "setup: $PF_WHY at click $i"; return 1; }
    arc || { row "$rowname" FAIL "setup: pin into the swing arc refused at click $i: $PF_WHY"; return 1; }
    engage || { row "$rowname" FAIL "setup: $FI left the fight with $TG at click $i (why=$(ms why))"; return 1; }
    sleep 0.3; local f0t f0a f0n; f0t=$(flesh "$TG"); f0a=$(flesh "$AL"); f0n=$(flesh "$NE"); S0=$(ms swings)
    for _ in $(seq 1 20); do [ "$(ms dead)" = 0 ] && [ "$(ms state)" != 8 ] && break; sleep 0.1; done
    echo "click $i gaps tg=$(gap "$TG") al=$(gap "$AL") ne=$(gap "$NE")" >> "$LOG"
    click; z="-"
    for _ in $(seq 1 30); do [ "$(ms swings)" != "$S0" ] && { swung=$((swung+1)); break; }; sleep 0.05; done
    for _ in $(seq 1 20); do local zt; zt=$(ms zone_targets); [ -n "$zt" ] && [ "$zt" != 0 ] && { z=$zt; break; }; sleep 0.1; done
    zones+="$z "; sleep 2.6
    lost "$f0t" "$(flesh "$TG")" && HIT_T=$((HIT_T+1)); lost "$f0a" "$(flesh "$AL")" && HIT_A=$((HIT_A+1)); lost "$f0n" "$(flesh "$NE")" && HIT_N=$((HIT_N+1))
    [ "$on" = 1 ] && [ $HIT_T -ge 1 ] && [ $HIT_A -ge 1 ] && [ $HIT_N -ge 1 ] && break
  done
  PEV="setting=$on clicks=$i swung=$swung hits target=$HIT_T ally=$HIT_A neutral=$HIT_N zone_targets=[${zones% }] swing_all{$(A fp_melee swing_all | sed 's/^swing_all //')} wep=$WEP"; return 0; }

# ---- preflight (setup checks before any swing; a failure stops the take) ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$FI" "$TG" "$AL"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ -f "$INI" ] || setup_fail "KenshiFP.ini missing ($INI)"
INI_BAK=$(mktemp); cat "$INI" > "$INI_BAK"
[ -n "${SWA_NATIVE:-}" ] || [ "$(sw ready)" = 1 ] || setup_fail "swing_all hooks not ready ($(A fp_melee swing_all | head -1); KenshiFP build without kfp-swing-hits-all?)"
# melee weapon independent of earlier rows (op-comb2: a kah-fpstudio row before left Malzin with a crossbow only)
pf_melee_arm "$FI" || setup_fail "$PF_WHY"; WEP=$PF_WEP
pf_noxbow "$FI" "$TG" "$AL" Axima Malzin Tassilo Shay || setup_fail "$PF_WHY"   # bow-free scene (crash-safety quarantine 2026-10-11 BSOD: no crossbow equipped on anyone, so nothing fires/reloads)
pf_awake "$TG" "$AL" || setup_fail "$PF_WHY (target/ally must stand: wrong save? row needs kah-fpxbow)"
A protect "$FI" on >/dev/null
# every other squad member far away + protected, so only the fighter hits anyone in the arc
for m in $(A chars 3000 "[nameless]" | tr '|' '\n' | sed -n 's/^[0-9]* within [0-9.]*: //; s/^ *//; s/ #.*//p'); do
  case "$m" in "$FI"|"$AL") ;; *) A protect "$m" on >/dev/null; A pin "$m" at "$FI" dist 600 >/dev/null;; esac; done
SP=$(A spawn "Hungry Bandit" "Tech Hunters" near "$FI" dist 40 count 1); NEH=$(grep -oE '#[0-9]+/[0-9]+' <<<"$SP" | head -1)
[ -n "$NEH" ] || setup_fail "neutral spawn failed ($(cut -c1-100 <<<"$SP"))"
NE=$NEH; A relation "$NE" 20 >/dev/null
A where "$NE" | grep -q 'pos=' || setup_fail "spawned neutral $NE not found"
for c in "$TG" "$AL" "$NE"; do A setstat "$c" defence 1 >/dev/null; A setstat "$c" dodge 1 >/dev/null; done
A setstat "$FI" attack 30 >/dev/null
A select "$FI" >/dev/null; A fp_mode on >/dev/null; sleep 1
A fp_control take >/dev/null
A fp_control state | grep -q "control_ids=.*/$(A where "$FI" | grep -o '#[0-9]*' | tr -d '#')" || setup_fail "fp_control did not take $FI"
pf_combat_on || setup_fail "$PF_WHY"
inp 0 0
pf_awake "$NE" || setup_fail "$PF_WHY"
arc || setup_fail "pin target/ally/neutral into the swing arc refused: $PF_WHY"
engage || setup_fail "$FI not in a native fight with $TG (why=$(ms why))"
for _ in $(seq 1 40); do [ "$(ms why)" = ok ] && in_fight && break; sleep 0.5; done
[ "$(ms why)" = ok ] || setup_fail "melee adapter not ok (why=$(ms why))"
PS=$(A where "$FI" | grep -o '#[0-9]*' | head -1 | tr -d '#')
A fp_melee passive "$PS" | grep -q "passive on" || setup_fail "fp_melee passive $PS refused"
echo "SETUP fighter=$FI wep=$WEP target=$TG ally=$AL neutral=$NE ($SP)" >> "$LOG"

# ---- SWA_NATIVE=1 (build WITHOUT kfp-swing-hits-all): native baseline, does vanilla melee hit the neutral/ally in the arc?
#      (op-swa2: SWA-OFF neutral hit 2x with zone_targets=2 natively). PASS = recorded; the hit counts are the evidence.
if [ -n "${SWA_NATIVE:-}" ]; then
  phase SWA-NATIVE 0 && row SWA-NATIVE PASS "native baseline (no swing_all hooks): $PEV"; finish; exit 0; fi
# ---- SWA-OFF: only the target ----
if phase SWA-OFF 0; then
  # neutral hits are vanilla behaviour (SWA-NATIVE op-swanat 2026-10-10: no hooks, neutral hit 3/8): OFF = native = no ally hit, nothing widened
  if [ $HIT_T -ge 1 ] && [ $HIT_A = 0 ] && [ "$(sw widened)" = 0 ]; then row SWA-OFF PASS "$PEV (neutral hits = vanilla)"; else row SWA-OFF FAIL "$PEV"; fi; fi
# ---- SWA-ON: target, ally and neutral ----
if phase SWA-ON 1; then
  echo "SWA-ON neutral after: $(A where "$NE" | cut -c1-160)" >> "$LOG"
  if [ $HIT_T -ge 1 ] && [ $HIT_A -ge 1 ] && [ $HIT_N -ge 1 ] && [ "$(sw widened)" -ge 1 ]; then row SWA-ON PASS "$PEV"; else row SWA-ON FAIL "$PEV"; fi; fi
finish
