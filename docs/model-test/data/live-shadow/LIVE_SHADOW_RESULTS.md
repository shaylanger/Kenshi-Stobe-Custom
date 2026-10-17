# Coordinator shadow run: Haiku High (H) vs Sonnet High (S): REPORT

Written 2026-10-16 by coordinator 22. Covers the LIVE shadow run only (coordinator 20's session, feed 15:49-16:47, batches 1-38 of 38; both arms answered every batch). Stage-1 offline replay results are separate: `shadow\replay\aggregate.md`. Full table: `shadow\live-grading\aggregate.md`. Grading: 5 blind kenshi-grader chunks (A/B randomised per point, key in `live-grading\key.json`), 38 points.

## Result
| | H (Haiku High) | S (Sonnet High) |
|---|---|---|
| graded decisions | 38 | 38 |
| agreement with real coordinator (equivalent + acceptable-different) | 61% | 71% |
| worse | 15 | 11 |
| HARMFUL (harm gate a-i) | 0 | 0 |
| missed events (real coordinator acted, arm only ignored/waited) | 11 | 5 |
| extra actions | 4 | 4 |
| invalid commands (final lines / all lines) | 0 / 1 of 106 | 0 / 4 of 91 |
| median latency per batch | 13.6 s | 8.9 s |
| total tokens (input + output + cache write + cache read) | 15,799,012 | 11,137,408 |
| of which cache read / cache write / fresh input / output (est) | 15,504,640 / 270,880 / 276 / 23,216 | 10,922,571 / 193,631 / 184 / 21,022 |
| API-equivalent USD (prices.json; output estimated from content) | $0.763 (logged-output floor $0.724) | $1.787 (floor $1.598) |
| USD per graded decision / per active hour (0.95 h) | $0.020 / $0.81 | $0.047 / $1.88 |
| USD per agreeing decision (23 H, 27 S of 38) | $0.033 | $0.066 |
| API calls / tokens per decision | 138 / 415k | 92 / 293k |
| context size first -> last call | 27k -> 209k (78 of 138 calls over 100k) | 27k -> 206k (54 of 92 over 100k) |

All 38 real-coordinator actions were judged acceptable by the graders (truth_ok 38/38), so agreement is measured against a sound baseline.

## Per class (mechanical rule: core class with any harmful or < 80% agreement = Sonnet only)
| class | n | H agree | S agree | verdict |
|---|---|---|---|---|
| relay/hand-back | 14 | 64% | 79% | Sonnet only (H missed 7 vs 1) |
| setup-fail ticket | 3 | 33% | 33% | Sonnet only (both weak, n=3) |
| lane alert | 4 | 75% | 75% | Sonnet only (below 80%, n=4) |
| waker digest | 6 | 33% | 83% | Sonnet only |
| Shay message | 2 | 50% | 100% | Sonnet only (n=2) |
| stop-hook feedback | 6 | 67% | 50% | Sonnet only (both weak) |
| agent stopped/dead | 1 | 100% | 0% | n=1, no conclusion |
| other | 2 | 100% | 100% | Haiku ok (n=2) |

## Reading it
- No arm produced a harmful decision, so the harm gate did not fail any class on this sample.
- Haiku is clearly worse on relay/hand-back (misses the follow-up action 7 of 14 times) and on waker digests; Sonnet is better but not at the 80% bar in several classes either. Typical defects for BOTH arms: re-spawning an agent an earlier event already launched, acking or messaging an invented target (an agent or alert id not in the input), unrequested lanes.held edits, missing the HANDOFF update after a report.
- Stage-3 hybrid (Haiku for mechanical classes) is NOT supported by this data for relay, waker digest, lane alert or setup-fail; only tiny classes (other, n=2) look fine.
- Caveats: n is small per class (1-14); outcome labels are heuristic ("unknown" for 37 of 38, not "truth was good"); tokens/cost come from the subagent transcripts (`live-grading\cost.json`, script `tools/automation/shadow-replay/shadow-cost.py`), not the ledgers; the transcripts log only about 15 output tokens per call, so output is estimated as content chars / 3.5 (output is under 0.2% of tokens, but ~12% of Sonnet's USD); H = two agents (first spawn ended after 7 min, resume ran to the end, both counted); both shadows saw a fixed feed and could not run commands to verify state, which penalises invented-id claims.
- Audit (`shadow_audit.py check`, baseline `shadow\audit-pre-git.txt`): 3248 change lines, 12 git-status and 3236 mtime-only; the workspace was busy with real agents during the window, so the audit cannot attribute any change to a shadow. No shadow-written file was identified; judge by hand if needed.

## Cost (tokens used)
- Both arms re-read a growing context every call (cache read is 98% of tokens): H 15.8M tokens, S 11.1M tokens over about 57 minutes each; the totals are cache-read tokens, which are billed at 1/10 (Haiku) or 1/20 (Sonnet) of the input rate.
- Per hour (local, MDT) H: 15:xx 2.2M tok $0.039 (10 min), 16:xx 13.6M tok $0.724; S: 15:xx 2.4M tok $0.483, 16:xx 8.8M tok $1.304. Context grew from 27k to about 206-209k in both arms, so cost per decision rises through the run.
- Haiku 5.5 is billed at the 5x over-100k rate whole-prompt for 78 of 138 calls (prices.json assumption); at the base Haiku rate the same tokens would cost about $0.20, so the Haiku figure is a worst case under that band rule. Even so Haiku is 2.3x cheaper than Sonnet per decision ($0.020 vs $0.047), 2.0x cheaper per agreeing decision ($0.033 vs $0.066).
- The whole 38-decision run cost under $2.00 per arm, so the quality gap (61% vs 71% agreement, 11 vs 5 missed events) matters far more than the roughly $1 per hour saving: a missed follow-up costs more than the saving. Cost does not change the recommendation.

## Recommendation
Keep Sonnet as coordinator. A hybrid is not justified yet (tokens/cost measured: Haiku saves about $0.027 per decision, and loses about 10 points of agreement and 6 more missed events over 38 decisions). If Shay wants more evidence: re-run (cost is now captured by `shadow-cost.py` from the transcripts) and give shadows read-only state checks, and grade relay/waker-digest classes with n >= 15 per arm.
