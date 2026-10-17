BENCH-haiku-low-p3 report (read-only; no files, services or DB rows changed)

## Summary
Mouse does not refuse because she is unwilling. The server rejects every "lead me" offer before she speaks, because the only destination the model can name ("Spring", her current city) is excluded, and the native side supplies no other destination for her. The rejection text ("I need to find a practical place before promising to lead us there.") is then spoken as her reply, which feeds the loop. The fix is to give the model the real destination choices, and to stop the loop.

## Root cause
In `lib/travel_companionship.php` (around line 450-454), when `stobeTravelResolvePlan()` returns false, the code sets `$reason = "I need to find a practical place before promising to lead us there."` and returns. `stobeTravelResolvePlan()` (line 134) can only succeed in two ways:
1. A native candidate from the NPC's metadata `travel_destinations` (`stobeTravelLocalCandidates`, line 8). It needs `actor_serial` match, `observed` true, `reachability` = `path_confirmed`, and `observed_unix` within the last 300 s (and at most 30 s in the future).
2. A named place from `location_zones` via `stobeResolveTravelLocationFromVisitedZones()` (lib/chat_helper_functions.php:2117). This is refused when the label equals `$GLOBALS['CACHE_CITY']`, which is "Spring" here.

Mouse's requests all resolved to "Spring" (log: `loc_zone":"Spring"`, `city":"Spring"`), so path 2 is refused by design, and path 1 produced nothing usable for her in the window. The model is never given the choices, so it cannot name a valid place. The loop is that the refusal line becomes Mouse's own chat line in the context (context_sent_to_llm.log lines 1930101-1930111), so the model keeps repeating it.

## Evidence
- stobeserver.log 2026-10-15 02:00:33: Shay: "Okay, can you please find a practical place to lead me? (talking to: Mouse)". Location Spring, Stobe's Gamble, loc_x 52843.8, loc_y 2530.99.
- stobeserver.log 02:00:38 and 02:00:48: `Travel agreement rejected before speech | {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place before promising to lead us there."}`. Same pattern repeats through the session.
- The log does not record the candidate payload for Mouse, so whether her native `travel_destinations` was empty at 02:00:33 is NOT settled (see below).
- Database `stobe.location_zones` has 7 rows: Ogdam, Stumble Inn, The Hub, Bantam Knoll, Spring, Hummock, Clownsteady. So named places exist, but the model is never told about them.
- Native producer: `components/STOBE/src/LocalTravel.cpp` `CandidatesJson()` (line 223) emits candidates only from anchors near the NPC: buildings within 250 units, town radius, guard posts, observed sources. Each is marked `path_confirmed` at line 186 without a live path test in that function. Context.cpp:3620 sends them as `travel_destinations`.

## What I ruled out
- Not a server outage: the chat events arrive and are parsed (rechat, inputtext, chat rows all present).
- Not the travel-policy refusal: the reason string is the candidate-resolution failure, not `stobeTravelPolicyRefusal()`.
- Not a duplicate-echo problem: "Skipped duplicate dialogue echo row" at 02:00:33 is a harmless dedupe of Shay's line.
- Not the `ACCEPT` path: this is the PROPOSE path failing at point resolution.

## Proposed fix (for you to apply)
1. **Show the model the choices.** In the prompt builder for travel (the code that writes the travel instructions into the LLM prompt; find it by grepping `stobeTravelLocalCandidates` and `travel_` in `lib/` and the prompt file), add the list of valid destinations: the `label` of each native candidate in `stobeTravelLocalCandidates($actor,$npc)`, plus every `location_zones.zone_name` other than `$GLOBALS['CACHE_CITY']` (use the same query as `stobeResolveTravelLocationFromVisitedZones`). Tell the model: "When asked to lead, pick one of these exact names; do not say you need to find a place."
2. **Break the loop.** In `lib/travel_companionship.php` around line 454, when `$reason` is the "practical place" message, do not return the same line each time. Instead, if a valid choice exists, pick the nearest one from the list (or the first `location_zones` entry that is not the current city) and call `stobeTravelResolvePlan` with its name. Only fall back to the refusal line when the list is empty.
3. **Keep the refusal out of her speech history.** The refusal text should not be written as a chat line from Mouse into the context. Log it only.

Diff sketch for step 2 (inside the `if (!$point)` branch):
```php
if (!$point) {
    $fallback = stobeTravelFirstAlternative($actor, $npc);  // new helper: candidate labels, then location_zones names != CACHE_CITY
    $point = $fallback ? stobeTravelResolvePlan($actor, $npc, $fallback['label'], $old) : false;
}
if (!$point) {
    $reason = "I need to find a practical place before promising to lead us there.";
}
```
(`stobeTravelFirstAlternative` is a new helper I have not written; the exact code is for you to author.)

## How to confirm the fix worked
- Offline: write a PHP check that calls `stobeTravelResolvePlan` with `requested=''` and `requested='Spring'` for a fixture NPC and asserts a non-false point. It should fail before the fix and pass after. Add it to `tests/` and run `stobe-tests`.
- Game: on a fixture copy, with Mouse near Spring, say "Can you lead me somewhere?" Expect a named destination (for example Stumble Inn) and no "practical place" line. Check `Travel agreement rejected` count is 0 in stobe.log and stobeserver.log for that request.

## What is not settled
- Whether Mouse's native `travel_destinations` was empty at 02:00:33 (the log does not show the candidate payload). If it was empty, step 1 is needed as well as the server change; if non-empty, the labels were filtered out and the filter must be checked.
- Whether the model's prompt actually includes travel destination names today (I did not read the prompt builder).
- Process note: an early grep inside `/root/STOBE-src` matched files under `pending-fixes\`; I did not open any of them, but the instruction was not to read that folder, so this is disclosed.
