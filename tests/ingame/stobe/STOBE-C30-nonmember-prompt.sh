#!/usr/bin/env bash
# id: STOBE-C30-nonmember-prompt
# covers: STOBE 30: a non-member's prompt never calls the player's squad "squadmate" (bug 38): Shay/Malzin show as
#         "player's squad" in a stranger's nearby-people list
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: server live, harness on. No switch: this row only needs the situation (a stranger talking with the squad near).
# verify: in log/context_sent_to_llm.log, the prompt block(s) for "Varn Oddie" since the start: lines
#   "- <PLAYER|MATE> (Gender Race): player's squad | Faction: ... | ..." (m22: nearby-people block; also the lifelike
#   "<name> (gender) | ..." form) exist, none says "squadmate", at least one says "player's squad" (server C30 fix).
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
# prompt blocks start with  'npc_name' => '<name>',  ; roster lines: "- <name> (Female Greenlander): ..." or "## <name> (...)"
# (nearby-people block) or "<name> (female) | ..." (lifelike squad lines); m22: the old parser only knew the last form
lines=$(tail -n +"$ctx0" "$CTX" | awk -v n="$NPC" -v p="${PLAYER}" -v m="${MATE}" -v q="'" '
  index($0, q "npc_name" q " => " q) { cur=$0; sub(".*" q "npc_name" q " => " q, "", cur); sub(q ".*", "", cur); next }
  cur==n { l=$0; sub(/^[[:space:]]*(#+|-)?[[:space:]]*/, "", l); if (index(l, p " (")==1 || index(l, m " (")==1) print l }')
echo "$lines" | head -6 | cut -c1-200
total=$(echo "$lines" | grep -c -E "\): | \| "); sm=$(echo "$lines" | grep -c -i "squadmate"); ps=$(echo "$lines" | grep -c -E "player.{0,2}s squad")
log "roster lines=$total squadmate=$sm player's_squad=$ps"
put_away "$v"
if [ "$total" -eq 0 ]; then verdict 30 "INCONCLUSIVE no nearby-people line for ${PLAYER}/${MATE} in $NPC's prompt"
elif [ "$sm" -eq 0 ] && [ "$ps" -ge 1 ]; then verdict 30 "PASS $NPC's prompt shows the squad as \"player's squad\" ($ps lines), never squadmate"
else verdict 30 "FAIL squadmate lines=$sm player's_squad=$ps"; fi
