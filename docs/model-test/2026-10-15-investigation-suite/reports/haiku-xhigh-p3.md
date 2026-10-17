BENCH-haiku-xhigh-p3 report: why Mouse never names a place to lead you (read-only; no code, DB, service or file changes made)

SUMMARY
Mouse is not refusing to travel. On all 8 of her turns in your conversation the chat prompt listed zero observed places, so she could only say "I don't know this ground" or propose "Spring" / "West of Spring" / a blank destination, and the server rejected every one with "I need to find a practical place before promising to lead us there." The root cause is that the installed Stobe.dll contains no native local-travel code, so no NPC snapshot carries any destination candidates. That code exists in the workspace snapshot (commit d541519, 2026-10-14) but the DLL build compiles a stale source tree with a hard-coded file list that leaves it out. Fixing the build is required but not enough: candidates would still be stale after 5 minutes and only pushed on selection, and the server writes its own rejection text into Mouse's history, which is what keeps the loop going.

ROOT CAUSE
1. Build: C:\StobeBuild\build_portable.bat (run by C:\KenshiModding\tools\automation\build-stobe.ps1) compiles a hard-coded list of 43 files from \\wsl.localhost\...\root\STOBE-src\src. That tree is a clean checkout at commit dedc49d (2026-09-26) with no LocalTravel.cpp. The newer source C:\KenshiModding\components\STOBE\src has 13 .cpp files the build never compiles: LocalTravel, NativeAiAwareness, NativeTravelLifecycle, NpcReferralPeople, ProfilePortrait, BodyguardContractProbe, ActivityController, ActivityGoals, ActivityNativeExecutor, ActivityPolicySupport, ActivityRuntime, ActivityRuntimeBindings, ActivityTransport. Only the components copy writes "travel_destinations" (Context.cpp:3620). The DLL was built 19:37 game clock, about 6 h after commit d541519 (13:39 -0600), from the stale tree.
2. Server: with no candidate IDs and strict matching, every concrete destination is rejected, and the rejection replaces Mouse's real reply and is stored as her line, which the next prompt feeds back to her.

EVIDENCE
Times: server log is UTC (game clock is UTC-6). Conversation = 2026-10-15 01:58-02:01 UTC (game clock 19:58-20:01 on 2026-10-14). Log: C:\...\StobeServer log/stobeserver.log (WSL: /var/www/html/StobeServer/log/).
- 01:59:23 Shay asks her to lead him. LLM proposes "Spring" (chat_llm_full_capture.log req_6ad0337b904b8). Rejected 01:59:28 (stobeserver.log line 2159049).
- 01:59:36 Shay: "Why don't you pick a practical place then?" LLM proposes with blank destination (req_6ad03388720ac). Rejected 01:59:43 (line 2159164).
- 02:00:24 Shay: "pick a location, a landmark or a direction and lead me". LLM proposes "West of Spring" (req_6ad033b458190). Rejected (line 2159477). Her real reply ("Fine. We go west out of Spring...") was never spoken.
- 02:00:33 Shay: "find a practical place to lead me". LLM proposes "Spring" (req_6ad033c171a7a). Rejected 02:00:38 (line 2159585).
- 02:00:48 Shay: "Do you know any place that you could lead me to?" LLM proposes "Spring, Stobe's Gamble" (req_6ad033cb930e7). Rejected (line 2159697).
- Prompt contents: in all 8 Mouse requests from 01:57:10 on, "Observed local choices ...: []" is empty, and the destination sections are empty too ("Grounded named-place choices", "Ranked reachable source choices", "This NPC historical observations", "Conditional regional search suggestions" all []). "Recorded agreement" is null.
- Database (SELECT only): core_npc_master row for Mouse (id 85855, storage hand_2627441408) has no travel_destinations key. Across all 136 NPC rows, zero have travel_destinations, native_ai, travel_lifecycle or referral_people. location_zones has 7 rows only: Bantam Knoll, Clownsteady, Hummock, Ogdam, Spring, Stumble Inn, The Hub.
- Installed DLL: D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll, identical to C:\StobeBuild\out\Stobe.dll, SHA256 E64C6593..., 3,182,080 bytes, 2026-10-14 19:37:42. ASCII search finds 0 occurrences each of travel_destinations, path_confirmed, native_ai, referral_people, travel_lifecycle, and LOCAL_TRAVEL. inventory_live_sync is present.
- Build inputs: C:\StobeBuild\src has 95 files, no LocalTravel.cpp. /root/STOBE-src is clean at dedc49d; its Context.cpp is 152,745 bytes (2026-10-01). Snapshot Context.cpp is 158,120 bytes (2026-10-12) and calls Stobe::LocalTravel::CandidatesJson at line 3620. components\STOBE\Stobe.vcxproj and CMakeLists.txt do list the 13 files. Build-listed files Context.cpp, Functions.cpp (line 8029), Globals.cpp and main.cpp reference LocalTravel / NativeTravelLifecycle / NativeAiAwareness / NpcReferralPeople / ProfilePortrait / BodyguardContractProbe, so the snapshot cannot link against the current list either.
- Delivery path: chat turns go through stream.php inputtext (ChatBox.cpp:4892) with no native envelope. chat.php's $context (line 70) and the detailed_context_json section (line 381) only get data from the /chat POST, and SendChatToStobeServer (ChatBox.cpp:6401) has no callers in components\STOBE\src. The prompt's NPC facts come from the stored row (processor/chat.php:1459 uses getNpcData).
- The envelope reaches the server only via /context -> npc_snapshot.php on selection (main.cpp:14202, 8 s minimum interval at main.cpp:1634), on trader chat-open (main.cpp:16026), and some dialogue hooks. The frequent npc_snapshot POSTs in Apache are inventory syncs (main.cpp:4177, payload at main.cpp:4091 carries inventory and money only). stobe.log has zero CONTEXT_PUSH lines in this session.
- Server freshness: candidates older than 300 s are dropped (lib/travel_companionship.php:19).
- Server rejection logic (lib/travel_companionship.php): line 145 accepts only an exact candidate ID or exact label. Candidate labels are like "outside Spring on its west side" (LocalTravel.cpp line ~369 / 445), so "Spring" can never match. Line 147 rejects a blank destination. Line 150 rejects the current town (CACHE_CITY) in the visited-zone fallback. Lines 453-454 set the practical-place reason. Line 504 sets $text = $reason, replacing the reply; line 506 logs it.
- The rejection is stored as Mouse's own line in the same request (stobeserver.log 2159054-2159058, speaker Mouse). The next prompt includes it: "Mouse, speaking to Shay: I need to find a practical place before promising to lead us there." (req_6ad033cb930e7, system message 0). That is why she repeats it.
- destination_discovery.php:142 filters for kind 'known_place', which no native code emits (no matches in components\STOBE\src).
- Scope: 26 travel rejections in the current stobeserver.log (since 2026-10-12 21:37), across Laru, Mouse, Ambulin, Heads or Tails Dealer and Icthy. 12 use one of the two "find a place" texts.

WHAT YOU RULED OUT
- Model/provider: HTTP 200, first text in 0.6-5 s. Her proposals were sensible; the failure is the missing IDs.
- Affinity/fight/cleanup gates: the reason is the practical-place branch, so stobeTravelPolicyRefusal and the cleanup check passed.
- Playthrough receipts: not the first blocker. The field is absent from every row, so there is nothing to receipt. Not tested after a rebuild.
- Destination sightings: no destination_sighting rows for Mouse. Empty, but not the cause.
- TTS/speech: lines were produced and played.
- Freshness alone: not the first blocker (no rows at all) but will be the second.
- Not a cause of the failure: the server-side strip. The DLL never emits the key, so there is nothing for the server to strip.

PROPOSED FIX (ordered; each step is testable on its own)
Step 1 - make the DLL contain the travel code (required)
a. Pick the source of truth. components\STOBE\src is the newest (commit d541519). Copy its .cpp/.h into /root/STOBE-src/src after a diff -rq review and commit there (the build reads that tree), or point build-stobe.ps1 at the components folder. Record the choice in CLAUDE.md.
b. In C:\StobeBuild\build_portable.bat, append to the set SOURCES= line:
  ... StobeDrawnWeapon LocalTravel NativeAiAwareness NativeTravelLifecycle NpcReferralPeople ProfilePortrait BodyguardContractProbe
  Leave the Activity* files out unless the linker names them. Better long term: generate SOURCES from components\STOBE\Stobe.vcxproj's ClCompile list so the lists cannot drift.
c. Run tools\automation\build-stobe.ps1. Expect BUILD OK; link errors name any missing symbols.
d. Install with tools\automation\install-dll.ps1 Stobe with Kenshi closed.
Effect: snapshots start carrying travel_destinations, native_ai, referral_people and travel_lifecycle. native_ai and referral_people will also reach prompts, which is wider than travel alone.

Step 2 - candidates must be fresh every turn (required)
In C:\KenshiModding\components\STOBE\src\ChatBox.cpp, function SubmitChatTextForCurrentContext (lines 4125-4895), just before the PlaythroughSession::StartTask(... StreamChatResponseThread ...) call near line 4885, add (use the chat target variable this function already resolves; I did not read its exact name):
  // Native facts for this turn. Synchronous so the server stores them before the inputtext event.
  std::string turnContext = BuildNpcContextEnvelope(<chat target>, "npc");
  if (turnContext.size() > 1 && turnContext.front() == '{' && turnContext.back() == '}')
      PostToStobe(L"/context", turnContext);
Do not use AsyncPostToStobe (Comm.cpp:1523) here: it is fire-and-forget and can lose the race with the stream request. Measure the added latency; the candidate query runs up to 40 path checks, cached for 30 s unless the NPC moved more than 30 m (LocalTravel.cpp lines 234-236). If the full envelope is too heavy, add a travel-only variant. Inventory syncs keep the original observed_unix stamps (data_functions.php retains them), so the 300 s window still applies and the per-turn push is what keeps the data fresh.

Step 3 - stop the loop (server; needed for a sane fallback)
a. Do not store the rejection as the NPC's line. At lib/travel_companionship.php:504 keep the spoken text but record the rejection as a separate travel note (for example $GLOBALS['STOBE_TRAVEL_REJECTED']). Where the NPC line is stored after stobeStreamDialogueResponse (processor/chat.php around line 2064, the server write at stobeserver.log 2159054-2159058), store the original line or skip the chat row when the note is set. I did not read the exact storage call; verify with the Mouse row after a test.
b. In stobeTravelPrompt (lib/travel_companionship.php around line 349), add a rule for an empty list: "No observed destination points exist right now. Do not propose or accept a place. Say which direction or landmark you can see, and that you need to look first." Keep the non-empty rule.
c. Name matching: in stobeTravelResolvePlan (line 147), when the requested name equals the current town, return a clarifying reason ("Which way out of Spring?") instead of rejecting with the practical-place text. Auto-picking a side is a design choice for you.
d. destination_discovery.php:142: remove 'known_place' or have native code emit it. Currently a dead filter.

Step 4 - knowledge beyond 180 m (decision, not required for the fix)
LocalTravel sees only 180 m around the NPC (LocalTravel.cpp line 37: kLocalRange = 1800 units). Named towns beyond that come only from location_zones (7 rows). Options: (a) enumerate towns and gates from game world data (native RE, effort unknown); (b) seed a town table; (c) keep the honest "I don't know other towns" answer. Suggest shipping Steps 1-3 first, then choosing (a) or (b).

HOW TO CONFIRM THE FIX WORKED
1. Build: [regex]::Matches([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes('C:\StobeBuild\out\Stobe.dll')),'travel_destinations').Count. Currently 0; expect more than 0. Also path_confirmed > 0, and the build log lists LocalTravel.obj.
2. Install: installed DLL SHA256 equals the build output.
3. In game: stobe.log shows "CONTEXT_PUSH: sent" lines before each chat turn with that target.
4. DB (SELECT): select jsonb_array_length(metadata->'travel_destinations') from core_npc_master where name='Mouse'; more than 0, with observed_unix within 300 s of the turn.
5. Server capture for a travel turn: "Observed local choices" non-empty; travel_destination equals one of the IDs; no "Travel agreement rejected" line for that turn; the trip is recorded as PROPOSED/ACCEPTED.
6. Replay your exact words: she should name an observed point or say which direction she can see.
7. Offline: add a PHP check that calls stobeTravelResolvePlan with a candidate ID (expect a point) and with an empty list (expect false). The current tree fails the first case for label "Spring". Place it beside the existing regression checks (for example tests/negotiation_engine_regression.php).

WHAT IS NOT SETTLED
- Whether the 13-file link succeeds unchanged (no build was run).
- Whether PathConfirmed yields candidates at Spring (unknown until the DLL runs).
- Latency cost of the synchronous per-turn push.
- Which source tree is authoritative. This is inferred from timestamps and git; you should confirm.
- lib/travel_companionship.php and lib/destination_discovery.php are untracked in the live tree (no commit history). I read the running copies.
- Time zones: server log UTC, Apache -0500, game clock UTC-6 (inferred from matching lines).
- Source for named towns beyond 180 m (Step 4) is not identified.
- Nothing was run: no game launch, no DB writes, no restarts, no POSTs.

RULE COMPLIANCE
- I did not read any pending-fixes content. My first workspace-wide grep for "practical place" listed pending-fixes file names (names only). One grep run from the wrong directory printed four match lines from pending-fixes files; I did not use them.
- I created one scratch file, /tmp/cap1.txt in WSL, and deleted it.
- Only read-only git (status, log, ls-files), SELECT-only SQL, grep/read of logs and sources. I did not read testing\HANDOFF.md and did not run session-start.ps1.
