# Work-package (WP) sizing, code maps, checkpoints (2026-10-15)

Why: the imm26 program lost agents that read whole 60 KB+ files (chat_helper_functions.php is 694 KB / 16.6k lines, main.cpp 634 KB)
and hit the 200k-token meter before their tests ran, and a coordinator stop orphaned healthy agents. Rules below keep every package
small, resumable and cheap. Tool: `tools/automation/codemap.sh`. Standard block copy: `testing/AGENT_PROMPTS.md` ("Work packages").

## 1. What a work package is
- One WP = **1-3 related items, or ONE phase** of an item: `code` | `tests` | `patch/compose` | `native build` | `live validation`.
- Target **<= 120k tokens** of agent work (reads + edits + tool output + the final report). Hard stop for any agent is 200k.
- A WP touching **more than 2 big files** (> 60 KB) is split before spawning (by file or by phase).
- Phases are separate WPs even for one item: code (edit + `php -l`/build), tests (write + run offline tests), patch/compose (regenerate
  patch, compose onto the live tree), native build (STOBE.dll build, install), live validation (game rows). Never code + tests + live in one agent.
- Name: `wp<Letter>` (wpA); successors `wpA2`, `wpA3` (see 6). Work dir `/root/imm26/<name>/` (made by `/root/imm26/mkwp.sh`), patch
  `/root/imm26/<name>.patch`, copy in `pending-fixes/<program>/<name>/`.

## 2. Coordinator: WP breakdown BEFORE spawning
Write the breakdown (in the program md / ledger, one table) before the first Agent call; no agent starts without a row.

| WP | items / phase | big files touched (size) | est. read tokens | est. edit tokens | est. total | depends on | outputs |
|----|---------------|--------------------------|------------------|------------------|-----------|------------|---------|

Estimate: bytes/3.5 = tokens for anything an agent must read in full; for big files count only the codemap entries it will `sed`
(lines x ~12 tokens); edits ~2x the changed lines; tests/tool output ~15k per run; reserve 20k for brief + report. Total > 120k or > 2 big
files = split. Record the table in the program ledger (`C:\KenshiTestRuns\programs\<name>.json`) and update it after EVERY agent report.

## 3. Code maps: how agents read big files
`bash /mnt/c/KenshiModding/tools/automation/codemap.sh` (WSL) writes `/root/imm26/codemap/<label>__<path with __>.txt` + `INDEX.txt`:
- Maps exist for `/root/imm26/base` (every .php > 60 KB + `lib/chat_helper_functions.php`, `processor/chat.php`, `lib/npc_conversation_context.php`,
  `data/schema.sql`) as `base__lib__chat_helper_functions.php.txt` etc., and for `components/STOBE/src` (every .cpp/.h > 60 KB + `main.cpp`,
  `Context.cpp`, `ChatBox.cpp`, `Functions.cpp`) as `STOBE-src__main.cpp.txt` etc. `INDEX.txt` lists file, bytes, lines, entries, map, 3 largest entries.
- Line = `name start end lines kind`. Read one function: `grep -n 'funcname' /root/imm26/codemap/base__lib__chat_helper_functions.php.txt`, then
  `sed -n START,ENDp /root/imm26/base/lib/chat_helper_functions.php`. Kinds: function, method (`Class::m`), class/struct/namespace, `block`/`block1`
  (big top-level if/foreach/try in scripts/pages), `toplevel` (> 120 lines of code outside any function), `section` (banner comment),
  SQL `create_table`, `alter_table`, `create_index` (`idx@table`).
- Work-package copies: `bash codemap.sh /root/imm26/wpA/lib/x.php` makes `wpA__lib__x.php.txt` (line numbers shift after edits: regenerate after
  every edit batch, or just `grep -n` the real file for the name). `codemap.sh --check` lists stale maps; `--selftest` proves the parser (synthetic
  fixtures + every real entry's range starts on its name and ends on a closing brace/`;`).
- Fallback when a name is not in the map: `grep -n 'name' <real file> | head`, then `sed -n a,bp`. Never `cat`, never Read without offset/limit on a file > 60 KB.

## 4. Agent reading rules
1. Files > 60 KB: only `grep -n`, codemap, `sed -n a,bp`; Read with offset+limit <= 250 lines. Smaller files may be read whole.
2. Logs/status/test output: `tail -n`, `grep -c`, RESULT lines; paste result lines, not output.
3. The brief names the codemap entries to read (function names), not whole files. Briefs say "read only these", agents add reads sparingly.
4. Patches: `diff -ruN` into a file, read only `diffstat` + the hunks being checked.

## 5. CHECKPOINT rule (a stop at 200k must lose nothing)
At every milestone **or every ~40k tokens** (whichever first), do all four, in order, in one go:
1. regenerate the patch (`/root/imm26/mkpatch.sh`-style `diff -ruN -x log base <name> > <name>.patch`) and copy it with new tests into `pending-fixes/<program>/<name>/`;
2. `php -l` / compile-check what changed (a checkpoint is never a broken tree);
3. `agent-status.ps1 <name> RUNNING "<task>" "<latest: what is done, what is next, patch path + line count>" "<outputs>" "<next>"`;
4. commit the work dir files that live in git (`git -c user.email=shaylanger2@gmail.com -c user.name=shaylanger`), push; update `C:\KenshiTestRuns\agents\<name>.handoff.md` (done / in progress / next / gotchas).
The status "latest" line must be enough for a fresh agent to continue without asking.

## 6. Meter levels, handoff, successors
- **Warn level** (the subagent meter's WARN message, before 200k): finish the current edit, CHECKPOINT, then continue only if < 150k of work
  remains in the WP **and** the remaining steps are small; otherwise hand off now.
- **200k stop:** nothing may be lost: patch, status `latest` and handoff file are always current (section 5), so the stop costs one respawn.
- **Handoff:** status `STOPPED-CONTEXT`, handoff file with exact next step, final report begins `CONTEXT LIMIT: handoff at <path>`.
- **Successor naming:** `wpA` -> `wpA2` -> `wpA3`; the successor continues the SAME work dir and patch name suffix-free (patch stays `wpA.patch`), is a
  fresh agent (never SendMessage a stopped one), pointed at the predecessor's status + handoff files. The ledger records the chain. More than 3 successors = the WP was mis-sized: split it.
- **Coordinator** at its own limit (300k) hands off WITHOUT telling healthy running agents to stop: it stays alive as a TAIL session and relays their results (section 9, overlap handoff).

## 7. Agent BRIEF TEMPLATE (copy into every Agent prompt)
```
[case:generate] <wpName> - <one-line goal>. Program <program>, ledger C:\KenshiTestRuns\programs\<program>.json.
GOAL: <1-3 items or one phase; acceptance in one sentence each>.
FILES: work dir /root/imm26/<wpName>/ (private copy: mkwp.sh <wpName>); touch only: <paths>. Base (read-only): /root/imm26/base.
CODEMAP: /root/imm26/codemap/ (INDEX.txt). Read ONLY: <file>: <func1>, <func2> (grep -n name <map>; sed -n a,bp <file>). Files > 60 KB never read whole.
BUDGET: <= 120k tokens. CHECKPOINT every milestone or ~40k tokens: patch regenerated, php -l, agent-status "latest", commit/push, handoff file.
At the meter WARN: finish the edit, checkpoint, continue only if < 150k work remains, else hand off (status STOPPED-CONTEXT).
STATUS: powershell -NoProfile -File C:\KenshiModding\tools\automation\agent-status.ps1 <wpName> RUNNING|DONE|FAILED|STOPPED-CONTEXT "<task>" "<latest>" "<outputs>" "<next>"
HANDOFF: C:\KenshiTestRuns\agents\<wpName>.handoff.md ; successor name <wpName>2.
CHECKS: <exact commands, e.g. php -l, tests path, RESULT lines to paste>; 3 failed attempts = FAILED with last error.
DELIVERABLES: <patch /root/imm26/<wpName>.patch + copy in pending-fixes/<program>/<wpName>/, tests, docs row>.
REPORT (10 lines max): files changed, check result lines, patch path + diffstat, status path, next speed-up. End with SubagentHandback.
```

### 7b. Lane operators: generate the brief, do not write one (PI-12, 2026-10-15)

For a rig-lane operator (5090-i3/i4/i5, 4080-i3/i4) do not copy the long briefs into the Agent prompt. Run `powershell -NoProfile -File C:\KenshiModding	oolsutomation\lane-brief.ps1 <lane> -Out C:\KenshiTestRunsgents\<operator>.brief.md -Name <operator>` and spawn with a 2-line prompt that points at that file (it carries the lane facts, current lane and newest NC DLL SHA256, the predecessor handoff, the next 5 non-PASS rows, known blockers, the standing rules (ONE debug attempt per row, <= 8-line handbacks, status/handoff files, isolated lane only) and the exact status/handoff/report commands, all read at call time, about 6 KB). Set `lane-owners.json` to the new operator first. Selftest: `tools/automation/lane-brief-selftest.ps1`.

## 8. PROPOSED CLAUDE.MD TEXT
Not applied (awaits Shay). The existing section "Large programs: never lost, never stalled" already holds: state in files, supervisor, "Size work
packages before spawning" (<= 120k, 1-3 items or one phase, > 2 big files split, grep/line ranges only, checkpoints, coordinator hands off without
stopping agents). Proposed: replace its "Size work packages before spawning" bullet with the one below and add the two new bullets after it. (Delta
only: code maps, warn level, successor names, tool pointers.)

```
- **Size work packages before spawning:** write a breakdown with token estimates first (`docs/WP_SIZING.md` section 2); one package = 1-3 related items or one phase (code | tests | patch/compose | native build | live validation), target <= 120k tokens, split anything touching more than 2 big files (> 60 KB). Never code + tests + live validation in one agent.
- **Big files are read through code maps:** `bash tools/automation/codemap.sh` (WSL) keeps `/root/imm26/codemap/<label>__<file>.txt` (name start end lines kind) for the large server PHP and STOBE C++ files; agents `grep -n funcname <map>` then `sed -n a,bp <file>`, never read a file > 60 KB whole; briefs name the functions to read. Regenerate a map after editing its file (`codemap.sh <file>`; `--check` lists stale maps).
- **Checkpoints and handoffs:** every milestone or ~40k tokens an agent regenerates its patch, compile-checks, updates its status `latest`, commits and updates its handoff, so a stop at 200k loses nothing. At the meter's warn level (before 200k): finish the edit, checkpoint, continue only if < 150k of work remains, else hand off (STOPPED-CONTEXT). Successors are fresh agents named wpA -> wpA2 -> wpA3 (the same work dir). Brief template: `docs/WP_SIZING.md` section 7.
```

## 9. CONTEXT-METER HANDOFF TEXT (RESOLVED 2026-10-15: the proposal below was REJECTED by the resume test; REPLACED the same day by the OVERLAP HANDOFF)
**Current flow (Shay 2026-10-15, `docs/TAIL_HANDOFF_CONTRACT.md`, steps in `testing/AGENT_PROMPTS.md` "Overlap handoff and tail mode"):** the coordinator's handoff text (`$HANDOFF_MSG_MAIN` in `.claude/context-meter.project.ps1`, at 300k; warn 270k) no longer asks for a "checkpoint now" message or a fresh-respawn list. The old coordinator writes a ledger routing note per running agent (`program-ledger.ps1 route ... -Owner tail:<session>`), runs `tail-mode.ps1 enter`, `handoff-ready.ps1`, opens the new coordinator with the meter's `handoff ... keep` and stays alive as a TAIL session; the in-session agents therefore keep running and their results reach the new coordinator via `tail-relay.ps1` / `tail-ack.ps1`. Tail hard limit 400k (agents checkpoint, are stopped, new coordinator respawns them). Work-package sizing/checkpoints (sections 2 and 5) still apply: they protect against an agent hitting its own 200k, and a dead tail (PC shutdown) is recovered from checkpoints by the cold-start listing in `session-start.ps1`. The text below is historical.
Resume test result (coordinator, 2026-10-15 14:50): subagents of an ended session are gone (no processes, status files frozen, not in ListAgents, no stobe-tests running) and cannot be messaged by the new session. So 'adopt healthy agents' is impossible. Applied instead in `.claude/context-meter.project.ps1`: step (2) = one non-blocking 'checkpoint now' SendMessage (max ~2 min), then list every running agent + its fresh successor name in HANDOFF and the ledger; the next coordinator respawns them fresh. The real protection is small work packages + 40k-token checkpoints (sections 2, 5). Historic proposal text follows.
Not applied (`.claude/context-meter.project.ps1` untouched; awaits Shay). Problem: `$HANDOFF_MSG_MAIN` step (2) tells the coordinator to
SendMessage every running subagent to stop, so a coordinator at its limit kills healthy mid-package agents (imm26). Revised wording; replace
step (2) and add the sentence to step (3) in `$HANDOFF_MSG_MAIN`, and soften `$WARN_MSG`:

```
$WARN_MSG = "Context: {tokens} tokens (handoff at {handoff}). Wrap up the current unit of work; don't start a new batch, build or review round (a work package may still be spawned if it is written into the program ledger first). Make sure testing/HANDOFF.md 'Right now', the program ledger and every agent's C:\KenshiTestRuns\agents\<name>.status are current."

(2) Do NOT tell healthy running subagents to stop and do not wait for their reports: they keep working and keep reporting to their status files, handoff files and C:\KenshiTestRuns\programs\<program>.json. Make sure each running agent is listed in the ledger (name, WP, status file, handoff file, successor name) and in HANDOFF 'Right now' with the line 'running, adopt it: read <name>.status'. Only an agent whose status is already STOPPED-CONTEXT/FAILED, or that is sitting idle past its status staleness (> 30 min), needs a note for the next coordinator to respawn it.
(3) Update testing/HANDOFF.md 'Current state' / 'Right now' and the program ledger: running batches (out dirs, rig jobs, lock owner), EVERY running agent with its status file and WP (adopt, do not restart), what was mid-way, the next coordinator's first steps (session-start.ps1, adopt agents from the ledger, answer any inbox\coordinator messages). Commit + push.
```
and in step (5) after the `handoff` command: "the next coordinator adopts the running agents from the ledger and HANDOFF; their reports arrive in C:\KenshiTestRuns\inbox\coordinator\ and status files, which the new session's event wait reads".
The subagent message `$HANDOFF_MSG_SUBAGENT` stays, plus its first clause "CHECKPOINT first (regenerate patch, compile check, status latest, commit)" so the stop point is always a valid tree.

## 10. Independent agent sessions (2026-10-15, imm26-indep-spawn) - SUPERSEDED / OPTIONAL
**Superseded the same day by the overlap (tail) handoff (section 9):** in-session subagents are the standard and the router no longer forces long work into independent sessions; this section documents code that stays in the repo (`spawn-wp-session.ps1`, `agent-host.ps1`) but is off by default. Use it only if Shay asks.
Why: in-session subagents die with the session that spawned them (section 9). A work package that must outlive its coordinator runs as an INDEPENDENT `claude` session: its own terminal window, own process tree, own transcript, found and adopted by files. Tools: `tools/automation/spawn-wp-session.ps1`, `agent-session-live.ps1`, selftest `spawn-wp-session-selftest.ps1` (22 offline checks; `-Real` adds one real trivial child). No LLM is needed to call them (the supervisor / a watchdog may).

### Usage
- `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\spawn-wp-session.ps1 <name> <case-or-tier> <prompt-file> [-Program imm26 -Wp wpA] [-Task "..."] [-PermissionMode auto] [-DryRun] [-Force]`
- `<case-or-tier>` is resolved through `model-policy.json` (generate/patch -> sonnet high, debug/investigate -> sonnet xhigh, escalate -> opus medium ...) and passed as `claude --model <m> --effort <e>`. Prompt file = the brief of section 7; the script writes a copy `agents\<name>.prompt.md` = brief + the standard independent-agent block (status/heartbeat, checkpoint, own inbox, 150k handoff with successor `<name>2`, DONE/FAILED/STOPPED-CONTEXT report to `inbox\coordinator\`, save-report). The session itself is started with a one-line bootstrap prompt ("read <prompt.md> and follow it").
- The prompt must be claude's FIRST argument: `--add-dir` is variadic and swallows a prompt placed after it (a first test child sat idle for exactly this reason).
- Spawning over a LIVE session of the same name is refused (`-Force` overrides); a successor gets a new name.
- `agent-session-live.ps1 <name>` prints `LIVE ...` (exit 0) or `DEAD <reason>` (exit 1; exit 2 = no session record). LIVE = claude pid alive (verified by its recorded start time, so a recycled pid does not count) AND `agents\<name>.status` is RUNNING and written < 10 min ago (`KAH_HEARTBEAT_MIN`). Another source: `claude agents --json` lists every interactive session with pid, `sessionId` (= `claude_session_id` below), name, `status` busy/idle.

### Schema (for session-start.ps1 adoption)
`C:\KenshiTestRuns\agents\<name>.session.json` (written by spawn, `exited`/`exit_code` added by the launcher when claude ends):
`name program wp tier model effort permission_mode claude_session_id workdir title mode("terminal") prompt_file launch_script status_file inbox started(ISO) launcher_pid launcher_start claude_pid claude_start spawned_by_pid dry_run [exited exit_code]`. `launcher_pid` = the PowerShell window running `agents\<name>.launch.ps1`; `claude_pid` = the claude.exe child (0 when not found within 40 s: liveness then uses the launcher pid). Companion files: `agents\<name>.status` (RUNNING at spawn, then the agent's heartbeat), `agents\<name>.prompt.md`, `agents\<name>.launch.ps1`, `inflight\<name>` (created by agent-status RUNNING, removed on DONE), `inbox\<name>\` (messages TO the agent). Resume of a dead session is possible with `claude --resume <claude_session_id>` but the rule stays: respawn a FRESH successor.
Program ledger (`programs\<program>.json`), new work-package field `sessions` (list of strings `agent|launcher_pid|claude_pid|startedISO`, one per agent name, newest wins) and command `program-ledger.ps1 session <program> <wp> <agent> <launcher_pid> [claude_pid]` (also sets `agent`, or appends to `successors` when the WP already names another agent; `agent-status.ps1 <name> RUNNING` then moves the WP to running). `brief`/`show` are unchanged; `show -Md` prints `- session:` lines.
Adoption check for a coordinator / session-start: for every unfinished WP read `agent`, run `agent-session-live.ps1 <agent>`: LIVE = adopt (do nothing, read its status; its DONE/FAILED/STOPPED-CONTEXT arrives as a file in `inbox\coordinator\`); DEAD with RUNNING status or STOPPED-CONTEXT = spawn a fresh successor with spawn-wp-session.ps1 from its handoff. `coord-supervisor.ps1` already treats a command line containing the agent name as alive (Real-ProcessProbe; the launcher and claude command lines contain the name), so it does not mark a live independent session orphaned; it does NOT auto-spawn agents (cost and duplicate risk): auto-respawn is left to the coordinator that reads `agent-session-live.ps1`.
Permission mode: default `auto` (the classifier approves routine tool calls, so an unattended session is not blocked by a prompt; measured below). No `--dangerously-skip-permissions`. An agent that needs a project allow-list entry still asks inside its window: check `claude agents --json` status / the window if a heartbeat goes stale with the process alive.

### Survival test results (measured 2026-10-15, claude 2.1.301)
Mechanism (a) `mcp__ccd_session__start_session`: NOT in this session's tool set; skipped.
Mechanism (b) scripted terminal launch (the context-meter `handoff` / coord-supervisor pattern):
- Launched from a detached hidden PowerShell that exited 1.8 s later (`Start-Process powershell -WindowStyle Hidden ... spawn-wp-session.ps1`): the child window and its claude.exe kept running (trivial child `imm26-indep-test1`, sonnet, permission auto, 6 x [agent-status heartbeat + inbox check + 30 s sleep]); 15:21:23 -> status DONE 15:24:53 (3.5 min), status rewritten every ~30 s, `agent-session-live.ps1` printed LIVE throughout (heartbeat 0.2-0.3 min) and `DEAD status is DONE (claude pid ... still alive)` after the work ended.
- Job object: the launching tool shell is inside a Windows job with limit flags 0x0 (no KILL_ON_JOB_CLOSE, no breakaway needed), so no job teardown kills the children; the supervisor-launched coordinator (pid 56556) uses the same pattern. What was NOT possible to test: ending the whole interactive session that launched it (this agent is that session); the two proxies above (launching shell gone, job without kill-on-close) are what was measured.
- Reach from another session: (1) status file `agents\<name>.status` fresh every 30 s; (2) process list: claude.exe child of the launcher window, `claude agents --json` shows it as `kind interactive`, name = window name, `status busy|idle`, sessionId = `claude_session_id`; (3) inbox: a file dropped in `inbox\<name>\` was read by the child at its next check (about 40 s later), moved to `inbox\<name>\delivered\` and answered in its status `latest` ("inbox got: PING-OK"). A child only sees inbox files when it looks: the standard block orders a check at every checkpoint and `event-wait.sh --me <name>` while waiting; an idle prompt receives nothing. (4) `ListAgents` / SendMessage in a coordinator session: not applicable, an independent session is not a subagent of any session (the Agent tool's list never contains it); use the three channels above.
- Permission mode `auto`: the child ran PowerShell commands (agent-status, Get-ChildItem, Start-Sleep) with no prompt, unattended. Without a flag the same launch would stop at any command not in settings allow lists.
- Finished sessions stay open: after DONE the claude window idles at its prompt (alive, status DONE = DEAD for the liveness check). A coordinator closes it with `taskkill /PID <launcher_pid> /T /F` (launcher_pid from session.json) once the report is read; do not leave old windows.
- Bug found while testing: `claude <flags> --add-dir A B 'prompt'` treats the prompt as a third directory (variadic option) and the session opens with no task; the generated launcher therefore puts the prompt first.
- Mechanism (c), measured as a side note, not built: `claude --bg --model sonnet --effort low --permission-mode auto -n <name> "<prompt>"` starts a daemon-hosted background session without a window (`claude agents`, `claude logs|attach|stop|rm <id>`); it ran a one-line task unattended and was listed `kind background state done` with no pid. It would avoid window clutter and Windows job questions, but its survival depends on the claude daemon (`claude daemon run --origin transient --spawned-by ...` is a child of some other session), which was not tested to outlive a session. Candidate follow-up if windows prove a problem.
- Selftest: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\spawn-wp-session-selftest.ps1` = SELFTEST PASS 22/22 offline; with `-Real` 25/25 (spawn from a shell that exits, survives, listed by `claude agents --json`, runs agent-status DONE unattended, then cleaned up). `program-ledger.ps1 -Selftest` = 46/46 (new checks 6j-6l for the `session` command).
