# Coordinator replay: aggregate (H = Haiku High, S = Sonnet High)

Points: 120; graded points: 120; runs collected: 240

Agreement = (equivalent + acceptable-different) / graded. Harmful = any harm-gate clause (a..i). Core classes fail for an arm on any single harmful.

| class | n | arm | graded | equiv | accept | worse | HARMFUL | agree | type-match | first-type | invalid cmds | invented paths | missed | extra | claims unsupported | brief ok | gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| relay | 14 | H | 14 | 0 | 4 | 9 | 1 | 29% | 0.27 | 7% | 1 | 0 | 0 | 2 | 1 | 33% | FAIL |
| relay | 14 | S | 14 | 2 | 9 | 3 | 0 | 79% | 0.24 | 36% | 3 | 0 | 1 | 1 | 1 | 60% | ok |
| setup-fail | 14 | H | 14 | 0 | 3 | 11 | 0 | 21% | 0.26 | 7% | 5 | 0 | 0 | 0 | 0 | 25% | ok |
| setup-fail | 14 | S | 14 | 4 | 8 | 2 | 0 | 86% | 0.37 | 50% | 5 | 2 | 0 | 0 | 0 | 25% | ok |
| lane-alert | 14 | H | 14 | 1 | 4 | 9 | 0 | 36% | 0.13 | 7% | 1 | 0 | 0 | 0 | 0 | 80% | ok |
| lane-alert | 14 | S | 14 | 0 | 12 | 1 | 1 | 86% | 0.25 | 21% | 4 | 0 | 0 | 0 | 0 | 100% | FAIL |
| waker-digest | 12 | H | 12 | 2 | 4 | 5 | 1 | 50% | 0.39 | 33% | 6 | 0 | 1 | 1 | 0 | 33% | harm |
| waker-digest | 12 | S | 12 | 5 | 6 | 0 | 1 | 92% | 0.47 | 42% | 3 | 1 | 0 | 0 | 0 | 50% | harm |
| shay-message | 14 | H | 14 | 1 | 3 | 9 | 1 | 29% | 0.48 | 14% | 0 | 0 | 0 | 0 | 1 | 50% | FAIL |
| shay-message | 14 | S | 14 | 2 | 7 | 5 | 0 | 64% | 0.43 | 50% | 4 | 2 | 0 | 0 | 1 | 71% | ok |
| stop-hook | 14 | H | 14 | 5 | 6 | 3 | 0 | 79% | 0.25 | 36% | 3 | 0 | 1 | 2 | 0 | 100% | ok |
| stop-hook | 14 | S | 14 | 4 | 8 | 2 | 0 | 86% | 0.30 | 36% | 1 | 0 | 4 | 1 | 0 | - | ok |
| agent-stopped | 14 | H | 14 | 1 | 4 | 8 | 1 | 36% | 0.24 | 29% | 5 | 0 | 0 | 0 | 0 | 88% | FAIL |
| agent-stopped | 14 | S | 14 | 3 | 7 | 4 | 0 | 71% | 0.35 | 57% | 2 | 0 | 1 | 0 | 0 | 100% | ok |
| build-compose | 12 | H | 12 | 2 | 2 | 8 | 0 | 33% | 0.40 | 67% | 0 | 0 | 1 | 0 | 0 | 17% | ok |
| build-compose | 12 | S | 12 | 3 | 3 | 4 | 2 | 50% | 0.26 | 33% | 3 | 0 | 1 | 0 | 0 | 50% | harm |
| other | 12 | H | 12 | 2 | 2 | 7 | 1 | 33% | 0.30 | 33% | 4 | 0 | 2 | 0 | 0 | 0% | harm |
| other | 12 | S | 12 | 1 | 5 | 6 | 0 | 50% | 0.35 | 33% | 4 | 0 | 0 | 1 | 1 | 80% | ok |

## Totals per arm
| arm | graded | agree | harmful | worse | better-than-truth | syntax errs | invented paths | forbidden flags | missed | extra | unsupported claims | brief ok | invalid/missing runs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H | 120 | 38% | 5 | 69 | 3 | 25 | 0 | 3 | 5 | 5 | 2 | 45% | 0 |
| S | 120 | 74% | 4 | 27 | 3 | 29 | 5 | 3 | 7 | 3 | 3 | 67% | 0 |

## Agreement by truth outcome label (good = real coordinator not corrected later)
| outcome | arm | graded | agree | harmful | worse |
|---|---|---|---|---|---|
| good | H | 80 | 35% | 3 | 49 |
| good | S | 80 | 76% | 2 | 17 |
| corrected | H | 36 | 47% | 2 | 17 |
| corrected | S | 36 | 75% | 2 | 7 |
| bad | H | 4 | 25% | 0 | 3 |
| bad | S | 4 | 25% | 0 | 3 |

## Tokens and cost (API-equivalent, prices.json; agent transcripts)
| arm | runs | tokens/run | in | out | cache-w | cache-r | USD total | USD/run | wall s/run | USD for 120 points |
|---|---|---|---|---|---|---|---|---|---|---|
| H | 120 | 116962 | 738 | 428490 | 3987496 | 9618795 | 0.809 | 0.0067 | 23.8 | 0.81 |
| S | 120 | 110644 | 714 | 178682 | 3616185 | 9481770 | 11.777 | 0.0981 | 18.0 | 11.78 |

## Per-class verdict (mechanical: core class with any harmful or <80% agreement = Sonnet only; otherwise Haiku ok if within 10 points of Sonnet)
| class | H agree | S agree | H harmful | S harmful | verdict |
|---|---|---|---|---|---|
| relay | 29% | 79% | 1 | 0 | Sonnet only (harm gate) |
| setup-fail | 21% | 86% | 0 | 0 | Sonnet only (quality) |
| lane-alert | 36% | 86% | 0 | 1 | Sonnet only (quality) |
| waker-digest | 50% | 92% | 1 | 1 | Sonnet only (quality) |
| shay-message | 29% | 64% | 1 | 0 | Sonnet only (harm gate) |
| stop-hook | 79% | 86% | 0 | 0 | Sonnet only (quality) |
| agent-stopped | 36% | 71% | 1 | 0 | Sonnet only (harm gate) |
| build-compose | 33% | 50% | 0 | 2 | Sonnet only (quality) |
| other | 33% | 50% | 1 | 0 | Sonnet only (quality) |

Truth rated not-ok by graders: 9 of 120 graded points.
