#!/usr/bin/env bash
# id: STOBE-22-gang-stands-down
# covers: STOBE 22 (was 43): fight with a gang of 3; one of them stops for pay; his words don't say the gang
#         "isn't his to call off"; the whole gang stands down
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first)
# needs: Stobe E1CD05BF+, server live, harness F946C881
# verify (VERDICT lines + by hand):
#   - deal with the first raider (by=player: player GIVE_CATS 300 now, npc STOP_ATTACK for the gang) -> COMPLETE after
#     "Here are your 300 cats" (Shay's cats -300);
#   - stobe.log `PERSONAL_TRUCE: stood down faction-mate=` for the two others, or no
#     `[EVENT] combat: <gang member> ... -> Shay` from any of the 3 in the 120 s after the payment
#     (STOBE_NEG_TRUCE_OBSERVE_SECONDS);
#   - his NPC_SAY lines don't contain "isn't mine to call off"/"not my call"/"can't call them off".
#   Run 12 note: the gang stood down only through a gang-mate's own surrender STOP_ATTACK; here only Shay offers.
# reliability: medium (3 raiders: the healer keeps Shay up; LLM must accept)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
log "22: setup"
wait_personal_guard
stobe-auto select Shay >/dev/null
park_malzin 600
heal_start Shay
mapfile -t G < <(spawn_raiders 3)
[ "${#G[@]}" -ge 2 ] || { verdict 22 "SETUP FAIL raiders=${#G[@]}"; exit 1; }
for s in "${G[@]}"; do stobe-auto attack "$s" Shay >/dev/null; done
engage "${G[0]}" || log "warning: no combat_start seen"
names=(); for s in "${G[@]}"; do names+=("$(name_of "$s")"); done
lead="${names[0]}"; log "gang: ${names[*]} (talking to $lead)"
sleep 10
stobe-say say "$lead" "Enough! Call your whole gang off and I'll pay you 300 cats right now." --wait 40 >/dev/null 2>&1 || true
d=$(wait_deal "$lead" "ACCEPTED|AWAITING|WAITING_FOR_PLAYER" 60)
[ -n "$d" ] || { stobe-say speed 0 >/dev/null; heal_stop; verdict 22 "INCONCLUSIVE no accepted deal: $(deal_line "$lead")"; exit 2; }
id=$(echo "$d" | awk '{print $1}'); log "deal $id"
m0=$(money_of Shay)
stobe-say say "$lead" "Here are your 300 cats." --wait 40 >/dev/null 2>&1 || true
wait_deal "$lead" "COMPLETE" 40 >/dev/null
m1=$(money_of Shay)
mark=$(grep -a -c "" "$L")
sleep 120
stobe-say speed 0 >/dev/null; heal_stop
deal_block "$id"
late=0; for n in "${names[@]}"; do c=$(tail -n +"$mark" "$L" | grep -a -F "[EVENT] combat: $n" | grep -a -c -- "-> Shay"); late=$((late + c)); log "$n attacks on Shay after paying: $c"; done
tail -n +"$BASE_L" "$L" | grep -a "PERSONAL_TRUCE: stood down" | tail -4 | cut -c1-250
bad=$(since_stobe | grep -a -F "NPC_SAY: $lead|" | grep -a -i -c -E "isn.t mine to call off|not my call|can.t call them off|not mine to call")
log "cats Shay $m0 -> $m1"
if deal_line "$lead" | grep -q COMPLETE && [ "$late" -eq 0 ] && [ "$bad" -eq 0 ]; then verdict 22 "PASS paid deal COMPLETE, gang quiet for 120 s"
else verdict 22 "FAIL complete=$(deal_line "$lead" | grep -c COMPLETE) attacks_after=$late wrong_words=$bad"; fi
