#!/usr/bin/env bash
# id: STOBE-C25-renamed-surrender
# covers: STOBE 25 (bug 128): a raider's surrender offer queued under his generic name arrives although he got a name
#         mid-fight ("Dust Bandit" -> "Gost [Dust Bandit]"): server `Directive follows the NPC's new name`, offer arrives
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh
# needs: StobeServer 2b2b52d+ (NEG_TEST_FORCE_INITIATIVE, NEG_TEST_INJECT), harness on (`protect`)
# switches: NEG_TEST_FORCE_INITIATIVE {kind surrender, npc <old name>, queue_as_old_name true}: the first fight event
#           queues his surrender offer under the old name (the state a mid-fight naming leaves; spawned raiders were
#           always named before any offer); NEG_TEST_INJECT context directive: PROPOSE STOP_ATTACK npc + SPARE player +
#           GIVE_CATS npc 40 (so the offer is a recorded deal).
# verify: `NEG_TEST_FORCE_INITIATIVE fired (test switch, row 25)` queued_as=<old>; `Directive follows the NPC's new name
#   (bug 128)` to=<new>; the directive row now named <new> and delivered; a deal PROPOSED by npc for <new>.
# reliability: high
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
log "25: setup"
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 600
heal_start ${PLAYER}
r=$(KEEP_TEMPLATE_NAME=1 spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict 25 "SETUP FAIL no raider"; exit 1; }
old=$(name_of "$r")
case "$old" in *"["*) put_away "$r"; verdict 25 "SETUP FAIL raider already named: $old"; exit 1;; esac
new="Gost [$old]"
stobe-auto setname "$r" "$new" >/dev/null
log "raider $r: '$old' -> '$new'"
force_on 25 surrender "$old" true
inject_on 25 "$old" directive '[{"deal_decision":"PROPOSE","deal_terms":[{"kind":"GIVE_CATS","by":"npc","to":"player","amount":40},{"kind":"STOP_ATTACK","by":"npc","target":"player"},{"kind":"SPARE","by":"player","target":"npc"}],"message":"Enough! Forty cats, all I have, if you let me go."}]'
engage "$r" || log "warning: no combat_start seen"
dir=""
for i in $(seq 1 24); do
  dir=$(PSQL "SELECT npc_name||'|'||consumed_unix||'|'||outcome FROM stobe_negotiation_directive WHERE kind='surrender' AND npc_name IN ('$(sq "$old")','$(sq "$new")') AND created_unix >= ${WRAP_START} ORDER BY id DESC LIMIT 1")
  echo "$dir" | grep -q '|delivered$' && break
  sleep 5
done
sleep 4
stobe-auto speed 0 >/dev/null
ff=$(srv_has "NEG_TEST_FORCE_INITIATIVE fired (test switch, row 25)" | tail -1)
fol=$(srv_has "Directive follows the NPC's new name" | grep -c -F "$new")
d=$(deal_row "$new"); st=$(echo "$d" | cut -d'|' -f2); by=$(echo "$d" | cut -d'|' -f4)
npc_said "$new" | tail -2
log "forced: $(echo "$ff" | grep -oE '"queued_as":"[^"]*"') follows=$fol directive=${dir:-none} deal=${st:-none} by=$by"
heal_stop; cancel_deals "$new"; put_away "$r"
if [ -z "$ff" ]; then verdict 25 "INCONCLUSIVE the forced surrender never fired (no fight with ${PLAYER}?)"
elif [ "$fol" -ge 1 ] && echo "$dir" | grep -q -F "$new|" && echo "$dir" | grep -q '|delivered$' && [ "$st" = PROPOSED ] && [ "$by" = npc ]; then
  verdict 25 "PASS offer queued as '$old' followed him to '$new' and arrived (deal PROPOSED)"
else verdict 25 "FAIL follows=$fol directive=${dir:-none} deal=${st:-none}"; fi
