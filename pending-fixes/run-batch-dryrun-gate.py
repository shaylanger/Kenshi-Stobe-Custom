#!/usr/bin/env python3
"""run-batch-dryrun-gate.py <tree root>: run-batch.sh refuses a list that fails tools/automation/dryrun.sh
(Speed plan 1, Shay 2026-10-10); --no-dryrun "<reason>" skips the gate with a NOTE line. Asserts its anchors."""
import io, sys
p = sys.argv[1].rstrip('/') + '/tools/automation/run-batch.sh'
s = io.open(p, newline='').read()
if 'dryrun.sh' in s and 'NODRY' in s:
    print('already applied'); sys.exit(0)
R = [
("""LAUNCH=""; STOP=0; RESUME=0
while [ $# -gt 0 ]; do case "$1" in --launch) LAUNCH="$2"; shift 2 ;; --stop) STOP=1; shift ;; --resume) RESUME=1; shift ;; *) break ;; esac; done
L="${1:?usage: run-batch.sh [--launch <save>] [--stop] [--resume] <list-file> <out-dir>}\"""",
"""LAUNCH=""; STOP=0; RESUME=0; NODRY=""
while [ $# -gt 0 ]; do case "$1" in --launch) LAUNCH="$2"; shift 2 ;; --stop) STOP=1; shift ;; --resume) RESUME=1; shift ;; --no-dryrun) NODRY="${2:?--no-dryrun needs a reason}"; shift 2 ;; *) break ;; esac; done
L="${1:?usage: run-batch.sh [--launch <save>] [--stop] [--resume] [--no-dryrun <reason>] <list-file> <out-dir>}\""""),
("""# restarted first (NOTE line). m22: Kenshi crashed on a NULL texture allocation with the commit charge at its limit.
""",
"""# restarted first (NOTE line). m22: Kenshi crashed on a NULL texture allocation with the commit charge at its limit.
# Dry-run gate (Speed plan 1, Shay 2026-10-10): before the game is touched the whole list runs through
# tools/automation/dryrun.sh (fake game, seconds per row; output <out>/dryrun.txt + <out>/dryrun/); any dry-run FAIL
# refuses the batch (one `RESULT <row> FAIL dryrun: ...` line per failing row + BATCH REFUSED, then DONE).
# --no-dryrun "<reason>" skips the gate (NOTE line with the reason): only for a dry-run bug, logged for take-dryrun.
"""),
("""else : > "$S"; : > "$R"; : > "$D"; say "BATCH START $(date '+%F %H:%M') list=$L"; fi
""",
"""else : > "$S"; : > "$R"; : > "$D"; say "BATCH START $(date '+%F %H:%M') list=$L"; fi
if [ -n "$NODRY" ]; then say "NOTE dryrun gate skipped (--no-dryrun): $NODRY"
else
  DRO=$(bash "$A/dryrun.sh" --out "$O/dryrun" "$L" 2>&1); DRC=$?
  printf '%s\n' "$DRO" > "$O/dryrun.txt"
  say "$(printf '%s\n' "$DRO" | grep '^DRYRUN-SUMMARY' | tail -1 | cut -c1-300)"
  if [ "$DRC" != 0 ]; then
    printf '%s\n' "$DRO" | grep '^DRYRUN [^ ]* FAIL' | while IFS= read -r l; do n=$(awk '{print $2}' <<<"$l"); say "RESULT $n FAIL dryrun: $(cut -c1-400 <<<"${l#DRYRUN $n FAIL }")"; done
    say "BATCH REFUSED $(date '+%F %H:%M'): the list failed tools/automation/dryrun.sh ($O/dryrun.txt); fix the scripts and restart (a dry-run bug: --no-dryrun \\"<reason>\\")"
    finish; exit 1
  fi
fi
"""),
]
for a, b in R:
    assert s.count(a) == 1, 'anchor not found once: ' + a[:60]
    s = s.replace(a, b, 1)
io.open(p, 'w', newline='').write(s)
print('applied')
