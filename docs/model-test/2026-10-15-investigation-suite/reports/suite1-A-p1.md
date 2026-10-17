SUITE-A1 report: why the first Stobe reply to Tengu took about 113 s

Times are the game's local time (UTC-6). The server log is UTC, so add 6 h. Read-only: no files changed, no service restarted, no POST or LLM request, one SELECT on the stobe database.

SUMMARY
- The first reply was held in the game, not slow to generate. The game was paused from 19:49:57.6 to 19:51:30.1. Stobe does not run queued NPC speech while the game is paused, so Tengu's line (ready at 19:50:02.1) played only at 19:51:30.1. That is 88 of the 113 seconds.
- The other 25 s is normal first-turn latency: a cold speech-to-text call of 11.9 s, then about 13 s for LLM plus TTS. Later turns in the same session, with no pause, played 6-15 ms after their line arrived and took 10-13 s from end of speech.
- What paused the game is not in any log. The most likely trigger is the Space key (vanilla pause), because in first-person mode KenshiFP does not swallow Space while jump is off. Window focus change is the other candidate and is unverified. Three quick tests decide it (see HOW TO CONFIRM).
- The fix that removes the 88 s wait for any cause is in Stobe: do not hold NPC speech while paused (Fix 1). Separately, each chat reply costs 8-10 s of LLM time, mostly hidden reasoning (Fix 3).

ROOT CAUSE
1. Pause hold (main cause). Live file /root/STOBE-src/src/Functions.cpp, ExecuteQueuedActions (line 7055). When isPaused() is true (line 7086), the function returns at lines 7134-7144 before any queued action runs, NPC speech included. stobe.log logs "ACTION_QUEUE: paused; deferring queued actions" every 1.5 s from 19:50:02.150 (line 232) to 19:51:29.202 (line 298). The SAY ran at 19:51:30.064 (line 299).
2. The game really was paused (world-level, not a frozen process). KenshiFP.log line 212: 19:49:57.597 frameSpeedMult 1.00 -> 0.00. Line 213: 19:51:30.067 back to 1.00. Game time stopped: gamets 124104 at 19:49:59.103 (stobe.log line 216) and again at 19:51:19.120 (line 291). The harness fps counter kept climbing through the hold (harness.log 19:50:11.064 frames=7800; 19:51:05.034 frames=10800).
3. Most likely trigger: Space. Kenshi's controls.cfg line 45 is pause=Space. KenshiFP is meant to eat Space (jump) and use P for pause, but both are gated on jump: kenshifp_client.c line 7783 (kfp_keypress_eat eats the jump key only when g_cfg_jump && g_cfg_falling) and line 7912 (fp_jump_pause_guard returns at once when !g_cfg_jump, so the P toggle never runs). The shipped mods\KenshiFP\KenshiFP.ini has jump=0 (line 39) and falling=0 (line 30). fpc_key_bound_any (client/kfp_controls.inc, line 323) only matches configured FP keys, so Space reaches the vanilla pause. KenshiFP.log has no "[jump]" line in the whole session. FP mode was on (FP look lines at 19:49:21 and 19:49:34). The last walking key was released at 19:49:57.18, 0.4 s before the pause.
4. Alternatives: (a) The game window losing focus. By 19:50:03 the cursor was visible, which KenshiFP only does when the game is not foreground (see Evidence). That would explain the pause only if Kenshi pauses on focus loss, which I found no evidence for. (b) The enabled Vortex mod "Auto Pause On Load" (mods\Auto-Pause-on-Load\mod-config.json: pause_on_inventory_open true, pause_on_trade true). It explains the load pause at 19:48:34, but is less likely for 19:49:57 (see Evidence).
5. The rest of the first wait: server request 01:49:49-01:50:02 UTC, STT cold call 11,942 ms, pre-LLM 1,249 ms, time to first token 1,060 ms, LLM total 10,016 ms, TTS synthesis 1,451 ms, request total 12,840 ms.

EVIDENCE
- Timeline (game time): 19:49:36.07 push-to-talk start, 19:49:37.14 stop (stobe.log 142, 147). 19:49:49.12 STT upload complete (line 172; server stt_service_ms 11,942). 19:49:49.29 chat sent (lines 177-196). 19:50:02.147 first Tengu line streamed (line 223). 19:50:02.150 paused queue begins (line 232). 19:51:30.064 SAY (line 299).
- Turns 2-4 ran unpaused: line 382/391 (19:51:55.129 line, SAY 19:51:55.135); lines 449/459 (19:52:12.596, SAY 19:52:12.611); lines 785/794 (19:52:31.497, SAY 19:52:31.505). KenshiFP shows no pause between 19:51:30 and 19:53:04.
- Second held window: Mouse's reply ran at 19:57:19.887 with the game running. KenshiFP paused at 19:57:20.824. Jaegar's follow-up line arrived at 19:57:32.333 and was held until SAY at 19:58:33.845 (unpause at 19:58:33.848), 61 s. The pauses at 19:53:04.267 and 20:00:51.377 held nothing.
- Stobe UI pauses are logged on creation, and both match KenshiFP pauses: "UI: CreateChatUI done" 19:48:58.020 (pause 19:48:58.022) and "UI: starting window created" 19:49:01.736 (pause 19:49:01.738). The pauses at 19:49:57.6, 19:53:04.3, 19:57:20.8 and 20:00:51.4 have no Stobe UI line.
- Server, request req_6ad0313d4e3da (stobeserver.log, UTC): 01:49:49 "STT transcription completed" stt_service_ms 11942; 01:49:50 pre-llm 1249 ms; 01:49:51 llm_ttft_ms 1060; 01:50:00 llm_total_ms 10016; 01:50:02 TTS synthesized 1451 ms; "Request completed" duration_ms 12840.
- Same request, log/chat_llm_full_capture.log: prompt_tokens 12321, completion_tokens 257, cached_tokens 0. Request: reasoning {max_tokens: 300, exclude: true}, max_tokens 1950, strict json_schema with 22 required keys.
- Reasoning budget: connector/openaijson.php lines 130-139 (stobeReasoningPayload). The setting CHAT_REASONING_MAX_TOKENS is not in general_settings (SELECT checked), so the code default 300 applies.
- Streaming: of the last 160 structured replies in stobeserver.log, 134 had chunks_emitted=0, so the line was sent only after the whole reply was done. The decoder (lib/chat_helper_functions.php line 6065, stobeDecodeStructuredDialoguePayload) only parses a complete JSON object.
- Last 160 chat LLM turns: llm_total median 4,432 ms, p90 7,968 ms; time to first token median 852 ms.
- STT: 147 calls, median 53 ms. Slow ones are first calls after idle: 20,436 ms (10-12 19:27), 8,755 ms (10-12 19:41), 1,667 ms (10-13 03:14), 11,942 ms (10-15 01:49, after 45 h with no call). Parakeet's log.txt shows the model on CUDA, with no per-request timing.
- Input: harness.log shows no key or mouse injection and input isolation was never on. The harness keeps the render window active (19:47:51.598).
- Clicks: the last LMB release before 19:49:57.6 was 19:48:55.9 (KenshiFP "ms after LMB up" = 61,672). The LMB release at about 19:50:03.4 is derived from the 86,687 ms value on line 213 (not logged as an event). KenshiFP's cursor is hidden only when the game has focus and no UI is open (kenshifp_client.c ~line 4035). No "[ui]" change was logged after 19:49:43.7, and the "FP look ... kept from the GUI" line that every hidden-cursor press produces is absent for that press. So the game was not foreground at 19:50:03 (inference).

WHAT YOU RULED OUT
- STT as the main delay: only the first call was slow; the later calls in this session took 49-61 ms.
- A server error or timeout: the request completed with HTTP 200 in 12.8 s. The "Empty stream response" at 19:51:30.347 belongs to a follow-up for another NPC, after the line had played.
- Network or DeepInfra first-token time: 1.06 s, normal.
- Stobe's own chat or starting-window pauses in the 19:49:50-19:51:30 window: none logged.
- A player-TTS barrier or TTS hold: no "PLAYER_TTS barrier" lines and no TTS playback between 19:49:50 and 19:51:30.
- Harness-injected input or an Ogre background stop: neither applies (fps kept rising; the harness keeps the window active).
- The speech path itself: when unpaused, SAY ran 6-15 ms after its line.

PROPOSED FIX
Priority 1 (Stobe; removes the hold for any cause). Copy the live file /root/STOBE-src/src/Functions.cpp first. The repo snapshot components/STOBE/src/Functions.cpp is 29 lines offset.
Change 1: replace the early return at lines 7134-7144 so NPC lines may run while paused:

    // An NPC line is not held by a pause: a reply to the player shows at once.
    // Everything else still waits for the unpause, as before.
    const bool pausedNpcLineNext = gamePaused && !g_uiActionQueue.empty() &&
        g_uiActionQueue.front().type == ACT_SAY &&
        g_uiActionQueue.front().taskValue >= 0;
    if (gamePaused && !pausedNpcLineNext) {
      ... unchanged: the pausedQueueLogTick log, LeaveCriticalSection, return ...
    }

Change 2: in the while loop (line 7196), after pendingPlayerBubble (line 7209), stop at the first non-line action while paused:

      if (gamePaused && !(nextAction.type == ACT_SAY && nextAction.taskValue >= 0))
        break;  // paused: only NPC lines run; the rest wait for the unpause

Check first: the player's own bubble uses taskValue < 0 (line 7209). Grep the ACT_SAY pushes to confirm no non-speech ACT_SAY uses taskValue >= 0.
Build with tools/automation/build-stobe.ps1 and install with install-dll.ps1 Stobe (Kenshi closed). Expected: the bubble stays until unpause, and the voice may wait for it. Test both.

Priority 2 (KenshiFP; stops Space pausing in first person). Live file /root/KenshiFP/client/kenshifp_client.c:
- Line 7783: replace "if (g_cfg_jump && g_cfg_falling && g_fp_mode && !g_ui_open" with "if (g_fp_mode && !g_ui_open". Space is then eaten in FP whatever the jump setting. With jump off it does nothing.
- Line 7912: replace "if (!g_cfg_jump) { g_jump_fire_req = 0; return; }" with "if (!g_cfg_jump) g_jump_fire_req = 0;"
- Insert before "int jk = (GetAsyncKeyState(g_cfg_key_jump) & 0x8000) != 0;": "if (!g_cfg_jump) return;  /* the rest is the jump only */"
With the shipped ini: Space does nothing in FP, and P toggles pause (log "[jump] FP pause toggle -> paused"). Build through tools/automation/kfp-pipeline.sh (the workspace's KenshiFP build path), then install-dll.ps1 KenshiFP.
Stop-gap, untested: in Kenshi's Options > Controls, rebind Pause away from Space (controls.cfg line 45).

Priority 3 (chat latency, 8-10 s per reply; not the cause of the 88 s).
(a) Reasoning cap: add a CHAT_REASONING_MAX_TOKENS row to general_settings (check the table's key columns first), e.g. 100. The code reads it at connector/openaijson.php line 136. Alternative: turn hidden reasoning off for normal talk. processor/chat.php line 1424 sets $GLOBALS['STOBE_REASONING_OFF'] only for combat today, and that path already sends reasoning {enabled: false}. Test about 10 NPC turns for reply quality first.
(b) Stream the line early: keep the final json_decode as it is, but add a partial reader for the "message" string (the 3rd schema key) that works on the open stream buffer. Feed it to processStructuredSnapshot (lib/chat_helper_functions.php line ~15054) so complete sentences go out while the rest of the JSON is still generating.
(c) Trim the schema: 22 keys are required on every chat reply. Make the keys a talk turn never uses optional (travel_*, region_plan_decision, proposed_region, social_repair_updates, ...). The builder was not traced in this read-only pass.
(d) Prompt cache: cached_tokens is 0 of 12,321. Put the static system prompt first. Not traced.
Server changes follow the workspace rules: back up, stage, php -l, standalone test, deploy live and ss-merge, rotate logs, commit and push.
Estimate, not measured: (a) cuts the 10 s tail to roughly 3-5 s; (b) hides most of the rest.

Priority 4 (STT cold start, 12 s on the first call after idle). Keep Parakeet warm: POST a 0.5 s silent WAV to http://127.0.0.1:8022/v1/audio/transcriptions every 2 minutes while the game runs, or once at game load. Expected first-call time around 50 ms (estimate). Cause not proven; GPU residency after idle is the likely one.

Priority 5 (instrument the next pause). In fp_speed_watch (kenshifp_client.c, about line 8080), log game_has_focus() and the state of Space (0x20), P (0x50), Alt (0x12), Tab (0x09), Esc (0x1B) and I (0x49) whenever frameSpeedMult changes. In ExecuteQueuedActions, log GAME_PAUSED and GAME_RESUMED with the number of held actions.

HOW TO CONFIRM THE FIX WORKED
1. Trigger test (about 2 minutes, no build): in FP mode outside chat, press Space once. A "1.00 -> 0.00" line in KenshiFP.log within a second means Space is the trigger. Then alt-tab away and back: a speed line at the switch would mean focus-based pausing. Open and close the inventory: a speed line would point to the Auto-Pause mod.
2. After Fix 1: pause the game, then chat with an NPC. stobe.log should show "ACTION_EXEC: SAY [NPC]" within about 1 s of its "STREAM_LINE", and no "ACTION_QUEUE: paused" for it. Check whether the bubble shows while paused and whether the voice plays.
3. After Fix 2: Space in FP makes no speed line; P does, and logs "[jump] FP pause toggle".
4. After Fix 3: "Latency stage llm complete" llm_total_ms falls (today median 4.4 s, p90 8.0 s, first reply 10.0 s); completion_tokens in chat_llm_full_capture falls below 257; chunks_emitted is above 0 on structured replies.
5. After Fix 4: the first "STT transcription completed" after a launch shows stt_service_ms under 500.
6. End to end, with Shay's exact steps (fresh start save, select Tengu, push-to-talk, leave Space alone). Speech end to bubble today: 25 s for the first reply without a hold, 10-13 s for later replies, 113 s with the hold. Target after Fixes 1, 3 and 4: about 5-8 s (estimate).

WHAT IS NOT SETTLED
- The pause trigger: Space, focus change, or the Auto-Pause mod. The logs do not decide it. The trigger test above does, or Shay can say whether he pressed Space or alt-tabbed around 19:49:57 and 19:51:30.
- Whether the bubble and voice work while the game is paused (Fix 1 test).
- The latency figures for Priorities 3 and 4 are estimates. No LLM request was sent.
- The cause of the 11.9 s cold STT call is unproven.
- Source versus installed binaries: I read the live sources (/root/STOBE-src, /root/KenshiFP). The installed Stobe.dll (written 19:37:42 on 14 Oct) and the KenshiFP.dll (a Vortex link) were not hash-compared with them.
- Not investigated: KenshiFP.log shows a crash at 20:06:25 (access violation in RE_Kenshi.dll+0x381E9, called through OgreMain and USER32), about 1.5 minutes after this chat. It is a separate issue and worth a look.
- Scope: one stray background command (a hung cmd.exe directory listing) was started and then stopped. No files were changed.
