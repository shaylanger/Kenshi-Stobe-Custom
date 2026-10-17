# Stage 1 offline replay: full-run recipe (Haiku High = arm H, Sonnet High = arm S)

Plan: C:\KenshiModding\docs\COORD_SHADOW_PLAN.md. Tools: C:\KenshiModding\tools\automation\shadow-replay\ (Windows python, always `python -I`).
Dataset (done): `points\P001..P120.input.md/.truth.json`, `INDEX.csv`. The dry run (6 points x 2 arms, P008 P011 P013 P022 P028 P058) is already in `runs\` and `runs.tsv`; the full run skips them (228 runs left).
Shortcut: give the coordinator-free version to ONE executor agent: prompt file `C:\KenshiTestRuns\shadow\replay\EXECUTOR_PROMPT.md`.

## Recipe (what the coordinator or executor does)
T = C:\KenshiModding\tools\automation\shadow-replay

1. Plan (already done once; re-run is idempotent and skips finished runs):
   `python -I T\replay-run.py plan --batch 20`   -> `plan\batch-01..12.json` (228 runs; each entry has rid, description, prompt, run_in_background).
2. For batch N = 01..12: read `plan\batch-NN.json` and issue its entries as ONE message of <= 20 parallel Agent calls, each with
   - description = entry.description, e.g. `[case:bench] [ticket:REPLAY-P001-ra] [model:haiku] [effort:high] replay P001-ra`
     (tags: `[case:bench]`, `[model:haiku|sonnet]`, `[effort:high]`; the `P001-ra` run id is the marker; `-ra` = Haiku, `-rb` = Sonnet)
   - prompt = entry.prompt (starts with `replay-run: <rid>`, never names the model), run_in_background = true
   - subagent_type: omit (default). Each replies "OK" in one word; wait until all 20 notifications are in.
3. After each batch: `python -I T\replay-run.py collect` (finds transcripts by the `replay-run:` marker, parses JSON, writes tokens/USD to `runs.tsv`; prints `bad: [...]`).
4. After all 12 batches: `python -I T\replay-run.py status` (missing count). If anything is missing or bad: `python -I T\replay-run.py retry --batch 20`
   (clears invalid outputs, re-plans only the missing runs into `plan\batch-NN.json`), run those batches ONCE, `collect --redo`. Do not retry twice; leftovers are reported as invalid.
5. Mechanical checks: `python -I T\grade.py mech` (-> `mech.json`, `mech.csv`).
6. Blind grading packets: `python -I T\grade.py packets --chunk 8` (-> `grading\chunk-01..15.md` + secret `grading\key.json`). It prints one Agent line per chunk.
7. Spawn 15 graders (they may run in parallel, background): `subagent_type: kenshi-grader`, description `[case:grade] [ticket:REPLAY-chunk-NN] grade chunk-NN`,
   prompt `Read C:\KenshiTestRuns\shadow\replay\grading\chunk-NN.md and follow it exactly.` Each writes `grading\out\chunk-NN.json` (JSON array, one object per point:
   `{"id":"P001","A":{"class","clause","better_than_truth","note"},"B":{...},"truth_ok":true}`) and replies DONE. Missing/invalid file: respawn that grader once.
   NEVER open `grading\key.json` (it maps A/B to the arms).
8. `python -I T\aggregate.py` -> `aggregate.md` (per-class table: agreement, harmful, invalid commands, invented paths, missed/extra, claims, brief quality, tokens/USD per arm, per-class verdict, core-class gate).
9. Hand back the path `C:\KenshiTestRuns\shadow\replay\aggregate.md` (+ a summary: per-class verdicts, harmful count per arm, cost).

## Cost estimate (API-equivalent, from the dry-run runs.tsv and prices.json)
- Haiku run ~ $0.007 (114k tokens, mostly cached CLAUDE.md context); 114 runs ~ $0.8.
- Sonnet run ~ $0.10; 114 runs ~ $11.5.
- 15 graders ~ $0.3-0.5 each (one 8-point packet ~ 60 KB) ~ $5-7.
- Total ~ $18-20; wall time ~ 12 batches x 2-4 min + graders 5 min ~ 35-50 min. Coordinator cost if it spawns itself: ~255 Agent calls + 12 collects (one-word replies, so little context); the executor prompt moves this out of the coordinator.

## Caveats
- Replay agents see TODAY's CLAUDE.md (it auto-loads), not the one of the original session, and have no tools beyond one Read and one Write, so they cannot investigate; the point inputs are abridged.
- Outcome label (good/corrected/bad) is a noisy heuristic; graders are told to grade on what should have been done when the truth was corrected.
- Both arms see identical inputs; the A/B order is randomised per point in the packets.
- Dry run (n=6) is not evidence for any verdict; only the 120-point run is.
