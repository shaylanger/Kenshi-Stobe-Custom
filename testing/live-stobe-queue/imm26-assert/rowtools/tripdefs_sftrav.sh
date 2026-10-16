#!/usr/bin/env bash
# tripdefs_sftrav.sh (imm26-sfTrav): sourced LAST by reload-run-sftrav.sh (20-d) and unblockrun_sftrav.sh (08-d) (and any new runner that wants it). It REDEFINES tr_trip_setup only inside that
# process; tripdefs.sh / reloaddefs_*.sh / unblockdefs_*.sh and the queued runners are NOT edited. Every row that opens its trip with tr_trip_setup (s1 "Take me to Squin." -> s2 accept) gets a
# DETERMINISTIC travel PROPOSE: the lane is armed (inject-travel.sh, one-shot marker) right before s1, so the NPC's next chat turn becomes a REAL stored PROPOSED travel_agreement through the
# unchanged product path (stobeTravelCapture: policy, availability, destination grounding, plan hash, stobeTravelWrite). The player's "Yes" (s2) still has to be accepted by the product's own
# path, and the row checker is unchanged: the armed turn is never the PASS. Why: 20-d (Cind gave no PROPOSE after 2 asks), 08-d ("requires an existing concrete offer"), 19-e: LLM variance.
# Env: SFT_INJECT (1 = arm, default; 0 = byte-identical to tripdefs.sh)  SFT_TTL (marker seconds, default 600)  SFT_KEEP_TEXT=1 (keep the model's words instead of the offer line)
# Needs the seam on the lane: bash rowtools/inject-travel-deploy.sh <lane> (rerun after every lane-deploy.sh). Missing seam = SETUP-FAIL before s1 naming the deploy command (no wasted turn).
SFT_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sft_arm() {   # arm the lane for the next travel turn of the row NPC
  local o rc npc="${RL_NPC_FULL%% \[*}"
  o=$(bash "$SFT_HERE/inject-travel.sh" "$LT_LANE" "$npc" "${TR_DEST:-Squin}" --row "${ROW:-sftrav}" --ttl "${SFT_TTL:-600}" ${SFT_KEEP_TEXT:+--keep-text} 2>&1); rc=$?
  echo "$o" >> "$EV/inject_arm.txt"
  if [ $rc != 0 ]; then
    RL_REASON="inject-travel arm failed rc=$rc: $(echo "$o" | head -1 | cut -c1-200)"
    return 3
  fi
  return 0
}
sft_disarm() { bash "$SFT_HERE/inject-travel.sh" "$LT_LANE" --disarm >> "$EV/inject_arm.txt" 2>&1; return 0; }   # an unused marker must not fire on a later turn
tr_trip_setup() {  # as tripdefs.sh, plus: s1 is preceded by the one-shot travel PROPOSE arm (SFT_INJECT=1)
  ROW_NATIVE=1
  local inj="${SFT_INJECT:-1}"
  [ "$inj" = 1 ] && { sft_arm || return $?; }
  rl_say 1 "Take me to $TR_DEST." || return $?
  tr_has s1 PROPOSED || { [ "$inj" = 1 ] && { sft_arm || return $?; }; rl_say 1b "Would you lead me to $TR_DEST?" || return $?; }
  [ "$inj" = 1 ] && sft_disarm
  rl_say 2 "${TRIP_ACCEPT:-I'm fine. Yes, let's go.}" || return $?
  if tr_has s2 ACCEPTED && ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then
    rl_say 2b "Lead the way." || return $?
  fi
  tr_agr agr_trip.txt 4
  return 0
}
