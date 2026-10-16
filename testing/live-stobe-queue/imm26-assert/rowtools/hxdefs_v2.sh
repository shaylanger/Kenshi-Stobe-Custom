#!/usr/bin/env bash
# hxdefs_v2.sh (imm26-sfU2): 16-bx v2 scene.  NEW file; hxdefs.sh / hxcheck.py are NOT edited.  Sourced by hxrun_v2.sh AFTER hxdefs*.sh: it REDEFINES rd_16bx (only inside the
# hxrun_v2.sh shell).  Verdict = hxcheck.py (assert_stance 16-bx from the v2 asserter dir), unchanged.
# Why (imm26-sfU finding on the first 16-bx FAIL): the eventlog survives a save load, so stale combat / knockout rows from earlier rows made the "reserved NPC" prompt carry
#   a fight (R1 43 words, scene purge needed).   v2: right after BOTH hxd_dbclean calls (reserved load and outgoing-control load) the combat-type rows are deleted:
#   delete from eventlog where type in ('combat','combat_start','combat_end','knockout','major_damage','limb_loss','recovered')   (output appended to $EV/clean.txt)
# Everything else is a verbatim copy of rd_16bx in hxdefs.sh.

hx16_purge() {  # hx16_purge : stale fight rows out of the eventlog (call right after hxd_dbclean)
  lt_sqlx "delete from eventlog where type in ('combat','combat_start','combat_end','knockout','major_damage','limb_loss','recovered')" >> "$EV/clean.txt" 2>&1
}
rd_16bx() {
  hxd_begin; rd_need_npc || return 3
  local ctl="${HX16_CTL:-Malzin}" cn m0 i g lab d
  local -a gs=("Good to see you again, friend." "It has been a while, how are you?" "Well met. I hoped I would run into you.")
  hxd_load "$HX_SAVE" || return $?; hxd_scene || return $?; hxd_dbclean; hx16_purge; m0=$(hxd_rowid)
  hxd_haff "$EV/pre" cind "$RL_NPC_FULL" 60 platonic
  i=0; for g in "${gs[@]}"; do i=$((i+1)); lab="R$i"; hxd_sample "$lab" "$g" || return $?; cp "$EV/pre/haff-cind.txt" "$HXD/$lab/haff.txt"; done
  hxd_trim "$m0"
  hxd_load "$HX_SAVE2" || return $?; hxd_scene || return $?; hxd_dbclean; hx16_purge; hxd_trim "$m0"
  rl_resolve "$ctl" || { RL_REASON="cannot resolve the control NPC '$ctl' (HX16_CTL)"; return 3; }; cn="$RL_NPC_FULL"; echo "$cn" > "$EV/ctl_npc.txt"
  hx16_outgoing "$cn"; hxd_haff "$EV/pre" ctl "$cn" 0 platonic
  i=0; for g in "${gs[@]}"; do i=$((i+1)); lab="O$i"; d="$HXD/$lab"; mkdir -p "$d"
    : > "$d/inv_before.txt"; hxd_inv "$d/inv_before.txt" "$cn" Shay
    hxd_sample "$lab" "$g" "$cn" || return $?
    : > "$d/inv_after.txt"; hxd_inv "$d/inv_after.txt" "$cn" Shay; cp "$EV/pre/haff-ctl.txt" "$d/haff.txt"
  done
  hxd_trim "$m0"
}
