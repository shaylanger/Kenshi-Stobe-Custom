#!/usr/bin/env bash
# id: STOBE-C30-nonmember-prompt
# covers: STOBE 30: a non-member's prompt never calls the player's squad "squadmate" (bug 38): Shay/Malzin show as
#         "player's squad" in a stranger's nearby-people list
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: server live, harness on. No switch: this row only needs the situation (a stranger talking with the squad near).
# verify: in log/context_sent_to_llm.log, the prompt block(s) for "Varn Oddie" since the start: lines
#   "<PLAYER|MATE> (gender) | ..." exist, none has "| squadmate", at least one has "player's squad".
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"; CTX=/var/www/html/StobeServer/log/context_sent_to_llm.log
log "30: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
stobe-auto teleport ${MATE} ${PLAYER} dist 5 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 30 "SETUP FAIL spawn"; exit 1; }
sleep 4
ctx0=$(grep -a -c "" "$CTX")
talk "$NPC" "Hello $NPC, how are you today? That's my friend ${MATE} over there." 20
stobe-auto speed 0 >/dev/null
# prompt blocks start with  'npc_name' => '<name>',  ; roster lines start with "<name> (female) | ..."
lines=$(tail -n +"$ctx0" "$CTX" | awk -v n="$NPC" -v p="${PLAYER}" -v m="${MATE}" -v q="'" '
  index($0, q "npc_name" q " => " q) { cur=$0; sub(".*" q "npc_name" q " => " q, "", cur); sub(q ".*", "", cur); next }
  cur==n && index($0, " | ") && (index($0, p " ")==1 || index($0, m " ")==1) { print }')
echo "$lines" | head -6 | cut -c1-200
total=$(echo "$lines" | grep -c " | "); sm=$(echo "$lines" | grep -c "| squadmate"); ps=$(echo "$lines" | grep -c "player's squad")
log "roster lines=$total squadmate=$sm player's_squad=$ps"
put_away "$v"
if [ "$total" -eq 0 ]; then verdict 30 "INCONCLUSIVE no nearby-people line for ${PLAYER}/${MATE} in $NPC's prompt"
elif [ "$sm" -eq 0 ] && [ "$ps" -ge 1 ]; then verdict 30 "PASS $NPC's prompt shows the squad as \"player's squad\" ($ps lines), never squadmate"
else verdict 30 "FAIL squadmate lines=$sm player's_squad=$ps"; fi
