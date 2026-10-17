SUITE-A2 report. Read-only: nothing was edited, created, deleted or restarted. The database was only read (SELECT), git only logged or status-checked, and no POST requests were made.

## Summary

Both problems are server-side: the live tree /var/www/html/StobeServer and its seed data. I found no fault in the Stobe mod. It sends the name and a handle, and the server picks the persona and the reply.

1. Identity: the seed data gives the Emperor's persona to the bare name "Tengu". Every NPC called Tengu gets it, the persona is copied into her stored profile, and the LLM is told she is the Emperor of the United Cities. The real emperor's rows are named "Emperor Tengu".
2. "I haven't agreed to that job": the LLM replied with a move order (MoveToTarget@Shay). The trust gate refused it, and the validator then replaced her whole spoken line with the gate's fallback text. For this order that text is "I haven't agreed to that job." Nobody offered a job. The wording is wrong for every refused minor order, whatever her identity.

The same name match has already copied unique personas onto four other stored NPCs in this database (Horse, Grey, Jaegar, Tinfist). Horse is clearly wrong. So the identity fix needs a class-level decision as well as the Tengu fix.

## Root cause

1. /var/www/html/StobeServer/data/schema.sql lines 3404-3408 seed five bio_unique rows named exactly "Tengu" with the Emperor persona (committed in 1eee261 "RELEASE!", 2026-03-14). The unique-bio lookup matches display names only (/var/www/html/StobeServer/lib/data_functions.php:5434, `WHERE LOWER(name) = $1`). selectBioTraitsForNpc (data_functions.php:5685) takes unique traits before random ones. The result is written to her stored profile, core_npc_master id 85663, when the profile is created.
2. /var/www/html/StobeServer/lib/travel_companionship.php:561 (`$text=$why;`) overwrites the NPC's reply for every refused order. /var/www/html/StobeServer/lib/chat_helper_functions.php:15925 returns "I haven't agreed to that job." for MOVE_TO_TARGET, HOLD_POSITION, BODYGUARD and GUARD_TARGET. Only FOLLOW, MOVE_TO and TRAVEL_LOCATION have their own text (15921-15924).

## Evidence

Issue 1 (identity)
- DB, bio_unique: five rows with name='Tengu' (ids 11-15, enabled): personality "Entitled, theatrical, and insulated from consequences."; backstory "United Cities emperor raised in luxury while nobles enforce his rule."; speechstyle "Imperious tone with abrupt demands and mockery."; occupation "Emperor of the United Cities."; goals "Maintain noble control, tribute flow, and personal comfort." The real emperor is "Emperor Tengu" (6 rows; appearance "Scorchlander male...", occupation "...throne room in Heft").
- DB, stored copy: core_npc_master id 85663 (name Tengu, race Shek, female, faction Anti-Slavers, lock_profile false) holds all five seed texts, and it is the only row that does. created_at is 2026-10-15 03:49:19 in the DB zone (Europe/Madrid), which is 19:49:19 local (UTC-6), 30 s before her first chat.
- Prompt, /var/www/html/StobeServer/log/context_sent_to_llm.log: line 1916786 is the request for npc_name 'Tengu' (req_6ad0313d4e3da, 01:49:50 UTC). Line 1916812 says "Tengu is a Shek aligned with Anti-Slavers", which is correct. Line 1916816 says "United Cities emperor raised in luxury...", 1916820 "Entitled, theatrical...", 1916828 "Emperor of the United Cities.", and 1916836 the goals. The block is the 'established_character' fact (/var/www/html/StobeServer/lib/npc_motivation_context.php:18).
- Game log, D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log: lines 223-225 (19:50:02.147) "'Tango'? You address an emperor, peasant. But I am in a generous mood - I am walking. Walk with me or step aside." Lines 383-391 (19:51:55) "You got it wrong. It is Tengu. Emperor Tengu, if you want to keep that tongue."
- The name is shared: context_sent_to_llm.log line 449769 lists another "Tengu (Male Scorchlander), Faction: Shinobi Thieves".
- The lookup also strips a bracket suffix (getBioUniqueLookupKeys, data_functions.php:5397-5411), so "Tengu [anything]" matches as well.
- Same class already in the DB (SELECT): only five stored NPC rows share a name with any unique, and all five copy that unique's occupation text. They are 85663 Tengu (Shek, female); 85975 Horse (race "Midland Hive Worker Drone", male) with "Treasure hunter specializing in dangerous looting expeditions..."; 85923 Jaegar (Scorchlander, male) with "Anti-Slaver operative..."; 85723 Grey and 85757 Tinfist (race Unknown, no faction) with the Gatekeeper and Anti-Slavers-leader personas. Horse is clearly a copy onto the wrong NPC. The other three may be the real uniques (not settled).

Issue 2 (the job line). Timeline, stobe.log local time. The server logs at /var/www/html/StobeServer/log/ are UTC, six hours ahead.
- 19:52:38.057, stobe.log line 828: STT_RESULT text_len=26. Line 843: PLAYER_SAY "You are not Emperor Tango." stobeserver.log line 2157671 gives text_sha1 6e6bf764a8496d0132ad84b8bd75c22da74f15e2, which equals sha1("You are not Emperor Tango.") (checked).
- 19:52:47, stobeserver.log line 2157754 (req_6ad031e617a02): actions ["MOVE_TO_TARGET@Shay"]. Raw reply in /var/www/html/StobeServer/log/chat_llm_full_capture.log line 151: message "\"Tango\" again. You are either deaf or you enjoy bleeding. I am walking, peasant, and you are in my way. Step aside.", action MoveToTarget, target Shay.
- 19:52:47, stobeserver.log lines 2157755-2157758: "REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job." and "Order rejected before speech".
- 19:52:48.035, stobe.log lines 864-866: she speaks "I haven't agreed to that job." /var/www/html/StobeServer/log/output_to_plugin.log line 10041 queues that same text.
- 19:52:48, stobeserver.log lines 2157763-2157767: the canned line is stored as her chat memory row.
- Later prompts contain "- Tengu, speaking to Shay: I haven't agreed to that job." (context_sent_to_llm.log line 1922177).
- 19:52:52, stobe.log line 916: the player says "I didn't give you a job."
- Trigger, context_sent_to_llm.log line 1921273: "Shay: You are not Emperor Tango. (talking to: Tengu)".

Why the order was refused (by design): /var/www/html/StobeServer/processor/chat.php lines 1966-1970 call stobeTravelValidateOrders (travel_companionship.php:538), which calls stobePlayerOrderGate (chat_helper_functions.php:15898). Line 15915: MOVE_TO_TARGET is in the minor list (15886). Line 15917: trust 0 is below 56 (prompt policy line 1917175: affinity_to_configured_player 0, minor_order_min 56). Line 15919: stobeTravelOrderGate returns null for this command (travel_companionship.php:378-380 handles only FOLLOW, MOVE_TO and TRAVEL_LOCATION). The travel branch does not apply, so line 15925 returns the job line.

## What you ruled out
- Random bio pool: no bio_random row mentions "emperor of the united cities" (SELECT returned 0).
- The real emperor's rows: they are not matched (exact name). The prompt's occupation text is the bare-name row's text, and her appearance is "Female Shek", not the Scorchlander emperor.
- The mod or game data: the prompt and the roster say Shek, Anti-Slavers. Only the persona rows say emperor.
- Speech-to-text as the cause of the emperor claim: the persona was in the prompt before any player line reached the server. STT explains only the "'Tango'?" reaction. No server code maps "tango" (grep of the server PHP, JSON and Python: no hits).
- Negotiation tier (negotiation_phase1.php:363-370): gives any "Tengu" tier 5, "ruler", for pricing. That word is not in the chat prompt. It is a side effect of the same name (fix A4).
- Rename protection (data_functions.php:6100, 6126): 'tengu' is a protected name, so this path never marks her rename-eligible. It supplies no persona.
- A job offer by Shay: no chat line before 19:52:48 mentions a job. The first "job" is the refusal itself (stobe.log line 865).
- The trust gate: refusing a minor order from affinity 0 matches the policy. The fault is the speech replacement and the wording.
- Identity dependence of the job line: the replacement path takes no identity input, so any NPC refused a MOVE_TO_TARGET says the same line.

## Proposed fix

Nothing has been applied. Fix A stops the Tengu persona, Fix B stops the job line, and Fix C is a decision for you.

Fix A1, /var/www/html/StobeServer/data/schema.sql (committed, clean): delete the five tuples and the blank line after them.
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

Fix A2, /var/www/html/StobeServer/debug/db_updates.php: append a new applyPatch after the newest one (the last is 202610020001, at line 2936). Use the next unused ID. Without this, existing databases keep the rows, and a re-run of schema.sql puts them back, because ON CONFLICT DO NOTHING re-inserts a deleted row.
```php
        $applyPatch('bio_unique', 202610140001, static function () use ($db): void {
            // Bare-name "Tengu" rows carried the Emperor's persona onto every NPC named Tengu.
            $db->exec("DELETE FROM bio_unique WHERE LOWER(name) = 'tengu'");
            $db->exec("DELETE FROM bio_unique_custom WHERE LOWER(name) = 'tengu'");
        });
```

Fix A3, the stored copy (run once, after A2): clear her saved persona so the next snapshot can rebuild it. Do this after A2. If the snapshot re-derives the persona from the name (not traced), the bare rows would otherwise supply it again.
```sql
UPDATE core_npc_master
   SET personality = '', backstory = '', speechstyle = '', occupation = '', goals = ''
 WHERE id = 85663 AND occupation = 'Emperor of the United Cities.';
```

Fix A4, /var/www/html/StobeServer/lib/negotiation_phase1.php:370 (committed, clean): drop the bare "tengu" alternative. The real emperor still gets tier 5 from his 100000 bounty and from "emperor tengu". No test under /var/www/html/StobeServer/tests mentions tengu.
```diff
-    if (preg_match('/\b(holy lord|phoenix|emperor tengu|tengu|bugmaster)\b/', $who)) $tier = 5;
+    if (preg_match('/\b(holy lord|phoenix|emperor tengu|bugmaster)\b/', $who)) $tier = 5;
```

Fix B1, /var/www/html/StobeServer/lib/travel_companionship.php lines 557-562 (UNTRACKED in the live tree: back it up first). Only a refused travel plan answers in the refusal's words. A refused ordinary order is dropped, and she keeps her own line.
```diff
         $why=stobePlayerOrderGate($actor,$npc,strval($action));
         if ($why === '') { $kept[]=$action; continue; }
         // A rejection must never enter memory as an executed action.
         storeEvent('infoaction',time(),$gamets,$actor.': REJECTED '.$action.'; not dispatched. '.$why.' (talking to: '.$speaker.')');
-        $text=$why;
+        // Only a refused travel plan answers in the refusal's words. A refused ordinary order is
+        // dropped and the NPC keeps her own line.
+        if (in_array(explode('@',$action,2)[0],['FOLLOW','MOVE_TO','TRAVEL_LOCATION'],true)) $text=$why;
         stobeLogInfo('Order rejected before speech',['actor'=>$actor,'action'=>$action,'reason'=>$why]);
```

Fix B2, /var/www/html/StobeServer/lib/chat_helper_functions.php:15925 (modified in the live tree: anchor-patch only). The new wording implies no job. This text is also spoken by the player-order path (line 16134) and stored as the reason (lines 13995-13997).
```diff
-    return "I haven't agreed to that job.";
+    return "I don't take orders from you.";
```

Fix C, a decision for you: the four stored copies and the other bare-name uniques.
- Quick option: delete the bare-name unique rows that are also generic NPC names (Horse, Grey, Jaegar, Tinfist, after a game check of each), then clear their stored copies with the A2 and A3 pattern.
- Real fix: an identity guard in selectBioTraitsForNpc (data_functions.php:5677). Apply a unique persona only when the NPC's race and faction agree with that unique, or when the Stobe payload carries a unique key. Stobe sends only name plus handle today (the "people" lists in stobe.log, e.g. Tengu|130004880), so a key needs a mod change. Not checked whether the game exposes one.

## How to confirm the fix worked

Before and after (SELECT only):
- `SELECT count(*) FROM bio_unique WHERE LOWER(name)='tengu';` gives 5 now and 0 after A2. The 'Emperor Tengu' rows stay at 6.
- The join of core_npc_master to combined_bio_unique on name and occupation text gives 5 rows now (85663, 85975, 85923, 85723, 85757). After A2 and A3 it gives only the rows you decide to keep.

Offline, must fail before the change and pass after. Add these to the server regression set:
- /var/www/html/StobeServer/tests/bio_unique_regression.php: a check that the bare name Tengu gets no unique persona. It fails now (5 rows) and passes after A2.
- A new file, /var/www/html/StobeServer/tests/travel_order_refusal_regression.php (rollback DB harness, as in bio_unique_regression.php). Call stobeTravelValidateOrders('Tengu', <npc with no relationship rows>, 'Shay', <gamets>, $text, $actions) with $text = "I am walking, peasant, and you are in my way. Step aside." and $actions = ['MOVE_TO_TARGET@Shay']. After B1, $text is unchanged and $actions is []. Now, $text becomes "I haven't agreed to that job.".
- `grep -rn "agreed to that job" /var/www/html/StobeServer/lib/` returns no hits after B2.
- `php -l` on each changed file. stobe-tests must pass before the next game batch.

In game, after deploy and relaunch, sent with stobe-say so the words are exact:
- Select Tengu at Spring and say "What's up, Tengu?". She must not claim to be an emperor. The next prompt for npc_name Tengu in context_sent_to_llm.log must not contain "Emperor of the United Cities" or "Imperious tone".
- Say "You are not Emperor Tango." (the exact text the server received), then "You are not Emperor Tengu.". Her own line must be spoken. stobe.log must have no NPC_SAY containing "agreed to that job", and no chat memory row may contain the canned line. The reply varies, so if the MoveToTarget reply does not recur, force it with a test switch (none verified for travel replies).

Deploy per the workspace rules: back up, stage, php -l, regression, deploy to the live tree and /root/stobe-work/ss-merge, rotate logs, commit and push. schema.sql, db_updates.php and negotiation_phase1.php are committed and clean. chat_helper_functions.php has live uncommitted changes. travel_companionship.php is untracked, so commit it on purpose.

## What is not settled
- Whether Shay said "Tengu" and Parakeet heard "Tango", or he said "Tango". The transcripts have "Tango" in 3 of 4 name utterances (stobe.log lines 195, 440, 843) and "tengu" once (line 767). No audio is kept. If he said "Tengu", the recognizer needs name biasing, which is a separate ticket.
- The real emperor's in-game name. The wealth-template key and both unique seed files say "Emperor Tengu", and this save has no stored row for him. If the game names him only "Tengu", A1 and A2 would strip his persona, so check his roster name first.
- Whether a snapshot re-derives the trait fields of an existing core_npc_master row (storeNpcSnapshot, data_functions.php:11026-11140, not traced to the UPDATE). A3 makes the Tengu case certain.
- Whether Grey (85723), Tinfist (85757) and Jaegar (85923) are the real uniques or generic NPCs with the same names. That needs a game check of each.
- Which of the 92 single-word bio_unique names collide with generic NPCs in the game (list: `SELECT name, count(*) FROM combined_bio_unique WHERE name NOT LIKE '% %' GROUP BY name`). Only the five above are confirmed.
- Whether the Stobe payload can carry a unique key. Only name plus handle was seen, and the mod source was not checked.
- The trust value the gate used for the job request. The policy block shows 0 for the first request (context_sent_to_llm.log line 1917175). I did not re-read the relationship data for the job request.
- Why the LLM chose MoveToTarget for "Step aside". That is an LLM action choice, not a server fault on its own.
