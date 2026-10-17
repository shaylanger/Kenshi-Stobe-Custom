# imm26-fix16bxbrevity (row 16-bx word cap; Shay 2026-10-16 "3: a")
Evidence: 16-bx v3 FAIL 0/3 on 4080-i3 (agents/out/imm26-4080-i3op31/out-20261016-204558.md, ev-16bx-rep1..3): the reserved Fond NPC (Cind) answered 45/50/44/49 words in 4 of 9 replies; the prompt only
had "Vary response length naturally" (lifelike_continuity rule) and no trait brevity rule. Note Cind's profile never says "reserved" (personality "Lighthearted ...", speechstyle "Tends toward understatement and dry humor.
Gets quieter and more direct when serious."); the checker's trait_in_prompt only passed through the generic "A reserved friend can be caring without gushing" sentence that every NPC gets.

## Change (lib/imm26_personality.php only)
- imm26TerseTemperament($npc): pure; true when personality or speechstyle contains reserved | taciturn | laconic | terse | curt | stoic | reticent | tight-lipped | soft-spoken | (of) few words | words sparingly |
  understatement | understated (not after "not "/"never "/"un").
- imm26BrevityLine($npc): '' for everybody else; for a terse NPC ONE line: "Your temperament is reserved: you are a person of few words. Answer in at most 40 words, usually one or two short sentences, even with a close friend."
- imm26PersonalityAnchorContext(): adds that line inside <personality_anchor> (after the "What you share" line, before the overused-phrase line). A non-terse NPC's prompt is byte-identical to before.
Run: `python3 apply.py <tree-root> [--check]` then `python3 apply_test.py <tree-root>` (idempotent, *.bak-fix16bxbrevity); test: `STOBE_DB_NAME=stobe_test php tests/imm26_wpA_personality_claims_regression.php` (38/38, 9 new; they fatal on the unpatched lib).
Offline suite (tests/*regression*.php + tests/imm26_*.php, 136 files): exit codes identical on the patched stage and the unpatched compose copy (the 20+ non-zero files are the same pre-existing ones in both).
Trees patched: /root/imm26/compose, /tmp/stobe-imm26-5090/site, -5090-i5/site, /tmp/stobe-sfo-manual/site. NOT patched: -5090-i4 (ab2 freeze), the 4080 sites (4080 operator applies via the note), live tree and ss-merge (imm26 reaches them through the compose merge).
