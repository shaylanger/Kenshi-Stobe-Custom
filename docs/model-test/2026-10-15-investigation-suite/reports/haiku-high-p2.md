BENCH-haiku-high-p2 report (read-only; no files, services or DB rows changed)

## Summary
Both symptoms have one cause each, and both are server-side (Stobe mod and game data are not at fault).
1. "Emperor Tengu" belief: the server's profile for any NPC named exactly "Tengu" comes from five seed rows in `bio_unique` that describe the Emperor (schema seed, `data/schema.sql` lines 3404-3408). The anti-slaver Tengu is a low-level Shek woman, but the LLM was given "Emperor of the United Cities" as her occupation.
2. "I haven't agreed to that job": the LLM replied "Tango again... I am walking, peasant... Step aside." with action MoveToTarget@Shay. The travel gate refused the action, and `stobeTravelValidateOrders` replaced the whole spoken line with the gate's canned refusal. The player never heard the LLM's line; the refusal text is the generic minor-order fallback, which says "job".

## Root cause
1. Exact-name profile lookup (`lib/data_functions.php` `getBioUniqueLookupKeys` / `loadBioUniqueTraitSelections`, `LOWER(name) = $1`) matches the seed rows named 'Tengu'. Unique traits win over random ones, so the stored profile (`core_npc_master` row Tengu) and the prompt both say Emperor. The real Emperor's rows are named 'Emperor Tengu' and are never matched for the bare name.
2. `lib/travel_companionship.php:538-564`: on a rejected order, line 561 `$text=$why;` discards the LLM's reply text. The fallback in `lib/chat_helper_functions.php:15925` (`return "I haven't agreed to that job.";`) is returned for any MOVE_TO_TARGET from a non-faction NPC whose trust is below `MINOR_ORDER_TRUST_MIN` (default 56, `stobePlayerOrderGate` ~line 15900-15926).

## Evidence
Game log (`D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`, game-local time):
- :163 NPC panel for Tengu: "Shek woman, 42-year-old", "Job: unknown", "Faction: Anti-Slavers" (the game's own data contradicts the Emperor profile).
- :195 `[EVENT] chat: Shay -> Tengu ("What's up, Tango?")`, from STT (`STT_RESULT` at :182).
- :225 (19:50:02) NPC: "'Tango'? You address an emperor, peasant..." (gen=3).
- :383 (19:51:55) NPC: "You got it wrong. It is Tengu. Emperor Tengu, if you want to keep that tongue." (gen=4).
- :866 (19:52:48) NPC: "I haven't agreed to that job." (gen=7). Preceded by :849 player "You are not Emperor Tango."

Server log (`/var/www/html/StobeServer/log/stobeserver.log`, server time = game time + 6 h):
- 2026-10-15 01:52:47 `LLM stream response generated ... actions ["MOVE_TO_TARGET@Shay"]` (req_6ad031e617a02).
- 01:52:47 `Order rejected before speech | {"actor":"Tengu","action":"MOVE_TO_TARGET@Shay","reason":"I haven't agreed to that job."}`.
- `log/output_from_llm.log` (same request) raw reply: `"message": "\"Tango\" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside.", "action": "MoveToTarget", "target": "Shay"`.
- `log/output_to_plugin.log` 01:52:48: the only line sent to the game is `message":"I haven't agreed to that job."`.
- `log/context_sent_to_llm.log` (Tengu turns): `established_character: {personality "Entitled, theatrical, and insulated from consequences.", occupation "Emperor of the United Cities.", goals "Maintain noble control, tribute flow, and personal comfort.", speechstyle "Imperious tone with abrupt demands and mockery."}`.

Database (`stobe`, SELECT only):
- `bio_unique` ids 11-15: name 'Tengu', types personality/backstory/speechstyle/occupation/goals, created 2026-09-25 05:19:30, enabled. `bio_unique_custom` has no Tengu row.
- `bio_unique` ids 113-118: name 'Emperor Tengu' (the real Emperor, "Scorchlander male").
- `core_npc_master` row Tengu: personality "Entitled, theatrical...", occupation "Emperor of the United Cities.", updated 2026-10-15 04:08:40.

Code: `data/schema.sql:3404-3408` (the seed rows). `lib/negotiation_phase1.php:370` also matches any "tengu" as wealth tier 5 (same name collision, pricing side).

## What you ruled out
- Fuzzy or prefix matching in the bio lookup: it is exact (`LOWER(name) = $1`, with a bracket-suffix strip only). The Emperor rows are not used for the bare name; the 'Tengu' rows are.
- The Stobe mod naming her wrongly: INV_SYNC, PORTRAIT_SYNC and the NPC panel all name her Tengu, Shek, Anti-Slavers, job unknown.
- STT as the cause of the Emperor belief: the transcript may be "Tango", but the profile is the same for "Tengu". The Emperor claim is in the profile, not the spelling. STT is still a secondary issue (see unsettled).
- The gate creating the Emperor belief: the Emperor line at :225 came before any gate event.
- A real job or contract: no accepted travel/task record was involved; the gate fired on the LLM's invented MOVE_TO_TARGET.
- The validator not running: it runs for any non-faction chat turn (`processor/chat.php:1448`, `:1968-1970`).

## Proposed fix
Fix 1 (Emperor belief, the root): remove the generic 'Tengu' seed rows.
- `data/schema.sql`: delete lines 3404-3409 (the five `('Tengu', ...)` rows and the blank line after them), so the list keeps its commas:
```diff
 ('Esata the Stone Golem', 'goals', 'Preserve Shek power without sacrificing the kingdom to reckless wars.'),
 
-('Tengu', 'personality', 'Entitled, theatrical, and insulated from consequences.'),
-('Tengu', 'backstory', 'United Cities emperor raised in luxury while nobles enforce his rule.'),
-('Tengu', 'speechstyle', 'Imperious tone with abrupt demands and mockery.'),
-('Tengu', 'occupation', 'Emperor of the United Cities.'),
-('Tengu', 'goals', 'Maintain noble control, tribute flow, and personal comfort.'),
-
 ('Cat-Lon', 'personality', 'Obsessive, grandiose, and bitterly rational.'),
```
- Live DB (existing installs): add a patch in `debug/db_updates.php` modelled on the existing one at lines 1265-1268, using the next free patch id (check the file's maximum first):
```php
$applyPatch('bio_unique', 202610140001, static function () use ($db): void {
    $db->exec("DELETE FROM bio_unique WHERE LOWER(name) = 'tengu'");
});
```
- Then re-resolve the stored Tengu profile (`core_npc_master`, updated 2026-10-15). The re-resolve path is not confirmed (see unsettled).
- Optional, pricing side: in `lib/negotiation_phase1.php:370` drop the bare `tengu` alternative (keep `emperor tengu`). This changes wealth-tier pricing for every NPC named Tengu, so it needs Shay's OK.

Fix 2 (the "job" line): keep the LLM's words when an order is refused.
- `lib/travel_companionship.php:561`:
```diff
         storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
-        $text=$why;
+        // Keep the NPC's own reply; only the order is dropped.
+        if (trim($text) === '') $text=$why;
         stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
```
  Risk: the kept reply could still agree to the refused order (e.g. "Fine, let's go"). Mitigation: keep the gate line whenever the reply affirms the order; a small check on acceptance words is enough for a first version.
- Also reword the generic fallback at `lib/chat_helper_functions.php:15925` for MOVE_TO_TARGET/MOVE_TO (e.g. "I'm not walking with you on your word alone.") so the word "job" is not used for movement. Low priority.

## How to confirm the fix worked
- Offline (before/after): a PHP regression in the style of `tests/negotiation_engine_regression.php`. Call `stobeTravelValidateOrders` with `$text` = the 01:52:47 LLM message, actions `['MoveToTarget@Shay']`, and a non-faction NPC with trust < 56. Before the fix `$text` becomes "I haven't agreed to that job."; after it, `$text` is unchanged and `$actions` is empty. Add a second case where the text affirms the move, which must still give the gate line.
- Offline: profile check. `SELECT * FROM bio_unique WHERE LOWER(name)='tengu'` returns 0 rows; the Tengu profile built for the prompt has no "Emperor" in occupation.
- Game (batch, after the server fix and `stobe-tests` pass): with STOBE on, select the anti-slaver Tengu, say "You're not Emperor Tengu" and "Step aside". Pass = no "Emperor" in any NPC line, no "job" line, and the NPC's reply stays in-character (stobe.log NPC_SAY lines, and `stobeserver.log` no "Order rejected" for a line that did not ask for a move).

## What is not settled
- Whether the player said "Tengu" or "Tango": the STT transcript text is not logged (only its length and sha1). The Emperor belief is independent of this, but the STT mishearing should be checked from the audio.
- How the stored `core_npc_master` Tengu profile is re-resolved after the seed rows are deleted (the code path that rebuilds it was not traced). It may need an explicit refresh or a clear of the row.
- Whether other NPCs named exactly "Tengu" exist in the game and already have this profile (they would, by the same exact-name match; not enumerated in-game).
- The rejection is written to memory as an infoaction ("REJECTED MoveToTarget@Shay ... I haven't agreed to that job."), which may feed later prompts. Not traced whether the job wording repeats later.
- The LLM mapped "Step aside" to MoveToTarget@Shay. Whether to also tighten the prompt's action mapping for "step aside" is a product choice.
