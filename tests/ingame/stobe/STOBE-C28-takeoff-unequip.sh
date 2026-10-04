#!/usr/bin/env bash
# id: STOBE-C28-takeoff-unequip
# covers: STOBE 28: "take off X" during a deal is recorded as UNEQUIP_ITEM (she keeps it), not a hand-over
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie": ACCEPT with GIVE_CATS player 50 + GIVE_ITEM npc <the item
#         he wears> (the model's wrong kind for a take-off request).
# verify: server log `NEG_TEST_INJECT fired (test switch, row 28)` + `take-off request recorded as UNEQUIP_ITEM`; the deal's
#   terms hold UNEQUIP_ITEM and no GIVE_ITEM; after Shay pays, the item is not in Shay's inventory.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "28: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 28 "SETUP FAIL spawn"; exit 1; }
sleep 4
item=$(first_worn "$v")
if [ -z "$item" ]; then
  stobe-auto give "$v" "Iron Hat" 1 >/dev/null; stobe-auto equip "$v" "Iron Hat" >/dev/null; item=$(first_worn "$v")
fi
[ -n "$item" ] || { put_away "$v"; verdict 28 "SETUP FAIL he wears nothing to take off"; exit 1; }
log "$NPC ($v) wears: $item"
greet "$NPC"
stobe-say give_cats 200 >/dev/null
inject_on 28 "$NPC" chat "[{\"deal_decision\":\"ACCEPT\",\"deal_terms\":[{\"kind\":\"GIVE_CATS\",\"by\":\"player\",\"to\":\"npc\",\"amount\":50},{\"kind\":\"GIVE_ITEM\",\"by\":\"npc\",\"to\":\"player\",\"item\":\"$item\"}],\"message\":\"Fine. Fifty and it comes off.\"}]"
have0=$(stobe-auto inv ${PLAYER} | grep -c -F "\"name\":\"$item\"")
talk "$NPC" "$NPC, take off your $item and I'll pay you 50 cats."
d=$(deal_row "$NPC"); terms=$(echo "$d" | cut -d'|' -f5)
log "deal: $(echo "$d" | cut -c1-260)"
talk "$NPC" "Here are your 50 cats, $NPC." 20
have1=$(stobe-auto inv ${PLAYER} | grep -c -F "\"name\":\"$item\"")
worn=$(equipped_items "$v" | grep -c -F "$item")
stobe-auto speed 0 >/dev/null
f=$(fired 28); fix=$(srv_count "take-off request recorded as UNEQUIP_ITEM")
log "injected=$f fix_lines=$fix item in ${PLAYER}'s inv $have0 -> $have1, still worn by him: $worn"
cancel_deals "$NPC"; put_away "$v"
if [ "$f" -lt 1 ]; then verdict 28 "INCONCLUSIVE switch never fired"
elif [ "$fix" -ge 1 ] && echo "$terms" | grep -q UNEQUIP_ITEM && ! echo "$terms" | grep -q GIVE_ITEM && [ "$have1" -le "$have0" ]; then
  verdict 28 "PASS recorded as UNEQUIP_ITEM (no GIVE_ITEM), $item not handed to ${PLAYER}"
else verdict 28 "FAIL fix_lines=$fix terms=$(echo "$terms" | cut -c1-160) ${PLAYER}_has $have0->$have1"; fi
