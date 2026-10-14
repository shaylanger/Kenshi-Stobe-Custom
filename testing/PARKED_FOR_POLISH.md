# Animation work: CLOSED for now (Shay, 2026-10-14)

All KenshiFP / animation-lab work is **done for now**. No animation task, ticket, bug, queue row, agent or
batch is open. Work resumes only after Shay has done his own in-game testing and sends findings; until then
nobody starts, queues or fixes anything animation-related.

## What ships (MVP, 2026-10-11 20:31)
Keyframed viewmodel strokes for all weapon classes, live in `components/KenshiFP/tables/fp_tables.txt`
(= `<Kenshi>\mods\KenshiFP\fp_tables.txt`). Format: `components/KenshiFP/docs/KEYFRAME_FORMAT.md`,
`LIVE_TABLES.md`. Rules: `components/KenshiFP/animlab/SHAY_RULES.md`. Lab: `Kenshi-Automation-Harness/docs/animlab/`.

## Cleared on 2026-10-14
Earlier open lists (GPU lab, table/optimizer strokes, lab polish, speed tooling, regression filler, look
items for Cleaver/Naginata/heavy 2H/Axe, PT30, zoom-reset, B03-B06 stubs) were dropped, not forgotten as
work: they are not scheduled. Shay's in-game findings will define the next list. Their scratch dirs, tables,
GPU work copies, filler lists and 4080 lab copies were deleted. Kept: `C:\KenshiTestRuns\corpus\` (protected
lab evidence), `for-shay\` and `spec-videos\` (videos for Shay), the staged/installed KenshiFP DLL, git history.

## To resume
Read `SHAY_RULES.md` + animlab `STATUS.md`, then start from Shay's in-game notes.
