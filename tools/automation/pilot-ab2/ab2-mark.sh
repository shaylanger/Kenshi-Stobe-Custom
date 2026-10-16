#!/usr/bin/env bash
# ab2-mark.sh <haiku|sonnet> <ROW> <PASS|FAIL|SETUP-FAIL|GATED|ESCALATE> ["<the RESULT line you read>"]
# Records the operator's verdict for the pilot-2 shadow ledger (C:/KenshiTestRuns/pilot/ab2/<arm>/verdicts.csv) via pilot-mark.sh. Shadow only: no claims,
# no TESTS file, no commits. PASS/FAIL is accepted only if it equals the checker's last `RESULT <ROW> ...` line in ab2/<arm>/out/<ROW>.out;
# SETUP-FAIL / GATED / ESCALATE close the row and notify the coordinator (inbox) - you STOP and hand back.
# Exit (pilot-mark.sh): 0 accepted, 3 refused (your word differs from the checker line; mark exactly what it printed), 4 escalated/closed.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARM="$1"; ROW="$2"; V="$3"; NOTE="$4"
case "$ARM" in haiku|sonnet) ;; *) sed -n 2,2p "$0"; exit 2;; esac
[ -n "$ROW" ] && [ -n "$V" ] || { sed -n 2,2p "$0"; exit 2; }
AB2="${AB2_DIR:-C:/KenshiTestRuns/pilot/ab2}"
EVF="$AB2/$ARM/out/$ROW.out"
[ -f "$EVF" ] || { echo "ab2-mark: no $EVF - ab2-run.sh $ARM $ROW has not run for this arm. Do NOT run the row's script by hand; STOP and hand back."; exit 4; }
export KAH_PILOT_DIR="$AB2/$ARM" PILOT_MODEL="$ARM" KAH_LANE=5090-i4
bash "$HERE/../pilot-mark.sh" "ab2-$ARM-$ROW" "$ROW" "$V" "$NOTE" --evidence-file "$EVF" --next "hand back (final report <= 4 lines)"
RC=$?
case $RC in
  0) echo "ab2-mark: recorded. Now hand back (<= 4 lines) and stop.";;
  3) echo "ab2-mark: refused. Mark exactly the verdict word the checker line printed (or ESCALATE); do NOT rerun the row.";;
  *) echo "ab2-mark: row closed/escalated. Hand back now (<= 4 lines) and stop.";;
esac
exit $RC
