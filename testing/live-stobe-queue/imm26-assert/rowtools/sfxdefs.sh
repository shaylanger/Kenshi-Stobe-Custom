#!/usr/bin/env bash
# sfxdefs.sh: row 12-d v2 (imm26-sfX).  NEW file; rowdefs.sh / rowcheck.py / rowlib.sh / go-row.sh are NOT edited.  Sourced by sfxrun.sh AFTER go-row.sh (which sources rowdefs.sh):
# it REDEFINES rd_12d (only inside the sfxrun.sh shell; the original go-row.sh 12-d path stays as it was).  Verdict: sfxcheck.py via sfx_py (PY shim below).
# Why (imm26-fxC/fxC2 12-d section, agents/out/imm26-fxC/latest.md): the 12-d FAIL on 5090-i3 / 4080-i4 / 5090-i5 was three TEST defects + MODEL-VARIANCE, no product bug:
#   1  contaminated positive control: aff40 ask and aff75 ask ran in the SAME conversation; the s2 prompt carried "Shay, speaking to Cind: Can I have your sword as a gift?" and the
#      NPC's refusal, so the reply was "Still no. Same answer as before".  v2: the chat history made by an ask (eventlog type chat/inputtext, rowid > the pre-ask mark) is purged
#      before every positive-control ask (sfx_purge; waits for the NPC's trailing speech first: sfx_quiet), and any older "Shay: ...sword..." ask is purged at the start.
#      sfxcheck.py also reads each step's prompt.txt: a control that still carries a sword-ask history line is reported as SETUP-FAIL contaminated (not as a refusal).
#   2  wrong reply attribution: s1's third NPC line arrived after the s1 settle and was printed as the s2 reply.  v2: sfx_quiet before the purge/next ask, and sfxcheck.py takes a
#      step's reply only from the lines AFTER that step's own `CHAT_SEND_STAGE: begin`.
#   3  false-positive gate check: the regex `gate|threshold|...` matched gate_relative / "threshold":0.35 / gate=complete.  v2 looks only for the real log line
#      `Blocked low-trust outsider` (chat_helper_functions.php:1635) / `required_affinity`; absent = "gate not exercised" (the model refused in words), reported, not a failure.
#   4  the positive control assumed the LLM volunteers its only weapon (prompt PROPERTY/GEAR RULES tell outsiders not to surrender weapons).  The server weapon floor 70 only BLOCKS a
#      GiveItem below 70; it never produces one (numeric proof: /root/imm26/compose/tests/imm26_wpW_weapon_guard_regression.php W2 blocked at 69, W3 allowed at 70).
#      v2: best-effort control at aff 85, up to SFX_ASKS (3) fresh-context asks with persona-compatible wording (s2..s<N+1>), stops at the first transfer.  No transfer after clean asks =
#      `RESULT 12-d GATED SERVER-GATE-PASS ... LLM-DECLINED` (rc 3, never a FAIL, never blocks a retry); a transfer at aff40 or a gate block at aff85 is a hard FAIL.
# Steps: s1 = aff40 ask ("Can I have your sword as a gift?", unchanged wording), s2.. = aff85 asks.  Evidence: purge.txt sfx_mark.txt haff-aff40.txt haff-aff85.txt inv_before<k>/after<k>.txt (k = step).
# Env: SFX_ASKS (3)  SFX_NPC2 (run the aff85 controls on this second outsider instead of ROW_NPC; it must carry a weapon and stand within 80 u)  SFX_QUIET_S (9)  SFX_QUIET_MAX (90)  SFX_AFF_CTL (85)
SFX_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sfx_py() {  # $PY shim: go-row.sh calls `$PY rowtools/rowcheck.py <ROW> <ev>`; 12-d goes to sfxcheck.py, everything else (attempts.py, other rows) runs unchanged
  local real; real=$(command -v python3 || command -v python)
  if [ "$#" -ge 3 ] && [[ "$1" == *rowcheck.py ]] && [ "${2#IMM-}" = 12-d ]; then "$real" "$SFX_HERE/sfxcheck.py" "$2" "$3"; return $?; fi
  "$real" "$@"
}
sfx_rowid() { rl_mark | awk '{print $1}'; }   # eventlog max rowid
sfx_quiet() {  # wait until the NPC has stopped speaking: no pending chat rows and the newest chat rowid unchanged for SFX_QUIET_S s (max SFX_QUIET_MAX s); never fails
  [ -n "${KAH_ROW_FAKE:-}" ] && { echo "quiet: skipped (fake)" >> "$EV/purge.txt"; return 0; }
  local q="${SFX_QUIET_S:-9}" mx="${SFX_QUIET_MAX:-90}" t0=$SECONDS last="" same=0 cur pend
  while [ $((SECONDS - t0)) -lt "$mx" ]; do
    cur=$(lt_sql "select coalesce(max(rowid),0) from eventlog where type='chat'" | head -1 | tr -dc 0-9)
    pend=$(lt_sql "select count(*) from eventlog where type='chat' and delivery_state='pending'" | head -1 | tr -dc 0-9)
    if [ "$cur" = "$last" ] && [ "${pend:-0}" = 0 ]; then same=$((same + 3)); else same=0; last="$cur"; fi
    [ "$same" -ge "$q" ] && { echo "quiet: ok after $((SECONDS - t0))s (last chat rowid $cur)" >> "$EV/purge.txt"; return 0; }
    sleep 3
  done
  echo "quiet: TIMEOUT ${mx}s (pending=${pend:-?}); purging anyway" >> "$EV/purge.txt"; return 0
}
sfx_purge() {  # sfx_purge <rowid mark>: drop the chat history made after the mark so the next ask starts a clean conversation
  lt_sqlx "delete from eventlog where type in ('chat','inputtext') and rowid > ${1:-0}" >> "$EV/purge.txt" 2>&1
  local left; left=$(lt_sql "select count(*) from eventlog where type in ('chat','inputtext') and rowid > ${1:-0}" | head -1 | tr -dc 0-9)
  echo "purge: mark=${1:-0} left=${left:-?}" >> "$EV/purge.txt"
}
sfx_shay_items() { grep '^SHAY ' "$EV/inv_$1.txt" 2>/dev/null | grep -o '"name":"[^"]*","count":[0-9]*' | sort; }
sfx_shay_gained() {  # sfx_shay_gained <k>: rc 0 when Shay's item set grew between before<k> and after<k>
  local b a; b=$(sfx_shay_items "before$1"); a=$(sfx_shay_items "after$1")
  [ -n "$(comm -13 <(printf '%s\n' "$b") <(printf '%s\n' "$a"))" ]
}
SFX_TEXTS=("We have been through enough together. Would you give me your sword as a gift? I will keep it safe."
           "Cind, I trust you with my life and I hope you trust me. Please give me your sword."
           "A friend is asking: hand me your sword, I will not let you down.")

rd_12d() {  # aff40 refusal (s1) + best-effort aff85 positive control in a CLEAN conversation (s2..), see the header
  rd_need_npc || return 3
  local asks="${SFX_ASKS:-3}" aff="${SFX_AFF_CTL:-85}" m0 k i txt
  lt_sqlx "delete from eventlog where type in ('chat','inputtext') and data like 'Shay: %sword%'" >> "$EV/purge.txt" 2>&1   # older sword asks of earlier 12-d runs
  m0=$(sfx_rowid); echo "m0=$m0 asks=$asks aff_ctl=$aff npc2=${SFX_NPC2:-none}" > "$EV/sfx_mark.txt"
  rd_aff 40 platonic aff40; rl_inv before1; rl_say 1 "Can I have your sword as a gift?" || return $?; rl_inv after1
  if [ -n "${SFX_NPC2:-}" ]; then RL_NPC_ID=""; rl_resolve "$SFX_NPC2" || { RL_REASON="cannot resolve SFX_NPC2 '$SFX_NPC2' (stobe-auto where)"; return 3; }; fi
  for ((k = 2; k <= asks + 1; k++)); do
    sfx_quiet; sfx_purge "$m0"
    i=$(( (k - 2) % ${#SFX_TEXTS[@]} )); txt="${SFX_TEXTS[$i]}"
    rd_aff "$aff" platonic aff85; rl_inv "before$k"; rl_say "$k" "$txt" || return $?; rl_inv "after$k"
    if sfx_shay_gained "$k"; then echo "transfer at s$k: stop asking" >> "$EV/sfx_mark.txt"; break; fi
  done
  return 0
}
