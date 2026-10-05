#!/usr/bin/env bash
# id: STOBE-NPCPANEL
# covers: NPC info panel (Stobe DAF1390F+, StobeServer 2596ef2+): open/target switch/close, no LLM call on
#         open/refresh, relationship of the SPEAKING character, hidden backstory, disclosed fact recorded from a
#         real chat turn and kept over save+reload, renamed NPC keeps its info, deal states (in progress,
#         outstanding payment, deadline, broken), agreed goal status matches the goal row.
# fixture: Crafting base (Shay + Malzin, Apothecary Abia in town), on a kah-* copy
# usage: bash STOBE-NPCPANEL.sh [rows]   rows = space list of NP1..NP8 (default all)
# verify: one RESULT line per row; panel text is read back through `stobe_npcinfo read` (what the window shows).
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
ROWS="${1:-NP1 NP2 NP3 NP4 NP5 NP6 NP7 NP8}"
want() { case " $ROWS " in *" $1 "*) return 0 ;; esac; return 1; }
PSQLQ() { (cd /tmp && sudo -u postgres psql -d stobe -At -c "$1" 2>/dev/null); }
TRADER="${TRADER:-Apothecary Abia}"
CTX=/var/www/html/StobeServer/log/context_sent_to_llm.log

serial_of() { stobe-auto where "$1" 2>/dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#'; }
pread() { stobe-auto stobe_npcinfo read 2>/dev/null | tail -1; }
popen() { stobe-auto stobe_npcinfo open "$@" 2>/dev/null | tail -1; }
# pwait <serial> [speaker]: wait until the panel shows a loaded reply for that key; prints the read line
pwait() {
  local r i k="$1|${2:-}"
  for i in $(seq 1 25); do r=$(pread); case "$r" in *"key=$k "*"loaded=1"*) echo "$r"; return 0 ;; esac; sleep 1; done
  echo "$r"; return 1
}
ptext() { sed -E 's/^.* text=//'; }
llm_count() { echo "$(PSQLQ "SELECT COUNT(*) FROM audit_llm")/$(wc -l < "$CTX" 2>/dev/null || echo 0)"; }

stobe-auto select "$PLAYER" >/dev/null
TS=$(serial_of "$TRADER"); MS=$(serial_of "$MATE")
[ -n "$TS" ] && [ -n "$MS" ] || setup_fail NPCPANEL "no $TRADER/$MATE serial (trader=$TS mate=$MS)"
log "trader $TRADER #$TS, mate $MATE #$MS"

if want NP1; then # open + content + no LLM call while open/refreshing (game paused: no bored/autonomy chatter)
  stobe-auto speed 0 >/dev/null; sleep 2
  c0=$(llm_count)
  popen "$TRADER" >/dev/null; r=$(pwait "$TS" "$PLAYER"); t=$(echo "$r" | ptext)
  stobe-auto stobe_npcinfo refresh >/dev/null; sleep 3; stobe-auto stobe_npcinfo refresh >/dev/null; sleep 12
  c1=$(llm_count)
  miss=""
  for s in "$TRADER" "Faction: " "Occupation: Trader (seen trading)" "DEALS WITH ${PLAYER^^}" "ACTIVITY" "Doing now: " \
           "RELATIONSHIP WITH ${PLAYER^^}" "WHAT ${PLAYER^^} KNOWS"; do
    echo "$t" | grep -q -F -- "$s" || miss="$miss [$s]"
  done
  echo "$t" | grep -q -F "Doing now: not visible" && miss="$miss [live activity missing]"
  if [ -z "$miss" ] && [ "$c0" = "$c1" ]; then verdict NP1 "PASS opened for $TRADER key=$TS|$PLAYER, all sections, llm audit/ctx $c0 -> $c1"
  else verdict NP1 "FAIL missing:$miss llm $c0 -> $c1 text: ${t:0:300}"; fi
  stobe-auto speed 1 >/dev/null
fi

if want NP2; then # target switch drops the older reply; close button closes
  popen "$MATE" >/dev/null; popen "$TRADER" >/dev/null
  r=$(pwait "$TS" "$PLAYER"); t=$(echo "$r" | ptext)
  first=$(echo "$t" | sed 's/ | .*//')
  sleep 4; r2=$(pread)
  stobe-auto click Stobe_NpcPanelCloseBtn >/dev/null 2>&1; sleep 2; c=$(pread)
  if echo "$r2" | grep -q "key=$TS|$PLAYER " && [ "$first" = "$TRADER" ] && [ "$c" = "open=0" ]; then
    verdict NP2 "PASS switch $MATE->$TRADER shows $TRADER (key $TS), close button -> $c; $(since_stobe | grep -a -c 'NPC_PANEL: dropped stale') stale replies dropped"
  else verdict NP2 "FAIL after switch first line '$first' read='${r2:0:120}' after close='$c'"; fi
fi

if want NP3; then # relationship is the speaking character's
  bash "$SC" trust "$TRADER" 60 Fond friend >/dev/null 2>&1
  PSQLQ "UPDATE core_npc_master SET extended_data = extended_data #- '{relationships,$MATE}' WHERE lower(name)=lower('$TRADER')" >/dev/null
  popen "$TRADER" "$PLAYER" >/dev/null; a=$(pwait "$TS" "$PLAYER" | ptext)
  popen "$TRADER" "$MATE" >/dev/null; b=$(pwait "$TS" "$MATE" | ptext)
  ra=$(echo "$a" | grep -oE "RELATIONSHIP WITH ${PLAYER^^} \| [^|]*"); rb=$(echo "$b" | grep -oE "RELATIONSHIP WITH ${MATE^^} \| [^|]*")
  if echo "$ra" | grep -q "Fond (friend)" && echo "$rb" | grep -q "No opinion of $MATE yet"; then
    verdict NP3 "PASS $ra / $rb"
  else verdict NP3 "FAIL as $PLAYER: '$ra' as $MATE: '$rb'"; fi
fi

if want NP4; then # stored backstory/goals/bio never shown
  popen "$TRADER" "$PLAYER" >/dev/null; t=$(pwait "$TS" "$PLAYER" | ptext)
  hidden=$(PSQLQ "SELECT concat_ws(E'\n', backstory, goals, occupation, personality) FROM core_npc WHERE metadata->>'storage_id'='hand_$TS' ORDER BY updated_at DESC LIMIT 1")
  leak=$(PANEL="$t" HID="$hidden" python3 - <<'PY'
import os, re
t = os.environ['PANEL'].lower(); h = os.environ['HID'].lower()
words = re.findall(r"[a-z']+", h)
hits = [' '.join(words[i:i+5]) for i in range(0, max(0, len(words) - 4)) if ' '.join(words[i:i+5]) in t]
print(len(words), len(hits), hits[:2])
PY
)
  nw=$(echo "$leak" | awk '{print $1}'); nh=$(echo "$leak" | awk '{print $2}')
  if [ "${nw:-0}" -gt 20 ] && [ "$nh" = 0 ]; then verdict NP4 "PASS 0 of the stored bio's 5-word runs appear (bio $nw words)"
  elif [ "${nw:-0}" -le 20 ]; then verdict NP4 "INCONCLUSIVE no stored bio for $TRADER (words=$nw)"
  else verdict NP4 "FAIL bio text shown: $leak"; fi
fi

if want NP5; then # disclosed fact from a real chat turn, shown, kept over save + reload
  f0=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER')")
  stobe-auto teleport "$PLAYER" "$TRADER" dist 3 >/dev/null
  talk "$TRADER" "Tell me about yourself. Where did you grow up, and what work did you do before you ended up here?" 25
  f1=$f0
  for i in $(seq 1 20); do f1=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER')"); [ "${f1:-0}" -gt "${f0:-0}" ] && break; sleep 3; done
  said=$(since_stobe | grep -a -F "NPC_SAY: $TRADER|" | tail -1 | sed -E "s/.*NPC_SAY: $TRADER\|([0-9]+: )?//" | cut -c1-220)
  fact=$(PSQLQ "SELECT fact FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER') ORDER BY id DESC LIMIT 1")
  if [ "${f1:-0}" -le "${f0:-0}" ]; then
    verdict NP5 "FAIL no fact recorded (facts $f0 -> $f1); reply: $said; srv: $(since_srv | grep -a -E 'NPC_FACTS|Relationship evaluation|relationship_eval' | tail -2 | cut -c1-200)"
  else
    popen "$TRADER" "$PLAYER" >/dev/null; t=$(pwait "$TS" "$PLAYER" | ptext)
    stobe-auto save kah-npcpanel-r >/dev/null; sleep 5
    stobe-auto load kah-npcpanel-r >/dev/null; sleep 5; timeout 300 stobe-auto wait-world >/dev/null 2>&1
    TS2=""; for i in $(seq 1 15); do TS2=$(serial_of "$TRADER"); [ -n "$TS2" ] && break; sleep 2; done
    popen "$TRADER" "$PLAYER" >/dev/null; r2=$(pwait "${TS2:-$TS}" "$PLAYER"); ok2=$?; t2=$(echo "$r2" | ptext)
    if [ "$ok2" = 0 ] && [ -n "$TS2" ] && echo "$t" | grep -q -F -- "$fact" && echo "$t2" | grep -q -F -- "$fact" && echo "$t2" | grep -q -F "They told you (not verified):"; then
      verdict NP5 "PASS fact '$fact' recorded ($f0 -> $f1), shown, kept after save+reload (serial $TS -> ${TS2:-?}); reply: ${said:0:120}"
    else verdict NP5 "FAIL fact '$fact' before='$(echo "$t" | grep -o 'WHAT.*' | cut -c1-160)' after reload(ok=$ok2 serial=${TS2:-none})='$(echo "$t2" | grep -o 'WHAT.*' | cut -c1-160)'"; fi
  fi
fi

if want NP6; then # renamed NPC keeps deals/facts (same serial/storage id)
  new="Abia Panelcheck"
  stobe-auto setname "$TRADER" "$new" >/dev/null; sleep 4
  TSN=$(serial_of "$new")
  popen "$new" "$PLAYER" >/dev/null; t=$(pwait "${TSN:-x}" "$PLAYER" | ptext)
  nf=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TSN' AND lower(learner_name)=lower('$PLAYER')")
  if [ "$TSN" = "$TS" ] && echo "$t" | grep -q "^$new" && { [ "${nf:-0}" = 0 ] || echo "$t" | grep -q -F "They told you"; } && echo "$t" | grep -q "Fond"; then
    verdict NP6 "PASS renamed to '$new', same serial $TSN, facts ($nf) and relationship kept"
  else verdict NP6 "FAIL serial $TS -> ${TSN:-none} facts=$nf text: ${t:0:240}"; fi
  stobe-auto setname "$new" "$TRADER" >/dev/null
fi

if want NP7; then # deal states: in progress + outstanding + deadline, then broken by the player
  DN="Dealer $(date +%H%M%S)"  # unique per run: open/where resolve by name, an old put-away dealer would win
  h=$(spawn_neutral "$DN" 10) || setup_fail NP7 "spawn failed"
  DS=$(echo "$h" | grep -oE '#[0-9]+' | tr -d '#')
  stobe-auto teleport "$PLAYER" "$h" dist 3 >/dev/null
  greet "$DN"
  inject_on NP7 "$DN" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_ITEM","by":"npc","to":"player","item":"{worn}"},{"kind":"GIVE_CATS","by":"player","to":"npc","amount":100,"when":"after_npc"}],"message":"Fine. Take my {worn}, then you pay me 100."}]'
  talk "$DN" "Give me your shirt and I'll pay you 100 cats right after. Deal?" 5
  d=$(wait_accept "$DN" 90); sw_off
  [ -n "$d" ] || { put_away "$h"; verdict NP7 "INCONCLUSIVE no accepted deal (inject fired $(fired NP7)): $(deal_line "$DN")"; d=""; }
  if [ -n "$d" ]; then
    id=$(echo "$d" | awk '{print $1}')
    popen "$DN" "$PLAYER" >/dev/null; pwait "$DS" "$PLAYER" >/dev/null
    amt=$(PSQLQ "SELECT e->>'amount' FROM stobe_social_contract, jsonb_array_elements(term_state) e WHERE contract_id='$id' AND e->>'kind'='GIVE_CATS' LIMIT 1")
    ok1=""; t=""
    for i in $(seq 1 20); do
      stobe-auto stobe_npcinfo refresh >/dev/null; sleep 3; t=$(pread | ptext)
      echo "$t" | grep -q -F "Outstanding: $PLAYER owes $DN ${amt:-100} Cats" && echo "$t" | grep -q -F "Agreed, in progress" && { ok1=1; break; }
      deal_line "$DN" | grep -q -E "BREACHED|COMPLETE|CANCELLED" && break
    done
    st1=$(deal_field "$id" status); dl=$(echo "$t" | grep -oE "Deadline: [^|]*")
    # setup: the social pay deadline is ~23 game h; move the real-time deadline into the past so the server's own
    # expiry check (negotiation_engine: deadline_unix passed -> UNMET -> breach) runs now. Breach logic itself: STOBE-21.
    PSQLQ "UPDATE stobe_social_contract SET deadline_unix=extract(epoch from now())::bigint-5, term_state=(SELECT jsonb_agg(CASE WHEN e ? 'deadline_unix' THEN jsonb_set(e,'{deadline_unix}',to_jsonb(extract(epoch from now())::bigint-5)) ELSE e END ORDER BY o) FROM jsonb_array_elements(term_state) WITH ORDINALITY x(e,o)) WHERE contract_id='$id'" >/dev/null
    log "NP7 pay deadline forced to now-5 s (was '$dl')"
    stobe-auto speed 5 >/dev/null
    for i in $(seq 1 60); do deal_field "$id" status | grep -q -E "BREACHED|EXPIRED|COMPLETE|CANCELLED|IMPOSSIBLE" && break; sleep 5; done
    stobe-auto speed 1 >/dev/null; put_away "$h"
    st2=$(deal_field "$id" status)
    stobe-auto stobe_npcinfo refresh >/dev/null; sleep 4; t2=$(pread | ptext)
    case "$st2" in BREACHED_PLAYER) lab="Broken by $PLAYER" ;; BREACHED_NPC) lab="Broken by $DN" ;; COMPLETE) lab="Completed" ;; EXPIRED) lab="Expired" ;; *) lab="$st2" ;; esac
    if [ -n "$ok1" ] && [ -n "$dl" ] && echo "$t2" | grep -q -F -- "$lab"; then
      verdict NP7 "PASS deal $id in progress ($st1): outstanding ${amt:-?} Cats, '$dl'; then $st2 -> panel '$lab'"
    else verdict NP7 "FAIL deal $id first=$st1 ok1=${ok1:-0} dl='$dl' then=$st2 want '$lab'; text: $(echo "$t2" | grep -oE 'DEALS WITH.*ACTIVITY' | cut -c1-260)"; fi
  fi
fi

if want NP8; then # agreed goal status matches the goal row
  stobe-auto teleport "$PLAYER" "$MATE" dist 3 >/dev/null
  talk "$MATE" "$MATE, please make one Katana at the Weapon Smith." 40
  row=$(PSQLQ "SELECT status||'|'||item_name FROM (SELECT status,item_name,updated_at FROM stobe_work_goal WHERE actor_serial=$MS OR lower(actor_name)=lower('$MATE') UNION ALL SELECT status,item_name,updated_at FROM stobe_task_goal_runtime WHERE actor_serial=$MS OR lower(actor_name)=lower('$MATE')) g ORDER BY updated_at DESC LIMIT 1")
  popen "$MATE" "$PLAYER" >/dev/null; t=$(pwait "$MS" "$PLAYER" | ptext)
  # the row may move on while the panel loads: re-read it right after
  row2=$(PSQLQ "SELECT status FROM (SELECT status,updated_at FROM stobe_work_goal WHERE actor_serial=$MS OR lower(actor_name)=lower('$MATE') UNION ALL SELECT status,updated_at FROM stobe_task_goal_runtime WHERE actor_serial=$MS OR lower(actor_name)=lower('$MATE')) g ORDER BY updated_at DESC LIMIT 1")
  g=$(echo "$t" | grep -oE "(Agreed|Last agreed) goal: [^|]*\| +Status: [^|]*")
  st=$(echo "${row%%|*}" | tr 'A-Z' 'a-z'); st2=$(echo "$row2" | tr 'A-Z' 'a-z')
  if [ -z "$row" ]; then verdict NP8 "INCONCLUSIVE no goal row for $MATE; panel: ${g:-none}"
  elif echo "$g" | grep -q -E "Status: ($st|$st2)" && echo "$g" | grep -q -i -F -- "${row#*|}"; then verdict NP8 "PASS goal row $row -> panel '$g'"
  else verdict NP8 "FAIL goal row $row (now $row2) panel '${g:-none}'"; fi
  for f in stobe_work_goal stobe_task_goal; do
    id=$(cut -f1 "/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/$f.status" 2>/dev/null | head -1)
    [ -n "$id" ] && printf '%s\tCANCEL\n' "$id" > "/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/$f.control"
  done
fi

stobe-auto stobe_npcinfo close >/dev/null
log "done"
