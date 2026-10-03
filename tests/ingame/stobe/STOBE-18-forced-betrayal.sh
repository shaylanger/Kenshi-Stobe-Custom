#!/usr/bin/env bash
# id: STOBE-18-forced-betrayal
# covers: STOBE 18: an NPC betrays a paid deal (re-attacks after the payment): BREACHED_NPC, marked intentional,
#         the outcome lands in his memory and the reputation record
# fixture: auto-home (or any fixture: PLAYER/MATE env)
# reset: fresh (`bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh`)
# needs: StobeServer 96b2c91+ (general_settings NEG_TEST_FORCE_BETRAYAL test switch), Stobe EF62563B+,
#        harness 08AB6BF0+ (`protect`; the lib falls back to a heal loop)
# Rare by design (personality + low trust + dice), so the wrapper turns the test switch on for the run and OFF again
# on exit (also on errors): every eligible paid deal is then betrayed, with reason "test_switch" in the plan.
# verify (VERDICT line + by hand):
#   - the deal (player GIVE_CATS + npc STOP_ATTACK) is accepted, Shay pays ("Here are your 200 cats"), then:
#   - deal status BREACHED_NPC; its betrayal plan has reason test_switch; term_state evidence `intentional_betrayal`;
#   - a `betray` directive with ATTACK@<player>, and stobe.log `[EVENT] combat: <npc> ... -> <player>` after paying;
#   - stobe_negotiation_reputation.npc_broken for the player +1; an eventlog memory row "went back on our deal".
# reliability: medium (the deal acceptance is an LLM decision; the betrayal itself is forced)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
PSQL() { (cd /tmp && sudo -u postgres psql -d stobe -At -c "$1"); }
switch_off() { PSQL "DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'" >/dev/null; log "test switch NEG_TEST_FORCE_BETRAYAL off"; }
trap 'switch_off; heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
PSQL "DELETE FROM general_settings WHERE id='NEG_TEST_FORCE_BETRAYAL'; INSERT INTO general_settings (id, value) VALUES ('NEG_TEST_FORCE_BETRAYAL', 'true')" >/dev/null
log "18: test switch on; setup"
rep0=$(PSQL "SELECT COALESCE(MAX(npc_broken),0) FROM stobe_negotiation_reputation WHERE player_name=LOWER('${PLAYER}')")
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 600
heal_start ${PLAYER}
r=$(spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict 18 "SETUP FAIL no raider"; exit 1; }
engage "$r" || log "warning: no combat_start seen"
name=$(name_of "$r"); log "raider $r = $name"
say_to "$r" "$name" "Enough! Stop fighting and I'll pay you 200 cats right now."
d=$(wait_accept "$name" 90)
[ -n "$d" ] || { verdict 18 "INCONCLUSIVE no accepted deal: $(deal_line "$name")"; exit 2; }
id=$(echo "$d" | awk '{print $1}'); log "deal $id"
PSQL "SELECT betrayal FROM stobe_social_contract WHERE contract_id='$id'" | cut -c1-200
mark=$(grep -a -c "" "$L")
say_to "$r" "$name" "Here are your 200 cats."
wait_deal "$name" "BREACHED_NPC|COMPLETE" 90 >/dev/null
sleep 10
stobe-auto speed 0 >/dev/null
deal_block "$id"
st=$(deal_line "$name" | awk '{print $3}')
plan=$(PSQL "SELECT betrayal::text FROM stobe_social_contract WHERE contract_id='$id'")
intent=$(PSQL "SELECT (term_state::text LIKE '%intentional_betrayal%')::int FROM stobe_social_contract WHERE contract_id='$id'")
dir=$(PSQL "SELECT COUNT(*) FROM stobe_negotiation_directive WHERE contract_id='$id' AND kind='betray' AND payload::text LIKE '%ATTACK@%'")
atk=$(tail -n +"$mark" "$L" | grep -a -F "[EVENT] combat: $name" | grep -a -c -- "-> ${PLAYER}")
rep1=$(PSQL "SELECT COALESCE(MAX(npc_broken),0) FROM stobe_negotiation_reputation WHERE player_name=LOWER('${PLAYER}')")
mem=$(PSQL "SELECT COUNT(*) FROM eventlog WHERE data LIKE '%went back on our deal%' AND data LIKE '%${PLAYER}%' AND localts > EXTRACT(EPOCH FROM NOW())::bigint - 900")
log "status=$st intentional=$intent betray_directive=$dir attacks_after_pay=$atk npc_broken $rep0 -> $rep1 memory_rows=$mem"
log "plan: $(echo "$plan" | cut -c1-200)"
if [ "$st" = BREACHED_NPC ] && [ "$intent" = 1 ] && [ "$rep1" -gt "$rep0" ] && echo "$plan" | grep -q test_switch; then
  verdict 18 "PASS forced betrayal: BREACHED_NPC, intentional, npc_broken +1 (attacks after paying: $atk, memory rows: $mem)"
else verdict 18 "FAIL status=$st intentional=$intent npc_broken $rep0->$rep1 directive=$dir"; fi
