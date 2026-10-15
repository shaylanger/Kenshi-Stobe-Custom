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
- **Coordinator** at its own limit hands off WITHOUT telling healthy running agents to stop (see PROPOSED CONTEXT-METER HANDOFF TEXT).

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

## 9. CONTEXT-METER HANDOFF TEXT (RESOLVED 2026-10-15: the proposal below was REJECTED by the resume test)
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
