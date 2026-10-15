# NPC immersion 26-feature test file

Companion to `NPC_IMMERSION_26_HANDOFF.md`. STOBE only (no FP/animation). Tests run on the isolated 4080 instance 3 (`live-stobe-queue/4080-imm26-runbook.md`) on copied `kah-*` saves; never on Shay's saves; the 5090 is not used.

## How a row is marked
- Status: `UNRUN` -> `PASS` | `FAIL` | `SETUP-FAIL` | `GATED` (needs a build/fixture not yet installed). Only the 4080 operator marks PASS, and only with game-state evidence (stobe.log line, DB row, status file, NPC reply text plus the state change it implies). An NPC saying the right words without the state change is not a PASS for rows that name a state change.
- Each row: ID | feature | setup/fixture | exact player utterance or action | expected observable evidence | negative control | status | evidence path | date.
- A FAIL becomes a bug ticket (`bugs` section below) handed to a fix agent; the row is retested on the fixed build and the old FAIL text kept in the evidence column.
- Output line per row: `RESULT <ID> PASS|FAIL <evidence>` (project convention).
- Two groups: **F** rows test a feature as listed (IMM-nn-x); **C** rows test a change made by this program (IMM-Cnn), added when the change is made.

## Feature index (rows are filled in from the audits; none run yet)
| # | Feature | Audit state | Rows | Status |
|---|---|---|---|---|
| 1 | Relationship shapes the conversation from the start | pending audit A1 | | UNRUN |
| 2 | Personal boundaries and values | pending A1 | | UNRUN |
| 3 | Remember witnessed actions | pending A2 | | UNRUN |
| 4 | Relationships between NPCs | pending A2 | | UNRUN |
| 5 | Public and private reactions | pending A1 | | UNRUN |
| 6 | Remember player preferences | pending A3 | | UNRUN |
| 7 | Introductions and referrals | pending A3 | | UNRUN |
| 8 | Follow-up conversations | pending A3 | | UNRUN |
| 9 | Companion communication preferences | pending A3 | | UNRUN |
| 10 | Gradual social repair | pending A2 | | UNRUN |
| 11 | Limits on attention | pending A3 | | UNRUN |
| 12 | Different kinds of trust | pending A1 | | UNRUN |
| 13 | Relationships change through experience | pending A2 | | UNRUN |
| 14 | Negotiated alternatives | pending A4 | | UNRUN |
| 15 | Personal, imperfect knowledge | pending A2 | | UNRUN |
| 16 | Consistent personalities | pending A1 | | UNRUN |
| 17 | Uncertainty and corrections | pending A1 | | UNRUN |
| 18 | Awareness of actual game behavior | pending A4 | | UNRUN |
| 19 | Shared commitments and plans | pending A4 | | UNRUN |
| 20 | Natural plan changes | pending A4 | | UNRUN |
| 21 | NPCs have their own priorities | pending A4 | | UNRUN |
| 22 | Reactions during shared activities | pending A5 | | UNRUN |
| 23 | Clear activity endings | pending A4 | | UNRUN |
| 24 | NPC-chosen destinations and broad regions | pending A5 | | UNRUN |
| 25 | Purpose-based goals | pending A5 | | UNRUN |
| 26 | Activities as complete goal sequences | pending A5 | | UNRUN |

## Test rows
(filled after the audits: one section per feature, then the C rows for each change)

## Bugs found by these tests
(none yet)
