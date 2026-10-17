# Suite findings: A (Haiku max investigate + Sonnet verify) vs B (Sonnet medium solo)

Order run: B1, B2, B3, A1, A2, A3 (B1 ran twice: attempt 1 asked for a report file, the harness blocks subagent file writes, so it was discarded and all six used the return-as-text wrapper). Same prompt text, same wrapper, same state checks (STATE OK before and after every round).

| Prompt | B cost | B time | A cost (investigate + verify) | A time | Grade B | Grade A |
|---|---|---|---|---|---|---|
| 1 slow first reply | $0.486 | 145 s | $1.819 ($1.595 + $0.224) | 1479 s | 18/25 | 23/25 |
| 2 Emperor Tengu / "job" | $0.373 | 132 s | $0.722 ($0.540 + $0.182) | 951 s | 17/25 | 25/25 |
| 3 Mouse location loop | $0.435 | 113 s | $0.789 ($0.591 + $0.198) | 991 s | 16/25 | 24/25 |
| Total | $1.294 | 390 s | $3.330 | 3421 s | 51/75 | 72/75 |

Costs are token cost at the official prices from the subagent transcripts (coordinator overhead excluded). Graders (3 x Sonnet high) cost $0.582 extra. Quota (whole percent, coarse): B rounds 4% to 5% (5 h window), A rounds 5% to 6%; weekly stayed 2%.

Verifier: PASS on all three first tries; it changed no output and added $0.60 (18% of A's cost), 15 to 41 s per round. Investigator alone is $2.73, 2.1x B.

Blind grading (X/Y random, key stored outside the folder): A won all three, margin "large" each time. The graders checked claims against live code, logs and database.
- P1: B led with a 12 s speech-to-text warm-up and gave the 88 s pause hold only "find who paused it"; A found the pause hold, ranked the trigger (Space, focus, auto-pause mod) as unproven, and gave a concrete fix for the hold.
- P2: B said the "Tango" line came from the model and was typed (it was speech-to-text) and proposed a function that does not exist; A gave schema, migration, stored-row and wording fixes.
- P3: both found the missing LocalTravel producer in the installed DLL; B told you to re-sync the build source (would not add the file), A found the real blocker (the SOURCES list in build_portable.bat).

Caveats: n=3 prompts, one run each; B always ran before A; one grader model; A's reports are about twice as long (graders were told not to reward length); no in-game test of any fix; A3 once listed pending-fixes\ (disclosed); flagged mutating commands were reads or temp files in /tmp.
