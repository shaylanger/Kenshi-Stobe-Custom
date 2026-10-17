## Summary

Two separate causes, both on the Stobe server side. Nothing was edited, restarted or written.

1. **"Emperor Tengu" confusion:** the server's base seed `data/schema.sql` (lines 3404-3408) has `bio_unique` rows named exactly `Tengu` (ids 11-15) that describe the Emperor. Any NPC whose name is exactly "Tengu" gets the Emperor's personality, occupation, backstory, speech style and goals. The real Emperor is `Emperor Tengu` (ids 113-118), so the bare-name rows are a collision.
2. **"I haven't agreed to that job":** no job was ever offered in the chat. The LLM invented it. The Emperor persona and the server's order/deal rules probably turned Tengu's earlier "Walk with me or step aside" into a job offer. The model then rejected it. Shay's next line "I didn't give you a job" was a correction of something that was never said. This is a generation problem with no guard behind it.

## Root cause

**Issue 1:** The NPC `Tengu` (core_npc_master id 85663, faction Anti-Slavers) carries the Emperor's bio because the bio lookup matches on the plain name. `lib/data_functions.php` `getBioUniqueLookupKeys()` (line 5397) and `loadBioUniqueTraitSelections()` (line 5413) do an exact `LOWER(name) = 'tengu'` match against `combined_bio_unique`. That matches the bare-name rows 11-15, which are the Emperor's text. The NPC's stored `personality` and `occupation` are identical to those rows. The server then builds the prompt's `established_character` block from that stored profile (`lib/npc_motivation_context.php` lines 9-18, called from `lib/npc_conversation_context.php` line 48).

**Issue 2:** The generated reply at 19:52:48 has no action and no goal behind it. Tengu's conversation history has no job offer. The nearest thing is his own "Walk with me or step aside" at 19:50:02. The prompt also tells the model to shape its first reply around any hint of a request, and to weigh "orders/deals" rules. That is the most likely route to a hallucinated job. This is a probable cause, not proven from the logs.

## Evidence

Issue 1, stobe.log (`D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, the live one; the `D:\KenshiInst\2|3` copies are stale):
- 19:49:49.290 `[EVENT] chat: Shay -> Tengu (What's up, Tango?)`. The player's text was "Tango", not "Tengu".
- 19:50:02.147 gen 3 Tengu: `"Tango"? You address an emperor, peasant. But I am in a generous mood - I am walking. Walk with me or step aside.`
- 19:51:55.129 gen 4 Tengu: `You got it wrong. It is Tengu. Emperor Tengu, if you want to keep that tongue.`
- 19:52:03.443 Shay: `You're not Emperor Tango.`
- 19:52:12.597 gen 5 Tengu: `Tango. Tengu. You are not even close...`
- 19:52:48.035 gen 7 Tengu: `I haven't agreed to that job.` (ACTION_EXEC shows SAY only; no action).
- 19:52:52.499 Shay: `I didn't give you a job.`

Server LLM context (`/var/www/html/StobeServer/log/context_sent_to_llm.log`, around lines 1922161-1922177, and 1922288):
- The history for the gen-7 request shows no job offer between the player's lines and Tengu's reply. The only earlier request-like line is "Walk with me or step aside."
- The `established_character` block for Tengu reads: personality "Entitled, theatrical...", occupation "Emperor of the United Cities.", goals "Maintain noble control, tribute flow...", speechstyle "Imperious tone...".

Database (`stobe`, SELECT only):
- `bio_unique` ids 11-15: `Tengu` / personality|backstory|speechstyle|occupation|goals, with the occupation "Emperor of the United Cities.", `is_enabled = t`, created 2026-09-25 by the base seed.
- `data/schema.sql` lines 3404-3408 are the source of those five rows.
- `bio_unique` ids 113-118: `Emperor Tengu`, the proper Emperor rows.
- `core_npc_master` id 85663: name `Tengu`, faction `Anti-Slavers [58229-Dialogue.mod]`, race Shek, occupation "Emperor of the United Cities.", personality "Entitled, theatrical, and insulated from consequences.", `lock_profile = f`, created 2026-10-15 03:49 Madrid time, which is 19:49 Shay's time (UTC-6). This is the NPC from the chat.
- Blast radius: other bare-name rows with an NPC carrying their occupation are `Grey`, `Horse`, `Jaegar`, `Tinfist` (one NPC each). Dozens of bare-name rows exist in general, such as `Arc`, `Agnu`, `Barnabus`, `Bard`; most of them probably have no NPC of that name.

Goal files: `stobe_task_goals.tsv`, `stobe_work_goals.tsv`, `stobe_goals.log` contain no Tengu entry. No job was ever created for him.

## What you ruled out

- **Fuzzy matching of "Tengu" to "Emperor Tengu":** the lookup is an exact lowercase match. The Emperor rows are matched only because a row named plain `Tengu` exists.
- **A real job or goal:** no goal file or work-goal record references Tengu.
- **An action fired at gen 7:** stobe.log shows only `SAY`.
- **The player's wording as the cause of the Emperor persona:** "Tango" vs "Tengu" only changed Tengu's reaction. The persona came from the bio rows, not from the chat.
- **STT:** the player's line reached the chat path as "What's up, Tango?". Whether Shay typed it or dictated it is not in the logs.

## Proposed fix

**Fix 1, bad bio rows (the Emperor persona):**
1. `data/schema.sql`: delete lines 3404-3408 (the five `('Tengu', ...)` tuples). Keep the `Emperor Tengu` rows at `kenshi_boss_bio_unique_upsert.sql` lines 75-80 and `kenshi_unique_bio_unique_upsert.sql` lines 225-230.
2. Existing installs (the seed won't re-run on them): add a patch in `debug/db_updates.php` next to patch `202606150001` that does `UPDATE bio_unique SET is_enabled = FALSE WHERE name = 'Tengu' AND type IN ('personality','backstory','speechstyle','occupation','goals')` and the same on `bio_unique_custom` if rows exist. A patch is needed because `ADD COLUMN IF NOT EXISTS` patches don't re-run.
3. The NPC row: `core_npc_master` id 85663 keeps the Emperor fields. Either re-run profile selection for that NPC (`selectBioTraitsForNpc`, data_functions.php line 5676) or clear the five trait fields and re-derive. Not verified which entry point is safe on a live save; check before running it. Do not change it by hand without that check.
4. Code guard (optional but recommended): in `loadBioUniqueTraitSelections`, skip a bio row when its name is a bare common name that also has a `Emperor`/title-qualified row, or require the NPC's race/faction to match. A simpler option is a regression test in `tests/` that fails if any `bio_unique` name without a space is seeded with a `occupation` that starts with a title.

**Fix 2, invented job (hallucination guard):**
1. `lib/npc_conversation_context.php` (near the `ORDERS/GIFTS` block) and `lib/npc_motivation_context.php` (the rules list around line 25): add a line such as "Do not mention a job, deal, contract or offer unless it appears in the conversation history or in your active goal state. A request to walk with someone is not a job. Never refuse or accept an offer that was not made."
2. Optional post-generation check where the reply is parsed (the `NPC_SAY` path): if the reply matches `/\b(job|deal|contract|hire)\b/i` and neither the history nor the active goal state contains the same term, log `UNSUPPORTED_OFFER` and regenerate once. Use the existing `stobeLogWarn` pattern.

Both files are in `/var/www/html/StobeServer` (live) and `/root/stobe-work/ss-merge` (patch both).

## How to confirm the fix worked

- SQL: `SELECT name, type, is_enabled FROM combined_bio_unique WHERE name='Tengu'` returns all rows FALSE, and `SELECT occupation FROM core_npc_master WHERE id=85663` no longer says "Emperor".
- Offline: a new regression test that loads `loadBioUniqueTraitSelections('Tengu')` and expects no `occupation` description containing "Emperor". It should fail before the fix and pass after it.
- Offline: a prompt check that `stobeNpcMotivationContext` output contains the new "no job unless in history" line.
- In game: save-load the Anti-Slavers Tengu (or any NPC named Tengu), greet him with "What's up, Tengu?", and confirm the reply has no Emperor reference (`stobe.log` and `context_sent_to_llm.log`, `established_character` should show no occupation). Then say "Walk with me" and check that no "job" appears unless an offer exists in the history.

## What is not settled

- Why the model invented the job. The walk request is the most likely trigger, but the logs do not prove it. The fix in issue 2 works either way, but a regression needs a repeat run to be sure.
- Whether Shay typed "Tango" or dictated it. It does not change the root cause.
- The safe re-derive path for NPC id 85663 on a live save (fix 1, step 3). Not checked against the code path.
- Whether other rows in the bio tables or elsewhere (`combined_rename_token_global`, `bio_random`) have the same bare-name collision. The check above covered `bio_unique` only.
- The DB `created_at` for the NPC is Madrid time. The conversion to Shay's clock was done by inference, not by reading the server timezone config.
