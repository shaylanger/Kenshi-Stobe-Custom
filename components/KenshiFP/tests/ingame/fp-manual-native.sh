#!/bin/bash
# fp-manual-native.sh: in-game S02 (COMBAT_TEST_PLAN.md Gate 5): manual combat must not change native combat of the
# characters it does NOT own. Run with Kenshi in the world on kah-fpxbow (Axima = squad crossbow user, Malzin = squad
# melee fighter, Skaera = hostile Hungry Bandit). Production RNG, no diagnostic spread.
# Rows (one `RESULT <row> PASS|FAIL <evidence>` each):
#  S02-RANGED  Axima's native AI shooting (`rangedtest ... attack`, N shots at DIST dm, hold position) with FP/manual combat
#              OFF (baseline) and with FP + manual combat ON while the controlled actor is Malzin: both blocks complete,
#              >= N shots, other_damage=0, the adapter never owns Axima and its actual_shots don't move, game s/shot of the
#              ON block <= 1.5 x baseline + 10 s (no slowdown/suppression of the native shooter).
#  S02-MELEE   FP + manual combat ON controlling Axima: Malzin (uncontrolled) given a native attack order on Skaera hurts
#              her within MELEE_S s; fp_melee never owns Malzin (owned=0) and the adapter stays fault=0.
# Usage: fp-manual-native.sh [shooter] [fighter] [target] [outdir] [shots, default 3] [dist_dm, default 80]
SH=${1:-Axima}; FI=${2:-Malzin}; TG=${3:-Skaera}; OUT=${4:-/tmp/fp-manual-native}; N=${5:-3}; DIST=${6:-80}
MELEE_S=${MELEE_S:-75}
mkdir -p "$OUT"; LOG="$OUT/log.txt"; : > "$LOG"
A() { local r; r=$(stobe-auto "$@" 2>&1); echo "> $* | $r" >> "$LOG"; echo "$r"; }
. "$(dirname "$0")/take-preflight.sh"; PF_A() { A "$@"; }   # pf_combat_on (fp_combat on with repair)
fld() { grep -o "\b$1=[^ ]*" | head -1 | cut -d= -f2; }
cs() { A fp_combat state | fld "$1"; }
parts() { A hp "$1" | grep -o '[0-6]:[-0-9.]*/' | tr -d / | cut -d: -f2 | tr '\n' ' '; }
lost() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x," ");split(b,y," ");s=0;for(i=1;i<=n;i++){d=x[i]-y[i];if(d>0)s+=d};printf "%.1f",s}'; }
id_of() { A where "$1" | grep -o '#[0-9]*' | head -1 | tr -d '#'; }
ROWS="S02-RANGED S02-MELEE"
setup_fail() { local r; for r in $ROWS; do echo "RESULT $r FAIL setup: $1 log=$LOG"; done; exit 1; }
row() { echo "RESULT $1 $2 $3"; echo "RESULT $1 $2 $3" >> "$LOG"; }
FP0=$(A fp_state | fld fp_mode)
cleanup() { A fp_combat input 0 0 0 >/dev/null; A fp_combat off >/dev/null; A fp_combat physical >/dev/null
  A combatmode "$SH" hold off >/dev/null; for c in "$SH" "$FI" "$TG"; do A protect "$c" off >/dev/null; A pin "$c" off >/dev/null; done
  A health "$TG" 100 >/dev/null; A fp_mode "$([ "$FP0" = 1 ] && echo on || echo off)" >/dev/null; }
trap cleanup EXIT; trap "exit 143" TERM INT HUP
take() { A select "$1" >/dev/null; A fp_mode on >/dev/null; sleep 1; A fp_control take >/dev/null
  A fp_control state | grep -q "control_ids=.*/$(id_of "$1")"; }

# ---- setup ----
A status | grep -q phase=world || setup_fail "not in world"
for c in "$SH" "$FI" "$TG"; do A where "$c" | grep -q 'pos=' || setup_fail "$c not found"; done
[ "$(A rangedinfo "$SH" | fld bow)" != none ] || setup_fail "$SH has no ranged weapon"
FB=$(A rangedinfo "$FI" | grep -o 'bow=.* has_ammo' | sed 's/^bow=//; s/ has_ammo$//')
[ -n "$FB" ] && [ "$FB" != none ] && A unequip "$FI" "$FB" >/dev/null   # fighter melee-only
SHID=$(id_of "$SH"); FIID=$(id_of "$FI")
A protect "$SH" on >/dev/null; A protect "$FI" on >/dev/null
A pin "$FI" at "$SH" dist 400 >/dev/null                      # the fighter out of the line of fire for the ranged row
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
A combatmode "$SH" hold on >/dev/null

# ---- S02-RANGED baseline: FP + manual combat off ----
A fp_combat off >/dev/null; A fp_mode off >/dev/null; sleep 1
B0=$(A rangedtest "$SH" "$TG" shots "$N" timeout 300 attack); A health "$TG" 100 >/dev/null
bc=$(echo "$B0" | fld complete); bn=$(echo "$B0" | fld shots); bs=$(echo "$B0" | fld seconds); bo=$(echo "$B0" | fld other_damage)
[ "$bc" = 1 ] && [ "${bo:-1}" = 0 ] || setup_fail "native baseline at ${DIST}dm: complete=$bc shots=$bn other_damage=$bo ($(A rangedinfo "$SH" | grep -o 'in_ranged_combat=[^ ]* rc_state=[^ ]*'))"

# ---- S02-RANGED: FP + manual combat on, controlling the fighter ----
take "$FI" || setup_fail "fp_control did not take $FI ($(A fp_control state | cut -c1-120))"
pf_combat_on "$FI" || setup_fail "$PF_WHY"
A fp_combat input 0 0 0 >/dev/null; sleep 1
en=$(cs enabled); s0=$(cs actual_shots); a0=$(cs actor)
[ "$en" = 1 ] || setup_fail "manual combat not enabled (enabled=$en why=$(cs why))"
A pin "$TG" at "$SH" dist "$DIST" face "$SH" >/dev/null
B1=$(A rangedtest "$SH" "$TG" shots "$N" timeout 300 attack); A health "$TG" 100 >/dev/null
oc=$(echo "$B1" | fld complete); on=$(echo "$B1" | fld shots); os_=$(echo "$B1" | fld seconds); oo=$(echo "$B1" | fld other_damage)
s1=$(cs actual_shots); a1=$(cs actor); f1=$(cs fault); ctl=$(A fp_control state | grep -o 'control_ids=[^ ]*')
slow=$(awk -v b="$bs" -v o="$os_" -v n0="$bn" -v n1="$on" 'BEGIN{if(n0<1||n1<1){print 1;exit}; print ((o/n1) <= 1.5*(b/n0)+10)?0:1}')
ev="base: complete=$bc shots=$bn game_s=$bs other=$bo | on(ctl $FI, $ctl): enabled=$en complete=$oc shots=$on game_s=$os_ other=$oo adapter actor=$a0->$a1 (shooter #$SHID) actual_shots $s0->$s1 fault=$f1 slow=$slow"
ok=1; [ "$oc" = 1 ] && [ "${on:-0}" -ge "$N" ] && [ "${oo:-1}" = 0 ] && [ "$s0" = "$s1" ] && [ "${f1:-1}" = 0 ] && [ "$slow" = 0 ] || ok=0
case "$a0 $a1" in *"$SHID"*) ok=0;; esac
row S02-RANGED "$([ $ok = 1 ] && echo PASS || echo FAIL)" "$ev"

# ---- S02-MELEE: control the shooter, the fighter fights natively ----
A combatmode "$SH" hold off >/dev/null; A pin "$FI" off >/dev/null; A pin "$TG" off >/dev/null
A pin "$TG" at "$FI" dist 20 face "$FI" >/dev/null; A pin "$TG" off >/dev/null
take "$SH" || setup_fail "fp_control did not take $SH back ($(A fp_control state | cut -c1-120))"
pf_combat_on "$SH" || { row S02-MELEE FAIL "setup: $PF_WHY log=$LOG"; exit 0; }
A fp_combat input 0 0 0 >/dev/null
A health "$TG" 100 >/dev/null; A protect "$TG" off >/dev/null; p0=$(parts "$TG")
A attack "$FI" "$TG" >/dev/null
owned=0; hurt=0; t0=$SECONDS
while [ $((SECONDS-t0)) -lt "$MELEE_S" ]; do
  [ "$(A fp_melee state "$FI" | fld owned)" = 1 ] && owned=1
  hurt=$(lost "$p0" "$(parts "$TG")"); awk -v h="$hurt" 'BEGIN{exit !(h>0.5)}' && break; sleep 1; done
tm=$((SECONDS-t0)); A protect "$TG" on >/dev/null; A health "$TG" 100 >/dev/null
f2=$(cs fault); mo=$(A fp_melee state "$FI" | fld owned); ctl=$(A fp_control state | grep -o 'control_ids=[^ ]*')
ev="ctl $SH ($ctl) $FI native attack: $TG flesh_lost=$hurt in ${tm}s (limit $MELEE_S) fp_melee owned=$mo owned_fighter_seen=$owned fault=$f2"
ok=1; awk -v h="$hurt" 'BEGIN{exit !(h>0.5)}' || ok=0; [ "$owned" = 0 ] && [ "${f2:-1}" = 0 ] || ok=0
row S02-MELEE "$([ $ok = 1 ] && echo PASS || echo FAIL)" "$ev"
