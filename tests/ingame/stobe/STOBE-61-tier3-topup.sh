#!/usr/bin/env bash
# id: STOBE-61-tier3-topup
# covers: STOBE 61 (cap tiers 3-5, purse top-up): a tier 3+ NPC (default the Dust King, 2849-gamedata.base, tier 4)
#         with few cats offers more than he carries; on payment the purse is topped up
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first)
# needs: Stobe E1CD05BF+ (`NEG_CATS_PURSE_MODES` on), server live, harness F946C881
# usage: STOBE-61-tier3-topup.sh [template]   (e.g. a Samurai template for tier 3)
# m10 blocker: he fled ~240 m at 25 % health before his offer was spoken -> this wrapper teleports him back next to
# Shay every 4 s while it waits.
# verify (VERDICT lines + by hand):
#   - his offer (deal kind=surrender by=npc): npc GIVE_CATS amount > what he carried (printed), up to 50,000 (tier 4) /
#     10,000 (tier 3);
#   - after "<full name>, deal.": stobe.log `GIVE_CATS@Shay@<N>@topup` dispatched and `GIVE_CATS topup ... added=`;
#     Shay's cats +N (the full amount); deal COMPLETE.
#   - second deal within 3 game days (optional, by hand): he offers only what he carries.
# reliability: medium (the offer is LLM-made; the teleport loop removes the flee problem)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
T="${1:-2849-gamedata.base}"
log "61: setup with $T"
wait_personal_guard
stobe-auto select Shay >/dev/null
park_malzin 600
heal_start Shay
r=$(spawn_raiders 1 "$T" | head -1); [ -n "$r" ] || { verdict 61 "SETUP FAIL no NPC from $T"; exit 1; }
carried=$(money_of "$r"); log "$r carries ${carried:-?} cats"
if [ "${carried:-0}" -gt 200 ]; then stobe-auto money "$r" "-$(( carried - 150 ))" >/dev/null; carried=$(money_of "$r"); log "now carries $carried"; fi
engage "$r" || log "warning: no combat_start seen"
name=$(name_of "$r"); log "$r = $name"
stobe-auto health "$r" 25 >/dev/null
name=$(name_of "$r")
d=""
for i in $(seq 1 30); do
  sleep 4
  dist=$(stobe-auto where "$r" | grep -oE 'dist=[0-9.]+' | cut -d= -f2 | cut -d. -f1)
  [ "${dist:-0}" -gt 15 ] && stobe-auto teleport "$r" Shay dist 4 >/dev/null
  stobe-auto where "$r" | grep -q " KO" && { log "he went down (KO)"; break; }
  d=$(deal_line "$name" "PROPOSED|COUNTERED"); [ -n "$d" ] && break
  name=$(name_of "$r")
done
[ -n "$d" ] || { stobe-say speed 0 >/dev/null; heal_stop; verdict 61 "INCONCLUSIVE no offer: $(deal_line "$name")"; exit 2; }
id=$(echo "$d" | awk '{print $1}'); deal_block "$id"
offer=$(deal_block "$id" | awk '$1=="npc" && $2=="GIVE_CATS"{print $3}' | head -1)
m0=$(money_of Shay)
stobe-say say "$name" "$name, deal." --wait 40 >/dev/null 2>&1 || true
wait_deal "$name" "COMPLETE" 60 >/dev/null
sleep 5
m1=$(money_of Shay); stobe-say speed 0 >/dev/null; heal_stop
deal_block "$id"
since_stobe | grep -a -E "GIVE_CATS@[^@]*@[0-9]+@(topup|exact)|GIVE_CATS topup" | tail -4 | cut -c1-250
got=$(( ${m1:-0} - ${m0:-0} ))
log "carried=$carried offer=${offer:-?} Shay got=$got"
if [ -n "$offer" ] && [ "$offer" -gt "${carried:-0}" ] && [ "$got" -ge "$offer" ] && since_stobe | grep -a -q "GIVE_CATS topup"; then
  verdict 61 "PASS offer $offer > carried $carried, topped up, Shay +$got"
elif [ -n "$offer" ] && [ "$offer" -le "${carried:-0}" ]; then verdict 61 "INCONCLUSIVE offer $offer within what he carried ($carried): no top-up needed"
else verdict 61 "FAIL offer=${offer:-none} carried=$carried got=$got"; fi
