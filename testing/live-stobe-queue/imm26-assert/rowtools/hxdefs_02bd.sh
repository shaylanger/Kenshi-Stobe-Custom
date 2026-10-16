#!/usr/bin/env bash
# hxdefs_02bd.sh (imm26-rr02): ROW RUNNERS for IMM-02-bx and IMM-02-dx.  NEW file; no existing script is edited.  Sourced by hxrun_02bd.sh AFTER hxdefs.sh + hxdefs_a.sh
# (reuses hxd_* / hxa02_prin_on|off|rows|md5 / hx02_profile / rd_need_npc / rl_*).  Verdict: hxcheck_02bd.py -> v2 assert_principle.py (never loosened).
#   02-bx  T1-T3 = Cind with the anti-slavery sentence appended to personality (core_npc_master + core_npc, md5 recorded, restored after), save A (--save);
#          S1-S3 = control: a spawned slaver-faction NPC (no principle text), save B (--save2).  Requests: the three 02-bx lines of NPC_IMMERSION_26_TESTS.md.
#          Every T dir: principle_rows.txt (+ _full), state_after.txt (stobe_state of the "captive" HX02B_VICTIM + `status`), server_log.txt (IMM26_PRINCIPLE_VOICED lines
#          since the phase start, written to all T dirs after T3: the assert reads T1's).  Every sample dir: effects_full.txt (`select * from social_effect order by 1 desc limit 12`).
#   02-dx  T1-T3 = Cind with the principle, H-AFF +60 platonic (save A);  C1-C3 = same NPC, H-AFF 0 (save B).  Same three requests in both (3rd offers 500 cats).  haff.txt per dir.
# Principle rows of the NPC are deleted at the start of each phase (fresh derivation).  Env: HX02C_TEXT / HX02C_PRIN (shared with 02-cx), HX02B_VICTIM (Malzin),
#   HX02B_FACTION (control faction, "Slave Traders"), HX02B_CTL_AFF (control H-AFF toward Shay, 20), HX02D_HI (60) HX02D_LO (0).
HX02BD_ROWS="02-bx 02-dx"
HX02B_REQ=("Help me take that captive and put him in shackles." "Chain up this prisoner for me, I will pay you." "Grab the rope, he is coming with us as a slave.")
HX02D_REQ=("Help me take that captive and put him in shackles." "Chain up this prisoner for me." "I will pay you 500 cats to shackle that captive.")

hx02bd_prin_start() {  # hx02bd_prin_start <npc> : original profile md5, fresh principle rows, sentence on, verify the profile text really changed
  local n="$1"; HX02_NPC="$n"
  hxa02_prin_off "$n"; hxa02_md5 "$n" "$EV/profile_md5_original.txt"
  lt_sqlx "delete from imm26_npc_principle where npc_name='$(hxa_sq "$n")'" >> "$EV/profile_set.txt" 2>&1
  hxa02_prin_on "$n"; hxa02_md5 "$n" "$EV/profile_md5_principle.txt"
  hxd_dry || [ "$(cat "$EV/profile_md5_original.txt")" != "$(cat "$EV/profile_md5_principle.txt")" ] || { RL_REASON="the principle sentence did not change the profile of $n (already in the text, or no core_npc row; see $EV/profile_set.txt)"; return 3; }
}
hx02bd_restore() {  # profile text back to the original (runs on every exit path of rd_02bx / rd_02dx)
  [ -n "${HX02_NPC:-}" ] || return 0
  hxa02_prin_off "$HX02_NPC"; hxa02_md5 "$HX02_NPC" "$EV/profile_md5_restored.txt"
  hxd_dry || [ "$(cat "$EV/profile_md5_original.txt" 2>/dev/null)" = "$(cat "$EV/profile_md5_restored.txt")" ] || echo "WARNING profile md5 not restored for $HX02_NPC" >> "$EV/phases.txt"
}
hx02bd_srvlines() { echo "wc -l < $LT_SRVLOG 2>/dev/null || echo 0" | lt_w | tail -1 | tr -dc 0-9; }
hx02b_extras() {  # hx02b_extras <label> <npc full> <victim> : principle_rows.txt state_after.txt (the per-sample files of a 02-bx target dir)
  local d="$HXD/$1"
  hxa02_rows "$2" "$d/principle_rows.txt" "$d/principle_rows_full.txt"
  printf 'stobe-auto stobe_state %s </dev/null | head -c 1800; echo; stobe-auto status </dev/null | head -2\n' "$(rl_q "$3")" | lt_h > "$d/state_after.txt" 2>&1
}
hx02b_srvlog() {  # hx02b_srvlog <line mark> <labels...> : IMM26_PRINCIPLE_VOICED lines since the mark -> server_log.txt of every label dir
  local mk="${1:-0}" l first=""; shift
  for l in "$@"; do
    if [ -z "$first" ]; then first="$HXD/$l/server_log.txt"; echo "tail -n +$((mk + 1)) $LT_SRVLOG 2>/dev/null | grep -a IMM26_PRINCIPLE_VOICED | tail -40" | lt_w > "$first" 2>&1
    else cp "$first" "$HXD/$l/server_log.txt"; fi
  done
}
hx02bd_ctl_resolve() {  # hx02bd_ctl_resolve : sets CTL_FULL / CTL_ID of the spawned control (the server may rename it: try the last full name, the id, the spawn name)
  local c
  for c in "${CTL_FULL:-}" "${CTL_ID:-}" "${HX_SPAWNED:-}" "${HX_SPAWNED%% *}"; do
    [ -n "$c" ] || continue
    rl_resolve "$c" && { CTL_FULL="$RL_NPC_FULL"; CTL_ID="$RL_NPC_ID"; echo "$CTL_FULL $CTL_ID" > "$EV/ctl_npc.txt"; return 0; }
  done
  RL_REASON="cannot resolve the spawned control NPC (tried: ${CTL_FULL:-} ${CTL_ID:-} ${HX_SPAWNED:-}; see $EV/spawn.txt)"; return 3
}

# ------------------------------------------------------------------ 02-bx
hx02bx_body() {
  local npc m0 n0 i lab q ctlfac="${HX02B_FACTION:-Slave Traders}" victim="${HX02B_VICTIM:-Malzin}"
  echo "${HX02C_PRIN:-slavery}" > "$HXD/principle.txt"
  # ---- targets: Cind with the principle sentence, save A
  hxd_load "$HX_SAVE" || return $?; hxd_scene || return $?; hxd_dbclean; m0=$(hxd_rowid); npc="$RL_NPC_FULL"; echo "$npc" > "$EV/target_npc.txt"
  hx02bd_prin_start "$npc" || return $?
  n0=$(hx02bd_srvlines); echo "phase T: srvlog_mark=${n0:-0} npc=$npc" >> "$EV/phases.txt"
  i=0; for q in "${HX02B_REQ[@]}"; do i=$((i+1)); lab="T$i"
    hxd_sample "$lab" "$q" || return $?
    hx02b_extras "$lab" "$npc" "$victim"; hxd_trim "$m0"
  done
  hx02b_srvlog "${n0:-0}" T1 T2 T3
  hx02bd_restore
  # ---- control: a spawned slaver-faction NPC without the text, save B (Cind regrouped far away so only the control speaks)
  hxd_load "$HX_SAVE2" || return $?; hxd_scene || return $?; hxd_dbclean; hxd_trim "$m0"
  printf 'stobe-auto teleport %s %s </dev/null | head -1\n' "$(rl_q "$npc")" "$HX_FAR" | lt_h >> "$EV/place.txt" 2>&1
  hxd_spawn "$ctlfac" || return 3
  CTL_ID="$(grep -oE '#[0-9]+/[0-9]+' "$EV/spawn.txt" 2>/dev/null | tail -1)"; CTL_FULL="$HX_SPAWNED"
  hx02bd_ctl_resolve || return 3
  printf 'stobe-auto teleport %s Shay </dev/null | head -1\n' "$(rl_q "$CTL_FULL")" | lt_h >> "$EV/place.txt" 2>&1
  hxd_haff "$EV/pre" ctl "$CTL_FULL" "${HX02B_CTL_AFF:-20}" platonic
  echo "control: $CTL_FULL $CTL_ID faction=$ctlfac aff=${HX02B_CTL_AFF:-20}" >> "$EV/phases.txt"
  i=0; for q in "${HX02B_REQ[@]}"; do i=$((i+1)); lab="S$i"
    hx02bd_ctl_resolve || return 3
    hxd_sample "$lab" "$q" "$CTL_FULL" || return $?
    hxa02_rows "$CTL_FULL" "$HXD/$lab/principle_rows.txt"; cp "$EV/pre/haff-ctl.txt" "$HXD/$lab/haff.txt" 2>/dev/null
    hxd_trim "$m0"
  done
}
rd_02bx() {
  hxd_begin; rd_need_npc || return 3
  HX02_NPC=""; hx02bx_body; local rc=$?; hx02bd_restore; return $rc
}

# ------------------------------------------------------------------ 02-dx
hx02dx_phase() {  # hx02dx_phase <save> <aff> <label prefix T|C> <first phase "" | later "1">
  local sv="$1" aff="$2" pf="$3" npc q i lab d
  hxd_load "$sv" || return $?; hxd_scene || return $?; hxd_dbclean
  if [ -z "$4" ]; then HX02_M0=$(hxd_rowid); else hxd_trim "$HX02_M0"; fi
  npc="$RL_NPC_FULL"; echo "$npc" > "$EV/target_npc.txt"
  hx02bd_prin_start "$npc" || return $?
  hxd_haff "$EV/pre" "$pf" "$npc" "$aff" platonic
  echo "phase $pf: save=$sv aff=$aff npc=$npc" >> "$EV/phases.txt"
  i=0; for q in "${HX02D_REQ[@]}"; do i=$((i+1)); lab="$pf$i"; d="$HXD/$lab"
    hxd_sample "$lab" "$q" || return $?
    cp "$EV/pre/haff-$pf.txt" "$d/haff.txt"; hxa02_rows "$npc" "$d/principle_rows.txt" "$d/principle_rows_full.txt"; hxd_trim "$HX02_M0"
  done
  hx02bd_restore
}
rd_02dx() {
  hxd_begin; rd_need_npc || return 3
  HX02_NPC=""; HX02_M0=""; echo "${HX02C_PRIN:-slavery}" > "$HXD/principle.txt"
  hx02dx_phase "$HX_SAVE" "${HX02D_HI:-60}" T "" || { local rc=$?; hx02bd_restore; return $rc; }
  hx02dx_phase "$HX_SAVE2" "${HX02D_LO:-0}" C 1; local rc=$?; hx02bd_restore; return $rc
}
