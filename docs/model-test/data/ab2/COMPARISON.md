# Pilot 2 (ab2): Haiku High vs Sonnet High, same rows, lane 5090-i4

seed 20261016, plan created 2026-10-16T19:32:38; baseline {"dll_mods": "3FE805BF", "dll_re": "3FE805BF", "bundle": "21f3eef15a89", "saves": {"kah-imm26-i4": "227:83c34fdc58", "kah-imm26-i4-hx0": "232:99fa19fde9"}}

| row | order | Haiku checker | Haiku operator (agree) | Sonnet checker | Sonnet operator (agree) | checkers same? | Haiku script wall | Sonnet script wall | Haiku op wall | Sonnet op wall | Haiku tokens | Haiku USD | Sonnet tokens | Sonnet USD | esc H/S | refused H/S | status-count H/S | drift |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 17-bx | sonnet first | PASS | PASS (1) | VOID | - (-) | - | 4m15s | - | 4m20s | - | 180,894 | $0.006 | 117,165 | $0.057 | 0/0 | 0/0 | ok/ok | - |
| 05-cx | haiku first | VOID | - (-) | VOID | - (-) | - | - | - | - | - | 147,929 | $0.004 | 124,241 | $0.062 | 0/0 | 0/0 | ok/ok | - |
| 02-ax | haiku first | PASS | PASS (1) | FAIL | FAIL (1) | DIFFERENT | 3m59s | 3m59s | 4m05s | 4m06s | 190,202 | $0.008 | 190,427 | $0.119 | 0/0 | 0/0 | ok/ok | - |
| 02-cx | sonnet first | PASS | PASS (1) | PASS | PASS (1) | SAME | 8m15s | 9m01s | 8m25s | 9m06s | 292,500 | $0.009 | 358,733 | $0.151 | 0/0 | 0/0 | ok/ok | - |
| 01-bx | sonnet first | PASS | PASS (1) | FAIL | FAIL (1) | DIFFERENT | 20m44s | 19m55s | 20m55s | 20m04s | 293,582 | $0.014 | 312,356 | $0.192 | 0/0 | 0/0 | ok/ok | - |
| 27-a | haiku first | SETUP-FAIL | ESCALATE (n/a) | PASS | PASS (1) | DIFFERENT | 3m43s | 3m15s | 3m48s | 3m19s | 189,907 | $0.008 | 189,511 | $0.070 | 1/0 | 0/0 | ok/ok | - |
| 01-cx | haiku first | - | - (-) | - | - (-) | - | - | - | - | - | - | - | - | - | 0/0 | 0/0 | -/- | - |
| 18-cx | sonnet first | - | - (-) | - | - (-) | - | - | - | - | - | - | - | - | - | 0/0 | 0/0 | -/- | - |
| 23-b | sonnet first | - | - (-) | - | - (-) | - | - | - | - | - | - | - | - | - | 0/0 | 0/0 | -/- | - |
| 16-bx | haiku first | - | - (-) | - | - (-) | - | - | - | - | - | - | - | - | - | 0/0 | 0/0 | -/- | - |

## Totals
| arm | runs | operator matches checker | script wall | agent tokens | API-price USD | escalation lines | refused marks | status-count MISMATCH |
|---|---|---|---|---|---|---|---|---|
| haiku | 5 | 5/5 | 40m56s | 1,295,014 | $0.050 | 1 | 0 | 0 |
| sonnet | 4 | 4/4 | 36m10s | 1,292,433 | $0.650 | 0 | 0 | 0 |

Checker verdicts identical across arms on 1 of 4 rows with both runs (a row that is LLM-sampling noisy can differ for either arm; the checker RESULT line is the ground truth, the operator verdict only has to equal it).
Status-count notes: none

Costs are API-price-equivalent (prices.json), whole transcript per agent (one agent per run). op wall = START..mark; script wall = the row script only.

## INTERIM STATUS (wound down early on the coordinator's order, 2026-10-16 ~21:50)
Plain terms: 12 of 20 planned runs were attempted, 9 produced a result, 3 were voided. 4 rows (01-cx, 18-cx, 23-b, 16-bx) and seq 13-20 were NOT run. Pilot is incomplete; numbers below are small-sample.
- Void: seq 1 (sonnet 17-bx), seq 3 (haiku 05-cx), seq 4 (sonnet 05-cx): scene reset failed ("no character named Cind"); root cause fixed afterwards (lane-setup waits for --with characters, commit 8d57ec16). Seq 4 was voided only because its agent already had a terminal FAILED status from before the fix, so ab2-next refused to respawn it. Rows 05-cx has no result for either arm; 17-bx only Haiku (PASS).
- Rows with both arms: 02-ax (H PASS, S FAIL), 02-cx (both PASS), 01-bx (H PASS, S FAIL), 27-a (H SETUP-FAIL -> escalated, S PASS). Checker verdicts differ on 3 of 4: the rows are LLM-sampling noisy (and 27-a's SETUP-FAIL is the checker saying its chase control could not discriminate), so this is data about the rows, not about the operators.
- Operator quality: in all 9 results the operator word equalled the checker's RESULT word (Haiku 5/5, Sonnet 4/4); no refused marks, no status-count mismatch, no drift, no false claims found. Haiku correctly escalated the one SETUP-FAIL (inbox pilot-escalate message). Both arms made the same small slip: first agent-status call with backslash paths failed in Git Bash and was rerun once; a few arms recorded a truncated RESULT line as the mark note (output tail cut it).
- Time: script wall is the row itself and about equal per row for both arms (02-ax 3m59s/3m59s, 02-cx 8m15s/9m01s, 01-bx 20m44s/19m55s, 27-a 3m43s/3m15s); the operator model adds ~5-10 s.
- Tokens/USD: "tokens" counts whole-transcript tokens including cache reads (hence ~120k-350k per run); at API prices Haiku was about $0.050 for 5 runs and Sonnet about $0.650 for 4 (roughly 10x cheaper per run). The 17-bx and 05-cx rows show token/USD figures from voided agents too (Sonnet 17-bx 117k and both 05-cx), which are wasted spend, not results.
- Reading (mine, not a decision): on this small sample Haiku High did the mechanical lane-operator job as accurately as Sonnet High at about a tenth of the cost; the sample is too small (no run exercised an odd mid-run failure beyond one SETUP-FAIL) to call it proven.
- Cleanup done by the executor on the coordinator's order: see the executor's status file / final report.
