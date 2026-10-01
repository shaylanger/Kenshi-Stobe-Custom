#!/usr/bin/env bash
# Run from Git Bash on this PC: watch a goal id in the status files every 10 s;
# print status changes; pause the game (stobe-say speed 0) on combat or knockout
# toward Shay/Malzin. Exit 0 done/blocked/cancelled, 1 timeout, 2 alert.
# watch3.sh <goal_id> <max_s> : prints status changes; pauses game on combat/knockout toward Shay|Malzin
K=/d/Steam/steamapps/common/Kenshi; S=$K/RE_Kenshi/mods/Stobe; SL=$S/stobe.log
start=$(date +%s); base=$(grep -a -c "" "$SL"); last=""
while :; do
  el=$(( $(date +%s)-start ))
  st=$(cat $S/stobe_work_goal.status $S/stobe_task_goal.status 2>/dev/null | grep -a "^$1" | head -1 | cut -f3- | tr '\t' '|' | cut -c1-180)
  [ "$st" != "$last" ] && echo "[$el s] $st" && last="$st"
  cb=$(tail -n +$base "$SL" | grep -a -E "\[EVENT\] (combat.*-> (Shay|Malzin)|knockout: (Shay|Malzin))" | tail -1)
  if [ -n "$cb" ]; then echo "ALERT: $cb"; wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- stobe-say speed 0; exit 2; fi
  case "$st" in *COMPLETE*|*BLOCKED*|*CANCELLED*|*FAILED*) exit 0;; esac
  [ $el -ge $2 ] && exit 1
  sleep 10
done
