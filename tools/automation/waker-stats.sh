#!/usr/bin/env bash
# waker-stats.sh [hours=24] : coordinator wake cost from the event-wait.sh logs (KAH_RUNS, default /mnt/c/KenshiTestRuns).
#   waker-wakes.log       one line per real wake        (epoch TAB iso TAB kind TAB text)
#   waker-suppressed.log  one line per suppressed event (same format; kinds DONE DUP HAS-SUCCESSOR SETUP-FAIL-READY INFO STALL-SUPPRESSED)
# Prints wakes/hour and suppressed/hour over the window plus a count per kind.
H=${1:-24}; R=${KAH_RUNS:-/mnt/c/KenshiTestRuns}; now=$(date +%s); cut=$(( now - H * 3600 ))
for f in waker-wakes waker-suppressed; do
  p="$R/$f.log"
  if [ ! -f "$p" ]; then echo "$f: no log yet"; continue; fi
  awk -F'\t' -v c="$cut" -v h="$H" -v n="$now" -v name="$f" '
    $1>=c { k[$3]++; t++; if (!first || $1<first) first=$1 }
    END {
      span = (first ? (n-first)/3600 : 0); if (span < 0.0167) span = 0.0167; if (span > h) span = h
      lab = (name=="waker-wakes") ? "wakes/hour" : "suppressed/hour"
      printf "%s: %d in last %dh (log span %.1fh) = %.1f %s\n", name, t, h, span, t/span, lab
      for (x in k) printf "    %-18s %d\n", x, k[x]
    }' "$p"
done
