#!/usr/bin/env bash
# wsl-cpucap.sh loop|status   (WSL root; started by gaming-throttle.ps1 on)
# While /mnt/c/KenshiTestRuns/gaming.on exists (Shay gaming on the 5090, 2026-10-10): every 15 s pin every WSL process
# to vCPUs 0-5 (taskset, all threads) and renice anything below nice 10 to 10, so WSL keeps at most 6 host threads busy;
# every 2 min drop the clean page cache + compact so vmmem returns RAM. When the flag is gone: all vCPUs back, exit.
# Single instance (flock). Nice values are not raised back on exit (lab jobs keep their own nice 15).
FLAG=/mnt/c/KenshiTestRuns/gaming.on; CPUS=0-5; ALL=0-$(( $(nproc --all) - 1 ))
pin() { for p in /proc/[0-9]*; do p=${p#/proc/}; [ "$p" = 1 ] && continue; taskset -a -cp "$1" "$p" >/dev/null 2>&1; done; }
case "${1:-status}" in
  loop)
    exec >/tmp/wsl-cpucap.log 2>&1 </dev/null
    exec 9>/tmp/wsl-cpucap.lock; flock -n 9 || exit 0
    n=0
    while [ -f "$FLAG" ]; do
      pin "$CPUS"
      for p in $(ps -eo pid=,ni= | awk '$2!="-" && $2<10 && $1>1 {print $1}'); do renice -n 10 -p "$p" >/dev/null 2>&1; done
      if [ $((n % 8)) -eq 0 ]; then sync; echo 1 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory 2>/dev/null; fi
      n=$((n+1)); sleep 15
    done
    pin "$ALL" ;;
  status) [ -f "$FLAG" ] && echo "gaming flag on" || echo "gaming flag off"; pgrep -f "wsl-cpucap.sh loop" >/dev/null && echo "loop running" || echo "loop not running"; taskset -cp $$ ;;
esac
