#!/usr/bin/env bash
# unblockdefs_a.sh: one-call rows 08-e 08-d 11-b for the 4080-i4 operator (imm26-u-rowsA). Sourced by unblock-run.sh AFTER go-row.sh (rowlib, rowdefs, tripdefs helpers)
# and reloaddefs_a.sh (rw_* helpers; sourced here when missing). rowdefs.sh / hxdefs.sh / tripdefs.sh / hunt26a-scene.sh are NOT edited: this file REDEFINES rd_08e / rd_08d
# (only inside the unblock-run.sh shell) and defines rd_11b. The verdict is unblockcheck_a.py (unblock-py.sh redirects rowcheck.py for these three rows).
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
curl -s -m 120 -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:$LT_PORT/stream.php?DATA=\$D&profile=$(printf %s "$nm" | sed 's/ /%20/g')&optional=1&people=\$P&mode=autochat" | head -c 800
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
