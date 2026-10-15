# Profession Gear (PG), finished

Read only if PG balance work is ever reopened.
Moved verbatim from CLAUDE.md (original line numbers in the comment before each block). Nothing here is paraphrased.

<!-- original CLAUDE.md line 32 -->
- **PG validation gate (Shay, 2026-10-04; PG is finished, Shay 2026-10-10: applies only if PG balance work is ever reopened):** before any full PG measurement matrix, run 3 control points on the same fixture and method: low skill/no gear, high skill/no gear, low skill/gear. Each must prove the action really ran (worker awake at the right bench, materials in its input inventory, kit present, observer/target stable, game time advancing) and record elapsed game time, start/end state and native evidence (a failed command must never leave a stale value). Flat results aren't an automatic fail: decide real game behavior vs broken measurement and write it down. Gate fails → classify (setup / measurement / product / unresolved balance), fix, rerun only the gate. Track "gear applies correctly" (mechanical pass) separately from "balance curve accepted". Report one gate line per profession. Only one runner per machine: record runner, machine owner and output/checkpoint paths in `testing/HANDOFF.md` "Right now" so a successor resumes it instead of starting a second one.
<!-- original CLAUDE.md line 55 -->
- **PG:** finished standalone mod (development done, Shay 2026-10-10); its only home is the repo `C:\KenshiModding\Kenshi-Profession-Gear-Progression` (plan `TEST_PLAN.md`, status `INGAME_STATUS.md`, run order `tests/ingame/RUN_ORDER.md`).
