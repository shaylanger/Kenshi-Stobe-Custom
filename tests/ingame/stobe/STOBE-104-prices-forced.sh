#!/usr/bin/env bash
# id: STOBE-104-prices-forced
# covers: 104/119 buy and sell relationship pricing including higher/lower counter offers; 118 no premature payment
# fixture: auto-home test fixture; reset: fresh; needs: NEG_TEST_INJECT, relationship_trading.php item119
# verify: actual ledger terms at each boundary match runtime inventory value and production formula; r=-80 has
# no live contract, item transfer or cats delta. Inject only the model response to exercise the real chat/guard path.
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
preflight prices-forced  # shared setup check (Shay 2026-10-04)
NPC="Price Probe"
stobe-auto select "$PLAYER" >/dev/null
stobe-say speed 1 >/dev/null
heal_start "$PLAYER"
v=$(spawn_neutral "$NPC") || { verdict "prices-forced" "SETUP FAIL spawn"; exit 1; }
greet "$NPC"
stobe-auto give "$v" "Iron Hat" 1 >/dev/null
stobe-auto give "$PLAYER" "Iron Hat" 1 >/dev/null
stobe-auto money "$v" 30000 >/dev/null
stobe-auto money "$PLAYER" 30000 >/dev/null
inv_items() { stobe-auto inv "$1" | sed 's/^.* items=[0-9]* //'; }  # items JSON only (the prefix carries pos=, which moves)
value() { stobe-auto inv "$1" | python3 -c 'import json,sys; print(next((x.get("value_each",0) for x in (lambda s: json.loads(s.split(" items=",1)[1].split(" ",1)[1]))(sys.stdin.read()) if x["name"]=="Iron Hat"),0))'; }
nv=$(value "$v"); pv=$(value "$PLAYER")
[ "$nv" -gt 0 ] && [ "$pv" -gt 0 ] || { verdict "prices-forced" "SETUP FAIL inventory values npc=$nv player=$pv"; exit 1; }
for side in buy sell; do
  [ "$side" = buy ] && base=$nv || base=$pv
  for r in -80 -50 -10 0 10 56 100; do
    for asked in 300 1; do
      cancel_deals "$NPC"
      trust "$NPC" "$r" Neutral neutral >/dev/null 2>&1
      want=$(php -r "require '/var/www/html/StobeServer/lib/relationship_trading.php'; echo stobeRel$( [ "$side" = buy ] && echo Buy || echo Sell )Price($base,$r);")
      steps=$(python3 - "$side" "$asked" <<'PY'
import json,sys
side,asked=sys.argv[1],int(sys.argv[2])
payer,giver=("player","npc") if side=="buy" else ("npc","player")
print(json.dumps([{"action":"Talk","amount":0,"deal_decision":"COUNTER","deal_terms":[{"kind":"GIVE_CATS","by":payer,"to":giver,"amount":asked},{"kind":"GIVE_ITEM","by":giver,"to":payer,"item":"Iron Hat","quantity":1}],"message":f"{asked} cats for the Iron Hat."}]))
PY
)
      inject_on "prices-$side-$r-$asked" "$NPC" chat "$steps"
      before_player=$(money_of "$PLAYER"); before_npc=$(money_of "$v")
      if [ "$r" = -80 ]; then before_pi=$(inv_items "$PLAYER"); before_ni=$(inv_items "$v"); fi
      if [ "$side" = buy ]; then line="$NPC, I want to buy your Iron Hat. What is your price?"
      else line="$NPC, I want to sell you my Iron Hat. What will you pay?"; fi
      talk "$NPC" "$line" 25
      if [ "$(fired "prices-$side-$r-$asked")" -lt 1 ]; then
        verdict "price-$side-$r-$asked" "FAIL injected response never reached real chat path"
        continue
      fi
      row=$(deal_row "$NPC"); status=$(echo "$row" | cut -d'|' -f2)
      terms=$(echo "$row" | cut -d'|' -f5)
      after_player=$(money_of "$PLAYER"); after_npc=$(money_of "$v")
      if [ "$r" = -80 ]; then
        after_pi=$(inv_items "$PLAYER"); after_ni=$(inv_items "$v")
        if echo "$status" | grep -qE 'PROPOSED|COUNTERED|ACCEPTED|AWAITING_PERFORMANCE|COMPLETE'; then
          verdict "price-$side-$r-$asked" "FAIL no-trade gate recorded $status terms=$terms"
        elif [ "$before_player" = "$after_player" ] && [ "$before_npc" = "$after_npc" ] && [ "$before_pi" = "$after_pi" ] && [ "$before_ni" = "$after_ni" ]; then
          verdict "price-$side-$r-$asked" "PASS no live deal, inventory transfer or cats movement"
        else verdict "price-$side-$r-$asked" "FAIL moved without agreement: cats p=$before_player->$after_player n=$before_npc->$after_npc items_p=$([ "$before_pi" = "$after_pi" ] && echo same || echo changed) items_n=$([ "$before_ni" = "$after_ni" ] && echo same || echo changed)"; fi
      else
        got=$(python3 - "$side" "$terms" <<'PY'
import json,sys
by="player" if sys.argv[1]=="buy" else "npc"
try: print(sum(int(x.get("amount",0)) for x in json.loads(sys.argv[2]) if x.get("kind")=="GIVE_CATS" and x.get("by")==by))
except (ValueError,TypeError): print("invalid")
PY
)
        if [ "$got" = "$want" ] && echo "$status" | grep -qE 'PROPOSED|COUNTERED|ACCEPTED|AWAITING_PERFORMANCE|COMPLETE'; then
          verdict "price-$side-$r-$asked" "PASS ledger=$got formula=$want original=$asked status=$status"
        else verdict "price-$side-$r-$asked" "FAIL ledger=$got formula=$want original=$asked status=$status"; fi
      fi
    done
  done
done
cancel_deals "$NPC"
stobe-auto speed 0 >/dev/null
