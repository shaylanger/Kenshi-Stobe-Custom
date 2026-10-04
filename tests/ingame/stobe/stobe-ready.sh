#!/usr/bin/env bash
# stobe-ready.sh: Stobe readiness poll after a load (source it; no traps, no game-state changes, safe for any wrapper).
# stobe-fight-lib.sh sources it; wrappers that don't use the fight lib (e.g. REL rel-m18.sh) source this file directly.
#
# Why: Stobe's NPC world-event sweep (inventory deltas -> item_gain/item_transfer, KO, limb loss) starts only 45 s
# after the LAST "HOOK: world transition detected" (kNpcWorldEventWarmupMs); the log marker for that is
# "HOOK_LOAD_PROBE: heavy sync pipeline complete". A load fires ~3 transitions ~20 s apart, so `wait-world` returns
# long before the sweep runs and events in the first ~1-2 min are only baselined (m22 rel-m18: no item_gain/KO lines).
STOBE_LOG="${STOBE_LOG:-/mnt/d/Steam/steamapps/common/Kenshi/RE_Kenshi/mods/Stobe/stobe.log}"
# stobe_log_lines: current line count of stobe.log (pass it to stobe_ready as the pre-load baseline)
stobe_log_lines() { grep -a -c "" "$STOBE_LOG" 2>/dev/null || echo 0; }
# stobe_ready [secs=150] [base_line=0]: poll every 2 s until the last "heavy sync pipeline complete" comes after the
# last "world transition detected" (and that transition is after base_line, i.e. from this load), then sleep 5
# (one baseline sweep at the 3 s interval). Returns 1 on timeout and sets STOBE_READY_WHY to a specific reason.
stobe_ready() {
  local secs="${1:-150}" base="${2:-0}" t tr pc
  t=$(( $(date +%s) + secs )); STOBE_READY_WHY=""
  while :; do
    tr=$(grep -a -n "HOOK: world transition detected" "$STOBE_LOG" 2>/dev/null | tail -1 | cut -d: -f1)
    pc=$(grep -a -n "HOOK_LOAD_PROBE: heavy sync pipeline complete" "$STOBE_LOG" 2>/dev/null | tail -1 | cut -d: -f1)
    tr=${tr:-0}; pc=${pc:-0}
    if [ "$tr" -gt "$base" ] && [ "$pc" -gt "$tr" ]; then sleep 5; return 0; fi
    if [ "$(date +%s)" -ge "$t" ]; then
      if [ "$tr" -le "$base" ]; then STOBE_READY_WHY="no 'world transition detected' in stobe.log after line $base within ${secs}s (load not seen by Stobe)"
      else STOBE_READY_WHY="no 'heavy sync pipeline complete' after the last world transition (line $tr) within ${secs}s (Stobe NPC event sweep not warm)"; fi
      return 1
    fi
    sleep 2
  done
}
