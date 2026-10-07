#!/usr/bin/env bash
# id: STOBE-D-confirm
# covers: STOBE_full_test_plan.md section D, the "fixed, not yet confirmed in game" items (MASTER_TEST_PLAN.md section 3):
#   D70  (items 70 + 108) template-name relationship keys: save, fight a template-named NPC ("Hungry Bandit", the mate
#        joins in, one chat line about him), load that OLDER save (the save-follow restore), fight a second one after the
#        load. PASS: no relationship key that is a name in server data/npc_generic_templates.json appeared in any NPC's
#        map (core_npc_master extended_data->relationships and the relationships column) since the start, the server
#        logged the rollback, and both fights reached the game's combat events.
#   D86  paid truce, then an older-save load: save, fight a raider, injected ACCEPT (player GIVE_CATS 100 + npc
#        STOP_ATTACK, NEG_TEST_INJECT), Shay pays, load the save while the deal is in flight. PASS: the deal ends
#        CANCELLED with evidence note rolled_back_by_load (server log "Deals from after the loaded save cancelled") and
#        is never BREACHED_PLAYER during 90 s after the load.
#   D94  stobe-reset-npc round trip on MATE -> PLAYER: reset (key gone), --restore, one chat line. PASS: exactly one key
#        for the player (any case) in both copies, spelled exactly "$PLAYER" (not "shay"), aff = the saved entry's aff.
#        Runs the tool without PLAYER when PLAYER matches the PLAYER_NAME setting (the item-94 path: setting "shay").
#        Clears MATE's deals and today's memories (the tool's reset): run it last ("round trip at the end").
#   D99  WAITING_APPROVAL for a trader-only ingredient: runs STOBE-15-buy-approval.sh decline (Crafting base) and
#        passes when its status file showed a buy-...Fabrics row in WAITING_APPROVAL (the decline result is item 15's).
#   D101 `[]` extended_data: a fresh NPC (spawned + greeted) must be created with object extended_data/metadata; then
#        his extended_data is forced to '[]' (the old broken shape) and (a) `social_relationship_inspect.php
#        --set-relation` writes aff 37, (b) again '[]', then a real in-game fight with PLAYER makes the server's attack
#        rule write his map (skipped when SOCIAL_RELATIONSHIP_MODE is enabled/fights: R4 retired). PASS: values written,
#        extended_data an object, no new postgres "path element at position 1 is not an integer" errors.
#   D105 KenshiFP/Stobe goal log spam: runs STOBE-A8-bread-chain.sh (a real work goal) and counts `WORK_GOAL input
#        ratio` lines it caused in stobe_goals.log and KenshiFP.log. PASS: a work goal ran (WORK_GOAL accepted) and the
#        count stays within the item-105 throttle (8 keys x one per 30 s); the bug was 30k lines.
# usage: STOBE-D-confirm.sh [D70] [D86] [D94] [D99] [D101] [D105]   (default: D70 D86 D101 D94)
# fixtures: D70 D86 D94 D101 D105 = auto-home ("home" in run-batch: Shay + Malzin); D99 = kah-crafting (Crafting base,
#   Shay + Malzin, Apothecary Abia nearby; TRADER=... for others). D70/D86 make temporary saves kah-dconfirm-d70/-d86
#   (deleted on exit) and leave the world on that loaded save.
# needs: server live (items 70/108/86/101 fixes), stobe-reset-npc in /usr/local/bin, harness save/load/protect,
#   Stobe/KenshiFP builds from m49+. Runs as root in WSL (run-batch).
# output: one `RESULT <row> PASS|FAIL <evidence>` line per row; a failed setup = `FAIL SETUP FAIL <reason>`.
#   NEG_TEST_INJECT is deleted on exit; temporary saves removed; D101 never leaves a '[]' row behind.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/stobe-fight-lib.sh"
. "$D/stobe-switch-lib.sh"
SAVES=/mnt/c/Users/Shay/AppData/Local/kenshi/save
SRVROOT=/var/www/html/StobeServer
TPL_JSON=$SRVROOT/data/npc_generic_templates.json
KFPLOG=/mnt/d/Steam/steamapps/common/Kenshi/KenshiFP.log
TMP_SAVES=""
cleanup() {
  sw_off; heal_stop; stobe-auto speed 0 >/dev/null 2>&1
  for s in $TMP_SAVES; do case "$s" in kah-dconfirm-*) rm -rf "${SAVES:?}/$s" ;; esac; done
}
trap cleanup EXIT; trap 'exit 130' INT TERM
ROWS="${*:-D70 D86 D101 D94}"
export PLAYER MATE

# --- shared helpers ---------------------------------------------------------------------------------------------
srv_lines() { grep -a -c "" "$SRV" 2>/dev/null || echo 0; }
# save_point <name>: save the game as <name> and wait (30 s) until its folder is written; adds it to the cleanup list
save_point() {
  local t; t=$(date +%s)
  stobe-auto save "$1" >/dev/null 2>&1 || { WHY="save command failed"; return 1; }
  TMP_SAVES="$TMP_SAVES $1"
  wait_for 30 eval "[ -n \"\$(find '$SAVES/$1' -newermt '@$t' -print -quit 2>/dev/null)\" ]" || { WHY="no save folder $SAVES/$1 written within 30 s"; return 1; }
  sleep 3
}
# advance <game minutes>: run the game (speed 5) until the game clock (harness `time`) moved that far (bounded 60 s)
game_hours() { stobe-auto time | grep -oE "game_hours=[0-9.]+" | cut -d= -f2; }
advance() {
  local h0 h; h0=$(game_hours); stobe-say speed 5 >/dev/null
  for i in $(seq 1 30); do sleep 2; h=$(game_hours); awk -v a="${h0:-0}" -v b="${h:-0}" -v m="$1" 'BEGIN{exit !(b >= a + m/60)}' && break; done
  stobe-say speed 1 >/dev/null
  awk -v a="${h0:-0}" -v b="${h:-0}" -v m="$1" 'BEGIN{exit !(b >= a + m/60 && a > 0)}'
}
# older_load <save>: load it, wait for the world + Stobe's sync, then for the server's rollback (90 s). Sets WHY.
older_load() {
  local b m; b=$(stobe_log_lines); m=$(srv_lines)
  stobe-auto load "$1" >/dev/null 2>&1 || { WHY="load $1 failed"; return 1; }
  sleep 12
  stobe-auto wait-world 300 >/dev/null 2>&1 || { WHY="world not back within 300 s after loading $1"; return 1; }
  stobe_ready 150 "$b" || { WHY="$STOBE_READY_WHY"; return 1; }
  stobe-auto select "$PLAYER" >/dev/null; stobe-say speed 1 >/dev/null
  wait_for 90 eval "tail -n +$m '$SRV' | grep -a -q 'PLAYTHROUGH: Rollback completed'" || { WHY="server logged no 'PLAYTHROUGH: Rollback completed' within 90 s of the load"; return 1; }
  ROLLBACK_LINE=$(tail -n +"$m" "$SRV" | grep -a 'PLAYTHROUGH: Rollback completed' | tail -1 | cut -c1-300)
}
# tpl_keys: "owner<TAB>key" for every relationship key (both copies) that is a generic template name (lowercased,
# whitespace collapsed, as stobeIsGenericNpcName); first line "TOTAL <keys scanned>"
tpl_keys() {
  PSQLQ "SELECT m.name||E'\t'||k FROM core_npc_master m, jsonb_object_keys(CASE WHEN jsonb_typeof(m.extended_data->'relationships')='object' THEN m.extended_data->'relationships' ELSE '{}'::jsonb END) k
         UNION ALL SELECT m.name||E'\t'||k FROM core_npc_master m, jsonb_object_keys(CASE WHEN m.relationships ~ '^\s*\{.*\}\s*$' THEN m.relationships::jsonb ELSE '{}'::jsonb END) k" \
  | python3 -c '
import json, re, sys
t = set(str(x).lower() for x in json.load(open(sys.argv[1])))
rows = [l.rstrip("\n") for l in sys.stdin if "\t" in l]
print("TOTAL %d" % len(rows))
for r in sorted(set(rows)):
    k = r.split("\t", 1)[1]
    if re.sub(r"\s+", " ", k.strip().lower()) in t: print(r)
' "$TPL_JSON"
}
is_tpl() { python3 -c 'import json,re,sys; t=set(str(x).lower() for x in json.load(open(sys.argv[1]))); sys.exit(0 if re.sub(r"\s+"," ",sys.argv[2].strip().lower()) in t else 1)' "$TPL_JSON" "$1"; }
# fight_template <template>: spawns one hostile NPC that keeps its template name, the squad fights it until the game
# reports combat; prints "<handle>\t<name>"
fight_template() {
  local r n
  r=$(KEEP_TEMPLATE_NAME=1 spawn_raiders 1 "$1" | head -1); [ -n "$r" ] || return 1
  n=$(name_of "$r")
  stobe-auto attack "$MATE" "$r" >/dev/null 2>&1
  engage "$r" || log "no combat_start for $n"
  printf '%s\t%s\n' "$r" "$n"
}
pg_log() { ls -t /var/log/postgresql/*.log 2>/dev/null | head -1; }
pg_err_count() { local f; f=$(pg_log); [ -n "$f" ] && grep -a -c "path element at position 1 is not an integer" "$f" 2>/dev/null || echo 0; }
# inner <row> <script> [args]: runs another wrapper, its RESULT/VERDICT lines renamed so this row keeps exactly one
inner() {
  local row="$1"; shift
  INNER_OUT=/tmp/stobe-dconfirm-$row.$$.txt
  bash "$D/$1" "${@:2}" 2>&1 | sed -u -e 's/^RESULT /(inner) RESULT /' -e 's/^VERDICT /(inner) VERDICT /' | tee "$INNER_OUT" >&2
  INNER_RC=${PIPESTATUS[0]}
}

# --- rows (each runs in its own subshell: a setup_fail ends only that row) ------------------------------------------
row_D70() {
  trap 'heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
  preflight D70 advancing
  local TPL="${D70_TEMPLATE:-Hungry Bandit}" pre post new f1 f2 h1 n1 h2 n2 c1 c2
  is_tpl "$TPL" || setup_fail D70 "'$TPL' is not in npc_generic_templates.json"
  pre=$(tpl_keys); [ "$(echo "$pre" | head -1 | awk '{print $2}')" -gt 0 ] 2>/dev/null || setup_fail D70 "relationship key query returned nothing ($(echo "$pre" | head -1))"
  log "D70 template keys before: $(( $(echo "$pre" | grep -c .) - 1 ))"
  wait_personal_guard
  save_point kah-dconfirm-d70 || setup_fail D70 "$WHY"
  advance 3 || setup_fail D70 "game time did not advance after the save"
  heal_start "$PLAYER" "$MATE"
  f1=$(fight_template "$TPL") || setup_fail D70 "no '$TPL' spawned"
  h1=$(echo "$f1" | cut -f1); n1=$(echo "$f1" | cut -f2)
  is_tpl "$n1" || setup_fail D70 "spawned NPC is called '$n1', not a template name"
  stobe-say say "$MATE" "$MATE, what do you make of that $n1? Can we trust his kind?" >/dev/null 2>&1 || log "say failed"
  sleep 25; stobe-auto ko "$h1" 900 >/dev/null 2>&1
  c1=$(since_stobe | grep -a -F "[EVENT] combat: $n1" | grep -a -c .)
  heal_stop
  older_load kah-dconfirm-d70 || setup_fail D70 "$WHY"
  log "rollback: $ROLLBACK_LINE"
  heal_start "$PLAYER" "$MATE"
  local m2; m2=$(stobe_log_lines)
  f2=$(fight_template "$TPL") || setup_fail D70 "no '$TPL' spawned after the load"
  h2=$(echo "$f2" | cut -f1); n2=$(echo "$f2" | cut -f2)
  sleep 25; stobe-auto ko "$h2" 900 >/dev/null 2>&1
  c2=$(tail -n +"$m2" "$L" | grep -a -F "[EVENT] combat: $n2" | grep -a -c .)
  heal_stop; stobe-say speed 0 >/dev/null
  sleep 20  # the relationship evaluator / attack rule writes after the events
  post=$(tpl_keys)
  [ "$(echo "$post" | head -1 | awk '{print $2}')" -gt 0 ] 2>/dev/null || { verdict D70 "FAIL relationship key query failed after the test"; return; }
  new=$(comm -13 <(echo "$pre" | tail -n +2 | sort) <(echo "$post" | tail -n +2 | sort) | tr '\t' '>' | tr '\n' ';')
  log "template keys after: $(( $(echo "$post" | grep -c .) - 1 )) new: ${new:-none}"
  if [ -n "$new" ]; then verdict D70 "FAIL new template keys: ${new:0:150}"
  elif [ "${c1:-0}" -lt 1 ] || [ "${c2:-0}" -lt 1 ]; then verdict D70 "FAIL fights not seen by Stobe (combat events '$n1' before load=$c1, '$n2' after=$c2)"
  else verdict D70 "PASS no new template keys ($(echo "$post" | head -1)); fights '$n1' pre-load=$c1 + '$n2' post-load=$c2 combat events; rollback ok"; fi
}

row_D86() {
  trap 'heal_stop; stobe-auto speed 0 >/dev/null 2>&1' EXIT
  preflight D86 advancing
  local r name d id g_save base_g st_pre m0 m1 st seen_breach=0 note cancel_line
  wait_personal_guard
  save_point kah-dconfirm-d86 || setup_fail D86 "$WHY"
  g_save=$(srv_gamets)
  advance 3 || setup_fail D86 "game time did not advance after the save"
  park_malzin 600; heal_start "$PLAYER"
  r=$(spawn_raiders 1 | head -1); [ -n "$r" ] || setup_fail D86 "no raider"
  engage "$r" || log "no combat_start seen"
  name=$(name_of "$r"); log "raider $r = $name"
  stobe-auto health "$r" 35 >/dev/null
  stobe-auto protect "$r" on >/dev/null 2>&1 && PROTECTED="${PROTECTED:-} $r"
  stobe-say give_cats 300 >/dev/null 2>&1
  inject_on D86 "$name" chat '[{"deal_decision":"ACCEPT","deal_terms":[{"kind":"GIVE_CATS","by":"player","to":"npc","amount":100},{"kind":"STOP_ATTACK","by":"npc","target":"player"}],"message":"Fine. A hundred cats and I stop."}]'
  say_to "$r" "$name" "Stop fighting! I'll pay you 100 cats right now if you stand down."
  d=$(wait_accept "$name" 90 "$r")
  [ -n "$d" ] || setup_fail D86 "no accepted deal (injection fired=$(fired D86)): $(deal_line "$name")"
  sw_off
  id=$(echo "$d" | awk '{print $1}')
  m0=$(money_of "$PLAYER")
  say_to "$r" "$name" "Here are your 100 cats, $name."
  for i in $(seq 1 15); do deal_terms "$id" | grep -q "player:GIVE_CATS:VERIFIED" && break; sleep 3; done
  m1=$(money_of "$PLAYER")
  st_pre=$(deal_field "$id" status); base_g=$(deal_field "$id" "baseline->>'gamets'")
  log "deal $id status=$st_pre terms=$(deal_terms "$id") baseline gamets=$base_g save gamets=$g_save cats $m0 -> $m1"
  case "$st_pre" in ACCEPTED|AWAITING_PERFORMANCE|PROPOSED|COUNTERED) ;; *) setup_fail D86 "deal not in flight before the load: $st_pre" ;; esac
  [ "${base_g:-0}" -gt "${g_save:-0}" ] || setup_fail D86 "deal baseline gamets $base_g not after the save ($g_save)"
  heal_stop
  older_load kah-dconfirm-d86 || setup_fail D86 "$WHY"
  log "rollback: $ROLLBACK_LINE"
  for i in $(seq 1 18); do st=$(deal_field "$id" status); [ "$st" = BREACHED_PLAYER ] && seen_breach=1; sleep 5; done
  stobe-say speed 0 >/dev/null
  st=$(deal_field "$id" status); [ "$st" = BREACHED_PLAYER ] && seen_breach=1
  note=$(deal_field "$id" "evidence->>'note'")
  cancel_line=$(since_srv | grep -a "Deals from after the loaded save cancelled" | grep -a -c -F "$id")
  local paid=$(( ${m0:-0} - ${m1:-0} ))
  if [ "$seen_breach" = 1 ]; then verdict D86 "FAIL deal $id went BREACHED_PLAYER after the older-save load (pre-load $st_pre, paid $paid)"
  elif [ "$st" = CANCELLED ] && [ "$note" = rolled_back_by_load ] && [ "${cancel_line:-0}" -ge 1 ]; then
    verdict D86 "PASS deal $id $st_pre -> CANCELLED note=rolled_back_by_load (server cancel line), never BREACHED_PLAYER in 90 s; paid $paid cats"
  else verdict D86 "FAIL deal $id after load: status=$st note=${note:-none} cancel_log=$cancel_line (pre-load $st_pre, paid $paid)"; fi
}

row_D94() {
  preflight D94
  command -v stobe-reset-npc >/dev/null || setup_fail D94 "stobe-reset-npc not installed"
  local setting lower f envp keys0 aff0 keys1 keys2 aff2 rkeys2 exp="$PLAYER" out
  setting=$(PSQLQ "SELECT value FROM general_settings WHERE id='PLAYER_NAME'")
  lower=$(echo "$MATE" | tr '[:upper:]' '[:lower:]')
  if [ "$(echo "$setting" | tr '[:upper:]' '[:lower:]')" = "$(echo "$PLAYER" | tr '[:upper:]' '[:lower:]')" ]; then
    envp=(env -u PLAYER); f=/root/stobe-backups/relationship_saved/$lower.json        # item 94 path: setting "$setting"
  else envp=(env PLAYER="$PLAYER"); f=/root/stobe-backups/relationship_saved/$lower.$(echo "$PLAYER" | tr '[:upper:]' '[:lower:]').json; fi
  kq() { PSQLQ "SELECT string_agg(k, ',' ORDER BY k) FROM core_npc_master m, jsonb_object_keys(CASE WHEN jsonb_typeof(m.extended_data->'relationships')='object' THEN m.extended_data->'relationships' ELSE '{}'::jsonb END) k WHERE LOWER(m.name)=LOWER('$(sq "$MATE")') AND LOWER(k)=LOWER('$(sq "$PLAYER")')"; }
  rq() { PSQLQ "SELECT string_agg(k, ',' ORDER BY k) FROM core_npc_master m, jsonb_object_keys(CASE WHEN m.relationships ~ '^\s*\{.*\}\s*$' THEN m.relationships::jsonb ELSE '{}'::jsonb END) k WHERE LOWER(m.name)=LOWER('$(sq "$MATE")') AND LOWER(k)=LOWER('$(sq "$PLAYER")')"; }
  aq() { PSQLQ "SELECT v->>'aff' FROM core_npc_master m, jsonb_each(CASE WHEN jsonb_typeof(m.extended_data->'relationships')='object' THEN m.extended_data->'relationships' ELSE '{}'::jsonb END) e(k, v) WHERE LOWER(m.name)=LOWER('$(sq "$MATE")') AND LOWER(k)=LOWER('$(sq "$PLAYER")') LIMIT 1"; }
  keys0=$(kq)
  if [ -z "$keys0" ]; then
    (cd /tmp && sudo -u www-data php $SRVROOT/tools/social_relationship_inspect.php --set-relation "$MATE" "$PLAYER" 20) >/dev/null 2>&1
    keys0=$(kq); [ -n "$keys0" ] || setup_fail D94 "$MATE has no key for $PLAYER and --set-relation did not add one"
  fi
  stobe-say speed 1 >/dev/null 2>&1
  aff0=$(aq); log "D94 before: keys=$keys0 aff=$aff0 saved-file=$( [ -s "$f" ] && echo existing || echo none)"
  out=$("${envp[@]}" stobe-reset-npc "$MATE" "$(date +%F)" 2>&1); log "reset: $(echo "$out" | tail -2 | tr '\n' ' ' | cut -c1-200)"
  keys1=$(kq)
  [ -z "$keys1" ] || { verdict D94 "FAIL reset left the key: $keys1"; return; }
  [ -s "$f" ] || { verdict D94 "FAIL reset saved no entry ($f)"; return; }
  local want_aff; want_aff=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("aff",""))' "$f" 2>/dev/null)
  out=$("${envp[@]}" stobe-reset-npc --restore "$MATE" 2>&1); log "restore: $(echo "$out" | tail -1 | cut -c1-200)"
  talk "$MATE" "$MATE, everything all right with us?" 20
  stobe-say speed 0 >/dev/null 2>&1
  keys2=$(kq); rkeys2=$(rq); aff2=$(aq)
  log "after: extended keys=$keys2 column keys=$rkeys2 aff=$aff2 (saved aff $want_aff, before $aff0)"
  if [ "$keys2" = "$exp" ] && [ "$rkeys2" = "$exp" ] && [ "$aff2" = "$want_aff" ]; then
    verdict D94 "PASS restore key '$keys2' in both copies (PLAYER_NAME setting '$setting'), aff $aff2 = saved entry"
  elif [ "$keys2" = "$exp" ] && [ "$rkeys2" = "$exp" ]; then
    verdict D94 "FAIL key case ok ('$keys2') but aff $aff2 != saved $want_aff (a chat line may have moved it: check the evaluator)"
  else verdict D94 "FAIL keys after restore: extended='$keys2' column='$rkeys2' (want '$exp'; setting '$setting')"; fi
}

row_D99() {
  inner D99 STOBE-15-buy-approval.sh decline
  local row; row=$(grep -a "approval row: " "$INNER_OUT" | tail -1 | sed 's/.*approval row: //' | cut -c1-160)
  if echo "$row" | grep -q WAITING_APPROVAL; then verdict D99 "PASS WAITING_APPROVAL buy row: $row"
  elif grep -a -q "SETUP FAIL" "$INNER_OUT"; then verdict D99 "FAIL SETUP FAIL (STOBE-15) $(grep -a 'VERDICT' "$INNER_OUT" | tail -1 | sed 's/.*VERDICT 15: //' | cut -c1-150)"
  else verdict D99 "FAIL no WAITING_APPROVAL row (STOBE-15 rc=$INNER_RC): $(grep -a 'VERDICT' "$INNER_OUT" | tail -1 | sed 's/.*VERDICT 15: //' | cut -c1-150)"; fi
  rm -f "$INNER_OUT"
}

row_D101() {
  d101_exit() {  # never leave his row as '[]'
    heal_stop; stobe-auto speed 0 >/dev/null 2>&1
    [ -n "${NPCQ:-}" ] && PSQLQ "UPDATE core_npc_master SET extended_data='{}'::jsonb WHERE LOWER(name)=LOWER('$NPCQ') AND jsonb_typeof(extended_data)<>'object'" >/dev/null
  }
  trap d101_exit EXIT
  preflight D101
  local firsts=(Tavi Orla Brenn Kesh Mora Vell Ilsa Dorn) lasts=(Quorn Fallow Drem Sarrow Ilk Tamsin Vorle Hask)
  local s; s=$(date +%s)
  local NPC="${firsts[$((s % 8))]} ${lasts[$(((s / 8) % 8))]}"
  NPCQ=$(sq "$NPC")
  local h tx td pe0 pe1 a_aff b_keys mode fights shape note_b=""
  pe0=$(pg_err_count)
  h=$(spawn_neutral "$NPC" 6) || setup_fail D101 "spawn failed"
  sleep 4; greet "$NPC"
  wait_for 60 eval "[ -n \"\$(PSQLQ \"SELECT 1 FROM core_npc_master WHERE LOWER(name)=LOWER('$NPCQ')\")\" ]" || { put_away "$h"; setup_fail D101 "server made no core_npc_master row for '$NPC' within 60 s of the greeting"; }
  shape=$(PSQLQ "SELECT jsonb_typeof(extended_data)||'/'||jsonb_typeof(metadata) FROM core_npc_master WHERE LOWER(name)=LOWER('$NPCQ') LIMIT 1")
  log "D101 new row '$NPC' extended_data/metadata: $shape"
  # (a) the tool's set-relation on a '[]' row
  PSQLQ "UPDATE core_npc_master SET extended_data='[]'::jsonb WHERE LOWER(name)=LOWER('$NPCQ')" >/dev/null
  (cd /tmp && sudo -u www-data php $SRVROOT/tools/social_relationship_inspect.php --set-relation "$NPC" "$PLAYER" 37) 2>&1 | tail -1 | cut -c1-160 >&2
  a_aff=$(PSQLQ "SELECT jsonb_typeof(extended_data)||':'||COALESCE((SELECT v->>'aff' FROM jsonb_each(CASE WHEN jsonb_typeof(extended_data->'relationships')='object' THEN extended_data->'relationships' ELSE '{}'::jsonb END) e(k,v) WHERE LOWER(k)=LOWER('$(sq "$PLAYER")') LIMIT 1),'none') FROM core_npc_master WHERE LOWER(name)=LOWER('$NPCQ') LIMIT 1")
  log "(a) after set-relation on '[]': $a_aff"
  # (b) a real fight: the server's attack rule writes his map (R4; retired when REL scores fights)
  mode=$(PSQLQ "SELECT value FROM general_settings WHERE id='SOCIAL_RELATIONSHIP_MODE'")
  fights=$(PSQLQ "SELECT value FROM general_settings WHERE id='RELATIONSHIP_FIGHTS_COUNT'")
  if [ "$mode" = enabled ] || [ "$mode" = fights ] || [ "$fights" = false ] || [ "$fights" = 0 ]; then
    note_b="(b) skipped: mode=$mode fights_count=${fights:-default}"; b_keys=skip
  else
    PSQLQ "UPDATE core_npc_master SET extended_data='[]'::jsonb WHERE LOWER(name)=LOWER('$NPCQ')" >/dev/null
    heal_start "$PLAYER"
    stobe-auto protect "$h" on >/dev/null 2>&1 && PROTECTED="${PROTECTED:-} $h"
    stobe-auto teleport "$h" "$PLAYER" dist 3 >/dev/null
    stobe-say speed 1 >/dev/null
    for i in $(seq 1 8); do
      stobe-auto attack "$PLAYER" "$h" >/dev/null; stobe-auto attack "$h" "$PLAYER" >/dev/null; sleep 4
      since_stobe | grep -a -F "[EVENT] combat: $NPC" | grep -a -q . && break
    done
    b_keys=""
    for i in $(seq 1 15); do
      b_keys=$(PSQLQ "SELECT jsonb_typeof(extended_data)||':'||COALESCE((SELECT string_agg(k||'='||(v->>'aff'), ',') FROM jsonb_each(CASE WHEN jsonb_typeof(extended_data->'relationships')='object' THEN extended_data->'relationships' ELSE '{}'::jsonb END) e(k,v)),'none') FROM core_npc_master WHERE LOWER(name)=LOWER('$NPCQ') LIMIT 1")
      echo "$b_keys" | grep -q -i "^object:.*$PLAYER=" && break; sleep 3
    done
    heal_stop; stobe-say speed 0 >/dev/null
    note_b="(b) fight wrote: $b_keys; combat events: $(since_stobe | grep -a -F "[EVENT] combat: $NPC" | grep -a -c .)"
  fi
  stobe-auto ko "$h" 900 >/dev/null 2>&1; put_away "$h"
  pe1=$(pg_err_count)
  log "$note_b; postgres array-path errors $pe0 -> $pe1"
  if [ "${shape}" != "object/object" ]; then verdict D101 "FAIL new NPC row created with extended_data/metadata '$shape' (want object/object)"
  elif [ "$a_aff" != "object:37" ]; then verdict D101 "FAIL set-relation on a '[]' row gave '$a_aff' (want object:37)"
  elif [ "$b_keys" != skip ] && ! echo "$b_keys" | grep -q -i "^object:.*$PLAYER="; then verdict D101 "FAIL $note_b"
  elif [ "${pe1:-0}" -gt "${pe0:-0}" ]; then verdict D101 "FAIL $(( pe1 - pe0 )) new postgres 'path element at position 1' errors"
  else verdict D101 "PASS '$NPC' new row object/object; '[]' row set-relation -> aff 37; ${note_b:0:110}; no new pg errors"; fi
}

row_D105() {
  local k0 f0 t0 t1 rk rf acc bound
  k0=$(grep -a -c "" "$KFP" 2>/dev/null || echo 0); f0=$(grep -a -c "" "$KFPLOG" 2>/dev/null || echo 0); t0=$(date +%s)
  inner D105 STOBE-A8-bread-chain.sh
  t1=$(date +%s)
  rk=$(tail -n +"$((k0 + 1))" "$KFP" | grep -a -c "WORK_GOAL input ratio")
  rf=$(tail -n +"$((f0 + 1))" "$KFPLOG" 2>/dev/null | grep -a -c "WORK_GOAL input ratio")
  acc=$(tail -n +"$((k0 + 1))" "$KFP" | grep -a -c "WORK_GOAL accepted")
  bound=$(( 8 * ((t1 - t0) / 30 + 1) ))
  log "D105: ${rk} ratio lines in stobe_goals.log, ${rf} in KenshiFP.log over $((t1 - t0)) s (bound $bound); WORK_GOAL accepted=$acc; A8: $(grep -a '(inner) VERDICT' "$INNER_OUT" | tail -1 | cut -c1-120)"
  if [ "${acc:-0}" -lt 1 ]; then verdict D105 "FAIL SETUP FAIL no work goal ran (no WORK_GOAL accepted; A8 rc=$INNER_RC $(grep -a '(inner) VERDICT' "$INNER_OUT" | tail -1 | cut -c20-140))"
  elif [ $(( rk + rf )) -gt "$bound" ]; then verdict D105 "FAIL ratio spam: stobe_goals.log $rk + KenshiFP.log $rf lines in $((t1 - t0)) s (bound $bound)"
  else verdict D105 "PASS input-ratio lines stobe_goals.log=$rk KenshiFP.log=$rf in $((t1 - t0)) s (bound $bound), work goal ran (A8: $(grep -a '(inner) RESULT' "$INNER_OUT" | tail -1 | awk '{print $4}'))"; fi
  rm -f "$INNER_OUT"
}

# --- main: each row once, exactly one RESULT line each ----------------------------------------------------------
for r in $ROWS; do
  case "$r" in D70|D86|D94|D99|D101|D105) ;; *) echo "RESULT $r FAIL SETUP FAIL unknown row (D70 D86 D94 D99 D101 D105)"; continue ;; esac
  tmp=/tmp/stobe-dconfirm-row.$$.txt
  log "=== $r"
  ( "row_$r" ) | tee "$tmp"
  rc=${PIPESTATUS[0]}
  grep -q "^RESULT $r " "$tmp" || verdict "$r" "FAIL row ended without a verdict (exit $rc)"
  rm -f "$tmp"
  sw_off >/dev/null 2>&1
done
