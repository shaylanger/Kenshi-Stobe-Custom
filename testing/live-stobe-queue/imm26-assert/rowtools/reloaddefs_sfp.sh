# reloaddefs_sfp.sh (imm26-sfP/sfP2): sourced AFTER reloaddefs_sfo.sh (or reloaddefs_sfi.sh). Redefines rl_say (copy of rowlib.sh rl_say) with ONE change: the reply wait accepts a
# non-Shay speaker line ending "(NPC)" OR "(PC)". Reason: with --faction Nameless the NPC (Cind) becomes type=player and logs "ACTION_EXEC: SAY [Cind]: ... (PC)"; the original wait
# only matched "(NPC)" and blocked the full ROW_WAIT (150 s) per say, so the Hunt proposal (TTL ~117 s real) was already expired at the dump (row 26-dx SETUP-FAIL, sfP analysis).
# Everything else is identical to rowlib.sh rl_say (rowlib.sh itself is never edited). Traders Guild (NPC) behaviour is unchanged.
rl_say() {  # rl_say <N> "text" [wait_s]  -> s<N>/ bundle. rc 3 = SETUP-FAIL, rc 4 = GATED (reason in RL_REASON)
  local n="$1" text="$2" wait_s="${3:-${ROW_WAIT:-150}}" d="$EV/s$1" mk tq tgt rc
  [ -n "${RL_NPC_ID:-}" ] || rl_resolve || { RL_REASON="cannot resolve ${ROW_NPC:-Cind} (stobe-auto where)"; return 3; }
  tgt="$RL_NPC_ID"; mkdir -p "$d"
  if [ -n "${ROW_NATIVE:-}" ]; then rl_push; rc=$?; [ $rc = 0 ] || return $rc; fi
  rl_prep_player || { RL_REASON="Shay not conscious/selected (replies would come from another character)"; return 3; }
  mk=$(rl_mark); tq=$(rl_q "$text")
  lt_h <<EOT > "$d/say.txt" 2>&1
L=$(rl_q "$LT_STOBELOG"); n0=\$(wc -l < "\$L")
stobe-auto stobe_say "$tgt" $tq </dev/null 2>&1 | head -2
end=\$((SECONDS+$wait_s))
while [ \$SECONDS -lt \$end ]; do sleep 2; tail -n +\$((n0+1)) "\$L" | grep -E "ACTION_EXEC: SAY \[[^]]*\](.*)\((NPC|PC)\)" | grep -qv "SAY \[Shay\]" && { sleep 3; break; }; done
EOT
  [ -n "${KAH_ROW_FAKE:-}" ] || sleep "${ROW_SETTLE:-3}"
  rl_bundle "$d" "$mk"; echo "say: $text" >> "$d/meta.txt"; echo "$text" > "$d/utterance.txt"
  [ -n "${KAH_ROW_FAKE:-}" ] && return 0
  grep -q 'resolved_speaker=Shay' "$d/reply.txt" || { RL_REASON="resolved_speaker is not Shay in s$n (see $d/reply.txt)"; return 3; }
  grep -qE 'ACTION_EXEC: SAY \[' "$d/reply.txt" || { RL_REASON="no NPC reply within ${wait_s}s in s$n (see $d/reply.txt)"; return 3; }
  return 0
}
