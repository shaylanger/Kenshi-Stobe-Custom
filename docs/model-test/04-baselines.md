# 04 - Baseline numbers, their sources, and what could and could not be reproduced

All figures below were checked against the shipped data in `data/` on 2026-10-16 (the check is described in section 2). "H" = Haiku High (cheap model), "S" = Sonnet High (strong model); both are 2026-10 Claude models used at "high" effort. Terms: `02-offline-replay-suite.md` section 1.

## 1. Baseline tables, one per suite

### 1.1 Offline replay, 120 points (source: `data/replay/aggregate.md`, `runs.tsv`, `grading/out/`)
| measure | H | S |
|---|---|---|
| graded points | 120 | 120 |
| agreement with reference | 38% | 74% |
| equivalent / acceptable-different | 14 / 32 | 24 / 65 |
| worse | 69 | 27 |
| HARMFUL | 5 | 4 |
| better than the reference | 3 | 3 |
| syntax errors in commands (bash only, see 3.1) | 25 | 29 |
| invented paths (mech, see 3.1) | 0 | 5 |
| forbidden-target flags | 3 | 3 |
| missed events / extra actions | 5 / 5 | 7 / 3 |
| unsupported claims to the owner | 2 | 3 |
| spawn briefs well-formed ("brief ok") | 45% | 67% |
| tokens per run (all kinds, transcript basis) | 116,962 | 110,644 |
| USD total / per run | 0.809 / 0.0067 | 11.777 / 0.0981 |
| wall seconds per run | 23.8 | 18.0 |
Reference acceptable on 111 of 120 points (graders rated it not-ok on 9). By outcome label (agreement H vs S): good (80 points) 35% vs 76%; corrected (36) 47% vs 75%; bad (4) 25% vs 25%.
Per class (agreement H / S, harmful H / S): relay 29/79 (1/0), setup-fail 21/86 (0/0), lane-alert 36/86 (0/1), waker-digest 50/92 (1/1), shay-message 29/64 (1/0), stop-hook 79/86 (0/0), agent-stopped 36/71 (1/0), build-compose 33/50 (0/2), other 33/50 (1/0). Every class: verdict "strong model only" (the full per-class table is in `data/replay/aggregate.md`).
Cost of the 15 graders of this run: not recorded in the shipped files.

### 1.2 replay2 variants, same 120 points (source: `data/replay2/aggregate.md`, `cost.md`)
| arm | agree | worse | HARMFUL | USD total | tokens / point | calls / point | wall s / point |
|---|---|---|---|---|---|---|---|
| Haiku alone (= H above) | 38% | 69 | 5 | 0.81 | 116,962 | 1 | 23.8 |
| Sonnet alone (= S above) | 74% | 27 | 4 | 11.78 | 110,644 | 1 | 18.0 |
| Haiku pair | 54% | 47 | 8 | 6.73 | 557,272 | 4.55 | 86.0 |
| Draft-review | 67% | 37 | 3 | 13.29 | 232,306 | 2.00 | 41.4 |
| Guard rails | 47% | 57 | 7 | 0.92 | 143,914 | 1 | 31.4 |
Graders for the three new arms: 15 sessions, 10.26M tokens, $4.36. Guard rails on class stop-hook: 86% (12 of 14), 0 harmful. Detail and caveats in `03-replay2-variants.md`.

### 1.3 Live coordinator shadow, 38 batches (source: `data/live-shadow/LIVE_SHADOW_RESULTS.md`, `live-grading/aggregate.md`)
Two shadow agents (H and S) received the SAME stream of events as a live coordinator session during 2026-10-16 15:49-16:47 (feed of 38 batches) and answered every batch; the real coordinator's actions were the reference. Graded blind like the replay.
| measure | H | S |
|---|---|---|
| agreement | 61% (23/38) | 71% (27/38) |
| worse | 15 | 11 |
| HARMFUL | 0 | 0 |
| missed events | 11 | 5 |
| USD (token cost at list prices; Haiku over-100k band applied to 78 of 138 calls) | 0.763 | 1.787 |
| API calls / tokens per decision | 138 / 415k | 92 / 293k |
Per class (n = 1 to 14 each, too small to conclude): relay 64% vs 79% (H missed 7 vs 1), waker-digest 33% vs 83%, stop-hook 67% vs 50%, others n <= 4. Reference acceptable on 38 of 38. Conclusion of that run: keep the strong model as coordinator; no class qualified for the cheap model.

### 1.4 Lane-operator pilot ab2, interim (source: `data/ab2/COMPARISON.md`)
A different job: an "operator" agent runs one game-test row via a one-call script, reads the checker's result line, records it, escalates on anything odd. Same rows, same lane, Haiku vs Sonnet alternating in A/B/B/A order.
| measure | Haiku | Sonnet |
|---|---|---|
| runs with a result | 5 | 4 |
| operator verdict equal to the checker's result line | 5 / 5 | 4 / 4 |
| agent tokens (whole transcripts) / API-price USD | 1,295,014 / $0.050 | 1,292,433 / $0.650 |
| script wall time | 40m56s | 36m10s |
Only 12 of 20 planned runs were attempted, 9 produced a result, 3 were voided (scene reset failed; fixed afterwards). Four rows were never run. Checker verdicts differed between arms on 3 of the 4 rows run by both (the rows are noisy; the operator only has to equal its own checker line). Two earlier numbers quoted elsewhere come from a separate earlier pilot, not from ab2: Haiku operator matched the checker 11/12 and the strong-model verdict on 8/13 rows, at about 1/16 of the cost per row, with 33% of its reports containing a false checkable claim.
Discrepancy to know about: `HAIKU_VS_SONNET_FINAL.md` (final summary of the live shadow, written earlier) says ab2 was never run; the ab2 files show it ran partially. `data/ab2/COMPARISON.md` is the authority.

### 1.5 Investigation suite, 36 runs + 2 earlier reports (source: `2026-10-15-investigation-suite/FINDINGS2.md`, `FULL_TABLE.md`, `runs.tsv`, `grades/`)
Quality = mean of two blind judges (Sonnet High, Opus High) on a 5-criterion rubric, 5 to 25 points; cost = token cost per task at list prices; one run per cell, 3 prompts.
| config | quality /25 | cost / task | time / task | false claims / task |
|---|---|---|---|---|
| haiku low / medium / high / xhigh | 14.7 / 15.3 / 19.0 / 22.3 | $0.03 / 0.10 / 0.27 / 0.74 | 1.4 / 3.0 / 4.8 / 10.7 min | 0.8 / 1.2 / 1.2 / 0.5 |
| sonnet low / medium / high / xhigh | 14.3 / 17.3 / 21.3 / 24.7 | $0.26 / 0.36 / 0.66 / 1.39 | 1.2 / 2.5 / 4.4 / 9.4 min | 0.8 / 1.0 / 0.7 / 0.0 |
| opus low / medium / high / xhigh | 18.2 / 22.7 / 22.0 / 22.8 | $0.70 / 1.09 / 1.49 / 3.78 | 2.6 / 4.1 / 5.5 / 13.8 min | 0.8 / 0.7 / 0.7 / 0.7 |
| earlier: cascade (Haiku investigates, Sonnet verifies) | 21.5 | $1.11 | 19.0 min | |
| earlier: Sonnet medium alone | 17.3 | $0.43 | 2.2 min | |
Totals: 36 runs, $32.67, 190 agent-minutes. Judges agreed at r = 0.92. Effort moved quality more than model did (mean by effort: low 15.7, medium 18.4, high 20.8, xhigh 23.3; by model: Haiku 17.8, Sonnet 19.4, Opus 21.4). Per-config means carry about +/-3 points; a single prompt can swing 10.

## 2. What was re-checked and how
Everything below was recomputed from the shipped data with the shipped tools:
- `python -I tools/score.py aggregate --points data/replay/points --arms H,S --arm H=data/replay/outputs/H --arm S=data/replay/outputs/S --grades data/replay/grading/out --key data/replay/grading/key.json --mech data/replay/mech.json --runs-file H=data/replay/runs.tsv --runs-file S=data/replay/runs.tsv --out <file>` reproduced every table of `data/replay/aggregate.md` (per class, totals, outcome-label table, token/cost table, per-class verdict, "truth not ok 9 of 120") exactly, apart from title and wording.
- `score.py packets --arms H,S` reproduced the shipped blind `key.json` (the A/B order of all 120 points) exactly.
- `score.py check` on both arms: 0 invalid, 0 missing outputs (120 + 120).
- The replay2 and live-shadow numbers were read from their shipped aggregate files and cross-checked against the per-class tables (sums of harmful per class equal the totals: H 5, S 4).
- The investigation-suite table was read from `FINDINGS2.md`; its raw rows are in `runs.tsv`. It was not recomputed with `mt.py report` in this package (that tool needs the original folder layout and a Linux shell).

## 3. What could NOT be reproduced, and why
### 3.1 Mech columns "syntax errs" and "invented paths" (replay baseline)
Re-running the mechanical checks (`score.py mech --fs-list data/context/workspace-paths.txt`) on the shipped outputs differs from the shipped `mech.csv` in 8 of 240 rows:
- Syntax errors: H 25 -> 26 and S 29 -> 30. Cause: the ORIGINAL script `grade.py` ran its PowerShell check wrongly (files were passed after `-Command`, where they are not visible as arguments) so PowerShell commands were never actually checked; the baseline column therefore counts bash errors only. `score.py` checks both. The shipped baseline number is kept in all tables, and it is a floor.
- Invented paths: H 0 -> 4 and S 5 -> 10. Cause: the original check asked the file system at grading time; the package substitutes a frozen list of existing files (`workspace-paths.txt`), built later, so files created since then count as existing or not differently. Treat this column as not comparable between the original run and a re-run.
- One row (P090, arm H) has 5 commands checked in the baseline and 4 now; the baseline mech was probably run before that output was re-collected.
Agreement, harmful and worse counts are NOT affected: they come from the grader files, not from mech.

### 3.2 Token, cost and time figures
Computed in the original environment from agent session transcripts (each run = one agent session; usage per assistant message summed). Those transcripts are private and not shipped. The shipped `runs.tsv`, `runs2.tsv`, `cost.json` are the only record; `score.py aggregate` reads them and recomputes the TOTALS, but it cannot regenerate the per-run tokens. A new run through `run_point.py` gets either exact usage (if your command reports it) or an estimate chars/3.5, so cost is on a different basis from the baseline (see 02 section 9). Compare cost only as an order of magnitude unless you measure both arms on the same basis (rerun a baseline arm yourself).

### 3.3 Grades
Grade files are the record of what 15 grader sessions decided; re-grading the same 240 candidates with a different grader model gives different numbers (nothing in the package can predict by how much). The package reproduces the AGGREGATION of the grades, not the grades. If you change the grader model, re-grade the baseline arms too (section 6 of the runbook) and compare only within that grading session.

### 3.4 Fidelity differences between the baseline run and a portable run
- Baseline replay agents had, auto-loaded, (a) the project rules file `CLAUDE.md` at its CURRENT version, (b) the owner's personal global instruction file, and (c) a persistent memory index of one-line notes about the owner's preferences. (b) and (c) are private and not shipped. A portable run gets only (a) (`data/context/CLAUDE.md`, the repo version at git `dc307389`). Expect small differences for decisions that depend on the owner's personal preferences.
- Baseline agents read a prompt file and wrote an answer file (one Read, one Write); a portable run uses stdin/stdout.
- Baseline agents ran inside an agent harness with its own system prompt and about 100k tokens of cached context per run; a plain API call has far fewer tokens, so latency and cost per call are NOT comparable.
- Baseline models: Haiku 5.5 and Sonnet 5.5 at "high" effort (model ids `claude-haiku-5-5`, `claude-sonnet-5-5` in `runs.tsv`).

### 3.5 Not shipped, hence not reproducible from this package alone
- The extraction of the 120 points from the private session transcripts (`tools/original/extract.py`, `build_points.py` are provenance; the shipped `points/` are the dataset).
- The live-shadow raw feed and ledgers; the replay2 job and raw-output folders; the investigation suite's frozen world (1.3 GB) and Codex transcripts (about 290 MB). See `data/MANIFEST.md`.
- ab2 needs a game lane and the lane tooling.

## 4. Using the baselines as the control
Do not compare a new model against the numbers above only. In every serious run grade the new arm TOGETHER with at least one baseline arm in the same blind chunks (runbook section 6.4: `--arms NEW,S` or `--arms NEW,H`), so that grader drift cancels. The baselines' outputs are shipped for exactly this reason (`data/replay/outputs/H`, `.../S`).
