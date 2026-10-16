#!/usr/bin/env bash
# unblockdefs_sfs.sh: 08-d v2 (imm26-sfS).  NEW file; unblockdefs_a.sh / unblockrun_a.sh / unblockcheck_a.py / rowcheck_trip.py are NOT edited.  Sourced by unblockrun_sfs.sh AFTER
# unblockdefs_a.sh: it REDEFINES i4_bored and rd_08d (only inside the unblockrun_sfs.sh shell; 08-e / 11-b keep using unblockrun_a.sh and are unaffected).
# Why (imm26-fxC findings, handoff section "08-d"): the 08-d FAIL on 4080-i4 was two TEST defects.
#   1  i4_bored sent `mode=autochat&optional=1` with NO `attn=`.  The follow-up claim (social_followups.php stobeSocialFollowupsClaim) only retires a completed-trip topic AFTER the attention
#      gate (stobeSocialAttentionOptionalSpeechAllowed, social_attention.php:41), which needs in_combat === false.  The only other source is the native snapshot (native_ai_context.php
#      stobeNativeAiSnapshot), rejected when its stamp is > 120 game s behind the request gamets, and i4_bored's gamets (max(eventlog.gamets)) lags the clock by seconds-to-minutes at
#      speed 0.5 => in_combat unknown => deny => "Targeted optional request: nothing claimable" and the topic is never retired.   The director path has
#      director_bored_unknown_attention_ok; the autochat harness tick does not.   v2: every tick carries `attn={"in_combat":false}` (processor/bored.php:171-173 puts it into
#      $optionalMeta['request_attention']; lib/imm26_c2_attention.php imm26C2ParseRequestAttention + imm26C2AttentionFacts apply it last, so it wins over a missing snapshot).
#      It is a true statement: the scene is calm (Cind walked to the gate, no fight).  Override with U_BORED_ATTN='<json>' ('' = no attn, the v1 behaviour).
#   2  the check `no_npc_ask_about_the_topic` greps SAY lines for `fur|squin` over the whole bored_log.txt, which includes tick 1 = the trip ARRIVAL remark ("I'll be around Squin a while ...").
#      v2: after tick 1 has spoken (polled up to U08D_SAYWAIT=25 s real) the stobelog line count is recorded (bored_after1_mark.txt) and bored_log_after1.txt holds the same grep of ONLY the
#      lines after it; unblockcheck_sfs.py runs the unchanged c_08d on a view whose bored_log.txt is that file.  A follow-up ASK on tick 1 would still be caught by
#      no_situated_remark_claim_for_closed_topic (the claim row followup:<topic>:<n> is written to the eventlog for every ask).  Nothing else is weakened.
# Evidence added: bored_attn.txt (attn sent per tick), bored_after1_mark.txt, bored_log_after1.txt.  Env: U_BORED_ATTN ({"in_combat":false})  U08D_SAYWAIT (25)  plus all of unblockdefs_a.sh (U08D_TRIES U08D_POST_CHAT_S U08D_TICK_REAL_S U_BORED_GAP U08D_NEG).
USFS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F i4_bored >/dev/null || . "$USFS_HERE/unblockdefs_a.sh"
declare -F sfk_gate >/dev/null || . "$USFS_HERE/tripdefs_sfk.sh"   # imm26-fix20a19e: sfK2 walk helpers (sfk_gate, uf_walk_stage, sfk_shay_guard)
[ -n "${U_BORED_ATTN+x}" ] || U_BORED_ATTN='{"in_combat":false}'

# ------------------------------------------------------------------ i4_bored v2: same request as v1 + attn=
i4_bored() {  # i4_bored <tag> [push=1]
  local tag="$1" push="${2:-1}" nm s0 rc res f="$EV/bored_$1.txt" pa pb ns ps at="${U_BORED_ATTN-}"
  nm="${RL_NPC_FULL%% \[*}"; [ -n "$nm" ] || nm="${ROW_NPC%% \[*}"
  pa="$nm"; pb="Shay"
  if [ "${U_BORED_SERIALS:-0}" = 1 ]; then   # the DLL sends people as "Name|serial" (ChatBox.cpp:5833-5835); a plain name resolves to serial 0 server-side
    ns="${RL_NPC_ID#\#}"; ns="${ns%%/*}"
    ps=$(printf 'stobe-auto where Shay </dev/null 2>&1 | head -1\n' | lt_h 2>&1 | grep -oE '#[0-9]+/' | head -1 | tr -dc 0-9)
    if [ -n "$ns" ] && [ -n "$ps" ]; then pa="$nm|$ns"; pb="Shay|$ps"; fi
    echo "people=$pa,$pb" >> "$EV/bored_people.txt"
  fi
  echo "$tag attn=${at:-<none>}" >> "$EV/bored_attn.txt"
  s0=$(printf 'wc -l < %s # u:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); s0=${s0:-0}
  if [ "$push" = 1 ]; then rl_push; rc=$?; [ $rc = 0 ] || return $rc; else echo "no ctxpush (stale/no native snapshot)" >> "$EV/ctxpush.txt"; fi
  lt_w <<EOT > "$f" 2>&1
# u:stream
G=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select coalesce(max(gamets),0) from eventlog")
D=\$(printf 'bored|%s|%s|%s: [BORED_EVENT_TRIGGER] (talking to: Shay)' "\$(date +%s)" "\$G" "$nm" | base64 -w0 | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe=""))')
P=\$(python3 -c 'import sys,urllib.parse,json;print(urllib.parse.quote(json.dumps([sys.argv[1],sys.argv[2]]),safe=""))' "$pa" "$pb")
A=\$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' '$at')
T=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select (value::json)->>'token' from stobe_meta.settings where key='PLAYTHROUGH_SESSION'")
curl -s -m 120 -H "X-Stobe-Playthrough: \$T" -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:$LT_PORT/stream.php?DATA=\$D&profile=$(printf %s "$nm" | sed 's/ /%20/g')&optional=1&people=\$P&mode=autochat&attn=\$A" | head -c 800
EOT
  rw_sleep 3
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "Targeted optional request|nothing claimable|ocial attention|situated_remark|ollowup|BORED" | cut -c1-300 | tail -8 # u:tlog\n' "$(( s0 + 1 ))" "$LT_SRVLOG" | lt_w > "$EV/bored_${tag}_log.txt" 2>&1
  if ! grep -q 'HTTP=200' "$f"; then res=http_err
  elif grep -qi 'nothing claimable' "$EV/bored_${tag}_log.txt"; then res=nothing_claimable
  else res=sent; fi
  echo "$res" > "$EV/bored_$tag.res"; U_BORED_RES="$res"
  [ "$res" = http_err ] || echo "$tag" >> "$EV/bored_ticks.txt"
  { echo "## $tag push=$push res=$res attn=${at:-<none>}"; cat "$f"; } >> "$EV/stream.txt"
  return 0
}

# ------------------------------------------------------------------ rd_08d v2
sfs_stobelog_lines() { echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9; }
sfs_wait_say() {  # sfs_wait_say <n0> : poll (real s, U08D_SAYWAIT) until the Stobe log shows an NPC SAY after line n0; no SAY (nothing claimable) just times out
  local n0="$1" t="${U08D_SAYWAIT:-25}" k
  [ -n "${KAH_ROW_FAKE:-}" ] && return 0
  for k in $(seq 1 $(( (t + 2) / 3 ))); do
    printf 'tail -n +%s %s | grep -q "ACTION_EXEC: SAY" && echo yes\n' "$(( n0 + 1 ))" "$LT_STOBELOG" | lt_h | grep -q yes && return 0
    sleep 3
  done
  return 0
}
sfs_walk_v2() {   # the sfK2 23-a body (tripdefs_sfk.sh rd_23a lines 55-75): gate = newest agreement destination_point, staged SFK_23A_BACK u short, speed 1, no harness order; walk_done.txt = completed=<0|1>
  local n g
  n=$(rl_q "$RL_NPC_FULL"); g=$(sfk_gate)
  [ -n "$g" ] || { RL_REASON="no gate coordinates for '$TR_DEST' (set TRIP_GATE='x y z')"; return 3; }
  echo "$g" > "$EV/gate.txt"
  UF_N0=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1 | tr -dc 0-9); UF_N0=${UF_N0:-0}
  uf_walk_stage "$n" "$g" "${SFK_23A_BACK:-400}" 0 150 "${SFK_23A_SPEED:-1}" "${SFK_23A_TRIES:-30}"
  uf_native_dump native_travel.txt
  printf 'end=%s gate=%s last_progress=%s
' "$UB_WALK_END" "$g" "$(tail -1 "$EV/walk_progress.txt" 2>/dev/null)" > "$EV/arrival.txt"
  if [ "$UB_WALK_END" = TIMEOUT ]; then
    echo "completed=0 end=TIMEOUT" > "$EV/walk_done.txt"
    RL_REASON="no native arrival within ${SFK_23A_TRIES:-30} walk cycles (walk_progress.txt: $(tail -1 "$EV/walk_progress.txt" 2>/dev/null | cut -c1-120)); needs: recipe (raise SFK_23A_TRIES / lower SFK_23A_BACK) or native (no NATIVE_TRAVEL line = old DLL)"
    return 3
  fi
  echo "completed=1 end=$UB_WALK_END" > "$EV/walk_done.txt"
  lt_h <<EOT >> "$EV/walk.txt" 2>&1
stobe-auto teleport Shay $n </dev/null | head -1 | cut -c1-120
EOT
  sfk_shay_guard || return 3
  return 0
}
rd_08d() {
  tr_prep || return $?
  local dest="$TR_DEST" neg="${U08D_NEG:-0}" n0 m1=""
  echo "neg=$neg" > "$EV/neg.txt"
  lt_sqlx "delete from eventlog where type='social_followup' and data like '%sell my furs%'" >> "$EV/clean.txt" 2>&1
  rl_say 0 "I need to sell my furs in $dest before winter." || return $?
  grep -q '"kind":"personal_plan"' "$EV/s0/ev_full.txt" 2>/dev/null || { rl_say 0b "I want to sell my furs in $dest before winter." || return $?; }
  tr_trip_setup || return $?
  if [ "$neg" = 1 ]; then echo "completed=0 (negative control: no walk)" > "$EV/walk_done.txt"
  else
    sfs_walk_v2 || return $?   # sfK2 23-a v2 walk (stage at the agreement's own destination_point), imm26-fix20a19e
    tr_state state_shay.txt Shay
    rl_say 3 "We're here. Thanks for guiding me." || return $?
  fi
  tr_state state_after.txt "$RL_NPC_FULL"; tr_agr agr_final.txt 8
  rd08d_dump fu_before.txt
  n0=$(sfs_stobelog_lines); n0=${n0:-0}
  local tries="${U08D_TRIES:-3}" k
  [ "$neg" = 1 ] && tries=1
  U_BORED_SERIALS=1
  rw_sleep "${U08D_POST_CHAT_S:-31}"   # the claim gate refuses for 30 s real after any manual chat (social_followups.php:215)
  for k in $(seq 1 "$tries"); do
    i4_bored 08d 1 || { U_BORED_SERIALS=0; return $?; }
    rw_sleep 3
    if [ "$k" = 1 ]; then   # tick 1 = the arrival remark: mark where the log stands once it has spoken, the ask check looks only after this line
      [ "$U_BORED_RES" = sent ] && sfs_wait_say "$n0"
      m1=$(sfs_stobelog_lines); m1=${m1:-$n0}; echo "m1=$m1 n0=$n0 tick1_res=$U_BORED_RES" > "$EV/bored_after1_mark.txt"
    fi
    rd08d_dump fu_after.txt
    echo "tick $k res=$U_BORED_RES" >> "$EV/bored_08d_tries.txt"
    grep -q 'outcome_completed' "$EV/fu_after.txt" 2>/dev/null && break
    [ "$k" = "$tries" ] && break
    [ "$neg" = 1 ] || rw_sleep "${U08D_TICK_REAL_S:-185}"   # tick 1 answers with the arrival remark; the follow-up claim gate then refuses the same actor for 180 s REAL
    ADV_SECONDS="${U_BORED_GAP:-60}" rl_advance_gametime || { U_BORED_SERIALS=0; return $?; }
    u_heal
  done
  U_BORED_SERIALS=0
  rd08d_dump fu_after.txt
  printf 'tail -n +%s %s | grep -E "BORED_EVENT|ACTION_EXEC: SAY|FOLLOWUP|followup" | cut -c1-300 | head -40\n' "$(( n0 + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/bored_log.txt" 2>&1
  printf 'tail -n +%s %s | grep -E "BORED_EVENT|ACTION_EXEC: SAY|FOLLOWUP|followup" | cut -c1-300 | head -40 # after tick 1\n' "$(( ${m1:-$n0} + 1 ))" "$LT_STOBELOG" | lt_h > "$EV/bored_log_after1.txt" 2>&1
}
