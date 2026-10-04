#!/usr/bin/env bash
# id: STOBE-C37-assist-request
# covers: STOBE 37: a neutral NPC losing a fight near Shay asks for help, maybe with a reward
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_FORCE_INITIATIVE, NEG_TEST_INJECT), harness on (`fight`, `protect`)
# switches: NEG_TEST_FORCE_INITIATIVE {kind assist, npc "Pell Varrow"} (skips the health/courage/cooldown gates once:
#           run 10's victim wandered off before his health dropped); NEG_TEST_INJECT context directive for Pell:
#           PROPOSE player PROTECT + npc GIVE_CATS 100 after_player (so the offer is a recorded deal, not just words).
# setup: two neutral Drifters 15/18 m from Shay, "Brakk Oddie" moved to Traders Guild (C37_ATTACKER_FACTION) and ordered (`fight`) to attack "Pell Varrow"; Pell protected.
# verify: server `NEG_TEST_FORCE_INITIATIVE fired (test switch, row 37)`; an `assist` directive for Pell with an outcome
#   (delivered: his call for help was spoken, stobe.log NPC_SAY: Pell…); a deal kind assist PROPOSED by npc for Pell.
#   INCONCLUSIVE when the switch never fired (no fight events with Shay in the people list).
# reliability: medium-high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
V="Pell Varrow"; T="Brakk Oddie"
log "37: setup"
stobe-auto select ${PLAYER} >/dev/null
stobe-auto teleport ${MATE} ${PLAYER} dist 25 >/dev/null
stobe-say speed 1 >/dev/null
v=$(spawn_neutral "$V" 15) || { verdict 37 "SETUP FAIL spawn victim"; exit 1; }
t=$(spawn_neutral "$T" 18) || { put_away "$v"; verdict 37 "SETUP FAIL spawn attacker"; exit 1; }
# m22 (C37 m22): both spawn as Drifters and `fight` refuses one faction ("same faction (Drifters): move one first").
# Move the attacker into another faction neutral to the player first (new handle).
AF="${C37_ATTACKER_FACTION:-Traders Guild}"
fo=$(stobe-auto faction "$t" "$AF" 2>&1); nt=$(echo "$fo" | grep -oE '#[0-9]+/[0-9]+' | tail -1)
[ -n "$nt" ] || { put_away "$t" "$v"; verdict 37 "SETUP FAIL faction move: $fo"; exit 1; }
t="$nt"; log "$T moved to $AF ($t)"
stobe-auto protect "$v" on >/dev/null 2>&1 || log "no protect: $V may go down"
sleep 4
force_on 37 assist "$V"
inject_on 37 "$V" directive '[{"deal_decision":"PROPOSE","deal_terms":[{"kind":"PROTECT","by":"player","target":"npc"},{"kind":"GIVE_CATS","by":"npc","to":"player","amount":100,"when":"after_player"}],"message":"Help! Get him off me - 100 cats are yours if you do!"}]'
for i in 1 2 3; do fo=$(stobe-auto fight "$t" "$v" 2>&1) || log "fight: $fo"; sleep 5; done
dir=""
for i in $(seq 1 18); do
  dir=$(PSQL "SELECT id||'|'||consumed_unix||'|'||outcome FROM stobe_negotiation_directive WHERE npc_name='$(sq "$V")' AND kind='assist' AND created_unix >= ${WRAP_START} ORDER BY id DESC LIMIT 1")
  echo "$dir" | grep -q '|delivered$' && break
  sleep 5
done
sleep 5
stobe-auto speed 0 >/dev/null
ff=$(srv_count "NEG_TEST_FORCE_INITIATIVE fired (test switch, row 37)")
d=$(deal_row "$V"); st=$(echo "$d" | cut -d'|' -f2); kind=$(echo "$d" | cut -d'|' -f3); by=$(echo "$d" | cut -d'|' -f4)
npc_said "$V" | tail -2
log "forced=$ff directive=${dir:-none} deal=${st:-none} kind=$kind by=$by"
stobe-auto protect "$v" off >/dev/null 2>&1
cancel_deals "$V"; put_away "$t" "$v"
if [ "$ff" -lt 1 ]; then verdict 37 "INCONCLUSIVE the forced initiative never fired (fight events / ${PLAYER} not nearby?)"
elif echo "$dir" | grep -q '|delivered$' && [ "$kind" = assist ] && [ "$by" = npc ] && [ "$st" = PROPOSED ]; then verdict 37 "PASS $V asked for help with a reward (assist deal PROPOSED)"
elif echo "$dir" | grep -q '|delivered$'; then verdict 37 "FAIL call for help spoken but no assist deal (deal=${st:-none} kind=$kind)"
else verdict 37 "FAIL assist directive not delivered: ${dir:-none}"; fi
