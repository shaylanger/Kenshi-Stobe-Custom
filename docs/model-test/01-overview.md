# 01 - Overview: why we test models, what each suite measures, what it decided, what is not conclusive

Terms (arm, point, class, truth/reference, mech, HARMFUL, blind grading) are defined in `README.md` ("Terms"). Numbers here are copied from the sources named in each table; the exact checks and the list of what could not be reproduced are in `04-baselines.md`. All dates are 2026-10 and all prices are list prices at the time (USD per million tokens).

## 1. Why we test
A software project is run by AI agents in long sessions. One strong "coordinator" agent reads events (agent reports, alerts, owner messages, hook feedback) and decides actions (spawn a helper agent, message someone, edit a ledger, run a command). Strong models cost about 20 times more per token than the cheapest ones, so the question is: for which jobs can a cheaper model, or a lower effort setting, replace the strong one without more mistakes, and how do we find out without risking the real system? The suites below answer that with replays of past decisions and with controlled comparisons of finished work, graded blind. The same suites can be re-run on any other model; `05-runbook-new-model.md` is the procedure.

## 2. The suites at a glance
| suite | job tested | method | size | arms | decision it drove |
|---|---|---|---|---|---|
| Offline replay (`02`) | coordinator decisions | 120 past decision points replayed as text-only prompts; answers graded blind against what the real coordinator did | 120 points x 2 arms = 240 runs, 15 grader sessions | Haiku High (H), Sonnet High (S) | keep the strong model as coordinator; no event class passed the cheap-model gate |
| replay2 variants (`03`) | can scaffolding fix the cheap model? | three constructions on the same 120 points: cheap pair with a vote, cheap draft + strong review, cheap model + mechanical guard rails | 360 final answers, 15 grader sessions | pair, draft-review, guard rails (+ H, S) | none adopted; only noise-level candidate was guard rails on one class |
| Live shadow (pointer only, section 7) | coordinator decisions on a live feed | the same live event feed shown to a cheap and a strong shadow agent; they decide but never act | 38 batches | H, S | confirmed: keep the strong model |
| Lane-operator pilot ab2 (pointer only, section 7) | run one game-test row via a one-call script, record the result | A/B on the same rows, same lane | 12 attempted, 9 results | Haiku High, Sonnet High | cheap model acceptable for the mechanical read-and-record part (interim) |
| Investigation suite (section 5) | root-cause investigations of a real bug, read-only, with a written report | 3 prompts x 3 models x 4 efforts; blind rubric grading by two judges | 36 runs | Haiku, Sonnet, Opus x low..xhigh | the model-and-effort routing table used for investigations |
| Codex matrix (section 6) | the same investigations on another vendor's models | prepared, not run | 88 runs planned | 7 models, 44 configs | none yet |

Common design rules: same input for every arm, one run per cell, no retries, no live system touched, graders blind to the arm, results reported with their noise.

## 3. Offline replay: headline (source `data/replay/aggregate.md`)
| | Haiku High | Sonnet High |
|---|---|---|
| agreement with the real coordinator's action (120 points) | 38% | 74% |
| HARMFUL decisions (breaks a hard limit; clauses a-i in `02` 7.3) | 5 | 4 |
| worse than reference | 69 | 27 |
| cost per run, API-equivalent | $0.0067 | $0.098 |
| classes where the cheap arm qualifies (zero harmful AND agreement >= 80% AND within 10 points of the strong arm) | none of 9 | |
The strong model is also imperfect: 4 harmful decisions, 29 command syntax errors, 5 invented paths. The cheap model was best on the class "stop-hook feedback" (79% vs 86%) and worst on "setup-fail" (21% vs 86%).

## 4. replay2 and live shadow: headline (sources `data/replay2/aggregate.md`, `data/live-shadow/`)
| | agreement | HARMFUL | cost (USD) |
|---|---|---|---|
| replay: Haiku alone / Sonnet alone | 38% / 74% | 5 / 4 | 0.81 / 11.78 |
| replay2: Haiku pair (4.55 calls per point) | 54% | 8 | 6.73 |
| replay2: Draft-review (cheap draft, strong review) | 67% | 3 | 13.29 |
| replay2: Guard rails (cheap + mechanical filter) | 47% | 7 | 0.92 |
| live shadow, 38 batches: Haiku / Sonnet | 61% / 71% | 0 / 0 | 0.76 / 1.79 |
Reading: the pair costs more than half of the strong model and is worse; draft-review costs as much as the strong model alone (the strong reviewer rewrote 72 of 120 drafts) and is a little worse; the guard rails are cheap but only lifted the cheap model from 38% to 47%. The one class where a variant looked usable was stop-hook with guard rails (12 of 14, 86%, zero harm) but plain Haiku was 11 of 14 there, a one-point gain. The live shadow shows a smaller gap than the replay, with the same direction (it has only 38 batches, so the difference between the two tests is itself within noise).

## 5. Investigation suite (source `2026-10-15-investigation-suite/`, `docs/MODEL_TEST.md`)
Task: read-only investigation of a real defect in a running system (three prompts; evidence = code, logs and a database). Each run returns a written report. Rubric, five criteria scored 1-5 (root cause, evidence, fix specificity, completeness of the answer including only reading and not changing anything, honesty about unknowns/false claims), 25 maximum. Two blind judges (Sonnet High and Opus High) scored every report together with older reports, agreeing at r = 0.92; claims were checked against the live code, logs and database. Table (mean of 3 prompts, one run per cell; source `FINDINGS2.md`, `FULL_TABLE.md`):
| model | low | medium | high | xhigh |
|---|---|---|---|---|
| Haiku quality /25 (cost per task) | 14.7 ($0.03) | 15.3 ($0.10) | 19.0 ($0.27) | 22.3 ($0.74) |
| Sonnet | 14.3 ($0.26) | 17.3 ($0.36) | 21.3 ($0.66) | 24.7 ($1.39) |
| Opus | 18.2 ($0.70) | 22.7 ($1.09) | 22.0 ($1.49) | 22.8 ($3.78) |
36 runs, $32.67, 190 agent-minutes. An earlier two-step pipeline (cheap investigation + strong verification) scored 21.5 at $1.11 and 19 minutes; the strong model at medium effort alone scored 17.3 at $0.43 and 2 minutes. Findings: effort mattered more than model (mean by effort 15.7 / 18.4 / 20.8 / 23.3 from low to xhigh; by model Haiku 17.8, Sonnet 19.4, Opus 21.4); Opus medium is the best "fast strong" setting (22.7, $1.09, 4 min); Sonnet xhigh scored best and made no false claims (24.7, $1.39, 9 min); Haiku high or xhigh is the cheap option (19.0 at $0.27, 22.3 at $0.74); low effort and Sonnet medium are poor (14-17); raising Opus above medium bought nothing. Decision driven: the model-and-effort table used to route investigation tasks.
Not conclusive: 3 prompts and one run per cell; each configuration mean is about +/-3 points and a single prompt can swing 10 (Haiku high scored 12.5 on one prompt and 22.5 on another). Fixes were judged on specificity, not applied. 17 of the 36 runs tripped a "mutating command" heuristic; the ones inspected were reads or scratch files in a temp folder.

## 6. Codex matrix (prepared only; source `docs/CODEX_MODEL_TEST_BRIEF.md`, `tools/model-test/codex_bench.py`)
The same investigation task on another vendor's CLI models: 7 models (gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-6-luna, gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna), efforts low to ultra with a standard and a fast tier: 31 standard + 13 fast = 44 configurations, prompts 2 and 3 only (prompt 1's evidence is not in the frozen world), 88 runs. The runner has commands `prepare`, `preflight`, `run --execute`, `status`, `record`, `recheck`; only `run --execute` makes paid calls. The suite files and one failed attempt are in the repo; the run transcripts (about 290 MB) are untracked. No results exist; the owner has to authorise the start. If you run it, use the frozen world below, not the live system.

## 7. Pointers only (not re-runnable from this package)
- **Live shadow, 38 batches (2026-10-16 15:49-16:47):** results `data/live-shadow/LIVE_SHADOW_RESULTS.md`, graded packets and aggregate in `data/live-shadow/live-grading/`, summary of this and the other cheap-vs-strong tests in `HAIKU_VS_SONNET_FINAL.md`. Its raw feed and ledgers are not in the package (they hold unreviewed session text). Key numbers: agreement 61% vs 71%, harmful 0 vs 0, missed events 11 vs 5, cost $0.763 vs $1.787 (78 of 138 cheap-model calls had prompts over 100k tokens and were billed at the higher band: a worst case).
- **Lane-operator pilot ab2:** `data/ab2/COMPARISON.md` (authority), `README.md`, `brief.md`, `plan.json`, `state.json`. Needs a running game lane and the project's tooling. Result so far: 12 of 20 planned runs attempted, 9 produced a result, 3 voided; operator verdict equal to the checker's result line in 5 of 5 (Haiku) and 4 of 4 (Sonnet); Haiku about $0.050 vs Sonnet about $0.650 per set; four planned rows were not run. `HAIKU_VS_SONNET_FINAL.md` (written earlier the same day) says ab2 was never run; that statement is out of date.

## 8. Frozen world
The investigation suite needs a system to investigate. Two modes exist: the live system (suite 1 and 2: the investigated defect was real and the judges checked claims against live code, logs and a database that kept changing), and a frozen copy for repeatable runs (the Codex matrix and any later suite).
- Location on the original machine: `C:\KenshiTestRuns\invest\frozen-2026-10-14`, 1.3 GB: server source tree 397 MB, server logs 922 MB, native source 6.3 MB, and a database `stobe_frozen` (453 MB) inside a PostgreSQL instance (in a Linux distribution under WSL on the original machine).
- It is partly a reconstruction, not an exact replay of the moment of the defect. Cut-off 2026-10-15 02:26 UTC (nothing in it is newer than 02:08:40 UTC). The database was rebuilt from a saved clone of the live database schema taken about 16 hours after the investigated session, with rows newer than the cut-off left out or undone (77 base tables, content hashes per table in its `MANIFEST-data.txt`; three live tables not copied); the server code tree is an exact export of a version-control snapshot (tree hash 25c343ea..., 1113 files, hash-verified); the native C++ source was rebuilt from backups and is NOT byte-proven; the logs were cut at the test start. Its `README.txt` and `README-data.txt` list every deviation. `verify.sh` prints "FROZEN OK" when file hashes and the database match the recorded manifests and "FROZEN DIFF" otherwise; run it before every run.
- Rules for runs on it: read-only; use only the frozen files and the database copy; no live paths; no helper agents; results saved as a report with the required sections.
- It is NOT in this package (size, and the logs have not been reviewed for private content). To use it elsewhere, recreate it from the project's repositories at the recorded commit, restore a database dump, and re-create `verify.sh`'s baseline. Prompt 1 of the suite is excluded for the frozen world (its evidence was in the live game, not in the copy). Related files: `2026-10-15-investigation-suite/baseline-state.txt`, `baseline.env`, `data/investigation/task-frozen.tmpl`.

## 9. What is NOT conclusive (read before quoting any number)
1. Small samples: 120 replay points (12-14 per class), 38 live batches, 9 ab2 results, 36 investigation runs (3 prompts). One run per cell. A one-point change is 0.8 points overall and 7-8 points inside a class.
2. The reference is fallible: graders judged the real coordinator's own action not acceptable on 9 of 120 points, and the outcome label is a heuristic. Agreement measures similarity to one reference, not correctness.
3. Graders are language models; the replay was graded by one grader family (Sonnet High) of which one of the arms is a member. Self-preference was not tested. Replay2's new arms were graded in a different session than the baselines (drift possible).
4. replay2 variants were designed after seeing the replay failures on the same 120 points, so the numbers are optimistic for them (no held-out set).
5. Cost bases differ: the baseline token counts include an agent harness and a large cached rules prefix; plain API calls are much smaller. Compare cost only on the same basis (`05` section 8).
6. The harm gate (clauses a-i) is specific to the project it was written for; "0 harmful" in 14 points is not evidence of safety.
7. The live shadow shadows could not verify state (they could not check whether an id existed), which penalises both arms for invented ids; the lane-operator pilot is only partly controlled and ab2 is incomplete.
8. Investigation quality was judged on evidence and fix specificity; fixes were not applied and tested.
9. Nothing here tests other tasks (code editing, long tool-using sessions), other model families (the Codex matrix is unrun), or newer model versions. See `06-open-questions.md`.

## 10. Index of the files (where to look)
| what | where |
|---|---|
| Package index, terms, ready prompt | `README.md` |
| Offline replay method, formats, grader text, harm gate | `02-offline-replay-suite.md` |
| replay2 variants with the exact prompts | `03-replay2-variants.md` |
| Baselines, reproduction and what could not be reproduced | `04-baselines.md` |
| Run a new model | `05-runbook-new-model.md` |
| Open questions and how to extend | `06-open-questions.md` |
| Data manifest | `data/MANIFEST.md` |
| Portable scripts | `tools/run_point.py`, `tools/score.py`, `tools/grade_chunks.py`, `tools/answer_from_dir.py`, `tools/stub_model.py`; originals in `tools/original/` |
| Investigation suite 2026-10-15 | `2026-10-15-investigation-suite/` (`FINDINGS.md`, `FINDINGS2.md`, `FULL_TABLE.md`, `rubric.md`, `prompt1..3.txt`, `runs.tsv`, `grades/`, `keys/`, `reports/`) |
| How to run more investigation suites | `docs/MODEL_TEST.md` (needs the original tooling `tools/model-test/mt.py`: commands init, gen, rec, extract, blind, report; its `rec` reads Claude session transcripts, so it is Claude-specific) |
| Codex matrix brief and runner | `docs/CODEX_MODEL_TEST_BRIEF.md`, `tools/model-test/codex_bench.py` |
| Earlier cheap-vs-strong summary | `HAIKU_VS_SONNET_FINAL.md` (ab2 statement out of date, see section 7) |
