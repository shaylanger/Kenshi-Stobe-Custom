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

## Compact #2 (MANUAL /compact, 2026-10-17 03:06 UTC = 21:06 local, at 284k; NOT the 150k threshold)
- 284,045 -> 14,628 tokens, summarizer 89 s.
- One-off: first turn after MEASURED $0.174. The summarizer call is NOT recorded: UNKNOWN. Assumed cache-read input gives ~$0.09 (input $0.03 + output ~$0.05), but a cache write would be ~$1.2 and uncached ~$0.6. Real number only from /cost before vs after, or the provider usage page.
- Mean turn cost: before $0.048 (n=15) -> after $0.0326 (n=14).
- CORRECTION 21:09: an earlier message to Shay quoted $0.23, which was compact #1 (the auto one at 02:34Z), not this one.
- Comparison caveat: the "$1.84 handoff vs $0.23 compact" ratio is not like-for-like (handoff figure = 25 turns of the new session incl. real work + the tail's 69 turns; compact figure = one-off only). Fair view: after a compact you still pay ~$0.03/turn; the real extra cost of the handoff is the tail's $1.40.
- Clean 150k measurement: still to come (after /autocompact 183000).

## /cost reconciliation (Shay pasted /cost at ~03:15Z; session total $67.60 = Sonnet $64.34 + Haiku $3.25)
- Transcripts (main + 347 subagent files, since 01:44Z) re-priced with prices.json: $53.74. Gap $13.86.
- Token categories, Sonnet: uncached input /cost 596k vs transcript 4.3k -> gap 592k = 299k (compact 1) + 284k (compact 2) + ~9k. So the two summarizer calls were billed as UNCACHED input ($2/M): ~$0.60 and ~$0.57, NOT cache-read ($0.03). Inferred from the totals matching within 1.5%, not read directly.
- So a compact at ~290k costs about $0.6 (summarizer input) + ~$0.05 output + first turn $0.17 = ~$0.8, not $0.23-0.26. Earlier break-even (15 turns) is ~3x too optimistic: about 50 turns. Cost scales with the pre-compact size, so a 150k compact is about half of that.
- Transcript output tokens are UNDERCOUNTED: /cost Sonnet output 1.5M vs 0.69M in transcripts (~$8 of the gap). All MEASURED per-turn costs here are ~20-25% low (the handoff and compact figures are affected alike).
- Unexplained: Haiku uncached input 1.6M in /cost vs 2k in transcripts.
- Procedure from now on: Shay runs /cost before and after each compact (meter warn text says so).

## Compact #3 (first at the 150k threshold) - /cost BEFORE reading
- Shay pasted at ~03:29Z (wall 1h33m, context ~135k): total $69.42 = Sonnet $66.17 (uncached input 609.8k, output 1.5M, cache read 204.5M, cache write 11.3M) + Haiku $3.25 (unchanged).
- Next: Shay pastes /cost right after the compact. Real cost = (after - before) minus the normal turns/subagent spend in between (read from transcripts with the same re-pricing); the uncached-input delta should be ~ the pre-compact context (~150k) if the summarizer is billed uncached again.
