#!/usr/bin/env bash
# id: STOBE-NPCPANEL
# covers: NPC biography card (Stobe 3EF4CCEE+, StobeServer 7ea8347+): open/target switch/close, card sections,
#         no LLM call on open/refresh once the bio is cached, relationship of the SPEAKING character, hidden
#         backstory, disclosed fact recorded from a real chat turn and kept over save+reload, renamed NPC keeps its
#         info, deal states (in progress, outstanding payment, deadline, broken), agreed goal status matches the
#         goal row, in-game portrait shown, basics + empty bio on a fresh NPC, bio filled after a conversation,
#         bio cache hit on refresh (no LLM call), bio uses the hidden backstory (confided) at Devoted+ (NP13,
#         StobeServer bf31d12+) and not below (NP14): checked on the server's bio_backstory field, the
#         stobe_npc_bio.backstory_included row and the NPC_BIO log line, never on the prose.
# fixture: Crafting base (Shay + Malzin, Apothecary Abia in town), on a kah-* copy (kah-npcpanel)
# usage: bash STOBE-NPCPANEL.sh [rows]   rows = space list of NP1..NP14 (default all)
# verify: one RESULT line per row; panel text is read back through `stobe_npcinfo read` (what the window shows:
#         header lines, then ABOUT THEM / WHAT YOU'VE LEARNED / DEALINGS WITH <speaker> / RIGHT NOW).
set -u
. "$(dirname "$0")/stobe-fight-lib.sh"
. "$(dirname "$0")/stobe-switch-lib.sh"
sw_trap
ROWS="${*:-NP1 NP2 NP3 NP4 NP5 NP6 NP7 NP8 NP9 NP10 NP11 NP12 NP13 NP14}"
EMPTYBIO="You don't know much about them yet. Talk to them to learn more."
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
# pbio <serial> [speaker]: like pwait, then until the bio is no longer being written (phase 2 done, max 60 s)
pbio() {
  local r i
  r=$(pwait "$@") || { echo "$r"; return 1; }
  for i in $(seq 1 30); do case "$r" in *"bio_state=pending"*) sleep 2; r=$(pread) ;; *) echo "$r"; return 0 ;; esac; done
  echo "$r"; return 1
}
# learned: the WHAT YOU'VE LEARNED section of a read text
learned() { sed -E "s/.*WHAT YOU'VE LEARNED \| //; s/ \| +\| DEALINGS WITH.*//"; }
# NP5: NPC_BIO lines for the trader (phase-2 bio request done: generated|cache hit|throttled|llm returned nothing)
bio_lines() { since_srv | grep -a -c -E "NPC_BIO: .*\"npc\":\"$TRADER\""; }
field() { echo "$1" | grep -oE " $2=[^ ]*" | head -1 | cut -d= -f2; }
# NP12 (m63): bio prompts only - a late relationship_eval from NP11's chat lines also writes to the prompt log
bio_llm_count() { grep -a -c "'event_type' => 'npc_bio'" "$CTX" 2>/dev/null || echo 0; }
llm_count() { echo "$(PSQLQ "SELECT COUNT(*) FROM audit_llm")/$(wc -l < "$CTX" 2>/dev/null || echo 0)"; }

stobe-auto select "$PLAYER" >/dev/null
TS=$(serial_of "$TRADER"); MS=$(serial_of "$MATE")
[ -n "$TS" ] && [ -n "$MS" ] || setup_fail NPCPANEL "no $TRADER/$MATE serial (trader=$TS mate=$MS)"
log "trader $TRADER #$TS, mate $MATE #$MS"

if want NP1; then # open + card sections + no LLM call on refresh once the bio is settled (game paused: no chatter)
  stobe-auto speed 0 >/dev/null; sleep 2
  popen "$TRADER" >/dev/null; r=$(pbio "$TS" "$PLAYER"); t=$(echo "$r" | ptext)
  c0=$(llm_count)
  stobe-auto stobe_npcinfo refresh >/dev/null; sleep 3; stobe-auto stobe_npcinfo refresh >/dev/null; sleep 12
  c1=$(llm_count)
  miss=""
  for s in "$TRADER | Job: Trader" "Faction: " "Relationship: " "ABOUT THEM | " "WHAT YOU'VE LEARNED | " \
           "DEALINGS WITH ${PLAYER^^} | " "RIGHT NOW | " "Doing now: "; do
    echo "$t" | grep -q -F -- "$s" || miss="$miss [$s]"
  done
  echo "$t" | grep -q -F "Doing now: not visible" && miss="$miss [live activity missing]"
  echo "$t" | sed -E "s/WHAT YOU'VE LEARNED.*DEALINGS WITH/DEALINGS WITH/" | grep -q -i -E "limb|blood|hunger|profile|voice|hand_[0-9]" \
    && miss="$miss [stat/metadata shown]"
  if [ -z "$miss" ] && [ "$c0" = "$c1" ]; then verdict NP1 "PASS card for $TRADER key=$TS|$PLAYER bio_state=$(field "$r" bio_state), all sections, llm audit/ctx on refresh $c0 -> $c1"
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
  ra=$(echo "$a" | grep -oE "Relationship: [^|]*"); rb=$(echo "$b" | grep -oE "Relationship: [^|]*")
  if echo "$ra" | grep -q "Fond (friend) - they like you a lot" && echo "$rb" | grep -q "Neutral - they have no opinion of you yet"; then
    verdict NP3 "PASS $ra / $rb"
  else verdict NP3 "FAIL as $PLAYER: '$ra' as $MATE: '$rb'"; fi
fi

if want NP4; then # stored backstory/goals/bio never shown (the learned section is excluded: it is written from what the
                  # NPC said, which may echo its own story; its prompt is checked offline: npc_player_view_regression)
  popen "$TRADER" "$PLAYER" >/dev/null; t=$(pbio "$TS" "$PLAYER" | ptext | sed -E "s/WHAT YOU'VE LEARNED.*DEALINGS WITH/DEALINGS WITH/")
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
  # setup: an earlier run's injected fact would make the new one a duplicate (ON CONFLICT DO NOTHING)
  PSQLQ "DELETE FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND fact LIKE 'grew up in a farming village and trained as an apothecary%'" >/dev/null
  f0=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER')")
  stobe-auto teleport "$PLAYER" "$TRADER" dist 3 >/dev/null
  # deterministic (StobeServer 9c0fc10+): the evaluator reply after her turn gets a "disclosed" fact via
  # NEG_TEST_INJECT context relationship; it only fires if the real gate decided to evaluate this turn.
  # NP5_LIVE=1: no injection (does the evaluator model extract a fact by itself).
  injf0=$(fired NP5)
  [ "${NP5_LIVE:-0}" = 1 ] || inject_on NP5 "$TRADER" relationship '[{"disclosed":[{"fact":"grew up in a farming village and trained as an apothecary","category":"background"}]}]'
  talk "$TRADER" "Tell me about yourself. Where did you grow up, and what work did you do before you ended up here?" 25
  f1=$f0
  for i in $(seq 1 20); do f1=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER')"); [ "${f1:-0}" -gt "${f0:-0}" ] && break; sleep 3; done
  injn=$(( $(fired NP5) - injf0 )); sw_off
  said=$(since_stobe | grep -a -F "NPC_SAY: $TRADER|" | tail -1 | sed -E "s/.*NPC_SAY: $TRADER\|([0-9]+: )?//" | cut -c1-220)
  fact=$(PSQLQ "SELECT fact FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER') ORDER BY id DESC LIMIT 1")
  if [ "${f1:-0}" -le "${f0:-0}" ]; then
    verdict NP5 "FAIL no fact recorded (facts $f0 -> $f1, inject_fired=$injn$( [ "${NP5_LIVE:-0}" = 1 ] || [ "$injn" -ge 1 ] || echo ': evaluator never ran for her turn')); reply: $said; srv: $(since_srv | grep -a -E 'NPC_FACTS|Relationship evaluation|relationship_eval' | tail -2 | cut -c1-200)"
  else
    # the fact feeds the bio (or the "They told you:" list while no bio exists); the learned section must be
    # filled before and stay the same (cached, no new LLM call) after save + reload of the same save
    # m64: the first reply is the cached bio + bio_stale=1 (new dialogue); the DLL then asks for the new bio
    # (phase 2, one NPC_BIO line) and shows it -> read l1 only after that line, else the pre-fact bio is compared
    nb0=$(bio_lines); popen "$TRADER" "$PLAYER" >/dev/null; t=$(pbio "$TS" "$PLAYER" | ptext)
    for i in $(seq 1 20); do [ "$(bio_lines)" -gt "$nb0" ] && { sleep 3; t=$(pread | ptext); break; }; sleep 2; done
    l1=$(echo "$t" | learned)
    stobe-auto save kah-npcpanel-r >/dev/null; sleep 5
    stobe-auto load kah-npcpanel-r >/dev/null; sleep 5; timeout 300 stobe-auto wait-world >/dev/null 2>&1
    TS2=""; for i in $(seq 1 15); do TS2=$(serial_of "$TRADER"); [ -n "$TS2" ] && break; sleep 2; done
    popen "$TRADER" "$PLAYER" >/dev/null; r2=$(pbio "${TS2:-$TS}" "$PLAYER"); ok2=$?; t2=$(echo "$r2" | ptext); l2=$(echo "$t2" | learned)
    if [ "$ok2" = 0 ] && [ -n "$TS2" ] && [ -n "$l1" ] && [ "$l1" != "$EMPTYBIO" ] && [ "$l1" = "$l2" ]; then
      verdict NP5 "PASS fact '$fact' recorded ($f0 -> $f1, inject_fired=$injn), learned='${l1:0:140}', same after save+reload (serial $TS -> ${TS2:-?}, $(field "$r2" bio_state)); reply: ${said:0:100}"
    else verdict NP5 "FAIL fact '$fact' learned before='${l1:0:160}' after reload(ok=$ok2 serial=${TS2:-none} $(field "$r2" bio_state))='${l2:0:160}'"; fi
  fi
fi

if want NP6; then # renamed NPC keeps deals/facts (same serial/storage id)
  bash "$SC" trust "$TRADER" 60 Fond friend >/dev/null 2>&1   # own setup: Fond was only set by NP3 (m55: NP5 NP6 alone -> Neutral)
  new="Abia Panelcheck"
  # m63: the harness setname bypassed Stobe's rename (the server then split the NPC into a second, relationship-less
  # row); rename the way the player does: Stobe's Rename NPC window (rename.php keeps the identity)
  rn=$(stobe-auto stobe_npcinfo rename "$TRADER" "$new" 2>&1 | tail -1); log "NP6 rename: $rn"; sleep 4
  TSN=$(serial_of "$new")
  popen "$new" "$PLAYER" >/dev/null; t=$(pbio "${TSN:-x}" "$PLAYER" | ptext)
  nf=$(PSQLQ "SELECT COUNT(*) FROM stobe_npc_learned_fact WHERE npc_storage_id='hand_$TSN' AND lower(learner_name)=lower('$PLAYER')")
  if [ "$TSN" = "$TS" ] && echo "$t" | grep -q "^$new" && { [ "${nf:-0}" = 0 ] || [ "$(echo "$t" | learned)" != "$EMPTYBIO" ]; } && echo "$t" | grep -q "Fond"; then
    verdict NP6 "PASS renamed to '$new', same serial $TSN, facts ($nf) and relationship kept"
  else verdict NP6 "FAIL serial $TS -> ${TSN:-none} facts=$nf rename='${rn:0:120}' text: ${t:0:240}"; fi
  # rename back (same window path) so later rows and runs find the trader by its fixture name
  rb=$(stobe-auto stobe_npcinfo rename "$new" "$TRADER" 2>&1 | tail -1); log "NP6 rename back: $rb"; sleep 3
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
      # m64: term_state can still be empty right after the accept (amt="") and the price may differ from the ask:
      # take the amount the panel shows and check it against the term amount once the state exists
      shown=$(echo "$t" | grep -oE "Outstanding: $PLAYER owes $DN [0-9]+ Cats" | grep -oE "[0-9]+ Cats" | cut -d" " -f1)
      [ -n "$amt" ] || amt=$(PSQLQ "SELECT e->>'amount' FROM stobe_social_contract, jsonb_array_elements(term_state) e WHERE contract_id='$id' AND e->>'kind'='GIVE_CATS' LIMIT 1")
      [ -n "$shown" ] && [ "$shown" = "$amt" ] && echo "$t" | grep -q -F "Agreed, in progress" && { ok1=1; break; }
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
    else verdict NP7 "FAIL deal $id first=$st1 ok1=${ok1:-0} shown=${shown:-none} amt=${amt:-none} dl='$dl' then=$st2 want '$lab'; text: $(echo "$t2" | grep -oE 'DEALINGS WITH.*RIGHT NOW' | cut -c1-260)"; fi
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

if want NP9; then # the card shows the target's in-game portrait (PortraitManager atlas texture)
  popen "$TRADER" "$PLAYER" >/dev/null; r=$(pwait "$TS" "$PLAYER"); sleep 2; r=$(pread)
  pl=$(since_stobe | grep -a "NPC_PANEL: portrait=" | tail -1 | sed -E 's/.*NPC_PANEL: //' | cut -c1-160)
  if [ "$(field "$r" portrait)" = 1 ] && [ "$(field "$r" tex)" != "-" ] && echo "$pl" | grep -q "portrait=1"; then
    verdict NP9 "PASS portrait=1 tex=$(field "$r" tex) log '$pl'"
  else verdict NP9 "FAIL read portrait=$(field "$r" portrait) tex=$(field "$r" tex) log '${pl:-none}'"; fi
fi

# NP13/NP14: the bio may use the hidden backstory only at tier NPC_BIO_BACKSTORY_MIN_TIER (default Devoted) or higher.
SRV_URL="${SRV_URL:-http://127.0.0.1:8081/StobeServer/ai_npcs.php}"
NP_BACKSTORY="Born in Shark to a family of salt traders, she left after her mother died of dust fever and learned herbal medicine from a Hub doctor named Orrin."
# srv_view <serial> <name> <speaker>: the card's machine fields as the server returns them (bio=0 + why=periodic: no LLM call, no log)
srv_view() {
  curl -s -m 15 -X POST -H 'Content-Type: application/json' \
    -d "{\"action\":\"player_view\",\"storage_id\":\"hand_$1\",\"serial\":$1,\"name\":\"$2\",\"speaker\":\"$3\",\"why\":\"periodic\"}" "$SRV_URL" |
    python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: d = {}
print(" bio_backstory=%s bio_state=%s" % (d.get("bio_backstory", "-"), d.get("bio_state", "-")))'
}
bs_row() { PSQLQ "SELECT backstory_included FROM stobe_npc_bio WHERE npc_storage_id='hand_$TS' AND lower(learner_name)=lower('$PLAYER')"; }
bs_log() { since_srv | grep -a -c -E "NPC_BIO: (generated|cache hit) backstory=$1 .*\"npc\":\"$TRADER\""; }
if want NP13 || want NP14; then # setup: the trader needs a stored (hidden) backstory
  stobe-auto stobe_npcinfo close >/dev/null
  bw=$(PSQLQ "SELECT length(coalesce(backstory,'')) FROM core_npc WHERE metadata->>'storage_id'='hand_$TS' ORDER BY updated_at DESC LIMIT 1")
  if [ "${bw:-0}" -lt 40 ]; then
    PSQLQ "UPDATE core_npc_master SET backstory='$NP_BACKSTORY' WHERE lower(name)=lower('$TRADER')" >/dev/null
    bw=$(PSQLQ "SELECT length(coalesce(backstory,'')) FROM core_npc WHERE metadata->>'storage_id'='hand_$TS' ORDER BY updated_at DESC LIMIT 1")
    log "NP13/14: $TRADER had no backstory, test backstory set ($bw chars)"
  fi
  [ "${bw:-0}" -ge 40 ] || setup_fail NP13 "$TRADER (hand_$TS) has no stored backstory and setting one failed (len=${bw:-none})"
  PSQLQ "DELETE FROM general_settings WHERE id='NPC_BIO_BACKSTORY_MIN_TIER' RETURNING value" | grep -q . && log "NP13/14: removed a NPC_BIO_BACKSTORY_MIN_TIER override (default Devoted)"
  # below the tier a bio is only written from what the NPC said to this speaker: make sure there is one line (NP14)
  nl=$(PSQLQ "SELECT COUNT(*) FROM eventlog WHERE type IN ('chat','rechat') AND people LIKE '%|hand_$TS\"%' AND people LIKE '%\"$PLAYER|%'")
  if [ "${nl:-0}" -eq 0 ]; then
    stobe-auto teleport "$PLAYER" "$TRADER" dist 3 >/dev/null
    talk "$TRADER" "Hello there. How is business today?" 22
    nl=$(PSQLQ "SELECT COUNT(*) FROM eventlog WHERE type IN ('chat','rechat') AND people LIKE '%|hand_$TS\"%' AND people LIKE '%\"$PLAYER|%'")
  fi
  [ "${nl:-0}" -ge 1 ] || setup_fail NP14 "$TRADER said nothing to $PLAYER (no chat line for the bio)"
fi

if want NP13; then # Devoted: bio regenerated with the confided backstory
  bash "$SC" trust "$TRADER" 85 Devoted friend >/dev/null 2>&1
  g0=$(bs_log 1)
  popen "$TRADER" "$PLAYER" >/dev/null; r=$(pbio "$TS" "$PLAYER")
  g1=$(bs_log 1); v=$(srv_view "$TS" "$TRADER" "$PLAYER"); row=$(bs_row)
  if [ "$(field "$v" bio_backstory)" = 1 ] && [ "$row" = 1 ] && [ "$g1" -gt "$g0" ]; then
    verdict NP13 "PASS Devoted(85): bio_backstory=1, backstory_included=1, NPC_BIO backstory=1 log $g0 -> $g1, panel bio_state=$(field "$r" bio_state)"
  else verdict NP13 "FAIL Devoted(85):$v row=${row:-none} NPC_BIO backstory=1 log $g0 -> $g1 panel bio_state=$(field "$r" bio_state) learned='$(echo "$r" | ptext | learned | cut -c1-160)'"; fi
  stobe-auto stobe_npcinfo close >/dev/null
fi

if want NP14; then # back below Devoted: confided bio hidden at once, regenerated without the backstory
  bash "$SC" trust "$TRADER" 20 Acquaintance friend >/dev/null 2>&1
  v0=$(srv_view "$TS" "$TRADER" "$PLAYER")
  g0=$(bs_log 0)
  popen "$TRADER" "$PLAYER" >/dev/null; r=$(pbio "$TS" "$PLAYER")
  g1=$(bs_log 0); v=$(srv_view "$TS" "$TRADER" "$PLAYER"); row=$(bs_row)
  if [ "$(field "$v0" bio_backstory)" = 0 ] && [ "$(field "$v" bio_backstory)" = 0 ] && [ "$row" = 0 ] && [ "$g1" -gt "$g0" ]; then
    verdict NP14 "PASS Acquaintance(20): bio_backstory=0 before+after regen, backstory_included=0, NPC_BIO backstory=0 log $g0 -> $g1, panel bio_state=$(field "$r" bio_state)"
  else verdict NP14 "FAIL Acquaintance(20): before:$v0 after:$v row=${row:-none} NPC_BIO backstory=0 log $g0 -> $g1 panel bio_state=$(field "$r" bio_state)"; fi
  stobe-auto stobe_npcinfo close >/dev/null
fi
if want NP13 || want NP14; then bash "$SC" trust "$TRADER" 60 Fond friend >/dev/null 2>&1; fi

SN=""; SS=""; SH=""
if want NP10 || want NP11 || want NP12; then # a fresh stranger: no conversation, no record yet
  SN="Stranger $(date +%H%M%S)"
  SH=$(spawn_neutral "$SN" 10) || setup_fail NP10 "spawn failed"
  SS=$(echo "$SH" | grep -oE '#[0-9]+' | tr -d '#')
  stobe-auto teleport "$PLAYER" "$SH" dist 3 >/dev/null
fi

if want NP10; then # basics on first open with no conversation, empty bio state, no LLM call
  stobe-auto speed 0 >/dev/null; sleep 2
  c0=$(llm_count)
  popen "$SN" "$PLAYER" >/dev/null; r=$(pbio "$SS" "$PLAYER"); t=$(echo "$r" | ptext); sleep 5
  c1=$(llm_count)
  miss=""
  for s in "$SN | Job: " "Faction: " "Relationship: " "You haven't talked yet" "ABOUT THEM | " "WHAT YOU'VE LEARNED | $EMPTYBIO" "RIGHT NOW | "; do
    echo "$t" | grep -q -F -- "$s" || miss="$miss [$s]"
  done
  if [ -z "$miss" ] && [ "$(field "$r" bio_state)" = empty ] && [ "$c0" = "$c1" ]; then
    verdict NP10 "PASS fresh $SN #$SS: basics + empty bio, bio_state=empty, llm $c0 -> $c1"
  else verdict NP10 "FAIL missing:$miss bio_state=$(field "$r" bio_state) llm $c0 -> $c1 text: ${t:0:300}"; fi
  stobe-auto stobe_npcinfo close >/dev/null
  stobe-auto speed 1 >/dev/null
fi

if want NP11; then # bio fills after a conversation and mentions something the NPC said
  stobe-auto stobe_npcinfo close >/dev/null
  g0=$(since_srv | grep -a -c "NPC_BIO: generated .*\"npc\":\"$SN\"")
  BL=$(wc -l < "$L")
  talk "$SN" "Hello $SN. Tell me about yourself, where are you from?" 22
  talk "$SN" "What work did you do before you came out here?" 22
  talk "$SN" "What do you want out of life, $SN?" 22
  said=$(tail -n +"$BL" "$L" | grep -a -F "NPC_SAY: $SN|" | sed -E "s/.*NPC_SAY: $SN\|([0-9]+: )?//" | tr '\n' ' ')
  popen "$SN" "$PLAYER" >/dev/null; r=$(pbio "$SS" "$PLAYER"); t=$(echo "$r" | ptext); l=$(echo "$t" | learned)
  g1=$(since_srv | grep -a -c "NPC_BIO: generated .*\"npc\":\"$SN\"")
  hit=$(SAID="$said" BIO="$l" python3 - <<'PY'
import os, re
stop = set("about after again their there these those which while would could should where other being being every never maybe really things thing think youre theyre dont didnt cant wont".split())
said = set(w for w in re.findall(r"[a-z]{5,}", os.environ['SAID'].lower()) if w not in stop)
bio = set(re.findall(r"[a-z]{5,}", os.environ['BIO'].lower()))
print(','.join(sorted(said & bio)[:5]))
PY
)
  if [ -n "$said" ] && [ -n "$l" ] && [ "$l" != "$EMPTYBIO" ] && [ "$g1" -gt "$g0" ] && [ -n "$hit" ]; then
    verdict NP11 "PASS bio ($(field "$r" bio_state)) after 3 lines shares '$hit' with what $SN said: ${l:0:160}"
  else verdict NP11 "FAIL bio_state=$(field "$r" bio_state) generated $g0 -> $g1 shared='$hit' said='${said:0:160}' learned='${l:0:160}'"; fi
fi

if want NP12; then # second refresh: cache hit, no LLM call
  stobe-auto speed 0 >/dev/null; sleep 2
  popen "$SN" "$PLAYER" >/dev/null; pbio "$SS" "$PLAYER" >/dev/null
  h0=$(since_srv | grep -a -c "NPC_BIO: cache hit .*\"npc\":\"$SN\""); c0=$(llm_count); b0=$(bio_llm_count)
  stobe-auto stobe_npcinfo refresh >/dev/null; sleep 4; stobe-auto stobe_npcinfo refresh >/dev/null; sleep 4
  r=$(pread); c1=$(llm_count); b1=$(bio_llm_count); h1=$(since_srv | grep -a -c "NPC_BIO: cache hit .*\"npc\":\"$SN\"")
  if [ "$(field "$r" bio_state)" = cached ] && [ "$h1" -ge $((h0 + 2)) ] && [ "$b0" = "$b1" ]; then
    verdict NP12 "PASS 2 refreshes: bio_state=cached, cache-hit log $h0 -> $h1, bio llm prompts $b0 -> $b1 (all llm $c0 -> $c1)"
  else verdict NP12 "FAIL bio_state=$(field "$r" bio_state) cache-hit log $h0 -> $h1 bio llm prompts $b0 -> $b1 (all llm $c0 -> $c1)"; fi
  stobe-auto speed 1 >/dev/null
fi
[ -n "$SH" ] && put_away "$SH"

stobe-auto stobe_npcinfo close >/dev/null
log "done"
