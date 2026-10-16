#!/usr/bin/env bash
# heartbeat.sh: rows double as agent heartbeats. hb_update "<RESULT line>" "<evidence dir>" [next]
# When env KAH_AGENT_NAME is set and that agent's status file says RUNNING, re-run tools/automation/agent-status.ps1 with the same task,
# `latest` = the RESULT line, outputs = the evidence dir (a DONE/FAILED/STOPPED-CONTEXT status is never overwritten).
# KAH_RUNS_DIR (Windows path, same switch as agent-status.ps1) redirects the status dir for selftests. KAH_HB_DRY=1 prints instead of calling.
hb_update() {
  [ -n "${KAH_AGENT_NAME:-}" ] || return 0
  local winruns="${KAH_RUNS_DIR:-C:\\KenshiTestRuns}" runs f st task next res="$1" evd="${2:--}" nx="${3:-}"
  runs=$(echo "$winruns" | sed -E 's#\\#/#g; s#^([A-Za-z]):#/\L\1#')
  [ -d /mnt/c ] && runs="/mnt$runs"   # WSL mounts drives at /mnt/<x>, Git Bash at /<x>; the old fixed /<x> missed the status file in WSL, so a DONE agent was overwritten with "row runs"
  f="$runs/agents/$KAH_AGENT_NAME.status"
  [ -f "$f" ] || { task="row runs"; next="next row"; st=RUNNING; }
  if [ -f "$f" ]; then
    st=$(head -1 "$f" | tr -d '\r\357\273\277' | awk -F' [|] ' '{print $2}')
    task=$(grep -m1 '^task:' "$f" | sed 's/^task: *//' | tr -d '\r'); next=$(grep -m1 '^next:' "$f" | sed 's/^next: *//' | tr -d '\r')
  fi
  [ "$st" = RUNNING ] || return 0
  [ -n "$nx" ] && next="$nx"
  if [ -n "${KAH_HB_DRY:-}" ]; then echo "HB $KAH_AGENT_NAME RUNNING latest=${res:0:200}"; return 0; fi
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\agent-status.ps1' \
    "$KAH_AGENT_NAME" RUNNING "${task:-row runs}" "${res:0:600}" "${evd}" "${next:-next row}" >/dev/null 2>&1
}
