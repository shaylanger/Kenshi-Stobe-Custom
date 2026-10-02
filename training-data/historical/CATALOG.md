# Historical Training / Evaluation Sources

This catalog points to existing project records that are useful for future model training and evaluation.

## Curated gameplay/test labels

- `../../archive/STOBE_bug_history_old_numbers.md`: numbered bugs (old numbering, closed), fixes, and known behavior failures. Excellent negative-example source.
- `../../STOBE_full_test_plan.md`: current/open regression scenarios and expected behavior.
- `../../archive/test-run-2026-09-30.md`: first detailed automated/live gameplay run.
- `../../archive/test-run-2026-09-30-r2.md`: second run and discovered regressions.
- `../../archive/test-run-2026-09-30-r3.md`: third run.
- `../../archive/test-run-2026-09-30-r4.md`: fourth run, including later work/task-goal testing.

These reports should be treated as labels around actual gameplay, not as replacement for raw prompts/logs.

## Design and investigation context

- `../../archive/STOBE_minime_topic_findings_brief_2026-09-30.txt`: MiniMe/topic latency and quality findings.
- `../../archive/STOBE_trade_intent_polling_latency_context_2026-09-30.txt`: trader polling latency investigation.
- `../../archive/STOBE_negotiation_phase1_completion_plan.md`: negotiation implementation/verification plan.
- `../../archive/STOBE_negotiation_test_guide.md`: negotiation test scenarios and expected outcomes.
- `../../archive/two-pc-setup.md`: historical deployment context.
## Regression and fix provenance

- `../../pending-fixes/`: patch scripts for server, STOBE DLL, and KenshiFP regression rounds.
- `../../pending-fixes/negotiation_round6_regression.php`: explicit negotiation regression coverage.
- `../../pending-fixes/r15_unit.php` and `r15_unit2.php`: later negotiation unit cases.
- `../../components/STOBE/`: native STOBE source snapshot at the preserved baseline.
- `../../components/KenshiFP/`: KenshiFP source snapshot at the preserved baseline.

Patch scripts are useful for understanding exactly what rule changed after a failure and can help turn bugs into before/after training examples.

## Raw historical evidence

- `server-log-archives/`: compressed server logs preserved from the old rotating log system.
- `server-log-snapshots/`: snapshot of current server logs taken when permanent capture was introduced.

Important log types include:
- `context_sent_to_llm.log`: prompts/context assembled for LLM calls.
- `audit_request.log`: request/result metadata and provider usage.
- `output_from_llm.log`: raw model output/timing.
- `output_to_plugin.log`: responses/actions sent game-side.
- `stobeserver.log`: detailed events, validation, negotiation, actions, and timing.

When reconstructing an old example, correlate timestamps, NPC name, player text, request IDs where available, and the matching test-run/bug entry.
