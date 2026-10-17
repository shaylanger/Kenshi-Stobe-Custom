# replay2 cost (API-equivalent, prices.json; agent transcripts; same method as replay-run.py collect)

| arm | points | calls | calls/point | in | out | cache-w | cache-r | tokens | tokens/point | USD total | USD/point | wall s/point (critical path) | wall s/point (sum of calls) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Haiku pair | 120 | 546 | 4.55 | 3970 | 2935645 | 16699211 | 47233839 | 66872665 | 557272 | 6.734 | 0.0561 | 86.0 | 141.6 |
| Draft-review | 120 | 240 | 2.00 | 1458 | 620291 | 7818615 | 19436366 | 27876730 | 232306 | 13.288 | 0.1107 | 41.4 | 41.4 |
| Guard rails | 120 | 120 | 1.00 | 992 | 557608 | 4154563 | 12556627 | 17269790 | 143914 | 0.924 | 0.0077 | 31.4 | 31.4 |

Draft-review total = Haiku draft (existing run P###-ra, counted here) + Sonnet review. Pair wall time (critical path) = max of the two parallel agents in each of R1, R2 + R3 when it ran.
Graders for these 3 arms (replay2 chunks): 15 transcripts, 10258959 tokens, $4.356.
