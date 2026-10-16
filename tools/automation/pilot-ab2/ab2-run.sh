#!/usr/bin/env bash
# ab2-run.sh <haiku|sonnet> <ROW>   the ONE script both pilot-2 arms run for a row (lane 5090-i4). Run it from Git Bash, nothing else is needed.
# Refuses unless (arm,row) is the CURRENT seq of C:/KenshiTestRuns/pilot/ab2/plan.json and no run is in progress, and unless the lane baseline
# (Stobe.dll, server bundle, base saves) and the row's scripts equal the first arm's / the plan's (ab2-state.py begin). Then, identically for both arms:
#   1. scene reset OUTSIDE the timed window: lane-setup.sh 5090 4 kah-imm26-i4 --with Cind (reload base save, squad, teleport, clear outlaws)
#   2. pilot-mark.sh START (shadow ledger C:/KenshiTestRuns/pilot/ab2/<arm>/verdicts.csv; no claims, no TESTS marks)
#   3. the row's one-call command from queue.txt, full output to ab2/<arm>/out/<ROW>.out, only the last 4 lines are printed
#   4. evidence dir copied to ab2/<arm>/evidence/<ROW>; captures.jsonl line (start/end epoch, wall, exit, last RESULT line, DLL/bundle/save baseline)
# Exit: 0 ran (read the RESULT line, then ab2-mark.sh), 5 refused / reset failed (nothing ran, STOP and hand back).
# Env (selftest/tuning): AB2_DIR AB2_RESET_CMD ("" = skip the reset) AB2_ROW_TIMEOUT (s, default 2400) AB2_ASSERT AB2_ROWS_DIR AB2_ALLOW_DRIFT.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
ARM="$1"; ROW="$2"
case "$ARM" in haiku|sonnet) ;; *) echo "usage: ab2-run.sh <haiku|sonnet> <ROW>"; exit 2;; esac
[ -n "$ROW" ] || { echo "usage: ab2-run.sh <haiku|sonnet> <ROW>"; exit 2; }
AB2="${AB2_DIR:-C:/KenshiTestRuns/pilot/ab2}"; export AB2_DIR="$AB2"
RUNS="${KAH_RUNS_DIR:-C:/KenshiTestRuns}"
ASSERT="${AB2_ASSERT:-C:/KenshiModding/testing/live-stobe-queue/imm26-assert}"
ROWS_DIR="${AB2_ROWS_DIR:-$RUNS/imm26-5090-i4/rows}"
REPO="${AB2_REPO:-C:/KenshiModding}"

OUT="$("$PY" -I "$HERE/ab2-state.py" begin "$ARM" "$ROW" 2>&1)"; RC=$?
echo "$OUT" | grep -v '^CMD '
[ $RC = 0 ] || { echo "ab2-run: nothing ran. STOP and hand back to the coordinator (do not retry, do not debug)."; exit 5; }
CMD="$(printf '%s\n' "$OUT" | sed -n 's/^CMD //p' | head -1)"
touch "$AB2/ACTIVE"; mkdir -p "$AB2/$ARM/out" "$AB2/$ARM/evidence" "$AB2/$ARM/bundles"

# 1. identical scene reset, outside the timed window
RESET="${AB2_RESET_CMD-DEFAULT}"
if [ "$RESET" = DEFAULT ]; then
  RESET="bash $REPO/tools/automation/lane-setup.sh 5090 4 kah-imm26-i4 --with Cind"
fi
if [ -n "$RESET" ]; then
  RLOG="$AB2/$ARM/out/$ROW.reset.out"
  ( export KAH_INSTANCE=4 KAH_OWNER=rig5090-imm26-i4 KAH_GFX=low KAH_VIDEO_MODE='1024 x 768' KENSHI_MONITOR='\.\DISPLAY2'; cd "$REPO" && eval "$RESET" ) > "$RLOG" 2>&1
  RRC=$?
  if [ $RRC != 0 ] || ! grep -aq 'RESULT lane-setup.* PASS' "$RLOG"; then
    tail -3 "$RLOG" | cut -c1-300
    "$PY" -I "$HERE/ab2-state.py" abort "$ARM" "$ROW" "scene reset failed rc=$RRC ($(tail -1 "$RLOG" | cut -c1-160))" >/dev/null
    echo "ab2-run: scene reset FAILED, the row did not run. STOP and hand back to the coordinator (do not retry, do not debug)."; exit 5
  fi
fi

# stale evidence of an earlier run of this row is moved aside (never deleted)
[ -d "$ROWS_DIR/$ROW" ] && mv "$ROWS_DIR/$ROW" "$ROWS_DIR/$ROW.pre-ab2-$(date +%s)" 2>/dev/null

# 2. shadow START
AGENT="ab2-$ARM-$ROW"
KAH_PILOT_DIR="$AB2/$ARM" PILOT_MODEL="$ARM" KAH_LANE=5090-i4 bash "$HERE/../pilot-mark.sh" "$AGENT" "$ROW" START "" --next "read the RESULT line, then ab2-mark.sh $ARM $ROW" >/dev/null 2>&1

# 3. the row
T0=$(date +%s)
( cd "$ASSERT" && timeout "${AB2_ROW_TIMEOUT:-2400}" bash -c "$CMD" 2>&1 ) | tee "$AB2/$ARM/out/$ROW.out" | tail -4 | cut -c1-600
RC=${PIPESTATUS[0]}

# 4. evidence + capture + advance
[ -d "$ROWS_DIR/$ROW" ] && { rm -rf "$AB2/$ARM/evidence/$ROW"; cp -r "$ROWS_DIR/$ROW" "$AB2/$ARM/evidence/$ROW" 2>/dev/null; }
LAST="$(grep -aE "^[[:space:]]*RESULT[[:space:]]+(IMM-)?$ROW[[:space:]]" "$AB2/$ARM/out/$ROW.out" | tail -1 | sed 's/^[[:space:]]*//' | cut -c1-600)"
"$PY" -I "$HERE/ab2-state.py" end "$ARM" "$ROW" "$RC" "$T0" "$LAST" | cut -c1-300
echo "ab2-run: exit=$RC wall=$(( $(date +%s) - T0 ))s. Next: bash $HERE/ab2-mark.sh $ARM $ROW <PASS|FAIL|ESCALATE> \"<the RESULT line above>\""
exit 0
