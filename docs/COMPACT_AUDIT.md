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

## Compact #3 RESULT (Shay's /cost, 150k threshold; "before" pasted at context ~1% below the trigger, wall 1h39m56, "after" wall 1h41m26 = 90 s later)
- Session total: $73.64 -> $74.04 = **+$0.40** (Sonnet $70.39 -> $70.78; Haiku $3.26 unchanged). This is an UPPER BOUND for the compact: it also contains everything else billed in those 90 s (my turns, and running subagents bill into the same total).
- Token deltas, Sonnet: uncached input 675.5k -> 689.2k (+13.7k), cache read 216.5M -> 218.0M (+1.5M), cache write 12.0M -> 12.0M (no visible change), output 1.6M -> 1.7M (rounded).
- Reading: the summarizer was NOT billed as ~150k uncached input this time (the uncached delta is only 13.7k, compacts #1/#2 showed ~290k each). It was almost certainly served from the warm cache (cache-read delta 1.5M, about $0.45 at $0.30/M, which is roughly the whole +$0.40 together with other work). The cache was warm: /cost showed "warm (1h TTL)" and "2 expected rebuilds".
- So a 150k compact costs at most about $0.4, and likely less. Compacts #1/#2 (299k/284k) were billed ~$0.8 each; the difference is the cache state at the moment of the summarizer call, not just the size. Cannot separate the exact summarizer share from the 90-s window; do not quote below $0.40 as measured.
- Break-even (rough): turns after the compact cost about $0.03-0.05 each at ~30k context vs ~$0.15 at 150k, so the compact repays within roughly 4-8 turns.

## Compact #4 - /cost BEFORE reading (Shay, context ~147k, 1% before the trigger)
- Total $85.32 (Sonnet $82.05: uncached input 841.9k, output 2.0M, cache read 251.5M, cache write 13.8M; Haiku $3.27 unchanged), wall 1h55m53s, API 6h20m11s, 422 requests, 3 expected rebuilds.
- Since the compact #3 "after" paste ($74.04 at wall 1h41m26): +$11.28 in 14m27s of wall = ~$0.78/min = ~$47/h, while ~10 subagents ran (lane operators, fixers, investigators, Haiku deep dive). Cache write +1.8M, uncached input +153k, cache read +33.5M. This is the number to look at for the credit-use review: the compact is ~$0.4, the agent fleet is ~$47/h.
- Next: Shay pastes /cost right after this compact; record the delta here.

## Compact #4 RESULT (Shay /cost after: $87.04, wall 1h57m58s)
- Delta $1.72 in 2m05s of wall (Sonnet $82.05 -> $83.77, Haiku unchanged). By class (Sonnet, prices.json): uncached input +16.7k = $0.03, cache read +6.2M = $0.62, cache write +0.2M = $0.80 (+-0.1M rounding = +-$0.40), output not resolvable at 0.1m rounding.
- This is an UPPER bound: the same 2 minutes also carried the fleet (~10 subagents, burn rate $0.78/min = ~$1.6 per 2 min before the compact). The compact itself is therefore inside the noise; the clearly attributable part is the new prefix written to cache (~$0.2) plus one warm-cache summarizer pass over ~150k (cache read ~$0.015) and its output (~$0.1-0.3).
- Compact #3 +$0.40 upper bound, compact #4 +$1.72 upper bound (noisier window). Conclusion unchanged: a 150k compact costs well under $1; the fleet costs ~$47/h and is the lever.

## Compact #5 (2026-10-16, Shay's /cost pastes)
- BEFORE (3 s into the compact call): $94.94 (Sonnet $91.67, Haiku $3.27), wall 2h13m08s. Since the #4 after-paste ($87.04, wall 1h57m58s): +$7.90 in 15m10s (fleet burn ~$0.52/min).
- AFTER (1m10s later): $95.64 (Sonnet $92.36, Haiku $3.28), wall 2h14m11s. Delta **+$0.70 in 1m03s** (upper bound, includes the live fleet).
- Detail: cache write unchanged at 15.1m (no cache rebuild), cache read +1.7m, input +14.5k, output +~0.1m. The compact itself is well under $0.70.

## Compact #6 (2026-10-16, Shay's /cost pastes)
- BEFORE (at 1%): $104.85 (Sonnet $101.57, Haiku $3.28), wall 2h29m47s. Since #5 after-paste ($95.64): +$9.21 in 15m36s (fleet burn ~$0.59/min).
- AFTER (1m11s later): $105.24 (Sonnet $101.96), wall 2h31m08s. Delta **+$0.39 in 1m21s** (upper bound, includes the live fleet).
- Detail: cache write unchanged at 16.2m (5 expected rebuilds, no new rebuild), cache read +0.4m. Compacts #3 +$0.40, #4 +$1.72, #5 +$0.70, #6 +$0.39: a 150k compact costs well under $0.50.
