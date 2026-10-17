# 06 - Open questions, untested areas, method defects, how to extend

Read `01-overview.md` section 9 first (what is not conclusive). This file lists what has NOT been tested, what is wrong or weak in the method, and how to extend the suites. Nothing here is a result.

## 1. Untested areas (no data exists)
| area | why it matters | cheapest way to test |
|---|---|---|
| Other model families (no result for any non-Claude model; the Codex matrix is prepared, 88 runs, never run) | the package is built for "model X", but only two Claude models were ever scored on the replay | `05-runbook-new-model.md` on the replay (120 calls + 15 grader calls); start with 30 points if cost matters and say it is a subsample |
| Low, medium and xhigh effort on the replay | the replay only used "high" for both arms; the investigation suite shows effort moves quality more than model does (15.7 to 23.3 from low to xhigh) | run the same 120 points at another effort; same blind packets against arm S |
| The strong model at a LOWER effort than "high" as a cheaper option | may close most of the cost gap without changing model | as above |
| Cheap model as the GRADER or as a mechanical reader of files | a cheap grader would cut the grading cost; never tested | grade the 15 baseline chunks twice, once with the cheap and once with the strong model, compare grade agreement |
| Different graders for the same candidates | all replay baselines were graded by one strong model of the same family as one arm; a grader from another family might rank differently | re-grade the 15 shipped baseline packets (`data/replay/grading/chunk-*.md`) with another grader and compare per-point agreement with the shipped grades |
| Repeat runs of the same model on the same point (sampling noise) | the method uses one run per cell and treats differences under about 8 points as noise on the strength of the sample size, not on a measured run-to-run variance | run 20 points 5 times at a fixed setting and measure how often the decision class flips |
| Held-out points | all replay2 variants were designed after seeing failures on these same 120 points | build a new set (section 4) and score the best variant there once |
| Hybrid routing in a live system (cheap model for the easy classes, strong for the rest) | the only candidate class (stop-hook feedback) is a one-point gain at n = 14 | a live shadow of 15 or more stop-hook events, or 60 offline points of that class |
| Code-editing or long tool-using tasks | the suites test decisions as text and read-only investigations; no code was changed by a model under test | a task suite with per-run copies of the repository and automatic tests as the grader |
| Newer versions of the same models | models change under the same name | re-run with `05`, compare with the shipped S arm in the same packets |
| Latency under real conditions | wall times were measured with 20 parallel agents and an agent harness | single-call timing on your own setup |

## 2. Method defects (weaknesses of what was done)
These are the same facts as `02` section 10 and `01` section 9, stated as to-dos:
1. One reference per point, and the reference was wrong on 9 of 120 (graders' verdict). Fix: add a second reference (an independent expert or a strong-model consensus) and score against both, or grade without a reference on "would this be safe and sufficient".
2. Agreement is graded by a language model with a text rubric. Fix: add a small human-graded sample (for example 20 points, both arms, blind) to calibrate the grader; report grader-vs-human agreement.
3. The harm gate is local to one project (clauses a-i name its live system, its held work areas, its handoff steps). Fix for reuse: rewrite the nine clauses for the target system before the first grading (`02` 7.3 gives the structure) and re-grade the baselines against the new clauses.
4. Mechanical checks have false positives, and two columns (syntax, invented paths) cannot be reproduced exactly (`04` section 3.1). Fix: store the file listing at replay time with every run, and run both syntax checkers.
5. Single run per cell. Fix: three samples per point at the arm's normal setting, majority/consistency reported.
6. Cost basis mismatch between the baseline (agent transcripts with a large cached prefix) and plain API calls (`05` section 8). Fix: always re-run a baseline arm on your own basis when cost is the question.
7. Class sizes of 12-14. Fix: 40 per class would give a per-class difference resolution of about 3 points per flipped point instead of 7-8, at triple the cost.
8. replay2 grading of three candidates in a different grader session than the baselines (drift) and without a repeat of the baselines. Fix: re-grade all five arms together in one session with five-way packets, or run pairwise vs S.
9. The investigation suite scores reports, not repairs. Fix: apply each proposed fix to a copy of the system and run the failing scenario (the Codex brief partly does this by claim-checking against the frozen world, not by applying the fix).
10. The live shadow could not verify state, so both arms are penalised for ids and paths they could not check; and its labels were mostly "unknown".
11. ab2 is incomplete (12 of 20 planned runs attempted, 3 voided, 4 rows never run) and the earlier lane-operator pilot was not controlled. Nothing there is conclusive; it needs the project's game lane and was not re-run.
12. Privacy of the data: the points contain the text of real agent sessions (commands, paths, internal names). Review them before sharing outside the team. No secrets were found by a pattern scan (`data/MANIFEST.md`), but a pattern scan is not a review.

## 3. Questions that the existing data could answer but nobody has asked
- Which input features (event batch size, number of preceding messages, estimated tokens) predict failure of the cheap arm? `data/replay/INDEX.csv` has tokens, class, label, time; the grades are in `grading/out/`.
- How many of the strong model's failures are the same points as the cheap model's? (Hard-point overlap: if the failures overlap, the reference may be wrong rather than the arms.)
- What share of the "worse" verdicts comes from missed follow-up actions vs wrong targets vs bad syntax? (The grader notes in `grading/out/*.json` have a short reason per candidate.)
- Does agreement depend on the position in time (the first points are from the earliest sessions and the rules file changed between sessions)?
- How would the verdicts change if "acceptable-different" were not counted as agreement? Strict agreement = equivalent only: H 14/120 = 12%, S 24/120 = 20% (from the totals row of `data/replay/aggregate.md`).

## 4. How to extend
### 4.1 More points of the same kind (same project)
1. Choose sessions of the coordinator that are not already used (`data/replay/INDEX.csv` lists the 19 session ids used).
2. A decision point is an inbound event batch (agent report, alert, owner message, hook feedback) followed by the coordinator's actions up to the next inbound event. `tools/original/extract.py` and `build_points.py` did this from the original session transcripts (a JSON-lines format specific to the Claude Code CLI; read them as a recipe, they will not run on other transcripts).
3. Output per point: `P###.input.md` (see `02` section 3 for the exact template: preamble with the output schema, handoff text trimmed to 6000 characters, the preceding conversation with tool outputs cut to 1500 characters, the event batch, and the last line "Now output the decision JSON only") and `P###.truth.json` (fields: id, session, ts, class, outcome{label, why}, actions[{type, exact_command_or_message, why}], actions_truncated, reads[], narration[], event_text_chars). Action types are the 14 listed in `02`; map the real actions the same way (`02` section 3).
4. Sample with the same quotas (class quotas 14/14/14/12/14/14/14/12/12, at most 3 per session and class, 35% from non-good points) with a new seed; keep ids unique (for example `Q001..`); `score.py` works on any directory with this layout, with up to 3-digit ids in the order they should be listed.
5. Never include text that contains secrets or personal data without redaction; the packets copy decisions verbatim.

### 4.2 A different project or job
Keep the structure, replace the content: (a) pick decision moments from that job's logs; (b) rewrite the output schema (action types) and the preamble; (c) write the harm gate for that system (live-system damage, files in use, wrongly stopping work, false statements, forbidden work, live commands, skipped required steps, unasked spend, ignored order); (d) put the project's rules file at `data/context/` equivalent; (e) update `CLASSES`/`TYPES` in `tools/run_point.py` and `tools/score.py` (they are constants at the top of each file) and the core-class list; (f) generate the key, packets and grading with the same code.

### 4.3 More models, efforts, variants
`05-runbook-new-model.md`. Keep the same 120 points, the same footer, the same context file, and grade against arm S in the same packets every time. For multi-call variants (pair, draft-review, guard rails) use the prompts and filter rules in `03`; the guard-rails filter needs recalibration on a project's own real actions before use (it rejected 22.3% of the real coordinator's own actions).

### 4.4 More investigation tasks
Use `docs/MODEL_TEST.md` for the method (prompt files, rubric, blind shuffling, two judges, `mt.py report`). It depends on Claude Code Agent calls and session transcripts for `rec`; for another tool, record per run: report text, wall seconds, tokens, cost, and whether the run issued a mutating command, and check what `mt.py blind` and `mt.py report` read (suite folder layout, `runs.tsv`, report files, grade files) before relying on them with another tool; `docs/MODEL_TEST.md` describes the layout. Always write per prompt, before any run, what "complete" means. Run read-only on a frozen copy (`01` section 8), and verify the frozen copy before every run.

### 4.5 Pre-registration (recommended)
Before running a new model, write down: which classes you expect it to qualify on, the acceptance gate (the rule in `05` section 7, or a stricter one), the sample, and the grader. Publish the result against that, including failures. The method has many degrees of freedom (point choice, grader, prompts), and the replay2 results show how easily a variant tuned on the same points looks better than it is.

## 5. Things that were not found or not possible while building this package
- The per-session CLAUDE.md versions and the owner's private global instructions used by the original replay agents (only the repository copy of the project rules at one commit is shipped).
- Exact cost of the 15 baseline graders for the first replay (not recorded; the cost of the replay2 graders, $4.36, is).
- The per-run agent transcripts (token counts are shipped as numbers; the transcripts are private).
- The raw live-shadow feed and ledgers (shipped: points, grades, aggregate and cost only).
- A reproduction of the investigation-suite table with `mt.py report` inside this package (the table was copied from `FINDINGS2.md`; its raw rows are in `runs.tsv`).
