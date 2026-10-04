#!/usr/bin/env bash
# id: STOBE-20-refuse-after-handover
# covers: STOBE 20: he hands something over first, Shay refuses to pay; he may threaten/attack; paying then
#         stops it and the stop holds
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first)
# needs: Stobe E1CD05BF+, server live, harness F946C881
# verify (VERDICT lines + by hand):
#   - deal: npc GIVE_ITEM (his weapon) + player GIVE_CATS 100 after; his GIVE_ITEM VERIFIED/DISPATCHED and the item in
#     `inv Shay` before Shay refuses;
#   - after "I'm not paying": deal BREACHED_PLAYER and/or a threat line / `[EVENT] combat: <name> ... -> Shay`;
#   - after "Fine, here are your 100 cats": Shay's cats -100, his +100 (`money <npc> 0`), and no
#     `[EVENT] combat: <name> ... -> Shay` in the 60 s after the payment (the stop holds).
#   INCONCLUSIVE when he insists on being paid first (run 12) - the trust 60 + "you first, I pay right after" wording
#   is meant to avoid that.
# reliability: low-medium (two LLM decisions: hand over first, then react to the refusal); with FORCE=1 (default) the
#   first decision is forced: test switch NEG_TEST_INJECT (StobeServer 2b2b52d+) makes his reply an ACCEPT with npc
#   GIVE_ITEM {worn} now + player GIVE_CATS 100 after_npc + npc STOP_ATTACK (raiders always wanted Cats first, run 12/m16;
#   by design per the negotiation rules, so the switch is the only way to reach the rest of the row). FORCE=0 = old run.
#   The switch is turned off on exit.
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
log "20: setup"
wait_personal_guard
stobe-auto select ${PLAYER} >/dev/null
park_malzin 500
heal_start ${PLAYER}
r=$(spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict 20 "SETUP FAIL no raider"; exit 1; }
engage "$r" || log "warning: no combat_start seen"
name=$(name_of "$r"); log "raider $r = $name"
trust "$name" 60 Fond >/dev/null 2>&1 || true
stobe-auto health "$r" 30 >/dev/null
sleep 4
weapon=$(stobe-auto inv "$r" | grep -o '"name":"[^"]*","count":1,"equipped":true' | head -1 | sed -E 's/"name":"([^"]*)".*/\1/')
log "his first worn item: ${weapon:-?}"
if [ "${FORCE:-1}" = 1 ]; then
  inject_on 20 "$name" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_ITEM","by":"npc","to":"player","item":"{worn}"},{"kind":"GIVE_CATS","by":"player","to":"npc","amount":100,"when":"after_npc"},{"kind":"STOP_ATTACK","by":"npc","target":"player"}],"message":"Fine. You first get my {worn}, then you pay me 100."}]'
fi
say_to "$r" "$name" "Enough! Toss me your weapon first and I'll pay you 100 cats right after. Deal?"
d=$(wait_accept "$name" 90)
[ -n "$d" ] || { stobe-say speed 0 >/dev/null; heal_stop; verdict 20 "INCONCLUSIVE no accepted deal: $(deal_line "$name")"; exit 2; }
id=$(echo "$d" | awk '{print $1}'); log "deal $id"
for i in $(seq 1 15); do deal_block "$id" | grep -E "npc +(GIVE_ITEM|UNEQUIP_ITEM)" | grep -q -E "VERIFIED|DISPATCHED" && break; sleep 4; done
deal_block "$id"
if ! deal_block "$id" | grep -E "npc +(GIVE_ITEM|UNEQUIP_ITEM)" | grep -q -E "VERIFIED|DISPATCHED"; then
  stobe-say speed 0 >/dev/null; heal_stop; verdict 20 "INCONCLUSIVE he did not hand over first"; exit 2
fi
m_shay0=$(money_of ${PLAYER}); m_him0=$(money_of "$r")
say_to "$r" "$name" "Actually, I'm not paying you anything. Get lost."
sleep 20
reacted=0
deal_line "$name" | grep -q BREACHED_PLAYER && reacted=1
since_stobe | grep -a -F "[EVENT] combat: $name" | grep -a -q -- "-> ${PLAYER}" && reacted=1
since_stobe | grep -a -F "NPC_SAY: $name|" | tail -2 | cut -c1-300
say_to "$r" "$name" "Fine, fine. Here are your 100 cats."
sleep 6
m_shay1=$(money_of ${PLAYER}); m_him1=$(money_of "$r")
mark=$(grep -a -c "" "$L")
sleep 60
stobe-say speed 0 >/dev/null; heal_stop
late=$(tail -n +"$mark" "$L" | grep -a -F "[EVENT] combat: $name" | grep -a -c -- "-> ${PLAYER}")
deal_block "$id"
log "cats ${PLAYER} $m_shay0 -> $m_shay1, $name $m_him0 -> $m_him1; attacks on ${PLAYER} after paying: $late; reacted to refusal: $reacted"
paid=$(( ${m_shay0:-0} - ${m_shay1:-0} ))
if [ "$paid" -ge 100 ] && [ "${late:-0}" -eq 0 ]; then verdict 20 "PASS paid $paid after refusing, stop held (reacted=$reacted: see his lines)"
else verdict 20 "FAIL paid=$paid attacks_after_pay=$late"; fi
