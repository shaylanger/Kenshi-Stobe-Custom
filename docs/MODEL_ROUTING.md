# Model routing (Kenshi workspace)

Set 2026-10-14 from Shay's cost reasoning. Enforced by `tools/automation/hooks/agent-router.ps1` (every Agent call) and `tools/automation/event-sweep.sh` (verdicts). Policy: `tools/automation/model-policy.json`. Agent roles: `.claude/agents/kenshi-*.md`.

## Prices

Per prompt, from Shay's table. These are guesses until the ledger measures real usage.

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
| kenshi-debugger | Sonnet high | debug (diagnosis, then verified) |
| kenshi-escalation | Opus medium | escalate, after the cascade fails |

Coordinator: Sonnet medium, set in `.claude/settings.json` (`model`, `effortLevel`). Choose the model when a session starts. Changing model or effort mid-session can invalidate the prompt cache, so start a new session for a different tier.

## Cascade for one ticket

1. Generator, up to 3 attempts, each with the previous failure text. The mechanical checks (tests, RESULT lines, lab checks) decide each attempt.
2. Verifier. Evidence first. It writes `C:\KenshiTestRuns\verdicts\<ticket>.txt`, whose first word is PASS or FAIL, and judges only what scripts cannot.
3. On FAIL: `debug` (the router needs a FAIL verdict first), then one more generator attempt with the diagnosis, then the verifier again.
4. Still FAIL: `escalate` (Opus medium) with the full ticket history. The router needs a debug round on the ticket and a FAIL verdict written after it.

A change counts only after a PASS verdict backed by evidence. The sweep flags a work ticket (patch, generate, debug or escalate) from the last 6 h that has no verifier call after its last work row, or a verdict that is missing, not PASS, older than that call, or citing fewer than two existing evidence paths.

Automatic at turn end: the Stop gate (`tools/automation/hooks/cascade-gate.ps1`) keeps the cascade going. When a work ticket's next step is missing, it blocks the coordinator from ending its turn and names the Agent call to make: a verifier after a generator or escalation, a debugger after a FAIL, a generator after a debug round. It reads the coordinator's transcript for each subagent's task-notification, so it acts only on finished runs; a ticket with a run still going is skipped. It fails open when `transcript_path` is missing. The log `C:\KenshiTestRuns\ledger\cascade-gate.log` shows whether that path arrives.

Not automatic: nothing stops the coordinator from editing code itself. A direct edit is not an Agent call, so neither the router nor the gate sees it. Blocking direct edits would also block the generator's own edits, unless the hook can tell the coordinator's calls from a subagent's. That is not confirmed.

Why scripts first: at the table's prices a Sonnet medium verifier ($0.40) costs 8x a Haiku max generator ($0.05). One attempt plus a verifier costs $0.45, and three attempts plus a verifier cost $0.55, so the cascade costs more than Sonnet medium alone. It saves only against Sonnet high or Opus ($0.55 or more), or when scripts replace the verifier call. Up to 3 Haiku retries still cost less than one Sonnet medium prompt ($0.15 against $0.40), so retries are cheap and the verifier call is the expensive step. Script-only verdicts are not built yet.

## Tags and the router

- The Agent description starts with `[case:<name>]`. `patch`, `generate`, `debug`, `escalate`, `verify`, `judge` and `review` also need `[ticket:<id>]`.
- The router denies: a call with no case unless it is kenshi-reader; an unknown case; a case that doesn't match the subagent_type it names; a case without its required ticket; `debug` without a FAIL verdict for its ticket; `escalate` without a debug round on its ticket and a FAIL verdict written after it.
- Otherwise it rewrites model and effort to the tier's values. Any model or effort the coordinator passed is overridden, and the ledger records the override.
- If the router crashes, the call goes through unrouted, the ledger records an error row, and the sweep reports it.

## Ledger and measurement

Every Agent call writes one line to `C:\KenshiTestRuns\ledger\agent-calls.tsv`:
time, case, ticket, subagent_type, model, effort, action (allow, override, deny or error), description.

Every Agent call that runs also writes one line to `C:\KenshiTestRuns\ledger\agent-runs.tsv`: time, agentId, output_file (its transcript), case, ticket, subagent_type, model, effort. `python3 tools/automation/ledger-report.py` (run in WSL) adds up each run's tokens from its transcript and prints them per case, model and effort, plus the verdict per ticket. Tune the table from that report, not from the guessed prices.

The subagent sees the routing facts in the first line of its prompt (`Routing: case=... tier=... ticket=...`), because it does not see the description.

## Not enforced

- Retry limits (3 generator attempts, one debugger round) are documented, not enforced by the router.
- The verifier's judgement. The sweep checks that a verdict exists, starts with PASS, is newer than the verifier call and cites two evidence paths that exist. It does not check that the evidence supports the verdict, so a model can still write a false PASS.
- The chain is only as honest as the ledger. The router writes it; nothing checks it against the transcripts, so a model that edits the ledger or the verdict files by hand can fake the chain.
- Script-only verdicts (no verifier call when scripts can judge) are not built.
- The Kenshi waker guard Stop and PreToolUse hooks were not registered in any settings file on 2026-10-14. CLAUDE.md "Stay reachable" describes what they should do.
- The user-level default model is `opus` (`C:\Users\Shay\.claude\settings.json`). This project overrides it to sonnet.
