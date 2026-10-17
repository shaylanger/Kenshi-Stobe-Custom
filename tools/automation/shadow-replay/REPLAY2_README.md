# replay2: Haiku pair / Draft-review / Guard rails on the 120 offline coordinator points (Shay 2026-10-16)

Builds on the stage-1 replay (`docs/COORD_SHADOW_PLAN.md`, `C:\KenshiTestRuns\shadow\replay\README.md`). Baselines (measured, NOT repeated): Haiku alone 38% agreement / 69 worse / 5 harmful, $0.81, 14.0M tokens; Sonnet alone 74% / 27 worse / 4 harmful, $11.78, 13.3M tokens. All tools: `C:\KenshiModding\tools\automation\shadow-replay\` (Windows python, `python -I`). Data: `C:\KenshiTestRuns\shadow\replay2\` (not committed).

## The three arms
1. **HAIKU PAIR** (real communication, not "independent runs then compute"). All steps Haiku High, tool-less (one Read + one Write each), schema identical to the replay ledger (`event_class`, `decision[]`, `checks[]`).
   - R1: agents `P###-pa1` and `P###-pb1` each decide the point (same input as the baseline Haiku run).
   - R2: `P###-pa2` / `P###-pb2` each get the input plus BOTH R1 decisions ("YOUR first decision" / "YOUR COLLEAGUE's first decision", no model labels) and write a revised decision plus `peer_note` ("agree:/disagree: why").
   - R3: `P###-pc3` only if the two R2 decisions still differ in actions (compare = sorted set of (action type, primary target: alert/agent/lane/row/script; ignore/wait collapsed), `replay2_common.differ`): one Haiku reconciler sees both R2 decisions and writes the final. Else final = the common decision (agent a's R2).
   - Missing step fallbacks (flagged in `cands.jsonl` meta.fallback): R2 missing -> that agent's R1; R3 missing -> a's R2.
2. **DRAFT-REVIEW**: draft = the existing Haiku-alone decision `replay\runs\ra\P###.json` (its cost from `replay\runs.tsv` is added to the arm: "draft cost + review cost"). One Sonnet High agent `P###-dr` gets the full input + the draft + the review rules (check each action against the input; remove duplicates of already-done actions; add missed required actions; fix invented targets; do not rewrite correct parts) and writes the final decision (plus a `review_note`, stripped from the final).
3. **GUARD RAILS**: Haiku High `P###-gr` alone. `replay2_guard.done_block` builds an "ALREADY DONE" list from the point's own preceding conversation (agents spawned, alerts/agents acked or abandoned, messages sent incl. tail-relay, commits/pushes, wakers/monitors started, files edited, other mutating commands) and injects it before the final instruction. After the run `replay2_guard.filter_decision` REJECTS every action that names an agent, alert, lane, row or file that does not occur in the point input (kinds: agent, alert, lane, row, path; plus forbidden-target = a write to Shay's live install/saves/server tree via `shadow_validate.FORBIDDEN`). A `spawn` may introduce a new agent name; `edit-file`/`commit` may too. Absolute paths that exist on disk, and new data/doc files inside an existing folder, are not "invented" (same rule as `grade.check_paths`). Each rejection is logged in `guard-log.jsonl` (point, action index, kind, token, text); an empty result becomes one `wait` action. No second model.
   - Calibration (printed in aggregate.md): the same filter applied to the REAL coordinator's actions rejects about 56 of 251 (22%), because the abridged input does not show every id the real coordinator knew. So a rejection is a "not in the point input" signal, not proof of an invented id; the "missed" column shows what it cost.

## Files
- `replay2-run.py`: `plan` (job files in `jobs\`, plan files `plan\batch-<round>-NN.json`, <= 20 runs, rounds r1 r2 r3 dr gr; r2 needs both R1 outputs, r3 only for points whose R2 decisions differ), `collect` (transcripts matched by the `replay-run: <rid>` marker, tokens in/out/cache-w/cache-r + API-equivalent USD via pilot-rowcmp/cost-audit/prices.json = same method as the baselines, all attempts of a rid counted, grader transcripts -> `graders.tsv`), `status`, `retry`, `finalize` (`final\<arm>\P###.json`, `cands.jsonl` = one candidate per arm per point, `guard-log.jsonl`), `aggregate-cost` (`cost.json`, `cost.md`, `cost-points.csv`: per point and per arm; wall = critical path and sum of calls).
- `replay2-grade.py`: `mech` (grade.py `mech_one` on the finals: bash/PowerShell syntax, forbidden targets, invented paths, claims, briefs, missed/extra) and `packets --chunk 8` (blind A/B/C candidates, order random per point, same rubric and harm-gate text imported from grade.py; secret `grading\key.json`).
- `replay2-aggregate.py`: `aggregate.md` = comparison table incl. the baselines (read from `replay\aggregate.md`), tokens/USD/time per arm, per-class tables and agreement matrix, per-class verdict, pair protocol stats, draft-review change rate, guard-rails rejections.
- `replay2_common.py`, `replay2_guard.py` (libraries), `replay2-selftest.py` (offline selftest in a temp root: `python -I replay2-selftest.py`).
- `EXECUTOR2_PROMPT.md`: the prompt for ONE executor agent (imm26-hpairexec).

## Run order and counts
Fresh start: r1 240 runs (12 batch files), gr 120 (6), dr 120 (6), r2 240 (12), r3 about 30-70 (2-4), graders 15 (120 points / 8). The executor issues R1 batches together with one independent batch each (<= 40 calls per message), then R2, then R3: about 27 messages of agent calls.

## Cost estimate (API-equivalent; basis: baseline runs.tsv Haiku run $0.0067 / 117k tokens, Sonnet run $0.098 / 111k tokens, mostly cached context)
| item | calls | USD |
|---|---|---|
| pair R1 | 240 Haiku | 1.6 |
| pair R2 (input + two decisions, ~+20% tokens) | 240 Haiku | 1.8 |
| pair R3 (assume 50 of 120 points) | 50 Haiku | 0.4 |
| guard rails | 120 Haiku | 0.8 |
| draft-review (Sonnet review, input + draft) | 120 Sonnet | 12.6 |
| draft-review draft (already measured, counted in the arm) | 120 Haiku | 0.8 (not new spend) |
| 15 graders, 3 candidates per point (~80 KB packets, ~$0.5 each) | 15 Sonnet | 7.5 |
| **New spend** | about 785 agent calls + 15 graders | **about $24.7** (range $22-28) |
Arm totals expected: pair about $3.9 (about 4.5 calls and about 0.5M tokens per point), guard rails about $0.8, draft-review about $13.4 (draft + review). Wall time: about 27 messages x 1.5-3 min ~ 60-90 min, plus graders ~10 min. Executor itself: ~150-250k tokens (1-2 sessions) on a cheap model, not included above (a few $0.1 on Haiku/Sonnet cache reads).

## Caveats
- Same as stage 1: replay agents see today's CLAUDE.md, have no tools beyond one Read + one Write, inputs are abridged, outcome labels are a heuristic.
- The new arms are graded in one blind run (3 candidates per packet); the baselines were graded earlier by 15 other graders, so a small grader drift between the two runs is possible; per-arm numbers are comparable but not paired.
- Pair/draft-review/guard-rails differ from the baselines in prompt as well as in protocol (R1 and GR jobs add a runner instruction at the end of the input file; GR adds the already-done block).
