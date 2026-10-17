## Summary
Mouse could not lead you anywhere because the server never gave her a destination she was allowed to pick. At every turn the "observed local choices" list in her prompt was empty. The prompt also contains no list of visited towns. The only place she knew was Spring, and the server rejects Spring because you were both standing in it. So each PROPOSE she made ("Spring", "Spring, Stobe's Gamble", "West of Spring", or an empty destination) failed in `stobeTravelResolvePlan`. Each time, the server replaced her line with the fixed refusal "I need to find a practical place before promising to lead us there." That is the loop you saw.

## Root cause
There are two causes, and they stack:
1. **The game side never sends local destinations.** The installed Stobe.dll comes from `/root/STOBE-src`, and that source tree has no `LocalTravel.cpp`. The code that produces `travel_destinations` (`Stobe::LocalTravel::CandidatesJson`, called from `Context.cpp`) exists only in the repo snapshot `components/STOBE/src`, and it never made it into a build. So `travel_destinations` is always empty on the server.
2. **The server's fallback is hidden from the model.** `stobeTravelResolvePlan` would accept an exact visited town name from `location_zones`. But the prompt only says "or an exact known visited location" and never lists any. The model therefore only knew the current town, which the resolver refuses on purpose (`CACHE_CITY` check, travel_companionship.php:150).

## Evidence
- **Server log `log/stobeserver.log` (WSL `/var/www/html/StobeServer`):**
  - `[2026-10-15 02:00:33]` Shay: "Okay, can you please find a practical place to lead me? (talking to: Mouse)"
  - `[2026-10-15 02:00:38]` and `[02:00:48]`: `Travel agreement rejected before speech | {"npc":"Mouse","speaker":"Shay","reason":"I need to find a practical place before promising to lead us there."}`
  - The same text was also emitted at `02:00:24`.
- **Mouse's replies in `log/output_from_llm.log`:**
  - Every attempt was `travel_decision: PROPOSE`, `travel_leader: npc`.
  - The `travel_destination` values were `"Spring"`, `""` (reason "No confirmed local destination"), `"West of Spring"`, `"Spring"` and `"Spring, Stobe's Gamble"`.
  - Her own reason text: "Spring is the only place I have a read on".
- **The prompt in `log/context_sent_to_llm.log` (Mouse's prompt, "Do you know any place that you could lead me to?"):**
  - `Observed local choices (...): []`
  - `Grounded named-place choices (...): []`, `Ranked reachable source choices: []`, `This NPC historical observations ...: []`
  - None of the visited zone names (The Hub, Hummock, Bantam Knoll, Clownsteady, Ogdam, Stumble Inn) appear anywhere in the prompt.
  - Affinity line: "Your affinity toward the actual speaker Shay is 0/100".
- **Rejection site, `lib/travel_companionship.php`:**
  - :447-454: `$point = stobeTravelResolvePlan(...)`, then `if (!$point) $reason = "I need to find a practical place..."`
  - :134-152 (`stobeTravelResolvePlan`): it tries native candidates first, then `stobeResolveTravelLocationFromVisitedZones($requested)`. It returns false when the label is not an exact match, or when it equals `$GLOBALS['CACHE_CITY']` (Spring).
  - :8-50 (`stobeTravelLocalCandidates`): reads `metadata['travel_destinations']` only. An empty value gives an empty list.
- **Database (SELECT only):**
  - `core_npc_master` row `Mouse` (public schema; storage_id `hand_2627441408`, updated `2026-10-15 04:08:40`, sync_reason `dialogue_npc`) has no `travel_destinations` key. It also has no `native_ai` or `travel_lifecycle` keys.
  - `location_zones` has 7 rows that are not knowledge-only: Spring, The Hub, Bantam Knoll, Stumble Inn, Hummock, Clownsteady, Ogdam. So a server fallback has real towns to offer.
- **Installed DLL:**
  - `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll` (Oct 14 20:37, sha256 prefix e64c65930e4a19f5) is identical to `C:\StobeBuild\out\Stobe.dll`.
  - It contains 0 occurrences of `travel_destinations`, `path_confirmed`, `referral_people` and `travel_lifecycle`. Older strings such as `horn_sliders`, `sync_reason` and `dialogue_npc` are present.
- **Native source:**
  - `/root/STOBE-src/src` has no `LocalTravel.*`, `NativeTravelLifecycle.*`, `NativeAiAwareness.*` or `NpcReferralPeople.*`, and `Context.cpp` there has 0 matches for `travel_destinations` or `LocalTravel`.
  - `tools/automation/build-stobe.ps1:7` builds from `\\wsl.localhost\DwemerAI4Skyrim3\root\STOBE-src\src`.
  - The producer is only in `C:\KenshiModding\components\STOBE\src\LocalTravel.cpp` (it writes `"reachability":"path_confirmed"` at :186), called from `components/STOBE/src/Context.cpp:3620`. It was committed in d541519.

## What you ruled out
- **Affinity or policy refusal:** affinity is 0, and `same_route` needs >= 0. `stobeTravelPolicyRefusal` would have produced a different message.
- **Missing earlier offer on ACCEPT:** every attempt was a PROPOSE, not an ACCEPT, so the "requires an existing concrete offer" path never ran.
- **Stale receipt or an inventory-sync wipe:** the key was never stored at all, and the DLL doesn't produce it.
- **No visited towns in the DB:** there are 7, and the resolver would accept their exact names.
- **The model ignoring instructions:** it followed them. It truthfully had no candidates and kept trying the only town it knew.

## Proposed fix
There are two independent parts. Part B is server-only and gives Mouse destinations today. Part A restores the intended local-point travel ("lead me west / to that ridge").

**Part B (server, smallest): list visited towns in the travel prompt.** File: `lib/travel_companionship.php`. Apply the change to both trees: live `/var/www/html/StobeServer` and `/root/stobe-work/ss-merge`.

1. Add a helper above `stobeTravelPrompt`:
```php
/** Executable fallback destinations: visited zones the resolver accepts by exact label. */
function stobeTravelVisitedChoices(): array {
    $db = $GLOBALS['db'] ?? null;
    if (!$db) return [];
    $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
    try {
        $rows = $db->fetchAll(
            "SELECT zone_name, city_name FROM location_zones
             WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
               AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
             ORDER BY last_seen_ts DESC, id DESC LIMIT 40");
    } catch (Throwable $e) { return []; }
    $out = [];
    foreach ($rows as $r) {
        $label = stobeSanitizeTravelLocationToken(strval($r['city_name'] ?: $r['zone_name']));
        if ($label === '' || strcasecmp($label, $here) === 0) continue;
        $resolved = stobeResolveTravelLocationFromVisitedZones($label);   // same check the capture uses
        if (!$resolved || strcasecmp($resolved['label'], $label) !== 0) continue;
        $out[mb_strtolower($label)] = $label;
        if (count($out) >= 12) break;
    }
    return array_values($out);
}
```
2. In `stobeTravelPrompt`, insert this line right after the `'Observed local choices ...'` line (around :348):
```php
        . 'Known visited towns (exact travel_destination values; your current town is excluded; these are places the world map knows, not proof you personally know the road): ' . json_encode(stobeTravelVisitedChoices(), JSON_UNESCAPED_UNICODE) . "\n"
        . 'You are currently in ' . trim(strval($GLOBALS['CACHE_CITY'] ?? 'an unknown place')) . "; it cannot be a travel destination. If the local list is empty and a visited town fits, PROPOSE it by its exact name; otherwise say plainly you have no route instead of repeating the offer.\n"
```
No change is needed in `stobeTravelResolvePlan`: it already accepts exact visited labels and marks them `source=visited_location`. `stobeTravelPlanHash` and `stobeTravelPlanPointForDispatch` already accept that source, so TravelLocation dispatch works with it.

3. Optional, to stop the canned-line loop: in `stobeTravelCapture` at :454, include the rejected label in the reason so the next turn sees why it failed:
```php
$reason = $requestedDestination === ''
    ? "I need to find a practical place before promising to lead us there."
    : "I can't lead us to '" . mb_substr($requestedDestination,0,60) . "' - I need a place I actually know the way to.";
```
4. Run `php -l lib/travel_companionship.php`. Then add a regression check in `tests/`, deploy both trees, run `stobe-rotate-logs`, wait about 1 minute for opcache, and commit and push.

Design caveat: travelling to a different town is arguably a `detour`. A detour needs affinity >= 20, and Mouse is at 0 toward you, so she would only accept it as her own route. Raise her affinity or accept that limitation.

**Part A (native): ship the LocalTravel producer.** Bring the snapshot-only files into `/root/STOBE-src/src`:
- `LocalTravel.cpp/.h`
- the `Context.cpp` hunk at :3620, plus its includes at :1-4
- the `LocalTravel::Reset()` calls in `main.cpp` (:15289, :15327)
- the `Functions.cpp` :8029 validation
- `NativeTravelLifecycle.*`, `NativeAiAwareness.*` and `NpcReferralPeople.*`, because `Context.cpp` calls them too

Also add them to `CMakeLists.txt` and `Stobe.vcxproj`. Then `build-stobe.ps1` and `install-dll.ps1 Stobe` (with Kenshi closed).

Warning: `/root/STOBE-src` has its own uncommitted edits (CMakeLists.txt, Stobe.vcxproj, mod/Stobe.ini, AiNpcInfoWindow.*). `components/STOBE` also carries a lot of other unshipped work (Activity*, ProfilePortrait, ...) and has uncommitted `NativeTravelLifecycle` edits. Do not wholesale copy. Port only the travel and context files with `diff -rq`, and confirm the build compiles.

## How to confirm the fix worked
- **Part B:**
  1. Talk to Mouse in Spring and ask her to lead you somewhere.
  2. In `context_sent_to_llm.log`, check that `Known visited towns` lists e.g. `["The Hub","Bantam Knoll",...]` without Spring.
  3. In `output_from_llm.log`, check for a PROPOSE with `travel_destination` set to one of those names.
  4. In `stobeserver.log`, check there is no new `Travel agreement rejected before speech` line for Mouse.
  5. After you say "lead the way", the stored travel state is ACCEPTED with `destination_point.source=visited_location`, and a TravelLocation action is dispatched.
  - Before the fix, the same exchange logs the rejection line and an empty prompt list.
- **Part A:**
  - `grep -c -a path_confirmed` on the installed Stobe.dll is greater than 0.
  - After a dialogue sync, `SELECT jsonb_array_length(metadata::jsonb->'travel_destinations') FROM core_npc_master WHERE name='Mouse'` is greater than 0.
  - The prompt's `Observed local choices` becomes non-empty.

## What is not settled
- Why the LocalTravel and related native work exists in `components/STOBE` (d541519) but not in the live `/root/STOBE-src`. It may have been lost when that tree was reset to upstream 1.3.1 (`dedc49d`), or it may have never been synced back. I did not read pending-fixes or candidate folders.
- Whether the visited-town fallback should count as `same_route` or `detour` for an NPC with affinity 0. This is a design choice.
- `location_zones` is global, not per NPC. The prompt line above therefore says it does not prove Mouse personally knows the road. Decide whether you want per-NPC knowledge instead.
- I did not check whether the native TravelLocation handler in the current DLL moves an NPC to a `visited_location` point end to end. It needs one in-game run.
