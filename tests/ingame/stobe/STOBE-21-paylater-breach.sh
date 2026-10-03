#!/usr/bin/env bash
# id: STOBE-21-paylater-breach
# covers: STOBE 21 (was 42): fight, Fond trust, he stops for pay-later; Shay doesn't pay for 1+ game minute
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first)
# needs: Stobe E1CD05BF+, server live, harness F946C881; NEG personal fights on (default)
# verify (the wrapper prints VERDICT lines; also check by hand):
#   - deal for the raider: kind by=player with player GIVE_CATS (pay later) + npc STOP_ATTACK, state ACCEPTED /
#     AWAITING_PERFORMANCE after the offer, then BREACHED_PLAYER after the game minute
#     (`negotiation_admin.php deals 8`);
#   - server log: a `breach_react` directive for that deal; his next stobe.log `NPC_SAY: <name>|` line is angry and
#     does not say "cats received"/"we're square";
#   - an attack after the breach is allowed (it should match his words); Shay stays up (healer).
#   INCONCLUSIVE (not FAIL) when he refuses pay-later (run 12: "After is where men die") - rerun or raise trust.
# reliability: medium (LLM must accept pay-later; trust 60 Fond helps)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
log "21: setup"
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 400
heal_start ${PLAYER}
r=$(spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict 21 "SETUP FAIL no raider"; exit 1; }
engage "$r" || log "warning: no combat_start seen"
name=$(name_of "$r"); log "raider $r = $name"
trust "$name" 60 Fond >/dev/null 2>&1 || true
stobe-auto health "$r" 45 >/dev/null          # hurting, not yet ready to beg (we want ${PLAYER}'s offer, not his)
sleep 4
say_to "$r" "$name" "Stop! Stop fighting. Stand down now and I'll pay you 200 cats later, once this is over. You have my word."
d=$(wait_accept "$name" 90)
if [ -z "$d" ]; then
  stobe-say speed 0 >/dev/null; heal_stop
  verdict 21 "INCONCLUSIVE no accepted pay-later deal: $(deal_line "$name")"; exit 2
fi
id=$(echo "$d" | awk '{print $1}'); log "deal $id accepted"; deal_block "$id"
# do NOT pay; let more than a game minute pass (game time runs only unpaused)
stobe-say speed 2 >/dev/null
sleep 45
stobe-say speed 1 >/dev/null
d2=$(wait_deal "$name" "BREACHED_PLAYER" 90); stobe-say speed 0 >/dev/null; heal_stop
deal_block "$id"
since_srv | grep -a -F "$id" | grep -a -i "breach_react" | tail -2 | cut -c1-300
since_stobe | grep -a -F "NPC_SAY: $name|" | tail -3 | cut -c1-300
if [ -n "$d2" ]; then
  if since_stobe | grep -a -F "NPC_SAY: $name|" | tail -2 | grep -a -q -i -E "cats received|we're square|we are square"; then
    verdict 21 "FAIL breached but his line claims payment"
  else verdict 21 "PASS deal BREACHED_PLAYER (check his line + breach_react above)"; fi
else verdict 21 "FAIL deal not BREACHED_PLAYER after the wait: $(deal_line "$name")"; fi
