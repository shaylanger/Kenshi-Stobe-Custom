# reloaddefs_sfo.sh (imm26-sfO): sourced AFTER reloaddefs_sfi.sh. Wraps si_offer so that, when RW_INJECT_PROPOSE=Hunt|ClearGroup, the lane is armed
# (inject-propose.sh, one-shot marker) right before the offer say (s1): the NPC's next chat turn then becomes a REAL activity PROPOSE through the
# unchanged product path (see README_RELOAD_SFI.md "Deterministic PROPOSE (imm26-sfO)"). Without RW_INJECT_PROPOSE this is exactly si_offer from sfI.
# The armed turn itself is never the PASS: the row checker still verifies accepted / executor / save+load state afterwards.
# Env: RW_INJECT_PROPOSE (Hunt|ClearGroup)  RW_INJECT_TARGET (optional candidate filter)  RW_INJECT_TTL (default 900)
eval "si_offer_orig () $(declare -f si_offer | tail -n +2)"
si_offer() {   # si_offer <dumpfile>
  if [ -n "${RW_INJECT_PROPOSE:-}" ]; then
    local o rc
    o=$(bash "$RR_HERE/inject-propose.sh" "$LT_LANE" "${ROW_NPC:-any}" "$RW_INJECT_PROPOSE" ${RW_INJECT_TARGET:+"$RW_INJECT_TARGET"} --row "${ROW:-sfo}" --ttl "${RW_INJECT_TTL:-900}" 2>&1); rc=$?
    echo "$o" > "$EV/inject_arm.txt"
    if [ $rc != 0 ]; then RL_REASON="inject-propose arm failed rc=$rc: $(echo "$o" | head -1 | cut -c1-160)"; return 3; fi
  fi
  si_offer_orig "$@"
}
