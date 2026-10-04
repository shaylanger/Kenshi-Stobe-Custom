#!/usr/bin/env bash
# id: STOBE-C35-weapon-not-for-sale
# covers: STOBE 35: she agrees to sell her equipped weapon without enough trust -> refused ("Not my <weapon>…"),
#         log `NPC would give up her weapon`, no deal, the weapon stays equipped
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# switch: NEG_TEST_INJECT for the spawned neutral "Varn Oddie" (trust 0 < NEG_WEAPON_TRUST_MIN): ACCEPT GIVE_CATS
#         player 3000 + GIVE_ITEM npc {weapon} (his equipped weapon, resolved by the server).
# verify: server `Negotiation rejected: NPC would give up her weapon`; no ACCEPTED/AWAITING deal for him; the weapon is
#   still equipped (`inv`), not in Shay's inventory. SETUP FAIL when the spawned Drifter has no weapon.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
NPC="Varn Oddie"
log "35: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$NPC") || { verdict 35 "SETUP FAIL spawn"; exit 1; }
sleep 4
w=$(first_weapon "$v")
[ -n "$w" ] || { put_away "$v"; verdict 35 "SETUP FAIL $NPC has no equipped weapon: $(equipped_items "$v" | tr '\n' ',')"; exit 1; }
log "$NPC ($v) wields: $w"
greet "$NPC"
inject_on 35 "$NPC" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":3000},{"kind":"GIVE_ITEM","by":"npc","to":"player","item":"{weapon}"}],"message":"3000? Fine, it is yours."}]'
talk "$NPC" "$NPC, I'll pay you 3000 cats for your weapon."
sleep 5
stobe-auto speed 0 >/dev/null
rej=$(srv_count "NPC would give up her weapon")
d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2)
still=$(equipped_items "$v" | grep -c -F "$w")
npc_said "$NPC" | tail -2
log "rejections=$rej deal=${st:-none} weapon still equipped: $still"
cancel_deals "$NPC"; put_away "$v"
if [ "$(fired 35)" -lt 1 ]; then verdict 35 "INCONCLUSIVE switch never fired"
elif [ "$rej" -ge 1 ] && ! echo "$st" | grep -q -E "ACCEPTED|AWAITING|COMPLETE" && [ "$still" -ge 1 ]; then verdict 35 "PASS weapon deal refused, $w still equipped"
else verdict 35 "FAIL rejections=$rej deal=${st:-none} still_equipped=$still"; fi
