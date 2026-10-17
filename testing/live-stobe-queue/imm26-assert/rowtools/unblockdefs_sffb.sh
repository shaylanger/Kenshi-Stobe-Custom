#!/usr/bin/env bash
# unblockdefs_sffb.sh: imm26-sfFixA3 recipe v3 for row 11-b. Sourced by unblockrun_sffb.sh AFTER unblockdefs_a.sh and unblockdefs_sfk.sh; it REDEFINES rd_11b only inside that process
# (unblockdefs_a.sh, unblockdefs_sfk.sh, unblockcheck_a.py, row-runners.tsv are NOT edited). The verdict is still unblockcheck_a.c_11b (via unblockpy_a.sh), unchanged and not weakened;
# every evidence file the checker reads keeps its name (fu_pre/mark_rowid/state_combat_pre/combat/calm/calm2/claim_*/fu_combat/final/combat_rows/bored_*).
# Why v3 (evidence: sfK2 v2 run, unblockdefs_sfk.sh header): v2 proved the combat leg (in_combat=true source=eventlog, no claim while in combat) but its END of the fight teleported the
# spawned enemy to U_FAR (14 k u away) and sent `order Cind NULL_TASK`; from then every `stobe_state 'Cind [Hungry Bandit]'` answered "target not found" (checker: SETUP-FAIL "NPC vanished").
# The harness name lookup (main.cpp ResolveTestInboxTarget) matches getName() exactly or '#serial/idx', and only inside the character update list or 500 u of Shay; the cause inside the
# game is unproven, so v3 removes every suspected trigger and adds a serial-based way to still read her:
#   (a) END = KO the enemy (`stobe-auto ko '#enemy' 900`): no teleport, no NULL_TASK. U11B_END=far restores the old end; U11B_END=ko (default).
#   (b) Cind is tracked by serial (`where '#serial'`) every calm poll and recalled (`teleport '#serial' Shay`) when she is farther than U11B_RECALL_DIST (120) or the lookup fails.
#   (c) The state read falls back from the NAME to '#serial/idx' (both replies are logged to combat_probe.txt) before it says in_combat=gone.
#   (d) Only if she is STILL in combat after half the calm polls, escalate ONCE with the old end (enemy to U_FAR + NULL_TASK); calm_track.txt says so.
# Env: U11B_END(ko|far) U11B_RECALL_DIST(120) plus everything of unblockdefs_sfk.sh (U11B_FACTION U11B_DIST U11B_FIGHT_S U11B_CALM_S U11B_CALM_TRIES SFK_* RW_FU_SAY).
SFFB_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F sfk_scene >/dev/null || . "$SFFB_HERE/unblockdefs_sfk.sh"

sffb_state_combat() {   # sffb_state_combat <file>: like u_state_combat, but a NAME lookup that fails is retried by '#serial/idx' (RL_NPC_ID) before in_combat=gone
  local js ic src="" k nm sq row id="${RL_NPC_ID:-}"; nm="$RL_NPC_FULL"; sq="${nm//\'/\'\'}"
  js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000 # u:state\n' "$(rl_q "$nm")" | lt_h 2>&1)
  if echo "$js" | grep -qiE 'no character named|ERROR|not found' && [ -n "$id" ]; then
    echo "name-lookup-failed $1 [$(echo "$js" | head -c 120 | tr '\n' ' ')] -> serial $id" >> "$EV/combat_probe.txt"
    js=$(printf 'stobe-auto stobe_state %s </dev/null 2>&1 | head -c 6000 # u:state\n' "$(rl_q "$id")" | lt_h 2>&1)
    echo "serial $1 [$(echo "$js" | head -c 160 | tr '\n' ' ')]" >> "$EV/combat_probe.txt"
  fi
  ic=$(echo "$js" | grep -oE '"in_combat": ?(true|false)' | head -1 | grep -oE 'true|false'); [ -n "$ic" ] && src=stobe_state
  if [ -z "$ic" ] && ! echo "$js" | grep -qiE 'no character named|ERROR|not found'; then
    for k in $(seq 1 "${U_SNAP_TRIES:-3}"); do
      printf 'stobe-auto stobe_ctxpush %s </dev/null 2>&1 | head -1 # u:cp\n' "$(rl_q "$nm")" | lt_h >/dev/null 2>&1; rw_sleep 1.5
      row=$(lt_sql "select coalesce(((metadata::jsonb)->'native_ai'->'combat'->>'in_combat'),case when ((metadata::jsonb)->'native_ai'->>'observed')='true' then 'false' end,'none') from core_npc_master where lower(name) = lower('$sq') order by updated_at desc limit 1 /* u:snap */" 2>&1 | head -2 | tr -d '\r')
      echo "snap$k $1 [$row]" >> "$EV/combat_probe.txt"
      ic=$(echo "$row" | head -1 | tr -dc 'a-z'); case "$ic" in true|false) src=native_snapshot; break;; *) ic="";; esac
    done
  fi
  if [ -z "$ic" ] && ! echo "$js" | grep -qiE 'no character named|ERROR|not found'; then
    row=$(lt_sql "select data from eventlog where type='combat' and data like '%$sq%' order by rowid desc limit 1 /* u:evt */" 2>&1 | head -1 | tr -d '\r' | cut -c1-160)
    echo "evt $1 [$row]" >> "$EV/combat_probe.txt"
    case "$row" in '') ;; *[Ee]nded*) ic=false; src=eventlog;; *) ic=true; src=eventlog;; esac
  fi
  echo "state $1 [$(echo "$js" | head -c 160 | tr '\n' ' ')]" >> "$EV/combat_probe.txt"
  if echo "$js" | grep -qiE 'no character named|ERROR|not found'; then echo "in_combat=gone $(echo "$js" | head -1 | cut -c1-120)" > "$EV/$1"
  else echo "in_combat=${ic:-unknown}${src:+ (source=$src)}" > "$EV/$1"; fi
}

sffb_track() {   # sffb_track <poll#>: Cind's distance to Shay by serial -> calm_track.txt; recall when far or not found. Never fails the row.
  local id="${RL_NPC_ID:-}" w d rec=0 lim="${U11B_RECALL_DIST:-120}"
  [ -n "$id" ] || { echo "$1 no-serial" >> "$EV/calm_track.txt"; return 0; }
  w=$(printf 'stobe-auto where %s </dev/null 2>&1 | head -1 # sffb:track\n' "$(rl_q "$id")" | lt_h 2>&1)
  d=$(echo "$w" | sed -nE 's/.*dist=([0-9.]+).*/\1/p' | head -1)
  if [ -z "$d" ] || awk -v d="$d" -v l="$lim" 'BEGIN{exit !(d+0>l+0)}'; then
    printf 'stobe-auto teleport %s Shay </dev/null 2>&1 | head -1 # sffb:recall\n' "$(rl_q "$id")" | lt_h >> "$EV/recall.txt" 2>&1; rec=1
  fi
  echo "$1 dist=${d:-none} recalled=$rec [$(echo "$w" | cut -c1-100)]" >> "$EV/calm_track.txt"
}

sffb_old_end() {   # the v2 end: spawned enemy to U_FAR + NULL_TASK on the NPC. rc 3 + RL_REASON when the wrong serial moved
  local eq="$1" ens="$2" nq="$3"
  lt_h <<EOT >> "$EV/calm.txt" 2>&1
stobe-auto teleport $eq $U_FAR </dev/null | head -1
stobe-auto order $nq NULL_TASK </dev/null | head -1
EOT
  grep -qF "#$ens" "$EV/calm.txt" || { RL_REASON="calm teleport did not move the spawned enemy #$ens: $(head -1 "$EV/calm.txt" | cut -c1-160)"; return 3; }
}

sffb_end_fight() {   # sffb_end_fight <enemy-quoted> <enemy-serial/idx> <npc-quoted>: ends the fight, polls until in_combat=false. rc 3 + RL_REASON = SETUP-FAIL
  local eq="$1" ens="$2" nq="$3" k tries="${U11B_CALM_TRIES:-8}" esc=0 half ko
  : > "$EV/calm_poll.txt"; : > "$EV/calm_track.txt"
  if [ "${U11B_END:-ko}" = far ]; then
    echo "end=far (U11B_END=far)" >> "$EV/calm_track.txt"; sffb_old_end "$eq" "$ens" "$nq" || return $?; esc=1
  else
    ko=$(printf 'stobe-auto ko %s 900 </dev/null 2>&1 | head -2 # sffb:ko\n' "$eq" | lt_h 2>&1); echo "$ko" > "$EV/ko.txt"
    echo "$ko" | grep -qi 'knocked out' || { RL_REASON="ko of the spawned enemy #$ens failed: $(echo "$ko" | head -1 | cut -c1-160) (needs: U11B_END=far)"; return 3; }
    echo "end=ko enemy #$ens" >> "$EV/calm_track.txt"
  fi
  half=$(( (tries + 1) / 2 ))
  for k in $(seq 1 "$tries"); do
    rw_sleep "${U11B_CALM_S:-15}"
    sffb_track "$k"
    sffb_state_combat state_calm.txt; echo "$k $(cat "$EV/state_calm.txt")" >> "$EV/calm_poll.txt"
    grep -q 'in_combat=false' "$EV/state_calm.txt" && break
    if [ "$esc" = 0 ] && [ "$k" -ge "$half" ] && grep -q 'in_combat=true' "$EV/state_calm.txt"; then
      esc=1; echo "$k ESCALATE: still in combat after the KO, old end (enemy to U_FAR + NULL_TASK) once" >> "$EV/calm_track.txt"
      sffb_old_end "$eq" "$ens" "$nq" || return $?
    fi
  done
  return 0
}

rd_11b() {
  local nq o en ens eq mark t_say el tid k max="${SFK_SCENE_MAX:-0}" n
  tr_prep || return $?
  [ -n "${RL_NPC_ID:-}" ] || rl_resolve >/dev/null 2>&1 || true
  nq=$(rl_q "$RL_NPC_FULL")
  u_topic "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  t_say=$(date +%s)
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                         # checker: SETUP-FAIL (no topic)
  cp "$EV/fu_pre.txt" "$EV/fu_pre0.txt" 2>/dev/null
  u_heal; unset TR_SCENE; tr_quiet
  n=1
  for k in 1 2; do
    sfk_scene scene_pre.txt; n=$(cat "$EV/scene_pre.txt.n")
    [ "$n" -le "$max" ] && break
    tr_quiet
  done
  [ "$n" -le "$max" ] || { RL_REASON="scene not isolated: $n non-squad characters within ${SFK_SCENE_R:-300} u after 2 quiet passes ($(head -2 "$EV/scene_pre.txt" | cut -c1-80 | tr '\n' ';')): a third party would join the fight (needs: recipe, another scene / SFK_SCENE_R / SFK_SCENE_MAX)"; return 3; }
  mark=$(lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9); echo "${mark:-0}" > "$EV/mark_rowid.txt"
  o=$(printf 'stobe-auto spawn "Hungry Bandit" %s near %s dist %s count 1 </dev/null 2>&1 | head -2\n' "$(rl_q "${U11B_FACTION:-Dust Bandits}")" "$nq" "${U11B_DIST:-20}" | lt_h 2>&1)
  echo "$o" > "$EV/spawn.txt"
  ens=$(echo "$o" | sed -nE 's/.*[^0-9]#([0-9]+\/[0-9]+).*/\1/p' | head -1)
  en=$(echo "$o" | sed -nE 's/^spawned [0-9]+\/[0-9]+ [^:]*: (.*) #[0-9]+\/[0-9]+.*/\1/p' | head -1)
  [ -n "$ens" ] || { RL_REASON="enemy spawn failed or unparseable reply (no #serial/index): $(echo "$o" | head -1 | cut -c1-160)"; return 3; }
  echo "#$ens" > "$EV/enemy.txt"; echo "${en:-?}" > "$EV/enemy_name.txt"
  eq=$(rl_q "#$ens")
  lt_h <<EOT >> "$EV/fight.txt" 2>&1
stobe-auto protect $nq on </dev/null | head -1
stobe-auto protect $eq on </dev/null | head -1
stobe-auto fight $nq $eq </dev/null 2>&1 | head -2
EOT
  grep -q 'fight (factions set' "$EV/fight.txt" || { RL_REASON="fight command did not start: $(tail -1 "$EV/fight.txt" | cut -c1-160) (needs: recipe, enemy faction must differ from Traders Guild)"; return 3; }
  rw_sleep "${U11B_FIGHT_S:-10}"
  sffb_state_combat state_combat_pre.txt
  tid=$(grep -o '"topic_id":"[^"]*"' "$EV/fu_pre.txt" | head -1 | cut -d'"' -f4)
  [ -n "$tid" ] || { RL_REASON="no topic_id in fu_pre.txt"; return 3; }
  lt_sqlx "update eventlog set data=regexp_replace(data,'\"not_before_gamets\":[0-9]+','\"not_before_gamets\":1') where type='social_followup' and rowid=(select max(rowid) from eventlog where type='social_followup' and data like '%\"topic_id\":\"$tid\"%')" > "$EV/claimable.txt" 2>&1
  rw_fu_dump fu_pre.txt
  grep -q '"not_before_gamets":1[,}]' "$EV/fu_pre.txt" || { RL_REASON="could not make the topic claimable (UPDATE gave: $(head -1 "$EV/claimable.txt" | cut -c1-120)); needs: recipe"; return 3; }
  el=$(( $(date +%s) - t_say )); [ "$el" -ge "${SFK_TICK_GAP_S:-32}" ] || rw_sleep $(( ${SFK_TICK_GAP_S:-32} - el ))
  i4_bored c1b 0 || return $?
  u_claim_dump claim_c1b.txt "$mark"; rw_fu_dump fu_c1b.txt
  i4_bored c1a 1 || return $?
  sffb_state_combat state_combat.txt; u_claim_dump claim_c1a.txt "$mark"; rw_fu_dump fu_combat.txt
  lt_sql "select count(*) from eventlog where type='combat' and rowid>${mark:-0}" > "$EV/combat_rows.txt" 2>&1
  sffb_end_fight "$eq" "$ens" "$nq" || return $?
  sfk_scene scene_calm.txt "$ens"
  u_heal
  sffb_state_combat state_calm2.txt
  i4_bored c2 1 || return $?
  u_claim_dump claim_after.txt "$mark"; rw_fu_dump fu_final.txt
}
