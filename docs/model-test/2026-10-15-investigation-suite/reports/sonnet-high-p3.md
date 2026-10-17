**Summary**

Mouse had nothing to pick, and the server then rejected every destination she did name. The reply "I need to find a practical place before promising to lead us there." is a hard-coded server string (`lib/travel_companionship.php:454`). It is not the model's own words. It replaced her real replies five times between 01:59:28 and 02:00:48 UTC on 2026-10-15.

There are two causes:

1. **The Stobe.dll installed in the game cannot send local destinations.** The prompt Mouse saw listed no candidate places at all.
2. **The server gives the model no list of known towns.** It also refuses "Spring" as a destination, because she is standing in Spring.

**Root cause**

The server accepts a destination from only two sources. The first is a native candidate ID (`stobeTravelLocalCandidates`, `travel_companionship.php:8-50`). The second is an exact name of a town the player has visited or discovered (`stobeResolveTravelLocationFromVisitedZones`, `lib/chat_helper_functions.php:2117`). Mouse had neither.

- **Candidates.** The game plugin produces them in `LocalTravel::CandidatesJson` (`components/STOBE/src/LocalTravel.cpp:223`). The call is at `Context.cpp:3620`. The installed `Stobe.dll` contains none of the strings `travel_destinations`, `LOCAL_TRAVEL`, `native_ai` or `referral_people`. It does contain `CHAT_SEND_STAGE`, so the check works. The server therefore never receives candidates.
- **Why that DLL lacks the code.** `tools/automation/build-stobe.ps1` builds from `/root/STOBE-src`. That tree is at commit `dedc49d` (2026-09-26) and has no `LocalTravel.cpp`. The repo copy `components/STOBE/src/LocalTravel.cpp` was added later, in `d541519`. The installed DLL has the same SHA256 as `C:\StobeBuild\out\Stobe.dll` (`e64c6593...`).
- **No known-town list in the prompt.** `stobeDestinationDiscoveryPrompt` (`lib/destination_discovery.php:135`) lists only native candidates and sighting memories. The prompt text says "or an exact known visited location" (`travel_companionship.php:345`), but no such list is supplied.
- **The current town is excluded.** The resolver (`travel_companionship.php:149-150`) rejects a visited town whose name equals `CACHE_CITY`. Mouse is in Spring, and Spring is the only place she says she knows. Her one concrete offer was dropped here.

**Evidence**

- **Chat sequence** (`log/stobeserver.log`): Shay's 8 messages to Mouse run from 01:57:10 to 02:00:43 UTC. The rejection line `Travel agreement rejected before speech | {"npc":"Mouse",... "reason":"I need to find a practical place before promising to lead us there."}` appears at 01:59:28, 01:59:43, 02:00:24, 02:00:38 and 02:00:48.
- **What the model proposed** (`log/output_from_llm.log`):
  - It proposed `travel_decision: PROPOSE` with `travel_destination: ""` at 01:59:28 (line ~327707). Its reason was "No confirmed local destination; propose a bounded walk out from Spring".
  - It proposed `"West of Spring"` at 02:00:24 (line ~327877).
  - It proposed `"Spring"` at 02:00:38, with the reason "Spring is the only place I have a read on".
- **What the model was shown** (`log/context_sent_to_llm.log`, lines 1930134-1930150, her last request): `Observed local choices ...: []`, `Grounded named-place choices ...: []`, `Ranked reachable source choices: []`, `This NPC historical observations: []`, `Conditional regional search suggestions: []`, and `Recorded agreement: null`.
- **Database:**
  - `core_npc_master` has 136 rows and none has a `travel_destinations` key. Mouse's metadata lacks it.
  - `location_zones` has only 7 rows, all towns: Spring (visited), Bantam Knoll (visited), The Hub, Stumble Inn, Hummock, Clownsteady and Ogdam (all discovered). All have `knowledge_only` false.
  - Bantam Knoll and the others would resolve if the model had named them. It was never told they exist.
- **Code path:** blank destination → `travel_companionship.php:147` returns false. "West of Spring" → no row, false at `:149`. "Spring" → `:150` returns false. Each case ends at `:453-455` with the generic reason, which is spoken as Mouse's line (`:504`) and written into history.
- **Installed DLL:** `D:\Steam\...\RE_Kenshi\mods\Stobe\Stobe.dll` was modified at 19:37 local on Oct 14.

**What you ruled out**

- **Willingness or affinity.** `stobeTravelPolicyRefusal` returns different messages and never fired. The log has no "Order rejected" or trust lines.
- **Model refusal.** The model proposed a trip every time.
- **Missing visited towns in the database.** They exist; the model was just never shown them.
- **A stored agreement blocking things.** Recorded agreement was `null`.
- **Stale candidates.** The 300-second age check (`:19`) never ran, because the list was empty from the start.

**Proposed fix**

Do this in order. Step 1 fixes the "pick a location" case, and step 2 helps whether or not step 1 works.

1. **Build and install a Stobe.dll that contains `LocalTravel`.**
   - The simplest route is to sync the sources into `/root/STOBE-src/src`. That means `LocalTravel.*`, `Context.cpp`, `Functions.cpp` and everything else from `components/STOBE/src` that `d541519` and later added. Add the new files to the build list too, since `build_portable.bat` and `/root/STOBE-src`'s `CMakeLists.txt` don't list `LocalTravel.cpp` or `NativeTravelLifecycle.cpp`. The alternative is to build `components/STOBE` directly with the CMake line in its `CLAUDE.md`, using the v100 toolset.
   - The working tree has uncommitted edits to `NativeTravelLifecycle.*`, `NativeTravelReceiptPolicy.h` and `PlaythroughSession.cpp`. Decide whether you want those in the build.
   - Once installed, the plugin sends up to 32 outdoor points within about 180 metres. They include "outside Spring on its west side", terrain compass points, gates and nearby buildings, each already path-checked. "West of Spring" then becomes a real selectable ID.

2. **Server: tell the model which towns it knows, in `lib/destination_discovery.php`.**
   - Add a helper (anywhere above `stobeDestinationDiscoveryPrompt`):

   ```php
   function stobeTravelKnownTowns(int $limit = 12): array {
       $db = $GLOBALS['db'] ?? null;
       if (!$db) return [];
       $current = mb_strtolower(trim(strval($GLOBALS['CACHE_CITY'] ?? '')));
       try {
           $rows = $db->fetchAll(
               "SELECT zone_name, city_name FROM location_zones
                WHERE metadata->>'knowledge_only' IS DISTINCT FROM 'true'
                ORDER BY (metadata->>'visited')='true' DESC, last_seen_ts DESC LIMIT 40");
       } catch (Throwable $e) { return []; }
       $out = [];
       foreach (is_array($rows) ? $rows : [] as $r) {
           $label = trim(strval($r['city_name'] ?? '')) ?: trim(strval($r['zone_name'] ?? ''));
           if ($label === '' || mb_strtolower($label) === $current || isset($out[mb_strtolower($label)])) continue;
           $out[mb_strtolower($label)] = $label;
           if (count($out) >= $limit) break;
       }
       return array_values($out);
   }
   ```

   - In `stobeDestinationDiscoveryPrompt`, change the final return so it appends one line:

   ```php
   .'Conditional regional search suggestions: '.json_encode($regional,JSON_UNESCAPED_UNICODE)."\n"
   .'Known towns you may lead to (use the exact name as travel_destination; these are far away, not a short walk): '
       .json_encode(stobeTravelKnownTowns(),JSON_UNESCAPED_UNICODE);
   ```

   - The existing resolver already turns an exact town name into a `visited_location` plan, and `stobeTravelPlanHash` accepts that source. No other validator needs changing. Both the live tree (`/var/www/html/StobeServer`) and `/root/stobe-work/ss-merge` need the edit, and PHP opcache takes about a minute to pick it up.
   - Decision for you: this deliberately gives NPCs global town knowledge. `destination_discovery.php` currently avoids that ("no global map knowledge"). If you want a narrower rule, filter to `visited` only or to towns near the NPC's region. The `location_zones` table has x and z but no region, so distance filtering needs the NPC's position.

3. **Server: replace the repeating line with a useful one, at `travel_companionship.php:453-455`.**

   ```php
   if (!$point) {
       $known = function_exists('stobeTravelKnownTowns') ? stobeTravelKnownTowns(5) : [];
       $reason = $known
           ? "I don't have a good spot in mind from here. I could lead you to " . implode(', ', array_slice($known,0,3)) . ", if you want to go that far."
           : "I need to find a practical place before promising to lead us there.";
   }
   ```

   This breaks the loop. The player now learns the real options, and the line goes into Mouse's history as something she can build on.

4. **Optional:** remove the current-town exclusion at `:150` only if you want "walk to the centre of the town I'm in". I would leave it; a lead-to-here trip is useless.

**How to confirm the fix worked**

- **DLL:** `grep -ac travel_destinations <installed Stobe.dll>` should return at least 1. It is 0 today.
- **Context:** after a chat with any NPC, run `select count(*) from core_npc_master where metadata::jsonb ? 'travel_destinations'`. It should be above 0, and the entry should have rows. In `log/context_sent_to_llm.log`, `Observed local choices (...):` should show a non-empty array.
- **Prompt:** the same log should end with the new `Known towns you may lead to:` line listing Bantam Knoll, The Hub and the others.
- **Behaviour:** run the same chat as before ("pick a location, a landmark or a direction and lead me"). `stobeserver.log` should show no `Travel agreement rejected before speech`. The `travel_agreement` row should have `status:'PROPOSED'` and a `destination_point` (`select substr(data,1,300) from eventlog where type='travel_agreement' order by rowid desc limit 1`). Replying "yes, lead the way" should write `ACCEPTED`.
- **Dispatch:** `TRAVEL_LOCATION@<name>` should be issued, and Mouse should visibly move.
- **Offline tests:** run `stobe-tests` before the next game run, as the project rules require.

**What is not settled**

- **Running build:** I did not confirm which DLL was running in the game, only the file on disk. Its modified time (19:37) is before the session, and no `LOCAL_TRAVEL` log lines exist. Please confirm with a fresh log after reinstalling.
- **Rejection with a good DLL:** the 5090 test receipt `testing/live-stobe-queue/KAH-CHAT-005-5090-20261014.receipt.md` ran with a different build (AEF84C0A...). It shows the same rejection even when the producer worked. The model offered a gate route and the resolver dropped it before speech. So a correct DLL may still hit a second, separate resolver or label-match problem. I did not investigate it, so test step 1 on its own.
- **Long trips:** I did not check how the game dispatches `TRAVEL_LOCATION` to a town about 95,000 units away (Spring to Bantam Knoll), or whether the 24-hour leg limit would cut it off.
- **Stale `stobe.log`:** the in-game `stobe.log` was last written at 20:06 local and cannot confirm the DLL path. The server logs are the primary evidence.
