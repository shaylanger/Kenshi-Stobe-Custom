#!/bin/bash
# reloaddefs_sf26e.sh (imm26-sf26e): sourced AFTER reloaddefs_sfi.sh / reloaddefs_sfo.sh by reload-run-sf26e.sh; it REPLACES rd_26e only (nothing else, all older files untouched).
# Needs the sf26e SERVER fix (lane-deploy.sh; no new DLL): after a load the resumed PROPOSED offer is re-displayed on the first ACCEPT-without-consent turn,
# so the player's NEXT Yes carries consent. Row flow: offer / (save+load) / offer again (s2: the NPC proposes again OR re-displays the carried-over offer) / Yes (s3).
# Extra step vs rd_26e: if after s3 the record is still proposed (the s2 turn did not display the offer, so the s3 Yes was the re-display turn), wait for the
# delivery of s3 and say ONE more Yes (step s3b), then re-dump act_post_s3.txt so the unchanged checker (reloadcheck_a.py c_26e) reads the final state.
rd_26e() {   # a PROPOSED Hunt across a save+load (re-bound in place, offer re-displayed, then accepted), on the hunt ground
  local n1 accept="${RW_ACCEPT:-$RW_ACCEPT_DEF}" offer="${RW_OFFER:-$RW_OFFER_DEF}"
  echo Hunt > "$EV/kind.txt"; echo offer > "$EV/mode.txt"
  si_start || return $?
  si_offer act_pre.txt || return $?
  rw_has_status act_pre.txt proposed || return 0                                                  # checker: SETUP-FAIL (no offer)
  rw_out_dump out_pre.txt
  rw_save_load offer || return $?
  n1=$(rw_logn); si_goats post || return $?
  rl_say 2 "$offer" || return $?                                                                 # resume turn: the NPC proposes again / re-displays the carried-over offer
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s2.txt
  si_wait_delivery 2
  rl_say 3 "$accept" || return $?
  rw_sleep "${RW_SAY_WAIT:-8}"
  rw_act_dump act_post_s3.txt
  if ! rw_has_status act_post_s3.txt accepted; then                                               # sf26e: s3 was the re-display turn; one more Yes confirms it
    si_wait_delivery 3
    rl_say 3b "$accept" || return $?
    rw_sleep "${RW_SAY_WAIT:-8}"
    rw_act_dump act_post_s3.txt
  fi
  rw_out_dump out_post.txt; rw_log act_log_post.txt "${n1:-0}"
  return 0
}
