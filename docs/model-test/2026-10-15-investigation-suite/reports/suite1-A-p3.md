SUITE-A3 read-only investigation (kenshi-debugger, case investigate). No code, DB row, service or game state was changed.

## Summary
Mouse has no places to offer. Her chat prompt has an empty list of local destinations ("Observed local choices: []") on every turn from the prompt after the 2026-10-13 21:59 UTC bored event onward, including all three of your asks. The Stobe.dll you play with does not contain the native code that builds that list (LocalTravel.cpp). That code is in the workspace snapshot but never reached the build tree. Each time she names a place, the server has nothing to match, so it throws away her whole reply and speaks "I need to find a practical place before promising to lead us there." Bystanders then reply to that line, which is the loop you saw. Restoring the producer is a small change (Phase 1). Phase 2 makes the walk use the chosen place. Phase 3 is optional wording and feedback.

## Root cause
The Stobe.dll in use has no NPC travel-candidate producer (LocalTravel::CandidatesJson, which writes "travel_destinations" into each NPC context). So the server gets no candidate places for any NPC, and the LLM is handed an empty list to choose from. The producer worked earlier: 96 of the 121 prompt markers in context_sent_to_llm.log list real candidates, e.g. "higher ground to the east" with path evidence (line 1771860).

## Evidence
Times: stobe.log is local time (UTC-6). stobeserver.log is UTC (20:00:20 local = 02:00:20 UTC).

The chat as logged:
- 20:00:20 you: "Okay, well can you maybe just pick a location, a landmark or a direction and lead me?" (stobe.log:2289). Mouse: "I need to find a practical place before promising to lead us there." spoken 20:00:25.011 (stobe.log:2317).
- 20:00:33 you: "Okay, can you please find a practical place to lead me?" (stobe.log:2364). Same line spoken 20:00:38.786 (stobe.log:2394).
- 20:00:43 you: "Do you know any place that you could lead me to?" (stobe.log:2439). Same line spoken 20:00:48.980 (stobe.log:2465).
- Each canned line starts a bystander reply (RECHAT: Crankshaft 20:00:25.065, Othra 20:00:38.847 at line 2403, Double 20:00:48.988 at line 2474).

What the LLM returned and what the server did (stobeserver.log, UTC):
- req_6ad033b458190, 02:00:24: LLM actions "TRAVEL_LOCATION@West of Spring" (line 2159475). Rejected before speech (line 2159477).
- req_6ad033c171a7a, 02:00:38: LLM actions "MOVE_TO_TARGET@Shay". Rejected the same second.
- req_6ad033cb930e7, 02:00:48: LLM no actions (line 2159696). Rejected (line 2159697).
- The LLM proposals were PROPOSE "West of Spring", PROPOSE "Spring", PROPOSE "Spring, Stobe's Gamble" (output_from_llm.log, blocks near lines 327864, 327917, 328073). Mouse's own text ("I don't know this ground well enough to name a safe spot...") was never spoken.
- The rejection code replaces the reply: lib/travel_companionship.php:504 `$text = $reason;`. The same block drops movement actions (stobeNonFactionMinorOrderCommands(), lib/chat_helper_functions.php:15885, includes MOVE_TO_TARGET). No movement ran: the stobe.log window shows only ACTION_EXEC SAY lines.

The prompt Mouse received (context_sent_to_llm.log):
- Line 1929234: "Observed local choices (ID selection; path checked when observed, rechecked before movement): []". Lines 1929245-1929248: "Grounded named-place choices: []", "Ranked reachable source choices: []", "Conditional regional search suggestions: []". Line 1929247: "This NPC historical observations ...: []".
- Line 1930134 (the last of 121 markers): also []. The last 21 markers, from line 1773432 on, are all []. The last non-empty one is line 1771860.
- Timing of the switch: the block at 1771860 has the 2026-10-13 04:00:14 UTC event in its history, so it is later than that. The block at 1773432 has the 2026-10-13 21:59:33 UTC Pacifier Perran event in its history, so it is at or after that. The exact switch is not recoverable from the logs.

The DLL in use lacks the producer:
- D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll: 3,182,080 bytes, 2026-10-14 20:37. Same size and time as C:\StobeBuild\out\Stobe.dll. grep -c -a finds 0 for travel_destinations, path_confirmed, observed_unix, destination_sighting, reachability, anchor_name, guard_count, referral_people. Other strings are present (CHAT_TIMING 3, NPC_SAY 2), so it is a real build of this source family.
- The session that ran the 20:00 chats started at 19:47:51 (one STARTUP line in stobe.log) and loaded the DLL installed before then. That DLL is not on disk any more, but the empty prompts from 21:59 UTC onward cover this session, so it almost certainly lacked the producer too.

The build tree lacks the source:
- /root/STOBE-src/src has no LocalTravel.*. No commit in that repo has ever had it (git log --all). build-stobe.ps1 copies only from that folder (lines 7-16).
- C:\StobeBuild\build_portable.bat compiles only the 44 names in `set SOURCES=` (line 21). None of the new .cpp files is in it. The file was last changed 2026-10-06 22:30. C:\StobeBuild\src has no travel file.
- The workspace snapshot components/STOBE/src has LocalTravel.h/.cpp (first and only commit d541519, 2026-10-14 13:39 -0600). Context.cpp:3620 writes travel_destinations. components/STOBE/Stobe.vcxproj:120 lists it. Compared with root: 32 files exist only in the workspace (13 .cpp: ActivityController, ActivityGoals, ActivityNativeExecutor, ActivityPolicySupport, ActivityRuntime, ActivityRuntimeBindings, ActivityTransport, BodyguardContractProbe, LocalTravel, NativeAiAwareness, NativeTravelLifecycle, NpcReferralPeople, ProfilePortrait), and 12 differ (AiNpcInfoWindow.cpp, ChatBox.cpp/.h, Context.cpp, Functions.cpp/.h, Globals.cpp/.h, KenshiBuildingCompat.h, PlaythroughSession.cpp, StobeHarnessBridge.cpp, main.cpp).

Server has nothing to forward (SELECT only):
- core_npc: 136 rows, none with a metadata key travel_destinations (Mouse's row has none).
- eventlog: 0 rows of type destination_sighting, 0 of type travel_agreement.
- location_zones: 7 rows (Bantam Knoll, Clownsteady, Hummock, Ogdam, Spring, Stumble Inn, The Hub).

Live server rules that produce the refusal (lib/travel_companionship.php):
- :19 freshness window (300 s). :147 an empty destination returns no point. :148-150 a named place must match a location_zones row, and the current town is refused (CACHE_CITY, set at lib/data_functions.php:2420).
- :345 and :349: the prompt says to pick a candidate or "an exact known visited location", and to be honest when none fits. The candidate list is empty and the zone names are not shown to the model.
- :433 the policy check runs first and passes. :453-454 the generic reason when no point resolves.

## What you ruled out
- Affinity, trust or an active fight: stobeTravelPolicyRefusal runs before the place check (:433) and passed. The refusal came from :454.
- The LLM ignoring a usable list: there was no list. "West of Spring" and "Spring" are not candidates, and the prompt tells it to be honest when nothing fits. It did what the prompt said for the input it got.
- "Spring is excluded" as the cause: that is a rule (:150), but "West of Spring" was refused too.
- The 300 s freshness window (:19): right in principle, but no rows ever arrive. Re-check it when Phase 1 is tested.
- Receipts and carry-forward (lib/data_functions.php:11102-11105, 11145-11170) and metadata normalising (normalizeCoreNpcMetadata, lib/data_functions.php:14159, does not strip the key): fine, they only carry rows that arrived.
- Movement executing: none in the window.
- location_zones (7 rows): a limit of the fallback, not the cause.
- TTS, timing, memory: not involved.

## Proposed fix

Phase 1: restore the candidate list (the smallest change that removes the cause).
1. Copy components\STOBE\src\LocalTravel.h and LocalTravel.cpp into /root/STOBE-src/src/. They are new files, so nothing is overwritten. Their includes (Globals.h, Utils.h, KenshiTownIdentity.h, KenshiBuildingCompat.h, kenshi/*.h) exist in the root tree and the standard build's SDK (C:\StobeBuild\sdk\Include). The Lock guard is defined in the file itself (line 84). The compiler will confirm this.
2. Patch /root/STOBE-src/src/Context.cpp by anchor, not by copying the file:
```diff
--- a/src/Context.cpp
+++ b/src/Context.cpp
 #include "Context.h"
+#include "LocalTravel.h"
 #include "Functions.h"
 ...
   json += "\"handle\": \"" + ToString((int)npc->getHandle().serial) + "\",";
+  json += "\"travel_destinations\":" + Stobe::LocalTravel::CandidatesJson(world, npc) + ",";
```
The `handle` line is root Context.cpp:3615, inside BuildNpcContextEnvelope (line 3588). `world` is in scope there (the function checks `!world`).
3. Append the token `LocalTravel` to the end of the `set SOURCES=` line in C:\StobeBuild\build_portable.bat (line 21).
4. Add a guard to tools\automation\build-stobe.ps1 after the build (near line 24) so a DLL without the producer fails the build:
```powershell
if (-not (Select-String -Path 'C:\StobeBuild\out\Stobe.dll' -Pattern 'travel_destinations' -SimpleMatch -Quiet)) {
  'ERROR: Stobe.dll has no travel producer (check SOURCES in build_portable.bat)'; exit 1 }
```
Run it on the current DLL first; it must exit 1 now.
5. Run build-stobe.ps1. Close Kenshi, run install-dll.ps1 Stobe, relaunch. If the compile fails on anything other than a missing helper from LocalTravel.*, stop and report.

Phase 2: make the walk use the chosen place (needed for "lead me" to actually walk to a candidate).
- The root TRAVEL_LOCATION branch (Functions.cpp:7984) predates candidate-point checks. The workspace version routes it through NativeTravelLifecycle::DispatchWire (Functions.cpp:7937) and LocalTravel::Validate (:8029), which check the candidate point and plan hash. Whether the root branch works for a candidate label is unverified.
- Bring NativeTravelLifecycle.h/.cpp and NativeTravelReceiptPolicy.h. Then take only the travel hunks from the workspace versions of Functions.cpp (7937, 8029), Globals.cpp (ControllerChanged calls, 352-410), main.cpp (Reset and Tick, 15289-15328 and 15741) and Context.cpp (ObserveIdle and travel_lifecycle, 3623-3624), one hunk at a time. Do not copy whole files: 12 differ and root has its own uncommitted edits.
- Test Phase 1 before Phase 2 (below). If Phase 1 already walks her, Phase 2 may be unnecessary.

Phase 3: server wording and feedback (small PHP edits, lib/travel_companionship.php):
a. In stobeTravelPrompt, just before the "Observed local choices" line (:349), add: "You are in <CACHE_CITY>; that place is not a travel destination. Choose a candidate ID outside it, or say you don't know a route yet."
b. Replace the generic reason at :453-454:
```php
if (!$point) {
    $here = trim(strval($GLOBALS['CACHE_CITY'] ?? ''));
    $reason = $requestedDestination === ''
        ? "I don't have a confirmed place to lead you to yet."
        : (($here !== '' && stripos($requestedDestination, $here) === 0)
            ? "That's where we already are. Name somewhere outside it."
            : "I can't confirm a path to that place from here.");
}
```
c. Add tests/travel_candidates_regression.php. Pull the row filter from stobeTravelLocalCandidates (:8-52) into a pure helper that takes rows, serial and now, then test fresh path_confirmed rows (kept) and stale or non-path_confirmed rows (dropped). Commit lib/travel_companionship.php and lib/destination_discovery.php (both untracked now).
d. Optional: do not start the bystander follow-up after a refused travel line. The RECHAT dispatch is native and I did not locate it.

Design decision for you (not a bug): whether an NPC may name towns beyond her local view. The code says "no global map knowledge" (lib/destination_discovery.php, stobeDestinationKnownRegions). location_zones has 7 rows. destination_discovery.php:142 filters on a 'known_place' kind that no producer emits. Phase 1 starts the sightings that a town memory would need.

## How to confirm the fix worked
Each check fails now and passes after the fix.
1. Build: `grep -c -a travel_destinations "D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll"` is 0 now and must be 1 or more. Same for path_confirmed.
2. Prompt, after one chat with Mouse near Spring: `grep -n "Observed local choices" /var/www/html/StobeServer/log/context_sent_to_llm.log | tail -n 1 | cut -c1-300`. It ends with [] now. It must start with [{"id":"local:...
3. Latency: compare the "Latency pre-llm stage" lines in stobeserver.log before and after. The candidate query adds per-event work (native cache 30 s, up to 40 path checks) and the prompt grows by up to 32 entries.
4. In game, replay your exact steps (same keys, selection and order): at Spring, select Mouse, say "Okay, can you please find a practical place to lead me?". Expect a named candidate place instead of the canned line. Then say "Yes, lead the way". Expect ACCEPT, "ACTION_EXEC: TRAVEL_LOCATION" in stobe.log, a travel_agreement row (count is 0 now), and Mouse walking there. Keep screenshots of each state.
5. Offline after Phase 3: the new regression passes, and stobe-tests passes.

## What is not settled
1. Which install dropped the producer. The window is 2026-10-13 04:00:14 UTC to at or after 21:59:33 UTC. There is no DLL install history, so the install cannot be named. LocalTravel.cpp was first committed 2026-10-14 13:39 local, so the producer ran from an uncommitted tree before that.
2. Whether the workspace travel files compile in the standard v100 build. The only build I could confirm with the producer strings is a CMake probe, components\STOBE\build-bodyguard-probe\Stobe-bodyguard-probe.dll (2026-10-13 13:56), not the standard path. Phase 1 has to prove it.
3. Whether Phase 1 alone makes her walk (see Phase 2).
4. Whether the list is useful at Spring. Navmesh and path checks run natively, and I could not run them.
5. Root repo state: /root/STOBE-src is on branch local/event-priority-debounce (HEAD dedc49d, 2026-09-26) with uncommitted edits (CMakeLists.txt, Stobe.vcxproj, mod/Stobe.ini, src/AiNpcInfoWindow.cpp/.h, others). Copying whole files would overwrite them. Decide which tree is the build truth.
6. Server: lib/travel_companionship.php and lib/destination_discovery.php are untracked, so the live server runs uncommitted code.
7. The bystander RECHAT after a refused line: not located.

## Scope and tooling notes
- A `find` over /mnt/c/KenshiModding for Stobe*.dll listed DLLs under pending-fixes\ and counted a string in them. That broke the "do not read pending-fixes\" rule. I did not open or use those results, and nothing was copied or changed. Reporting it so the coordinator can judge.
- Besides git log and status, I ran read-only git subcommands (ls-files, branch, reflog, stash list, rev-parse, log --all). No state changed.
- DB: SELECT and \d only. Logs and code: read only. No file written, no service or game touched.
