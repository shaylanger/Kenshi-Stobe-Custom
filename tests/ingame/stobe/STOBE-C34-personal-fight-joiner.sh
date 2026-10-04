#!/usr/bin/env bash
# id: STOBE-C34-personal-fight-joiner
# covers: STOBE 34: a one-on-one fight (an NPC attacks Shay over an insult) where a faction-mate joins uninvited:
#         the joiner is stood down (`PERSONAL_FIGHT: stood down joiner=…` within ~0.25 s)
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), Stobe with PERSONAL_FIGHT, harness on (`protect`, `attack`)
# switch: NEG_TEST_INJECT for "Varn Oddie" (neutral Drifter): action Attack on the player + "You'll regret that insult."
#         (the model's choice to start a personal fight). The joiner "Brakk Oddie" (same faction) gets a harness
#         `attack` order on Shay: that's the uninvited join.
# verify: server `Personal fight registered` (npc Varn) and stobe.log `PERSONAL_FIGHT: registered`; after Brakk's attack:
#   stobe.log `PERSONAL_FIGHT: stood down joiner=Brakk…` or server `Personal fight: faction-mate stood down` (joiner Brakk).
#   INCONCLUSIVE when Brakk never attacked Shay (no `[EVENT] combat: Brakk … -> Shay`).
# reliability: medium-high (game AI: Brakk must take the attack order)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
A="Varn Oddie"; B="Brakk Oddie"
log "34: setup"
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 600
heal_start ${PLAYER}
stobe-say speed 1 >/dev/null
a=$(spawn_neutral "$A" 12) || { verdict 34 "SETUP FAIL spawn A"; exit 1; }
b=$(spawn_neutral "$B" 16) || { put_away "$a"; verdict 34 "SETUP FAIL spawn B"; exit 1; }
sleep 4; greet "$A"
inject_on 34 "$A" chat "[{\"action\":\"Attack\",\"target\":\"{player}\",\"message\":\"You'll regret that insult.\"}]"
talk "$A" "$A, you're a coward and a thief." 12
reg=$(srv_count "Personal fight registered"); nreg=$(since_stobe | grep -a -c "PERSONAL_FIGHT: registered")
log "registered: server=$reg stobe=$nreg"
for i in 1 2 3; do stobe-auto attack "$b" ${PLAYER} >/dev/null; sleep 6; done
sleep 10
stobe-auto speed 0 >/dev/null
joined=$(since_stobe | grep -a -F "[EVENT] combat: $B" | grep -a -c -- "-> ${PLAYER}")
sd_n=$(since_stobe | grep -a "PERSONAL_FIGHT: stood down" | grep -a -c -F "$B")
sd_s=$(srv_has "Personal fight: faction-mate stood down" | grep -c -F "$B")
since_stobe | grep -a "PERSONAL_FIGHT" | tail -4 | cut -c1-200
log "Brakk attacks on ${PLAYER}: $joined; stood down: stobe=$sd_n server=$sd_s"
heal_stop; put_away "$a" "$b"
if [ "$(fired 34)" -lt 1 ]; then verdict 34 "INCONCLUSIVE switch never fired"
elif [ "$reg" -lt 1 ] && [ "$nreg" -lt 1 ]; then verdict 34 "FAIL the injected attack registered no personal fight"
elif [ "$sd_n" -ge 1 ] || [ "$sd_s" -ge 1 ]; then verdict 34 "PASS joiner $B stood down (stobe=$sd_n server=$sd_s)"
elif [ "$joined" -eq 0 ]; then verdict 34 "INCONCLUSIVE $B never attacked ${PLAYER}"
else verdict 34 "FAIL $B joined ($joined attacks) and was not stood down"; fi
