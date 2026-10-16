#!/usr/bin/env bash
# unblockdefs_a.sh: one-call rows 08-e 08-d 11-b for the 4080-i4 operator (imm26-u-rowsA). Sourced by unblockrun_a.sh AFTER go-row.sh (rowlib, rowdefs, tripdefs helpers)
# and reloaddefs_a.sh (rw_* helpers; sourced here when missing). rowdefs.sh / hxdefs.sh / tripdefs.sh / hunt26a-scene.sh are NOT edited: this file REDEFINES rd_08e / rd_08d
# (only inside the unblockrun_a.sh shell) and defines rd_11b. The verdict is unblockcheck_a.py (unblockpy_a.sh redirects rowcheck.py for these three rows).
#   Shared helpers:
#     i4_bored <tag> [push=1]   ONE targeted autochat bored request (the speaker lottery is gone): stobe_ctxpush (fresh native_ai < 120 s; push=0 = stale/no snapshot like a
#                               natural tick), then GET stream.php?DATA=<base64 bored event, FIRST parameter>&profile=<NPC>&optional=1&people=["<NPC>","Shay"]&mode=autochat on the
#                               lane's private backend (recipe: agents/out/imm26-setupfail-scope2b item (i)). Evidence bored_<tag>.txt (response + HTTP=), bored_<tag>_log.txt
#                               (server log lines since the request: "Targeted optional request ...", attention/claim lines), bored_<tag>.res = sent|nothing_claimable|http_err,
#                               bored_ticks.txt (count of requests that reached the server), stream.txt (all requests, read by c_08d). Sets U_BORED_RES.
#     tr_walk_stage [back=350] [speed=2] [tries=30]   REAL short walk for trips that end native_order_ended_before_goal after a teleported arrival: the NPC is staged `back` units
#                               short of the gate (teleport <npc> <gate> dist <back>), Shay is teleported onto her every 1.5 s (separation stays < 35), speed 1-3, no harness order on
#                               the NPC; polled up to `tries` x ~8 s for a COMPLETED travel_agreement. Evidence stage.txt gate.txt walk.txt walk_done.txt (completed=0|1).
#                               Env: TRIP_WALK_BACK TRIP_WALK_SPEED TRIP_WALK_TRIES. Also usable by 13-c / 23-a style rows.
#   Rows:
#     08-e  open topic (quiet scene, NPC sheathed) -> save+load -> re-quiet + sheathe + ONE chat line -> up to U_BORED_TRIES (3) targeted ticks, 60 s game gap + heal -> claim count
#     08-d  plain plan sentence topic -> trip proposed+accepted -> REAL walk (tr_walk_stage) to COMPLETED -> arrival line -> one targeted tick -> topic must be closed outcome_completed,
#           no situated_remark_claim, no ask.  U08D_NEG=1 = negative control: no walk, trip stays accepted, tick -> topic must stay open
#     11-b  topic -> Cind (protected) vs ONE spawned enemy (hostile faction, scene emptied by tr_quiet) -> in_combat proven -> tick WITH snapshot + tick WITHOUT snapshot -> no claim,
#           ask_count unchanged -> enemy removed, combat over, 60 s game gap -> tick WITH snapshot -> exactly one claim
# Env: U_BORED_TRIES(3) U_BORED_GAP(60 s at speed 10) U11B_FACTION("Holy Nation Outlaws") U11B_DIST(20) U11B_FIGHT_S(10) U11B_CALM_S(15) RW_FU_SAY RW_08E_POST_SAY TRIP_08D_*.
U_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F rw_prep >/dev/null || . "$U_HERE/reloaddefs_a.sh"
U_FAR="-53200 957 4893"

# ------------------------------------------------------------------ shared helper 1: targeted autochat bored tick
i4_bored() {  # i4_bored <tag> [push=1]
  local tag="$1" push="${2:-1}" nm s0 rc res f="$EV/bored_$1.txt"
  nm="${RL_NPC_FULL%% \[*}"; [ -n "$nm" ] || nm="${ROW_NPC%% \[*}"
  s0=$(printf 'wc -l < %s # u:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); s0=${s0:-0}
  if [ "$push" = 1 ]; then rl_push; rc=$?; [ $rc = 0 ] || return $rc; else echo "no ctxpush (stale/no native snapshot)" >> "$EV/ctxpush.txt"; fi
  lt_w <<EOT > "$f" 2>&1
# u:stream
G=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select coalesce(max(gamets),0) from eventlog")
D=\$(printf 'bored|%s|%s|%s: [BORED_EVENT_TRIGGER] (talking to: Shay)' "\$(date +%s)" "\$G" "$nm" | base64 -w0 | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe=""))')
P=\$(python3 -c 'import sys,urllib.parse,json;print(urllib.parse.quote(json.dumps([sys.argv[1],"Shay"]),safe=""))' "$nm")
T=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select (value::json)->>'token' from stobe_meta.settings where key='PLAYTHROUGH_SESSION'")   # op11: pas_guard answers 409 to a request without the session token once the DLL registered a client_id
curl -s -m 120 -H "X-Stobe-Playthrough: \$T" -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:$LT_PORT/stream.php?DATA=\$D&profile=$(printf %s "$nm" | sed 's/ /%20/g')&optional=1&people=\$P&mode=autochat" | head -c 800
EOT
  rw_sleep 3
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "Targeted optional request|nothing claimable|ocial attention|situated_remark|ollowup|BORED" | cut -c1-300 | tail -8 # u:tlog\n' "$(( s0 + 1 ))" "$LT_SRVLOG" | lt_w > "$EV/bored_${tag}_log.txt" 2>&1
  if ! grep -q 'HTTP=200' "$f"; then res=http_err
  elif grep -qi 'nothing claimable' "$EV/bored_${tag}_log.txt"; then res=nothing_claimable
  else res=sent; fi
  echo "$res" > "$EV/bored_$tag.res"; U_BORED_RES="$res"
  [ "$res" = http_err ] || echo "$tag" >> "$EV/bored_ticks.txt"
  { echo "## $tag push=$push res=$res"; cat "$f"; } >> "$EV/stream.txt"
  return 0
}

# ------------------------------------------------------------------ shared helper 2: real short walk to the gate
tr_walk_stage() {  # tr_walk_stage [back=350] [speed=2] [tries=30]
  local back="${1:-${TRIP_WALK_BACK:-350}}" spd="${2:-${TRIP_WALK_SPEED:-2}}" tries="${3:-${TRIP_WALK_TRIES:-30}}" g n k c=0 fin=0
  n=$(rl_q "$RL_NPC_FULL"); g=$(tr_gate)
  [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"; echo "gate=$g back=$back speed=$spd tries=$tries" > "$EV/stage.txt"
  lt_h <<EOT >> "$EV/stage.txt" 2>&1
stobe-auto teleport $n $g dist $back </dev/null | head -1 | cut -c1-120
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
stobe-auto speed $spd </dev/null | head -1
EOT
  for k in $(seq 1 "$tries"); do
    lt_h <<EOT >> "$EV/walk.txt" 2>&1
for i in 1 2 3 4 5; do stobe-auto teleport Shay $n </dev/null >/dev/null; sleep 1.5; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
    c=$(lt_sql "select count(*) from eventlog where type='travel_agreement' and data like '%\"status\":\"COMPLETED\"%'" | head -1 | tr -dc 0-9)
    [ "${c:-0}" -gt 0 ] && { fin=1; break; }
  done
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto speed 0.5 </dev/null | head -1
EOT
  echo "completed=$fin loops=$k speed=$spd back=$back" > "$EV/walk_done.txt"
  return 0
}

# ------------------------------------------------------------------ small shared bits
u_sheathe() { printf 'stobe-auto stobe_drawn sheathe %s </dev/null | head -1\n' "$(rl_q "$1")" | lt_h >> "$EV/quiet.txt" 2>&1; }
u_heal() { lt_h <<EOT >> "$EV/heal.txt" 2>&1
stobe-auto health Shay 100 </dev/null | head -1
stobe-auto health $(rl_q "$RL_NPC_FULL") 100 </dev/null | head -1
EOT
}
u_state_combat() {  # u_state_combat <file>: `in_combat=true|false|unknown` (stobe_state), ERROR text when the NPC is gone
  local js ic; js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000 # u:state\n' "$(rl_q "$RL_NPC_FULL")" | lt_h 2>&1)
  ic=$(echo "$js" | grep -oE '"in_combat": ?(true|false)' | head -1 | grep -oE 'true|false')
  if echo "$js" | grep -qiE 'no character named|ERROR'; then echo "in_combat=gone $(echo "$js" | head -1 | cut -c1-120)" > "$EV/$1"
  else echo "in_combat=${ic:-unknown}" > "$EV/$1"; fi
}
u_claim_dump() {  # u_claim_dump <file> <rowid mark>: follow-up claims written after the mark
  lt_sql "select rowid||'|'||type||'|'||left(data,400) from eventlog where type='situated_remark_claim' and data like '%followup:%' and rowid>${2:-0} order by rowid" > "$EV/$1" 2>&1
}
u_topic() {  # u_topic <say-text>: open personal_plan topic via one chat line; fu_pre.txt; rc 0 always (the checker judges)
  rl_say 1 "$1" || return $?
  rw_fu_dump fu_pre.txt
}

# ------------------------------------------------------------------ 08-e: open topic survives a save+load and is claimed ONCE by a targeted autochat tick
rd_08e() {
  local k n0 nq tries="${U_BORED_TRIES:-3}"
  rw_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  lt_sql "select coalesce((select value from general_settings where id='BORED_EVENT_CHANCE'),'unset')" > "$EV/bored_chance.txt" 2>&1
  u_sheathe "$RL_NPC_FULL"
  u_topic "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                         # checker: SETUP-FAIL (no topic)
  rw_save_load followup near || return $?
  rw_fu_dump fu_post.txt
  n0=$(printf 'wc -l < %s # rw:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); echo "${n0:-0}" > "$EV/srvlog_n0.txt"
  unset TR_SCENE; tr_quiet; u_sheathe "$RL_NPC_FULL"
  rl_resolve "$ROW_NPC" >/dev/null 2>&1
  rl_say 2 "${RW_08E_POST_SAY:-Hello again, I am back.}" || return $?                             # fresh native snapshot for the NPC
  for k in $(seq 1 "$tries"); do
    i4_bored "08e$k" 1 || return $?
    rw_claim_dump claim.txt
    [ -s "$EV/claim.txt" ] && break
    ADV_SECONDS="${U_BORED_GAP:-60}" rl_advance_gametime || return $?                            # past the 60 s any-actor claim cooldown, snapshot refreshed by the next push
    u_heal
  done
  cp "$EV/bored_ticks.txt" "$EV/cind_ticks_list.txt" 2>/dev/null
  [ -s "$EV/bored_ticks.txt" ] && wc -l < "$EV/bored_ticks.txt" | tr -dc 0-9 > "$EV/cind_ticks.txt" || echo 0 > "$EV/cind_ticks.txt"
  cat "$EV"/bored_08e*_log.txt 2>/dev/null | tail -6 > "$EV/cind_ticks_log.txt"
  rw_fu_dump fu_final.txt; rw_claim_dump claim.txt
  echo "$k" > "$EV/chunks.txt"
}

# ------------------------------------------------------------------ 08-d: topic retired by a REALLY WALKED trip (no teleported arrival)
rd_08d() {
  tr_prep || return $?
  local dest="$TR_DEST" neg="${U08D_NEG:-0}" n0
  echo "neg=$neg" > "$EV/neg.txt"
  lt_sqlx "delete from eventlog where type='social_followup' and data like '%sell my furs%'" >> "$EV/clean.txt" 2>&1
  rl_say 0 "I need to sell my furs in $dest before winter." || return $?
  grep -q '"kind":"personal_plan"' "$EV/s0/ev_full.txt" 2>/dev/null || { rl_say 0b "I want to sell my furs in $dest before winter." || return $?; }
  tr_trip_setup || return $?
  if [ "$neg" = 1 ]; then echo "completed=0 (negative control: no walk)" > "$EV/walk_done.txt"
  else
    tr_walk_stage || return $?
    tr_state state_shay.txt Shay
    rl_say 3 "We're here. Thanks for guiding me." || return $?
  fi
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
  rd08d_dump fu_before.txt
  n0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); n0=${n0:-0}
  i4_bored 08d 1 || return $?
  rw_sleep 3
  rd08d_dump fu_after.txt
  printf 'tail -n +%s %s | grep -E "BORED_EVENT|ACTION_EXEC: SAY|FOLLOWUP|followup" | cut -c1-300 | head -40\n' "$(( n0 + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/bored_log.txt" 2>&1
}

# ------------------------------------------------------------------ 11-b: no follow-up claim while the NPC is in combat; exactly one after combat
rd_11b() {
  local nq o en mark
  tr_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  u_topic "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                         # checker: SETUP-FAIL (no topic)
  mark=$(lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9); echo "${mark:-0}" > "$EV/mark_rowid.txt"
  o=$(printf 'stobe-auto spawn "Hungry Bandit" %s near %s dist %s count 1 </dev/null 2>&1 | head -2\n' "$(rl_q "${U11B_FACTION:-Holy Nation Outlaws}")" "$nq" "${U11B_DIST:-20}" | lt_h 2>&1)
  echo "$o" > "$EV/spawn.txt"
  en=$(echo "$o" | sed -nE 's/^spawned [0-9]+\/[0-9]+ [^:]*: (.*) #[0-9]+\/[0-9]+.*/\1/p' | head -1)
  [ -n "${KAH_ROW_FAKE:-}" ] && ! echo "$o" | grep -qi 'error' && en="${en:-Dry [Hungry Bandit]}"
  [ -n "$en" ] || { RL_REASON="enemy spawn failed or unparseable reply: $(echo "$o" | head -1 | cut -c1-160)"; return 3; }
  echo "$en" > "$EV/enemy.txt"
  lt_h <<EOT >> "$EV/fight.txt" 2>&1
stobe-auto protect $nq on </dev/null | head -1
stobe-auto protect $(rl_q "$en") on </dev/null | head -1
stobe-auto fight $nq $(rl_q "$en") </dev/null 2>&1 | head -2
EOT
  rw_sleep "${U11B_FIGHT_S:-10}"
  u_state_combat state_combat_pre.txt
  i4_bored c1b 0 || return $?                                                                    # tick WITHOUT a snapshot first (what a natural tick looks like; no push was sent in this scene yet)
  u_claim_dump claim_c1b.txt "$mark"; rw_fu_dump fu_c1b.txt
  i4_bored c1a 1 || return $?                                                                    # then WITH a fresh snapshot (in_combat visible to the attention gate)
  u_state_combat state_combat.txt; u_claim_dump claim_c1a.txt "$mark"; rw_fu_dump fu_combat.txt
  lt_sql "select count(*) from eventlog where type='combat' and rowid>${mark:-0}" > "$EV/combat_rows.txt" 2>&1
  lt_h <<EOT >> "$EV/calm.txt" 2>&1                                                              # end the fight: enemy gone, orders cleared
stobe-auto teleport $(rl_q "$en") $U_FAR </dev/null | head -1
stobe-auto order $nq NULL_TASK </dev/null | head -1
EOT
  rw_sleep "${U11B_CALM_S:-15}"
  u_state_combat state_calm.txt
  ADV_SECONDS="${U_BORED_GAP:-60}" rl_advance_gametime || return $?
  u_heal
  i4_bored c2 1 || return $?
  u_claim_dump claim_after.txt "$mark"; rw_fu_dump fu_final.txt
}
