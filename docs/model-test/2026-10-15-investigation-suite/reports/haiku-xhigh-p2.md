BENCH-haiku-xhigh-p2 report (read-only investigation; no code, config or DB changes; one disclosure at the end)

SUMMARY
Two separate server-side causes in the Stobe server (WSL /var/www/html/StobeServer), not in the game DLL.
1. "Emperor Tengu": the server's unique-bio table has five sample rows keyed only by the display name "Tengu" that describe an emperor. Every NPC named "Tengu" gets that persona, including the low-level Anti-Slaver Shek. The real emperor's rows are under "Emperor Tengu" and are not matched.
2. "I haven't agreed to that job": the LLM reply for "You are not Emperor Tango." contained a move order (MoveToTarget@Shay). The server refused it (trust below 56, no accepted travel), using a generic fallback string, and then replaced Tengu's whole spoken line with that string. No job, agreement or goal was created.
Contributing: speech-to-text heard "Tengu" as "Tango" in 4 of 5 turns this session.
Times: stobe.log is local (6 h behind); stobeserver.log is UTC. Example: stobe.log 19:52:48 = stobeserver.log 01:52:48 UTC.

ROOT CAUSE
A. Identity: getBioUniqueLookupKeys (lib/data_functions.php:5397-5411) and the query at lib/data_functions.php:5433-5434 match `LOWER(name) = 'tengu'` only. The game sends only the display name (profile=Tengu, stobe.log:163/187). The five 'Tengu' rows come from data/schema.sql:3404-3408 (upstream RELEASE commit 1eee261, 2026-03-14). The persona in the prompt matches those rows word for word.
B. Job line: the LLM returned action "MoveToTarget" (schema enum, chat_llm_full_capture.log:151), normalized to MOVE_TO_TARGET. In lib/chat_helper_functions.php, MOVE_TO_TARGET is in stobeNonFactionMinorOrderCommands (15885-15887). stobePlayerOrderGate (15898) then: trust < 56 (MINOR_ORDER_TRUST_MIN defaults to 56, 15889-15891); stobeTravelOrderGate returns null with no ACCEPTED leg (lib/travel_companionship.php:374-377); the travel branch at 15921 lists only FOLLOW/MOVE_TO/TRAVEL_LOCATION, so MOVE_TO_TARGET falls to the generic `return "I haven't agreed to that job.";` at 15925. Then lib/travel_companionship.php:561 `$text=$why;` overwrites the NPC's whole line (called for every outsider turn from processor/chat.php:1967-1970; travelConsentTurn at processor/chat.php:1448).

EVIDENCE
- Identity, in game: stobe.log:225 (19:50:02) first reply `"Tango"? You address an emperor, peasant.` Server message: output_from_llm.log:326781 and :327307.
- Prompt: context_sent_to_llm.log:1917658 onward: "Basic Summary: United Cities emperor...", "## Occupation Emperor of the United Cities."
- DB (SELECT only, combined_bio_unique, search_path public): 5 rows where LOWER(name)='tengu' (personality, backstory, occupation, speechstyle, goals). 'Emperor Tengu' has 6+ rows with different text (data/import/kenshi_unique_bio_unique_upsert.sql:225-236); not matched by the lookup.
- Propagation: a memory_summary_generate call at 01:52:02 UTC stored "Met a Tengu, who identified as an emperor" (output_from_llm.log:326913).
- Job, server: stobeserver.log:2157754 (01:52:47 UTC) `actions":["MOVE_TO_TARGET@Shay"]` for request req_6ad031e617a02; :2157758 `Order rejected before speech`, reason "I haven't agreed to that job."; output_from_llm.log:327307 message `"Tango" again. ... I am walking, peasant, and you are in my way. Step aside.` with "action":"MoveToTarget" (:327309). The Step-aside line never reached the game.
- Job, game: stobe.log:865 (19:52:48) `NPC_SAY: Tengu: I haven't agreed to that job.` Earlier turn 19:50:02 had no action (stobeserver.log:2157120, actions_count 0).
- Job, DB eventlog: rowid 1032193 infoaction "REJECTED MOVE_TO_TARGET@Shay; not dispatched. I haven't agreed to that job."; 1032194 chat line (the spoken replacement); 1032198 Tengu later: "Then we agree on something. Stop inventing work for me..." (the rejection line became dialogue memory).

WHAT YOU RULED OUT
- A job/agreement/goal was started: none. No eventlog travel_agreement row mentions Tengu; stobe_work_goal and stobe_task_goal have no Tengu rows; stobe_goals.log, the goal .status files and the .tsv files do not mention Tengu; the move was REJECTED and not dispatched. The "job" exists only as the spoken/stored line.
- STT as the cause of the emperor reply: STT only explains the spelling. At 19:52:23 the transcript was "I said tengu." (stobe.log:746), and the NPC still replied "Better. Now say it with the respect it deserves" (stobe.log:786). That is the persona.
- Memory summary as origin: it was generated after the first emperor reply, so it propagates the error.
- The "Emperor Tengu" rows as source: the persona text is the 'Tengu' rows, not the 'Emperor Tengu' rows.
- Other sample-row collisions in this session: comparing the 202 enabled unique names with NPC names in this session's rosters, only Tengu hit among the sample rows. Horse and Jaegar also matched, but their rows read as real uniques.
- Game-side name: the roster name is "Tengu" (stobe.log:137), so no naming bug in the native code.

PROPOSED FIX
A. Identity
 A1 (data, small, do first; Shay decides delete vs disable): remove the five 'Tengu' rows. Either `DELETE FROM bio_unique WHERE LOWER(name)='tengu';` or `UPDATE bio_unique SET is_enabled=false WHERE LOWER(name)='tengu';`, and delete data/schema.sql lines 3404-3408 so a reinstall does not restore them. Back up first. See "not settled" for the protection side effect.
 A2 (class fix): stop matching unique personas by display name alone. The native already reads the template id (components/STOBE/src/ActivityPolicySupport.cpp:39 uses target->getGameData()->stringID). Send it in the people/profile payload, add an optional template_id column to bio_unique, and in getBioUniqueLookupKeys/loadBioUniqueTraitSelections (lib/data_functions.php:5397-5440) apply a unique persona only when the template id matches. Name-only rows then stop applying to generic NPCs.
 A3 (optional): roster-aware STT correction (for example "Tango" becomes "Tengu" when Tengu is in the nearby roster and "Tango" is not). No such correction exists (grepped components/STOBE/src and lib/).
B. Job line and lost speech
 B1 lib/chat_helper_functions.php:15921, add MOVE_TO_TARGET to the travel list:
   -    if (in_array($cmd, ['FOLLOW','MOVE_TO','TRAVEL_LOCATION'], true)) {
   +    if (in_array($cmd, ['FOLLOW','MOVE_TO','MOVE_TO_TARGET','TRAVEL_LOCATION'], true)) {
   The refusal becomes "Let's agree on where we're going and who is leading first." (or the trust line).
 B2 lib/travel_companionship.php:380, the same list change in stobeTravelOrderGate, so an accepted leg is judged the same way. Semantics open (see not settled).
 B3 lib/travel_companionship.php:561, keep the NPC's own line and drop only the order:
   -        $text=$why;
   +        // Drop the refused order; keep the NPC's own line. Speak the refusal only when there is no line.
   +        if (trim($text) === '') $text = $why;
 Scope: B3 affects every outsider order (FOLLOW, BODYGUARD, HOLD_POSITION, ...), not only MOVE_TO_TARGET.
 Note: in the live tree lib/travel_companionship.php is untracked (git status ??), and lib/chat_helper_functions.php and processor/chat.php are modified and uncommitted. Patch the live tree and ss-merge per CLAUDE.md (back up, php -l, deploy both, rotate logs), then commit.

HOW TO CONFIRM THE FIX WORKED
- Offline regression (new tests/travel_order_gate_regression.php, same bootstrap style as the negotiation regression): (a) stobePlayerOrderGate('Tengu', <npc trust 0>, 'MOVE_TO_TARGET@Shay') must not equal "I haven't agreed to that job."; (b) stobeTravelValidateOrders with text "Step aside." and actions ['MOVE_TO_TARGET@Shay'] must leave text "Step aside." and empty actions. Run before the fix (must fail, text becomes the refusal) and after (must pass). Then stobe-tests.
- Identity: `SELECT count(*) FROM combined_bio_unique WHERE LOWER(name)='tengu'` returns 0; new prompts for a 'Tengu' NPC contain no "Emperor of the United Cities" (grep context_sent_to_llm.log after the fix).
- Game replay of Shay's exact steps (repro rule): select Tengu (Spring, Anti-Slavers), say "What's up, Tengu?" then "You're not Emperor Tengu.", and check the replies (no emperor claim; no "I haven't agreed" line; eventlog has the REJECTED row with the NPC's own spoken line). Capture screenshots.

WHAT IS NOT SETTLED
1. What Shay actually said in turn 1: audio is not logged. STT gave "Tango" 4 times and "tengu" once.
2. A1 delete vs disable: loadServerProtectedUniqueNames (lib/data_functions.php:6100-6118) builds from every row, including disabled ones, and isServerRenameEligibleName (6137-6140) refuses protected names. Disabling keeps "Tengu" protected; deleting removes that. Shay should pick.
3. After a refused move, the NPC's line may still agree to walking. B3 keeps the line; a rewrite or a second pass is a design choice.
4. MoveToTarget@<person> ("walk with me") under a trust or accepted leg: refuse with the travel line, or treat as FOLLOW of that speaker. Design decision.
5. Whether the memory summary (output_from_llm.log:326913) was stored and is fed into later prompts. Not checked; it may need correcting.
6. Whether other sample rows (Beep, Esata the Stone Golem, Cat-Lon) collide with real NPC names. Not seen in this session only.
7. Line numbers are from the live tree as it stands now (uncommitted changes); they will move after edits.

DISCLOSURE
Read-only as asked: SELECT only, no POST, git log/status only, no pending-fixes or candidate folders read, no session-start, no HANDOFF.md. My own scratch commands wrote two files in WSL /tmp: /tmp/bio_names_stobe_check.txt and /tmp/roster_names_check.txt. I did not delete them because the rules forbid deletes; please remove them.
