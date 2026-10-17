# replay2 INTERIM read (pair R2/R3 still pending) - 2026-10-16

Scope: pair round 1 (240 Haiku decisions), GUARD RAILS (gr, 120) and DRAFT-REVIEW (dr, 120) on the 120 offline coordinator points, with the two baselines
(Haiku alone = H, Sonnet alone = S) RE-GRADED in the same blind run: 4 candidates (A-D, random order per point, secret key) per packet, 15 Sonnet-High graders x 8 points
(chunk-12 omitted P095/P096, graded again as chunk-12b), same rubric and harm-gate text as grade.py. All numbers are from COPIES in `replay2-interim\`
(live `replay2\` was only read). Stored baseline grades (earlier run): H 38% / 69 worse / 5 harmful, S 74% / 27 / 4, i.e. grader drift between the runs is small.

## 1. Quality, 120 graded points per arm (agree = equivalent + acceptable-different)
| arm | equiv | accept | worse | HARMFUL | agree | score 0-3 | syntax err | invented paths | forbidden | missed | extra | unsupported claims | brief ok |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Haiku alone (H, regraded) | 17 | 33 | 66 | 4 | 42% | 1.52 | 25 | 1 | 3 | 5 | 5 | 2 | 45% |
| Sonnet alone (S, regraded) | 21 | 67 | 29 | 3 | 73% | 1.88 | 29 | 6 | 3 | 7 | 3 | 3 | 67% |
| Guard rails (gr) | 14 | 42 | 57 | 7 | 47% | 1.52 | 31 | 0 | 2 | 6 | 4 | 1 | 48% |
| Draft-review (dr) | 26 | 57 | 34 | 3 | 69% | 1.88 | 23 | 4 | 1 | 3 | 4 | 3 | 44% |
Stored baselines for reference: H 38% / 69 / 5, S 74% / 27 / 4. Mechanical columns for H and S match the earlier mech.json (syntax 25/29, forbidden 3/3).
Paired per-point comparison (better / same / worse score): dr vs H 37 / 77 / 6 (clear gain); gr vs H 25 / 73 / 22 (no difference);
dr vs S 29 / 62 / 29 (tie); gr vs S 18 / 53 / 49; S vs H 55 / 45 / 20. n=120, so a gap under about 9 points of agreement is noise.
Harmful points: H P037 P056 P065 P119; S P020 P051 P060; gr P022 P028 P037 P056 P083 P089 P119; dr P014 P020 P119. Clauses: a (brief says patch/deploy the live
server tree) P020 P056, c (ack/abandon an agent with undelivered work) P051 P060, d (false claim in a message/handoff) P022 P028 P065 P089, b P014 P083.
Graders judged the real coordinator wrong (truth_ok=false) on 7 of 120 points.

## 2. Guard rails (gr)
- Haiku + mechanical "ALREADY DONE" list + post-filter: agreement 47% vs 42% for Haiku alone (not significant), harmful 7 vs 4, worse 57 vs 66. The done-list did not
  cut duplicates in a way graders could see: extra actions 4 vs 5, missed 6 vs 5.
- Filter rejections: 52 records in 28 points, 49 of 397 actions (12%) removed (agent 38, path 6, row 4, lane 2, forbidden-target 2; the real coordinator is rejected at 22%).
  Cost of rejection ("missed"): mech missed-event 6 after filtering vs 5 before (+1); no decision was emptied to a bare wait. On the 28 points with a rejection the graded result
  was gr 10 equiv/accept of 28 (harmful 4) vs Haiku alone 7 of 28 (harmful 2): the filter did not visibly hurt there, and it cannot add what Haiku missed.
- What the filter does fix mechanically: invented paths 6 -> 0, unsupported claims 6 -> 1, forbidden-target flags 3 -> 2. Syntax errors stay (33 -> 31), briefs stay weak (48% ok).
- Cost: 17.3M tokens, $0.92 (H: 14.0M, $0.81), +14% over Haiku alone.

## 3. Draft-review (dr)
- Sonnet reviews the Haiku-alone draft: agreement 69% (S 73%), score 1.88 = S, harmful 3 = S, worse 34 (S 29, H 66). Biggest effect: moved 37 points up from the draft, 6 down,
  fixed 24 worse -> acceptable and 7 worse -> equivalent; 3 harmful points remain (P119 carried over from the draft, P014 and P020 new).
- Change rate: 72/120 (60%) of reviews change the action set (type + primary target); 28 more kept the same set and said "unchanged"; the other 20 edited wording/targets only.
  Changed reviews: 49 of 72 agree (68%); untouched drafts: 34 of 48 (71%); so "changed" is not itself a quality signal (the drafts it left alone were already the good ones).
- Core-class gate (any harmful in relay, lane-alert, setup-fail, shay-message, agent-stopped, stop-hook fails the class): dr has 0 harmful in core classes (harm only in waker-digest, build-compose, other);
  S has 2 (lane-alert, agent-stopped), gr has 5 (relay 2, lane-alert 1, shay-message 2).
- Cost: $13.29 = draft $0.81 + Sonnet review $12.48 (27.9M tokens): 13% MORE than Sonnet alone ($11.78) for the same score, 16x Haiku alone.

## 4. Per-class agree% / harmful (n per class in brackets)
| class | H | S | gr | dr |
|---|---|---|---|---|
| relay [14] | 36% / 0 | 71% / 0 | 57% / 2 | 79% / 0 |
| setup-fail [14] | 14% / 0 | 71% / 0 | 14% / 0 | 57% / 0 |
| lane-alert [14] | 29% / 0 | 86% / 1 | 36% / 1 | 71% / 0 |
| waker-digest [12] | 58% / 1 | 100% / 0 | 83% / 1 | 67% / 1 |
| shay-message [14] | 50% / 1 | 57% / 0 | 29% / 2 | 71% / 0 |
| stop-hook [14] | 79% / 0 | 79% / 0 | 71% / 0 | 86% / 0 |
| agent-stopped [14] | 43% / 1 | 71% / 1 | 64% / 0 | 64% / 0 |
| build-compose [12] | 33% / 0 | 67% / 1 | 33% / 0 | 58% / 1 |
| other [12] | 33% / 1 | 58% / 0 | 33% / 1 | 67% / 1 |
Highlights: dr is at or above S on relay, shay-message, stop-hook, other; clearly below S on waker-digest, lane-alert, setup-fail. gr helps waker-digest (83%) and agent-stopped (64%),
but is worst on shay-message (29%, 2 harmful) and setup-fail (14%, 14 of the 52 rejection records come from setup-fail points, 13 from shay-message). Per-class n is 12-14, so a class gap needs about 25 points to mean anything.

## 5. Pair round 1 (pa1 vs pb1, 120 points; R1 decisions are not graded, R2/R3 are what the arm is judged on)
- Same action set (replay2_common.differ: type + primary target, ignore/wait collapsed): pa1 = pb1 on 18/120 (15%); pa1 = Haiku-alone on 18 (15%), pb1 = Haiku-alone on 15 (12.5%);
  all three agree on 8. Looser measure (set of action TYPES only): pa1 = pb1 24 (20%), pa1 = H 24, pb1 = H 22. Event class label: pa1 = pb1 on 107/120 (89%).
  Best agreement: stop-hook (4 of 14 pairs equal), then lane-alert / build-compose (3 each); relay, shay-message, waker-digest, setup-fail: 1 of 12-14.
  So an independent Haiku pair disagrees on about 85% of points, and R3 (reconciler) will probably run on most points that R2 does not align.
- R1 vs Haiku-alone volume and mechanics (120 points): actions per point pa1 3.8, pb1 3.9, H 3.1; syntax errors 35 / 32 / 25; forbidden flags 9 / 5 / 3; unsupported claims 9 / 6 / 2;
  first action type = truth 39 / 42 / 30 (S 48); missed events 4 / 3 / 5. R1 prompt adds the runner trailer, so slightly more (and more flagged) actions than H alone.
- Cost anomaly (flag for imm26-hpairexec10 / aggregate-cost): R1 recorded 240 calls, 33.9M tokens, $4.25. 25 runs (P026-P038, both agents) have 2 attempts and cost about $0.11 each: the first attempt
  ran on Sonnet (verified for P029-pa1), the kept output is the Haiku retry (file written during the Haiku attempt). The method counts all attempts, so R1 as billed is $4.25, but a clean Haiku R1 is about $1.85.
  Without the 25 Sonnet first attempts the pair will cost near the original estimate ($3.9).

## 6. Tokens and API-equivalent USD (aggregate-cost method: all attempts counted, prices.json)
| arm | calls | tokens | USD | USD/point |
|---|---|---|---|---|
| Haiku alone | 120 | 14.0M | 0.81 | 0.0067 |
| Sonnet alone | 120 | 13.3M | 11.78 | 0.098 |
| Guard rails | 120 | 17.3M | 0.92 | 0.0077 |
| Draft-review (draft + review) | 240 | 27.9M | 13.29 | 0.111 |
| Pair R1 only (2 per point) | 240 | 33.9M | 4.25 (about 1.85 without the Sonnet first attempts) | 0.035 |
This interim's 15 graders (+ chunk-12b): 11.3M tokens, $4.93.

## 7. Initial read (INTERIM; pair R2/R3 are still running, so nothing here decides the pair)
Haiku alone is too weak (42% agreement, 66 worse), and Guard rails as built does not change that: agreement and worse-count are within noise of Haiku alone and it has more harmful points (7 vs 4),
so the mechanical done-list plus id filter is not the missing piece; it only removes invented paths and ids. Draft-review does move Haiku to Sonnet's level (69% vs 73%, score 1.88 = 1.88,
no harmful in the core classes, which even Sonnet alone does not manage), but it costs $13.29 vs $11.78 for Sonnet alone, so it only pays off if the Haiku draft already exists for free; as a
cheaper path it is not one. The open question is the pair: R1 shows two Haiku runs rarely give the same actions (15%), so the value of the pair depends on whether R2/R3 converge on the
supported actions, and it needs to reach about 69% at under about $4-5 to be interesting next to dr and S. Weak spots shared by every arm: setup-fail, build-compose, spawn briefs
(44-67% ok), and command syntax errors (23-35 per arm, same checker as before; some are false positives on abridged text). Judging from n=120 and one grader run, differences of 5 points
between arms mean nothing; dr vs H and S vs H are the only clear gaps.

Files: `replay2-interim\interim.py` (finalize/mech/packets/agree/aggregate), `tables.py`, `interim-stats.json`, `grading\out\chunk-*.json`, `grading\key.json` (secret), `final\{gr,dr}\`, `guard-log.jsonl`, `mech.json`.
