#!/usr/bin/env bash
# id: STOBE-C47-corpse-namesake
# covers: STOBE 47: an action target given by a name that a nearby corpse shares -> the living NPC is chosen
#         (Stobe 526D69F1+: a dead candidate scores 1 unless the serial was asked for)
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: Stobe 526D69F1+, StobeServer 2b2b52d+ (NEG_TEST_INJECT, only to make Malzin's ATTACK certain), harness on
# setup: two neutral Drifters both renamed "Dorn Vale": one 8 m from Malzin, killed (the corpse, nearer = would win on
#        distance), one alive 25 m away.
# switch: NEG_TEST_INJECT for MATE: action Attack, target "Dorn Vale".
# verify: stobe.log `HOOK_MSG_PROC: ATTACK target resolved arg='Dorn Vale' target_serial=N` with N = the living one's
#   serial (mod 2^32), not the corpse's.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NAME="Dorn Vale"
log "47: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-auto teleport ${MATE} ${PLAYER} dist 4 >/dev/null
stobe-say speed 1 >/dev/null
o1=$(stobe-auto spawn "Hungry Bandit" Drifters near ${MATE} dist 8 count 1); dead=$(echo "$o1" | grep -oE '#[0-9]+/[0-9]+' | head -1)
o2=$(stobe-auto spawn "Hungry Bandit" Drifters near ${MATE} dist 25 count 1); live=$(echo "$o2" | grep -oE '#[0-9]+/[0-9]+' | head -1)
[ -n "$dead" ] && [ -n "$live" ] || { verdict 47 "SETUP FAIL spawn: $o1 / $o2"; exit 1; }
stobe-auto setname "$dead" "$NAME" >/dev/null; stobe-auto setname "$live" "$NAME" >/dev/null
stobe-auto kill "$dead" >/dev/null
sleep 3
stobe-auto where "$dead" | cut -c1-160; stobe-auto where "$live" | cut -c1-160
ds=$(echo "$dead" | sed -E 's/#([0-9]+)\/.*/\1/'); ls_=$(echo "$live" | sed -E 's/#([0-9]+)\/.*/\1/')
inject_on 47 "${MATE}" chat "[{\"action\":\"Attack\",\"target\":\"$NAME\",\"message\":\"On it.\"}]"
mark=$(grep -a -c "" "$L")
talk "${MATE}" "${MATE}, attack $NAME." 15
res=$(tail -n +"$mark" "$L" | grep -a "ATTACK target resolved arg='$NAME'" | tail -1)
stobe-auto ko "$live" 900 >/dev/null 2>&1
stobe-auto speed 0 >/dev/null
n=$(echo "$res" | grep -oE 'target_serial=-?[0-9]+' | cut -d= -f2)
[ -n "$n" ] && [ "$n" -lt 0 ] && n=$((n + 4294967296))
log "resolved: ${res:-none} (living=$ls_ corpse=$ds)"
if [ "$(fired 47)" -lt 1 ]; then verdict 47 "INCONCLUSIVE switch never fired"
elif [ -z "$n" ]; then verdict 47 "INCONCLUSIVE no ATTACK target resolution in stobe.log (server dropped the action?)"
elif [ "$n" = "$ls_" ]; then verdict 47 "PASS the living $NAME ($n) was chosen over the corpse ($ds)"
elif [ "$n" = "$ds" ]; then verdict 47 "FAIL the corpse ($ds) was chosen"
else verdict 47 "FAIL resolved to someone else ($n; living=$ls_ corpse=$ds)"; fi
