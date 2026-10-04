#!/usr/bin/env bash
# id: STOBE-15-buy-approval
# covers: STOBE 15: a production goal whose missing ingredient only a trader has -> WAITING_APPROVAL;
#         approve -> she buys it (and the goal goes on); decline -> the purchase is cancelled
# fixture: Crafting base
# reset: fresh (reload the Crafting base copy first; once per mode)
# usage: STOBE-15-buy-approval.sh approve|decline
# needs: KenshiFP B1F468C8 (items 99b+99c: nearest trader that stocks it, carried goods included; STOBE 89 should pass first), Stobe EF62563B+,
#        harness F946C881
# chain: Basic First Aid Kit = Fabrics at the Basic Medical Workbench (game data: 'medical crafting basic' consumes
#        Fabrics). No Loom in the base, so Fabrics have no producer; the planner then asks the NEAREST trader to
#        Malzin (stg_find_trader). Every trader within 600 m gets 5 Fabrics so whichever is nearest has them; Malzin
#        and the base storage have none (checked).
# verify (VERDICT lines + by hand):
#   - KenshiFP.log `WORK_GOAL accepted ... item=Basic First Aid Kit`, then stobe_task_goal.status has a `buy-...Fabrics`
#     row in WAITING_APPROVAL with step "Need approval to buy N Fabrics from <trader> for up to M Cats";
#   - approve ("Yes, go ahead and buy the fabrics"): that row goes ACTIVE -> COMPLETE, Malzin's cats drop, Fabrics in
#     her inventory, and the work goal moves on (bench queue 1);
#   - decline ("No, don't buy anything"): the row goes CANCELLED and the work goal BLOCKED "purchase of Fabrics was
#     declined or failed". If the voice line isn't understood, the wrapper writes `<id>\tAPPROVE|CANCEL` to
#     stobe_task_goal.control and says so (then the voice path is the bug, the goal path is still checked).
# reliability: medium (fixed chain; risk: the nearest "trader" is someone the harness can't give to)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
mode="${1:-approve}"
ST=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.status
CT=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.control
BASE_K=$(grep -a -c "" "$KFP" 2>/dev/null || echo 0)
stobe-auto speed 0 >/dev/null; stobe-auto select ${PLAYER} >/dev/null
stobe-auto clearjobs ${MATE} >/dev/null
stobe-auto research "Fabric Manufacture" | cut -c1-160
stobe-auto research "Basic First Aid Kits" | cut -c1-160   # m16: blueprint found nothing for the kit
stobe-auto benches 200 crafts | tr '|' '\n' | grep -A0 "Basic Medical Workbench" | cut -c1-200
stobe-auto inv ${MATE} | grep -q '"name":"Fabrics"' && { verdict 15 "SETUP FAIL ${MATE} already has Fabrics"; exit 1; }
stobe-auto find item Fabrics | cut -c1-200
n=0
# m16 craft4: the "Skeleton Traders Animals" squad is only pack spiders (traders, but they never held the Fabrics:
# shopstock showed Iron Plates/Electrical Components/Skeleton Muscle), and the town apothecaries are ~250 m from
# Malzin, outside the fallback's 220 m. So: bring a real trader with real stock next to her.
TRADER="${TRADER:-Apothecary Abia}"   # m16 4080 fixtures: any trader (the Squin wrapper picks one)
if [ "${BUILD_BENCH:-0}" = 1 ]; then stobe-auto build "Basic Medical Workbench" near ${MATE} dist 15 | cut -c1-160; fi  # towns without a medical bench (Squin)
stobe-auto teleport "$TRADER" ${MATE} dist 30 | cut -c1-160
stobe-auto give "$TRADER" "Fabrics" 5 | cut -c1-120
# the medical bench needs power (m16 craft2: out_of_power=1.0): harness `power ... supply` (KAH 10)
stobe-auto power "Basic Medical Workbench" supply radius 300 | cut -c1-200
stobe-say speed 1 >/dev/null; sleep 3; stobe-say speed 0 >/dev/null
stobe-auto building "Basic Medical Workbench" radius 300 | grep -oE "has_power=[0-9] out_of_power=[0-9.]+"
for t in $(stobe-auto traders 600 | tr '|' '\n' | grep -oE '#[0-9]+/[0-9]+'); do
  stobe-auto give "$t" "Fabrics" 5 | cut -c1-120; n=$((n+1))
done
log "gave Fabrics to $n trader(s)"; [ "$n" -gt 0 ] || { verdict 15 "SETUP FAIL no trader within 600"; exit 1; }
# what the fallback will see: traders near Malzin and what each really sells (`shopstock` = the game's view)
for t in $(stobe-auto traders 300 near ${MATE} | tr '|' '\n' | grep -oE '#[0-9]+/[0-9]+'); do
  stobe-auto shopstock "$t" | cut -c1-300
done
# m16 Squin: Marquart got 4/5 given Fabrics but `shopstock` didn't list them; KenshiFP 99c also reads carried
# unworn goods, so carried Fabrics (`inv`) are enough. Fail only when the trader has none at all.
if ! stobe-auto shopstock "$TRADER" | grep -q "Fabrics"; then
  if stobe-auto inv "$TRADER" | grep -q '"name":"Fabrics"'; then log "$TRADER carries Fabrics (not listed by shopstock; KenshiFP 99c reads carried goods)"
  else verdict 15 "SETUP FAIL $TRADER has no Fabrics (shopstock and inv)"; exit 1; fi
fi
tail -n +"$BASE_K" "$KFP" | grep -a "BUY_FALLBACK" | tail -3
[ "$(money_of ${MATE})" -lt 200 ] 2>/dev/null && { stobe-auto money ${MATE} 500 >/dev/null; log "${MATE} had under 200 cats: +500 (m18 Squin: Kint 0)"; }
cats0=$(money_of ${MATE})
stobe-say say ${MATE} "${MATE}, make me one Basic First Aid Kit at the medical workbench." --wait 40 >/dev/null 2>&1 || true
stobe-say speed 1 >/dev/null
row=""
for i in $(seq 1 20); do sleep 3; row=$(grep -a -P '^buy-[^\t]*Fabrics' "$ST" 2>/dev/null | tail -1); echo "$row" | grep -q WAITING_APPROVAL && break; done
tail -n +"$BASE_K" "$KFP" | grep -a -E "WORK_GOAL (accepted|blocked)|find_producer done|BUY_FALLBACK" | tail -6 | cut -c1-260
echo "$row" | grep -q WAITING_APPROVAL || { stobe-say speed 0 >/dev/null; verdict 15 "FAIL no WAITING_APPROVAL buy row: ${row:-none}"; exit 1; }
bid=$(echo "$row" | cut -f1); log "approval row: $(echo "$row" | tr '\t' '|' | cut -c1-250)"
if [ "$mode" = approve ]; then line="Yes, go ahead and buy the fabrics."; want="ACTIVE|COMPLETE"; ctl=APPROVE
else line="No, don't buy anything."; want="CANCELLED"; ctl=CANCEL; fi
stobe-say say ${MATE} "$line" --wait 40 >/dev/null 2>&1 || true
ok=0; for i in $(seq 1 10); do sleep 3; grep -a -P "^\Q$bid\E\t" "$ST" | grep -q -E "$want" && { ok=1; break; }; done
if [ "$ok" = 0 ]; then log "voice not taken: writing $ctl to the control file"; printf '%s\t%s\n' "$bid" "$ctl" >> "$CT"; voice=0; sleep 8; else voice=1; fi
if [ "$mode" = approve ]; then
  for i in $(seq 1 40); do sleep 3; grep -a -P "^\Q$bid\E\t" "$ST" | grep -q COMPLETE && break; done
fi
stobe-say speed 0 >/dev/null
final=$(grep -a -P "^\Q$bid\E\t" "$ST" | tail -1 | tr '\t' '|' | cut -c1-250); cats1=$(money_of ${MATE})
has=$(stobe-auto inv ${MATE} | grep -c '"name":"Fabrics"')
log "final: $final; ${MATE} cats $cats0 -> $cats1; Fabrics in inv: $has; voice=$voice"
if [ "$mode" = approve ]; then
  echo "$final" | grep -q COMPLETE && [ "$has" -ge 1 ] && verdict 15 "PASS approve (voice=$voice): bought, goal continues" || verdict 15 "FAIL approve: $final"
else
  echo "$final" | grep -q CANCELLED && verdict 15 "PASS decline (voice=$voice)" || verdict 15 "FAIL decline: $final"
fi
