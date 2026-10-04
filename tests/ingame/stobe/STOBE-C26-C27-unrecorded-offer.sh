#!/usr/bin/env bash
# id: STOBE-C26-C27-unrecorded-offer
# covers: STOBE 26 (she agrees in words, nothing recorded -> reminded, records it next turn) and
#         27 (a COUNTER with no terms, log invalid_terms_json -> reminded, restates it with terms)
# usage: STOBE-C26-C27-unrecorded-offer.sh 26|27
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh (`bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh`)
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie", one step: 26 = deal_decision NONE + "Fine, you've got a
#         deal."; 27 = deal_decision COUNTER with empty deal_terms. Step 2 (after the reminder) is injected too (ACCEPT / COUNTER with terms).
# verify: server log `NEG_TEST_INJECT fired (test switch, row N)`, then
#   26: `NPC agreed in words but recorded no deal`; 27: `Negotiation rejected by deterministic validation` with invalid_terms_json;
#   the next prompt holds the reminder ("It was not recorded as a deal" / "gave no deal_terms"); a deal row for Varn
#   (ACCEPTED/AWAITING/COMPLETE for 26, COUNTERED/ACCEPTED/... for 27) appears after the reminder turn.
#   PASS = all; INCONCLUSIVE = reminder sent but the model still recorded nothing; FAIL = guard line or reminder missing.
# reliability: high for the guard, medium for the follow-up (model choice after the reminder)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
row="${1:-26}"; NPC="Varn Oddie"
CTX=/var/www/html/StobeServer/log/context_sent_to_llm.log
log "$row: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict "$row" "SETUP FAIL spawn"; exit 1; }
sleep 4; greet "$NPC"
# m22 batch D: the model's own reply after the reminder backed off ("Let's get the terms straight first"), which tests
# the model, not our code. Step 2 injects the reply the reminder asks for, so the row checks: guard -> reminder in the
# next prompt -> a recorded reply after the reminder becomes a deal row.
T50='{"kind":"GIVE_CATS","by":"player","to":"npc","amount":50},{"kind":"PROMISE","by":"npc","text":"tell {player} where the nearest bar is"}'
if [ "$row" = 27 ]; then
  inject_on 27 "$NPC" chat "[{\"deal_decision\":\"COUNTER\",\"deal_terms\":\"\",\"message\":\"Eighty cats, not fifty.\"},{\"deal_decision\":\"COUNTER\",\"deal_terms\":[${T50/50\}/80\}}],\"message\":\"Eighty cats, then I tell you.\"}]"
  guard="invalid_terms_json"; reminder="gave no deal_terms"
else
  inject_on 26 "$NPC" chat "[{\"deal_decision\":\"NONE\",\"deal_terms\":\"\",\"message\":\"Fine, you've got a deal.\"},{\"deal_decision\":\"ACCEPT\",\"deal_terms\":[${T50}],\"message\":\"Deal: fifty cats and I tell you.\"}]"
  guard="NPC agreed in words but recorded no deal"; reminder="It was not recorded as a deal"
fi
ctx0=$(grep -a -c "" "$CTX")
talk "$NPC" "$NPC, I'll pay you 50 cats to tell me where the nearest bar is."
f=$(fired "$row"); g=$(srv_count "$guard")
log "injected=$f guard_lines=$g"
deal_row "$NPC"
talk "$NPC" "$NPC, so what do you say?" 25
f2=$(fired "$row"); rem=$(tail -n +"$ctx0" "$CTX" | grep -a -c -F "$reminder")
d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2)
log "step2_injected=$((f2-f)) reminder_in_prompt=$rem deal=$(echo "$d" | cut -c1-200)"
npc_said "$NPC" | tail -3
stobe-auto speed 0 >/dev/null
cancel_deals "$NPC"; put_away "$v"
if [ "$f" -lt 1 ]; then verdict "$row" "INCONCLUSIVE switch never fired (no negotiation turn?)"
elif [ "$g" -lt 1 ] || [ "$rem" -lt 1 ]; then verdict "$row" "FAIL guard_lines=$g reminder_in_prompt=$rem"
elif [ -n "$st" ]; then verdict "$row" "PASS guard fired, reminder sent, deal recorded next turn ($st)"
elif [ "$f2" -le "$f" ]; then verdict "$row" "INCONCLUSIVE guard + reminder ok, step 2 (reply after the reminder) never fired"
else verdict "$row" "FAIL guard + reminder ok, but the injected reply after the reminder recorded no deal"; fi
