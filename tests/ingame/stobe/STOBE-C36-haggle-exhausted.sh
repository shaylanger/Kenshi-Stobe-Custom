#!/usr/bin/env bash
# id: STOBE-C36-haggle-exhausted
# covers: STOBE 36: haggling back and forth more than the round limit (6) -> she ends the talks
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie": 9 COUNTER steps (200, 210, ... Cats + a PROMISE), so
#         every turn is a counter on the same open deal (the model alone accepts by round 2).
# verify: server `Negotiation ended: bargaining rounds exhausted`; the deal CANCELLED with evidence note
#   bargaining_exhausted, within at most 8 player lines.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "36: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 36 "SETUP FAIL spawn"; exit 1; }
sleep 4; greet "$NPC"
steps=""
for i in 0 1 2 3 4 5 6 7 8; do
  a=$((200 + 10 * i))
  steps="$steps{\"deal_decision\":\"COUNTER\",\"deal_terms\":[{\"kind\":\"GIVE_CATS\",\"by\":\"player\",\"to\":\"npc\",\"amount\":$a},{\"kind\":\"PROMISE\",\"by\":\"npc\",\"text\":\"tell you where the nearest bar is\"}],\"message\":\"Make it $a cats.\"},"
done
inject_on 36 "$NPC" chat "[${steps%,}]"
talk "$NPC" "$NPC, I'll pay you 100 cats to tell me where the nearest bar is." 15
turns=1
for i in 1 2 3 4 5 6 7 8; do
  d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2)
  log "turn $turns: ${st:-none} $(echo "$d" | cut -d'|' -f6 | cut -c1-80)"
  [ "$st" = CANCELLED ] && break
  talk "$NPC" "How about $((100 + 10 * i)) cats?" 15; turns=$((turns+1))
done
stobe-auto speed 0 >/dev/null
d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2); ev=$(echo "$d" | cut -d'|' -f6)
ex=$(srv_count "Negotiation ended: bargaining rounds exhausted")
npc_said "$NPC" | tail -2
log "after $turns lines: status=$st exhausted_lines=$ex evidence=$(echo "$ev" | cut -c1-120)"
cancel_deals "$NPC"; put_away "$v"
if [ "$(fired 36)" -lt 1 ]; then verdict 36 "INCONCLUSIVE switch never fired"
elif [ "$st" = CANCELLED ] && [ "$ex" -ge 1 ] && echo "$ev" | grep -q bargaining_exhausted; then verdict 36 "PASS talks ended after $turns player lines (bargaining_exhausted)"
else verdict 36 "FAIL status=$st exhausted_lines=$ex after $turns lines"; fi
