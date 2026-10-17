#!/usr/bin/env bash
# reloaddefs_sfe.sh (imm26-sfE2): corrected setup recipes for two save+load RESUME rows whose set-A definitions (reloaddefs_a.sh) can never stage their precondition.
# Sourced by reload-run-sfe.sh AFTER go-row.sh and reloaddefs_a.sh, so rd_24c / rd_26f below REPLACE the set-A functions in that shell only; reloaddefs_a.sh,
# reload-run.sh, reloadcheck_a.py, cleargroup14c-scene.sh are untouched (operators may be running them).
#
# rd_24c  (recipe A, SEEDED, resume leg only):
#   Why: the natural 24-b path (region SUGGEST -> exact consent -> stobeAreaGoalResolve route_ready) is unreachable on the lanes: stobeAreaGoalEndpointValid needs a
#   native candidate with spatial.region_name == the region (never forwarded) or a known_place/town anchor the NPC's destination memory ties to the region and that is
#   not her current town; lane candidates are only landmark/building. rd_24c in set A also used utterances ("Let's go toward Vain.") that match
#   stobeRegionPlanExistingStart and go to ordinary travel. So: run the proven ordinary native trip (the 19-a path: "Walk with me to Stumble Inn." / "Yes, let's go." /
#   "Lead the way." until OWNED_TRAVEL accepted=1), then INSERT a clone of the newest travel_agreement row with kind same_route, a recomputed plan_hash and a regional_goal
#   block (seed24c.py; the original plan_hash is recomputed first and must match, proven against 20+ real rows), save+load, "Where were we going?", "I'm right behind you.".
#   The checker (reloadcheck_sfe.py) prints SEEDED in every RESULT line: this proves ONLY that an area-goal-shaped trip resumes after a load (chain, regional_goal kept,
#   one OWNED_TRAVEL, MOVE_CUS_ORDERED, destination). It does NOT prove the natural 24-b chat path: the row stays PARTIAL until recipe B or the native/server region_name fix.
#   Env: RS_REGION (Vain) TR_S1 (propose wording) RW_SAVE_NAME ROW_RESUME_WAIT (8)
# rd_26f  (ClearGroup / camp offer + accept + save/load, one call; composes imm26-sfA NC17 and the 14-c scene fixed by imm26-inv-14e):
#   Needs NC17 (player-faction partner may Start) installed on the lane, lane in/near the Hub with Shay + Cind. rw_prep with TRIP_QUIET=0 (tr_quiet would teleport the
#   bandits away), Cind into the player faction (RW_FACTION, Nameless), Shay + Cind into Rebirth, Holy Sentinel friendly, 4 plain "Dust Bandit"s teleported and pinned AT ONCE on the
#   ground NORTH of the south wall (inv-14e: z -55624, not -55640), Cind must see >= 3 on two polls, offer loop (4 wordings, never "Hunt the 5 bandits." / "Clear the
#   bandit camp."), accept, save+load, re-seat (the SAME bandit serials re-teleported + pinned), "Are we still on that job?".
#   Env: RW_FACTION (Nameless) RW_REFACTION=0 (already in the faction) RW_SENTINEL (id) RW_BANDITS (4) RW_BANDIT_Z (-55624) RW_REBIRTH ("-47333 730 -55600") RW_ACCEPT RW_RESUME_SAY RW_26F_ACCEPT_WAIT (2)
RS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RS_PY="$(command -v python3 || command -v python)"

# ------------------------------------------------------------------ 24-c recipe A
rs_ordinary_trip() {   # propose (+fallback), accept, lead: the rd19_trip path without its save/load; rc 3 + RL_REASON when no trip was proposed
  rl_say 1 "${TR_S1:-Walk with me to Stumble Inn.}" || return $?
  if ! grep -q '"status":"PROPOSED"' "$EV/s1/ev_full.txt" 2>/dev/null; then
    rl_say 1b "Is there a town you need to get to? Lead me there." || return $?
    grep -q '"status":"PROPOSED"' "$EV/s1b/ev_full.txt" 2>/dev/null || { RL_REASON="no trip proposed after two asks (s1/s1b): nothing to accept"; return 3; }
  fi
  rl_say 2 "Yes, let's go." || return $?
  if ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then rl_say 3 "Lead the way." || return $?; fi
  rw_sleep 6
  return 0
}
rs_seed_regional() {   # clone the newest agreement row as an area-goal trip (seed24c.py); evidence: agr_trip.txt seed_py.txt seed.sql seed_row.json seed_insert.txt seeded.txt
  local o
  rd19_dump agr_trip.txt
  o=$("$RS_PY" -I "$RS_HERE/seed24c.py" "$EV/agr_trip.txt" "$EV" --region "${RS_REGION:-Vain}" 2>&1 | tail -1); echo "$o" > "$EV/seed_py.txt"
  case "$o" in SEED-OK*) ;; *) return 0;; esac                                                 # checker: SETUP-FAIL (seed refused, reason in seed_py.txt)
  lt_sqlx "$(cat "$EV/seed.sql")" > "$EV/seed_insert.txt" 2>&1
  grep -q 'INSERT 0 1' "$EV/seed_insert.txt" || return 0                                       # checker: SETUP-FAIL (insert failed)
  echo "SEEDED regional_goal region=${RS_REGION:-Vain} (resume leg only) $o" > "$EV/seeded.txt"
}
rd_24c() {
  tr_prep || return $?; ROW_NATIVE=1
  rs_ordinary_trip || return $?
  grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" "$EV/s3/reply.txt" 2>/dev/null || { rd19_dump agr_pre.txt; return 0; }   # checker: SETUP-FAIL (native trip never started)
  rs_seed_regional
  rd19_dump agr_pre.txt
  [ -s "$EV/seeded.txt" ] || return 0                                                          # checker: SETUP-FAIL (no seed)
  rw_save_load area || return $?
  rl_say 4 "Where were we going?" || return $?
  rw_sleep "${ROW_RESUME_WAIT:-8}"; rd19_state post_s4.txt
  rl_say 5 "I'm right behind you." || return $?
  rw_sleep "${ROW_RESUME_WAIT:-8}"; rd19_state post_s5.txt
  rd19_dump agr_all.txt
}

# ------------------------------------------------------------------ 26-f ClearGroup
rs_sh() { printf '%s\n' "$1" | lt_h 2>&1; }
rs_place_bandits() {   # rs_place_bandits <ids...>: unpin, teleport each next to the camp spot (north of the wall), pin AT ONCE (spawned bandits roam 190-390 u away within 12 s)
  local k=0 b z="${RW_BANDIT_Z:--55624}"
  for b in "$@"; do
    lt_h <<EOT >> "$EV/spawn.txt" 2>&1
stobe-auto pin "$b" off </dev/null | head -1; stobe-auto teleport "$b" $((-47341+4*k)) 725 $z </dev/null | head -1; stobe-auto pin "$b" </dev/null | head -1
EOT
    k=$((k+1))
  done
}
rs_guard() {   # fix26f22b: Shay conscious, healed, protected and selected (and Cind protected) before every say; the 4080-i4 run lost Shay to a KO between say 1 and say 1b
  local c="${RL_NPC_ID:-}"
  lt_h <<EOT >> "$EV/guard.txt" 2>&1
stobe-auto wake Shay </dev/null | head -1; stobe-auto health Shay 100 </dev/null | head -1; stobe-auto protect Shay on </dev/null | head -1
[ -z "$c" ] || stobe-auto protect "$c" on </dev/null | head -1
stobe-auto select Shay </dev/null | head -1
EOT
}
rs_peace() {   # rs_peace <tries>: fix26f22b. The sentinel step in rs_scene_clear ran right after the 58 k-unit teleport, before Rebirth had streamed in (4080-i4: "WARN no Holy Sentinel id found"),
  # so the Holy Nation / Rebirth sentinels stayed hostile to the player faction and joined the bandit fight (13:54 events: Druven/Halna/Vesk/Skoval attack Shay, knockout by Druven's Iron Club).
  # Retry until sentinels are findable, make EVERY sentinel faction found friendly (relation sets that NPC's faction <-> player faction), then guard Shay/Cind.
  local sc="$EV/scene.txt" t ids s n=0
  for t in $(seq 1 "${1:-1}"); do
    ids=$(rs_sh 'stobe-auto chars 150 "Holy Sentinel|!dead" </dev/null | head -10' | grep -oE '#[0-9]+/[0-9]+' | sort -u | head -6)
    [ -n "$ids" ] && break
    echo "peace-wait $t: no Holy Sentinel listed yet" >> "$sc"; rw_sleep 5
  done
  for s in $ids; do n=$((n+1)); echo "peace: $(rs_sh "stobe-auto relation $(rl_q "$s") 100 </dev/null | head -2" | tr '\n' ' ' | cut -c1-200)" >> "$sc"; done
  echo "peace: sentinels made friendly=$n" >> "$sc"
  rs_guard
}
rs_scene_clear() {   # port of cleargroup14c-scene.sh steps 1-6 (any lane); evidence scene.txt (last line SCENE-OK|SCENE-BAD <why>), bandits.txt (ids), spawn.txt
  local sc="$EV/scene.txt" w fo nid sent ids B1 b ok poll sees tot
  local at="${RW_REBIRTH:--47333 730 -55600}" fac="${RW_FACTION:-Nameless}"
  : > "$sc"; : > "$EV/spawn.txt"
  w=$(rs_sh "stobe-auto where $(rl_q "$ROW_NPC") </dev/null 2>&1 | head -1")
  if [ "${RW_REFACTION:-1}" = 1 ] && ! echo "$w" | grep -q "\[$fac\]"; then
    fo=$(rs_sh "stobe-auto faction $(rl_q "$RL_NPC_ID") $fac </dev/null | head -2"); echo "faction: $fo" >> "$sc"; rw_sleep 3
  fi
  rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { echo "SCENE-BAD cannot resolve $ROW_NPC after the faction change" >> "$sc"; return 0; }
  rd_aff 60 friend haff26f
  local c; c="$RL_NPC_ID"
  set -- $at
  lt_h <<EOT >> "$sc" 2>&1
stobe-auto wake "$c" </dev/null | head -1; stobe-auto health "$c" 100 </dev/null | head -1; sleep 2
stobe-auto pin "$c" off </dev/null | head -1; stobe-auto pin Shay off </dev/null | head -1
stobe-auto teleport Shay $1 $2 $3 </dev/null | head -2
stobe-auto teleport "$c" $1 $2 $(( $3 + 6 )) </dev/null | head -2
stobe-auto select Shay </dev/null | head -1
for w in Shay Malzin; do stobe-auto stobe_drawn sheathe \$w </dev/null | head -1; done
EOT
  sent="${RW_SENTINEL:-$(rs_sh 'stobe-auto chars 150 "Holy Sentinel|!dead" </dev/null | head -3' | grep -oE '#[0-9]+/[0-9]+' | head -1)}"
  if [ -n "$sent" ]; then rs_sh "stobe-auto relation $(rl_q "$sent") 100 </dev/null | head -2" >> "$sc"; else echo "WARN no Holy Sentinel id found (set RW_SENTINEL)" >> "$sc"; fi
  lt_h <<EOT > "$EV/spawn.txt" 2>&1
stobe-auto spawn "Dust Bandit" "Dust Bandits" at -47335 725 -55640 count ${RW_BANDITS:-4} </dev/null | head -3
EOT
  ids=$(grep -oE '#[0-9]+/[0-9]+' "$EV/spawn.txt" | grep -v "^$c$" | sort -u | head -8)
  [ -n "$ids" ] || { echo "SCENE-BAD no bandits spawned (see spawn.txt)" >> "$sc"; return 0; }
  echo "$ids" > "$EV/bandits.txt"; B1=$(echo $ids | awk '{print $1}')
  rs_sh "stobe-auto relation $(rl_q "$B1") -100 </dev/null | head -2" >> "$sc"
  rs_place_bandits $ids
  rs_sh "stobe-auto face $(rl_q "$c") $(rl_q "$B1") </dev/null | head -1; sleep 1" >> "$sc"
  # fix26f11b (op15 4080-i4: 58 k-unit teleport, the game did not answer for 2 x 20 s; Cind had NO perception entries yet: entry=0 fov=-1 last_seen=-1 on both polls, which came ~6 s after the
  # spawn; 5090-i5: 3 of 4 seen at poll 1, then all lost 4 s later because Cind's cone was not refreshed). So: (1) wait until the game answers again, (2) poll up to RW_SCENE_POLLS (14) x
  # RW_SCENE_GAP (5 s), re-facing Cind to the first bandit before every poll, (3) a poll counts when >= 3 bandits have sees=1; SCENE-OK after RW_SCENE_NEED (2) counting polls,
  # (4) when NO bandit has a perception entry (fov=-1) every 4th poll the bandits are re-placed and Cind re-seated at the camp spot (settle kick).
  local i0 pl need="${RW_SCENE_NEED:-2}" npoll="${RW_SCENE_POLLS:-14}" gap="${RW_SCENE_GAP:-5}" blind
  for i0 in $(seq 1 "${RW_SCENE_READY_TRIES:-12}"); do
    fo=$(rs_sh "stobe-auto where Shay </dev/null | head -1"); echo "$fo" | grep -q 'pos=' && break
    echo "ready-wait $i0: $(echo "$fo" | head -1 | cut -c1-100)" >> "$sc"; rw_sleep 5
  done
  rw_sleep "${RW_SCENE_SETTLE:-6}"
  rs_peace "${RW_PEACE_TRIES:-6}"
  tot=$(echo $ids | wc -w); ok=0
  for pl in $(seq 1 "$npoll"); do
    rs_sh "stobe-auto face $(rl_q "$c") $(rl_q "$B1") </dev/null | head -1; sleep 1" >> "$sc"
    sees=0; blind=0
    for b in $ids; do
      fo=$(rs_sh "stobe-auto senses $(rl_q "$c") $(rl_q "$b") </dev/null | head -2"); echo "senses $b: $fo" >> "$sc"
      echo "$fo" | grep -qE 'sees=1' && sees=$((sees+1))
      echo "$fo" | grep -qE 'fov=-1\.0|entry=0 ' && blind=$((blind+1))
    done
    echo "poll $pl senses sees=1 count=$sees of $tot blind=$blind" >> "$sc"
    if [ "$sees" -ge 3 ]; then ok=$((ok+1)); [ "$ok" -ge "$need" ] && break; fi
    if [ "$blind" -ge "$tot" ] && [ $((pl % 4)) -eq 0 ]; then
      echo "settle-kick at poll $pl (no perception entries)" >> "$sc"; set -- $at
      rs_sh "stobe-auto teleport $(rl_q "$c") $1 $2 $(( $3 + 6 )) </dev/null | head -1" >> "$sc"; rs_place_bandits $ids
    fi
    rw_sleep "$gap"
  done
  if [ "$ok" -ge "$need" ]; then echo "SCENE-OK" >> "$sc"; else echo "SCENE-BAD cind does not stably see >= 3 bandits (counting polls ok=$ok of $need needed in $pl polls; see senses lines above)" >> "$sc"; fi
  return 0
}
rs_probe26f() {   # fix26fcamp: after the load + reseat, record whether the bandit scene survived (4080-i4 18:50: 3 of 4 serials gone and the hostility not logged). Evidence appended to reseat.txt;
  # the LAST line is RESEAT-OK or SCENE-LOST (checker reloadcheck_sfe.py: SETUP-FAIL, never a product FAIL). Re-applying relation -100 also logs the before-value:
  # "-100.0 -> -100.0 enemy=1->1" = the game kept the hostility, "-10.0 -> -100.0 enemy=0->1" = the load dropped it (now restored, as a real camp would be).
  local s id want=0 alive=0 chars first=""
  chars=$(rs_sh 'stobe-auto chars 600 "Dust Bandit|!dead" </dev/null | head -3')
  echo "probe chars600: $(echo "$chars" | tr '\n' ' ' | cut -c1-500)" >> "$EV/reseat.txt"
  for s in $(sed -E 's/^#([0-9]+)\/[0-9]+$/\1/' "$EV/bandits.txt" 2>/dev/null); do
    want=$((want+1)); id=$(echo "$chars" | grep -oE "#$s/[0-9]+" | head -1)
    if [ -n "$id" ]; then
      alive=$((alive+1)); [ -n "$first" ] || first="$id"
      echo "probe where $id: $(rs_sh "stobe-auto where $(rl_q "$id") </dev/null | head -1" | tr '\n' ' ' | cut -c1-200)" >> "$EV/reseat.txt"
    else
      echo "probe where #$s: not alive within 600 u after the load" >> "$EV/reseat.txt"
    fi
  done
  [ -z "$first" ] || echo "probe relation $first -100: $(rs_sh "stobe-auto relation $(rl_q "$first") -100 </dev/null | head -2" | tr '\n' ' ' | cut -c1-200)" >> "$EV/reseat.txt"
  if [ "$want" -gt 0 ] && [ "$alive" -ge "$want" ]; then echo "RESEAT-OK $alive of $want agreed bandits alive within 600 u after the load" >> "$EV/reseat.txt"
  else echo "SCENE-LOST only $alive of $want agreed bandits are alive within 600 u after the load (the exact agreedTargets cannot match: scene, not product)" >> "$EV/reseat.txt"; fi
}
rs_reseat26f() {   # after the load: Shay + Cind back at the camp spot, the SAME bandits (by serial) re-teleported + pinned
  local at="${RW_REBIRTH:--47333 730 -55600}" c chars ids s id
  rl_resolve "$ROW_NPC" >/dev/null 2>&1; c="$RL_NPC_ID"; set -- $at
  lt_h <<EOT >> "$EV/reseat.txt" 2>&1
stobe-auto teleport Shay $1 $2 $3 </dev/null | head -1
stobe-auto teleport "$c" $1 $2 $(( $3 + 6 )) </dev/null | head -1
EOT
  chars=$(rs_sh 'stobe-auto chars 300 "Dust Bandit|!dead" </dev/null | head -3'); echo "$chars" | cut -c1-600 >> "$EV/reseat.txt"
  ids=""
  for s in $(sed -E 's/^#([0-9]+)\/[0-9]+$/\1/' "$EV/bandits.txt" 2>/dev/null); do
    id=$(echo "$chars" | grep -oE "#$s/[0-9]+" | head -1); [ -n "$id" ] && ids="$ids $id"
  done
  echo "reseat bandits:$ids" >> "$EV/reseat.txt"
  [ -z "$ids" ] || { rs_place_bandits $ids; rs_sh "stobe-auto face $(rl_q "$c") $(rl_q "$(echo $ids | awk '{print $1}')") </dev/null | head -1; sleep 1" >> "$EV/reseat.txt"; }
  rs_probe26f
}
rs_proposed_clear() {   # act_s*.txt holds a proposed ClearGroup record
  awk -F'|' '$6=="proposed" && $7=="ClearGroup"{f=1} END{exit !f}' "$EV/$1" 2>/dev/null
}
rs_inject_arm() {   # fix26f2: arm the sfO one-shot ClearGroup PROPOSE seam (inject-propose.sh) right before the offer say; RW_INJECT_PROPOSE=0 = model-only offer (old behaviour)
  # Why (4080-i4 op16 evidence rows/26-f s1..s1d): the native candidate IS there (s1 prompt: kind ClearGroup, campZone Rebirth, agreedTargets 4, activityPermitted true) but Cind is already in
  # melee with Gannor (prompt: combat.in_combat=true, "Attack Target: Gannor") and the MODEL answers "Busy - Gannor's on me" with activity_decision NONE in s1/s1b/s1c. The seam replaces ONLY that
  # model choice with a PROPOSE built from the same turn's native candidate and runs it through the unchanged product path; accept ("Yes"), the native scope check, save+load and resume stay real.
  # fix26f4 (4080-i4 op17, stobeserver.log 22:27:20): with the seam the PROPOSE reached ActivityChat.php:104 and was rejected 'Activity availability rejected' (npc_availability.php reason in_combat: Cind is fighting the
  # very group she is asked to clear; the same gate re-checks at ACCEPT). --bypass-availability opens ONLY that gate for the armed NPC on this isolated lane (PROPOSE turn + the player's Yes, phase-2 marker); the
  # consent evidence, grounding and native scope check stay real. Opt out: RW_INJECT_BYPASS=0. Evidence: inject_arm.txt (bypass_availability=1), inject_status.txt, inject_end.txt, server log 'availability bypassed'.
  [ "${RW_INJECT_PROPOSE:-ClearGroup}" = 0 ] && { echo "inject disabled (RW_INJECT_PROPOSE=0)" > "$EV/inject_arm.txt"; return 0; }
  local o rc
  o=$(bash "$RS_HERE/inject-propose.sh" "$LT_LANE" "${ROW_NPC:-any}" ClearGroup ${RW_INJECT_TARGET:+"$RW_INJECT_TARGET"} --row "${ROW:-26-f}" --ttl "${RW_INJECT_TTL:-900}" $([ "${RW_INJECT_BYPASS:-1}" = 0 ] || echo --bypass-availability) 2>&1); rc=$?
  echo "$o" > "$EV/inject_arm.txt"
  if [ $rc != 0 ]; then
    RL_REASON="inject-propose arm failed rc=$rc: $(echo "$o" | head -1 | cut -c1-160)$([ $rc = 4 ] && echo ' (deploy the seam: bash rowtools/inject-propose-deploy.sh '"$LT_LANE"')')"; return 3
  fi
  return 0
}
rs_inject_done() {   # fix26f2: after the offer loop: keep the seam evidence (marker/FIRED files/newest records), then remove an unused one-shot marker so it cannot fire on the accept/resume turns
  [ "${RW_INJECT_PROPOSE:-ClearGroup}" = 0 ] && return 0
  bash "$RS_HERE/inject-propose.sh" "$LT_LANE" --status > "$EV/inject_status.txt" 2>&1
  bash "$RS_HERE/inject-propose.sh" "$LT_LANE" --disarm >> "$EV/inject_status.txt" 2>&1
  return 0
}
rs_inject_end() {   # fix26f4: after the whole row (every exit path of rd_26f): remove the phase-2 accept marker too; evidence inject_end.txt (marker/fired/done files + the seam's own log lines)
  [ "${RW_INJECT_PROPOSE:-ClearGroup}" = 0 ] && return 0
  bash "$RS_HERE/inject-propose.sh" "$LT_LANE" --status > "$EV/inject_end.txt" 2>&1
  bash "$RS_HERE/inject-propose.sh" "$LT_LANE" --disarm-all >> "$EV/inject_end.txt" 2>&1
  return 0
}
rs_wait_delivery() {   # rs_wait_delivery <step>: fix26f2. copy of reloaddefs_sfi.sh si_wait_delivery (the proven Hunt-row accept timing): wait for the offer speech of say step s<step> to be delivered (RECHAT_TIMING follow-up), then the accept delay. Evidence delivery_<step>.txt
  local l; l=$(sed -nE 's/^mark=[0-9]+ [0-9]+ ([0-9]+) .*/\1/p' "$EV/s$1/meta.txt" 2>/dev/null | head -1); l=${l:-0}
  lt_h <<EOT > "$EV/delivery_$1.txt" 2>&1
L=$(rl_q "$LT_STOBELOG"); end=\$((SECONDS+${RW_DELIVERY_WAIT:-40}))
while [ \$SECONDS -lt \$end ]; do tail -n +$((l+1)) "\$L" | grep -qE "RECHAT_TIMING: follow-up (dispatch scheduled|suppressed)" && break; sleep 0.5; done
echo "DELIVERY_CONFIRMED \$(tail -n +$((l+1)) "\$L" | grep -E "RECHAT_TIMING: follow-up" | head -1 | cut -c1-120)"
EOT
  rw_sleep "${RW_ACCEPT_DELAY:-1}"
}
rs_resumed_ok() {   # rs_resumed_ok <actdump> <old id>: old record superseded AND a continuation (resume.of = old) accepted|completed with resume.state resumed (copy of sa_resumed_ok, fix26ad)
  awk -F'|' -v o="$2" '$1==o && $6=="superseded"{s=1} $11==o && $1!=o && ($6=="accepted"||$6=="completed") && $10=="resumed"{c=1} END{exit !(s&&c)}' "$EV/$1" 2>/dev/null
}
rs_poll_resume() {   # fix26f2: copy of sa_poll_resume (fix26ad): the continuation appears LATER than a dump right after the s3 say; poll act_post.txt (final dump) until resumed or RW_RESUME_POLL s; the checker still judges the final dump (never-resumes = FAIL)
  local old t=0 max="${RW_RESUME_POLL:-150}" step="${RW_RESUME_POLL_STEP:-10}" ok=0
  old=$(awk -F'|' '$6=="accepted"{id=$1} END{print id}' "$EV/act_pre.txt" 2>/dev/null)
  : > "$EV/resume_poll.txt"; echo "old=$old max=${max}s step=${step}s" >> "$EV/resume_poll.txt"
  while :; do
    rw_act_dump act_post.txt
    if [ -n "$old" ] && rs_resumed_ok act_post.txt "$old"; then ok=1; echo "t=${t}s RESUMED" >> "$EV/resume_poll.txt"; break; fi
    echo "t=${t}s waiting: $(awk -F'|' '{printf "%s:%s/%s ", substr($1,1,17), $6, $10}' "$EV/act_post.txt" 2>/dev/null)" >> "$EV/resume_poll.txt"
    [ "$t" -ge "$max" ] && break
    rw_sleep "$step"; t=$((t+step))
  done
  [ $ok = 1 ] || echo "t=${t}s NOT RESUMED inside the window: the checker judges this final dump (a FAIL)" >> "$EV/resume_poll.txt"
  return 0
}
rs_offer_loop() {   # fix26f2: the four offer wordings; the seam is armed once, right before the first say (after rs_guard). Sets RS_OFFER_STEP to the say step whose dump holds a proposed ClearGroup (empty = none); rc != 0 only for harness failures
  local k=0 step P q
  RS_OFFER_STEP=""
  for P in "Cind, will you help me clear out the bandits you can see in front of us here in Rebirth?"            "Look at those Dust Bandits here in Rebirth. Cind, I want you to clear them out with me."            "Those Dust Bandits are raiding Rebirth and you can see them. Let's clear out that group together."            "Cind, I want you to help me kill the Dust Bandits standing in Rebirth. Just those ones."; do
    case $k in 0) step=1;; 1) step=1b;; 2) step=1c;; *) step=1d;; esac
    rs_guard; [ "$k" = 0 ] && { rs_inject_arm || return $?; }; rl_say "$step" "$P" || return $?
    for q in $(seq 1 "${RW_26F_OFFER_POLLS:-5}"); do rw_sleep 2; rw_act_dump act_s1.txt; rs_proposed_clear act_s1.txt && break; done
    rs_proposed_clear act_s1.txt && { RS_OFFER_STEP=$step; return 0; }
    k=$((k+1)); rw_sleep 8
  done
  return 0
}
rd_26f() {   # fix26f4: wrapper, so the phase-2 marker is removed on EVERY exit path
  local rc; rd_26f_body "$@"; rc=$?; rs_inject_end; return $rc
}
rd_26f_body() {
  local accept rsay n0 n1 a st rc
  # fix26f2: (1) rl_say that returns on Cind's own "(PC)" line (player-faction speaker; the rowlib one only matched "(NPC)" and blocked the full ROW_WAIT=150 s per say, the Hunt proposal TTL ~117 s ran out: sfP),
  # (2) offer through the sfO seam (rs_inject_arm), (3) delivery wait before the accept (as the Hunt rows), (4) accept retried once while the offer is still open, (5) bounded resume poll (fix26ad).
  [ -f "$RS_HERE/reloaddefs_sfp.sh" ] && . "$RS_HERE/reloaddefs_sfp.sh"
  export ROW_SETTLE="${ROW_SETTLE:-1}"
  TRIP_QUIET=0 rw_prep || return $?
  echo ClearGroup > "$EV/kind.txt"; echo run > "$EV/mode.txt"
  accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}"; rsay="${RW_RESUME_SAY:-Are we still on that job?}"
  rs_scene_clear
  tail -1 "$EV/scene.txt" | grep -q '^SCENE-OK' || return 0                                     # checker: SETUP-FAIL (scene not ready, reason in scene.txt)
  n0=$(rw_logn)
  rs_offer_loop; rc=$?
  rs_inject_done                                                                                # always: seam evidence + remove an unused one-shot marker
  [ $rc = 0 ] || return $rc
  rs_proposed_clear act_s1.txt || { rw_log act_log_pre.txt "${n0:-0}"; return 0; }              # checker: SETUP-FAIL (no ClearGroup offer)
  rs_wait_delivery "$RS_OFFER_STEP"
  for a in $(seq 1 "${RW_26F_ACCEPT_TRIES:-2}"); do
    st=2; [ "$a" -gt 1 ] && st=2b
    rs_guard; rl_say "$st" "$accept" || return $?
    rw_sleep "${RW_26F_ACCEPT_WAIT:-2}"
    rw_act_dump act_pre.txt
    rw_has_status act_pre.txt accepted && break
    rs_proposed_clear act_pre.txt || break                                                      # the offer is gone: another "Yes" cannot help
  done
  rw_out_dump out_pre.txt; rw_log act_log_pre.txt "${n0:-0}"
  rw_has_status act_pre.txt accepted || return 0                                                 # checker: SETUP-FAIL (accept did not land: NC17 missing / 26-a)
  tr_state state_pre.txt "$RL_NPC_FULL"
  rw_save_load job || return $?
  n1=$(rw_logn); rs_reseat26f
  rs_guard; rl_say 3 "$rsay" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rs_poll_resume
  rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  tr_state state_post.txt "$RL_NPC_FULL"
  return 0
}
