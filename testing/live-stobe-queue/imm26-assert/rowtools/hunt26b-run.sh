#!/usr/bin/env bash
# hunt26b-run.sh (imm26-sf26bd): row 26-b on lane 5090-i5 in one command = sfO inject arm + hunt26a-scene.sh (offer + accept, NO cancel inside it) + hunt26b-cancel.sh.
#   bash rowtools/hunt26b-run.sh [outdir]       (Malzin [Nameless] + 5 pinned goats; the Hunt proposal TTL is ~90 real s, so no manual steps between the parts)
# hunt26a-scene.sh itself is unchanged (operators run it); the cancel step that used to be CANCEL_AFTER/CANCEL_TEXT inside it is replaced by hunt26b-cancel.sh.
HR_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-/c/KenshiTestRuns/imm26-5090-i5/26b/run-sf26bd-$(date +%H%M%S)}"; mkdir -p "$OUT"
LANE=5090-i5; export ROW_NPC="${ROW_NPC:-Malzin}"
. "$HR_HERE/../go-row.sh"; lt_load "$LANE" >/dev/null || { echo "HUNT26B-RUN SETUP-FAIL unknown lane"; exit 2; }
EV="$OUT"; rl_resolve "$ROW_NPC" >/dev/null 2>&1 || { echo "HUNT26B-RUN SETUP-FAIL cannot resolve $ROW_NPC"; exit 2; }
arm=$(bash "$HR_HERE/inject-propose.sh" "$LANE" "$ROW_NPC" Hunt --row 26-b --ttl 900 2>&1) || { echo "HUNT26B-RUN SETUP-FAIL inject arm failed: $(echo "$arm" | head -1 | cut -c1-160)"; exit 2; }
echo "$arm" > "$OUT/inject_arm.txt"
NPC_ID="$RL_NPC_ID" NPC_FULL="$RL_NPC_FULL" REFACTION=0 APOLOGY=0 bash "$HR_HERE/hunt26a-scene.sh" "$OUT" > "$OUT/scene.out" 2>&1
grep -q 'SCENE-OK' "$OUT/log.txt" 2>/dev/null || { echo "HUNT26B-RUN SETUP-FAIL scene not ok: $(grep -a 'SCENE-BAD' "$OUT/log.txt" | head -1 | cut -c1-160) [evidence=$OUT]"; exit 2; }
exec bash "$HR_HERE/hunt26b-cancel.sh" "$LANE" --wait "${CANCEL_AFTER:-12}"
