# Haiku vs Sonnet replacement tests: ONE combined final summary

Written 2026-10-16 by imm26-shadowfinal (Shay's order: one summary of all Haiku-vs-Sonnet tests). H = Haiku High (Haiku 5.5), S = Sonnet High (Sonnet 5.5). All dollars are API-price equivalents from `tools/automation/prices.json`, not billed money. Tokens = input + output + cache write + cache read (cache read is 94-98% of every figure). Every number below is copied from the generated reports named in the "source" column; nothing was invented.

## 0. The three tests at a glance

| | 1. LIVE coordinator shadow | 2. Stage-1 OFFLINE replay | 3. LANE OPERATOR pilot |
|---|---|---|---|
| job tested | coordinator decisions on a live event feed | coordinator decisions replayed from past sessions | run a test row via one script, read checker line, record, escalate |
| window | feed 2026-10-16 15:49-16:47 (about 57 min, both arms) | 120 decision points taken from sessions between 2026-10-14 20:46 and 2026-10-16 ~14:58 (local); run 2026-10-16 ~15:30-16:11; graded 16:14 | 2026-10-16 13:02-14:08 (66 min), lane 5090-i4 |
| sample | 38 event batches (38 graded) | 120 points x 2 arms = 240 runs, 120 graded, 9 classes (12-14 per class) | 13 rows with a Haiku line (20 verdict lines, 14 attempt lines) vs the real Sonnet operators' runs of the same rows |
| control | both arms see the same fixed feed, cannot run commands | both arms see the same input, one Read + one Write only | NOT controlled (other lanes/builds/times) |
| quality headline | agreement H 61% vs S 71%; harmful 0 vs 0 | agreement H 38% vs S 74%; harmful 5 vs 4 | verdict agreement H vs Sonnet 8/13 rows (+1 after rerun); H vs own checker 11/12 |
| tokens | H 15.80M, S 11.14M | H 14.0M (116,962/run), S 13.3M (110,644/run) | H 5.67M over 13 row windows, S 7.87M over matching windows |
| API-equiv USD | H $0.763, S $1.787 | H $0.81, S $11.78 | H $0.14, S $2.23 |
| source | `shadow\REPORT.md`, `live-grading\aggregate.md`, `live-grading\cost.json` | `shadow\replay\aggregate.md`, `runs.tsv` | `pilot\haiku-i4\SUMMARY-final.md`, `COMPARISON.md`, `verdicts.csv` |

## 1. LIVE coordinator shadow (38 batches, 2026-10-16 15:49-16:47)

What: coordinator 20's real session event feed was fed in 38 batches to a Haiku shadow and a Sonnet shadow; each wrote the decision it would take (never acted). 5 blind kenshi-grader chunks (A/B randomised) graded each decision against the real coordinator's action; all 38 real actions were rated acceptable.

| metric | H | S |
|---|---|---|
| graded decisions | 38 | 38 |
| agreement (equivalent + acceptable-different) | 61% (23) | 71% (27) |
| worse than the real action | 15 | 11 |
| HARMFUL (clauses a-i) | 0 | 0 |
| missed events / extra actions | 11 / 4 | 5 / 4 |
| invalid commands (final line / all lines) | 0 / 1 of 106 | 0 / 4 of 91 |
| median latency per batch | 13.6 s | 8.9 s |
| API calls (messages) | 138 | 92 |
| tokens total | 15,799,012 | 11,137,408 |
| cache read / cache write / fresh input / output (est) | 15,504,640 / 270,880 / 276 / 23,216 | 10,922,571 / 193,631 / 184 / 21,022 |
| USD (output estimated) / logged-output floor | $0.763 / $0.724 | $1.787 / $1.598 |
| USD per decision / per agreeing decision / per active hour | $0.020 / $0.033 / $0.81 | $0.047 / $0.066 / $1.88 |
| tokens per decision | 415k | 293k |
| context first -> last call | 27k -> 209k | 27k -> 206k |

Tokens/cost measurement: `tools/automation/shadow-replay/shadow-cost.py` over the shadow subagent transcripts (not the ledgers). The transcripts log only about 15 output tokens per message (stream placeholder), so output is estimated as content chars / 3.5 (output < 0.2% of tokens, but about 12% of Sonnet's USD). Haiku prompts over 100k are billed whole at the over-100k rate for 78 of 138 calls (prices.json assumption); at the base Haiku rate the same tokens would be about $0.20, so $0.763 is a worst case. H is two agents (first spawn ended after 7 min, the resume ran to the end; both counted). Grader cost is NOT included.

| class | n | H agree | S agree | H missed / S missed | verdict |
|---|---|---|---|---|---|
| relay/hand-back | 14 | 64% | 79% | 7 / 1 | Sonnet only |
| setup-fail ticket | 3 | 33% | 33% | 0 / 0 | Sonnet only (both weak, n=3) |
| lane alert | 4 | 75% | 75% | 1 / 2 | Sonnet only (n=4, below 80%) |
| waker digest | 6 | 33% | 83% | 1 / 1 | Sonnet only |
| Shay message | 2 | 50% | 100% | 0 / 0 | Sonnet only (n=2) |
| stop-hook feedback | 6 | 67% | 50% | 1 / 0 | Sonnet only (both weak) |
| agent stopped/dead | 1 | 100% | 0% | 0 / 0 | n=1, no conclusion |
| other | 2 | 100% | 100% | 1 / 1 | Haiku ok (n=2) |

Typical defects of BOTH arms: re-spawning an agent an earlier event already launched, acking/messaging an invented id (shadows could not verify state), unrequested lanes.held edits, missing the HANDOFF update after a report. Outcome labels are heuristic (37 of 38 "unknown"). Audit (`shadow_audit.py`) could not attribute any workspace change to a shadow.

## 2. Stage-1 OFFLINE REPLAY (120 past decision points)

What: 120 decision points (9 event classes, 12-14 each) taken from 19 past coordinator sessions (2026-10-14 20:46 to 2026-10-16 ~14:58 local). Each point replayed to both arms (240 runs; agents had one Read + one Write, saw TODAY's CLAUDE.md, abridged inputs, no investigation). 15 blind graders (8 points per chunk). Truth rated not-ok by graders on 9 of 120 points.

| metric | H | S |
|---|---|---|
| graded points | 120 | 120 |
| agreement | 38% | 74% |
| worse than truth | 69 | 27 |
| HARMFUL | 5 | 4 |
| better-than-truth | 3 | 3 |
| syntax errors / invented paths / forbidden flags | 25 / 0 / 3 | 29 / 5 / 3 |
| missed / extra | 5 / 5 | 7 / 3 |
| unsupported claims | 2 | 3 |
| brief ok (spawn briefs) | 45% | 67% |
| agreement where the real coordinator was NOT later corrected ("good", n=80) | 35% | 76% |
| agreement where it was corrected (n=36) | 47% | 75% |
| tokens total | 14.04M (116,962/run) | 13.28M (110,644/run) |
| in / out / cache-write / cache-read | 738 / 428,490 / 3,987,496 / 9,618,795 | 714 / 178,682 / 3,616,185 / 9,481,770 |
| USD total / per run | $0.81 / $0.0067 | $11.78 / $0.098 |
| wall s per run | 23.8 | 18.0 |
| USD per agreeing point (46 vs 89 agreeing, summed from the per-class table; derived) | about $0.018 | about $0.132 |

Tokens/cost measurement: `replay-run.py collect` parses each replay agent's transcript (found by the `replay-run:` marker) and writes per-run tokens and USD to `runs.tsv`; prices.json per message at its own model. Output tokens here come from the transcripts (H writes about 3.6k output tokens/run, S about 1.5k). Not included: the 15 grader agents (README estimate about $5-7, an estimate only, not measured) and the 6 dry-run points (run in the same files).

| class | n | H agree / harm | S agree / harm | verdict |
|---|---|---|---|---|
| relay | 14 | 29% / 1 | 79% / 0 | Sonnet only (harm gate) |
| setup-fail | 14 | 21% / 0 | 86% / 0 | Sonnet only |
| lane-alert | 14 | 36% / 0 | 86% / 1 | Sonnet only |
| waker-digest | 12 | 50% / 1 | 92% / 1 | Sonnet only |
| shay-message | 14 | 29% / 1 | 64% / 0 | Sonnet only (harm gate) |
| stop-hook | 14 | 79% / 0 | 86% / 0 | Sonnet only by rule (H within 7 points, below 80%) |
| agent-stopped | 14 | 36% / 1 | 71% / 0 | Sonnet only (harm gate) |
| build-compose | 12 | 33% / 0 | 50% / 2 | Sonnet only (S has 2 harmful too) |
| other | 12 | 33% / 1 | 50% / 0 | Sonnet only |

Sonnet is not clean either: 4 harmful, 29 syntax errors, 5 invented paths. Replay is the harsher test (no state checks, abridged inputs), so absolute agreement is lower than the live run; the Haiku-Sonnet gap is the signal.

## 3. LANE OPERATOR pilot (Haiku operator vs the real Sonnet operators)

What: Haiku agents `imm26-5090-i4-hk1` (first attempt only) and `imm26-5090-i4-hk2` ran test rows on lane 5090-i4 under the restricted operator brief (run one script, read the checker line, record, escalate on anything odd), compared against the Sonnet lane operators `imm26-5090-i3op21..25` that ran the same rows on other lanes/times. Window 2026-10-16 13:02-14:08, 13 rows. **COVERAGE: later events (rows after 14:08, and the shadow run) are not in the pilot data.** Not a controlled A/B: Sonnet ran on other lanes (5090-i3/i5, 4080-i3/i4) between 11:40 and 14:21 with different builds and checker versions.

| metric (source) | H pilot | Sonnet lane operators |
|---|---|---|
| rows with a verdict (pilot-audit.py) | 13 rows, 14 attempt lines, 20 verdict lines incl. 5 `00-*` questions | 17 RESULT files finished in the window (all paired agents) |
| rows per hour (pilot-audit.py) | 11.7 | 5.3 (gap between finished RESULT files across parallel agents; not like-for-like) |
| time per row (rowcmp, 13 windows) | 1h06m total, 5m05s mean | 1h33m total, 7m11s mean; Sonnet windows include retries/analysis |
| agreement with the checker RESULT line | 11/12 = 92% | n/a (Sonnet ground truth is the checker itself) |
| same final verdict as the Sonnet run of the same row | 8/13 identical (+02-cx identical after rerun); 4 differ (08-d, 20-d, 05-cx, 12-d) | n/a |
| cause of the differences | lane scene/tooling at that moment (trip setup, NPC placement, roster pin), not a misreading of the same output | |
| accepted PASS/FAIL | 5 of 13 rows | most |
| escalations | 8 rows (02-cx, 02-ax, 15-bx, 20-a, 23-e, 24-c, 05-cx, 12-d); by design every SETUP-FAIL/GATED escalates | n/a |
| refused wrong-verdict attempts | 1 (stale 02-ax PASS) | n/a |
| idle gap | 1 gap of 15m54s (brief to first START was 14m52s) | n/a |
| false (checkable) claims, pilot-audit.py | 12 of 39 claims false (33% of checkable); 9/9 count claims and 3/5 verdict claims wrong, mostly hk1 reports/relays and the 02-cx / 00-ask rows | 2 of 204 false (1%) |
| tokens, 13 row windows (pilot-rowcmp.py) | 5,671,134 | 7,870,334 |
| API-equiv USD, 13 row windows | $0.14 | $2.23 |
| cost per row, mean | $0.010 | $0.17 (about 16x) |
| cost per hour (cost-audit.py, hk1 vs op21/op22) | $0.16/h | $1.35-2.29/h |

Measurement: tokens/USD from Claude transcripts per message at its own model, windows = row START..end (pilot-rowcmp.py, `COMPARISON.md`); time/quality/false-claims from `pilot-audit.py` (`SUMMARY-final.md`, generated 16:13, window start 13:02). Caveat: the `cost-audit.py --pilot-compare` section of SUMMARY-final.md covers hk1 only (460,156 tokens, $0.01) against the full Sonnet operator sessions (3.4M-10.1M tokens, $0.53-$1.60 each); use the rowcmp totals above for row-level cost. Token totals are similar (cache reads); the cost gap is price per token.

**ab2 (`pilot\ab2`)**: a controlled A/B follow-up (same lane, same 10 rows, each run once by each model, A/B/B/A order, scene reset, identical brief, frozen plan seed 20261016). It was planned and its tooling written (README, brief, queue, plan.json created 15:35-15:41) but NEVER RUN: there is no `state.json`, no `captures.jsonl`, no `ab2-*` agent or status file. There are no ab2 results.

## 4. Decision table (task class -> use)

| task class | decision | evidence | confidence |
|---|---|---|---|
| Lane operator: run a row, read the checker RESULT line, record PASS/FAIL, escalate on odd (restricted brief) | Haiku ok, for the mechanical read-and-record part only; keep claims about counts/verdicts in reports checked | test 3: 92% agreement with checker, 8/13 same verdict (rest explained by tooling/lane), about 16x cheaper per row, shorter wall time; but 33% false checkable claims in its reports (hk1) | medium-low (13 rows, not controlled, 5 accepted PASS/FAIL) |
| Lane operator SETUP-FAIL / GATED diagnosis | Sonnet only (or coordinator reviews every Haiku escalation, as designed) | Haiku escalates all of them (8 of 13 rows); 4 rows differ from Sonnet because Haiku stopped earlier | low |
| Coordinator: relay/hand-back | Sonnet only | live 64 vs 79% (H missed 7 of 14); replay 29 vs 79%, H 1 harmful | high (consistent across tests) |
| Coordinator: waker digest | Sonnet only | live 33 vs 83%; replay 50 vs 92% (both arms 1 harmful) | high |
| Coordinator: lane alert | Sonnet only | live 75/75% (n=4); replay 36 vs 86% (S 1 harmful) | medium |
| Coordinator: setup-fail ticket | Sonnet only | live 33/33% (n=3); replay 21 vs 86% | medium (live sample tiny) |
| Coordinator: Shay message | Sonnet only | live 50 vs 100% (n=2); replay 29 vs 64% (H 1 harmful) | medium-high |
| Coordinator: agent stopped/dead | Sonnet only | live n=1; replay 36 vs 71%, H 1 harmful | medium |
| Coordinator: stop-hook feedback | Sonnet only, but the closest class | live 67 vs 50% (both weak, n=6); replay 79 vs 86%, no harm either arm | low-medium: a hybrid candidate if re-tested with n >= 15 |
| Coordinator: build/compose | Sonnet only (not graded live); Sonnet itself had 2 harmful | replay only: 33 vs 50% | low |
| Coordinator: other / small | undecided | live 100/100% (n=2); replay 33 vs 50%, H 1 harmful | low |
| Grading / mechanical reading of files (shadow graders, reader tasks) | not tested here | no data | none |

## 5. Overall answer

Keep Sonnet as the coordinator. Across both coordinator tests Haiku loses clearly on quality: 61% vs 71% agreement live (11 vs 5 missed events) and 38% vs 74% in the harsher replay (69 vs 27 worse decisions, 5 vs 4 harmful), with the same classes weak in both tests (relay, waker digest, setup-fail, agent-stopped, Shay message). Haiku is cheaper per unit: 2.3x per live decision ($0.020 vs $0.047), about 14x per replay run ($0.0067 vs $0.098) and about 16x per lane-operator row ($0.010 vs $0.17), but total spend per test is small ($0.8-$12 per arm), so a missed follow-up or invented id costs more than the saving. Neither arm reached the 80% bar in most classes, and Sonnet itself produced 4 harmful decisions in replay, so Sonnet is the better choice, not a safe one. A hybrid is supported only for the narrow lane-operator job (read a checker RESULT line, record, escalate everything odd), where Haiku matched the checker 92% of the time and the real Sonnet verdict on 8 of 13 rows, at roughly 1/16 of the cost; its prose claims need verification. Recommended next step if Shay wants more evidence: run the unrun controlled ab2 pilot (same lane, same rows, 20 runs) and a larger stop-hook/lane-operator sample.

## 6. Data gaps and caveats (so nothing is silently out of date)

- Test 3 covers only 13:02-14:08; its SUMMARY-final.md (regenerated 18:08, data cut at 16:13) says newer events (later rows, the shadow window 15:49-16:47) are not included. The verdicts.csv has 20 lines last written 14:08; Haiku operator work after 14:08 is not counted. A rerun of `pilot-audit.py` would not change that because the pilot stopped at 14:08 (SUMMARY-final shows 2h04m silent at generation); it was not re-run.
- Test 3 is not a controlled A/B (other lanes, builds, checker versions); 5 of 13 rows differ for those reasons; only 5 rows have an accepted Haiku PASS/FAIL. ab2 (the controlled version) was never run.
- Test 1: 38 batches (n 1-14 per class), one session, 57 min; the shadows could not verify state, which penalises invented-id claims; outcome labels mostly "unknown"; Haiku cost is a worst case under the 5x band rule.
- Test 2: replay agents saw today's CLAUDE.md and abridged inputs and had no tools to investigate; points come from sessions up to 2026-10-16 ~14:58, so decisions made later (and any rule changes after 16:11) are not covered; outcome label is a noisy heuristic.
- Grader (kenshi-grader) token costs for tests 1 and 2 are not included in any figure (not recorded in cost.json / runs.tsv; the replay README estimate of $5-7 is a plan estimate, not measured). Reason: grader transcripts were not part of shadow-cost.py / replay-run.py collection.
- Live output tokens are estimates (content chars / 3.5) because transcripts log only a placeholder; replay and pilot figures use the transcript values.
- Not tested at all: stage-3 hybrid live, Haiku as grader/reader, Haiku at other effort levels.
