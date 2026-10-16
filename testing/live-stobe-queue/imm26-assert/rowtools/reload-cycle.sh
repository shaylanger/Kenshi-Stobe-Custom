#!/usr/bin/env bash
# reload-cycle.sh <lane> [save-name] [near|far]   the reusable 'save + load + wait-world' verb for the imm26 lanes (no stobe-auto equivalent exists: stobe-auto has
#   save, load, wait-world separately). Does: record the eventlog max rowid (load_rowid.txt), `stobe-auto save <name>`, `stobe-auto load <name>`, wait for phase=world
#   (20 s + 24 x 5 s), speed 0.5, re-place the NPC (near = teleport to Shay when > 70 u; far = 120 u). Prints ONE line:
#   RELOAD-CYCLE <lane> <save> PASS|FAIL <detail> [evidence=<dir>]    (exit 0 / 2). Default save name kah-imm26-rw-cycle-<lane>.
#   Function form for row scripts: rw_save_load <tag> [near|far] (reloaddefs_a.sh). KAH_ROW_DRY/KAH_ROW_FAKE work as in go-row.sh.
RC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$RC_HERE/../go-row.sh"; . "$RC_HERE/reloaddefs_a.sh"
LANE="${1:-}"; [ -n "$LANE" ] || { echo "usage: reload-cycle.sh <lane: $(lt_lanes)> [save-name] [near|far]" >&2; exit 2; }
lt_load "$LANE" >/dev/null || { echo "RELOAD-CYCLE $LANE - FAIL unknown lane"; exit 2; }
SV="${2:-kah-imm26-rw-cycle-$LANE}"; PLACE="${3:-near}"
if [ -n "${KAH_ROW_DRY:-}" ] && ! declare -F lt_fake >/dev/null; then lt_fake() { gr_default_fake "$@"; }; fi
tr_cfg; rl_begin reload-cycle >/dev/null
st=$(echo 'stobe-auto status </dev/null | head -1' | lt_h 2>&1 | head -1)
echo "$st" | grep -q 'phase=world' || { echo "RELOAD-CYCLE $LANE $SV FAIL not in the world before the save ($st) [evidence=$EV]"; exit 2; }
RL_NPC_ID=""; rd_need_npc >/dev/null || true
if RW_SAVE_NAME="$SV" rw_save_load cycle "$PLACE"; then
  echo "RELOAD-CYCLE $LANE $SV PASS world ok, npc=${RL_NPC_FULL:-?} dist=${RL_DIST:-?} load_rowid=$(cat "$EV/load_rowid.txt") [evidence=$EV]"; exit 0
fi
echo "RELOAD-CYCLE $LANE $SV FAIL ${RL_REASON:-reload failed} [evidence=$EV]"; exit 2
