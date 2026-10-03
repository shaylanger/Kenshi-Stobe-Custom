#!/usr/bin/env bash
# id: STOBE-14-A3-buy-squin
# covers: STOBE 14 (she walks to a friendly trader and really buys) + A3 (the purchase event names the trader as
#         seller, never the buyer) with another squad
# fixture: Testing-Save-Squin (copy kah-squin); squad Beak + Kint
# reset: fresh load of the copy
# needs: KenshiFP E64B1BD5+, Stobe EF62563B+, harness 12F5CE0B+, server live
# usage: [PLAYER=Beak] [MATE=Kint] [TRADER="<name>"] [ITEM="<item>"] STOBE-14-A3-buy-squin.sh
#   Without TRADER/ITEM it picks the nearest trader (within 300 of <mate>) that is not a pack animal and sells an
#   unworn item for 1..400 cats (from `shopstock`, the game's own sale view), and that item.
# verify (VERDICT line + by hand):
#   - a BUY task goal for the item ends COMPLETE (stobe_task_goal.status);
#   - <mate>'s inventory gains the item and her cats drop (`money <mate> 0`);
#   - stobe.log `[EVENT] trade:` for that purchase names <trader> as the seller (A3), not <mate>/<player>.
# reliability: high for 14 (task goal), A3 is a log check
set -u
export PLAYER="${PLAYER:-Beak}" MATE="${MATE:-Kint}"
. "$(dirname "$0")/stobe-fight-lib.sh"
trap 'stobe-auto speed 0 >/dev/null 2>&1' EXIT
STK=/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe_task_goal.status
stobe-auto speed 0 >/dev/null; stobe-auto select "${PLAYER}" >/dev/null
log "traders near ${MATE}:"
TR=$(stobe-auto traders 300 near "${MATE}" | tr '|' '\n' | grep -E '#[0-9]+/[0-9]+')
echo "$TR" | cut -c1-160
pick_t=""; pick_i=""
if [ -n "${TRADER:-}" ] && [ -n "${ITEM:-}" ]; then pick_t="$TRADER"; pick_i="$ITEM"
else
  while read -r line; do
    name=$(echo "$line" | sed -E 's/^ *([^#]+) #.*/\1/; s/ +$//'); h=$(echo "$line" | grep -oE '#[0-9]+/[0-9]+')
    echo "$name" | grep -q -i -E 'spider|bull|garru|beak thing|goat|pack|dog|leviathan' && continue
    st=$(stobe-auto shopstock "$h"); echo "  shopstock $name: $(echo "$st" | cut -c1-240)"
    it=$(echo "$st" | grep -oE '\[[^]$]+ x[0-9]+ \$[0-9]+\]' | grep -v ' worn' | awk -F'[$\\]]' '{p=$2+0; if(p>=1 && p<=400) print $0}' | head -1 | sed -E 's/^\[(.+) x[0-9]+ \$[0-9]+\]$/\1/')
    [ -n "$it" ] && { pick_t="$name"; pick_i="$it"; break; }
  done <<< "$TR"
fi
[ -n "$pick_t" ] && [ -n "$pick_i" ] || { verdict 14-A3 "SETUP FAIL no trader with a cheap unworn item near ${MATE}"; exit 1; }
log "buy: '$pick_i' from '$pick_t'"
stobe-auto money "${MATE}" 1000 >/dev/null
c0=$(money_of "${MATE}"); i0=$(stobe-auto inv "${MATE}" | grep -c -F "\"name\":\"$pick_i\"")
before=$(cut -f1 "$STK" 2>/dev/null | sort); mark=$(grep -a -c "" "$L")
stobe-say speed 1 >/dev/null
stobe-say say "${MATE}" "${MATE}, go buy one $pick_i from $pick_t." --wait 25 >/dev/null 2>&1 || log "say failed"
stobe-auto speed 3 >/dev/null
row=""
for i in $(seq 1 45); do
  sleep 4
  id=$(comm -13 <(echo "$before") <(cut -f1 "$STK" 2>/dev/null | sort) | head -1)
  [ -n "$id" ] && row=$(grep -a "^$id" "$STK" | tr '\t' '|' | cut -c1-240)
  echo "$row" | grep -q -E "COMPLETE|BLOCKED|CANCELLED|WAITING_APPROVAL" && break
done
stobe-auto speed 0 >/dev/null
c1=$(money_of "${MATE}"); i1=$(stobe-auto inv "${MATE}" | grep -c -F "\"name\":\"$pick_i\"")
trade=$(tail -n +"$mark" "$L" | grep -a "\[EVENT\] trade:" | tail -3)
log "task: ${row:-none}; ${MATE} cats $c0 -> $c1, '$pick_i' stacks $i0 -> $i1"; echo "$trade" | cut -c1-260
seller_ok=0; echo "$trade" | grep -a -q -F "$pick_t" && seller_ok=1
echo "$trade" | grep -a -q -E "from (${MATE}|${PLAYER})\b" && seller_ok=0
if echo "$row" | grep -q COMPLETE && [ "$c1" -lt "$c0" ] && [ "$seller_ok" = 1 ]; then verdict 14-A3 "PASS bought '$pick_i' from $pick_t, event names the seller"
elif echo "$row" | grep -q COMPLETE && [ "$c1" -lt "$c0" ]; then verdict 14-A3 "PASS 14 / FAIL A3: trade event doesn't name $pick_t as seller"
else verdict 14-A3 "FAIL ${row:-no task goal} cats $c0 -> $c1"; fi
