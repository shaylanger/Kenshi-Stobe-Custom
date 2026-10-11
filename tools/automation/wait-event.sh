#!/usr/bin/env bash
# wait-event.sh: WSL/Git Bash wrapper for wait-event.ps1 (ONE blocking process instead of a polling loop; args and exit
# codes as in its header: 0 EVENT, 1 TIMEOUT, 2 PRODUCER GONE, 3 STALE, 4 usage). Paths may be /mnt/c/..., /root/... or C:\...
#   bash tools/automation/wait-event.sh -File /mnt/c/KenshiTestRuns/queue/done/03-twohand.list.SUMMARY.txt -Producer runner-5090 -Timeout 110
#   bash tools/automation/wait-event.sh -Changed /mnt/c/KenshiTestRuns/staged/KenshiFP-latest.txt -Pid wsl:$PIPELINE_PID -Timeout 110
# Git Bash callers: prefix MSYS_NO_PATHCONV=1 when passing /mnt or /root paths.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\KenshiModding\tools\automation\wait-event.ps1' "$@" </dev/null | tr -d '\r'
exit "${PIPESTATUS[0]}"
