#!/usr/bin/env bash
# id: STOBE-C33-impossible-refund
# covers: STOBE 33: Shay pays for something she agreed to but can't do -> the deal fails (IMPOSSIBLE) and the Cats
#         come back (refund directive GIVE_CATS@Shay)
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie": ACCEPT GIVE_CATS player 100 (now) + UNEQUIP_ITEM npc
#         "Moon Crown" after_player (he wears no such thing: the game can't do it).
# verify: Shay pays by voice; the npc term goes IMPOSSIBLE, deal status IMPOSSIBLE; a `refund` directive with
#   GIVE_CATS@<player>@100 is queued and delivered (outcome set); Shay's Cats are back to the amount before paying.
# reliability: high (the refund needs a turn of his: the wrapper talks to him to carry it)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "33: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 33 "SETUP FAIL spawn"; exit 1; }
sleep 4; greet "$NPC"
stobe-say give_cats 300 >/dev/null
inject_on 33 "$NPC" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":100},{"kind":"UNEQUIP_ITEM","by":"npc","item":"Moon Crown","when":"after_player"}],"message":"Deal. Pay me and the crown comes off."}]'
talk "$NPC" "$NPC, I'll pay you 100 cats to take off your Moon Crown."
d=$(deal_row "$NPC"); id=$(echo "$d" | cut -d'|' -f1); log "deal: $(echo "$d" | cut -c1-200)"
echo "$d" | cut -d'|' -f2 | grep -q -E "ACCEPTED|AWAITING_PERFORMANCE" || { cancel_deals "$NPC"; put_away "$v"; verdict 33 "SETUP FAIL deal not accepted"; exit 1; }
m0=$(money_of ${PLAYER})
talk "$NPC" "Here are your 100 cats, $NPC." 15
m1=$(money_of ${PLAYER})
st=""
for i in $(seq 1 8); do
  st=$(PSQL "SELECT status FROM stobe_social_contract WHERE contract_id='$id'")
  [ "$st" = IMPOSSIBLE ] && break
  talk "$NPC" "$NPC, well? Your turn." 15
done
for i in 1 2 3; do  # the refund rides on his next turn
  PSQL "SELECT outcome FROM stobe_negotiation_directive WHERE contract_id='$id' AND kind='refund' ORDER BY id DESC LIMIT 1" | grep -q . && break
  talk "$NPC" "$NPC, so where does that leave us?" 15
done
sleep 8
m2=$(money_of ${PLAYER})
stobe-auto speed 0 >/dev/null
ref=$(PSQL "SELECT payload::text||' consumed='||consumed_unix||' outcome='||outcome FROM stobe_negotiation_directive WHERE contract_id='$id' AND kind='refund' ORDER BY id DESC LIMIT 1")
log "status=$st cats ${PLAYER}: $m0 -> $m1 (paid) -> $m2 refund: $(echo "$ref" | cut -c1-200)"
npc_said "$NPC" | tail -3
cancel_deals "$NPC"; put_away "$v"
paid=$(( ${m0:-0} - ${m1:-0} ))
if [ "$(fired 33)" -lt 1 ]; then verdict 33 "INCONCLUSIVE switch never fired"
elif [ "$paid" -lt 100 ]; then verdict 33 "INCONCLUSIVE the voice payment did not go through ($m0 -> $m1)"
elif [ "$st" = IMPOSSIBLE ] && echo "$ref" | grep -q "GIVE_CATS@${PLAYER}@100" && [ "${m2:-0}" -ge "${m0:-0}" ]; then verdict 33 "PASS deal IMPOSSIBLE, 100 Cats refunded ($m0 -> $m1 -> $m2)"
else verdict 33 "FAIL status=$st refund=${ref:-none} cats $m0 -> $m1 -> $m2"; fi
