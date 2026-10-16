#!/usr/bin/env bash
# reloaddefs_a2.sh: 08-e recipe fix (imm26-sfG2, after the imm26-sfG diagnosis of 4080-i3 op20). Source it right AFTER reloaddefs_a.sh (reload-run-a2.sh does); it only redefines
# rw_08e_cind_ticks and rd_08e. reloaddefs_a.sh / reloadcheck_a.py / reload-run.sh stay untouched (queued lists use them).
# Why: the only "Cind speaker tick" on 4080-i3 was a drawn-weapon REACTION turn (request carries react=drawn_weapon). bored.php never lets a reaction turn claim a follow-up, but the old counter
# counted it, so the checker blamed "the server-side claim gate". Now (a) reaction turns are counted separately (cind_ticks_react.txt) and never as claim-capable ticks (cind_ticks.txt), so a run with
# only reaction ticks ends in the checker's ticks==0 verdict ("NO tick with the NPC as speaker ... needs: recipe"); (b) the scene is re-quieted, the NPC sheathed and held, and the real-time wait after the
# s2 chat is >= 31 s (the 30 s inputtext gate), with 30 s chunks x 16.
# Files: cind_ticks.txt (count: profile=<npc> & mode=autochat|director & no react=), cind_ticks_react.txt (count of react= requests), cind_ticks_log.txt (server-log lines, not the URI).
rw_08e_cind_ticks() {   # rw_08e_cind_ticks <srvlog-line-offset>
  local nm="${RL_NPC_FULL%% *}" off tl; off=$(( ${1:-0} + 1 ))
  printf "tail -n +%s %s 2>/dev/null | grep -a -E 'profile=%s' | grep -a -E 'mode=(autochat|director)' | grep -a -v 'react=' | grep -a -c . # rw:ticks\n" "$off" "$LT_SRVLOG" "$nm" | lt_w | tail -1 | tr -dc 0-9 > "$EV/cind_ticks.txt"
  printf "tail -n +%s %s 2>/dev/null | grep -a -E 'profile=%s' | grep -a -c 'react=' # rw:ticks\n" "$off" "$LT_SRVLOG" "$nm" | lt_w | tail -1 | tr -dc 0-9 > "$EV/cind_ticks_react.txt"
  printf "tail -n +%s %s 2>/dev/null | grep -a -E 'Director bored|Targeted optional|Drawn weapon reaction|nothing claimable|chance gate' | cut -c1-260 | tail -12 # rw:ticks\n" "$off" "$LT_SRVLOG" | lt_w > "$EV/cind_ticks_log.txt" 2>&1
}
rd_08e() {
  # Recipe v2: as rd_08e in reloaddefs_a.sh, but every chunk starts with tr_quiet + sheathe + HOLD_POSITION (strangers wander back; a Hub patrol made Shay draw his Machete and the NPC answered with a
  # reaction turn, which cannot claim), >= 31 s real wait after the s2 chat, RW_ADV 30 x RW_TICK_CHUNKS 16. No targeted i4_bored tick (it returns HTTP 409 after a load).
  local k n0 nq
  rw_prep || return $?
  nq=$(rl_q "$RL_NPC_FULL")
  lt_sql "select coalesce((select value from general_settings where id='BORED_EVENT_CHANCE'),'unset')" > "$EV/bored_chance.txt" 2>&1
  printf 'stobe-auto stobe_drawn sheathe %s </dev/null | head -1\n' "$nq" | lt_h >> "$EV/quiet.txt" 2>&1
  rl_say 1 "${RW_FU_SAY:-I have to mend my armor tomorrow, it is falling apart.}" || return $?
  rw_fu_dump fu_pre.txt
  grep -q '"status":"open"' "$EV/fu_pre.txt" || return 0                                          # checker: SETUP-FAIL (no topic)
  rw_save_load followup near || return $?
  rw_fu_dump fu_post.txt
  n0=$(printf 'wc -l < %s # rw:srvn\n' "$LT_SRVLOG" | lt_w | tail -1 | tr -dc 0-9); echo "${n0:-0}" > "$EV/srvlog_n0.txt"
  nq=$(rl_q "$RL_NPC_FULL"); unset TR_SCENE
  tr_quiet; printf 'stobe-auto stobe_drawn sheathe %s </dev/null | head -1\n' "$nq" | lt_h >> "$EV/quiet.txt" 2>&1
  rl_say 2 "${RW_08E_POST_SAY:-Hello again, I am back.}" || return $?                              # one chat line to the NPC after the load: fresh native snapshot
  rw_sleep "${RW_08E_GATE_WAIT:-31}"                                                              # real-time inputtext gate (30 s) before the first tick may claim
  for k in $(seq 1 "${RW_TICK_CHUNKS:-16}"); do
    unset TR_SCENE; tr_quiet
    printf 'stobe-auto stobe_drawn sheathe %s </dev/null | head -1\nstobe-auto order %s HOLD_POSITION keep </dev/null | head -1\n' "$nq" "$nq" | lt_h >> "$EV/quiet.txt" 2>&1
    ADV_SECONDS="${RW_ADV:-30}" rl_advance_gametime || return $?
    lt_h <<EOT >> "$EV/heal.txt" 2>&1
stobe-auto health Shay 100 </dev/null | head -1
stobe-auto health $nq 100 </dev/null | head -1
EOT
    rw_claim_dump claim.txt
    [ -s "$EV/claim.txt" ] && break
  done
  rw_08e_cind_ticks "${n0:-0}"
  rw_fu_dump fu_final.txt; rw_claim_dump claim.txt
  echo "$k" > "$EV/chunks.txt"
}
