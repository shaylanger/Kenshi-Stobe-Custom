# Model routing (Kenshi workspace)

Set 2026-10-14, revised 2026-10-15 from the 36-run model test. Enforced by `tools/automation/hooks/agent-router.ps1` (every Agent call); `tools/automation/event-sweep.sh` reports router errors. Policy: `tools/automation/model-policy.json`. Agent roles: `.claude/agents/kenshi-*.md`.

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
| kenshi-reader | Sonnet high | read, parse, check |
| kenshi-generator | Sonnet high | patch, generate |
| kenshi-debugger | Sonnet xhigh | investigate (root cause and proposed fix), debug |
| kenshi-escalation | Opus medium | escalate: one hard problem, or when an earlier attempt failed |
| kenshi-grader | Sonnet high | grade: scores two finished outputs of one task blind to which arm made which; writes a grade file |
| kenshi-bench | from tags | bench: `[model:x] [effort:y]` tags set model and effort (benchmarks only; Fable is never allowed) |

There is no Haiku tier and no Sonnet medium tier. There is no cascade: one agent on the right model does the task, with no verifier step, no verdict files and no FAIL gates.

**Why (2026-10-15, 36-run test: 3 models x low/medium/high/xhigh x 3 investigation prompts, two blind judges; results in `C:\KenshiTestRuns\invest\suite2\FULL_TABLE.md`):** quality out of 25, mean of both judges. Haiku low/medium/high 14.7/15.3/19.0 and Sonnet low/medium 14.3/17.3 were not good enough (each dropped below 20 on at least one prompt). Only Sonnet xhigh (24.7, $1.39, 9.4 min, 0 false claims), Opus medium (22.7, $1.09, 4 min), Opus xhigh (22.8, $3.78) and Haiku xhigh (22.3, $0.74, 10.7 min) scored 20 or more on every prompt; Sonnet high averaged 21.3 ($0.66, 4.4 min) but scored 19.5 on one prompt. Haiku xhigh has no edge over Sonnet or Opus at that time and cost, so Haiku is not used. Opus above medium bought nothing. The old cascade (Haiku investigates, a better model verifies) scored 21.5 for $1.11 in 19 min, worse and slower than one Opus medium run (22.7, $1.09, 4 min) or one Sonnet xhigh run, so it was removed. The measured task was diagnosis; the generator and reader rows are judgement calls from that data, not measured. Revisit after a few real tasks. To run more comparisons (more prompts or models): `docs/MODEL_TEST.md`.

Measured agent runs cost $0.70 to $4 per task, far above the per-call table in the Prices section, which is kept only as a price reference.

Coordinator: Sonnet high (Shay 2026-10-15: close to Opus medium in quality and time at about half the cost, and the coordinator sends many messages; switch to Opus medium if it makes mistakes), set in `.claude/settings.json` (`model`, `effortLevel`). Choose the model when a session starts. Changing model or effort mid-session can invalidate the prompt cache, so start a new session for a different tier.

## Tags and the router

- The Agent description starts with `[case:<name>]`. A `[ticket:<id>]` tag is optional and is only written to the ledger.
- The router denies: a call with no case unless it is kenshi-reader; an unknown case; a case that doesn't match the subagent_type it names; a `bench` call without valid model and effort tags.
- Otherwise it rewrites model and effort to the tier's values. Any model or effort the coordinator passed is overridden, and the ledger records the override.
- If the router crashes, the call goes through unrouted, the ledger records an error row, and the sweep reports it.

## Ledger and measurement

Every Agent call writes one line to `C:\KenshiTestRuns\ledger\agent-calls.tsv`:
time, case, ticket, subagent_type, model, effort, action (allow, override, deny or error), description.

Every Agent call that runs also writes one line to `C:\KenshiTestRuns\ledger\agent-runs.tsv`: time, agentId, output_file (its transcript), case, ticket, subagent_type, model, effort. `python3 tools/automation/ledger-report.py` (run in WSL) adds up each run's calls and tokens from its transcript, per case, model and effort, with `table_$` (calls × table price per call) and `token_$` (the official rates above). With `--main`, `--window-start` and `--window-end` it also counts the coordinator's own turns in that window, since those wake up for every subagent and cost too. The window is on the Windows clock, the ledger's clock. WSL runs in another zone (America/Chicago), so the transcript times are converted with the Windows UTC offset, read from powershell.exe; `--utc-offset=-06:00` overrides it. To compare arms, run each in a fresh session so the coordinator's context is the same size.

The subagent sees the routing facts in the first line of its prompt (`Routing: case=... tier=... ticket=...`), because it does not see the description.

## Not enforced

- Retry limits are not enforced by the router.
- Nothing stops the coordinator from editing code itself: a direct edit is not an Agent call, so the router does not see it.
- The grader's judgement. A grade is a gauge: one model judges two outputs, and models can favour length or the first output. Grade twice with the labels swapped to see the position effect. Shay's accept or reject is the ground truth.
- The ledger is written by the router; nothing checks it against the transcripts.
- The Kenshi waker guard Stop and PreToolUse hooks were not registered in any settings file on 2026-10-14. CLAUDE.md "Stay reachable" describes what they should do.
- The user-level default model is `opus` (`C:\Users\Shay\.claude\settings.json`); this project overrides it to sonnet high.
