#!/usr/bin/env bash
# unblockdefs_sfk.sh: imm26-sfK2 recipe v2 for row 11-b (no follow-up claim while the NPC is in combat; exactly one after). Sourced by unblockrun_sfk.sh AFTER unblockdefs_a.sh; it
# REDEFINES rd_11b only inside that process (unblockdefs_a.sh, unblockcheck_a.py, tripdefs.sh are NOT edited: queued scripts). The verdict is still unblockcheck_a.c_11b (via
# unblockpy_a.sh), unchanged and not weakened; every evidence file name it reads is kept (fu_pre.txt mark_rowid.txt state_combat_pre/combat/calm/calm2.txt claim_*.txt fu_combat/final.txt
# combat_rows.txt bored_<tag>.res/_log.txt).
# Why v1 (rd_11b in unblockdefs_a.sh) could not run - three independent recipe defects, evidence C:\KenshiTestRuns\imm26-4080-i4\rows\11-b and 11-b.prev, lane stobe.log 10:03-10:05:
#   A. "Make the topic claimable" by a real-time advance is not a game-time advance. 15 s at speed 10 = 14,940 game s: a NATURAL bored tick claimed the topic (ask_count 0->1,
#      mark_rowid > claim row) BEFORE the fight, and in the earlier run the advance was too short (tick gamets 280056 < not_before 280098). Either way c1b/c1a were vacuous.
#      v2: NO time advance at all. The topic stays unclaimable (not_before = created + 3600 game s) until the fight is proven, then ITS not_before_gamets is set to 1 in the lane DB
#      (follow-up rows carry no integrity digest, lib/social_followups.php) and fu_pre.txt is re-dumped, so the checker's not_before test is honest and no natural tick can claim it first.
#   B. The enemy was addressed by NAME. "Hungry Bandit" also names the natural Starving Bandits pack, so protect/fight/calm-teleport hit `#1856811520/4 [Starving Bandits]` while the
#      spawned `#1528930688/14` stayed (lane stobe.log: Korstev [Hungry Bandit] (HNO) attacks Cind until the end). v2 parses the `#serial/idx` from the spawn reply and uses it everywhere;
#      the calm teleport must name that serial (else SETUP-FAIL: wrong character moved).
#   C. The 15 s advance at x10 let the Hub's Holy Nation Outlaws and Slave Traders walk back and the spawned enemy joined HNO: `fight` sets the WHOLE faction pair Traders Guild <-> HNO to
#      -100 for the rest of the session (WorldCommands.inc:2222), so Wyth/Mordrith/Grunic/Drovic/Beles/... attacked Cind for 2+ minutes (combat events 10:03:12 - 10:05:51) and
#      in_combat never went false. v2: tr_quiet again right before the spawn + a scene check (strangers within 300 u after the quiet = SETUP-FAIL, listed in scene_pre.txt), the enemy
#      faction defaults to "Dust Bandits" (not the Hub's HNO; U11B_FACTION overrides), the calm leg POLLS state until in_combat=false (U11B_CALM_TRIES x U11B_CALM_S) instead of one fixed
#      sleep, and scene_calm.txt records who is near when combat does not end. The faction pair stays -100 until the lane's next reload (no harness reset command exists): any
#      neighbour of that faction coming back would re-engage Cind, the checker names that case (state_calm2 / "re-engaged").
#   Also: the claim gate refuses for 30 s real after any chat line (social_followups.php), so the first tick waits until >= 32 s after the topic line.
# Env: U11B_FACTION("Dust Bandits") U11B_DIST(20) U11B_FIGHT_S(10) U11B_CALM_S(15) U11B_CALM_TRIES(8) SFK_SCENE_R(300) SFK_SCENE_MAX(0) SFK_TICK_GAP_S(32) RW_FU_SAY.
SFK_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F i4_bored >/dev/null || . "$SFK_HERE/unblockdefs_a.sh"

sfk_scene() {   # sfk_scene <file> [exclude-serial]: non-squad characters within SFK_SCENE_R of the squad -> <file> (one "Name #s/i [Faction] ..." per line), count in <file>.n
  local ex="${2:-NOSUCHSERIAL}" r="${SFK_SCENE_R:-300}"
  lt_h <<EOT > "$EV/$1" 2>&1
stobe-auto chars $r </dev/null 2>&1 | sed 's/ | /\n/g' | grep -v -E "Shay #|${RL_NPC_FULL%% *} \[|Malzin #|#$ex" | grep -E "#[0-9]+/[0-9]+" | cut -c1-140 # sfk:scene
EOT
  grep -c -E '#[0-9]+/[0-9]+' "$EV/$1" 2>/dev/null | tr -dc 0-9 > "$EV/$1.n"; [ -s "$EV/$1.n" ] || echo 0 > "$EV/$1.n"
}

rd_11b() {
  local nq o en ens eq mark t_say el tid k max="${SFK_SCENE_MAX:-0}" n
  tr_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  u_topic "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  t_say=$(date +%s)
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                         # checker: SETUP-FAIL (no topic)
  cp "$EV/fu_pre.txt" "$EV/fu_pre0.txt" 2>/dev/null
  # --- C: re-clear the scene right before the fight (no advance happened, nothing has walked back) and prove it is empty
  u_heal; unset TR_SCENE; tr_quiet
  n=1
  for k in 1 2; do
    sfk_scene scene_pre.txt; n=$(cat "$EV/scene_pre.txt.n")
    [ "$n" -le "$max" ] && break
    tr_quiet
  done
  [ "$n" -le "$max" ] || { RL_REASON="scene not isolated: $n non-squad characters within ${SFK_SCENE_R:-300} u after 2 quiet passes ($(head -2 "$EV/scene_pre.txt" | cut -c1-80 | tr '\n' ';')): a third party would join the fight (needs: recipe, another scene / SFK_SCENE_R / SFK_SCENE_MAX)"; return 3; }
  mark=$(lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9); echo "${mark:-0}" > "$EV/mark_rowid.txt"
  # --- B: spawn, keep the serial
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
  u_state_combat state_combat_pre.txt
  # --- A: make the topic claimable only now (after combat is proven), then re-dump so the checker's not_before is the real value
  tid=$(grep -o '"topic_id":"[^"]*"' "$EV/fu_pre.txt" | head -1 | cut -d'"' -f4)
  [ -n "$tid" ] || { RL_REASON="no topic_id in fu_pre.txt"; return 3; }
  lt_sqlx "update eventlog set data=regexp_replace(data,'\"not_before_gamets\":[0-9]+','\"not_before_gamets\":1') where type='social_followup' and rowid=(select max(rowid) from eventlog where type='social_followup' and data like '%\"topic_id\":\"$tid\"%')" > "$EV/claimable.txt" 2>&1
  rw_fu_dump fu_pre.txt
  grep -q '"not_before_gamets":1[,}]' "$EV/fu_pre.txt" || { RL_REASON="could not make the topic claimable (UPDATE gave: $(head -1 "$EV/claimable.txt" | cut -c1-120)); needs: recipe"; return 3; }
  el=$(( $(date +%s) - t_say )); [ "$el" -ge "${SFK_TICK_GAP_S:-32}" ] || rw_sleep $(( ${SFK_TICK_GAP_S:-32} - el ))
  i4_bored c1b 0 || return $?                                                                    # tick WITHOUT a snapshot first (what a natural tick looks like)
  u_claim_dump claim_c1b.txt "$mark"; rw_fu_dump fu_c1b.txt
  i4_bored c1a 1 || return $?                                                                    # then WITH a fresh snapshot (in_combat visible to the attention gate)
  u_state_combat state_combat.txt; u_claim_dump claim_c1a.txt "$mark"; rw_fu_dump fu_combat.txt
  lt_sql "select count(*) from eventlog where type='combat' and rowid>${mark:-0}" > "$EV/combat_rows.txt" 2>&1
  # --- end the fight: the SPAWNED enemy leaves, orders cleared, then poll until the NPC is out of combat
  lt_h <<EOT >> "$EV/calm.txt" 2>&1
stobe-auto teleport $eq $U_FAR </dev/null | head -1
stobe-auto order $nq NULL_TASK </dev/null | head -1
EOT
  grep -qF "#$ens" "$EV/calm.txt" || { RL_REASON="calm teleport did not move the spawned enemy #$ens: $(head -1 "$EV/calm.txt" | cut -c1-160)"; return 3; }
  : > "$EV/calm_poll.txt"
  for k in $(seq 1 "${U11B_CALM_TRIES:-8}"); do
    rw_sleep "${U11B_CALM_S:-15}"
    u_state_combat state_calm.txt; echo "$k $(cat "$EV/state_calm.txt")" >> "$EV/calm_poll.txt"
    grep -q 'in_combat=false' "$EV/state_calm.txt" && break
  done
  sfk_scene scene_calm.txt "$ens"
  u_heal
  u_state_combat state_calm2.txt                                                                 # re-read right before c2: the checker demands in_combat=false here
  i4_bored c2 1 || return $?
  u_claim_dump claim_after.txt "$mark"; rw_fu_dump fu_final.txt
}
