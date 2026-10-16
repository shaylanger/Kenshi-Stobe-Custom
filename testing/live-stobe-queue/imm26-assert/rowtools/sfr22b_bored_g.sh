#!/usr/bin/env bash
# sfr22b_bored_g.sh (imm26-4080-i3op24, 2026-10-16): i4_bored with a LIVE game-time stamp. NEW file; unblockdefs_a.sh is NOT edited. Sourced by sfrrun_v3.sh after unblockdefs_a.sh.
# Why (22-b run 5, 4080-i3): the targeted bored tick stamped its event with max(eventlog.gamets) (277047) while the native snapshot pushed right before it carries observed_gamets 277253.
#   stobeCommitmentNativeSnapshot (lib/commitment_native_bridge.php:16) rejects a snapshot with observed_gamets > gamets+1, so processor/bored.php's reconcile never ingested the
#   COMPLETED receipt (receipt stayed ACCEPTED/requested, no situated_event arrival, "nothing claimable"). The DLL's real bored events carry the live game time; here the tick uses
#   greatest(max(eventlog.gamets), the NPC's snapshot observed_gamets), i.e. what the DLL would send. Everything else is the original i4_bored (copied below with ONE changed query).
i4_bored() {  # i4_bored <tag> [push=1]
  local tag="$1" push="${2:-1}" nm s0 rc res f="$EV/bored_$1.txt" pa pb ns ps
  nm="$RL_NPC_FULL"; [ -n "$nm" ] || nm="$ROW_NPC"   # imm26-inv22b2: the DLL names the speaker "Cind [Hungry Bandit]" (profile= and people=, ChatBox.cpp:5752-5754/5833-5844). The bare "Cind" resolved
  # to a stale placeholder row (no travel_lifecycle) because getNpcData is an exact-name lookup, so bored.php:186's reconcile returned at stobeCommitmentNativeSnapshot and the COMPLETED receipt was never ingested (22-b run 3).
  pa="$nm"; pb="Shay"
  if [ "${U_BORED_SERIALS:-0}" = 1 ]; then   # u6-fix08d: the DLL sends people as "Name|serial" (ChatBox.cpp:5833-5835); a plain name resolves to serial 0 server-side (imm26_c2_followups.php:98)
    ns="${RL_NPC_ID#\#}"; ns="${ns%%/*}"
    ps=$(printf 'stobe-auto where Shay </dev/null 2>&1 | head -1\n' | lt_h 2>&1 | grep -oE '#[0-9]+/' | head -1 | tr -dc 0-9)
    if [ -n "$ns" ] && [ -n "$ps" ]; then pa="$nm|$ns"; pb="Shay|$ps"; fi
    echo "people=$pa,$pb" >> "$EV/bored_people.txt"
  fi
  s0=$(printf 'wc -l < %s # u:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); s0=${s0:-0}
  if [ "$push" = 1 ]; then rl_push; rc=$?; [ $rc = 0 ] || return $rc; else echo "no ctxpush (stale/no native snapshot)" >> "$EV/ctxpush.txt"; fi
  lt_w <<EOT > "$f" 2>&1
# u:stream
G=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select greatest(coalesce((select max(gamets) from eventlog),0), coalesce((select ((metadata::jsonb)->'travel_lifecycle'->>'observed_gamets')::bigint from core_npc_master where name='${RL_NPC_FULL}'),0))")
D=\$(printf 'bored|%s|%s|%s: [BORED_EVENT_TRIGGER] (talking to: Shay)' "\$(date +%s)" "\$G" "$nm" | base64 -w0 | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe=""))')
P=\$(python3 -c 'import sys,urllib.parse,json;print(urllib.parse.quote(json.dumps([sys.argv[1],sys.argv[2]]),safe=""))' "$pa" "$pb")
T=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select (value::json)->>'token' from stobe_meta.settings where key='PLAYTHROUGH_SESSION'")   # op11: pas_guard answers 409 to a request without the session token once the DLL registered a client_id
curl -s -m 120 -H "X-Stobe-Playthrough: \$T" -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:$LT_PORT/stream.php?DATA=\$D&profile=$(printf %s "$nm" | sed 's/ /%20/g; s/\[/%5B/g; s/\]/%5D/g')&optional=1&people=\$P&mode=autochat" | head -c 800
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
