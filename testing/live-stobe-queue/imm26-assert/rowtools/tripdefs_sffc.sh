#!/usr/bin/env bash
# tripdefs_sffc.sh (imm26-sfFixC; tickets 20-a / 19-e): sourced LAST by sfrrun_fc.sh (20-a) and reloadrun-b_fc.sh (19-e). It REDEFINES tr_trip_setup and rd19_trip only inside that process;
# tripdefs.sh / rowdefs.sh / sfrdefs.sh / reloaddefs_b.sh / rowcheck_trip.py and every queued runner are NOT edited.
# Adds to the already-live fix20a19e recipe (tr_faction_guard, tr_prompt_guard, 3 openers, rd_20a quiet spot + ACCEPTED guard):
#  1. s2 retry: when the accept turn produced no ACCEPTED row (5090-i4 20-a 13:53: LLM HTTP error 12002 -> "Empty stream response"), say a clearer accept ONCE in the s2b slot (rowcheck_trip.py STEPS
#     = s1 s1b s2 s2b, so no checker edit). Only runs where the old recipe would already have ended in SETUP-FAIL.
#  2. Deterministic fallback: when s1/s1b/s1c still gave no PROPOSED row (LLM variance: model emits TRAVEL_LOCATION without a concrete offer, 08-d/19-a/19-e/14-a), arm the sfTrav seam
#     (inject-travel.sh, one-shot) and say the first opener once more (step s1d). The offer is still stored by the unchanged product path (stobeTravelCapture); the player's Yes (s2) must still be accepted
#     by the product. SFFC_INJECT=0 disables; no fallback in dry/fake mode; seam missing on the lane = SETUP-FAIL naming inject-travel-deploy.sh (no wasted turn).
#  3. rd19_trip (19-a/19-e/19-f/19-anc2/...) gets the same prompt guard, third opener and fallback as tr_trip_setup (rowdefs.sh rd19_trip has none; its s2/s3 steps are unchanged, reloadcheck_b.py reads s2/s3).
# Env: SFFC_INJECT (1 default | 0)  TRIP_ACCEPT_RETRY (default "Yes, I accept. Please lead the way to <dest>.")  SFT_TTL / SFT_KEEP_TEXT as tripdefs_sftrav.sh.
SFFC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SFFC_HERE/tripdefs_sftrav.sh"   # sft_arm / sft_disarm (its older tr_trip_setup is redefined below)

sffc_have_proposed() { tr_has s1 PROPOSED || tr_has s1b PROPOSED || tr_has s1c PROPOSED || tr_has s1d PROPOSED; }
sffc_propose_fallback() {  # sffc_propose_fallback "<first opener text>"; rc 0 = a PROPOSED row exists, rc 3 = SETUP-FAIL (RL_REASON set)
  local rc=0 why=""
  sffc_have_proposed && return 0
  if [ -n "${KAH_ROW_FAKE:-}" ]; then why="dry/fake mode: no fallback"
  elif [ "${SFFC_INJECT:-1}" != 1 ]; then why="SFFC_INJECT=0"
  elif sft_arm; then
    rl_say 1d "$1"; rc=$?; sft_disarm
    [ $rc = 0 ] || return $rc
    tr_has s1d PROPOSED && return 0
    why="armed fallback turn s1d also stored no PROPOSED row (see $EV/inject_arm.txt, s1d/server.txt)"
  else why="fallback arm failed: ${RL_REASON:-?}"
  fi
  RL_REASON="no PROPOSED travel_agreement row after the asks (s1/s1b/s1c; $why): an accept would be refused ('requires an existing concrete offer'); needs: recipe/server (see s1b/reply.txt)"
  return 3
}
sffc_accept() {  # sffc_accept <dest> <accept text>: s2, one retry in the s2b slot when s2 stored no ACCEPTED row, else the usual 'Lead the way.' when no native start is logged
  rl_say 2 "$2" || return $?
  if ! tr_has s2 ACCEPTED; then
    rl_say 2b "${TRIP_ACCEPT_RETRY:-Yes, I accept. Please lead the way to $1.}" || return $?
  elif ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then
    rl_say 2b "Lead the way." || return $?
  fi
  return 0
}
tr_trip_setup() {  # as tripdefs.sh (fix20a19e) + fallback + s2 retry
  ROW_NATIVE=1
  rl_say 1 "Take me to $TR_DEST." || return $?
  tr_prompt_guard 1 || return $?
  tr_has s1 PROPOSED || { rl_say 1b "Would you lead me to $TR_DEST?" || return $?; }
  tr_has s1 PROPOSED || tr_has s1b PROPOSED || { rl_say 1c "Walk with me to $TR_DEST." || return $?; }
  sffc_propose_fallback "Take me to $TR_DEST." || return $?
  sffc_accept "$TR_DEST" "${TRIP_ACCEPT:-I'm fine. Yes, let's go.}" || return $?
  tr_agr agr_trip.txt 4
  return 0
}
rd19_trip() {  # rowdefs.sh rd19_trip (propose, accept, (lead), save, load, wait for the world) + prompt guard, third opener, deterministic fallback; s2/s3 names unchanged
  ROW_NATIVE=1; rd_need_npc || return 3
  local sv="kah-imm26-19a-$LT_LANE" pre="kah-imm26-19a-pre-$LT_LANE" s1txt
  local TR_DEST="${ROW_19_DEST:-Stumble Inn}"   # sft_arm destination (dynamic scope)
  if [ "${ROW_19A_NC:-1}" = 1 ]; then printf 'stobe-auto save %s </dev/null | head -1\n' "$pre" | lt_h > "$EV/save_pre.txt" 2>&1; fi
  if [ -n "${ROW_19_DEST:-}" ]; then s1txt="Take me to ${ROW_19_DEST}."; else s1txt="${TR_S1:-Walk with me to Stumble Inn.}"; fi
  rl_say 1 "$s1txt" || return $?
  tr_prompt_guard 1 || return $?
  if ! tr_has s1 PROPOSED; then   # the NPC answered 'nowhere in particular' / a canned 'concrete offer' line (LLM-soft): ask again, then the fallback
    rl_say 1b "${ROW_19_DEST:+Would you lead me to $ROW_19_DEST?}${ROW_19_DEST:-Is there a town you need to get to? Lead me there.}" || return $?
    tr_has s1b PROPOSED || { rl_say 1c "Walk with me to $TR_DEST." || return $?; }
    sffc_propose_fallback "$s1txt" || return $?
  fi
  rl_say 2 "Yes, let's go." || return $?
  if ! grep -qE 'OWNED_TRAVEL.*accepted=1' "$EV/s2/reply.txt" 2>/dev/null; then rl_say 3 "Lead the way." || return $?; fi
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
  rd19_dump agr_pre.txt
  lt_sql "select coalesce(max(rowid),0) from eventlog" | head -1 | tr -dc 0-9 > "$EV/load_rowid.txt"
  printf 'stobe-auto save %s </dev/null | head -1\n' "$sv" | lt_h > "$EV/save.txt" 2>&1
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep 6
  rd19_load "$sv"
}
