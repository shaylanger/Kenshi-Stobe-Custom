#!/usr/bin/env bash
# id: STOBE-15-buy-approval-squin
# covers: STOBE 15 (WAITING_APPROVAL; approve -> she buys, decline -> cancelled) with another squad in Squin
# fixture: Testing-Save-Squin (copy kah-squin); squad Beak + Kint
# reset: fresh load of the copy, once per mode
# needs: KenshiFP B1F468C8+ (item 99c), Stobe EF62563B+, harness 12F5CE0B+ (power supply)
# usage: [PLAYER=Beak] [MATE=Kint] [TRADER="<name>"] STOBE-15-buy-approval-squin.sh approve|decline
# Chain: Basic First Aid Kit = Fabrics at a Basic Medical Workbench. Squin has no player bench, so one is built 15 m
#   from <mate> (+ `power ... supply`, research); Fabrics have no producer, so the planner's purchase fallback asks
#   the nearest trader within 220 m of <mate> that stocks them (item 99b). TRADER: a Squin trader that already sells
#   Fabrics (found with `shopstock`), else the nearest non-animal trader, who is given 5 Fabrics; either way the
#   trader is brought 30 m from <mate>.
# verify: as STOBE-15-buy-approval.sh (WAITING_APPROVAL `buy-...Fabrics` row; approve -> COMPLETE + Fabrics in her
#   inventory; decline -> CANCELLED), plus KenshiFP.log `BUY_FALLBACK ... Fabrics: <trader> (N away) sells it for Q`.
set -u
export PLAYER="${PLAYER:-Beak}" MATE="${MATE:-Kint}" BUILD_BENCH=1
if [ -z "${TRADER:-}" ]; then
  TR=$(stobe-auto traders 600 near "${MATE}" | sed -E 's/^ *[0-9]+ traders? within [0-9.]+: *//' | tr '|' '\n' | grep -E '#[0-9]+/[0-9]+')
  first=""
  while read -r line; do
    name=$(echo "$line" | sed -E 's/^ *([^#]+) #.*/\1/; s/ +$//'); h=$(echo "$line" | grep -oE '#[0-9]+/[0-9]+')
    echo "$name" | grep -q -i -E 'spider|bull|garru|beak thing|goat|pack|dog|leviathan' && continue
    [ -z "$first" ] && first="$name"
    if stobe-auto shopstock "$h" | grep -q "Fabrics"; then TRADER="$name"; echo "trader selling Fabrics: $name"; break; fi
  done <<< "$TR"
  TRADER="${TRADER:-$first}"
fi
[ -n "${TRADER:-}" ] || { echo "VERDICT 15-squin: SETUP FAIL no trader within 600 of ${MATE}"; exit 1; }
export TRADER
echo "trader: $TRADER"
exec bash "$(dirname "$0")/STOBE-15-buy-approval.sh" "${1:-approve}"
