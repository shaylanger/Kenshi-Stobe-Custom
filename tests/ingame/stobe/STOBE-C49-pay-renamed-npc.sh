#!/usr/bin/env bash
# id: STOBE-C49-pay-renamed-npc
# covers: STOBE 49: Shay pays an NPC who was named after the deal ("Dust Bandit" -> "Weth [Dust Bandit]"): the payment
#         is VERIFIED for that NPC's deal (the record names the new name; it counts because the new name's stored serial
#         is the deal's serial)
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on (`protect`)
# switch: NEG_TEST_INJECT for the raider (template name kept): ACCEPT GIVE_CATS player 200 + STOP_ATTACK npc.
# verify: the deal's npc_serial = his serial; after `setname "Weth [<old>]"` and "Here are your 200 cats": stobe.log
#   `ACTION_EXEC: GIVE_CATS actor=<player> recipient=Weth [<old>] amount=200`, the player's GIVE_CATS term VERIFIED,
#   deal COMPLETE (or still AWAITING only for his truce window). Part 2 of the row (a same-named other serial does not
#   count) stays unit-tested (tests/negotiation_engine_regression.php item 49).
# reliability: medium-high (pay window: 60 s of game time after the deal)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
preflight 49  # shared setup check (Shay 2026-10-04)
log "49: setup"
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 600
heal_start ${PLAYER}
stobe-say give_cats 500 >/dev/null
r=$(KEEP_TEMPLATE_NAME=1 spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict 49 "SETUP FAIL no raider"; exit 1; }
old=$(name_of "$r"); serial=$(echo "$r" | sed -E 's/#([0-9]+)\/.*/\1/')
case "$old" in *"["*) put_away "$r"; verdict 49 "SETUP FAIL raider already named: $old"; exit 1;; esac
engage "$r" || log "warning: no combat_start seen"
# m22 (C49 m22): Stobe's batch identity auto-naming renamed him "Zeth 2 [Dust Bandit Bowman]" right as the wrapper
# spoke the template name. Let the name settle (two equal reads 3 s apart) and talk to whatever he is called now;
# the injection is keyed to the template name, which also matches "<auto name> [<template>]".
tmpl="$old"; prev=""; cur=""
for i in $(seq 1 8); do sleep 3; cur=$(name_of "$r"); [ -n "$cur" ] && [ "$cur" = "$prev" ] && break; prev="$cur"; done
[ -n "$cur" ] && old="$cur"; [ "$old" != "$tmpl" ] && log "raider auto-named '$tmpl' -> '$old'"
inject_on 49 "$tmpl" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":200},{"kind":"STOP_ATTACK","by":"npc","target":"player"}],"message":"Fine. 200 cats and I stop."}]'
say_to "$r" "$old" "Stop fighting! I'll pay you 200 cats right now."
d=$(wait_accept "$old" 60)
[ -n "$d" ] || { put_away "$r"; verdict 49 "INCONCLUSIVE no accepted deal: $(deal_line "$old")"; exit 2; }
id=$(echo "$d" | awk '{print $1}')
dserial=$(PSQL "SELECT npc_serial FROM stobe_social_contract WHERE contract_id='$id'")
new="Weth [$tmpl]"
stobe-auto setname "$r" "$new" >/dev/null
log "deal $id (npc_serial=$dserial, his serial=$serial); renamed '$old' -> '$new'"
m0=$(money_of ${PLAYER})
say_to "$r" "$new" "Here are your 200 cats."
for i in $(seq 1 12); do deal_block "$id" | grep -E "player +GIVE_CATS" | grep -q VERIFIED && break; sleep 5; done
stobe-auto speed 0 >/dev/null
m1=$(money_of ${PLAYER})
exec_line=$(since_stobe | grep -a "ACTION_EXEC: GIVE_CATS actor=${PLAYER}" | grep -a -F "recipient=$new" | tail -1)
deal_block "$id"
ver=$(deal_block "$id" | grep -E "player +GIVE_CATS" | grep -c VERIFIED)
st=$(PSQL "SELECT status FROM stobe_social_contract WHERE contract_id='$id'")
log "cats ${PLAYER} $m0 -> $m1; exec: ${exec_line:-none}; player GIVE_CATS verified=$ver status=$st"
heal_stop; put_away "$r"
if [ "$(fired 49)" -lt 1 ]; then verdict 49 "INCONCLUSIVE switch never fired"
elif [ -z "$exec_line" ]; then verdict 49 "INCONCLUSIVE no GIVE_CATS to '$new' executed (voice payment?)"
elif [ "$ver" -ge 1 ] && [ "${dserial:-0}" = "$serial" ]; then verdict 49 "PASS payment to the renamed NPC verified for his deal ($st, serial $serial)"
else verdict 49 "FAIL verified=$ver status=$st deal_serial=$dserial his_serial=$serial"; fi
