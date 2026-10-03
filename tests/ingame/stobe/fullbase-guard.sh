#!/usr/bin/env bash
# fullbase-guard.sh: Full-Base gets world raids (Band of Bones, Kral's Chosen) that reach the squad mid-test (m17:
# Avarek KO'd and killed during STOBE 16). Protect both squad members and knock out raiders within 400 m.
# Run right after the fixture load (protect is cleared on load). Env PLAYER, MATE.
export PLAYER="${PLAYER:-Beaks}" MATE="${MATE:-Avarek}"
. "$(dirname "$0")/stobe-fight-lib.sh"
stobe-auto protect "$PLAYER" on >/dev/null; stobe-auto protect "$MATE" on >/dev/null
log "fullbase-guard: protected $PLAYER + $MATE"
calm_raiders 400
