#!/bin/bash
# lane-waker.sh: the coordinator's waker (Shay 2026-10-11: stuck lanes must be caught in seconds, not by Shay).
# Checks every lane (lane-watch.ps1) every 15 s for up to 120 s; exits AT ONCE printing the LANE STUCK lines when a lane has
# not run a test row for > 90 s, else ends with rig-health.sh's one line. Run from Git Bash: bash tools/automation/lane-waker.sh
# Also wakes at once with "RUNNER NOTE: ..." when runnerqueue-dry.ps1 writes agentsordinator.note-from-runner (queues dry, idle lanes).
lw='C:/KenshiModding/tools/automation/lane-watch.ps1'
note=C:/KenshiTestRuns/agents/coordinator.note-from-runner; seen=C:/KenshiTestRuns/runner/lanewaker.seen
# a new runner note (queues dry, idle lanes; queue-dry.ps1) wakes the coordinator at once too
newnote() { [ -f "$note" ] && { [ ! -f "$seen" ] || [ "$note" -nt "$seen" ]; }; }
for i in 1 2 3 4 5 6 7 8; do
    r=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$lw" 2>&1)
    if [ $? -ne 0 ]; then echo "$r"; exit 1; fi
    if newnote; then touch "$seen"; echo "RUNNER NOTE: $(tail -1 "$note")"; exit 1; fi
    sleep 15
done
echo "$r"
MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/rig-health.sh
