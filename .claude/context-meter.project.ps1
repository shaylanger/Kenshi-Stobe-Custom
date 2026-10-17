# Kenshi workspace override for ~/.claude/hooks/context-meter.ps1 (dot-sourced after its config).
# At the limit the hook ORDERS a fixed handoff: HANDOFF.md + agent status files + handoff.ready marker,
# then a fresh session that starts with tools/automation/session-start.ps1. Shay, 2026-10-10.

# --- Overlap ("tail") handoff (docs/TAIL_HANDOFF_CONTRACT.md, Shay 2026-10-15) ---
# Coordinator (main session, not an agent): warn ~270k, handoff 300k. It does NOT exit while agents run: it opens the new coordinator
# session and becomes a TAIL session (tail-mode.ps1 enter). Subagents and independent agent sessions keep the user-level 200k.
# A session with a tail flag gets NO warn/handoff text; only at the tail hard limit (400k) one message tells it to checkpoint + stop its agents.
$sid = "$($in.session_id)"
$tailRuns = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$HANDOFF_MSG_MAIN = "CONTEXT LIMIT ({tokens}): OVERLAP HANDOFF (docs/TAIL_HANDOFF_CONTRACT.md). Your session id is $sid. Start NOTHING new (no batch, build, launch or agent); ~3 minutes in total, in this order: " +
    "(1) finish only the tool step you are in; leave detached batches and rig jobs running, each with an inflight marker in C:\KenshiTestRuns\inflight\ whose content is its out dir. " +
    "(2) Update testing/HANDOFF.md 'Right now' and the program ledger (C:\KenshiTestRuns\programs\<name>.json); commit + push per the repo rules. " +
    "(2b) PROCESS IDEAS REVIEW (about 5 minutes, before opening the new session; docs/PROCESS_IDEAS.md): write C:\KenshiTestRuns\process-ideas\review-<time>.json = {review, decisions:[{id, applies, evidence(this session), moment(only for confirmed)}], new:[{idea, evidence(concrete example + cost), saving, risk, hooks yes|no}]} with at most 3 new entries (the biggest 3 of this session) and a judgement for each existing open entry this session gives evidence about; run powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\process-ideas.ps1 review <file> , then commit + push docs/PROCESS_IDEAS.md. Ideas are recorded, never applied. " +
    "(3) For EACH agent still running write a ledger routing note and hand it to the tail: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\program-ledger.ps1 route <program> <agent> -Owner tail:$sid -Note ""<purpose/brief; where its output lands; what the new coordinator does when it finishes; dependencies; open decisions/warnings>"" [-Result <file>]. " +
    "(4) Agents ARE running: enter tail mode FIRST (so handoff.ready lists you as their owner): powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\tail-mode.ps1 enter -Session $sid -Agents <agent1>,<agent2> . " +
    "(5) Run: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\handoff-ready.ps1 ""<one-line note>"" (it refuses if HANDOFF.md wasn't just updated). Then open the new coordinator: " +
    "if NO agent is running run powershell -NoProfile -ExecutionPolicy Bypass -File ""{script}"" handoff ""C:\KenshiTestRuns\handoff.ready"" ""{project_dir}"" , tell Shay in one line what it printed and end the turn (old flow, the old window closes itself); " +
    "if agents ARE running run the same command with a trailing  keep  argument (it does NOT close this window). " +
    "(6) With agents running you are now a TAIL session: spawn nothing, edit nothing, decide nothing; keep your event-wait waker for YOUR agents only. When an agent finishes: save its full report to a file, then run: powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\tail-relay.ps1 -Agent <name> -Report <file> , send the printed message (<= ~30 lines) to the NEW coordinator with SendMessage (it also lands in C:\KenshiTestRuns\inbox\coordinator) and wait for its ACK. Forward agent questions, blockers, stalls and any peer message that reaches you immediately and unchanged. Stall rule: agent transcript silent 10 min -> message the agent; silent 20 min -> TaskStop it and tell the new coordinator. Healthy agents run as long as needed. You may end the turn only when every agent is done AND acknowledged (the Stop hook enforces it); this meter stays quiet until the tail hard limit (400k)."
$WARN_MSG = "Context: {tokens} tokens. LIVING-HANDOFF CHECKPOINT (docs/HANDOFF_STANDARD.md): auto-compact runs at about 150k. FIRST tell Shay in plain text: run /cost NOW and again right after the compact, and paste both (the summarizer call is not in the transcript; /cost is the only real measure). Now: run the zero-context test (could a new session continue from testing/COORDINATOR_LIVE.md + HANDOFF Right now + SHAY_DECISIONS.md + AGENT_BACKLOG.md alone?), update those files, AND the PROCESS IDEAS: file every new improvement idea from this stretch (concrete evidence + cost, docs/PROCESS_IDEAS.md via process-ideas.ps1 add or a review json; cap 15: progress/done finished ones first; record evidence on existing ideas that happened again), then commit + push and continue normally. Do not start a new large unit; there is NO handoff session and NO tail any more."
if (-not $in.agent_id -and -not $env:KAH_AGENT_NAME) {
    $WARN = 120000; $HANDOFF = 99999999
    if ($sid -and (Test-Path -LiteralPath (Join-Path (Join-Path $tailRuns 'tail') (($sid -replace '[\/:*?"<>|]', '_') + '.flag')))) {
        $WARN = 400000; $HANDOFF = 400000
        $HANDOFF_MSG_MAIN = "TAIL HARD LIMIT ({tokens}): you are a TAIL session (session $sid) at the hard limit. For every agent you still own: tell it to checkpoint now (patch, status STOPPED-CONTEXT, handoff file), TaskStop it, and relay to the new coordinator that it must be respawned from its checkpoint (tail-relay.ps1 -Agent <name> -Report <file>, SendMessage + inbox C:\KenshiTestRuns\inbox\coordinator). Then run powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\tail-mode.ps1 leave -Session $sid -Force and end the turn."
    }
}

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
