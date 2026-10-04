#!/usr/bin/env bash
# id: STOBE-C31-C32-C45-C51-deal-guards
# covers: one-turn deal guards, each forced with NEG_TEST_INJECT on a spawned neutral "Varn Oddie":
#   31: a counter-offer with misquoted amounts ("Make it 400 now and 250 after" for recorded 300/200) -> rewritten,
#       log `Negotiation speech amounts differ ... rewritten`, wrong [400,250]
#   32: a REJECT that names her price ("2000 cats, or nothing") -> recorded as COUNTER (log `REJECT with her own price
#       recorded as COUNTER`)
#   45: an extra 0-Cats term -> dropped (log `0 Cats (item 45)`), deal recorded without it
#   51: she repeats Shay's offer, then names hers ("Fifty cats? Tell you what - eighty") -> no rewrite, COUNTERED 80
# usage: STOBE-C31-C32-C45-C51-deal-guards.sh 31|32|45|51|all
# fixture: auto-home (PLAYER/MATE env for others)
# reset: fresh (one launch is enough for all four; a fresh Varn per row)
# needs: StobeServer 2b2b52d+ (NEG_TEST_INJECT), harness on
# verify: per row the server log line above + the deal row in stobe_social_contract (status, terms), since the start.
# reliability: high (no model choice left)
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
rows="${1:-all}"; [ "$rows" = all ] && rows="31 32 45 51"
stobe-auto select ${PLAYER} >/dev/null
stobe-say speed 1 >/dev/null
PROMISE='{"kind":"PROMISE","by":"npc","text":"tell you where the nearest bar is"}'
NAMES=("Varn Oddie" "Tess Marrow" "Ollo Brine" "Dace Fennick"); n=0
for row in $rows; do
  NPC="${NAMES[$n]}"; n=$((n+1))
  log "$row: setup ($NPC)"
  v=$(spawn_neutral "$NPC") || { verdict "$row" "SETUP FAIL spawn"; continue; }
  sleep 4; greet "$NPC"
  case $row in
    31) inject_on 31 "$NPC" chat '[{"deal_decision":"COUNTER","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":300},{"kind":"GIVE_CATS","by":"player","to":"npc","amount":200,"when":"after_npc"},{"kind":"PROMISE","by":"npc","text":"tell you where the bandit camp is"}],"message":"Make it 400 now and 250 after, and I will tell you."}]'
        line="$NPC, I'll pay you 300 now and 200 after if you tell me where the bandit camp is." ;;
    32) inject_on 32 "$NPC" chat '[{"deal_decision":"REJECT","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":2000},{"kind":"PROMISE","by":"npc","text":"tell you a secret"}],"message":"Five? No. 2000 cats, or nothing."}]'
        line="$NPC, I'll pay you 5 cats to tell me a secret." ;;
    45) inject_on 45 "$NPC" chat "[{\"deal_decision\":\"ACCEPT\",\"deal_terms\":[{\"kind\":\"GIVE_CATS\",\"by\":\"player\",\"to\":\"npc\",\"amount\":100},{\"kind\":\"GIVE_CATS\",\"by\":\"npc\",\"to\":\"player\",\"amount\":0},$PROMISE],\"message\":\"Deal. 100 cats and I will tell you.\"}]"
        line="$NPC, I'll pay you 100 cats to tell me where the nearest bar is." ;;
    51) inject_on 51 "$NPC" chat '[{"deal_decision":"COUNTER","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":80},{"kind":"PROMISE","by":"npc","text":"sing you a song"}],"message":"Fifty cats? Tell you what - eighty, and I will sing."}]'
        line="$NPC, I'll pay you 50 cats to sing me a song." ;;
    *) verdict "$row" "SETUP FAIL unknown row"; continue ;;
  esac
  rw0=$(srv_count "Negotiation speech amounts differ from recorded terms")
  talk "$NPC" "$line"
  d=$(deal_row "$NPC"); st=$(echo "$d" | cut -d'|' -f2); terms=$(echo "$d" | cut -d'|' -f5)
  rw1=$(srv_count "Negotiation speech amounts differ from recorded terms")
  log "deal: $(echo "$d" | cut -c1-240)"
  npc_said "$NPC" | tail -2
  f=$(fired "$row")
  cancel_deals "$NPC"; put_away "$v"
  if [ "$f" -lt 1 ]; then verdict "$row" "INCONCLUSIVE switch never fired"; continue; fi
  case $row in
    31) w=$(srv_has "Negotiation speech amounts differ from recorded terms; rewritten" | tail -1 | grep -oE '"wrong":\[[^]]*\]')
        if [ "$st" = COUNTERED ] && echo "$w" | grep -q 400 && echo "$w" | grep -q 250 && echo "$terms" | grep -q '"amount": *300'; then
          verdict 31 "PASS misquoted counter rewritten ($w), COUNTERED 300/200"
        else verdict 31 "FAIL status=$st wrong=${w:-none}"; fi ;;
    32) c=$(srv_count "REJECT with her own price recorded as COUNTER")
        if [ "$c" -ge 1 ] && [ "$st" = COUNTERED ] && echo "$terms" | grep -q 2000; then verdict 32 "PASS REJECT with her price recorded as COUNTERED 2000"
        else verdict 32 "FAIL log=$c status=$st"; fi ;;
    45) c=$(srv_count "0 Cats (item 45)"); zero=$(echo "$terms" | grep -c -E '"amount": *0[,}]')
        if [ "$c" -ge 1 ] && [ "$zero" -eq 0 ] && echo "$st" | grep -q -E "ACCEPTED|AWAITING_PERFORMANCE|COMPLETE"; then verdict 45 "PASS 0-Cats term dropped, deal $st"
        else verdict 45 "FAIL log=$c zero_terms=$zero status=$st"; fi ;;
    51) if [ "$rw1" -eq "$rw0" ] && [ "$st" = COUNTERED ] && echo "$terms" | grep -q -E '"amount": *80'; then verdict 51 "PASS her reply kept (no rewrite), COUNTERED 80"
        else verdict 51 "FAIL rewrites=$((rw1-rw0)) status=$st"; fi ;;
  esac
done
stobe-auto speed 0 >/dev/null
