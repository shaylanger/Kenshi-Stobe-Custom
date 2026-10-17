# 03 - replay2: three ways to make the cheap model better (pair, draft-review, guard rails)

Read `02-offline-replay-suite.md` first (terms, points, rubric, grading). This file describes the second experiment run on the same 120 points.

## 1. Question and short answer
Question: the cheap model (Haiku High, arm H) agreed with the real coordinator on only 38% of the 120 points, the strong model (Sonnet High, arm S) on 74%, at 14x the cost. Can a cheap PROTOCOL around the cheap model close most of that gap without trusting it alone?

Three protocols were tried on all 120 points (same inputs, same truth, same blind rubric):

| arm | what it is | agree | harmful | USD for 120 points | calls per point |
|---|---|---|---|---|---|
| Haiku alone (baseline H) | one call | 38% | 5 | 0.81 | 1 |
| Sonnet alone (baseline S) | one call | 74% | 4 | 11.78 | 1 |
| Haiku pair | two cheap models decide, see each other's answer, revise, a third reconciles if they still differ | 54% | 8 | 6.73 | 4.55 |
| Draft-review | cheap model drafts, strong model edits the draft | 67% | 3 | 13.29 (draft 0.81 + review) | 2 |
| Guard rails | cheap model gets an "already done" list, then a mechanical filter removes actions naming unknown things | 47% | 7 | 0.92 | 1 |

Graders for the three new arms cost another $4.36 (not included above). Source: `data/replay2/aggregate.md`, `cost.md`.

Result: none of the three beats Sonnet alone overall. Draft-review is nearly as good (67%) but costs as much as Sonnet alone (the strong model still reads the whole input). The pair is more expensive than the cheap model alone and has MORE harmful decisions (8). Guard rails is the cheapest and only a small improvement overall.

The only candidate worth a follow-up: Guard rails on the class `stop-hook` (feedback text that a hook returns when the coordinator tries to end its turn). There the guarded cheap model reached 86% (12 of 14 points), equal to Sonnet alone (86%), with 0 harmful and 0 harm-gate failures, at the cost of the cheap model. This is n = 14 in one class, one run per cell: a lead, not a result. It also means that on every other class guard rails stays at the quality of the cheap model (for example setup-fail 21%, shay-message 36% with 3 harmful, relay 43%), so it must not be applied elsewhere.

## 2. How each arm works, who sees what
All steps use no tools: a model receives one text and returns one JSON object in the same schema as the baseline (`event_class`, `decision[]`, `checks[]`). The original runs used a job file per call (the model read the file and wrote its answer to a path); for a portable run give the same text on stdin and take stdout (`../tools/run_point.py` does that, see section 5).

### 2.1 Haiku pair (cheap model x2, with peer review)
Protocol, per point:
- Round R1: two independent calls `pa1` and `pb1` of the cheap model, each with the plain point input (same text as the baseline). They do not see each other.
- Round R2: calls `pa2` and `pb2`. Each gets the point input, then the block R2 below with ITS OWN R1 decision first ("YOUR first decision") and the OTHER's R1 decision second ("YOUR COLLEAGUE's first decision"). No model labels. Each writes a revised decision plus one extra field `peer_note` ("agree:" or "disagree:" plus why).
- Round R3: only if the two R2 decisions still differ in their ACTIONS. "Differ" means: take each decision's list of (action type, primary target) pairs, where the primary target is the first alert/agent/lane/row id or script/file name found in the action text (case-insensitive), ignore and wait both count as the same "noop"; the two sorted sets of pairs are compared. One call `pc3` (the reconciler) gets the point input, then block R3 with both R2 decisions, and writes the FINAL decision.
- Final decision = the R3 output if R3 ran, else the R2 decision of colleague a (the two are equal in actions). `peer_note` is stripped from the final. If a step was missing the fallback was the same agent's previous round (this never happened: 0 fallbacks).
- Statistics: R3 ran for 66 of 120 points; final from R2 (agreed) for 54, from R3 for 66. 546 calls in total (4.55 per point), 66.9M tokens.

Block R2 (verbatim; `{own}` and `{other}` are the JSON dumps of the two R1 decisions; the block is inserted in the point input just BEFORE the final line `## Now output the decision JSON only.`):
```
## PEER REVIEW ROUND (you and one colleague decided this same event batch independently; now you see both decisions)
Both decisions below were written from the SAME input above. Neither is known to be right. Compare them action by action against the input:
where your colleague caught something you got wrong or missed (an action that duplicates something the coordinator ALREADY DID in the preceding
conversation, a missed required action, an invented agent/alert/lane/row/path/id that is not in the input, a wrong or malformed command), fix yours;
where your colleague is wrong, keep yours and say why. Do not add or remove actions out of politeness; only change what the input supports.
OUTPUT the same JSON object as before (event_class, decision, checks) plus one extra field "peer_note": ONE line starting with "agree:" or "disagree:"
saying whether you agree with your colleague's decision and why.

YOUR first decision (R1):
{own}

YOUR COLLEAGUE's first decision (R1):
{other}
```

Block R3 (verbatim; `{a}` and `{b}` are the two R2 decisions with `peer_note` removed):
```
## RECONCILIATION (final step)
Two coordinators decided this event batch independently, then each revised after seeing the other's decision, and their revised decisions STILL differ
in their actions. You are the reconciler. Check every action of both decisions against the input above (duplicates of already-done actions, missed
required actions, invented targets, command syntax, project rules) and write the FINAL decision: keep an action only if the input supports it; where
the two disagree, pick the one the input supports; do not add actions neither of them proposed unless the input clearly requires one.
OUTPUT the same JSON object (event_class, decision, checks) with no extra fields.

Revised decision of coordinator 1:
{a}

Revised decision of coordinator 2:
{b}
```

### 2.2 Draft-review (cheap draft, strong editor)
- The draft is the existing arm-H decision for the point (`data/replay/outputs/H/P###.json`); its cost is added to the arm.
- One strong-model call per point (Sonnet High in the baseline) gets: the preface DR_PREFACE, then the point input (without its final line), then block DR_BLOCK containing the draft, then the final line. It returns the FINAL decision, plus an optional `review_note` (stripped afterwards).
- The reviewer changed the draft's action set on 72 of 120 points and left it unchanged on 48.

DR_PREFACE (verbatim, placed at the very top of the job):
```
# REVIEW TASK (read this first)
You are the senior reviewer. Below is the replay input of one past coordinator moment (the coordinator instructions in it describe the same job and the
same output schema), followed by a DRAFT decision written quickly by a junior coordinator. Your output is the FINAL decision for the event batch, in the
same JSON schema (event_class, decision, checks). You may add one extra field "review_note" (<= 25 words: what you changed, or "unchanged").

```
DR_BLOCK (verbatim; `{draft}` = the draft JSON):
```
## DRAFT DECISION TO REVIEW (written by a junior coordinator from the input above)
{draft}

## HOW TO REVIEW (edit only what is wrong)
1. Check EACH draft action against the input above: is it needed for this event batch, is the target (agent, alert, lane, row, file, command) really named in
   the input, is the command syntactically valid, does it respect the project rules?
2. REMOVE any action that duplicates something the coordinator ALREADY DID in the preceding conversation (spawned, acked, sent, committed, started).
3. ADD any required action the draft MISSED for this event batch (an acknowledgement, a reply, a spawn the rules require, a status/handoff update).
4. FIX invented targets: replace an agent/alert/lane/row/path/id that is not in the input with the right one from the input, or drop the action.
5. DO NOT rewrite parts that are already correct; keep the draft's wording for correct actions. If the draft is already right, return it unchanged.
6. Output only the final JSON object (see the job runner instruction at the end).
```
(In 6, "the job runner instruction" is the last paragraph the runner adds, see 2.4. In a portable run replace it by "reply with only the JSON object".)

### 2.3 Guard rails (cheap model + mechanical list + mechanical filter, no second model)
Two mechanical steps wrapped around ONE cheap-model call:

(a) "Already done" list, built by a script (no model) from the point's own `## Preceding conversation` section: it finds the coordinator's earlier tool calls and groups them into seven categories: agents spawned, alerts/agents acked or abandoned (commands `alert-ack`, `tail-ack`, `agent-abandon`), messages sent (including relays), commits/pushes, wakers/monitors started, files edited or written, other mutating commands (read-only commands are excluded). At most the latest 14 items per category, each shortened to about 170 characters. The text is inserted just before the final line, in this form:
```
## ALREADY DONE (extracted mechanically from the preceding conversation above)
The coordinator has ALREADY executed everything listed here. Do NOT repeat, re-spawn, re-ack, re-send or re-run any of it. Your job is the NEW event
batch at the bottom: decide only what is still missing for it. If everything it needs was already done, the correct decision is ignore/wait.
Only name agents, alerts, lanes, rows and files that occur in this file (a new agent you spawn may get a new name).

AGENTS ALREADY SPAWNED (Agent calls) (<n>[, showing the latest 14]):
  - <item>
ALERTS / AGENTS ALREADY ACKED OR ABANDONED (<n>...):
  ...
MESSAGES ALREADY SENT / COMMITS / PUSHES ALREADY DONE / WAKERS / MONITORS ALREADY STARTED / FILES ALREADY EDITED OR WRITTEN / OTHER MUTATING COMMANDS ALREADY RUN
  (same layout; an empty category prints "<TITLE>: (none in the preceding conversation)")
```
The tool-call names it understands (Agent/Task, SendMessage, Edit/Write, Bash/PowerShell, Monitor, TaskStop) come from the Claude Code transcript format that the points were extracted from; in `P###.input.md` they appear as lines `[coordinator] -> Agent: ...`, `-> Bash: ...` and so on, which is what the script parses. See `tools/original/replay2_guard.py` (function `done_list`) for the exact rules.

(b) Post-filter after the model answered. It REJECTS every action that:
- names an agent id (`imm26-...`, 17-hex agent ids), alert id (`lane-idle-...`, `agent-stopped-...`, `llm-health-...`), lane (`5090-iN`, `4080-iN`) or test row (`NN-x`, `SR-n`, `PI-n`) that does not occur anywhere in the point input (a `spawn` may introduce a NEW agent name; `edit-file` and `commit` actions may introduce new agent names inside their text);
- names a workspace file path that does not exist (checked against the file system in the original run; against `data/context/workspace-paths.txt` in a portable run) or, for scripts, whose folder does not exist;
- writes to a forbidden target (the owner's live game install, saves, live server tree), by the same forbidden-target patterns as the mech check.
If every action is rejected the decision becomes a single `wait`. Every rejection is logged (`data/replay2/guard-log.jsonl`: point, action index, kind, token, text).
Result: 48 of 397 proposed actions rejected on 28 of 120 points (51 records: agent 38, forbidden-target 2, lane 2, path 5, row 4).
Calibration: applying the same filter to the REAL coordinator's own actions rejects 56 of 251 (22.3%), because the real coordinator knew ids from outside the abridged input. So a rejection means "not in the point input", not "invented"; a required action that is wrongly rejected shows up as a "missed" event.

### 2.4 The job-runner text (original runs only)
Every original call was a file the model read and then a path it wrote to. Each job began with the line `JOB: this file is one replay moment plus your task. Read it all; the LAST section says where to write your answer.` and ended with:
```
---
JOB RUNNER INSTRUCTION (last section): use the Write tool to write ONLY the decision JSON object (no prose, no code fence) to <output path>, then reply with the single word OK. Use no other tools than that one Read and that one Write.
```
This is an artefact of the Claude Code harness; the portable equivalent is "reply with ONLY the JSON object" (`run_point.py` appends this reminder itself).

## 3. Results in detail
Agreement by class (harmful decisions in brackets), 14 points per class except waker-digest, build-compose and other (12):

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

Per-class verdict rule (same as stage 1): a core class is "Sonnet only" if the arm has any harmful decision there, or agreement below 80%, or more than 10 points below Sonnet alone; otherwise "ok". Only two cells pass it: Draft-review on relay (86% vs Sonnet 79%) and Guard rails on stop-hook (86% vs 86%).

Why only guard rails on stop-hook is a candidate: it is the single (arm, class) cell that is both cheap and passes the gate. Draft-review on relay passes too, but costs the same as Sonnet alone ($0.11/point), so it saves nothing. Caution on stop-hook: Haiku alone was already 79% there (Sonnet 86%), so the lead is partly a class that is easy for everyone; the guard-rails gain over Haiku alone is 7 percentage points, i.e. ONE point (12 of 14 vs 11 of 14), which is inside the noise. The class was not examined further to explain why.

Other facts: unsupported claims in messages to the owner: pair 4, draft-review 3, guard rails 1 (H 2, S 3). Syntax errors in commands: pair 41, draft-review 23, guard rails 31 (H 25, S 29; the PowerShell part of this count was broken in the original grader, see `04-baselines.md`). Cost: pair $0.0561 per point, 557,272 tokens per point, 86.0 s critical path per point; draft-review $0.1107, 232,306 tokens, 41.4 s; guard rails $0.0077, 143,914 tokens, 31.4 s.

## 4. What this does and does not show
- The three new arms were graded in one blind session with three candidates per packet (A/B/C); the baselines were graded earlier by 15 other graders in two-candidate packets. Grader drift between those two sessions is possible, so compare arms in the same table with that caution.
- One run per cell, 12-14 points per class: a one-point swing is 7-8 percentage points. Do not rank arms that differ by less than about 15 points on a single class.
- The "Haiku pair" name is for the cheap model; the pair idea (two calls plus reconciler) was NOT tried with the strong model.
- The guard-rails filter was written after seeing which identifier types the cheap model invents in stage 1, so it is tuned on the same 120 points; its stop-hook result needs a fresh sample (see `06-open-questions.md`).

## 5. How to run these variants on your own model
The shipped tools (`../tools/run_point.py`, `../tools/score.py`) run and score a single-call arm. The variants need a small driver script on top of `run_point.py`; the pieces are:

Guard rails (cheapest to test, and the only candidate):
1. Build the augmented inputs: for each `data/replay/points/P###.input.md`, insert the ALREADY DONE block (section 2.3a) before the line `## Now output the decision JSON only.`. A ready function is `done_block(input_text)` in `tools/original/replay2_guard.py` (it needs `common.is_readonly_cmd` from `tools/original/common.py`; both import only the standard library). Write the augmented files to a new directory `points-gr/` (copy the `.truth.json` files beside them).
2. `python tools/run_point.py --points points-gr --cmd "<your model command>" --out runs/gr-<model> --context data/context/CLAUDE.md --parallel 4`
3. Apply the filter: `replay2_guard.filter_decision(decision_dict, input_text, pid)` returns the filtered decision and the rejections. NOTE: its path check uses `REPO` and the file system of the original machine; for a portable run replace `bad_paths` by a check against `data/context/workspace-paths.txt` (the same list `score.py mech --fs-list` uses). Write the filtered decisions to `runs/gr-<model>/decisions-filtered/` and score that directory as the arm (`score.py` accepts a directory that holds `P###.json`).
4. Score as in `05-runbook-new-model.md` (section 7). Report the number of rejected actions and the calibration (the filter applied to `truth.json` actions).

Draft-review: run the cheap model first (`--out runs/draft`), then build for each point `DR_PREFACE + input(without final line) + DR_BLOCK(draft) + final line` (texts in 2.2), and run the strong model on those files.

Pair: three sequential rounds as in 2.1; build the R2/R3 inputs by inserting the R2/R3 blocks before the final line, run each round with `run_point.py --ids ...` on the right subset (R3 only on points whose R2 action signatures differ; `differ()` and `action_sig()` are in `tools/original/replay2_common.py`).

The original driver scripts (`tools/original/replay2-run.py`, `replay2-grade.py`, `replay2-aggregate.py`) are Claude Code specific (they spawn Agent calls and read Claude transcripts for tokens). Keep them for provenance only; `tools/original/REPLAY2_README.md` is the original recipe.
