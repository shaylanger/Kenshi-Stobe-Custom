#!/usr/bin/env bash
# unblockdefs_d.sh: one-call row 03-b (rumor hearsay reaches B) for the 4080-i4 operator (imm26-rowtools-03b). Sourced by unblockrun_d.sh AFTER go-row.sh and reloaddefs_a.sh.
# NEW file: no existing rowtools file is edited. Sources unblockdefs_a.sh for u_heal / U_FAR only (its rd_08e/rd_08d/rd_11b are redefined but never called here).
# Why this exists (agents/out/imm26-inv-03b2/latest.md RECIPE): a director scene is a random 12-NPC cast, and a Hub guard (Zelvia, 75 eligible rows) never shows the hearsay
# row in the prompt (stobeKnowledgeClaimsFor LIMIT 12 + top-3 "about" cut). So: a SPARSE B, Cind's Shay first-hand row made her newest, and ONE targeted mode=autochat request.
#   Steps (rd_03b):
#     1 resolve Cind (the witness W), BORED_EVENT_CHANCE=100 on the private backend (old value saved, restored at the end)
#     2 u3_pick_b: sparse B = digit serial, awake, non-slave, <= U03B_MAX_ROWS (6) social_rumor rows, <= 2 about Shay, near Shay (chars radius U03B_RADIUS 400); U03B_B=<full name> forces one
#     3 quiet scene (everyone except Shay/Cind/Malzin/B away), B sent far + protected (B must not see the attack), Cind->Shay and Cind->Malzin affinity 60
#     4 unwitnessed attack: Shay hits Malzin (harness `hit`, same recipe as 10-b), Cind watches; Cind's newest Shay first-hand row is read (u3:crow)
#     5 make that row her newest AND inside her top 8 (game_ts = now; rows that outrank it are set status=superseded_03b, ids in superseded.txt, restore SQL in the operator sheet)
#     6 up to U03B_TRIES (6) targeted pair requests (i4_gossip: the i4_bored mechanism, unblockdefs_a.sh:27-65, WITHOUT optional=1 and with listener=B in "(talking to: B)" and people),
#       until the DB holds social_rumor holder=B basis=heard_from source=Cind hops=1 (log 'NPC gossip passed on' without via=director is checked by the verdict)
#     7 B back next to Shay, ctxpush, ONE chat line "Have you heard anything about me?" -> s1/prompt.txt must hold '[hearsay from Cind'
#   Evidence: npc.txt b.txt b_candidates.txt chars.txt cind_row.txt cind_rank.txt superseded.txt attack.txt gossip_<k>.txt/_log.txt/.res gossip_ok.txt hearsay_row.txt gossip_all.txt s1/
# Env: U03B_B U03B_MAX_ROWS U03B_RADIUS U03B_TRIES(6) U03B_ATTACK_WAIT(10) U03B_NO_ATTACK=1 (use Cind's existing newest Shay row) U03B_DEMOTE(1) RW_03B_SAY.
U_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F rw_prep >/dev/null || . "$U_HERE/reloaddefs_a.sh"
declare -F u_heal >/dev/null || . "$U_HERE/unblockdefs_a.sh"
U3_BASIS="'experienced','saw','heard'"
u3_sq() { printf '%s' "${1//\'/\'\'}"; }
u3_now() { lt_sql "select coalesce(max(gamets),0) from eventlog /* u3:now */" | head -1 | tr -dc 0-9; }

# ---- BORED_EVENT_CHANCE=100 (the roll in bored.php:119-149 is 50% by default); old value remembered for u3_restore
u3_chance_set() {
  lt_sql "select coalesce((select value from general_settings where id='BORED_EVENT_CHANCE'),'unset') /* u3:chance */" | head -1 > "$EV/bored_chance_old.txt"
  lt_sqlx "update general_settings set value='100' where id='BORED_EVENT_CHANCE'; insert into general_settings(id,value) select 'BORED_EVENT_CHANCE','100' where not exists (select 1 from general_settings where id='BORED_EVENT_CHANCE')" >> "$EV/chance.txt" 2>&1
}
u3_restore() {
  local old; old=$(head -1 "$EV/bored_chance_old.txt" 2>/dev/null | tr -d '\r')
  [ -n "$old" ] || return 0
  if [ "$old" = unset ]; then lt_sqlx "delete from general_settings where id='BORED_EVENT_CHANCE'" >> "$EV/chance.txt" 2>&1
  else lt_sqlx "update general_settings set value='$(u3_sq "$old")' where id='BORED_EVENT_CHANCE'" >> "$EV/chance.txt" 2>&1; fi
}

# ---- sparse B
u3_pick_b() {  # prints the chosen full name (also b.txt); empty = none
  local f="$EV/chars.txt" cands="$EV/b_candidates.txt" cw="$EV/b_counts.txt" nm pick="" st
  if [ -n "${U03B_B:-}" ]; then echo "$U03B_B" | tee "$EV/b.txt"; return 0; fi
  lt_h <<EOT 2>&1 | sed 's/ | /\n/g' | grep -E '#-?[0-9]+/[0-9]+' > "$f"
stobe-auto chars ${U03B_RADIUS:-400} </dev/null 2>&1 | head -c 20000 # u3:chars
EOT
  lt_sql "select holder_name||'|'||count(*)||'|'||count(*) filter (where lower(subject_name) like 'shay%' or lower(victim_name) like 'shay%') from social_rumor where status='active' group by holder_name /* u3:counts */" > "$cw" 2>&1
  # candidates: positive serial only (the regexp needs digits right after '#'), not Shay/Malzin/the witness, faction not a slave faction
  sed -nE 's/^[[:space:]]*(.*[^ ]) #([0-9]+)\/[0-9]+ \[([^]]*)\].*/\1|\2|\3/p' "$f" | awk -F'|' -v w="$(printf %s "${RL_NPC_FULL%% *}" | tr A-Z a-z)" '
    {n=tolower($1); fa=tolower($3)} n ~ /^(shay|malzin)/ {next} index(n,w)==1 {next} fa ~ /slave/ {next} {print}' > "$EV/b_all.txt"
  awk -F'|' -v mx="${U03B_MAX_ROWS:-6}" 'NR==FNR{t[$1]=$2; a[$1]=$3; next} {c=($1 in t)?t[$1]:0; s=($1 in a)?a[$1]:0; if (c<=mx && s<=2) print s"|"c"|"$1}' "$cw" "$EV/b_all.txt" | sort -t'|' -k1,1n -k2,2n > "$cands"
  while IFS='|' read -r _ _ nm; do
    [ -n "$nm" ] || continue
    st=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 3000 # u3:state\n' "$(rl_q "$nm")" | lt_h 2>&1)
    echo "$st" | grep -q '"unconscious": \?false' || continue
    echo "$st" | grep -qiE '"(is_)?slave": ?true' && continue
    pick="$nm"; break
  done < <(head -8 "$cands")
  echo "$pick" | tee "$EV/b.txt"
}

# ---- scene: everyone but Shay/Cind/Malzin/B moved away; B sent far (must not witness) and protected
u3_quiet() {  # u3_quiet <B full>
  local n b bs; n=$(rl_q "$RL_NPC_FULL"); b=$(rl_q "$1"); bs="${1%% *}"
  lt_h <<EOT >> "$EV/quiet.txt" 2>&1
stobe-auto teleport $n Shay </dev/null | head -1
stobe-auto teleport Malzin Shay </dev/null | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null | head -1
for pass in 1 2; do
  stobe-auto chars 400 </dev/null 2>&1 | sed 's/ | /\n/g' | grep -v -E "Shay #|${RL_NPC_FULL%% *} \[|Malzin #|$bs " | grep -E "#[0-9]+/[0-9]+" | sed -E 's/.*#([0-9]+\/[0-9]+).*/\1/' | sort -u > /tmp/u3-ids.txt
  while read id; do stobe-auto teleport "#\$id" $U_FAR </dev/null >/dev/null 2>&1; done < /tmp/u3-ids.txt
done
stobe-auto protect $b on </dev/null | head -1
stobe-auto teleport $b $U_FAR </dev/null | head -1
for nm in Shay $n Malzin; do stobe-auto health "\$nm" 100 </dev/null >/dev/null 2>&1; done
stobe-auto protect $n on </dev/null | head -1
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
}

# ---- Cind's best Shay first-hand row; make it newest + inside her top 8
u3_crow() {  # prints id|subject|victim|basis|severity|game_ts|learned_ts of her newest Shay first-hand row (empty = none)
  lt_sql "select id||'|'||subject_name||'|'||victim_name||'|'||basis||'|'||severity||'|'||game_ts||'|'||learned_ts from social_rumor where status='active' and holder_name='$(u3_sq "$RL_NPC_FULL")' and hops=0 and basis in ($U3_BASIS) and lower(subject_name) like 'shay%' order by id desc limit 1 /* u3:crow */" | head -1 | tr -d '\r'
}
u3_top8() {  # u3_top8 <id> <now>: bump the row to 'now', then demote rows that outrank it; writes cind_rank.txt (rows outranking AFTER the step) and superseded.txt
  local id="$1" now="$2" h sev rank
  h=$(lt_sql "select severity from social_rumor where id=$id /* u3:sev */" | head -1 | tr -dc 0-9); sev=${h:-1}
  lt_sqlx "update social_rumor set game_ts=$now, learned_ts=least(learned_ts,$now), ttl_ts=greatest(ttl_ts,$now+864000) where id=$id" >> "$EV/bump.txt" 2>&1
  rank=$(lt_sql "select count(*) from social_rumor where status='active' and holder_name='$(u3_sq "$RL_NPC_FULL")' and hops=0 and basis in ($U3_BASIS) and learned_ts<=$now and ttl_ts>$now and id<>$id and severity>$sev /* u3:rank */" | head -1 | tr -dc 0-9)
  echo "rank_before=${rank:-0} sev=$sev" > "$EV/cind_rank.txt"
  if [ "${rank:-0}" -ge 8 ] && [ "${U03B_DEMOTE:-1}" = 1 ]; then
    lt_sql "select string_agg(id::text,',') from social_rumor where status='active' and holder_name='$(u3_sq "$RL_NPC_FULL")' and hops=0 and basis in ($U3_BASIS) and id<>$id and severity>$sev /* u3:ids */" | head -1 | tr -d '\r' > "$EV/superseded.txt"
    lt_sqlx "update social_rumor set status='superseded_03b' where status='active' and holder_name='$(u3_sq "$RL_NPC_FULL")' and hops=0 and basis in ($U3_BASIS) and id<>$id and severity>$sev" >> "$EV/bump.txt" 2>&1
    echo "rank_after=0 demoted_ids_file=superseded.txt" >> "$EV/cind_rank.txt"
  else echo "rank_after=${rank:-0}" >> "$EV/cind_rank.txt"; fi
}

# ---- the targeted PAIR request (i4_bored without optional=1, listener = B); result in U3_RES: gossip|no_gossip|http_err
u3_hearsay_row() {  # u3_hearsay_row <B full> -> row(s) holder=B basis=heard_from source=Cind hops=1 (empty = none)
  lt_sql "select id||'|'||holder_name||'|'||subject_name||'|'||basis||'|'||source_name||'|'||hops||'|'||confidence||'|'||learned_ts from social_rumor where status='active' and holder_name='$(u3_sq "$1")' and basis='heard_from' and source_name like '${RL_NPC_FULL%% *}%' and hops=1 order by id desc limit 3 /* u3:brow */" | tr -d '\r'
}
i4_gossip() {  # i4_gossip <tag> <B full>
  local tag="$1" b="$2" nm s0 f="$EV/gossip_$1.txt" res bs row
  nm="${RL_NPC_FULL%% \[*}"; bs="${b%% *}"
  s0=$(printf 'wc -l < %s # u3:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); s0=${s0:-0}
  lt_w <<EOT > "$f" 2>&1
# u3:stream
G=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select coalesce(max(gamets),0) from eventlog")
D=\$(printf 'bored|%s|%s|%s: [BORED_EVENT_TRIGGER] (talking to: %s)' "\$(date +%s)" "\$G" "$RL_NPC_FULL" "$b" | base64 -w0 | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe=""))')
P=\$(python3 -c 'import sys,urllib.parse,json;print(urllib.parse.quote(json.dumps([sys.argv[1],sys.argv[2],sys.argv[3]]),safe=""))' "$RL_NPC_FULL" "$b" "Shay")
T=\$(runuser -u postgres -- psql -h $LT_ROOT/socket -p $LT_PG -d $LT_DB -At -c "select (value::json)->>'token' from stobe_meta.settings where key='PLAYTHROUGH_SESSION'")
curl -s -m 150 -H "X-Stobe-Playthrough: \$T" -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:$LT_PORT/stream.php?DATA=\$D&profile=$(printf %s "$nm" | sed 's/ /%20/g')&people=\$P&mode=autochat" | head -c 800
EOT
  rw_sleep 3
  printf 'tail -n +%s %s 2>/dev/null | grep -a -E "gossip passed on|BORED|chance gate|no eligible|Targeted|Director scene" | cut -c1-320 | tail -8 # u3:tlog\n' "$(( s0 + 1 ))" "$LT_SRVLOG" | lt_w > "$EV/gossip_${tag}_log.txt" 2>&1
  row=$(u3_hearsay_row "$b"); echo "$row" > "$EV/gossip_${tag}_row.txt"
  if ! grep -q 'HTTP=200' "$f"; then res=http_err
  elif [ -n "$row" ]; then res=gossip
  else res=no_gossip; fi
  echo "$res" > "$EV/gossip_$tag.res"; U3_RES="$res"
  [ "$res" = http_err ] || echo "$tag" >> "$EV/gossip_ticks.txt"
  { echo "## $tag res=$res"; cat "$f"; cat "$EV/gossip_${tag}_log.txt"; } >> "$EV/gossip_all.txt"
  return 0
}

# ------------------------------------------------------------------ row 03-b
rd_03b() { rd_03b_body "$@"; local rc=$?; u3_restore; return $rc; }
rd_03b_body() {
  local b now crow cid k tries="${U03B_TRIES:-6}" mark n bq
  tr_cfg; unset ROW_NATIVE TR_SCENE
  rd_need_npc || return 3
  echo "$RL_NPC_FULL" > "$EV/npc.txt"
  tr_clean_db; rd_aff 60 platonic haff
  u3_chance_set
  b=$(u3_pick_b | tail -1)
  if [ -z "$b" ]; then echo none > "$EV/b.txt"; return 0; fi                                      # checker: SETUP-FAIL (no sparse B)
  n=$(rl_q "$RL_NPC_FULL"); bq=$(rl_q "$b")
  u3_quiet "$b"
  rl_aff "$RL_NPC_FULL" Malzin 60 platonic aff_cm
  rl_resolve "$ROW_NPC" >/dev/null 2>&1
  if [ "${U03B_NO_ATTACK:-0}" != 1 ]; then
    lt_h <<EOT >> "$EV/attack.txt" 2>&1
stobe-auto protect Malzin off </dev/null 2>&1 | head -1
stobe-auto hit Shay Malzin head 130 </dev/null 2>&1 | head -2
sleep ${U03B_ATTACK_WAIT:-10}
stobe-auto health Malzin 100 </dev/null 2>&1 | head -1
stobe-auto wake Malzin </dev/null 2>&1 | head -1
stobe-auto protect Malzin on </dev/null 2>&1 | head -1
stobe-auto health Shay 100 </dev/null 2>&1 | head -1
EOT
    rw_sleep 5
  fi
  crow=$(u3_crow)
  for k in 1 2 3 4; do [ -n "$crow" ] && break; rw_sleep 6; crow=$(u3_crow); done
  echo "$crow" > "$EV/cind_row.txt"
  [ -n "$crow" ] || return 0                                                                     # checker: SETUP-FAIL (no first-hand row)
  cid="${crow%%|*}"; now=$(u3_now); echo "${now:-0}" > "$EV/now.txt"
  u3_top8 "$cid" "${now:-0}"
  for k in $(seq 1 "$tries"); do
    i4_gossip "g$k" "$b" || return $?
    echo "tick $k res=$U3_RES" >> "$EV/gossip_tries.txt"
    [ "$U3_RES" = gossip ] && break
    [ "$U3_RES" = http_err ] && [ "$k" -ge 2 ] && break
    rw_sleep 4
  done
  if [ "$U3_RES" = gossip ]; then echo "ok tick=$k" > "$EV/gossip_ok.txt"; else echo "none tries=$k" > "$EV/gossip_ok.txt"; fi
  u3_hearsay_row "$b" > "$EV/hearsay_row.txt"
  [ "$U3_RES" = gossip ] || return 0                                                             # checker: SETUP-FAIL (pair never formed)
  # --- B next to Shay, then the question
  lt_h <<EOT >> "$EV/b_return.txt" 2>&1
stobe-auto teleport $bq Shay </dev/null | head -1
stobe-auto health $bq 100 </dev/null | head -1
EOT
  rl_resolve "$b" >/dev/null 2>&1; RL_NPC_FULL="$b"; ROW_NPC="$b"
  echo "$b" > "$EV/npc_b.txt"; ROW_NATIVE=1
  rl_say 1 "${RW_03B_SAY:-Have you heard anything about me?}" || return $?
  rl_aff "$b" Shay "" read aff_b
}
