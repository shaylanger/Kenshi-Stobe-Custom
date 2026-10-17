# Row rework gate (imm26 credit-review cut #1, Shay approved 2026-10-16)

Why: on 24 rows with 2+ agents the later agents cost $105.75 (25% of the day; worst 26-a $18.15 after a $0.57 first agent, 26-f $13.34, 14-d $10.32, 11-b $10.01, 15-bx $8.95). The cost is re-reading and re-diagnosis, not spawn startup. 23-a needed three fixer rounds because each fixer's selftest used a fake scene instead of the previous live run's evidence. Details: `C:\KenshiTestRuns\agents\out\imm26-creditreview\creditreview.md` section 4B.

## The rules (enforced by the Agent hook, not by memory)
A **gated agent** is an Agent call with `[case:patch|generate|investigate|debug|escalate]` whose description (else the first 300 chars of the prompt) names 1-4 row ids. For each named row:

1. **One open agent per row.** Denied while another gated agent for the row is RUNNING (its `agents\<name>.status` says RUNNING and is < 45 min old; with no status file: < 45 min since the spawn; a foreground agent is closed by the post hook).
2. **Attempt 2 and later** must carry these three lines in the Agent prompt (each on its own line):
   - `PREV-REPORT: <path>` the previous agent's handoff/report (`agents\out\<name>\latest.md` or `<name>.handoff.md`); must exist and be newer than that agent's start. `PREV-REPORT: none` only if every earlier agent failed/stopped without a report.
   - `WHAT IS DIFFERENT THIS TIME: <one line, >= 20 chars>` ("same", "retry", "n/a" are refused).
   - `REPLAY-EVIDENCE: <dir>` the REAL lane evidence directory of the previous live run (non-empty; normally `C:\KenshiTestRuns\imm26-<lane>\rows\<row>\`; a path containing selftest/fake/scratch/tmp/fixture is refused). The fix must be replayed against it OFFLINE (the rowtools checker/recipe run on that directory) before any live rerun; put the replay command and its result line in the handback. A selftest on an invented scene does not count (the 23-a lesson).
3. **Cap 3.** The 4th and later gated agent for a row needs `[case:escalate]` plus a line `ESCALATE: <why the earlier attempts failed>` and a line `METHOD-QUESTION: <the different approach, already sent to Shay's relay with a speed estimate>` (CLAUDE.md: a work item at 2+ rounds or > 1 h questions the METHOD).
4. **Not gated (recorded only):** lane operators (`<rig>-i<N> operator ...`, name `...-<rig>-i<N>op<N>`), readers (`check/read/parse`), `bench`/`grade` (ab2 arms like `ab2-sonnet-02-ax`), calls with no row id, sweeps naming > 4 rows. Operators are the live replay, not rework; their cost is cut #2.
5. `rowgate.ps1 close <row> PASS` ends the round (next agent is attempt 1 again). `seed` closes rows whose table verdict is PASS.

## Escape tag
`[rowgate:skip <why>]` in the description (or the first 600 chars of the prompt) lets the call through. The reason is mandatory (`[rowgate:skip]` alone is denied), the attempt is still recorded, and the line goes to `C:\KenshiTestRuns\rowgate\skips.log` (reviewed at handoff; use for a typo fix, a tooling change that is not the row's failure, never to dodge the cap).

## Row detection and false positives
Regex `(?<![\w.])\d{2}-[a-z]x?(-neg)?(?!\w)`, case-insensitive: matches `26-a`, `15-bx`, `02-dx`, `13-c-neg`, `15-bx-op9o`; not `24-bit`, `30-min`, `2026-10-16`, `4080-i3`, `NC33`. Description first; the prompt is only searched (first 300 chars) when the description names no row. A wrong match: add `[rowgate:skip not a row id: <text>]`; a missed row: name it in the description. `python -I rowgate.py rows "<description>"` shows what the detector sees. Calls the detector cannot parse never block (internal error = allowed and logged in `rowgate\gate.log`, like the router).

## Tools
- `powershell -NoProfile -File tools\automation\rowgate.ps1 status [row]` (per-row table; with a row: every attempt, report paths, replay-evidence candidates, what the next agent needs), `add`, `done <row> <name> [outcome]`, `close <row> [outcome]`, `cost <row> <name> <usd>`, `seed`, `rows <text>`.
- Ledger `C:\KenshiTestRuns\rowgate\<row>.json` (attempts: name, role, case, state, started/ended, report, prev_report, evidence, different, outcome, cost, agentId, skipped), `gate.log`, `skips.log`. Seeded 2026-10-16 from `agents\*.status` (159 entries, 28 PASS rows closed).
- Code: `tools/automation/rowgate.py` (logic), `rowgate.ps1` (CLI), `hooks/rowgate-guard.ps1` (PreToolUse Agent, deny only, never rewrites the input so it cannot clash with `agent-router.ps1`), `hooks/rowgate-post.ps1` (PostToolUse Agent), selftest `tools/automation/rowgate-selftest.ps1` (PASS 47/47).

## Coordinator brief template (attempt 2+)
```
[case:patch] <name> <row> <what>
...
PREV-REPORT: C:\KenshiTestRuns\agents\out\<prev>\latest.md
WHAT IS DIFFERENT THIS TIME: <the new idea / the evidence that changes the plan>
REPLAY-EVIDENCE: C:\KenshiTestRuns\imm26-<lane>\rows\<row>
Replay the fix against REPLAY-EVIDENCE offline first (rowtools checker / recipe dry run), paste the result line, only then ask for a live rerun.
```

## Operator rule (lane brief)
An operator that marks a row SETUP-FAIL or FAIL must put `evidence <dir>` (the lane evidence directory, e.g. `C:/KenshiTestRuns/imm26-5090-i3/rows/23-a/`) in the ticket reason / `pilot-mark.sh` line and keep that directory unswept; the fixer replays it. `rowgate.ps1 status <row>` lists the ticket's `evidence <dir>` and every `imm26-*/rows/<row>` directory as candidates. Proposed lane-brief line: see `inbox\operators\cut1.txt`.
