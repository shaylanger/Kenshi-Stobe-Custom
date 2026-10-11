#!/bin/bash
# lane-batches.sh [instance] (WSL): "<pid> <cmdline>" of every run-batch.sh of ONE game lane (default 1 = the main 5090
# game). A lane-2 batch (multi-instance, env KAH_INSTANCE>=2) belongs to lane 5090b: rig-runner's 5090 loop counted it
# as "rig busy with other work" and left the main game idle with 5 lists queued (speed-scout 2026-10-11 14:36).
want=${1:-1}
for p in $(pgrep -f 'run-batch\.sh'); do
  [ -r /proc/$p/cmdline ] || continue
  c=$(tr '\0' ' ' < /proc/$p/cmdline); case "$c" in *run-batch.sh*) ;; *) continue ;; esac
  case "$c" in *pgrep*|*lane-batches*) continue ;; esac
  i=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^KAH_INSTANCE=//p'); i=${i:-1}
  [ "$i" = "$want" ] || { [ "$want" = 1 ] && ! [ "$i" -ge 2 ] 2>/dev/null; } || continue
  echo "$p $c"
done
