#!/usr/bin/env bash
# batch-health.sh <out-dir> [stall-minutes] (WSL): ONE line about a running batch, for the 10-minute check-in
# (Shay, 2026-10-03: don't wait hours on a batch that went wrong). Works for run-batch.sh batches and older
# hand-written ones (it looks at the newest file under <out-dir>).
#   HEALTH DONE  <last SUMMARY line>                      batch finished: read SUMMARY.txt
#   HEALTH OK    file=<newest output> age=<min> phase=world ...
#   HEALTH STALL <reason> file=... age=... phase=...      act now: game not running / not in the world (menu, loading
#                                                         stuck) / no new output for <stall-minutes> (default 20)
# Use it from a background wait so you're woken every 10 min:  sleep 600; bash .../batch-health.sh <out-dir>
set -u
O="${1:?usage: batch-health.sh <out-dir> [stall-minutes]}"; STALL_MIN="${2:-20}"
[ -f "$O/DONE" ] && { echo "HEALTH DONE $(tail -1 "$O/SUMMARY.txt" 2>/dev/null)"; exit 0; }
f=$(find "$O" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1)
if [ -n "$f" ]; then age=$(( ( $(date +%s) - ${f%%.*} ) / 60 )); f="${f#* }"
else age=0; f="(no output yet in $O)"; fi
cur=$(grep -a -E '^[0-9]{2}:[0-9]{2} .*: (prepare|run) ' "$O/batch.log" 2>/dev/null | tail -1 | cut -c1-80)
if ! tasklist.exe </dev/null 2>/dev/null | grep -qi kenshi_x64; then
  echo "HEALTH STALL Kenshi is not running file=$f age=${age}m ${cur:+now=\"$cur\"}"; exit 2
fi
st=$(timeout 30 stobe-auto status </dev/null 2>&1 | tr -d '\r' | head -1)
phase=$(grep -oE 'phase=[a-z]+' <<<"$st"); speed=$(grep -oE 'speed=[0-9.]+' <<<"$st"); paused=$(grep -oE 'paused=[01]' <<<"$st")
why=""
[ -z "$phase" ] && why="harness did not answer ($(cut -c1-60 <<<"$st"))"
[ -n "$phase" ] && [ "$phase" != phase=world ] && why="game is not in the world ($phase)"
[ -z "$why" ] && [ "$age" -ge "$STALL_MIN" ] && why="no new output for ${age}m"
if [ -n "$why" ]; then echo "HEALTH STALL $why file=$f age=${age}m $phase ${cur:+now=\"$cur\"}"; exit 2; fi
echo "HEALTH OK file=$f age=${age}m $phase $speed $paused ${cur:+now=\"$cur\"}"
