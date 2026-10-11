#!/bin/bash
# fastswap-bench.sh <mode> <out-dir> (WSL, a run-batch row on the running test game; hotswap2 2026-10-11)
# Times "new build -> game back in the world" on THIS instance ($KAH_INSTANCE, lock owner $KAH_OWNER from the runner):
#   oldlaunch  the pre-2026-10-11 run-batch.sh launch(): stop, kenshi-ctl launch in the background, 3 s polls for the
#              autoload line, sleep 5, kill proxy, sleep 5, postlaunch, stobe-auto wait-world (2 s polls)
#   fast       tools/automation/kfp-fastswap.ps1 -Keep -NoInstall (save the game, kill, relaunch into it, event waits)
#   oldload  the old in-place load (load, sleep 12, wait-world, sleep 10, select)
#   newload  the patched in-place load (load, 0.5 s world polls, select retry)
# Prints exactly one line: RESULT FS-<mode> PASS|FAIL seconds=<s> <detail>
set -u
MODE="${1:?mode}"; OUT="${2:?out}"; mkdir -p "$OUT"
I="${KAH_INSTANCE:-1}"
if [ "$I" -ge 2 ] 2>/dev/null; then KD=/mnt/d/KenshiInst/$I; else KD="/mnt/d/Steam/steamapps/common/Kenshi"; fi
# KAH_DIR: set by the runner lane for instance n (stobe-auto default = instance 1)
CTLW='C:\KenshiModding\tools\automation\kenshi-ctl.ps1'
HLOG=$KD/mods/AutomationHarness/harness.log
ps1() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$@" </dev/null 2>&1 | tr -d '\r'; }
SAVE=$(timeout 15 stobe-auto status 2>/dev/null | grep -o ' save=[^ ]*' | cut -d= -f2); [ -n "$SAVE" ] && [ "$SAVE" != "?" ] || SAVE=kah-fpxbow
wait_world_old() { stobe-auto wait-world "${1:-300}" >/dev/null 2>&1; }
wait_world_new() { local end=$((SECONDS + ${1:-300})); while [ $SECONDS -lt $end ]; do timeout 15 stobe-auto status </dev/null 2>/dev/null | grep -q "phase=world" && return 0; sleep 0.5; done; return 1; }
t0=$(date +%s.%N); el() { awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'; }
case "$MODE" in
  oldlaunch)
    ps1 "$CTLW" stop > "$OUT/stop.out"
    t1=$(date +%s)
    ps1 "$CTLW" launch -Save "$SAVE" > "$OUT/launch.out" &
    for i in $(seq 1 140); do kill -0 $! 2>/dev/null || break
      [ -f "$HLOG" ] && [ "$(stat -c %Y "$HLOG")" -ge "$t1" ] && grep -a -q "KAH: autoload $SAVE" "$HLOG" && { sleep 5; break; }; sleep 3; done
    pkill -f "kenshi-ctl.ps1 launch" 2>/dev/null; wait 2>/dev/null
    sleep 5; ps1 "$CTLW" postlaunch >> "$OUT/launch.out"
    if wait_world_old 300; then echo "RESULT FS-oldlaunch PASS seconds=$(el) save=$SAVE instance=$I (old run-batch launch path, stop..world+placed)"
    else echo "RESULT FS-oldlaunch FAIL seconds=$(el) world not reached (log $OUT/launch.out)"; fi ;;
  fast)
    ps1 'C:\KenshiModding\tools\automation\kfp-fastswap.ps1' -Keep -NoInstall -Instance "$I" > "$OUT/fast.out"
    l=$(grep '^FASTSWAP' "$OUT/fast.out" | tail -1)
    case "$l" in "FASTSWAP OK"*) echo "RESULT FS-fast PASS seconds=$(el) ${l#FASTSWAP OK }" ;;
      *) echo "RESULT FS-fast FAIL seconds=$(el) ${l:-no FASTSWAP line} (log $OUT/fast.out)" ;; esac ;;
  oldload)
    stobe-auto load "$SAVE" >/dev/null 2>&1; sleep 12
    wait_world_old 300 && { sleep 10; stobe-auto select Malzin >/dev/null 2>&1; echo "RESULT FS-oldload PASS seconds=$(el) save=$SAVE"; } \
      || echo "RESULT FS-oldload FAIL seconds=$(el) world not reached" ;;
  newload)
    stobe-auto load "$SAVE" >/dev/null 2>&1
    if wait_world_new 300; then for i in $(seq 1 20); do stobe-auto select Malzin >/dev/null 2>&1 && break; sleep 0.5; done
      echo "RESULT FS-newload PASS seconds=$(el) save=$SAVE"; else echo "RESULT FS-newload FAIL seconds=$(el) world not reached"; fi ;;
  *) echo "RESULT FS-$MODE FAIL setup: unknown mode"; exit 1 ;;
esac
