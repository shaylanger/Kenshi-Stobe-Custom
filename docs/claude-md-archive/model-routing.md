# Model routing and validation (2026-10-14/15)

Read before: spawning a subagent or changing models.
Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.

<!-- original CLAUDE.md line 61 -->
- The coordinator runs Sonnet high (`.claude/settings.json`: `model`, `effortLevel`; Shay 2026-10-15, from the 36-run model test: close to Opus medium in quality and time at about half the cost; switch to Opus medium if it makes mistakes). Pick the model when a session starts; don't switch it mid-session (it can invalidate the prompt cache). Takes effect on the next new session.
- Every subagent gets its tier's model and effort from `tools/automation/model-policy.json` (the Agent router hook). Start each Agent description with `[case:<name>]` (`[ticket:<id>]` is optional, ledger only). Tiers (from the 36-run model test, 2026-10-15; no Haiku and no Sonnet medium anywhere): `kenshi-reader` (Sonnet high), `kenshi-generator` (Sonnet high), `kenshi-debugger` (Sonnet xhigh), `kenshi-escalation` (Opus medium), `kenshi-grader` (Sonnet high: `grade` scores two finished outputs blind and writes a grade file).
- No cascade (Shay 2026-10-15): one agent on the right model does the task. There is no verifier step, no verdict files, no FAIL gates and no Stop gate; cheap-model-then-verify was slower and scored lower than one better-model run. Run the mechanical checks (tests, RESULT lines, lab checks) yourself and judge the result.
- Model comparison tests (more prompts, other models): runbook `docs/MODEL_TEST.md`, tool `tools/model-test/mt.py`, first results `docs/model-test/2026-10-15-investigation-suite/`.
- Investigate first: a bug or a behaviour that should not happen goes to `[case:investigate]` (Sonnet xhigh). Act on its proposal after checking its evidence lines against the code.
- On a failed attempt: retry the generator with the failure text (up to 3 times), then `debug`, then `escalate` (Opus medium) for a hard problem. The router no longer gates any of these.
