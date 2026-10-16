#!/usr/bin/env bash
# status-mark.sh <agent> <ROW> <STATUS> "<evidence>" [--lane LANE] [--next "<next row/step>"] [--task "<task text>"] [--no-commit] [--no-status] [--no-push] [--dry]
# ONE call per finished row instead of three (imm26-ctxfix PROPOSAL F): (1) python mark-row.py ROW STATUS "evidence" --lane LANE (an error such as a bare SETUP-FAIL
# is printed whole and stops everything: nothing is hidden), (2) agent-status.ps1 <agent> RUNNING "<task>" "<ROW> STATUS: evidence" ... (task text = line 2 of
# agents\<agent>.status unless --task: agent-guard rule b), (3) QUIET commit of the TESTS file only: git commit -q -m ... -- <TESTS path> (pathspec, so no status
# dump and no other staged file is touched; skipped when the file is unchanged) + git push -q. Identity shaylanger <shaylanger2@gmail.com> (repo-local, set per call).
# Prints at most 4 short lines: marked / status / commit / push. Exit: 0 ok, mark-row's code if the mark was refused, 5 push failed, 6 status failed (mark+commit still done).
# Env (selftests): KAH_REPO KAH_TESTS_MD KAH_RUNS_DIR. Never commits anything else; never logs, DLLs or evidence.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${KAH_REPO:-$(cd "$HERE/../.." && pwd)}"
PY="$(command -v python3 || command -v python)"
[ $# -ge 4 ] || { sed -n 2,3p "$0" | cut -c1-240; exit 2; }
AGENT="$1"; ROW="$2"; STATUS="$3"; EV="$4"; shift 4
LANE="${KAH_LANE:--}"; NEXT=""; TASK=""; DO_COMMIT=1; DO_STATUS=1; DO_PUSH=1; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --lane) LANE="$2"; shift 2;; --next) NEXT="$2"; shift 2;; --task) TASK="$2"; shift 2;;
  --no-commit) DO_COMMIT=0; shift;; --no-status) DO_STATUS=0; shift;; --no-push) DO_PUSH=0; shift;; --dry) DRY=1; shift;;
  *) echo "status-mark.sh: unknown option $1"; exit 2;; esac; done
ROW="${ROW#IMM-}"
RUNS="${KAH_RUNS_DIR:-}"; if [ -z "$RUNS" ]; then for c in /c/KenshiTestRuns /mnt/c/KenshiTestRuns; do [ -d "$c" ] && RUNS="$c" && break; done; fi
TESTS="${KAH_TESTS_MD:-$REPO/testing/NPC_IMMERSION_26_TESTS.md}"
short() { printf '%s' "$1" | tr '\n\r' '  ' | cut -c1-"$2"; }
if [ "$DRY" = 1 ]; then
  echo "DRY mark-row.py $ROW $STATUS \"$(short "$EV" 80)\" --lane $LANE"; [ $DO_STATUS = 1 ] && echo "DRY agent-status.ps1 $AGENT RUNNING task=${TASK:-<from $AGENT.status line 2>} step=\"$ROW $STATUS\""
  [ $DO_COMMIT = 1 ] && echo "DRY git commit -q -m \"imm26 $AGENT: $ROW $STATUS ...\" -- $TESTS (+ push -q)"; exit 0
fi
# (1) mark
if [ -n "${KAH_MARK_ROW:-}" ]; then MARK=($KAH_MARK_ROW); else MARK=("$PY" "$HERE/mark-row.py"); fi
OUT="$(KAH_TESTS_MD="$TESTS" "${MARK[@]}" "$ROW" "$STATUS" "$EV" --lane "$LANE" 2>&1)"; RC=$?
if [ $RC -ne 0 ]; then echo "$OUT"; echo "status-mark.sh: mark refused/failed (exit $RC); no status update, no commit"; exit $RC; fi
echo "$OUT" | sed -n 1p | cut -c1-200
echo "$OUT" | sed -n '2,$p' | grep -E '^ticket|failed' | cut -c1-240
# (2) status
RCS=0
if [ $DO_STATUS = 1 ]; then
  SF="$RUNS/agents/$AGENT.status"
  if [ -z "$TASK" ]; then [ -f "$SF" ] && TASK="$(sed -n 2p "$SF" | sed 's/^task: \{0,1\}//')"; fi
  if [ -z "$TASK" ]; then echo "status: SKIPPED (no $SF task line; pass --task \"<task>\")"; RCS=6
  else
    PSF="$HERE/agent-status.ps1"; command -v cygpath >/dev/null 2>&1 && PSF="$(cygpath -w "$PSF")"; command -v wslpath >/dev/null 2>&1 && PSF="$(wslpath -w "$PSF")"
    SOUT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSF" "$AGENT" RUNNING "$TASK" "$ROW $STATUS: $(short "$EV" 220)" "$(short "$EV" 160)" "${NEXT:-next-row.sh ${LANE}}" 2>&1)"; RCS=$?
    if [ $RCS -eq 0 ]; then echo "status: $AGENT RUNNING ($ROW $STATUS)"; else echo "status: FAILED: $(short "$SOUT" 300)"; RCS=6; fi
  fi
fi
# (3) quiet commit + push of the TESTS file only
if [ $DO_COMMIT = 1 ]; then
  REL="$(cd "$(dirname "$TESTS")" && pwd -P)/$(basename "$TESTS")"; RP="$(cd "$REPO" && pwd -P)"; REL="${REL#$RP/}"
  if git -C "$REPO" diff --quiet -- "$REL" 2>/dev/null; then echo "commit: nothing to commit (TESTS file unchanged)"
  else
    COUT="$(git -C "$REPO" -c user.name=shaylanger -c user.email=shaylanger2@gmail.com commit -q -m "imm26 $AGENT: $ROW $STATUS $(short "$EV" 110)" -- "$REL" 2>&1)"; CRC=$?
    if [ $CRC -ne 0 ]; then echo "commit: FAILED: $(echo "$COUT" | tail -2 | tr '\n' ' ' | cut -c1-300)"; exit 5; fi
    echo "commit: $(git -C "$REPO" rev-parse --short HEAD)"
    if [ $DO_PUSH = 1 ]; then
      POUT="$(git -C "$REPO" push -q origin HEAD 2>&1)"; PRC=$?
      if [ $PRC -ne 0 ]; then echo "push: FAILED: $(echo "$POUT" | tail -2 | tr '\n' ' ' | cut -c1-300) -> git pull --rebase (stash nothing: other files are dirty) then git push"; exit 5; fi
      echo "push: ok"
    fi
  fi
fi
[ $RCS -ne 0 ] && exit 6
exit 0
