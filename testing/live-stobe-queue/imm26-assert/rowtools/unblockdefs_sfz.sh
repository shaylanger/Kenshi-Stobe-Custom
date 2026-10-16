#!/usr/bin/env bash
# unblockdefs_sfz.sh (imm26-sfZ): row 03-b recipe, retry-loop + chance seam variant. NEW file; unblockdefs_d.sh / unblockdefs_d2.sh are sourced as libraries and NOT edited. Sourced by unblockrun_sfz.sh.
# Why (4080-i3 op21 finding, 03-b SETUP-FAIL: "6 director tries all no_gossip, 'Bored event skipped: chance gate roll 85/91 chance 85' even with BORED_EVENT_CHANCE=100"):
#  1 Cause of the 85: bored.php:130-148 reads the chance with getNpcProfileIntegerSetting -> stobeReadLayeredSettingRaw: NPC override (core_npc_master metadata / extended_data.setting_overrides)
#    -> core_profiles.metadata -> global general_settings LAST. u3_chance_set only writes the global row, so a profile value (<= 85 after the initiative bump) wins and ~15% of ticks roll >= 85.
#    Seam (no server change, lane DB only): sz_npc_chance_set writes extended_data.setting_overrides.BORED_EVENT_CHANCE=100 on the SPEAKER's core_npc_master row (highest layer), the old
#    override value is remembered (npc_chance_old.txt) and put back by sz_npc_chance_restore. Verified in the loop: a gate-skip log line with chance != 100 is flagged in gossip_tries.txt.
#  2 Even with the gate open the row only fires when the LLM line NAMES the subject (stobeKnowledgeShareFromSpeech -> stobeKnowledgeMentions): that is the lottery. Bounded retry loop:
#    up to U03B_TRIES (default 24) fresh pair requests, stop at the FIRST heard_from row; a tick that died at the chance gate costs no LLM call, is retried after 2 s and does not use the
#    spoken budget SZ_MAX_SPOKEN (default 12 ticks that reached the speech); http_err twice in a row stops. SETUP-FAIL names the counts (tries / gated / spoken).
# Extra evidence: npc_chance_old.txt, npc_chance.txt, gossip_tries.txt (tick k res=.. gate=0|1 chance=..), gossip_ok.txt ("ok tick=k gated=g spoken=s" | "none tries=N gated=g spoken=s").
SZ_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F rd_03b_body >/dev/null || . "$SZ_HERE/unblockdefs_d.sh"
declare -F d2_hearsay_check >/dev/null || . "$SZ_HERE/unblockdefs_d2.sh"
: "${U03B_TRIES:=24}"; : "${SZ_MAX_SPOKEN:=12}"; export U03B_TRIES SZ_MAX_SPOKEN

# ---- per-NPC chance seam (the layer that actually wins over the global BORED_EVENT_CHANCE)
sz_npc_where() { local f="${RL_NPC_FULL%% \[*}"; printf "name in ('%s','%s')" "$(u3_sq "$RL_NPC_FULL")" "$(u3_sq "$f")"; }
sz_npc_chance_set() {
  lt_sql "select coalesce(max(extended_data->'setting_overrides'->>'BORED_EVENT_CHANCE'),'unset') from core_npc_master where $(sz_npc_where) /* u3:sznpcold */" | head -1 | tr -d '\r' > "$EV/npc_chance_old.txt"
  lt_sqlx "update core_npc_master set extended_data = jsonb_set(coalesce(extended_data,'{}'::jsonb),'{setting_overrides}',coalesce(extended_data->'setting_overrides','{}'::jsonb) || '{\"BORED_EVENT_CHANCE\":100}'::jsonb) where $(sz_npc_where) /* u3:sznpcset */" >> "$EV/npc_chance.txt" 2>&1
}
sz_npc_chance_restore() {
  local old; old=$(head -1 "$EV/npc_chance_old.txt" 2>/dev/null | tr -d '\r')
  [ -n "$old" ] || return 0
  if [ "$old" = unset ]; then
    lt_sqlx "update core_npc_master set extended_data = extended_data #- '{setting_overrides,BORED_EVENT_CHANCE}' where $(sz_npc_where) /* u3:sznpcrest */" >> "$EV/npc_chance.txt" 2>&1
  else
    lt_sqlx "update core_npc_master set extended_data = jsonb_set(extended_data,'{setting_overrides,BORED_EVENT_CHANCE}','\"$(u3_sq "$old")\"'::jsonb) where $(sz_npc_where) /* u3:sznpcrest */" >> "$EV/npc_chance.txt" 2>&1
  fi
}

# ---- the retry loop (replaces the fixed `for k in 1..tries` of rd_03b_body); sets U3_RES, SZ_K, SZ_GATED, SZ_SPOKEN
sz_gossip_loop() {  # sz_gossip_loop <B full>
  local b="$1" k tries="${U03B_TRIES:-24}" gate http_run=0 lg chance
  SZ_GATED=0; SZ_SPOKEN=0; SZ_K=0; U3_RES=no_gossip
  for k in $(seq 1 "$tries"); do
    SZ_K=$k
    i4_gossip "g$k" "$b" || return $?
    lg="$EV/gossip_g${k}_log.txt"; gate=0; chance=""
    if grep -q 'chance gate' "$lg" 2>/dev/null; then gate=1; chance=$(grep -o '"chance":[0-9]*' "$lg" | head -1 | tr -dc 0-9); fi
    echo "tick $k res=$U3_RES gate=$gate chance=${chance:-n/a}" >> "$EV/gossip_tries.txt"
    [ "$U3_RES" = gossip ] && break
    if [ "$U3_RES" = http_err ]; then http_run=$((http_run+1)); [ "$http_run" -ge 2 ] && break; rw_sleep 4; continue; fi
    http_run=0
    if [ "$gate" = 1 ]; then SZ_GATED=$((SZ_GATED+1)); rw_sleep 2; continue; fi    # no LLM call happened: fresh roll, not charged to the spoken budget
    SZ_SPOKEN=$((SZ_SPOKEN+1))
    [ "$SZ_SPOKEN" -ge "${SZ_MAX_SPOKEN:-12}" ] && break
    rw_sleep 4
  done
  if [ "$U3_RES" = gossip ]; then echo "ok tick=$SZ_K gated=$SZ_GATED spoken=$((SZ_SPOKEN+1))" > "$EV/gossip_ok.txt"
  else echo "none tries=$SZ_K gated=$SZ_GATED spoken=$SZ_SPOKEN" > "$EV/gossip_ok.txt"; fi
}

# ---- row 03-b: rd_03b_body of unblockdefs_d.sh with the seam + the retry loop (everything else identical)
sz_03b_body() {
  local b now crow cid k bq n
  tr_cfg; unset ROW_NATIVE TR_SCENE
  rd_need_npc || return 3
  echo "$RL_NPC_FULL" > "$EV/npc.txt"
  tr_clean_db; rd_aff 60 platonic haff
  u3_chance_set; sz_npc_chance_set
  b=$(u3_pick_b | tail -1)
  if [ -z "$b" ]; then echo none > "$EV/b.txt"; return 0; fi
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
  [ -n "$crow" ] || return 0
  cid="${crow%%|*}"; now=$(u3_now); echo "${now:-0}" > "$EV/now.txt"
  u3_top8 "$cid" "${now:-0}"
  sz_gossip_loop "$b" || return $?
  u3_hearsay_row "$b" > "$EV/hearsay_row.txt"
  [ "$U3_RES" = gossip ] || return 0
  lt_h <<EOT >> "$EV/b_return.txt" 2>&1
stobe-auto teleport $bq Shay </dev/null | head -1
stobe-auto health $bq 100 </dev/null | head -1
EOT
  rl_resolve "$b" >/dev/null 2>&1; RL_NPC_FULL="$b"; ROW_NPC="$b"
  echo "$b" > "$EV/npc_b.txt"; ROW_NATIVE=1
  rl_say 1 "${RW_03B_SAY:-Have you heard anything about me?}" || return $?
  rl_aff "$b" Shay "" read aff_b
}

rd_03b() {
  tr_cfg
  d2_hearsay_check || return 0
  sz_03b_body "$@"; local rc=$?; u3_restore; sz_npc_chance_restore; return $rc
}
