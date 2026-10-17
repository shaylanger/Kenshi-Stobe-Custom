# Compaction vs overlap handoff: measured cost (Shay 2026-10-16)

Tool: `tools/automation/compact-audit.py` (reads the Claude Code transcripts; prices from tools/automation/prices.json). Raw rows: `C:\KenshiTestRuns\compact-audit\compact-audit.jsonl`.
Caveat: the summarizer call is not in the transcript, so its cost is an ESTIMATE (prompt = preTokens at cache-read if warm, output = summary chars / 3.6 per token); everything marked MEASURED comes from usage fields.

## Compact #1 (coordinator #24, auto at 299k, 2026-10-16 ~20:34 local)
- 299,005 -> 13,860 tokens (+ retained segment); summarizer ran 67 s; cache was warm.
- One-off $0.23: summarizer ESTIMATE $0.076 (in $0.030, out ~4.6k tokens $0.046) + first turn after MEASURED $0.156 (37k tokens cache-written, 20k read).
- Mean turn cost before $0.0438 (15 turns, context ~290k) -> after $0.0288 (15 turns, context 60-75k); break-even after ~15.5 turns.

## Overlap handoff #23 -> #24 (new session 7b068528 started 2026-10-17 01:44Z, old/tail 5161648d)
- New session startup, first 25 assistant turns (session-start, HANDOFF, status, first fixes): $0.45 MEASURED (first turn $0.075; context 75k after 25 turns). Includes real work, so an upper bound for "startup".
- Old session after the new one started: 69 turns, $1.40 MEASURED (relays + one compaction of its own 294k -> 93k at +10 min; mean context 92k). Last turn 02:22Z; closed 20:47 local.
- Total after the handoff point: $1.84. Not counted: the ritual before it (steps 1-6, PI review) in the old session: 112 turns in the 25 min before the handoff cost $3.63 at 150k-293k context (includes normal work).

## Reading
Compaction one-off ~$0.23 vs handoff ~$1.84 for the following hour, ~8x, plus the tail's relay turns and the risk of lost relays. Per-turn cost halves after either. My earlier estimate ("a handoff costs about the same") was wrong because the tail kept taking turns at high context and compacted itself anyway.

## Compact #2 (auto, 2026-10-17 02:34 UTC; fired at 299k, NOT the 150k threshold: the setting had not applied to the running session yet)
- 299,005 -> 13,860 tokens, summarizer 67 s. Cache was warm.
- One-off cost $0.23 = summarizer ESTIMATE $0.076 (input $0.030 at cache-read + ~4.6k output tokens $0.046) + first turn after MEASURED $0.156.
- Mean turn cost MEASURED: before $0.0438 (n=15) -> after $0.0288 (n=15); break-even ~15.5 turns.
- Vs the old overlap handoff ($1.84, compact #1/handoff data above): about 8x cheaper.
- Clean 150k measurement: still to come (next compaction after Shay runs /autocompact 183000).
