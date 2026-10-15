# Kenshi workspace override for ~/.claude/hooks/context-meter.ps1 (dot-sourced after its config).
# At the limit the hook ORDERS a fixed handoff: HANDOFF.md + agent status files + handoff.ready marker,
# then a fresh session that starts with tools/automation/session-start.ps1. Shay, 2026-10-10.

$WARN_MSG = "Context: {tokens} tokens (handoff at {handoff}). Wrap up the current unit of work; don't start a new batch, build, agent or review round. Make sure testing/HANDOFF.md 'Right now' and every agent's C:\KenshiTestRuns\agents\<name>.status are current."

$HANDOFF_MSG_MAIN = "CONTEXT LIMIT ({tokens}). Do the Kenshi handoff now, in this order, and start NOTHING new (no batch, build, launch or agent): " +
    "(1) finish only the tool step you are in; leave detached batches and rig jobs running, but make sure each has an inflight marker in C:\KenshiTestRuns\inflight\ whose content is its out dir. " +
    "(2) Do NOT message, wait for or stop any agent: independent agent sessions (spawn-wp-session.ps1, env KAH_AGENT_NAME) are separate processes that keep running and report to files and the coordinator inbox; healthy in-session subagents are left alone too. Only update the program ledger (C:\KenshiTestRuns\programs\<name>.json) and list each running agent in testing/HANDOFF.md with its status file, work package and (if stopped) the fresh successor name to spawn (agents\<name>.status 'next' line); the next coordinator picks them up from session-start.ps1. " +
    "(3) Update testing/HANDOFF.md 'Current state' / 'Right now': what is running (batch out dirs, rig jobs, lock owner), each agent and its status file, what was mid-way, next steps. Commit + push it per the repo rules. " +
    "(4) Run: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\handoff-ready.ps1 ""<one-line note>"" (it refuses if HANDOFF.md wasn't just updated). " +
    "(5) Run: powershell -NoProfile -ExecutionPolicy Bypass -File ""{script}"" handoff ""C:\KenshiTestRuns\handoff.ready"" ""{project_dir}"" , tell Shay in one line what it printed, and end the turn (the waker guard lets the turn end while handoff.ready is fresh)."

$HANDOFF_MSG_SUBAGENT = "CONTEXT LIMIT: you ({agent_type} subagent) are at {tokens} tokens. Finish the step you're in, commit and push verified work per the project rules (never unverified work), write your handoff to C:\KenshiTestRuns\agents\<your-name>.handoff.md (not the scratchpad: the next session must find it), and run: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\agent-status.ps1 <your-name> STOPPED-CONTEXT ""<task>"" ""<latest step; locks/inflight markers you own>"" ""<handoff + output paths>"" ""<next step>"". Then stop. Start your final report with 'CONTEXT LIMIT: handoff at <path>' and tell the parent NOT to resume you via SendMessage, but to spawn a fresh {agent_type} subagent (not a fork) pointed at the status file."

# Independent agent session (spawn-wp-session.ps1 sets KAH_AGENT_NAME=<name>; Shay 2026-10-15): this session is an AGENT, not
# the coordinator. At the limit it checkpoints, writes STOPPED-CONTEXT, tells the coordinator via the inbox and stops; it never opens
# a new terminal session and never runs handoff-ready.ps1 (the coordinator respawns a successor from the status file).
if ($env:KAH_AGENT_NAME) {
    $an = $env:KAH_AGENT_NAME
    $WARN = 170000
    $WARN_MSG = "Context: {tokens} tokens (you are agent '$an'; stop at {handoff}). Finish the edit you are in, checkpoint now (regenerate the patch, compile-check, commit, update C:\KenshiTestRuns\agents\$an.handoff.md and your status 'latest'); continue only if < ~30k of work remains, else hand off as STOPPED-CONTEXT."
    $HANDOFF_MSG_MAIN = "CONTEXT LIMIT ({tokens}): you are the independent agent session '$an', not the coordinator. Finish only the tool step you are in, then in this order: " +
        "(1) checkpoint: commit and push verified work (never unverified work), write C:\KenshiTestRuns\agents\$an.handoff.md (done, left, patch/output paths, gotchas). " +
        "(2) Run: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\agent-status.ps1 $an STOPPED-CONTEXT ""<task>"" ""<latest step; locks/inflight markers you own>"" ""<handoff + output paths>"" ""<next step>"". " +
        "(3) Drop a one-line message file C:\KenshiTestRuns\inbox\coordinator\<yyyyMMdd-HHmmss>-$an.msg (e.g. '$an STOPPED-CONTEXT: handoff at <path>, spawn fresh successor'). " +
        "(4) Do NOT open a new session or terminal, do NOT run handoff-ready.ps1 or context-meter 'handoff', do NOT message other agents. End your turn with 'CONTEXT LIMIT: handoff at <path>'."
}
