#!/usr/bin/env bash
# reloaddefs_b.sh: save/load RESUME rows, set B (imm26-reloadrows-B): deals, restitution scope, trips. Row functions in go-row.sh style (rd_<id>), run through
# rowtools/reloadrun-b.sh (one call per row; it sources go-row.sh, then this file, and swaps the verdict script for reloadcheck_b.py via pywrap_b.sh).
# Rows: 14-e 13-f 13-g 10-e 19-e 19-f.   Needs rowlib.sh/rowdefs.sh/tripdefs.sh helpers (rd19_load, rd19_place, rd19_trip, rd19_dump, rd19_state, rd_aff, tr_prep).
# Env knobs: ROW_NPC ("Cind [Hungry Bandit]")  ROW_BACKDATE_S (540, 14-e: age of the open offer before the save; the 10 min window then needs the pause)
#   ROW_19E_QUIET_S (30: silent control window after the load, 19-e) ROW_19E_SPEED (2)   ROW_19F_N (4 reloads) ROW_19F_MODE (target|cap) ROW_19F_CAP (setting STOBE_TRIP_RESUME_MAX_COUNT for the run)
#   ROW_13_TALK (1: one chat turn after the load before paying/breaching; it is also what triggers the first negotiation tick of the new load)
# Evidence (all under $EV): deal_<tag>.txt = "contract_id|status|resume_shift_total|age_s|KIND:STATUS,...|resume_shifts-json" (newest contract / the named one),
#   clock_<tag>.txt (stobe_deal_clock), t_*.txt (unix times), fired_*.txt (NEG_TEST_INJECT fired lines in the server log), effects_deal.txt, price.txt, probe_*.json.
# Deterministic deals: NEG_TEST_INJECT (general_settings; removed again at the end of every row) replaces the model reply BEFORE the logic under test (as 13-a).
RB_TERMS='[{"kind":"GIVE_ITEM","by":"npc","to":"player","item":"Bread","quantity":1},{"kind":"GIVE_CATS","by":"player","to":"npc","amount":20,"when":"after_npc"}]'
RB_OFFER_TEXT="Cind, give me one of your bread now and I'll pay you 20 cats later."
RB_PROBE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/repairprobe.php"

rb_cfg() { ROW_NPC="${ROW_NPC:-Cind [Hungry Bandit]}"; export ROW_NPC; }
rb_deal_clean() {   # leftover deals/directives out of the way (preflight does the same; harmless twice)
  lt_sqlx "UPDATE stobe_social_contract SET status='CANCELLED' WHERE status IN ('AWAITING_PERFORMANCE','PROPOSED','COUNTERED','ACCEPTED'); DELETE FROM stobe_negotiation_directive WHERE consumed_unix=0" >> "$EV/clean.txt" 2>&1
}
rb_inject() {   # rb_inject '<steps json array>'  (chat context, npc = first word of the NPC name)
  local j; j=$(printf '{"row":"%s","npc":"%s","context":"chat","steps":%s}' "${RL_ROW:-rb}" "${RL_NPC_FULL%% *}" "$1")
  lt_sqlx "DELETE FROM general_settings WHERE id='NEG_TEST_INJECT'; INSERT INTO general_settings (id,value) VALUES ('NEG_TEST_INJECT', \$q\$$j\$q\$);" >> "$EV/inject.txt" 2>&1
}
rb_inject_off() { lt_sqlx "DELETE FROM general_settings WHERE id='NEG_TEST_INJECT'" >> "$EV/inject.txt" 2>&1; }
rb_setting() {  # rb_setting <id> <value|-> : set (or delete with -) a general_settings row
  lt_sqlx "DELETE FROM general_settings WHERE id='$1'$( [ "$2" = - ] || printf "; INSERT INTO general_settings (id,value) VALUES ('%s','%s')" "$1" "$2" )" >> "$EV/settings.txt" 2>&1
}
rb_fired() {   # number of NEG_TEST_INJECT fired lines in the lane's server log (rb:fired)
  printf "grep -a -c 'NEG_TEST_INJECT fired' %s 2>/dev/null || echo 0 # rb:fired\n" "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9
}
rb_snap_deal() {   # rb_snap_deal <tag> [contract_id] -> deal_<tag>.txt
  local w="true"; [ -n "${2:-}" ] && w="contract_id='$2'"
  lt_sql "select contract_id||'|'||status||'|'||coalesce(resume_shift_total,0)||'|'||extract(epoch from (now()-updated_at))::int||'|'||coalesce((select string_agg((e->>'kind')||':'||coalesce(e->>'status',''),',') from jsonb_array_elements(term_state) e),'')||'|'||coalesce(resume_shifts::text,'[]') from stobe_social_contract where $w order by created_at desc limit 1 /* rb:deal */" 2>&1 | tr -d '\r' | head -1 > "$EV/deal_$1.txt"
}
rb_deal_field() { cut -d'|' -f"$2" "$EV/deal_$1.txt" 2>/dev/null | head -1; }
rb_poll_deal() {   # rb_poll_deal <tag> <id> <tries> <sleep_s> <regex over the whole snapshot line>
  local k
  for k in $(seq 1 "${3:-8}"); do
    rb_snap_deal "$1" "$2"
    grep -qE "$5" "$EV/deal_$1.txt" && return 0
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${4:-8}"
  done
  return 0
}
rb_clock_snap() { lt_sql "select load_token||'|'||last_tick_unix from stobe_deal_clock where id=1 /* rb:clock */" 2>&1 | tr -d '\r' | head -2 > "$EV/clock_$1.txt"; }
rb_now() { lt_sql "select extract(epoch from now())::bigint /* rb:now */" 2>&1 | tr -dc 0-9 > "$EV/$1"; }
rb_pause_log() { printf "grep -a 'Deal clocks paused across a load' %s 2>/dev/null | tail -3 | cut -c1-300 # rb:pauselog\n" "$LT_SRVLOG" | lt_w > "$EV/pause_log.txt" 2>&1; }
rb_saveload() {   # rb_saveload <save>: save, load, wait-world (rd19_load), NPC back near Shay (rd19_place); rc 3 + RL_REASON on failure
  local sv="$1"
  printf 'stobe-auto save %s </dev/null | head -1\n' "$sv" | lt_h > "$EV/save.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
  echo "$sv" > "$EV/save_name.txt"
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/load_rowid.txt"
  rd19_load "$sv" || return 3
  rd19_place near || return 3
}
rb_give_bread() { printf 'stobe-auto give %s Bread 3 </dev/null | head -1\n' "$(rl_q "$RL_NPC_ID")" | lt_h >> "$EV/give.txt" 2>&1; }
rb_deal_start() {   # common start of the deal rows: NPC resolved, deal clean, aff 75, Bread on the NPC, injection off
  rb_cfg; rd_need_npc || return 3; echo "$RL_NPC_FULL" > "$EV/npc.txt"
  rb_deal_clean; rb_inject_off; rd_aff 75 platonic haff
  rb_give_bread
}
rb_price() {   # the engine-priced Cats the player owes: GIVE_CATS amount from term_state, else (COUNTERED/PROPOSED, no term_state yet) from the `terms` column -> stdout
  lt_sql "select coalesce((select e->>'amount' from jsonb_array_elements(case when jsonb_typeof(c.term_state)='array' then c.term_state else '[]'::jsonb end) e where e->>'kind'='GIVE_CATS' limit 1),(select e->>'amount' from jsonb_array_elements(case when jsonb_typeof(c.terms)='array' then c.terms else '[]'::jsonb end) e where e->>'kind'='GIVE_CATS' limit 1),'') from stobe_social_contract c where c.contract_id='$1' /* rb:price */" 2>&1 | tr -dc 0-9 | head -c 9
}
rb_reprice_inject() {   # rb_reprice_inject <contract_id>: the engine raised the Cats to her relationship price (e.g. 353) and turned the injected ACCEPT-at-20 into a COUNTER; re-inject the ACCEPT at the READ price (replaces the stale step)
  local rbp; rbp=$(rb_price "$1"); echo "${rbp:-}" > "$EV/reprice.txt"
  [ -n "$rbp" ] && [ "$rbp" -gt 0 ] 2>/dev/null || return 0   # no price readable: keep the old injection (the later price check reports it)
  rb_inject "[{\"deal_decision\":\"ACCEPT\",\"deal_terms\":${RB_TERMS/\"amount\":20,/\"amount\":$rbp,},\"message\":\"Deal then.\"}]"
}

rd_14e() {   # counter-offer open, save + load within minutes, then accept: the deal windows were paused by the reload (wpR2)
  rb_deal_start || return $?
  rb_fired > "$EV/fired_before.txt"
  rb_inject "[{\"deal_decision\":\"COUNTER\",\"deal_terms\":$RB_TERMS,\"message\":\"Not for free: bread now, and you pay me after.\"},{\"deal_decision\":\"ACCEPT\",\"deal_terms\":$RB_TERMS,\"message\":\"Deal then.\"}]"
  rl_inv before
  rl_say 1 "$RB_OFFER_TEXT" || { local rc=$?; rb_inject_off; return $rc; }
  rb_snap_deal s1
  local id st; id=$(rb_deal_field s1 1); st=$(rb_deal_field s1 2)
  case "$st" in PROPOSED|COUNTERED) ;; *) rb_inject_off; RL_REASON="no open counter-offer after s1 (contract='$id' status='$st'): see $EV/deal_s1.txt"; return 3;; esac
  rb_reprice_inject "$id"
  rb_clock_snap pre
  lt_sqlx "update stobe_social_contract set updated_at=now()-make_interval(secs => ${ROW_BACKDATE_S:-540}::double precision) where contract_id='$id' and status in ('PROPOSED','COUNTERED')" >> "$EV/backdate.txt" 2>&1
  rb_snap_deal backdated "$id"; rb_now t_backdate.txt
  rb_saveload "kah-imm26-14e-$LT_LANE" || { local rc=$?; rb_inject_off; return $rc; }
  rb_snap_deal post "$id"
  rl_say 2 "Deal. I accept your terms." || { local rc=$?; rb_inject_off; return $rc; }
  rb_now t_accept.txt
  rb_poll_deal end "$id" 8 8 'GIVE_ITEM:VERIFIED'
  rb_clock_snap post; rb_pause_log; rb_fired > "$EV/fired_after.txt"; rl_inv after; rb_inject_off
}

rb_paylater_to_pending() {   # pay-later deal (NPC gives Bread now, player pays Cats after) up to AWAITING_PERFORMANCE with the NPC leg VERIFIED; sets RB_ID
  rb_deal_start || return $?
  rb_inject "[{\"deal_decision\":\"ACCEPT\",\"deal_terms\":$RB_TERMS,\"message\":\"Fine, bread now, twenty cats later.\"},{\"deal_decision\":\"ACCEPT\",\"deal_terms\":$RB_TERMS,\"message\":\"Deal then.\"}]"
  rl_inv before
  rl_say 1 "$RB_OFFER_TEXT" || { local rc=$?; rb_inject_off; return $rc; }
  rb_snap_deal s1
  local st; RB_ID=$(rb_deal_field s1 1); st=$(rb_deal_field s1 2)
  case "$st" in
    PROPOSED|COUNTERED) rb_reprice_inject "$RB_ID"; rl_say 2 "Deal. I accept your terms." || { local rc=$?; rb_inject_off; return $rc; };;
    ACCEPTED|AWAITING_PERFORMANCE) ;;
    *) rb_inject_off; RL_REASON="no pay-later deal after s1 (contract='$RB_ID' status='$st'): see $EV/deal_s1.txt"; return 3;;
  esac
  rb_inject_off
  rb_poll_deal pre "$RB_ID" 10 8 '\|AWAITING_PERFORMANCE\|.*GIVE_ITEM:VERIFIED'
  rb_price "$RB_ID" > "$EV/price.txt"
  rb_clock_snap pre
}
rb_after_reload() {   # save + load + (one chat turn: first negotiation tick of the new load) ; snapshot deal_post
  rb_saveload "$1" || return $?
  rb_snap_deal post "$RB_ID"
  if [ "${ROW_13_TALK:-1}" = 1 ]; then rl_say 3 "Still good with the deal?" || return $?; fi
  rb_snap_deal talk "$RB_ID"
}
rb_effects() { lt_sql "select game_ts||'|'||component||'|'||delta||'|'||incident_id||'|'||applied from social_effect where incident_id='deal:$RB_ID' order by game_ts /* rb:effects */" 2>&1 | tr -d '\r' > "$EV/effects_deal.txt"; }

rd_13g() {   # pay-later deal accepted, reload, pay -> COMPLETE + kept_promise
  rb_paylater_to_pending || return $?
  rb_after_reload "kah-imm26-13g-$LT_LANE" || return $?
  local price; price=$(tr -dc 0-9 < "$EV/price.txt")
  [ -n "$price" ] && [ "$price" -gt 0 ] 2>/dev/null || { RL_REASON="cannot read the GIVE_CATS price of $RB_ID (price.txt empty)"; return 3; }
  lt_h <<EOT >> "$EV/pay.txt" 2>&1
stobe-auto money Shay -$price </dev/null | head -2
stobe-auto money $(rl_q "$RL_NPC_ID") $price </dev/null | head -2 # rb:money
EOT
  rb_poll_deal end "$RB_ID" 12 10 '\|(COMPLETE|BREACHED_PLAYER|BREACHED_NPC|EXPIRED|IMPOSSIBLE|CANCELLED)\|'
  rb_effects; rb_clock_snap post; rb_pause_log; rl_inv after
}
rd_13f() {   # pay-later deal accepted, reload, DO NOT pay and force the deadline past -> BREACHED_PLAYER + broken_promise (the obligation survived the reload)
  rb_paylater_to_pending || return $?
  rb_after_reload "kah-imm26-13f-$LT_LANE" || return $?
  local sht g; sht=$(rb_deal_field talk 3); sht=${sht:-0}
  g=$(lt_sql "select coalesce(max(gamets),0) from eventlog /* rb:gamets */" | head -1 | tr -dc 0-9); g=${g:-0}
  lt_sqlx "update stobe_social_contract set deadline_unix=extract(epoch from now())::int-(${sht}+60), deadline_gamets=${g}-30 where contract_id='$RB_ID'" >> "$EV/force.txt" 2>&1
  rb_poll_deal end "$RB_ID" 14 10 '\|(COMPLETE|BREACHED_PLAYER|BREACHED_NPC|EXPIRED|IMPOSSIBLE|CANCELLED)\|'
  rb_effects; rb_clock_snap post; rb_pause_log
}

rd_10e() {   # restitution scope across a REAL load (seeded in-memory agreements frozen at the real pre-load scope; repairprobe.php, no DB write)
  rb_cfg; rd_need_npc || return 3; echo "$RL_NPC_FULL" > "$EV/npc.txt"
  local npc="${RL_NPC_FULL%% \[*}" r
  rb_probe_run() { printf 'cd %s/site; KAH_LANE_ROOT=%s KAH_LANE_DB=%s php %s %s %s %s 2>&1 | head -c 8000 # rb:probe\n' "$LT_ROOT" "$LT_ROOT" "$LT_DB" "$(rl_wsl_path "$RB_PROBE")" "$1" "$(rl_q "${2:-}")" "$(rl_q "$npc")" | lt_w; }
  rb_probe_run scope > "$EV/probe_pre.json" 2>&1
  rb_saveload "kah-imm26-10e-$LT_LANE" || return 3
  r=$(head -1 "$EV/probe_pre.json")
  rb_probe_run eval "$r" > "$EV/probe_eval.json" 2>&1
  rb_probe_run scope > "$EV/probe_post.json" 2>&1
}

rb_19e_close() {   # teleport the NPC to Shay and verify (where) she is <= ${ROW_19E_MAXDIST:-40} u away right before s4; else rc 3 + RL_REASON (SETUP-FAIL). Evidence: $EV/near_s4.txt
  local max="${ROW_19E_MAXDIST:-40}" n w d try
  RL_NPC_ID=""; rd_need_npc || return 3
  n=$(rl_q "$RL_NPC_FULL")
  for try in 1 2; do
    echo "try $try: before dist=${RL_DIST:-?}" >> "$EV/near_s4.txt"
    printf 'stobe-auto teleport %s Shay </dev/null | head -1\n' "$n" | lt_h >> "$EV/near_s4.txt" 2>&1
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep 2
    w=$(printf 'stobe-auto where %s </dev/null 2>&1 | head -1 # rb:near19e\n' "$n" | lt_h 2>&1 | head -1)
    d=$(echo "$w" | sed -nE 's/.* dist=([0-9.]+).*/\1/p' | head -1)
    echo "try $try: after teleport where=$w" >> "$EV/near_s4.txt"
    if [ -n "$d" ] && awk -v d="$d" -v m="$max" 'BEGIN{exit !(d+0<=m+0)}'; then echo "near_s4 ok dist=$d (<= $max)" >> "$EV/near_s4.txt"; RL_DIST="$d"; return 0; fi
  done
  RL_REASON="19-e recipe: $RL_NPC_FULL is ${d:-unreadable} u from Shay after 2 teleports (limit $max u; the resume needs her inside the 80 u people list at s4); not a product failure, see $EV/near_s4.txt"
  return 3
}

rd_19e() {   # visited-town trip, LAZY resume (Shay 2026-10-15): after the reload NOTHING may resume before a chat turn (control), the first chat line then resumes the SAME agreement
  rd19_prep || return $?
  local ROW_19_DEST="${TR_DEST:-Squin}"
  ROW_19A_NC=0 rd19_trip || return $?
  rd19_place near || return $?
  local l n=0; l=$(rl_mark | awk '{print $3}'); l=${l:-0}
  # control: a quiet window with the player silent; the NPC must not run off while the player loads (no OWNED_TRAVEL accepted=1, no requested/running row after the load)
  echo "stobe-auto speed ${ROW_19E_SPEED:-2} </dev/null | head -1" | lt_h >> "$EV/silent.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_19E_QUIET_S:-30}"
  echo "stobe-auto speed 0.5 </dev/null | head -1" | lt_h >> "$EV/silent.txt" 2>&1
  n=$(printf "tail -n +%s %s | grep -a -c 'OWNED_TRAVEL.*accepted=1' # rb:silentpoll
" "$((l+1))" "$LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); n=${n:-0}
  echo "quiet_s=${ROW_19E_QUIET_S:-30} owned_travel_accepted=$n" > "$EV/quiet.txt"
  rd19_dump agr_ctl.txt
  # 19-e recipe fix (fix19erecipe): the 30 s quiet window lets her wander (107.6 u at s4 = beyond the 80 u people-list limit -> 'Trip resume wait' why=not_in_people); put her next to Shay right before s4
  rb_19e_close || return $?
  # the one chat line: first post-load turn = the resume turn
  rl_say 4 "Where were we going?" || return $?
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s4.txt
  # 19E-FIX: the server writes phase `running` only when it ingests the native receipt, and that rides on the NEXT request after the resume turn -> second post-load line (as rd_19a)
  rd19_place near || return $?
  rl_say 5 "I'm right behind you." || return $?
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
  rd19_state post_s5.txt
  rd19_dump agr_all.txt
}

rd_19f() {   # N reloads in one trip: every one must resume (target) / the cap-th+1 ends honestly FAILED resume_count (cap mode)
  rd19_prep || return $?
  local ROW_19_DEST="${TR_DEST:-Squin}" N="${ROW_19F_N:-4}" mode="${ROW_19F_MODE:-target}" i rc=0
  echo "$mode" > "$EV/mode.txt"; echo "$N" > "$EV/n.txt"
  [ -n "${ROW_19F_CAP:-}" ] && { echo "$ROW_19F_CAP" > "$EV/cap.txt"; rb_setting STOBE_TRIP_RESUME_MAX_COUNT "$ROW_19F_CAP"; }
  ROW_19A_NC=0 rd19_trip || { rc=$?; [ -n "${ROW_19F_CAP:-}" ] && rb_setting STOBE_TRIP_RESUME_MAX_COUNT -; return $rc; }
  for i in $(seq 1 "$N"); do
    if [ "$i" -gt 1 ]; then   # the first load is the one rd19_trip did; further reloads of the same trip
      printf 'stobe-auto save %s </dev/null | head -1\n' "kah-imm26-19f-$LT_LANE" | lt_h >> "$EV/save.txt" 2>&1
      [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
      rd19_load "kah-imm26-19f-$LT_LANE" || { rc=3; break; }
    fi
    rd19_place near || { rc=3; break; }
    rl_say "r$i" "Where were we going?" || { rc=$?; break; }
    [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_RESUME_WAIT:-8}"
    rd19_state "post_r$i.txt"; rd19_dump "agr_r$i.txt"
  done
  [ -n "${ROW_19F_CAP:-}" ] && rb_setting STOBE_TRIP_RESUME_MAX_COUNT -
  rd19_dump agr_all.txt
  return $rc
}
