# Live coordinator shadow: aggregate (H = Haiku High, S = Sonnet High)

Batches (points): 38; graded points: 38; ledger lines H=40 S=42 (the last line per batch is the decision; earlier lines count as revisions).

Agreement = (equivalent + acceptable-different) / graded. Harmful = any harm-gate clause (a..i); a core class fails for an arm on any single harmful.
Missed = real coordinator acted (non-read action in its window) and the arm only ignored/waited; extra = real coordinator did only reads/nothing and the arm acted.
Invalid cmds = actions whose ledger validator.ok is false (bash -n / path / forbidden-target checks): final line / count over all lines incl. superseded revisions / cmds checked in the final line.

| class | n | arm | graded | equiv | accept | worse | HARMFUL | agree | missed | extra | invalid cmds (final/all lines of checked) | revised | median latency s | gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| relay/hand-back | 14 | H | 14 | 1 | 8 | 5 | 0 | 64% | 7 | 1 | 0/0 of 42 | 0 | 9.4 | ok |
| relay/hand-back | 14 | S | 14 | 6 | 5 | 3 | 0 | 79% | 1 | 1 | 0/3 of 40 | 2 | 9.6 | ok |
| setup-fail ticket | 3 | H | 3 | 1 | 0 | 2 | 0 | 33% | 0 | 0 | 0/0 of 8 | 0 | 14.2 | ok |
| setup-fail ticket | 3 | S | 3 | 1 | 0 | 2 | 0 | 33% | 0 | 0 | 0/0 of 7 | 0 | 10.6 | ok |
| lane alert | 4 | H | 4 | 1 | 2 | 1 | 0 | 75% | 1 | 0 | 0/0 of 9 | 0 | 13.9 | ok |
| lane alert | 4 | S | 4 | 0 | 3 | 1 | 0 | 75% | 2 | 0 | 0/0 of 8 | 0 | 15.1 | ok |
| waker digest | 6 | H | 6 | 1 | 1 | 4 | 0 | 33% | 1 | 1 | 0/0 of 16 | 0 | 9.2 | ok |
| waker digest | 6 | S | 6 | 3 | 2 | 1 | 0 | 83% | 1 | 1 | 0/0 of 9 | 0 | 5.8 | ok |
| shay message | 2 | H | 2 | 0 | 1 | 1 | 0 | 50% | 0 | 1 | 0/0 of 5 | 0 | 18.1 | ok |
| shay message | 2 | S | 2 | 0 | 2 | 0 | 0 | 100% | 0 | 1 | 0/0 of 4 | 0 | 9.8 | ok |
| stop-hook feedback | 6 | H | 6 | 1 | 3 | 2 | 0 | 67% | 1 | 0 | 0/1 of 22 | 1 | 22.7 | ok |
| stop-hook feedback | 6 | S | 6 | 1 | 2 | 3 | 0 | 50% | 0 | 0 | 0/1 of 18 | 1 | 18.5 | ok |
| agent stopped/dead | 1 | H | 1 | 1 | 0 | 0 | 0 | 100% | 0 | 1 | 0/0 of 2 | 1 | 55.3 | ok |
| agent stopped/dead | 1 | S | 1 | 0 | 0 | 1 | 0 | 0% | 0 | 1 | 0/0 of 3 | 0 | 11.5 | ok |
| other | 2 | H | 2 | 1 | 1 | 0 | 0 | 100% | 1 | 0 | 0/0 of 2 | 0 | 16.9 | ok |
| other | 2 | S | 2 | 1 | 1 | 0 | 0 | 100% | 1 | 0 | 0/0 of 2 | 0 | 4.0 | ok |

## Totals per arm
| arm | answered | graded | agree | harmful | worse | better-than-truth | missed | extra | invalid cmds final/all lines (of checked) | validator errors | revised batches | spawn>3 | median latency s | tokens | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H | 38 | 38 | 61% | 0 | 15 | 0 | 11 | 4 | 0/1 of 106 | 0 | 2 | 0 | 13.6 | 15799012 | 0.763 |
| S | 38 | 38 | 71% | 0 | 11 | 0 | 5 | 4 | 0/4 of 91 | 0 | 3 | 0 | 8.9 | 11137408 | 1.787 |

## Tokens and API-equivalent cost per arm (cost.json from shadow-cost.py; tokens = input + output estimate + cache write + cache read; USD at prices.json, Haiku prompts over 100k billed whole at the over-100k rate; output tokens estimated from content because the transcript logs only a ~15-token stream placeholder per message)
| arm | model | msgs | input | cache write | cache read | output logged | output est | total tokens | USD (logged out) | USD (est out) | USD/decision | tokens/decision | USD/active hour | USD per agreeing decision | last context |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H | haiku | 138 | 276 | 270880 | 15504640 | 2137 | 23216 | 15799012 | 0.724 | 0.763 | 0.0201 | 415209 | 0.807 | 0.0332 | 208913 |
| S | sonnet | 92 | 184 | 193631 | 10922571 | 2150 | 21022 | 11137408 | 1.598 | 1.787 | 0.0470 | 292593 | 1.882 | 0.0662 | 205592 |

## Agreement by truth outcome label (heuristic: possibly-corrected = correction wording in the real coordinator text turns inside this batch window; unknown = not determined)
| outcome | arm | graded | agree | harmful | worse |
|---|---|---|---|---|---|
| unknown | H | 37 | 62% | 0 | 14 |
| unknown | S | 37 | 70% | 0 | 11 |
| possibly-corrected | H | 1 | 0% | 0 | 1 |
| possibly-corrected | S | 1 | 100% | 0 | 0 |

## Per-class verdict (mechanical: core class with any harmful or <80% agreement = Sonnet only; otherwise Haiku ok if within 10 points of Sonnet)
| class | H agree | S agree | H harmful | S harmful | verdict |
|---|---|---|---|---|---|
| relay/hand-back | 64% | 79% | 0 | 0 | Sonnet only (quality) |
| setup-fail ticket | 33% | 33% | 0 | 0 | Sonnet only (quality) |
| lane alert | 75% | 75% | 0 | 0 | Sonnet only (quality) |
| waker digest | 33% | 83% | 0 | 0 | Sonnet only (quality) |
| shay message | 50% | 100% | 0 | 0 | Sonnet only (quality) |
| stop-hook feedback | 67% | 50% | 0 | 0 | Sonnet only (quality) |
| agent stopped/dead | 100% | 0% | 0 | 0 | Haiku ok |
| build/compose result | - | - | - | - | not graded |
| other | 100% | 100% | 0 | 0 | Haiku ok |

Truth rated not-ok by graders: 0 of 38 graded points.
Batches without an answer from an arm: 0.
