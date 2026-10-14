# Model routing (Kenshi workspace)

Set 2026-10-14 from Shay's cost reasoning. Enforced by `tools/automation/hooks/agent-router.ps1` (every Agent call) and `tools/automation/event-sweep.sh` (verdicts). Policy: `tools/automation/model-policy.json`. Agent roles: `.claude/agents/kenshi-*.md`.

## Prices

Two price sets, both printed by `tools/automation/ledger-report.py`:
- **Official** (`token_$`): the per-million-token rates in `tools/automation/prices.json`, from the [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing), read 2026-10-14. Each message is priced at its own model, its own prompt size and its own cache-write time (5 min or 1 h).
- **Table** (`table_$`): Shay's guess per call, below. Kept for comparison only.

Official rates, USD per million tokens (standard routing, no Batch API, no fast mode):

| Model | Input | Output | Cache read | Cache write 5 min | Cache write 1 h |
|---|---|---|---|---|---|
| Haiku 5.5, prompt up to 100k tokens | $0.10 | $0.50 | $0.01 | $0.125 | $0.20 |
| Haiku 5.5, prompt over 100k tokens | $0.50 | $2.50 | $0.05 | $0.625 | $1.00 |
| Sonnet 5.5 | $2.00 | $10.00 | $0.10 | $2.50 | $4.00 |
| Opus 5.5 | $4.00 | $20.00 | $0.20 | $5.00 | $8.00 |

- The page does not say whether the over-100k Haiku rate covers the whole prompt or only the tokens above 100,000. The report bills the whole prompt at it, which is the higher reading.
- Above 100k prompt tokens the Haiku gap to Sonnet shrinks from 20x to 4x on input and output, and from 10x to 2x on cache reads.
- Sonnet and Opus have no size band.

Table (Shay's guess per call, $ per prompt):

| Effort | Haiku 5.5 | Sonnet 5.5 | Opus 5.5 |
|---|---|---|---|
| Low | $0.015 | $0.30 | $0.60 |
| Medium | $0.020 | $0.40 | $0.80 |
| High | $0.0275 | $0.55 | $1.10 |
| Extra High | $0.0375 | $0.75 | $1.50 |
| Max | $0.050 | $1.00 | $2.00 |

What the table says:
- Model tier is the big lever. Sonnet is 20x Haiku at every effort, and Opus is 2x Sonnet.
- Effort moves cost about 3.3x from low to max, within any model.
- Haiku at max ($0.05) is cheaper than Sonnet at low ($0.30).
- Opus at low ($0.60) costs about what Sonnet at high ($0.55) does. Sonnet at max ($1.00) costs more than Opus at medium ($0.80). So the top escalation rung is Opus, not Sonnet at max.

## Tiers

| Tier | Model and effort | Used for |
|---|---|---|
| kenshi-reader | Haiku low | read, parse, check |
| kenshi-generator | Haiku max | patch, generate (output must be verified) |
| kenshi-verifier | Sonnet medium | verify, judge, review (writes the verdict) |
| kenshi-debugger | Haiku max | investigate (root cause and proposed fix); debug (after a FAIL) |
| kenshi-escalation | Opus medium | escalate, after the cascade fails |
| kenshi-solo | Sonnet medium | solo: benchmark baseline only, never for real work |
| kenshi-grader | Sonnet high | grade: scores two finished outputs of one task blind to which arm made which; writes a grade file, not a verdict |

Coordinator: Sonnet medium, set in `.claude/settings.json` (`model`, `effortLevel`). Choose the model when a session starts. Changing model or effort mid-session can invalidate the prompt cache, so start a new session for a different tier.

## Cascade for one ticket

Investigation first: a report of a bug or of a behaviour that should not happen (for example, an NPC that said it would do something and did not) goes to `investigate` (kenshi-debugger, Haiku max). Its proposal (the root cause, the evidence lines with file and line, what was ruled out, the smallest fix, and the proof check) goes to a verifier (Sonnet medium), which checks the evidence and the proof check. Only a PASS sends the fix to a generator, and the generator's change then goes to a verifier too.

Once a fix is in, the steps below apply.

1. Generator, up to 3 attempts, each with the previous failure text. The mechanical checks (tests, RESULT lines, lab checks) decide each attempt.
2. Verifier. Evidence first. It writes `C:\KenshiTestRuns\verdicts\<ticket>.txt`, whose first word is PASS or FAIL, and judges only what scripts cannot.
3. On FAIL: `debug` (the router needs a FAIL verdict first), then one more generator attempt with the diagnosis, then the verifier again.
4. Still FAIL: `escalate` (Opus medium) with the full ticket history. The router needs a debug round on the ticket and a FAIL verdict written after it.

A change counts only after a PASS verdict backed by evidence. The sweep flags a work ticket (patch, generate, debug, escalate or investigate) from the last 6 h that has no verifier call after its last work row, or a verdict that is missing, not PASS, older than that call, or citing fewer than two existing evidence paths.

Automatic at turn end: the Stop gate (`tools/automation/hooks/cascade-gate.ps1`) keeps the cascade going. When a work ticket's next step is missing, it blocks the coordinator from ending its turn and names the Agent call to make: a verifier after a generator or escalation, a debugger after a FAIL, a generator after a debug round. It reads the coordinator's transcript for each subagent's task-notification, so it acts only on finished runs; a ticket with a run still going is skipped. It fails open when `transcript_path` is missing. The log `C:\KenshiTestRuns\ledger\cascade-gate.log` shows whether that path arrives.

Not automatic: nothing stops the coordinator from editing code itself. A direct edit is not an Agent call, so neither the router nor the gate sees it. Blocking direct edits would also block the generator's own edits, unless the hook can tell the coordinator's calls from a subagent's. That is not confirmed.

Why the split can save money: each call is one unit at the table's prices: Haiku max $0.05, Sonnet medium $0.40. Investigating alone on Sonnet medium costs n × $0.40 for n calls. Haiku investigating and Sonnet validating costs n × $0.05 + v × $0.40 for v validation calls. The split is cheaper once n is more than about 1.14 × v: from 2 investigation calls with 1 validation call, from 3 with 2. Even if Haiku needs three times as many calls, the split still wins once n is about 1.6 × v. A one-call task is cheaper on Sonnet alone, because the validation call adds cost and saves nothing. Long runs cost more than the table shows, because every call re-reads the conversation so far, so a short validation package saves more than the table does. Script checks can replace the verifier for mechanical claims, which cuts the validation cost further. That is not built yet.

## Tags and the router

- The Agent description starts with `[case:<name>]`. `patch`, `generate`, `debug`, `escalate`, `investigate`, `solo`, `verify`, `judge`, `review` and `grade` also need `[ticket:<id>]`.
- The router denies: a call with no case unless it is kenshi-reader; an unknown case; a case that doesn't match the subagent_type it names; a case without its required ticket; `debug` without a FAIL verdict for its ticket; `escalate` without a debug round on its ticket and a FAIL verdict written after it.
- Otherwise it rewrites model and effort to the tier's values. Any model or effort the coordinator passed is overridden, and the ledger records the override.
- If the router crashes, the call goes through unrouted, the ledger records an error row, and the sweep reports it.

## Ledger and measurement

Every Agent call writes one line to `C:\KenshiTestRuns\ledger\agent-calls.tsv`:
time, case, ticket, subagent_type, model, effort, action (allow, override, deny or error), description.

Every Agent call that runs also writes one line to `C:\KenshiTestRuns\ledger\agent-runs.tsv`: time, agentId, output_file (its transcript), case, ticket, subagent_type, model, effort. `python3 tools/automation/ledger-report.py` (run in WSL) adds up each run's calls and tokens from its transcript, per case, model and effort, with `table_$` (calls × table price per call) and `token_$` (the official rates above). With `--main`, `--window-start` and `--window-end` it also counts the coordinator's own turns in that window, since those wake up for every subagent and cost too. The window is on the Windows clock, the ledger's clock. WSL runs in another zone (America/Chicago), so the transcript times are converted with the Windows UTC offset, read from powershell.exe; `--utc-offset=-06:00` overrides it. To compare arms, run each in a fresh session so the coordinator's context is the same size.

The subagent sees the routing facts in the first line of its prompt (`Routing: case=... tier=... ticket=...`), because it does not see the description.

## Not enforced

- Retry limits (3 generator attempts, one debugger round) are documented, not enforced by the router.
- The verifier's judgement. The sweep checks that a verdict exists, starts with PASS, is newer than the verifier call and cites two evidence paths that exist. It does not check that the evidence supports the verdict, so a model can still write a false PASS.
- The grader's judgement. A grade is a gauge: one model judges two outputs, and models can favour length or the first output. Grade twice with the labels swapped to see the position effect. Shay's accept or reject is the ground truth.
- The chain is only as honest as the ledger. The router writes it; nothing checks it against the transcripts, so a model that edits the ledger or the verdict files by hand can fake the chain.
- The break-even assumes each call is one price unit from the table. The report does not measure quality: the verifier's verdict and your judgement are the checks.
- Script-only verdicts (no verifier call when scripts can judge) are not built.
- The Kenshi waker guard Stop and PreToolUse hooks were not registered in any settings file on 2026-10-14. CLAUDE.md "Stay reachable" describes what they should do.
- The user-level default model is `opus` (`C:\Users\Shay\.claude\settings.json`). This project overrides it to sonnet.
