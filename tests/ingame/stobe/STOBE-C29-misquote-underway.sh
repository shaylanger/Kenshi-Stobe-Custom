#!/usr/bin/env bash
# id: STOBE-C29-misquote-underway
# covers: STOBE 29: she misquotes an amount in a longer reply about a deal that's underway: only the wrong sentence is
#         dropped, not everything from the first number on (held-back streaming), and nothing is said twice
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie", 2 steps: (1) ACCEPT GIVE_CATS player 100 + PROMISE npc
#         (the deal is then underway, unpaid); (2) NONE with "Sure thing. The road north is quiet tonight. You owe me 700
#         cats for that. Then we're done."
# verify: server log `Negotiation speech amounts differ from recorded terms; rewritten` (not "already spoken") whose line
#   keeps "Then we're done" and "road north" and drops "700"; stobe.log NPC_SAY: "road north" spoken once, "700" never.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "29: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 29 "SETUP FAIL spawn"; exit 1; }
sleep 4; greet "$NPC"
inject_on 29 "$NPC" chat "[{\"deal_decision\":\"ACCEPT\",\"deal_terms\":[{\"kind\":\"GIVE_CATS\",\"by\":\"player\",\"to\":\"npc\",\"amount\":100},{\"kind\":\"PROMISE\",\"by\":\"npc\",\"text\":\"tell you where the nearest bar is\"}],\"message\":\"Deal. Pay up and I'll tell you.\"},{\"deal_decision\":\"NONE\",\"deal_terms\":\"\",\"message\":\"Sure thing. The road north is quiet tonight. You owe me 700 cats for that. Then we're done.\"}]"
talk "$NPC" "$NPC, I'll pay you 100 cats to tell me where the nearest bar is."
d=$(deal_row "$NPC"); log "deal: $(echo "$d" | cut -c1-200)"
echo "$d" | cut -d'|' -f2 | grep -q -E "ACCEPTED|AWAITING_PERFORMANCE" || { cancel_deals "$NPC"; put_away "$v"; verdict 29 "SETUP FAIL deal not underway: $(echo "$d" | cut -d'|' -f2)"; exit 1; }
talk "$NPC" "$NPC, how much do I owe you again?" 22
stobe-auto speed 0 >/dev/null
rw=$(srv_has "Negotiation speech amounts differ from recorded terms; rewritten" | tail -1)
late=$(srv_count "Negotiation speech amounts differ from recorded terms (already spoken)")
said=$(npc_said "$NPC")
road=$(echo "$said" | grep -c -i "road north"); n700=$(echo "$said" | grep -c "700")
log "rewrite: $(echo "$rw" | grep -oE '"line":"[^"]*"' | cut -c1-240)"
log "already_spoken=$late NPC_SAY 'road north' x$road, '700' x$n700"
echo "$said" | tail -4
cancel_deals "$NPC"; put_away "$v"
line=$(echo "$rw" | grep -oE '"line":"[^"]*"')
if [ "$(fired 29)" -lt 2 ]; then verdict 29 "INCONCLUSIVE switch fired $(fired 29)/2 times"
elif [ -n "$line" ] && echo "$line" | grep -q "Then we" && echo "$line" | grep -q "road north" && ! echo "$line" | grep -q 700 \
     && [ "$road" -le 1 ] && [ "$n700" -eq 0 ]; then verdict 29 "PASS only the 700 sentence dropped; nothing repeated"
else verdict 29 "FAIL rewrite_line=${line:-none} already_spoken=$late road_spoken=$road 700_spoken=$n700"; fi
