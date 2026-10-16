#!/usr/bin/env bash
# reloaddefs_a.sh: save+load RESUME rows, set A (imm26-reloadrows-A). Sourced by reload-run.sh / reload-cycle.sh AFTER go-row.sh (so rowlib, rowdefs,
# tripdefs helpers exist). rowdefs.sh / tripdefs.sh / rowcheck.py are NOT edited: the checker is reloadcheck_a.py (reload-run.sh wraps $PY).
#   Rows : rd_26d (accepted Hunt survives)  rd_26dx (cancelled Hunt stays cancelled, NC)  rd_26e (proposed Hunt survives, re-PROPOSE needed)
#          rd_26f (ClearGroup / camp, same legs as 26-d)  rd_24c (area-goal trip across a reload)  rd_23e (legacy FOLLOW across a reload)
#          rd_27a (BODYGUARD order across a reload)  rd_08e (open follow-up topic across a reload, claimed once by a bored tick)
#          rd_20d (pending plan change across a reload, bare "yes" confirms)
#   Helpers: rw_save_load <tag> [near|far] = save + load + wait-world + re-place the NPC (reuses rd19_load/rd19_place; load_rowid.txt written first).
# Server behaviour under test (deploy notes inbox/operators/wpR1/wpR3-deployed.txt): the resumed activity continuation gets a NEW agreement id chained via
#   record.resume.of / old record superseded + resume.continuedAs; a resumed PROPOSAL keeps its id, is re-bound to the new world, and needs the NPC to PROPOSE
#   again before "Yes" accepts; resume fires on a CHAT TURN with that actor while the target is observed (so goats/bandits are re-spawned next to the NPC
#   right before the post-load say). Work goals created AFTER an older save are dropped by design (wpR3, bug 83): no row here loads an older save for them.
# Env knobs: RW_KIND (Hunt) RW_OFFER RW_ACCEPT RW_RESUME_SAY RW_SPAWN_CMD (body run on the harness, replaces the default spawn) RW_COMPLETE=1 (26-d/26-f: wait
#   RW_HUNT_WAIT s (180) at speed 3 and require COMPLETED) RW_AWAY (80) RW_CHASE_S (30) RW_BG_ARGS ("hours 24 own") RW_FU_SAY RW_ADV (120 s at speed 10)
#   RW_TICK_CHUNKS (4) RW_ALT (the Stumble Inn) RW_20D_RESUME_FIRST=1 (insert a "Where were we going?" turn before the bare yes) RW_SAY_WAIT (8).
# Every row only writes evidence below $EV; the verdict is reloadcheck_a.py's.

RW_OFFER_DEF="Look at all these goats. Let's hunt for raw meat."   # (kept out of ${VAR:-...}: bash 5.2 reads the apostrophe as a quote there)
RW_ACCEPT_DEF="Yes, let's do it."
rw_prep() {  # resolve the NPC, clean activity + trip rows, H-AFF 60 platonic, quiet scene; ROW_NATIVE=1
  tr_cfg; unset ROW_NATIVE
  rd_need_npc || return 3
  echo "$RL_NPC_FULL" > "$EV/npc.txt"
  lt_sqlx "delete from stobe_activity_outbox" >> "$EV/clean.txt" 2>&1
  lt_sqlx "delete from stobe_activity_record" >> "$EV/clean.txt" 2>&1
  tr_clean_db; rd_aff 60 platonic haff
  [ "${TRIP_QUIET:-1}" = 0 ] || tr_quiet
  unset TR_SCENE; rl_resolve "$ROW_NPC" >/dev/null 2>&1
  ROW_NATIVE=1
  return 0
}
rw_sleep() { [ -n "${KAH_ROW_FAKE:-}" ] || sleep "$1"; }
rw_logn() { echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9; }
rw_log() {  # rw_log <file> <n0> [pattern]: stobe.log lines after n0 matching the pattern (default ACTIVITY)
  printf 'tail -n +%s %s | grep -a -E %s | cut -c1-300 | tail -80\n' "$(( ${2:-0} + 1 ))" "$LT_STOBELOG" "$(rl_q "${3:-ACTIVITY}")" | lt_h > "$EV/$1" 2>&1
}
rw_act_dump() {  # id|world|actor|requester|revision|status|kind|resourceId|quantity|resume.state|resume.of|resume.continuedAs|resume.count|agreedTargets|campZone
  lt_sql "select id||'|'||world_id||'|'||actor||'|'||requester||'|'||revision||'|'||coalesce(record->>'status','')||'|'||coalesce(record->'agreement'->>'kind','')||'|'||coalesce(record->'agreement'->>'resourceId','')||'|'||coalesce(record->'agreement'->>'quantity','')||'|'||coalesce(record->'resume'->>'state','')||'|'||coalesce(record->'resume'->>'of','')||'|'||coalesce(record->'resume'->>'continuedAs','')||'|'||coalesce(record->'resume'->>'count','')||'|'||coalesce((record->'agreement'->'agreedTargets')::text,'')||'|'||coalesce((record->'agreement'->'campZone')::text,'') from stobe_activity_record order by id" > "$EV/$1" 2>&1
}
rw_out_dump() {  # agreement_id|revision|acknowledged|world_id (grants and revisions sent to the native side)
  lt_sql "select agreement_id||'|'||revision||'|'||acknowledged||'|'||world_id from stobe_activity_outbox order by sequence" > "$EV/$1" 2>&1
}
rw_has_status() {  # rw_has_status <file> <status>
  awk -F'|' -v s="$2" '$6==s{f=1} END{exit !f}' "$EV/$1" 2>/dev/null
}
rw_spawn() {  # fresh spawn next to the NPC right before the say (goats flee ~1500 u/min; the NPC only sees fresh spawns). RW_SPAWN_CMD replaces the default.
  local n; n=$(rl_q "$RL_NPC_FULL")
  if [ -n "${RW_SPAWN_CMD:-}" ]; then printf '%s\n' "$RW_SPAWN_CMD" | lt_h >> "$EV/spawn.txt" 2>&1; return 0; fi
  case "${RW_KIND:-Hunt}" in
    ClearGroup) lt_h <<EOT >> "$EV/spawn.txt" 2>&1
stobe-auto spawn "Bandit Raiders (weakened) 1" "Dust Bandits" near Shay dist 30 count 5 </dev/null | head -1 | cut -c1-120
stobe-auto spawn "Bandit Raiders (weakened) 1" "Dust Bandits" near Shay dist 170 count 1 </dev/null | head -1 | cut -c1-120
EOT
    ;;
    *) lt_h <<EOT >> "$EV/spawn.txt" 2>&1
stobe-auto spawn "wild goats" "Herbivore" near $n dist 7 count 3 </dev/null | head -1 | cut -c1-120
EOT
    ;;
  esac
  rw_sleep 2
}
rw_save_load() {  # rw_save_load <tag> [near|far]: record load_rowid, save, load, wait for the world, re-place the NPC. rc 3 when the world never returns
  local sv="${RW_SAVE_NAME:-kah-imm26-rw-$1-$LT_LANE}"
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/load_rowid.txt"
  rw_sleep 4
  printf 'stobe-auto save %s </dev/null | head -1\n' "$sv" | lt_h >> "$EV/save.txt" 2>&1
  rw_sleep 6
  rd19_load "$sv" || return $?
  rd19_place "${2:-near}"
}
rw_dist() { rl_resolve "${ROW_NPC:-Cind}" >/dev/null 2>&1; echo "${RL_DIST:-?}"; }
rw_chase() {  # rw_chase <tag>: Shay teleported RW_AWAY (80) u from the NPC and held; speed 3 for RW_CHASE_S (30) s; chase_<tag>.txt = "dist_before|dist_after"
  local tag="$1" pos x n d0 d1; n=$(rl_q "$RL_NPC_FULL")
  pos=$(echo 'stobe-auto where Shay </dev/null | head -1' | lt_h 2>&1 | sed -nE 's/.*pos=(-?[0-9.]+),(-?[0-9.]+),(-?[0-9.]+).*/\1 \2 \3/p' | head -1)
  [ -n "$pos" ] || { RL_REASON="cannot read Shay's position (stobe-auto where Shay)"; return 3; }
  set -- $pos; x=$(awk -v v="$1" -v d="${RW_AWAY:-80}" 'BEGIN{printf "%.0f", v+d}')
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto teleport Shay $x $2 $3 </dev/null | head -1 | cut -c1-100
stobe-auto order Shay HOLD_POSITION keep </dev/null | head -1 | cut -c1-80
EOT
  rw_sleep 2; d0=$(rw_dist)
  lt_h <<EOT >> "$EV/chase.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
sleep ${RW_CHASE_S:-30}
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
  d1=$(rw_dist); echo "$d0|$d1" > "$EV/chase_$tag.txt"
  return 0
}

# ------------------------------------------------------------------ 26-d / 26-dx / 26-f: an ACCEPTED activity job across a save+load
rw_job_resume() {  # rw_job_resume run|nc
  local mode="$1" offer accept rsay n0 n1
  rw_prep || return $?
  echo "${RW_KIND:-Hunt}" > "$EV/kind.txt"; echo "$mode" > "$EV/mode.txt"
  offer="${RW_OFFER:-$RW_OFFER_DEF}"; accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}"; rsay="${RW_RESUME_SAY:-Are we still on that job?}"
  [ "${RW_KIND:-Hunt}" = ClearGroup ] && offer="${RW_OFFER:-Hunt the 5 bandits.}"
  n0=$(rw_logn); rw_spawn
  rl_say 1 "$offer" || return $?
  rw_act_dump act_s1.txt
  rw_has_status act_s1.txt proposed || { rw_log act_log_pre.txt "${n0:-0}"; return 0; }          # checker: SETUP-FAIL (no offer)
  rl_say 2 "$accept" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  if [ "$mode" = nc ]; then rl_say 2c "Cancel that." || return $?; rw_sleep 4; fi
  rw_act_dump act_pre.txt; rw_out_dump out_pre.txt; rw_log act_log_pre.txt "${n0:-0}"
  if [ "$mode" = run ]; then rw_has_status act_pre.txt accepted || return 0; fi                  # checker: SETUP-FAIL (accept did not land)
  tr_state state_pre.txt "$RL_NPC_FULL"
  rw_save_load job || return $?
  n1=$(rw_logn); rw_spawn
  rl_say 3 "$rsay" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post.txt; rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  tr_state state_post.txt "$RL_NPC_FULL"
  if [ "$mode" = run ] && [ -n "${RW_COMPLETE:-}" ]; then
    lt_h <<EOT >> "$EV/complete.txt" 2>&1
stobe-auto speed 3 </dev/null >/dev/null
sleep ${RW_HUNT_WAIT:-180}
stobe-auto speed 0.5 </dev/null >/dev/null
EOT
    rw_act_dump act_final.txt; rw_out_dump out_final.txt
  fi
  return 0
}
rd_26d() { RW_KIND=Hunt rw_job_resume run; }
rd_26dx() { RW_KIND=Hunt rw_job_resume nc; }
rd_26f() { RW_KIND=ClearGroup rw_job_resume run; }   # camp variant: RW_OFFER="Clear the bandit camp." RW_SPAWN_CMD=<camp fixture>; same checks + campZone equality

# ------------------------------------------------------------------ 26-e: a PROPOSED Hunt across a save+load (re-bound in place, NPC must propose again)
rd_26e() {
  local offer n0 n1
  rw_prep || return $?
  echo Hunt > "$EV/kind.txt"; echo offer > "$EV/mode.txt"
  offer="${RW_OFFER:-$RW_OFFER_DEF}"
  n0=$(rw_logn); rw_spawn
  rl_say 1 "$offer" || return $?
  rw_act_dump act_pre.txt; rw_out_dump out_pre.txt
  rw_has_status act_pre.txt proposed || return 0                                                  # checker: SETUP-FAIL (no offer)
  rw_save_load offer || return $?
  n1=$(rw_logn); rw_spawn
  rl_say 2 "$offer" || return $?                                                                 # resume turn + the NPC proposes again
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s2.txt
  rl_say 3 "${RW_ACCEPT:-$RW_ACCEPT_DEF}" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s3.txt; rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  return 0
}

# ------------------------------------------------------------------ 24-c: area-goal trip (region plan -> native_local destination + regional_goal) across a reload
rd_24c() {
  tr_prep || return $?; ROW_NATIVE=1
  rl_say 1 "Let's consider Vain as a general area, not an exact spot." || return $?
  rl_say 2 "Let's go toward Vain." || return $?
  if tr_has s2 PROPOSED && ! tr_has s2 ACCEPTED; then rl_say 3 "Yes, let's go." || return $?; fi
  if ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" "$EV/s3/reply.txt" 2>/dev/null && { tr_has s2 ACCEPTED || tr_has s3 ACCEPTED; }; then
    rl_say 3b "Lead the way." || return $?
  fi
  rw_sleep 6
  lt_sql "select rowid||'|'||type||'|'||data from eventlog where type='region_plan' order by rowid" > "$EV/region_pre.txt" 2>&1
  rd19_dump agr_pre.txt
  grep -q '"status":"ACCEPTED"' "$EV/agr_pre.txt" || return 0                                     # checker: SETUP-FAIL (no accepted area trip)
  rw_save_load area || return $?
  rl_say 4 "Where were we going?" || return $?
  rw_sleep "${ROW_RESUME_WAIT:-8}"; rd19_state post_s4.txt
  rl_say 5 "I'm right behind you." || return $?
  rw_sleep "${ROW_RESUME_WAIT:-8}"; rd19_state post_s5.txt
  rd19_dump agr_all.txt
}

# ------------------------------------------------------------------ 23-e: legacy FOLLOW ("Follow me.") across a reload
rd_23e() {
  local l n1
  rw_prep || return $?
  rl_say 1 "Follow me." || return $?
  l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s1/meta.txt" | head -1); l=${l:-0}
  echo "$RL_NPC_ID" > "$EV/follow_npc.txt"
  rw_log follow_log_pre.txt "$l" 'FOLLOW'
  grep -q 'FOLLOW target resolved' "$EV/follow_log_pre.txt" || return 0                           # checker: SETUP-FAIL (follow never started)
  rw_chase pre || return $?
  rw_save_load follow near || return $?
  n1=$(rw_logn)
  rw_chase post || return $?
  rw_log follow_log_post.txt "${n1:-0}" 'FOLLOW'
  tr_state state_post.txt "$RL_NPC_FULL"
}

# ------------------------------------------------------------------ 27-a: BODYGUARD order across a reload
rd_27a() {
  local nq; rw_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT > "$EV/bg_set.txt" 2>&1
stobe-auto contract-bodyguard $nq Shay ${RW_BG_ARGS:-hours 24 own} </dev/null 2>&1 | head -3 | cut -c1-300
EOT
  rw_sleep 3
  lt_h <<EOT > "$EV/bg_pre.txt" 2>&1
stobe-auto contract-bodyguard status </dev/null 2>&1 | head -6 | cut -c1-300
EOT
  tr_state state_pre.txt "$RL_NPC_FULL"
  grep -qiE 'BODYGUARD' "$EV/state_pre.txt" "$EV/bg_pre.txt" 2>/dev/null || return 0               # checker: SETUP-FAIL (no order)
  rw_chase pre || return $?
  rw_save_load bodyguard near || return $?
  lt_h <<EOT > "$EV/bg_post.txt" 2>&1
stobe-auto contract-bodyguard status </dev/null 2>&1 | head -6 | cut -c1-300
EOT
  tr_state state_post.txt "$RL_NPC_FULL"
  rw_chase post || return $?
  tr_state state_after_chase.txt "$RL_NPC_FULL"
}

# ------------------------------------------------------------------ 08-e: an open follow-up topic across a reload, then claimed ONCE by a natural bored tick
rw_fu_dump() { lt_sql "select rowid||'|'||type||'|'||data from eventlog where type='social_followup' order by rowid" > "$EV/$1" 2>&1; }
rw_claim_dump() {
  local m; m=$(tr -dc 0-9 < "$EV/load_rowid.txt" 2>/dev/null); m=${m:-0}
  lt_sql "select rowid||'|'||type||'|'||left(data,300) from eventlog where type='situated_remark_claim' and data like '%followup:%' and rowid>$m order by rowid" > "$EV/$1" 2>&1
}
rd_08e() {
  local k
  rw_prep || return $?
  lt_sql "select coalesce((select value from general_settings where id='BORED_EVENT_CHANCE'),'unset')" > "$EV/bored_chance.txt" 2>&1
  rl_say 1 "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  rw_fu_dump fu_pre.txt
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                          # checker: SETUP-FAIL (no topic)
  rw_save_load followup near || return $?
  rw_fu_dump fu_post.txt
  for k in $(seq 1 "${RW_TICK_CHUNKS:-4}"); do
    ADV_SECONDS="${RW_ADV:-120}" rl_advance_gametime || return $?
    lt_h <<EOT >> "$EV/heal.txt" 2>&1
stobe-auto health Shay 100 </dev/null | head -1
stobe-auto health $(rl_q "$RL_NPC_FULL") 100 </dev/null | head -1
EOT
    rw_claim_dump claim.txt
    [ -s "$EV/claim.txt" ] && break
  done
  rw_fu_dump fu_final.txt; rw_claim_dump claim.txt
  echo "$k" > "$EV/chunks.txt"
}

# ------------------------------------------------------------------ 20-d: pending plan change (offered, not confirmed) across a reload; a bare "yes" confirms it
rd_20d() {
  tr_prep || return $?
  TR_ALT="${RW_ALT:-${TRIP_ALT:-the Stumble Inn}}"; echo "$TR_ALT" > "$EV/alt.txt"
  tr_trip_setup || return $?
  rl_say 3 "Actually, go to $TR_ALT instead." || return $?
  lt_sql "select rowid||'|'||type||'|'||left(data,700) from eventlog where type='travel_alternatives' order by rowid desc limit 4" > "$EV/alt_pre.txt" 2>&1
  rd19_dump agr_pre.txt
  grep -q 'pending_change' "$EV/alt_pre.txt" || return 0                                          # checker: SETUP-FAIL (change never offered)
  rw_save_load plan || return $?
  lt_sql "select rowid||'|'||type||'|'||left(data,700) from eventlog where type='travel_alternatives' order by rowid desc limit 4" > "$EV/alt_post.txt" 2>&1
  if [ -n "${RW_20D_RESUME_FIRST:-}" ]; then rl_say 4a "Where were we going?" || return $?; rw_sleep 6; fi
  rl_say 4 "Yes." || return $?
  rw_sleep 6
  lt_sql "select rowid||'|'||type||'|'||left(data,700) from eventlog where type='travel_alternatives' order by rowid desc limit 4" > "$EV/alt_after_yes.txt" 2>&1
  tr_agr agr_final.txt 8; rd19_dump agr_all.txt
}
