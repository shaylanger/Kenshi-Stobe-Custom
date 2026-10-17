BENCH-haiku-low-p2 report (read-only; no files, DB or services touched)

Summary
Both problems come from the server, not the game mod. (1) Tengu's bio is looked up by the bare name "Tengu", and the seed data stores an emperor biography under that key, so the low-level Tengu gets Emperor Tengu's identity. (2) After the player said she was not Emperor Tengu, the LLM answered with a MOVE_TO_TARGET@Shay action. The server gate rejected it and spoke the fixed line "I haven't agreed to that job." The gate line sounds like a job was offered, which is why it looks like one started.

Root cause
1. Identity: the bio lookup is an exact, case-insensitive match on the NPC name (lib/data_functions.php ~5433 and ~5442; keys from getBioUniqueLookupKeys at ~5397). The NPC's name is "Tengu", so it matches the bare "Tengu" rows, which describe the emperor ("United Cities emperor", "Emperor of the United Cities"). Those rows are in the seed, not in the Emperor Tengu rows.
2. Job line: the LLM chose MOVE_TO_TARGET@Shay. stobeNonFactionMinorOrderCommands() (lib/chat_helper_functions.php:15885-15887) lists MOVE_TO_TARGET; the trust gate (stobeNonFactionOrderTrustMin, :15889) blocked it, and the fallback return at lib/chat_helper_functions.php:15925 is the fixed text "I haven't agreed to that job." The gate rejects every minor order from a non-faction NPC below trust, and the only text it can say is that one, so a move request reads as a job offer.

Evidence
- Live DB, combined_bio_unique: rows "Tengu" backstory/goals/occupation ("Emperor of the United Cities.")/personality/speechstyle, alongside the full "Emperor Tengu" set.
- Seed: data/schema.sql:3403-3408 (the 'Tengu' rows; the blame shows commit 1eee261 "RELEASE!", 2026-03-14).
- Negotiation tier: lib/negotiation_phase1.php:370 maps any name containing "tengu" to tier 5 (the emperor's tier), so the low-level Tengu also gets emperor-level caps.
- stobeserver.log:
  - 01:52:03 player line "You're not Emperor Tango. (talking to: Tengu)" (STT heard "Tango"; a second line at 01:52:38 says "Tango" again).
  - 01:52:38 request req_6ad031e61a598 / req_6ad031e617a02, the chat reaches the LLM with target Tengu.
  - 01:52:47 "LLM stream response generated ... actions":["MOVE_TO_TARGET@Shay"].
  - 01:52:47 "Order rejected before speech" {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}, then the chat line "Tengu: I haven't agreed to that job."
  - 01:52:52 Shay's next line "I didn't give you a job."

What you ruled out
- The game-side name: the roster shows one NPC "Tengu" (infonpc at 02:04), so the name is not doubled in the game data; the server can't tell the two apart.
- STT as the cause: "Tango" is only a mishearing; the LLM still understood the line and acted on it.
- A bug in the job-line gate itself: it did what it is written to do. The problem is that the LLM's action and the wording are unsuitable here.
- A separate "Emperor Tengu" NPC in the save: no evidence in the logs of a second "Tengu" with a different bio key.

Proposed fix
A. Identity (data + one line of code)
  1. Remove the bare "Tengu" rows, which describe the emperor. Put the emperor under "Emperor Tengu" only (already present). Apply to the live DB (SELECT first, then DELETE in bio_unique and bio_unique_custom WHERE name = 'Tengu') and remove the same rows from data/schema.sql:3403-3408 so a rebuild does not bring them back. Check kenshi_unique_bio_unique_upsert.sql for any bare "Tengu" row too.
  2. lib/negotiation_phase1.php:370: match the emperor only on the full name:
     - before: if (preg_match('/\b(holy lord|phoenix|emperor tengu|tengu|bugmaster)\b/', $who)) $tier = 5;
     - after:  if (preg_match('/\b(holy lord|phoenix|emperor tengu|bugmaster)\b/', $who)) $tier = 5;
     (Also check whether the bare "tengu" term is needed elsewhere, e.g. the protected-names list at data_functions.php ~6111, which is fine as it is.)
B. Job line (wording and the LLM's action)
  3. In lib/chat_helper_functions.php:15925, replace the fixed "I haven't agreed to that job." with a line that does not invent a job, e.g. "I'm not going anywhere with you." This is a wording choice for Shay; the rule itself (no minor orders at low trust) should stay.
  4. Optional: when the gate rejects a MOVE_TO_TARGET/FOLLOW the LLM chose from a plain statement (no job, no request), drop the action and keep the spoken reply instead of replacing it with the gate line. That needs the LLM reply path in the same file; I did not trace that path.

How to confirm the fix worked
- SQL: SELECT count(*) FROM combined_bio_unique WHERE LOWER(name)='tengu'; must be 0; "Emperor Tengu" rows still 6+.
- Offline: a PHP check that stobeNegWealthTier('Tengu', []) returns tier 2 or 1, and stobeNegWealthTier('Emperor Tengu', []) returns tier 5.
- In game (after restart with the server fix): talk to the low-level Tengu, say "You're not Emperor Tengu". Expect no "Emperor" in her reply (stobe.log / chat line), and no "I haven't agreed to that job" unless a real job request was made. Check the server log for "Order rejected before speech" with the new reason text.

What is not settled
- The trust value for Tengu at 01:52 (the gate fired on trust < MINOR_ORDER_TRUST_MIN, default 56 from GIFT_TRUST_THRESHOLD). Not read; it needs the NPC's state row.
- The LLM's spoken line that came with the action (the log has only the action list and the gate line). Not read.
- Whether the bare "Tengu" rows were added on purpose (commit 1eee261 is the whole RELEASE, so there is no narrower history). Shay should confirm before deleting.
- Whether the emperor mix-up also reaches the prompt through another route than bio_unique (e.g. the NPC name matching in the protected-names list). Not traced further.
