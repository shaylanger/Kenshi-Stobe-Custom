BENCH-haiku-medium-p3 report (read-only; no files, services or DB rows changed; SELECT only)

## Summary
Mouse loops on "I need to find a practical place before promising to lead us there" because (1) her prompt never lists any place she can travel to, so the model only knows Spring, where she is standing, and (2) the server refuses any destination equal to the current city and answers with that one fixed sentence, which is then spoken and fed back into her history, so the model repeats it. The travel code can already travel to visited places by name (the 6 other explored zones are in the DB). The fix is to show her the real places and give a specific rejection that names the valid choices.

## Root cause
Two-part, both in the server:
- The chat prompt has no list of destinations. It says TravelLocation is "Travel to a previously visited location by name", and MoveTo says "Use a known visited location name", but no names are given. Her Knowledge section only describes Spring and Stobe's Gamble. Her own words in the prompt: "Spring's the only place I've got a read on".
- stobeTravelResolvePlan refuses the current city. A "Spring" request matches the visited zone Spring, but the function returns false when the label equals CACHE_CITY, which is Spring here. Any failed resolve gives the same fixed text, and that text is spoken and stored as her dialogue.

## Evidence
- Server log (times as logged by the server, which is 6 h ahead of local game-log time): 2026-10-15 02:00:24, 02:00:38, 02:00:48 and earlier at 01:59:28, 01:59:43: "Travel agreement rejected before speech" with reason "I need to find a practical place before promising to lead us there.", npc Mouse, speaker Shay (lines 2159477, 2159585, 2159697; 2159049, 2159164).
- LLM output for the rejected turns (output_from_llm.log ~327892 and ~328048): travel_destination "Spring" and "Spring, Stobe's Gamble", travel_decision PROPOSE. The reason text was queued as her speech (output_to_plugin.log lines 10062-10063, action ScriptQueue).
- The next prompt (context_sent_to_llm.log ~1930110) contains her own repeated line "Mouse, speaking to Shay: I need to find a practical place before promising to lead us there." in the history. The prompt's Knowledge section (lines 257-265 of the prompt) has entries only for Spring and Stobe's Gamble.
- DB stobe.location_zones (SELECT): 7 rows, all knowledge_only=false: Spring (current, last_seen 1792029875), The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady, Ogdam. Ogdam, Hummock and the others are reachable by name under the current code.
- lib/travel_companionship.php:134-152 (stobeTravelResolvePlan): returns false at line 150 when the place label equals $GLOBALS['CACHE_CITY'] (set in lib/data_functions.php:2420 from the geo zone; for this chat it is "Spring", per the GEO_DEBUG lines with city "Spring").
- lib/travel_companionship.php:454: the fixed reason; line 506: the "Travel agreement rejected before speech" log, then the reason is returned as speech.
- lib/chat_helper_functions.php:2117-2180: stobeResolveTravelLocationFromVisitedZones (name match on zone_name/city_name, knowledge_only excluded).
- Native candidate list: components/STOBE/src/LocalTravel.cpp:223-372 (CandidatesJson). Sent as "travel_destinations" in Context.cpp:3620 and the chat envelope (ChatBox.cpp:6437). The candidates need buildings, visible NPCs, town radius, PathConfirmed and at most 40 path queries. Inside a town these may all fail. The prompt contains no candidate list at all (0 matches for travel_destinations in context_sent_to_llm.log). The Mouse DB metadata (core_npc id 85855) has no travel_destinations key, but its sync is the lean dialogue inventory sync, so this is not proof the chat payload was empty.

## What you ruled out
- Not a LLM-only failure: the server rejects Spring because it is the current city (line 150), and the resolver works for the other visited names (the town_knowledge_regression test expects "explored town is travelable").
- Not a stale-cache or time-window issue for the visited path: the visited path does not use the 300 s observation window.
- Not a STOBE server outage: other lines in the same minute are processed normally.
- The native candidate list is not confirmed missing: its absence in the prompt and in the game log is consistent with it being empty, but nothing logs the count, so it is unproven.

## Proposed fix (for you to implement)
1. Prompt (lib/chat_helper_functions.php, the function that builds the "AVAILABLE ACTION" block near line 232 and the prompt's knowledge section): add a "Places you know" block. Build it from location_zones where metadata->>'knowledge_only' is distinct from 'true', excluding the current city (GLOBALS CACHE_CITY), ordered by last_seen_ts DESC, max 8. Each line: exact name, zone, rough direction/distance from the NPC if available. Add the native travel_destinations labels to the same block (only those with observed=true). Add one rule under Dialogue Contract: "When asked to lead somewhere, pick one exact name from Places you know; never name the place you are standing in."
2. Server rejection (lib/travel_companionship.php ~line 448-454): compute the reason from the cause instead of one fixed sentence:
   - requested equals the current city: "We're already in {CACHE_CITY}. Where else should we go?"
   - no match: "I don't know a place called {requested}. I know {list of the same names as the prompt}." (use the same list builder as item 1)
   Keep the reason out of the spoken history if possible (log it and send it as a system note), so the model does not copy it.
3. Resolver (lib/travel_companionship.php:150): keep the current-city exclusion (it is correct) but return the reason to the caller instead of silently returning false, so item 2 can use it. Example: have stobeTravelResolvePlan return ['__reason'=>'current_city'] or pass a reason by reference.
4. Optional, for diagnosis: in components/STOBE/src/LocalTravel.cpp CandidatesJson, log the candidate count per snapshot (one line, rate-limited), so the next test shows whether native candidates exist in towns.

Diff sketch for item 2 (server, lib/travel_companionship.php, replacing line 454):
    if ($reason === '') { $reason = stobeTravelNoPlaceReason($requestedDestination, $npc); }
with a new helper that returns the current-city sentence when the requested name equals CACHE_CITY, otherwise the "I don't know a place called ... I know: ..." sentence built from the item 1 list.

## How to confirm the fix worked
- Offline (WSL, server tree): a PHP regression that sets $GLOBALS['CACHE_CITY']='Spring' and calls stobeTravelResolvePlan('Mouse', $npc, 'Hummock', null): must return an array with label Hummock (currently it also does). Add: requested 'Spring' returns the current-city reason; a prompt-builder test asserts the Places block contains Hummock and not Spring.
- Confirm the test fails before the fix: the prompt-builder assertion fails on the current code (no Places block).
- In game (Mouse, Spring): "Mouse, lead me to Hummock" should give a travel offer (RESULT via stobeTravelWrite/ACCEPT), not the practical-place sentence. Check stobeserver.log for no "Travel agreement rejected" with reason "practical place" in the run window, and the prompt for the Places block.
- Replay Shay's exact sentences from this chat, in order, with Mouse in Spring.

## What is not settled
- Whether the native candidate list was empty for Mouse at 02:00: nothing logs it, and the DB snapshot does not carry travel_destinations. Item 4 settles it.
- Whether Hummock, Ogdam etc. are actually reachable on foot (distance, guards, the Stobe's Gamble landbats) is not checked; the server only checks the name and the zone coordinates.
- Shay's intent for "lead me somewhere": whether NPCs should pick unexplored places (the native candidate producer) or only explored ones (the visited list). This is a design decision for you, not a bug.
- I did not read pending-fixes/ or any candidate folder, as instructed.
