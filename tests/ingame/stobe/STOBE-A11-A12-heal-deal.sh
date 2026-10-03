#!/usr/bin/env bash
# id: STOBE-A11-A12-heal-deal
# covers: STOBE A11 (heal-for-item deal kept: she hands the item over on her own after Shay heals her) and
#         A12 (she hands over first, Shay then refuses to heal: Shay broke the deal, no "we're square")
# fixture: auto-home
# reset: fresh (run `bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh` first; once per mode)
# usage: STOBE-A11-A12-heal-deal.sh a11|a12
# needs: Stobe E1CD05BF+, server live, harness F946C881
# setup: a neutral Drifter renamed "Senlin" 12 m from Shay (closer gets her attacked), no medical item on her
#        (checked; anything found is moved to Shay), a bleeding chest wound (`damage` + `blood 40%`) and crippled-ish
#        legs (cut, not below 0) so she stays put; Shay gets 2 Basic First Aid Kits.
# verify (VERDICT lines + by hand):
#   A11: deal by=player: player FIRST_AID + npc GIVE_ITEM <her item>; after `order Shay FIRST_AID_ORDER target Senlin`:
#        stobe.log `[EVENT] healing: Shay ... Senlin`, player FIRST_AID VERIFIED; then (Shay says nothing) her GIVE_ITEM
#        VERIFIED, deal COMPLETE, the item in `inv Shay`.
#   A12: her GIVE_ITEM VERIFIED before any healing; after "I'm not going to heal you": deal BREACHED_PLAYER, her next
#        NPC_SAY has no "we're square"/"we are square".
#   INCONCLUSIVE: no deal, or (A12) she waits for the healing before handing over.
# reliability: A11 medium; A12 low (needs her to go first)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
mode="${1:-a11}"
log "$mode: setup"
stobe-auto select Shay >/dev/null
stobe-auto teleport Malzin Shay dist 25 >/dev/null
out=$(stobe-auto spawn "Hungry Bandit" Drifters near Shay dist 12 count 1)
v=$(echo "$out" | grep -oE '#[0-9]+/[0-9]+' | head -1); [ -n "$v" ] || { verdict "$mode" "SETUP FAIL spawn: $out"; exit 1; }
stobe-auto setname "$v" "Senlin" >/dev/null
# no self-treatment: move any medical item to Shay
for it in $(stobe-auto inv "$v" | grep -oE '"name":"[^"]*(First Aid|Bandage|Splint|Medkit)[^"]*"' | sed -E 's/"name":"(.*)"/\1/' | tr ' ' '_'); do
  stobe-auto transfer "$v" Shay "${it//_/ }" >/dev/null; log "moved ${it//_/ } to Shay"
done
item=$(stobe-auto inv "$v" | grep -oE '"name":"[^"]*","count":1,"equipped":true' | head -1 | sed -E 's/"name":"([^"]*)".*/\1/')
[ -n "$item" ] || item="shirt"
log "Senlin ($v) wears: $item"
stobe-auto damage "$v" chest 35 >/dev/null
stobe-auto damage "$v" left_leg 40 >/dev/null
stobe-auto damage "$v" right_leg 40 >/dev/null
stobe-auto blood "$v" 40% >/dev/null
stobe-auto give Shay "Basic First Aid Kit" 2 >/dev/null
stobe-auto hp "$v" | cut -c1-200
stobe-say speed 1 >/dev/null
sleep 8
stobe-say say "Senlin" "Senlin, you're bleeding badly. What if I bandage you up and you give me your $item?" --wait 40 >/dev/null 2>&1 || true
d=$(wait_deal "Senlin" "ACCEPTED|AWAITING|WAITING_FOR_PLAYER" 60)
[ -n "$d" ] || { stobe-say speed 0 >/dev/null; verdict "$mode" "INCONCLUSIVE no accepted deal: $(deal_line Senlin)"; exit 2; }
id=$(echo "$d" | awk '{print $1}'); deal_block "$id"
npc_done() { deal_block "$id" | grep -E "npc +(GIVE_ITEM|UNEQUIP_ITEM)" | grep -q -E "VERIFIED"; }
if [ "$mode" = a12 ]; then
  for i in $(seq 1 15); do npc_done && break; sleep 4; done
  npc_done || { stobe-say speed 0 >/dev/null; deal_block "$id"; verdict a12 "INCONCLUSIVE she did not hand over first"; exit 2; }
  stobe-say say "Senlin" "Thanks. I'm not going to heal you, though." --wait 40 >/dev/null 2>&1 || true
  wait_deal "Senlin" "BREACHED_PLAYER" 40 >/dev/null
  stobe-say speed 0 >/dev/null; deal_block "$id"
  since_stobe | grep -a -F "NPC_SAY: Senlin|" | tail -2 | cut -c1-300
  sq=$(since_stobe | grep -a -F "NPC_SAY: Senlin|" | tail -2 | grep -a -i -c -E "we.re square|we are square")
  if deal_line Senlin | grep -q BREACHED_PLAYER && [ "$sq" -eq 0 ]; then verdict a12 "PASS BREACHED_PLAYER, no 'we're square'"
  else verdict a12 "FAIL state=$(deal_line Senlin | awk '{print $NF}') square_lines=$sq"; fi
  exit 0
fi
stobe-auto order Shay FIRST_AID_ORDER target "$v" >/dev/null
for i in $(seq 1 20); do deal_block "$id" | grep -E "player +FIRST_AID" | grep -q VERIFIED && break; sleep 4; done
since_stobe | grep -a "\[EVENT\] healing: Shay" | tail -2 | cut -c1-200
for i in $(seq 1 20); do npc_done && break; sleep 4; done
stobe-say speed 0 >/dev/null
deal_block "$id"
have=$(stobe-auto inv Shay | grep -c -F "\"name\":\"$item\"")
if deal_line Senlin | grep -q COMPLETE && [ "$have" -ge 1 ]; then verdict a11 "PASS healed, she handed over $item on her own, COMPLETE"
else verdict a11 "FAIL state=$(deal_line Senlin | awk '{print $3}') item_in_shay_inv=$have"; fi
