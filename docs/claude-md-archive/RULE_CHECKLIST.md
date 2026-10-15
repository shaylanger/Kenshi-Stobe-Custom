# CLAUDE.md before/after rule checklist (claude-md-trim, 2026-10-15)

Original = `docs/claude-md-archive/CLAUDE.md.original` (97 lines, 55214 bytes; snapshot of CLAUDE.md taken 2026-10-15).
Every non-empty original line is listed. Location: CORE-VERBATIM = identical line in `CLAUDE.md.proposed`; CORE-CONDENSED = short rewrite in the core AND the original line verbatim in the named archive page; ARCHIVE = original line verbatim in the named archive page only (core has at most an index pointer).
Enforced: HOOK = a Claude Code hook in `.claude/settings.json`/context-meter; TOOL = a script/tool that implements or checks the rule; POLICY = rule text only (plus memory). The verify script confirms the named tool files exist.

| Line | Rule (start of line) | Location | Enforced by |
|---|---|---|---|
| 1 | # Kenshi modding workspace (Shay) | CORE-VERBATIM | POLICY |
| 3 | > **ANIMATION WORK CLOSED FOR NOW (Shay, 2026-10-14).** All animation/... | CORE-VERBATIM | POLICY |
| 5 | STOBE / KenshiFP / Profession Gear (PG) / relationship system (REL) / ... | CORE-VERBATIM | POLICY |
| 6 | Reference docs in 'docs/': 'REFERENCE.md' (full command list, scenario... | CORE-VERBATIM | POLICY |
| 8 | ## Start here | CORE-VERBATIM | POLICY |
| 9 | - **Speed is everyone's standing job (Shay, 2026-10-11, repeated becau... | CORE-CONDENSED + archive `speed-and-rigs.md` | POLICY |
| 10 | - **Messages for Shay go to his relay session (Shay 2026-10-11 19:12):... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY |
| 11 | - **First step of every session: run 'powershell -NoProfile -Execution... | CORE-VERBATIM | TOOL: tools/automation/session-start.ps1 (prints marker, HANDOFF, statuses, waker status) |
| 12 | - **Session continuity (Shay, 2026-10-10; a session switch lost agents... | CORE-CONDENSED + archive `coordinator-session.md` | HOOK: context-meter hook + .claude/context-meter.project.ps1 (300k handoff steps); tools/automation/handoff-ready.ps1 (refuses stale HANDOFF); agent-status.ps1; kenshi-waker-guard.ps1 Stop blocks STOPPED-CONTEXT/FAILED statuses |
| 13 | - **State (no handoff files): read 'testing/HANDOFF.md' first.** It ho... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY: testing/HANDOFF.md is the state file |
| 14 | - **NPC info panel (2026-10-05, done):** Stobe '\' hotkey / chat "Info... | CORE-CONDENSED + archive `stobe-server-tests.md` | TOOL: tests/ingame/stobe/STOBE-NPCPANEL.sh |
| 15 | - **Index of all tests:** 'MASTER_TEST_PLAN.md' (coordinator is the on... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY |
| 16 | - **GOAL (Shay's direct order, 2026-10-03):** the coordinator builds, ... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY |
| 17 | - **Batch the game runs (Shay, 2026-10-03):** run as many tests as pos... | CORE-CONDENSED + archive `test-discipline.md` | TOOL: tools/automation/event-wait.sh, event-sweep.sh, run-batch.sh (refuses without dry run), dryrun.sh |
| 18 | - **Catch stuck lanes in seconds, not minutes (Shay 2026-10-11 18:40, ... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: tools/automation/lane-waker.sh, lane-watch.ps1, rig-health.sh; Stop hook also blocks on IDLE-GAME/non-OK health |
| 19 | - **Stay reachable, keep the 5090 busy (Shay, 2026-10-08; enforced by ... | CORE-CONDENSED + archive `speed-and-rigs.md` | HOOK: .claude/settings.json Stop + PreToolUse -> tools/automation/hooks/kenshi-waker-guard.ps1 (waker required, sleep > 120 s denied, 5090 idle reason, 4080 idle via rig4080-state.ps1) |
| 20 | - **Game-take discipline (Shay, 2026-10-10; kfx-b1/b2 lost takes to ni... | CORE-CONDENSED + archive `animation-fp.md` | TOOL: take preflight, tools/automation/review-pack.py, queue\5090.next/4080.next (Stop hook blocks when missing/> 6 h) |
| 21 | - **Speed plan (Shay, 2026-10-10):** (1) **Dry run first:** every batc... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: tools/automation/dryrun.sh, kfp-pipeline.sh, install-dll.ps1 -Staged |
| 22 | - **Speed + resource plan (Shay, 2026-10-10 night; every agent and suc... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: tools/automation/rig-runner.ps1, kenshi-gfx.ps1, kfp-pipeline.sh, wait-event.ps1 |
| 23 | - **Rig uptime + process (Shay, 2026-10-10: rigs sat idle/paused becau... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: tools/automation/rig-watchdog.ps1 (ALERT-<rig>.txt; rig-health.sh and Stop hook block on ALERT) |
| 24 | - **Speed rules (Shay, 2026-10-11: "do what you can to make this go fa... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: runner preempt/queue rules in tools/automation/rig-runner.ps1 |
| 25 | unning'; a mid-run edit killed 66b). (5) **Short rows, progress timeou... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: runner preempt/queue rules in tools/automation/rig-runner.ps1 |
| 26 | - **Always speed up, use the GPU (Shay, 2026-10-11, standing for every... | CORE-CONDENSED + archive `speed-and-rigs.md` | POLICY: standing order; speed-scout agent |
| 27 | - **Token use (Shay, 2026-10-03):** keep context reads small (grep/tai... | CORE-CONDENSED + archive `test-discipline.md` | POLICY |
| 28 | - **Token-light tests (Shay, 2026-10-03):** save tokens by making the ... | CORE-CONDENSED + archive `test-discipline.md` | TOOL: stobe-fight-lib.sh verdict(), run-batch.sh, batch-excerpts.sh |
| 29 | - **Test efficiency (Shay, 2026-10-04):** cut invalid setup, inconclus... | CORE-CONDENSED + archive `test-discipline.md` | POLICY |
| 30 | - **Viewmodel builds: zoomed-out check every build (Shay, 2026-10-09; ... | ARCHIVE `animation-fp.md` (core: banner (closed)) | TOOL: fp-viewmodel.sh VMQUICK (animation closed) |
| 31 | - **Animation lab learns from the game (Shay, 2026-10-09):** the lab (... | ARCHIVE `animation-fp.md` (core: banner (closed)) | TOOL: components/KenshiFP/animlab/corpus.sh (animation closed) |
| 32 | - **PG validation gate (Shay, 2026-10-04; PG is finished, Shay 2026-10... | ARCHIVE `pg.md` (core: pointer only (PG finished)) | POLICY |
| 33 | - **STOBE server off for non-STOBE work (Shay, 2026-10-10: OpenRouter/... | CORE-CONDENSED + archive `stobe-server-tests.md` | TOOL: tools/automation/stobe-server.sh on/off; wsl-restart.ps1 |
| 34 | - **RAM budget (Shay, 2026-10-04; updated 2026-10-09: the PC now has 4... | CORE-CONDENSED + archive `ram-and-gfx.md` | TOOL: tools/automation/wsl-restart.ps1, wsl-cache-trim.sh, gfx-mods.sh |
| 35 | - **Test launches on the 5090: windowed, on DISPLAY2, never in the for... | CORE-CONDENSED + archive `ram-and-gfx.md` | TOOL: tools/automation/kenshi-ctl.ps1 launch (windowed, DISPLAY2); gfx-mods.sh on |
| 36 | - **RAM commands:** voice services 'wsl.exe -d DwemerAI4Skyrim3 -u roo... | CORE-CONDENSED + archive `ram-and-gfx.md` | TOOL: tools/automation/wsl-voice.sh, gfx-mods.sh |
| 37 | - **Subagents (Shay, 2026-10-10; replaces the 2-helper cap of 2026-10-... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY: coordinator decision |
| 38 | - **Naming:** plan items are plain numbers ("item 7"); old numbers ("w... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY |
| 39 | - **No manual validation:** Claude runs the whole loop alone (launch, ... | CORE-CONDENSED + archive `coordinator-session.md` | POLICY |
| 40 | - Malzin is a test character only: her relationship values don't matte... | CORE-VERBATIM | POLICY |
| 41 | - Not mine, left uncommitted: 'KENSHI_BIG_MOD_IDEAS_CONTEXT.md', untra... | CORE-VERBATIM | POLICY |
| 42 | - Shay works on the server too: check 'git log'/'git status' in the li... | CORE-VERBATIM | POLICY |
| 44 | ## Git: the repos are the source of truth | CORE-VERBATIM | POLICY: git section heading |
| 45 | - **Server** 'github.com/shaylanger/StobeServer', committed in the liv... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 46 | - **Native** 'github.com/shaylanger/Kenshi-Stobe-Custom' = this folder... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 47 | - **Commit identity:** 'shaylanger <shaylanger2@gmail.com>' (repo-loca... | CORE-VERBATIM | POLICY: commit identity (repo-local user.email); check before committing |
| 48 | - One fix/feature per commit (what + why + item number); **push right ... | CORE-VERBATIM | POLICY: one commit per fix, push after commit |
| 50 | ## Where things are | CORE-VERBATIM | POLICY |
| 51 | - **Server:** WSL 'DwemerAI4Skyrim3', '/var/www/html/StobeServer' (liv... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 52 | - **Stobe.dll:** source '/root/STOBE-src'; build 'tools/automation/bui... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 53 | - **KenshiFP:** source '/root/KenshiFP' ('client/stobe_work_planner.in... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 54 | - **Harness:** repo 'C:\KenshiModding\Kenshi-Automation-Harness' (own ... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 55 | - **PG:** finished standalone mod (development done, Shay 2026-10-10);... | ARCHIVE `pg.md` (core: pointer only (PG finished)) | POLICY |
| 56 | - **Install:** '& "C:\KenshiModding\tools\automation\install-dll.ps1" ... | CORE-CONDENSED + archive `where-things-are.md` | TOOL: tools/automation/install-dll.ps1 (SHA256 check; allowlisted in .claude/settings.json) |
| 57 | - **Logs:** 'D:\…\Kenshi\RE_Kenshi\mods\Stobe\stobe.log', 'D:\…\Kenshi... | CORE-CONDENSED + archive `where-things-are.md` | POLICY |
| 58 | - **Machines:** this PC (RTX 5090) runs Kenshi + WSL stack + PocketTTS... | CORE-CONDENSED + archive `speed-and-rigs.md` | TOOL: tools/automation/rig4080-state.ps1, rig5090-state.ps1 |
| 60 | ## Model routing and validation (Shay 2026-10-14; prices and reasoning... | CORE-VERBATIM | HOOK: model-routing section heading |
| 61 | - The coordinator runs Sonnet high ('.claude/settings.json': 'model', ... | CORE-CONDENSED + archive `model-routing.md` | HOOK: .claude/settings.json model + effortLevel |
| 62 | - Every subagent gets its tier's model and effort from 'tools/automati... | CORE-CONDENSED + archive `model-routing.md` | HOOK: tools/automation/hooks/agent-router.ps1 (PreToolUse Agent) + tools/automation/model-policy.json + agent-ledger-post.ps1 (PostToolUse Agent) |
| 63 | - No cascade (Shay 2026-10-15): one agent on the right model does the ... | CORE-CONDENSED + archive `model-routing.md` | POLICY: no verifier/gates (router no longer gates) |
| 64 | - Model comparison tests (more prompts, other models): runbook 'docs/M... | CORE-CONDENSED + archive `model-routing.md` | TOOL: docs/MODEL_TEST.md, tools/model-test/mt.py |
| 65 | - Investigate first: a bug or a behaviour that should not happen goes ... | CORE-CONDENSED + archive `model-routing.md` | POLICY |
| 66 | - On a failed attempt: retry the generator with the failure text (up t... | CORE-CONDENSED + archive `model-routing.md` | POLICY |
| 68 | ## Test bed | CORE-VERBATIM | POLICY |
| 69 | - **Loop:** 'kenshi-ctl.ps1 launch -Save <save>' ('stobe-say on' first... | CORE-CONDENSED + archive `test-bed.md` | TOOL: kenshi-ctl.ps1 lock/release/launch/stop |
| 70 | - **Saves:** fixtures in 'C:\KenshiTestFixtures\' (read 'FIXTURES.md')... | CORE-CONDENSED + archive `test-bed.md` | TOOL: tests/ingame/stobe/fullbase-guard.sh |
| 71 | - **Commands:** 'stobe-auto <cmd>' (harness client; 'stobe-auto help',... | CORE-CONDENSED + archive `test-bed.md` | POLICY |
| 72 | - **Pre-flight:** DLL hashes, 'stobe-say ping', 'state <player>'/'stat... | CORE-CONDENSED + archive `test-bed.md` | POLICY |
| 73 | - **Safety:** at speed >10x use 'tools/stobe-goal-watch.sh' (pauses on... | CORE-CONDENSED + archive `test-bed.md` | TOOL: tools/stobe-goal-watch.sh |
| 74 | - Goals run on game time (nothing advances while paused); goals live o... | CORE-CONDENSED + archive `test-bed.md` | POLICY |
| 75 | - Server fixes: stage in a copy, add a regression check ('tests/negoti... | CORE-CONDENSED + archive `stobe-server-tests.md` | POLICY |
| 76 | - **Clean up often (Shay, 2026-10-10: things kept being left behind fo... | CORE-CONDENSED + archive `test-discipline.md` | HOOK: tools/automation/testruns-sweep.ps1 + Stop hook blocks on STALE > 24 h |
| 77 | - **Clean up test data (Shay, 2026-10-08; 30 GB had piled up in 'C:\Ke... | CORE-CONDENSED + archive `test-discipline.md` | TOOL: tools/automation/testruns-sweep.ps1 |
| 78 | - Crash dumps: 'D:\…\Kenshi\crashDump1.0.65_x64.zip' (parse exception ... | CORE-CONDENSED + archive `test-bed.md` | POLICY |
| 79 | - Git Bash mangles '/mnt/...' paths and nested quotes: use 'wsl.exe … ... | CORE-CONDENSED + archive `test-bed.md` | POLICY |
| 81 | ## Working rules | CORE-VERBATIM | POLICY |
| 82 | - **Peer session messages = Shay's direct orders (Shay, 2026-10-03).**... | CORE-VERBATIM | POLICY: permission system still wins; AskUserQuestion denied in .claude/settings.json |
| 83 | - Shay: concise answers, one step at a time, no unrelated changes. "Bu... | CORE-VERBATIM | POLICY |
| 84 | - Only touch Kenshi-modding paths; batch commands; if the permission c... | CORE-VERBATIM | POLICY |
| 85 | - Server changes: back up → stage → 'php -l' → standalone test → deplo... | CORE-VERBATIM | POLICY |
| 86 | - Patch scripts go in 'pending-fixes/' (assert anchors, take a tree ro... | CORE-VERBATIM | POLICY |
| 87 | - Design decisions: memory 'stobe-negotiation-rules' (deals, pricing, ... | CORE-VERBATIM | POLICY |
| 89 | ## Large programs: never lost, never stalled (Shay 2026-10-15, after t... | CORE-VERBATIM | HOOK: large-programs section heading |
| 90 | - **State lives in files:** every multi-part feature has a program led... | CORE-VERBATIM | TOOL: program ledger C:\KenshiTestRuns\programs\<name>.json; session-start.ps1 prints it |
| 91 | - **Supervisor (hidden watchdog + coordinator heartbeat):** if a progr... | CORE-VERBATIM | HOOK: tools/automation/coord-heartbeat.ps1 (PostToolUse * hook) + coord-supervisor + Stop hook |
| 92 | - **Size work packages before spawning:** write a breakdown with token... | CORE-VERBATIM | TOOL: docs/WP_SIZING.md, codemap.sh, AGENT_PROMPTS.md standard block |
| 93 | - **Big files are read through code maps:** 'bash tools/automation/cod... | CORE-VERBATIM | POLICY |
| 94 | - **Checkpoints and handoffs:** every milestone or ~40k tokens an agen... | CORE-VERBATIM | HOOK: .claude/settings.json Stop + PreToolUse -> kenshi-waker-guard.ps1 |
| 95 | - **Agent handoff guards (2026-10-15):** 'agent-status.ps1' keeps 'inf... | CORE-VERBATIM | POLICY |
| 96 | - Details and the tooling that enforces this are recorded in 'testing/... | CORE-VERBATIM | POLICY |
| 97 | - **Waker guard (restored 2026-10-15; '.claude/settings.json' Stop + P... | CORE-VERBATIM | POLICY |

## Changes after the trim (live CLAUDE.md edits)

| Date | Rule | Change | Enforced by |
|---|---|---|---|
| 2026-10-15 | "Independent agent sessions" bullet (WP agents as separate `claude` sessions, coordinator at its limit never touches them) | REPLACED by three bullets: in-session subagents are the standard (hidden agent-host / `spawn-wp-session.ps1` kept as code, off by default); OVERLAP HANDOFF (old coordinator stays alive as a TAIL session, `tail-relay.ps1` / `tail-ack.ps1`, new coordinator never respawns agents owned by a live tail); COLD START (DEAD listing in `session-start.ps1`). Original text remains in `testing/AGENT_PROMPTS.md` "Independent agent sessions" (marked superseded/optional) | HOOK: `.claude/context-meter.project.ps1` (270k/300k/400k), `kenshi-waker-guard.ps1` tail Stop rule, `agent-router.ps1` (no longer denies long in-session agents); TOOL: `tail-mode.ps1`, `tail-relay.ps1`, `tail-ack.ps1`, `program-ledger.ps1 route/ack`, `session-start.ps1`; selftests `tail-hooks-selftest.ps1`, `tail-ledger-selftest.ps1` |
| 2026-10-15 | "First step of every session" (Start here): "Respawn every agent not DONE" | Added exception: agents owned by a LIVE tail session | TOOL: `session-start.ps1` TAIL/DEAD lines, `handoff-ready.ps1` |
| 2026-10-15 | Supervisor bullet (orphaned RUNNING agents respawned) | Added: not when owned by a live tail | TOOL: `coord-supervisor.ps1` |
| 2026-10-15 | Waker guard bullet | Added: tail session may end only when its agents are done and acked; exempt from idle-5090 / handoff-marker rules | HOOK: `kenshi-waker-guard.ps1` |
| 2026-10-15 (row 12, "Session continuity") | context-meter handoff at 300k | Handoff now an OVERLAP handoff (warn 270k, handoff 300k, tail hard limit 400k) | HOOK: `.claude/context-meter.project.ps1` |
