#!/bin/bash
# coord-waker.sh <out-dir> [seconds=300] (WSL): coordinator waker. Sleeps up to <seconds> (Shay: 5 min max),
# ends early with "KENSHI GONE" if kenshi_x64.exe was running and disappears, then prints the batch-health line.
OUT="$1"; MAX="${2:-300}"; t=0
up(){ tasklist.exe /FI "IMAGENAME eq kenshi_x64.exe" 2>/dev/null | grep -qi kenshi_x64; }
was=0; up && was=1
while [ $t -lt "$MAX" ]; do
  sleep 20; t=$((t+20))
  if up; then was=1; elif [ $was = 1 ]; then sleep 20; up || { echo "KENSHI GONE after ${t}s"; break; }; fi
done
free -g | awk '/Mem:/{printf "WSL mem used=%sG free=%sG ", $3, $4}'
bash /mnt/c/KenshiModding/tools/automation/batch-health.sh "$OUT" | tail -1
