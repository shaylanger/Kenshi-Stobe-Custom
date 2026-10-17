#!/usr/bin/env bash
# swap23a.sh (imm26-fix23acheck): put the 23-a option-A checker live. Run ONLY when no queued/running list or batch uses rowcheck_trip.py / tripdefs.sh
# (check `ps` in WSL and C:\KenshiTestRuns\inflight\). Usage: bash swap23a.sh [--check|--apply]   (default --check: lists what would change)
# Swaps: rowcheck_trip.py <- .candidate23a, tripdefs.sh <- .candidate23a (default rd_23a also sends the s4 follow-up turn), tripscen.py <- .candidate23a, trip-selftest.sh unchanged.
# The new 23-a row runner is unblockrun_23acheck.sh (+ tripdefs_23acheck.sh), which needs no swap. Offline test afterwards: python3 fix23a_selftest.py ; bash trip-selftest.sh
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in rowcheck_trip.py tripdefs.sh tripscen.py; do
  [ -f "$H/$f.candidate23a" ] || continue
  if cmp -s "$H/$f" "$H/$f.candidate23a"; then echo "same   $f"; continue; fi
  if [ "${1:-}" = --apply ]; then cp "$H/$f.candidate23a" "$H/$f" && echo "copied $f"; else echo "would copy $f.candidate23a -> $f"; fi
done
