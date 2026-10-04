#!/usr/bin/env bash
# id: STOBE-C44-reversed-cats-term
# covers: STOBE 44 (third rule, so far unit-tested only): a Cats term recorded the wrong way round is turned round
#         from the deal on the table ("350 and you go free" style acceptance of HIS offer to pay)
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie", 2 steps: (1) PROPOSE npc GIVE_CATS 350 + player PROMISE
#         "keep quiet about what I saw" (his offer on the table); (2) ACCEPT with the Cats term reversed (by player).
# verify: server `Negotiation term fixed: the deal on the table has her paying (item 44)`; the accepted deal's
#   GIVE_CATS 350 is by npc.
# reliability: high
# m19: step 2 forces action Talk: the model's own GiveCats action let the first item-44 rule (her GiveCats action) fix
#   the term before the table rule ran (outcome right, rule untested).
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "44: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 44 "SETUP FAIL spawn"; exit 1; }
stobe-auto money "$v" 500 >/dev/null
sleep 4; greet "$NPC"
inject_on 44 "$NPC" chat '[{"deal_decision":"PROPOSE","deal_terms":[{"kind":"GIVE_CATS","by":"npc","to":"player","amount":350},{"kind":"PROMISE","by":"player","text":"keep quiet about what I saw"}],"message":"350 cats and you keep quiet about what you saw."},{"deal_decision":"ACCEPT","action":"Talk","amount":0,"deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":350},{"kind":"PROMISE","by":"player","text":"keep quiet about what I saw"}],"message":"Done. Not a word, then."}]'
talk "$NPC" "$NPC, how much would you pay me to keep quiet about what I saw?"
log "offer: $(deal_row "$NPC" | cut -c1-200)"
talk "$NPC" "350 and I keep quiet. Deal."
stobe-auto speed 0 >/dev/null
d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2); terms=$(echo "$d" | cut -d'|' -f5)
fx=$(srv_count "the deal on the table has her paying (item 44)")
other=$(since_srv | grep -a "Negotiation term fixed" | grep -a -c -F "(item 44)"); other=$((other - fx))
npcpays=$(echo "$terms" | grep -c -E '"by": *"npc"[^}]*"kind": *"GIVE_CATS"|"kind": *"GIVE_CATS"[^}]*"by": *"npc"')
log "fixed_lines=$fx status=$st terms=$(echo "$terms" | cut -c1-200)"
cancel_deals "$NPC"; put_away "$v"
if [ "$(fired 44)" -lt 2 ]; then verdict 44 "INCONCLUSIVE switch fired $(fired 44)/2 times"
elif [ "$fx" -ge 1 ] && [ "$npcpays" -ge 1 ] && echo "$st" | grep -q -E "ACCEPTED|AWAITING_PERFORMANCE|COMPLETE|IMPOSSIBLE"; then verdict 44 "PASS reversed term turned round from the table: he pays 350 ($st)"
elif [ "$other" -ge 1 ] && [ "$npcpays" -ge 1 ]; then verdict 44 "INCONCLUSIVE another item-44 rule turned it round first (other_lines=$other status=$st)"
else verdict 44 "FAIL fixed_lines=$fx status=$st npc_pays=$npcpays"; fi
