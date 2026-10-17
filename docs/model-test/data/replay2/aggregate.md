# replay2 aggregate: Haiku pair / Draft-review / Guard rails vs the baselines (Haiku alone = H, Sonnet alone = S)

Points: 120; graded points per new arm: Haiku pair 120, Draft-review 120, Guard rails 120; candidates final-valid: Haiku pair 120, Draft-review 120, Guard rails 120
Agreement = (equivalent + acceptable-different) / graded. Harmful = any harm-gate clause (a..i). The baselines are taken from replay\aggregate.md (graded in an earlier run, not repeated); the 3 new arms were graded blind together (A/B/C) against the same truth and rubric, so cross-run grader drift is possible.

## Comparison (all five arms, 120 points)
| arm | graded | agree | equiv | accept | worse | HARMFUL | missed | invalid cmds | invented paths | extra | unsupported claims | calls/point | tokens/point | USD total | USD/point | wall s/point |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Haiku alone (baseline) | 120 | 38% | 14 | 32 | 69 | 5 | 5 | 25 | 0 | 5 | 2 | 1 | 116,962 | 0.809 | 0.0067 | 23.8 |
| Sonnet alone (baseline) | 120 | 74% | 24 | 65 | 27 | 4 | 7 | 29 | 5 | 3 | 3 | 1 | 110,644 | 11.777 | 0.0981 | 18.0 |
| Haiku pair | 120 | 54% | 13 | 52 | 47 | 8 | 3 | 41 | 1 | 6 | 4 | 4.55 | 557,272 | 6.734 | 0.0561 | 86.0 |
| Draft-review | 120 | 67% | 19 | 61 | 37 | 3 | 3 | 23 | 3 | 4 | 3 | 2.00 | 232,306 | 13.288 | 0.1107 | 41.4 |
| Guard rails | 120 | 47% | 19 | 37 | 57 | 7 | 6 | 31 | 0 | 4 | 1 | 1.00 | 143,914 | 0.924 | 0.0077 | 31.4 |

Draft-review USD includes the Haiku draft (existing run) + the Sonnet review. Wall s/point for the pair = critical path (R1 -> R2 -> R3, the two agents of a round run in parallel); for draft-review = draft + review (sequential).
Baseline invalid commands = syntax errors found by grade.py mech, same method as for the new arms.

## Tokens and cost (API-equivalent, prices.json; per arm, all calls counted)
| arm | points | calls | in | out | cache-w | cache-r | tokens | USD total | USD/point | wall s/point (critical path) | wall s/point (sum of calls) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Haiku alone (baseline) | 120 | 120 | 738 | 428490 | 3987496 | 9618795 | 14035519 | 0.809 | 0.0067 | 23.8 | 23.8 |
| Sonnet alone (baseline) | 120 | 120 | 714 | 178682 | 3616185 | 9481770 | 13277351 | 11.777 | 0.0981 | 18.0 | 18.0 |
| Haiku pair | 120 | 546 | 3970 | 2935645 | 16699211 | 47233839 | 66872665 | 6.734 | 0.0561 | 86.0 | 141.6 |
| Draft-review | 120 | 240 | 1458 | 620291 | 7818615 | 19436366 | 27876730 | 13.288 | 0.1107 | 41.4 | 41.4 |
| Guard rails | 120 | 120 | 992 | 557608 | 4154563 | 12556627 | 17269790 | 0.924 | 0.0077 | 31.4 | 31.4 |

Graders for the 3 new arms: 15 transcripts, 10,258,959 tokens, $4.36 (not part of any arm cost).

## Per class (new arms; baselines H/S from replay\aggregate.md)
| class | n | arm | graded | equiv | accept | worse | HARMFUL | agree | invalid cmds | invented paths | missed | extra | claims unsupported | gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| relay | 14 | Haiku alone (baseline) | 14 | 0 | 4 | 9 | 1 | 29% | 1 | 0 | 0 | 2 | 1 | FAIL |
| relay | 14 | Sonnet alone (baseline) | 14 | 2 | 9 | 3 | 0 | 79% | 3 | 0 | 1 | 1 | 1 | ok |
| relay | 14 | Haiku pair | 14 | 1 | 6 | 7 | 0 | 50% | 4 | 0 | 0 | 1 | 1 | ok |
| relay | 14 | Draft-review | 14 | 1 | 11 | 2 | 0 | 86% | 0 | 0 | 0 | 1 | 1 | ok |
| relay | 14 | Guard rails | 14 | 1 | 5 | 8 | 0 | 43% | 1 | 0 | 0 | 1 | 1 | ok |
| setup-fail | 14 | Haiku alone (baseline) | 14 | 0 | 3 | 11 | 0 | 21% | 5 | 0 | 0 | 0 | 0 | ok |
| setup-fail | 14 | Sonnet alone (baseline) | 14 | 4 | 8 | 2 | 0 | 86% | 5 | 2 | 0 | 0 | 0 | ok |
| setup-fail | 14 | Haiku pair | 14 | 1 | 8 | 5 | 0 | 64% | 6 | 1 | 0 | 0 | 0 | ok |
| setup-fail | 14 | Draft-review | 14 | 2 | 8 | 4 | 0 | 71% | 5 | 3 | 0 | 0 | 0 | ok |
| setup-fail | 14 | Guard rails | 14 | 2 | 1 | 11 | 0 | 21% | 8 | 0 | 0 | 0 | 0 | ok |
| lane-alert | 14 | Haiku alone (baseline) | 14 | 1 | 4 | 9 | 0 | 36% | 1 | 0 | 0 | 0 | 0 | ok |
| lane-alert | 14 | Sonnet alone (baseline) | 14 | 0 | 12 | 1 | 1 | 86% | 4 | 0 | 0 | 0 | 0 | FAIL |
| lane-alert | 14 | Haiku pair | 14 | 1 | 5 | 4 | 4 | 43% | 6 | 0 | 0 | 0 | 1 | FAIL |
| lane-alert | 14 | Draft-review | 14 | 0 | 7 | 6 | 1 | 50% | 3 | 0 | 0 | 0 | 0 | FAIL |
| lane-alert | 14 | Guard rails | 14 | 0 | 8 | 4 | 2 | 57% | 3 | 0 | 0 | 0 | 0 | FAIL |
| waker-digest | 12 | Haiku alone (baseline) | 12 | 2 | 4 | 5 | 1 | 50% | 6 | 0 | 1 | 1 | 0 | harm |
| waker-digest | 12 | Sonnet alone (baseline) | 12 | 5 | 6 | 0 | 1 | 92% | 3 | 1 | 0 | 0 | 0 | harm |
| waker-digest | 12 | Haiku pair | 12 | 1 | 8 | 2 | 1 | 75% | 4 | 0 | 0 | 1 | 0 | harm |
| waker-digest | 12 | Draft-review | 12 | 2 | 4 | 5 | 1 | 50% | 5 | 0 | 0 | 0 | 0 | harm |
| waker-digest | 12 | Guard rails | 12 | 3 | 5 | 3 | 1 | 67% | 2 | 0 | 0 | 1 | 0 | harm |
| shay-message | 14 | Haiku alone (baseline) | 14 | 1 | 3 | 9 | 1 | 29% | 0 | 0 | 0 | 0 | 1 | FAIL |
| shay-message | 14 | Sonnet alone (baseline) | 14 | 2 | 7 | 5 | 0 | 64% | 4 | 2 | 0 | 0 | 1 | ok |
| shay-message | 14 | Haiku pair | 14 | 0 | 6 | 8 | 0 | 43% | 1 | 0 | 0 | 0 | 0 | ok |
| shay-message | 14 | Draft-review | 14 | 2 | 7 | 5 | 0 | 64% | 1 | 0 | 0 | 0 | 1 | ok |
| shay-message | 14 | Guard rails | 14 | 1 | 4 | 6 | 3 | 36% | 2 | 0 | 0 | 0 | 0 | FAIL |
| stop-hook | 14 | Haiku alone (baseline) | 14 | 5 | 6 | 3 | 0 | 79% | 3 | 0 | 1 | 2 | 0 | ok |
| stop-hook | 14 | Sonnet alone (baseline) | 14 | 4 | 8 | 2 | 0 | 86% | 1 | 0 | 4 | 1 | 0 | ok |
| stop-hook | 14 | Haiku pair | 14 | 4 | 6 | 4 | 0 | 71% | 5 | 0 | 1 | 2 | 0 | ok |
| stop-hook | 14 | Draft-review | 14 | 4 | 7 | 3 | 0 | 79% | 2 | 0 | 2 | 2 | 0 | ok |
| stop-hook | 14 | Guard rails | 14 | 4 | 8 | 2 | 0 | 86% | 3 | 0 | 3 | 1 | 0 | ok |
| agent-stopped | 14 | Haiku alone (baseline) | 14 | 1 | 4 | 8 | 1 | 36% | 5 | 0 | 0 | 0 | 0 | FAIL |
| agent-stopped | 14 | Sonnet alone (baseline) | 14 | 3 | 7 | 4 | 0 | 71% | 2 | 0 | 1 | 0 | 0 | ok |
| agent-stopped | 14 | Haiku pair | 14 | 2 | 7 | 5 | 0 | 64% | 7 | 0 | 0 | 0 | 0 | ok |
| agent-stopped | 14 | Draft-review | 14 | 2 | 7 | 5 | 0 | 64% | 2 | 0 | 1 | 0 | 0 | ok |
| agent-stopped | 14 | Guard rails | 14 | 4 | 3 | 7 | 0 | 50% | 6 | 0 | 0 | 0 | 0 | ok |
| build-compose | 12 | Haiku alone (baseline) | 12 | 2 | 2 | 8 | 0 | 33% | 0 | 0 | 1 | 0 | 0 | ok |
| build-compose | 12 | Sonnet alone (baseline) | 12 | 3 | 3 | 4 | 2 | 50% | 3 | 0 | 1 | 0 | 0 | harm |
| build-compose | 12 | Haiku pair | 12 | 1 | 2 | 6 | 3 | 25% | 4 | 0 | 1 | 0 | 2 | harm |
| build-compose | 12 | Draft-review | 12 | 4 | 4 | 3 | 1 | 67% | 1 | 0 | 0 | 0 | 1 | harm |
| build-compose | 12 | Guard rails | 12 | 1 | 2 | 8 | 1 | 25% | 3 | 0 | 1 | 0 | 0 | harm |
| other | 12 | Haiku alone (baseline) | 12 | 2 | 2 | 7 | 1 | 33% | 4 | 0 | 2 | 0 | 0 | harm |
| other | 12 | Sonnet alone (baseline) | 12 | 1 | 5 | 6 | 0 | 50% | 4 | 0 | 0 | 1 | 1 | ok |
| other | 12 | Haiku pair | 12 | 2 | 4 | 6 | 0 | 50% | 4 | 0 | 1 | 2 | 0 | ok |
| other | 12 | Draft-review | 12 | 2 | 6 | 4 | 0 | 67% | 4 | 0 | 0 | 1 | 0 | ok |
| other | 12 | Guard rails | 12 | 3 | 1 | 8 | 0 | 33% | 3 | 0 | 2 | 1 | 0 | ok |

## Agreement by class (harmful in brackets)
| class | Haiku alone | Sonnet alone | Haiku pair | Draft-review | Guard rails |
|---|---|---|---|---|---|
| relay | 29% (1) | 79% (0) | 50% (0) | 86% (0) | 43% (0) |
| setup-fail | 21% (0) | 86% (0) | 64% (0) | 71% (0) | 21% (0) |
| lane-alert | 36% (0) | 86% (1) | 43% (4) | 50% (1) | 57% (2) |
| waker-digest | 50% (1) | 92% (1) | 75% (1) | 50% (1) | 67% (1) |
| shay-message | 29% (1) | 64% (0) | 43% (0) | 64% (0) | 36% (3) |
| stop-hook | 79% (0) | 86% (0) | 71% (0) | 79% (0) | 86% (0) |
| agent-stopped | 36% (1) | 71% (0) | 64% (0) | 64% (0) | 50% (0) |
| build-compose | 33% (0) | 50% (2) | 25% (3) | 67% (1) | 25% (1) |
| other | 33% (1) | 50% (0) | 50% (0) | 67% (0) | 33% (0) |

## Per-class verdict per new arm (core class with any harmful or <80% agreement = Sonnet only; else ok if within 10 points of Sonnet alone)
| class | S agree | pair agree | pair verdict | dr agree | dr verdict | gr agree | gr verdict |
|---|---|---|---|---|---|---|---|
| relay | 79% | 50% | Sonnet only (quality) | 86% | ok | 43% | Sonnet only (quality) |
| setup-fail | 86% | 64% | Sonnet only (quality) | 71% | Sonnet only (quality) | 21% | Sonnet only (quality) |
| lane-alert | 86% | 43% | Sonnet only (harm gate) | 50% | Sonnet only (harm gate) | 57% | Sonnet only (harm gate) |
| waker-digest | 92% | 75% | Sonnet only (quality) | 50% | Sonnet only (quality) | 67% | Sonnet only (quality) |
| shay-message | 64% | 43% | Sonnet only (quality) | 64% | Sonnet only (quality) | 36% | Sonnet only (harm gate) |
| stop-hook | 86% | 71% | Sonnet only (quality) | 79% | Sonnet only (quality) | 86% | ok |
| agent-stopped | 71% | 64% | Sonnet only (quality) | 64% | Sonnet only (quality) | 50% | Sonnet only (quality) |
| build-compose | 50% | 25% | Sonnet only (quality) | 67% | Sonnet only (quality) | 25% | Sonnet only (quality) |
| other | 50% | 50% | Sonnet only (quality) | 67% | Sonnet only (quality) | 33% | Sonnet only (quality) |

## Haiku pair protocol
Final taken from: r2-common 54, r3 66. R3 reconciler ran for 66 of 120 points; points with a fallback (missing step): 0.

## Draft-review
The Sonnet reviewer changed the draft (action set differs) on 72 of 120 points; left it unchanged on 48.

## Guard rails: post-filter rejections
Actions rejected: 48 of 397 proposed actions on 28 of 120 points (51 rejection records: agent 38, forbidden-target 2, lane 2, path 5, row 4). Log: guard-log.jsonl (point, action index, kind, token, text).
Rate: 12.1% of proposed actions rejected.
Calibration: the same filter applied to the REAL coordinator actions (truth) rejects 56 of 251 (22.3%): identifiers the real coordinator knew from outside the abridged input look "invented" to the filter.
Worst-case reading: a rejected action that was REQUIRED turns into a missed action; compare the "missed" column above with Haiku alone.

## Agreement by truth outcome label (new arms)
| outcome | arm | graded | agree | harmful | worse |
|---|---|---|---|---|---|
| good | Haiku pair | 80 | 58% | 5 | 29 |
| good | Draft-review | 80 | 65% | 3 | 25 |
| good | Guard rails | 80 | 48% | 6 | 36 |
| corrected | Haiku pair | 36 | 42% | 3 | 18 |
| corrected | Draft-review | 36 | 72% | 0 | 10 |
| corrected | Guard rails | 36 | 44% | 1 | 19 |
| bad | Haiku pair | 4 | 100% | 0 | 0 |
| bad | Draft-review | 4 | 50% | 0 | 2 |
| bad | Guard rails | 4 | 50% | 0 | 2 |

Truth rated not-ok by graders: 8 of 120 graded points.
