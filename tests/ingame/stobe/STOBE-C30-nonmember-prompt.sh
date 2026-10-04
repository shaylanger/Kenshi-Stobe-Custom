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
preflight 30  # shared setup check (Shay 2026-10-04)
NPC="Varn Oddie"; CTX=/var/www/html/StobeServer/log/context_sent_to_llm.log
log "30: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 30 "SETUP FAIL spawn"; exit 1; }
# m22 batch D: his prompt's nearby block held only a shop guard (Malzin was ~17 m off, other side of Shay, and the
# scene snapshot of the just-spawned NPC was stale). Put her next to him; greet first so the real line uses a fresh
# snapshot (all his prompt blocks since ctx0 are checked).
tp=$(stobe-auto teleport ${MATE} "$v" dist 4 2>&1); log "teleport ${MATE} -> $v: $(echo "$tp" | tail -1 | cut -c1-120)"
sleep 4
ctx0=$(grep -a -c "" "$CTX")
greet "$NPC"
talk "$NPC" "How are you today, $NPC? That's my friend ${MATE} right next to you." 20
stobe-auto speed 0 >/dev/null
# prompt blocks start with  'npc_name' => '<name>',  ; roster lines: "- <name> (Female Greenlander): ..." or "## <name> (...)"
# (nearby-people block) or "<name> (female) | ..." (lifelike squad lines); m22: the old parser only knew the last form
lines=$(tail -n +"$ctx0" "$CTX" | awk -v n="$NPC" -v p="${PLAYER}" -v m="${MATE}" -v q="'" '
  index($0, q "npc_name" q " => " q) { cur=$0; sub(".*" q "npc_name" q " => " q, "", cur); sub(q ".*", "", cur); next }
  cur==n { l=$0; sub(/^[[:space:]]*(#+|-)?[[:space:]]*/, "", l); if (index(l, p " (")==1 || index(l, m " (")==1) print l }')
echo "$lines" | head -6 | cut -c1-200
total=$(echo "$lines" | grep -c -E "\): | \| "); sm=$(echo "$lines" | grep -c -i "squadmate"); ps=$(echo "$lines" | grep -c -E "player.{0,2}s squad")
log "roster lines=$total squadmate=$sm player's_squad=$ps"
if [ "$total" -eq 0 ]; then  # diagnosis: who was in his nearby block(s)
  nb=$(tail -n +"$ctx0" "$CTX" | awk -v n="$NPC" -v q="'" '
    index($0, q "npc_name" q " => " q) { cur=$0; sub(".*" q "npc_name" q " => " q, "", cur); sub(q ".*", "", cur); on=0; next }
    cur==n && /^# Nearby Actors/ { on=1; next }
    cur==n && on && /^# / { on=0 }
    cur==n && on && /^- / { l=substr($0, 3); sub(/ \(.*/, "", l); print l }' | sort -u | tr "\n" "," | cut -c1-200)
  log "nearby names in $NPC's prompts: ${nb:-none}"
fi
put_away "$v"
if [ "$total" -eq 0 ]; then verdict 30 "INCONCLUSIVE no nearby-people line for ${PLAYER}/${MATE} in $NPC's prompt"
elif [ "$sm" -eq 0 ] && [ "$ps" -ge 1 ]; then verdict 30 "PASS $NPC's prompt shows the squad as \"player's squad\" ($ps lines), never squadmate"
else verdict 30 "FAIL squadmate lines=$sm player's_squad=$ps"; fi
