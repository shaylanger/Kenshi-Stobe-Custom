#!/usr/bin/env bash
# rowlib.sh: row-runner helpers (marks, say, evidence bundles) on top of lane.sh. Used by go-row.sh and the rows/*.sh definitions.
# Evidence dir (EV) = <KenshiTestRuns>/<lane-dir>/rows/<ROW>/ ; per say step s<N>/{events,ev_full,prompt,reply,server,effects,meta}.txt (a
# Bundle for imm26_lib.py), plus result-level files: social_effect.txt (select * ... FULL), haff-*.txt, inv_*.txt, distance.txt, deals.txt.
RL_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RL_HERE/lane.sh"
RL_HAFF="$RL_HERE/haff.php"
RL_NOISE="'combat','carry','healing','infonpc','major_damage','knockout','recovered','limb_loss','combat_start','combat_end','item_pickup'"
RL_FULLTYPES="'travel_agreement','social_followup','region_plan','social_preferences','social_rumor','situated_remark_claim','social_contract','social_commitment'"
rl_q() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }   # shell single-quote
rl_begin() {  # rl_begin <ROW>
  RL_ROW="$1"; EV="$LT_OUT/$1"; RL_REASON=""; RL_NPC_ID=""
  [ -d "$EV" ] && { rm -rf "$EV.prev"; mv "$EV" "$EV.prev"; }
  mkdir -p "$EV"; date > "$EV/started.txt"; echo "$LT_LANE" > "$EV/lane.txt"
}
rl_resolve() {  # sets RL_NPC_FULL ("Cind [Hungry Bandit]"), RL_NPC_ID ("#serial/idx"), RL_DIST
  local npc="${1:-${ROW_NPC:-Cind}}" w
  w=$(printf 'stobe-auto where %s </dev/null 2>&1 | head -1\n' "$(rl_q "$npc")" | lt_h 2>&1)
  RL_NPC_FULL=$(echo "$w" | sed -nE 's/^(.*) #[0-9]+\/[0-9]+ \[.*/\1/p' | head -1); RL_NPC_FULL=${RL_NPC_FULL:-$npc}
  RL_NPC_ID=$(echo "$w" | grep -oE '#[0-9]+/[0-9]+' | head -1)
  RL_DIST=$(echo "$w" | sed -nE 's/.* dist=([0-9.]+).*/\1/p' | head -1)
  [ -n "${RL_NPC_ID:-}" ]
}
rl_mark() {  # prints "<eventlog max rowid> <prompt bytes> <stobe.log lines> <server log lines> <social_effect count>"
  local e b l s c
  e=$(lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1)
  b=$(echo "stat -c %s $LT_PROMPTLOG 2>/dev/null || echo 0" | lt_w | tail -1)
  l=$(echo "wc -l < $LT_STOBELOG" | lt_h | tail -1)
  s=$(echo "wc -l < $LT_SRVLOG 2>/dev/null || echo 0" | lt_w | tail -1)
  c=$(lt_sql "select count(*) from social_effect" | head -1)
  echo "${e:-0} ${b:-0} ${l:-0} ${s:-0} ${c:-0}" | tr -d '\r'
}
rl_bundle() {  # rl_bundle <dir> "<mark>"
  local d="$1"; set -- $2; local e=${1:-0} b=${2:-0} l=${3:-0} s=${4:-0} c=${5:-0}; mkdir -p "$d"
  lt_sql "select rowid,type,left(data,500),coalesce(delivery_state,'') from eventlog where rowid>$e and type not in ($RL_NOISE) order by rowid" > "$d/events.txt"
  lt_sql "select rowid,type,data from eventlog where rowid>$e and type in ($RL_FULLTYPES) order by rowid" > "$d/ev_full.txt"
  echo "tail -c +$((b+1)) $LT_PROMPTLOG 2>/dev/null | head -c 400000" | lt_w > "$d/prompt.txt"
  echo "tail -n +$((l+1)) $LT_STOBELOG | grep -E 'ACTION_EXEC|resolved_speaker|ERROR|REJECT|rejected|ACTIVITY_|TRAVEL|CHAT_SEND_STAGE|Empty stream' | cut -c1-400 | head -80" | lt_h > "$d/reply.txt"
  echo "tail -n +$((s+1)) $LT_SRVLOG 2>/dev/null | grep -a -i -E 'gate|reject|SOCIAL_|TRAVEL|NEG_TEST|threshold|relationship_trading|ERROR' | cut -c1-300 | head -80" | lt_w > "$d/server.txt"
  local cnow; cnow=$(lt_sql 'select count(*) from social_effect' | head -1 | tr -dc 0-9)
  { echo "count_delta=$(( ${cnow:-0} - c ))"; lt_sql "select * from social_effect order by 1 desc limit 12"; } > "$d/effects.txt"
  { echo "mark=$e $b $l $s $c"; date; } > "$d/meta.txt"
}
rl_prep_player() {  # Shay must be conscious and selected (else replies come from another character)
  [ -n "${KAH_ROW_FAKE:-}" ] && { echo "stobe-auto select Shay" | lt_h >/dev/null; return 0; }
  local o; o=$(lt_h <<'EOT'
if stobe-auto stobe_state Shay </dev/null | grep -q '"unconscious":true'; then stobe-auto wake Shay </dev/null | head -1; sleep 2; fi
stobe-auto select Shay </dev/null >/dev/null; stobe-auto stobe_state Shay </dev/null | grep -o '"unconscious":[a-z]*' | head -1
EOT
)
  echo "$o" | grep -q 'unconscious":false'
}
rl_push() {  # native-context push right before a say (native_ai is valid ~120 game s); rc 4 = GATED (old DLL)
  local o; o=$(printf 'stobe-auto stobe_ctxpush %s </dev/null 2>&1 | head -2\n' "$(rl_q "${RL_NPC_FULL:-Cind}")" | lt_h 2>&1)
  echo "$o" >> "$EV/ctxpush.txt"
  if echo "$o" | grep -qiE 'unknown command|unknown handler|not supported|no such command|unsupported'; then
    RL_REASON="native-context blocker E607: stobe_ctxpush unsupported on $LT_LANE (installed DLL is not the NC build 4D18E32C; see KNOWN_BLOCKERS.md)"; return 4; fi
  return 0
}
rl_say() {  # rl_say <N> "text" [wait_s]  -> s<N>/ bundle. rc 3 = SETUP-FAIL, rc 4 = GATED (reason in RL_REASON)
  local n="$1" text="$2" wait_s="${3:-${ROW_WAIT:-150}}" d="$EV/s$1" mk tq tgt rc
  [ -n "${RL_NPC_ID:-}" ] || rl_resolve || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} (stobe-auto where)"; return 3; }
  tgt="$RL_NPC_ID"; mkdir -p "$d"
  if [ -n "${ROW_NATIVE:-}" ]; then rl_push; rc=$?; [ $rc = 0 ] || return $rc; fi
  rl_prep_player || { RL_REASON="Shay not conscious/selected (replies would come from another character)"; return 3; }
  mk=$(rl_mark); tq=$(rl_q "$text")
  lt_h <<EOT > "$d/say.txt" 2>&1
L=$(rl_q "$LT_STOBELOG"); n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$tgt" $tq </dev/null 2>&1 | head -2
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 2; tail -n +\$((n0+1)) "\$L" | grep -qE "ACTION_EXEC: SAY \[[^]]*\](.*)\(NPC\)" && { sleep 3; break; }; done
EOT
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_SETTLE:-3}"
  rl_bundle "$d" "$mk"; echo "say: $text" >> "$d/meta.txt"; echo "$text" > "$d/utterance.txt"
  [ -n "${KAH_ROW_FAKE:-}" ] && return 0
  grep -q 'resolved_speaker=Shay' "$d/reply.txt" || { RL_REASON="resolved_speaker is not Shay in s$n (see $d/reply.txt)"; return 3; }
  grep -qE 'ACTION_EXEC: SAY \[' "$d/reply.txt" || { RL_REASON="no NPC reply within ${wait_s}s in s$n (see $d/reply.txt)"; return 3; }
  return 0
}
rl_wsl_path() { echo "$1" | sed -E 's#^/([a-z])/#/mnt/\1/#'; }
rl_aff() {  # rl_aff <npc> <counterpart> <value> <type> [tag]   (H-AFF on the lane DB; appends before/after JSON to haff-<tag>.txt)
  local tag="${5:-aff}"
  printf 'cd %s/site; KAH_LANE_ROOT=%s KAH_LANE_DB=%s php %s %s %s %s %s 2>&1 | head -c 1500\n' "$LT_ROOT" "$LT_ROOT" "$LT_DB" "$(rl_wsl_path "$RL_HAFF")" "$(rl_q "$1")" "$(rl_q "$2")" "${3:-0}" "${4:-read}" | lt_w >> "$EV/haff-$tag.txt"
  echo >> "$EV/haff-$tag.txt"
}
rl_inv() {  # rl_inv <tag> : inventories of Shay and the NPC -> inv_<tag>.txt (one line each: NAME <inv output>)
  local c; : > "$EV/inv_$1.txt"
  for c in Shay "${RL_NPC_FULL:-Cind}"; do
    printf '%s ' "$(echo "$c" | tr a-z A-Z)" >> "$EV/inv_$1.txt"
    printf 'stobe-auto inv %s </dev/null 2>&1 | tr "\\n" " " | cut -c1-2500\n' "$(rl_q "$c")" | lt_h >> "$EV/inv_$1.txt"; echo >> "$EV/inv_$1.txt"
  done
}
rl_dist() { rl_resolve >/dev/null 2>&1; echo "${RL_NPC_FULL:-?}|${RL_DIST:-?}" >> "$EV/distance.txt"; }
rl_final_dump() {
  lt_sql "select * from social_effect order by 1 desc limit 40" > "$EV/social_effect.txt"
  lt_sql "select status,left(coalesce(detail::text,''),200) from stobe_social_contract order by 1 limit 20" > "$EV/deals.txt" 2>&1
  lt_sql "select rowid,left(data,300) from eventlog where type='travel_agreement' order by rowid desc limit 5" > "$EV/agreements.txt"
  rl_dist
}
rl_gametime() {  # prints the first number of `stobe-auto time` (game hours or day count; format is checked by the caller)
  echo 'stobe-auto time </dev/null 2>&1 | head -2' | lt_h | tee -a "$EV/time.txt" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1
}
rl_advance_gametime() {  # rl_advance_gametime <seconds of real time at speed 10> ; speed back to 0.5. rc 3 if time unreadable
  local t0 t1; t0=$(rl_gametime); [ -n "$t0" ] || { RL_REASON="cannot read game time (stobe-auto time returned no number)"; return 3; }
  lt_h <<EOT >> "$EV/time.txt" 2>&1
stobe-auto speed 10 </dev/null | head -1
sleep ${ADV_SECONDS:-120}
stobe-auto speed 0.5 </dev/null | head -1
EOT
  t1=$(rl_gametime); echo "time0=$t0 time1=$t1" >> "$EV/time.txt"; RL_T0="$t0"; RL_T1="$t1"
  [ -n "$t1" ]
}
