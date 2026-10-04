#!/usr/bin/env bash
# fullbase-guard.sh [row]: Full-Base gets world raids (Band of Bones, Kral's Chosen) that reach the squad mid-test (m17:
# Avarek KO'd and killed during STOBE 16). Protect both squad members and knock out raiders within 400 m.
# Run right after the fixture load (protect is cleared on load). Env PLAYER, MATE.
# m24 fixer 14: then checks the squad is protected and awake (protect revives a KO'd one): SETUP FAIL <row>, exit 4
# otherwise, so callers stop (`bash fullbase-guard.sh <row> || exit $?`) instead of running with a KO'd squad.
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}"
. "$(dirname "$0")/stobe-fight-lib.sh"
row="${1:-fullbase-guard}"
for n in "$PLAYER" "$MATE"; do
  p=$(stobe-auto protect "$n" on 2>&1)
  echo "$p" | grep -q -i -E "error|unknown|not found|no character" && setup_fail "$row" "protect $n failed: ${p:0:120}"
done
log "fullbase-guard: protected $PLAYER + $MATE"
calm_raiders 1500  # m26: 400 m missed the raid that hit Beaks 16 s later (m22 J A8)
awake() { ! stobe-auto where "$1" 2>&1 | grep -q -E " (KO|DEAD)( |$)"; }
for n in "$PLAYER" "$MATE"; do
  wait_for 20 awake "$n" || setup_fail "$row" "$n still KO/DEAD after protect + calm_raiders ($(stobe-auto where "$n" 2>&1 | cut -c1-120))"
done
log "fullbase-guard: $PLAYER + $MATE awake"
