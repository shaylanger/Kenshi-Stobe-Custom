#!/usr/bin/env bash
# id: STOBE-102-104-relationship-trading
# covers: STOBE 102 (weapon guard at r 69/70, squadmate + surrender exempt), 103 (willingness edges: pay-later -1/0,
#         free favour 29/30, free item 55/56, no trade -80), 104 (deal prices at -80/-50/-10/0/+10/+56/+100)
# fixture: auto-home (any: PLAYER/MATE env)
# reset: fresh before each mode (`bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh`)
# needs: StobeServer 1c2457f+ (items 102-104), Stobe EF62563B+, harness C2929739+
# usage: STOBE-102-104-relationship-trading.sh <mode>
#   modes: weapon69 weapon70 weapon-squad weapon-surrender paylater favour gift notrade prices
#          shop-prices shop-floor shop-block   (Stobe.dll shop-price hook, items 103/104; need Stobe 13A097D5+)
# shop-* modes: Vel is the shopkeeper (the hook prices any non-squad seller; a real trader's window is a Shay row).
#   Purchases go through the game's Inventory::buyItem (harness `trade`); `stobe_shopprice` refetches r after each
#   trust change. Truth = cats moved + stobe.log "SHOP_PRICE:" lines (vanilla_buy/vanilla_sell/price per item).
#   shop-prices: r in -79 -50 -10 0 10 56 100: player buys ITEM (default Hashish); paid == logged price ==
#     the formula with the floor (python mirror of ShopPricing::Adjust), logged vanilla_buy == harness "(price P)".
#   shop-floor: at r 10, 56, 100 the player buys ITEM then sells it straight back (r raised by +5 in between at 56):
#     no loop profits (sold_for <= paid; equal only for items the game itself buys and sells at one price).
#   shop-block: r=-80: purchase and sale both refused ("SHOP_PRICE: blocked", harness "buyItem refused"; the harness
#     then sells by hand at vanilla: that is its own fallback, not the game path); r=-79: buyItem goes through.
#   REAL_TRADER=1: the shopkeeper is a spawned isATrader (Skeleton Traders), so purchases go through the
#     ShopTrader (trade window) object like a GUI purchase (reply "from <trader> trade window"); needs Stobe
#     E45BFB0E+ and harness 7778508+. Default (Vel, not a trader) uses the harness's plain-inventory path.
# How: a neutral Drifter renamed "Vel Harrow" (12 m away, so the squad leaves him alone) gets a server profile
#   (greeting), then his relationship to the player is set with scenarios.sh trust (the live map the server reads),
#   then the player asks. Server truth (stobeserver.log since the start + negotiation_admin deals) decides, never his words.
# verify per mode (VERDICT lines):
#   weapon69: "Weapon hand-over blocked" / "would give up her weapon" logged, his weapon still equipped (`inv`).
#   weapon70: no such block line (whether he agrees is his choice; a recorded deal/handover is fine).
#   weapon-squad: "<mate>, drop your weapon." -> no block line for <mate> (squad exempt).
#   weapon-surrender: a raider's own surrender deal with "drop your weapon": no block line for him.
#   paylater: r=-1 -> "refused by relationship: pay-later"; r=0 -> no refusal line for pay-later.
#   favour: r=29 -> "refused by relationship: free favours"; r=30 -> none.
#   gift: r=55 -> "free items/Cats"; r=56 -> none.
#   notrade: r=-80 -> "refused by relationship: no trade"; r=-79 -> none.
#   prices: he holds an Iron Hat (value from `inv`); for each r in -50 -10 0 10 56 100 the player offers 1 cat; the
#     recorded deal (COUNTER/ACCEPT) has the player's GIVE_CATS = stobeRelBuyPrice(value, r) (computed with the
#     server's own lib), and "Deal price set by relationship" is logged. A NONE decision (no terms) = INCONCLUSIVE.
# reliability: the server lines are deterministic once the model proposes/accepts terms; the model may answer
#   without terms (INCONCLUSIVE, rerun).
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
mode="${1:?mode}"
SRVLIB=/var/www/html/StobeServer/lib/relationship_trading.php
NAME="Vel Harrow"
srv_since() { since_srv | grep -a -F "$1"; }
make_vel() {
  out=$(stobe-auto spawn "Hungry Bandit" Drifters near ${PLAYER} dist 12 count 1)
  V=$(echo "$out" | grep -oE '#[0-9]+/[0-9]+' | head -1); [ -n "$V" ] || { verdict "$mode" "SETUP FAIL spawn: $out"; exit 1; }
  stobe-auto setname "$V" "$NAME" >/dev/null
  stobe-say speed 1 >/dev/null
  stobe-say say "$NAME" "Hello there, ${NAME%% *}." >/dev/null 2>&1; sleep 15
}
set_r() { trust "$NAME" "$1" Neutral neutral >/dev/null 2>&1; log "$NAME -> ${PLAYER} r set to $1"; }
ask() { local m; m=$(grep -a -c "" "$SRV"); stobe-say say "$NAME" "$1" >/dev/null 2>&1; sleep 25; tail -n +"$m" "$SRV"; }
weapon_of() { stobe-auto inv "$1" | grep -oE '"name":"[^"]+","count":1,"equipped":true' | sed -E 's/"name":"([^"]+)".*/\1/' \
  | grep -i -E 'katana|sabre|saber|sword|machete|cleaver|blade|knife|dagger|club|mace|hammer|axe|plank|stick|naginata|spear|staff|bow' | head -1; }
stobe-auto speed 0 >/dev/null; stobe-auto select ${PLAYER} >/dev/null
heal_start ${PLAYER}
case "$mode" in
  weapon69|weapon70)
    make_vel; r=${mode#weapon}; set_r "$r"
    w=$(weapon_of "$V"); [ -n "$w" ] || { verdict "$mode" "SETUP FAIL $NAME has no equipped weapon"; exit 1; }
    out=$(ask "${NAME%% *}, I'll give you 300 cats for your $w. Hand it over.")
    blocked=$(echo "$out" | grep -a -c -E "Weapon hand-over blocked|would give up her weapon")
    still=$(stobe-auto inv "$V" | grep -c -F "\"name\":\"$w\",\"count\":1,\"equipped\":true")
    if [ "$r" = 69 ]; then
      [ "$blocked" -ge 1 ] && [ "$still" -ge 1 ] && verdict "$mode" "PASS blocked at r=69, $w still equipped" \
        || verdict "$mode" "$( [ "$still" -ge 1 ] && echo INCONCLUSIVE no weapon terms proposed, $w kept || echo FAIL weapon left at r=69 )"
    else
      [ "$blocked" -eq 0 ] && verdict "$mode" "PASS no block at r=70 (weapon equipped now: $still)" || verdict "$mode" "FAIL blocked at r=70"
    fi ;;
  weapon-squad)
    w=$(weapon_of "${MATE}"); [ -n "$w" ] || { verdict "$mode" "SETUP FAIL ${MATE} has no equipped weapon"; exit 1; }
    m=$(grep -a -c "" "$SRV"); stobe-say say "${MATE}" "${MATE}, put your $w down. Drop it." >/dev/null 2>&1; sleep 25
    blocked=$(tail -n +"$m" "$SRV" | grep -a -c -E "Weapon hand-over blocked|would give up her weapon")
    [ "$blocked" -eq 0 ] && verdict "$mode" "PASS no block for the squadmate" || verdict "$mode" "FAIL squadmate blocked" ;;
  weapon-surrender)
    park_malzin 600
    r=$(spawn_raiders 1 | head -1); [ -n "$r" ] || { verdict "$mode" "SETUP FAIL no raider"; exit 1; }
    engage "$r" || log "warning: no combat_start seen"; n=$(name_of "$r")
    stobe-auto health "$r" 25 >/dev/null
    m=$(grep -a -c "" "$SRV")
    wait_deal "$n" "PROPOSED|COUNTERED" 60 >/dev/null || log "no offer from $n"
    say_to "$r" "$n" "$n, drop your weapon and I'll spare you."
    blocked=$(tail -n +"$m" "$SRV" | grep -a -F "$n" | grep -a -c -E "Weapon hand-over blocked|would give up her weapon")
    [ "$blocked" -eq 0 ] && verdict "$mode" "PASS no block for a surrendering NPC ($(deal_line "$n" | awk -F '  ' '{print $3}'))" || verdict "$mode" "FAIL surrender blocked" ;;
  paylater|favour|gift|notrade)
    make_vel
    case "$mode" in
      paylater) lo=-1; hi=0; stobe-auto give "$V" Bread 2 >/dev/null; line="${NAME%% *}, give me one of your bread now and I'll pay you 20 cats tomorrow."; rule="pay-later" ;;
      favour) lo=29; hi=30; line="${NAME%% *}, would you bandage my arm for me, for free? I'm hurt."; rule="free favours" ;;
      gift) lo=55; hi=56; stobe-auto give "$V" Bread 2 >/dev/null; line="${NAME%% *}, could you just give me one of your bread? I've nothing to pay with."; rule="free items" ;;
      notrade) lo=-80; hi=-79; stobe-auto give "$V" Bread 2 >/dev/null; line="${NAME%% *}, sell me one of your bread. I'll pay you 200 cats for it, more than it's worth."; rule="no trade" ;;
    esac
    set_r "$lo"; out_lo=$(ask "$line")
    set_r "$hi"; out_hi=$(ask "$line")
    ref_lo=$(echo "$out_lo" | grep -a -c "refused by relationship: $rule"); ref_hi=$(echo "$out_hi" | grep -a -c "refused by relationship: $rule")
    # m19: judge what really happened (an item/cats moved, a deal agreed, or for favours a heal/roleplay of it),
    # not only the server guard line: a refusal by the model itself is a refusal too.
    extra=""; [ "$mode" = favour ] && extra="|${NAME}: action command received: (ROLEPLAY_ACTION|FIRST_AID[A-Z_]*|HEAL[A-Z_]*)@"
    moved(){ echo "$1" | grep -a -c -E "${NAME}: action command received: (GIVE_ITEM|GIVE_CATS)@|Voice hand-over dispatched|\"npc\":\"${NAME}\",\"decision\":\"(ACCEPT|COUNTER|PROPOSE)\"${extra}"; }
    mv_lo=$(moved "$out_lo"); mv_hi=$(moved "$out_hi")
    log "r=$lo: guard=$ref_lo moved/agreed=$mv_lo | r=$hi: guard=$ref_hi moved/agreed=$mv_hi"
    if [ "$mv_lo" -eq 0 ] && [ "$mv_hi" -ge 1 ]; then verdict "$mode" "PASS refused at r=$lo (guard lines $ref_lo), went ahead at r=$hi"
    elif [ "$mv_lo" -ge 1 ]; then verdict "$mode" "FAIL agreed/gave at r=$lo ($rule needs more)"
    else verdict "$mode" "INCONCLUSIVE refused at r=$lo, but the model refused at r=$hi too (allowed side not shown)"; fi ;;
  prices)
    make_vel
    stobe-auto give "$V" "Iron Hat" 1 >/dev/null
    val=$(stobe-auto inv "$V" | grep -oE '"name":"Iron Hat","count":1,"equipped":(true|false),"item_id":"[^"]*","value_each":[0-9]+' | grep -oE '[0-9]+$' | head -1)
    [ -n "$val" ] || { verdict "$mode" "SETUP FAIL no Iron Hat value"; exit 1; }
    log "Iron Hat value $val"
    for r in -80 -50 -10 0 10 56 100; do
      set_r "$r"
      out=$(ask "${NAME%% *}, I'll buy your Iron Hat. One cat, take it or leave it.")
      want=$(php -r "require '$SRVLIB'; echo stobeRelBuyPrice($val, $r);")
      if [ "$r" = -80 ]; then
        echo "$out" | grep -a -q "refused by relationship: no trade" && verdict "prices r=$r" "PASS no trade" || verdict "prices r=$r" "FAIL/INCONCLUSIVE no no-trade refusal"
        continue
      fi
      id=$(deal_id "$NAME" "COUNTERED|ACCEPTED|PROPOSED")
      got=$( [ -n "$id" ] && deal_block "$id" | awk '$1=="player" && $2=="GIVE_CATS"{print $3}' | head -1)
      if [ -n "$got" ] && [ "$got" = "$want" ]; then verdict "prices r=$r" "PASS player pays $got (formula $want)"
      elif [ -z "$id" ]; then verdict "prices r=$r" "INCONCLUSIVE no deal recorded (want $want)"
      else verdict "prices r=$r" "FAIL recorded ${got:-?}, formula $want"; fi
      # close the open deal before the next price
      [ -n "$id" ] && (cd /tmp && sudo -u postgres psql -d stobe -Atc "UPDATE stobe_social_contract SET status='CANCELLED', consequences_applied=TRUE, resolved_at=NOW() WHERE contract_id='$id'" >/dev/null)
    done ;;
  shop-prices|shop-floor|shop-block)
    ITEM="${ITEM:-Hashish}"
    if [ "${REAL_TRADER:-0}" = 1 ]; then
      # A real shopkeeper (isATrader): harness `trade` buys through the game's trade window object (ShopTrader,
      # harness 7778508+), the path a GUI purchase takes; the hook maps the ShopTrader to her (Stobe E45BFB0E+).
      out=$(stobe-auto spawn "Skeleton Traders Animals" "Traders Guild" near ${PLAYER} dist 140)
      ts=$(stobe-auto traders 300 | grep -oE '#[0-9]+/[0-9]+')
      V=""; for s in $(echo "$out" | grep -oE '#[0-9]+/[0-9]+'); do echo "$ts" | grep -qxF "$s" && { V=$s; break; }; done
      [ -n "$V" ] || { verdict "$mode" "SETUP FAIL no isATrader in the spawned squad: $out"; exit 1; }
      stobe-auto teleport "$V" ${PLAYER} dist 12 >/dev/null; stobe-auto setname "$V" "$NAME" >/dev/null
      stobe-say speed 1 >/dev/null; stobe-say say "$NAME" "Hello there, ${NAME%% *}." >/dev/null 2>&1; sleep 15
      log "real trader $V renamed $NAME"
    else
      make_vel
    fi
    stobe-auto money ${PLAYER} 60000 >/dev/null; stobe-auto money "$V" 60000 >/dev/null
    shop_r() {  # set r, make the hook refetch it, wait for the SHOP_PRICE r line
      set_r "$1"
      stobe-auto stobe_shopprice "$NAME" ${PLAYER} >/dev/null 2>&1; sleep 3
      log "hook cache: $(stobe-auto stobe_shopprice "$NAME" ${PLAYER} 2>&1 | head -1)"; sleep 2
    }
    buy() {  # player buys ITEM from Vel; prints "paid logged_vb logged_vs logged_price harness_price reply"
      stobe-auto give "$V" "$ITEM" 1 >/dev/null
      local m b a out lp
      m=$(grep -a -c "" "$L"); b=$(money_of ${PLAYER})
      out=$(stobe-auto trade ${PLAYER} "$V" "$ITEM" 2>&1); sleep 1; a=$(money_of ${PLAYER})
      lp=$(tail -n +"$m" "$L" | grep -a "SHOP_PRICE: player buys" | tail -1)
      local vb vs p hp
      vb=$(echo "$lp" | grep -oE 'vanilla_buy=[0-9]+' | cut -d= -f2); vs=$(echo "$lp" | grep -oE 'vanilla_sell=[0-9]+' | cut -d= -f2)
      p=$(echo "$lp" | grep -oE ' price=[0-9]+' | cut -d= -f2); hp=$(echo "$out" | grep -oE '\(price [0-9]+\)' | grep -oE '[0-9]+')
      echo "$((b - a)) ${vb:--} ${vs:--} ${p:--} ${hp:--} | $out"
    }
    sell() {  # Vel buys ITEM from the player; prints "gained logged_price | reply"
      local m b a out lp
      m=$(grep -a -c "" "$L"); b=$(money_of ${PLAYER})
      out=$(stobe-auto trade "$V" ${PLAYER} "$ITEM" 2>&1); sleep 1; a=$(money_of ${PLAYER})
      lp=$(tail -n +"$m" "$L" | grep -a "SHOP_PRICE: player sells" | tail -1)
      local p; p=$(echo "$lp" | grep -oE ' price=[0-9]+' | cut -d= -f2); echo "$((a - b)) ${p:--} | $out"
    }
    expect() {  # expect <vb> <vs> <r>: "buy sell" from ShopPricing::Adjust (python mirror, default constants)
      python3 - "$@" <<'PY'
import sys, math
vb, vs, r = int(sys.argv[1]), int(sys.argv[2]), max(-100, min(100, int(sys.argv[3])))
def shape(m, e): return m * (abs(r) / 100.0) ** e
bf = 1 - shape(0.30, 1.1) if r > 0 else (1 + shape(10.0, 2.32) if r < 0 else 1.0)
sf = 1 + shape(0.10, 1.1) if r > 0 else (max(0.0, 1 - shape(0.90, 2.32)) if r < 0 else 1.0)
rnd = lambda v: 0 if v <= 0 else min(100000000, int(math.floor(v + 0.5)))
if r == 0 or (vb <= 0 and vs <= 0): print(vb, vs); sys.exit()
b0, s0 = max(vb, 0), max(vs, 0)
sell, buy = rnd(s0 * sf), rnd(b0 * bf)
if b0 > 0:
    buy = max(buy, sell + 1, s0)
    if r > 0 and buy > b0:
        buy = b0
        if sell >= buy:
            sell = buy - 1
            if sell < s0 <= buy: sell = s0
print(buy, sell)
PY
    }
    case "$mode" in
      shop-prices)
        for r in -79 -50 -10 0 10 56 100; do
          shop_r "$r"; res=$(buy); set -- ${res%%|*}; paid=$1 vb=${2:-} vs=${3:-} lp=${4:-} hp=${5:-}
          log "r=$r buy: $res"
          if [ "$r" = 0 ]; then
            [ "$paid" = "$hp" ] && verdict "shop-prices r=0" "PASS paid $paid = vanilla" || verdict "shop-prices r=0" "FAIL paid $paid, vanilla $hp"
            continue
          fi
          [ "$lp" != - ] || { verdict "shop-prices r=$r" "FAIL no SHOP_PRICE line (paid $paid, vanilla $hp): ${res#*|}"; continue; }
          want=$(expect "$vb" "$vs" "$r" | awk '{print $1}')
          if [ "$paid" = "$lp" ] && [ "$lp" = "$want" ] && [ "$vb" = "$hp" ]; then
            verdict "shop-prices r=$r" "PASS paid $paid (vanilla $vb, trader pays $vs, formula $want)"
          else verdict "shop-prices r=$r" "FAIL paid $paid logged $lp formula $want vanilla log $vb harness $hp"; fi
        done ;;
      shop-floor)
        for r in 10 56 100; do
          shop_r "$r"; res=$(buy); paid=${res%% *}
          [ "$r" = 56 ] && shop_r 61
          s=$(sell); got=${s%% *}
          log "r=$r paid $paid, sold back for $got ($s)"
          if [ "$got" -le "$paid" ] 2>/dev/null; then verdict "shop-floor r=$r" "PASS no loop profit: loses $((paid - got)) (paid $paid, sold $got; 0 only when the game itself buys = sells)"
          else verdict "shop-floor r=$r" "FAIL loop profit/even: paid $paid sold $got"; fi
        done ;;
      shop-block)
        shop_r -80; m=$(grep -a -c "" "$L")
        res=$(buy); s=$(sell)
        blocked=$(tail -n +"$m" "$L" | grep -a -c "SHOP_PRICE: blocked")
        refused=$(echo "$res $s" | grep -a -o "buyItem refused" | wc -l)
        [ "$blocked" -ge 2 ] && [ "$refused" -ge 2 ] && verdict "shop-block r=-80" "PASS purchase + sale refused (blocked lines $blocked)" \
          || verdict "shop-block r=-80" "FAIL blocked lines $blocked, harness refusals $refused | $res | $s"
        shop_r -79; m=$(grep -a -c "" "$L"); res=$(buy)
        blocked=$(tail -n +"$m" "$L" | grep -a -c "SHOP_PRICE: blocked")
        [ "$blocked" -eq 0 ] && ! echo "$res" | grep -q "buyItem refused" && verdict "shop-block r=-79" "PASS purchase went through (paid ${res%% *})" \
          || verdict "shop-block r=-79" "FAIL blocked at -79 | $res" ;;
    esac ;;
  *) echo "unknown mode $mode"; exit 2 ;;
esac
heal_stop; stobe-auto speed 0 >/dev/null
[ -n "${V:-}" ] && stobe-auto teleport "$V" ${PLAYER} dist 300 >/dev/null 2>&1 || true
