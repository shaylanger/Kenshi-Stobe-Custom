#!/usr/bin/env bash
# id: STOBE-102-104-relationship-trading
# covers: STOBE 102 (weapon guard at r 69/70, squadmate + surrender exempt), 103 (willingness edges: pay-later -1/0,
#         free favour 29/30, free item 55/56, no trade -80), 104 (deal prices at -80/-50/-10/0/+10/+56/+100)
# fixture: auto-home (any: PLAYER/MATE env)
# reset: fresh before each mode (`bash /mnt/c/KenshiModding/tools/automation/scenarios.sh fresh`)
# needs: StobeServer 1c2457f+ (items 102-104), Stobe EF62563B+, harness C2929739+
# usage: STOBE-102-104-relationship-trading.sh <mode>
#   modes: weapon69 weapon70 weapon-squad weapon-surrender paylater favour gift notrade prices
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
      notrade) lo=-80; hi=-79; stobe-auto give "$V" Bread 2 >/dev/null; line="${NAME%% *}, sell me one of your bread for 20 cats."; rule="no trade" ;;
    esac
    set_r "$lo"; out_lo=$(ask "$line")
    set_r "$hi"; out_hi=$(ask "$line")
    ref_lo=$(echo "$out_lo" | grep -a -c "refused by relationship: $rule"); ref_hi=$(echo "$out_hi" | grep -a -c "refused by relationship: $rule")
    terms_lo=$(echo "$out_lo" | grep -a -c -E "Negotiation contract recorded|refused by relationship")
    if [ "$ref_lo" -ge 1 ] && [ "$ref_hi" -eq 0 ]; then verdict "$mode" "PASS refused at r=$lo, not at r=$hi"
    elif [ "$terms_lo" -eq 0 ]; then verdict "$mode" "INCONCLUSIVE no deal terms at r=$lo (model answered without a deal)"
    else verdict "$mode" "FAIL refusals r=$lo:$ref_lo r=$hi:$ref_hi"; fi ;;
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
  *) echo "unknown mode $mode"; exit 2 ;;
esac
heal_stop; stobe-auto speed 0 >/dev/null
[ -n "${V:-}" ] && stobe-auto teleport "$V" ${PLAYER} dist 300 >/dev/null 2>&1 || true
