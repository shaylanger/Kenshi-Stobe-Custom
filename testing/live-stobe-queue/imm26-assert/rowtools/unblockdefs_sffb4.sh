#!/usr/bin/env bash
# unblockdefs_sffb4.sh: imm26-fix11b recipe v4 for row 11-b. Sourced by unblockrun_sffb4.sh AFTER unblockdefs_a.sh, unblockdefs_sfk.sh and unblockdefs_sffb.sh; it REDEFINES rd_11b only inside that
# process (v3 files, unblockdefs_a.sh, unblockdefs_sfk.sh, unblockcheck_a.py, row-runners.tsv are NOT edited). The verdict is still unblockcheck_a.c_11b (via unblockpy_a.sh), unchanged and
# not weakened; every evidence file name the checker reads is kept (fu_pre/mark_rowid/state_combat_pre/combat/calm/calm2/claim_*/fu_combat/final/combat_rows/bored_*).
# v3 (sffb) fixed the Cind handle loss and proved the combat leg; four recipe defects remained (evidence C:/KenshiTestRuns/imm26-5090-i3/rows/11-b, imm26-4080-i4/rows/11-b, commits 59566105, 3355d984):
#   (1) scene: v3 `unset TR_SCENE; tr_quiet` dumped strays at -53200 957 4893 = the ready save's own spot (16 non-squad characters within 300 u). v4: the squad goes to the quiet spot
#       U11B_SPOT (default -48000 1500 2960, valid on both lane saves: scene_pre n=0 on 4080-i4 and 5090-i3) right after tr_prep, and strays are dumped at U11B_DUMP (default -62030 330 16250,
#       ~17 k u away) instead of 5 k u, so the Hub outlaws do not walk back during the fight; tr_prep runs with TRIP_QUIET=0 (its tr_quiet is the one that dumps at -53200).
#   (2) people: v3 sent plain names, the server logged `social_followup_claim null: no_social_scope` on every tick and the no-claim checks passed VACUOUSLY. v4 sets U_BORED_SERIALS=1 (as rd_08d does,
#       unblockdefs_a.sh:175) AND guards each tick: a tick whose people had no serial, or whose server log says no_social_scope (or shows no follow-up path at all for the in-combat ticks),
#       is SETUP-FAIL "vacuous", never a PASS.
#   (3) post-combat: Felk/Gills/Ukil (Holy Nation Outlaws) stood next to the squad after the fight and their situated threat events (usable for 120 s real, lib/situated_dialogue.php age>120 skip)
#       won the bored slot before the follow-up (bored.php: situated first, follow-up only if none); claim_cooldown then blocks the same actor for 180 s and any actor for 60 s. v4: after the fight the
#       strays within 400 u are sent to U11B_DUMP again (scene_calm.txt must be empty or SETUP-FAIL), then the tick waits until the newest situated_event for the NPC is >= U11B_EVENT_AGE (125) s old
#       and the newest situated_remark_claim is >= U11B_CLAIM_COOL (185) s old (quiet_wait.txt; SETUP-FAIL with the event kind when they keep arriving within U11B_QUIET_MAX_S 300).
#   (4) combat proof + KO: (a) the native snapshot said in_combat=false while the eventlog had combat rows every ~7 s, so the checker (accepts only true / unknown+rows) said SETUP-FAIL. v4: a read
#       that says false is overridden to true (source=eventlog) when the newest eventlog `combat`/`combatend` row naming the NPC is a `combat` row <= U11B_COMBAT_AGE (20) s old; that also makes the calm
#       polls stricter (false only when combat rows stopped). (b) `protect <enemy> on` from the fight setup made the harness revive the KO'd enemy 2.3 s after the KO: v4 sends `protect <enemy> off` first
#       (unprotect.txt must say protect=off) and then the KO.
# Env: U11B_SPOT U11B_DUMP U11B_COMBAT_AGE U11B_EVENT_AGE U11B_CLAIM_COOL U11B_QUIET_MAX_S TR_SCENE (overrides U11B_SPOT) + everything of unblockdefs_sffb.sh / unblockdefs_sfk.sh (U11B_END U11B_RECALL_DIST
# U11B_FACTION U11B_DIST U11B_FIGHT_S U11B_CALM_S U11B_CALM_TRIES SFK_* RW_FU_SAY).
SFFB4_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F sffb_state_combat >/dev/null || . "$SFFB4_HERE/unblockdefs_sffb.sh"

sffb4_quiet() {   # sffb4_quiet [spot] [exclude-serial]: like tr_quiet (tripdefs.sh) but strays go to U11B_DUMP; with a spot the squad is teleported there first
  local n spot="${1:-}" ex="${2:-NOSUCHSERIAL}" dump="${U11B_DUMP:--62030 330 16250}"
  n=$(rl_q "$RL_NPC_FULL")
  lt_h <<EOT >> "$EV/quiet4.txt" 2>&1
[ -n "$spot" ] && stobe-auto teleport Shay $spot </dev/null | head -1
stobe-auto teleport $n Shay </dev/null | head -1
stobe-auto teleport Malzin Shay </dev/null | head -1
stobe-auto stobe_drawn sheathe Shay </dev/null | head -1
for pass in 1 2; do
  stobe-auto chars 400 </dev/null 2>&1 | sed 's/ | /\n/g' | grep -v -E "Shay #|${RL_NPC_FULL%% *} \[|Malzin #|#$ex" | grep -E "#[0-9]+/[0-9]+" | sed -E 's/.*#([0-9]+\/[0-9]+).*/\1/' | sort -u > /tmp/tr-ids4.txt
  while read id; do stobe-auto teleport "#\$id" $dump </dev/null >/dev/null 2>&1; done < /tmp/tr-ids4.txt
done
for nm in Shay $n Malzin; do stobe-auto health "\$nm" 100 </dev/null >/dev/null 2>&1; done
stobe-auto where $n </dev/null | head -1 | cut -c1-140
EOT
}

sffb4_state_combat() {   # sffb4_state_combat <file>: v3 read, then a `false` is overridden to true when a combat eventlog row naming the NPC is fresh
  local f="$EV/$1" sn row ty age maxage="${U11B_COMBAT_AGE:-20}"
  sffb_state_combat "$1"
  grep -q 'in_combat=false' "$f" || return 0
  sn="${RL_NPC_FULL%% \[*}"; sn="${sn//\'/\'\'}"
  row=$(lt_sql "select type||'|'||(extract(epoch from now())::bigint - localts::bigint) from eventlog where type in ('combat','combatend') and lower(data) like lower('%$sn%') order by rowid desc limit 1 /* sffb4:age */" 2>&1 | head -1 | tr -d '\r')
  echo "evt-age $1 [$row]" >> "$EV/combat_probe.txt"
  ty="${row%%|*}"; age="${row#*|}"
  [ "$ty" = combat ] || return 0
  case "$age" in ''|*[!0-9-]*) return 0;; esac
  if [ "$age" -ge -5 ] && [ "$age" -le "$maxage" ]; then
    echo "in_combat=true (source=eventlog; the read said false but the newest combat row naming the NPC is ${age}s old)" > "$f"
  fi
}

sffb4_end_fight() {   # sffb4_end_fight <enemy-quoted> <enemy-serial/idx> <npc-quoted>: unprotect + KO the enemy, poll until in_combat=false. rc 3 + RL_REASON = SETUP-FAIL
  local eq="$1" ens="$2" nq="$3" k tries="${U11B_CALM_TRIES:-8}" esc=0 half ko po
  : > "$EV/calm_poll.txt"; : > "$EV/calm_track.txt"
  if [ "${U11B_END:-ko}" = far ]; then
    echo "end=far (U11B_END=far)" >> "$EV/calm_track.txt"; sffb_old_end "$eq" "$ens" "$nq" || return $?; esc=1
  else
    po=$(printf 'stobe-auto protect %s off </dev/null 2>&1 | head -1 # sffb4:unprotect\n' "$eq" | lt_h 2>&1); echo "$po" > "$EV/unprotect.txt"
    echo "$po" | grep -qi 'protect=off' || { RL_REASON="protect off of the spawned enemy #$ens failed: $(echo "$po" | head -1 | cut -c1-160) (the harness would revive it after the KO; needs: recipe)"; return 3; }
    ko=$(printf 'stobe-auto ko %s 900 </dev/null 2>&1 | head -2 # sffb:ko\n' "$eq" | lt_h 2>&1); echo "$ko" > "$EV/ko.txt"
    echo "$ko" | grep -qi 'knocked out' || { RL_REASON="ko of the spawned enemy #$ens failed: $(echo "$ko" | head -1 | cut -c1-160) (needs: U11B_END=far)"; return 3; }
    echo "end=ko enemy #$ens (protect off first)" >> "$EV/calm_track.txt"
  fi
  half=$(( (tries + 1) / 2 ))
  for k in $(seq 1 "$tries"); do
    rw_sleep "${U11B_CALM_S:-15}"
    sffb_track "$k"
    sffb4_state_combat state_calm.txt; echo "$k $(cat "$EV/state_calm.txt")" >> "$EV/calm_poll.txt"
    grep -q 'in_combat=false' "$EV/state_calm.txt" && break
    if [ "$esc" = 0 ] && [ "$k" -ge "$half" ] && grep -q 'in_combat=true' "$EV/state_calm.txt"; then
      esc=1; echo "$k ESCALATE: still in combat after the KO, old end (enemy to U_FAR + NULL_TASK) once" >> "$EV/calm_track.txt"
      sffb_old_end "$eq" "$ens" "$nq" || return $?
    fi
  done
  return 0
}

sffb4_tick_guard() {   # sffb4_tick_guard <tag> <need-path 0|1>: a tick whose claim path did not run makes the no-claim checks vacuous -> rc 3 (SETUP-FAIL), never a PASS
  local lg="$EV/bored_$1_log.txt"
  if grep -qi 'no_social_scope' "$lg" 2>/dev/null; then
    RL_REASON="tick $1: server log says no_social_scope - the follow-up claim path never ran, the no-claim checks would be vacuous (people without serials?) (needs: recipe, U_BORED_SERIALS=1)"; return 3
  fi
  if ! tail -1 "$EV/bored_people.txt" 2>/dev/null | grep -q '|'; then
    RL_REASON="tick $1: people were sent as plain names (no Name|serial): the claim scope cannot resolve, the no-claim checks would be vacuous (needs: recipe, where Shay / RL_NPC_ID)"; return 3
  fi
  if [ "${2:-0}" = 1 ] && ! grep -qiE 'social_followup_claim|claimed a social remark|situated_remark' "$lg" 2>/dev/null; then
    RL_REASON="tick $1: the server log shows no follow-up claim attempt at all (see bored_$1_log.txt): the no-claim check would be vacuous (needs: recipe, lane backend)"; return 3
  fi
  return 0
}

sffb4_wait_quiet() {   # sffb4_wait_quiet <actor-serial>: wait until no fresh situated_event (< U11B_EVENT_AGE s) and no recent situated_remark_claim (< U11B_CLAIM_COOL s) exist; rc 3 + RL_REASON otherwise
  local ser="$1" k iters=$(( ${U11B_QUIET_MAX_S:-300} / 10 )) needev="${U11B_EVENT_AGE:-125}" needcl="${U11B_CLAIM_COOL:-185}" r ea ek ca
  : > "$EV/quiet_wait.txt"
  [ "$iters" -ge 1 ] || iters=1
  for k in $(seq 1 "$iters"); do
    r=$(lt_sql "select (extract(epoch from now())::bigint - coalesce(max((substring(data from '\"recorded_unix\":([0-9]+)'))::bigint),0))||'|'||coalesce(max(substring(data from '\"kind\":\"([a-z_]+)\"')),'-') from eventlog where type='situated_event' and data like 'situated-v1:$ser:%' /* sffb4:evage */" 2>&1 | head -1 | tr -d '\r')
    ca=$(lt_sql "select extract(epoch from now())::bigint - coalesce(max(localts::bigint),0) from eventlog where type='situated_remark_claim' /* sffb4:claimage */" 2>&1 | head -1 | tr -dc '0-9-')
    ea="${r%%|*}"; ek="${r#*|}"
    echo "$k event_age=$ea kind=$ek claim_age=$ca" >> "$EV/quiet_wait.txt"
    case "$ea" in ''|*[!0-9-]*) ea=0;; esac; case "$ca" in ''|*[!0-9-]*) ca=0;; esac
    [ "$ea" -ge "$needev" ] && [ "$ca" -ge "$needcl" ] && return 0
    [ "$k" = "$iters" ] || rw_sleep 10
  done
  RL_REASON="situated events keep arriving for the NPC (newest ${ea}s old, kind $ek; newest situated_remark_claim ${ca}s old; need >=${needev}s / >=${needcl}s after $iters polls): a third party or the KO'd enemy still produces remarks that win the bored slot before the follow-up (quiet_wait.txt) (needs: recipe, another scene / U11B_DUMP / U11B_QUIET_MAX_S)"
  return 3
}

sffb4_rd11b() {
  local nq o en ens eq mark t_say el tid k max="${SFK_SCENE_MAX:-0}" n spot="${TR_SCENE:-${U11B_SPOT:--48000 1500 2960}}" ser
  TRIP_QUIET=0 tr_prep || return $?                                                              # tr_prep's own tr_quiet would dump strays at -53200 957 4893 (the ready save's spot)
  [ -n "${RL_NPC_ID:-}" ] || rl_resolve >/dev/null 2>&1 || true
  ser="${RL_NPC_ID#\#}"; ser="${ser%%/*}"
  echo "spot=$spot dump=${U11B_DUMP:--62030 330 16250}" > "$EV/scene_cfg.txt"
  unset TR_SCENE; sffb4_quiet "$spot"                                                            # (1) squad to the quiet spot, strays far away
  nq=$(rl_q "$RL_NPC_FULL")
  u_topic "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  t_say=$(date +%s)
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                         # checker: SETUP-FAIL (no topic)
  cp "$EV/fu_pre.txt" "$EV/fu_pre0.txt" 2>/dev/null
  u_heal; sffb4_quiet
  n=1
  for k in 1 2; do
    sfk_scene scene_pre.txt; n=$(cat "$EV/scene_pre.txt.n")
    [ "$n" -le "$max" ] && break
    sffb4_quiet
  done
  [ "$n" -le "$max" ] || { RL_REASON="scene not isolated: $n non-squad characters within ${SFK_SCENE_R:-300} u after 2 quiet passes at $spot ($(head -2 "$EV/scene_pre.txt" | cut -c1-80 | tr '\n' ';')): a third party would join the fight (needs: recipe, another scene / U11B_SPOT / SFK_SCENE_R / SFK_SCENE_MAX)"; return 3; }
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
  sffb4_state_combat state_combat_pre.txt
  tid=$(grep -o '"topic_id":"[^"]*"' "$EV/fu_pre.txt" | head -1 | cut -d'"' -f4)
  [ -n "$tid" ] || { RL_REASON="no topic_id in fu_pre.txt"; return 3; }
  lt_sqlx "update eventlog set data=regexp_replace(data,'\"not_before_gamets\":[0-9]+','\"not_before_gamets\":1') where type='social_followup' and rowid=(select max(rowid) from eventlog where type='social_followup' and data like '%\"topic_id\":\"$tid\"%')" > "$EV/claimable.txt" 2>&1
  rw_fu_dump fu_pre.txt
  grep -q '"not_before_gamets":1[,}]' "$EV/fu_pre.txt" || { RL_REASON="could not make the topic claimable (UPDATE gave: $(head -1 "$EV/claimable.txt" | cut -c1-120)); needs: recipe"; return 3; }
  el=$(( $(date +%s) - t_say )); [ "$el" -ge "${SFK_TICK_GAP_S:-32}" ] || rw_sleep $(( ${SFK_TICK_GAP_S:-32} - el ))
  i4_bored c1b 0 || return $?
  sffb4_tick_guard c1b 1 || return $?
  u_claim_dump claim_c1b.txt "$mark"; rw_fu_dump fu_c1b.txt
  i4_bored c1a 1 || return $?
  sffb4_tick_guard c1a 1 || return $?
  sffb4_state_combat state_combat.txt; u_claim_dump claim_c1a.txt "$mark"; rw_fu_dump fu_combat.txt
  lt_sql "select count(*) from eventlog where type='combat' and rowid>${mark:-0}" > "$EV/combat_rows.txt" 2>&1
  sffb4_end_fight "$eq" "$ens" "$nq" || return $?
  sffb4_quiet "" "$ens"                                                                          # (3) outlaws that walked to the squad during the fight go far again
  sfk_scene scene_calm.txt "$ens"
  [ "$(cat "$EV/scene_calm.txt.n")" -le "$max" ] || { sffb4_quiet "" "$ens"; sfk_scene scene_calm.txt "$ens"; }
  [ "$(cat "$EV/scene_calm.txt.n")" -le "$max" ] || { RL_REASON="third parties near the squad after the fight and 2 clear passes: $(cat "$EV/scene_calm.txt.n") ($(head -2 "$EV/scene_calm.txt" | cut -c1-80 | tr '\n' ';')): their situated threat remarks would win the bored slot (needs: recipe, another scene / U11B_DUMP)"; return 3; }
  u_heal
  sffb4_wait_quiet "$ser" || return $?
  sffb4_state_combat state_calm2.txt
  i4_bored c2 1 || return $?
  sffb4_tick_guard c2 0 || return $?
  u_claim_dump claim_after.txt "$mark"; rw_fu_dump fu_final.txt
}

rd_11b() {   # U_BORED_SERIALS=1 for the whole row (people as Name|serial like the DLL), reset on every exit
  local rc
  U_BORED_SERIALS=1
  sffb4_rd11b; rc=$?
  U_BORED_SERIALS=0
  return $rc
}
