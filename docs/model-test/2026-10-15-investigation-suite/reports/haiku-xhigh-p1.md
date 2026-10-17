BENCH-haiku-xhigh-p1 report (read-only; no files changed, no POSTs, DB only read via information_schema). Times: Stobe.log, KenshiFP.log and the Windows clock are local CST (UTC-6); the StobeServer log is UTC (+6 h); the Parakeet log uses WSL clock (CDT).

## Summary
The reply from Tengu to "What's up, Tango?" (save "Fresh start", 2026-10-14) took about 113 s from the end of Shay's speech (19:49:37) to Tengu's bubble and voice (19:51:30). Three delays add up:
1. About 88 s (19:50:02 to 19:51:30): the reply was ready at 19:50:02 but the game was paused (game speed 0) from 19:49:57.6 to 19:51:30.1. Stobe holds all queued NPC speech while the game is paused and shows nothing. The source of that pause is not in any log (see "Not settled").
2. About 12 s: speech-to-text. The first transcription after the Parakeet server process starts takes about 11-12 s (CUDA/cuDNN warm-up). Later calls take 0.05-0.1 s. Nothing warms the model at startup.
3. About 13 s: the reply itself. The LLM wrote 257 output tokens (most are empty schema fields added by four feature add-ons), taking 10.0 s, then TTS took 1.45 s after the LLM finished.
Without the pause, speech-to-reply-line is about 25 s. Fixes 1-3 below should bring it to about 7 s (estimate) and make a held reply visible.

## Root cause
A. Held reply (largest visible wait, conditional on the pause source): ExecuteQueuedActions returns early while thisptr->isPaused() is true, before any queued action runs (C:\KenshiModding\components\STOBE\src\Functions.cpp:7111-7173; the SAY executes at :7348). The reply's ACT_SAY was queued at 19:50:02.150 (main.cpp:12858 "Queuing SAY"), and the pause gate logged "ACTION_QUEUE: paused" from then until 19:51:29.202.
B. Parakeet cold start: the first POST /v1/audio/transcriptions in a Parakeet process takes 11.3 s; later calls 0.04-0.1 s. /home/dwemer/parakeet-api-server/server.py lifespan (lines 59-69) has no warm-up; start_native.sh only calls GET /health.
C. Verbose reply and serial TTS: the reply is produced as one structured JSON (json_schema). The server emits nothing until the whole JSON is done (chunks_emitted 0), then runs TTS (not overlapped). Schema add-ons add many fields to every reply: social_followups.php:73-77 (followup_update), npc_preferences.php:142 (preference_updates), region_plan.php:84-91 (region_plan_decision, proposed_region), travel_companionship.php:357-359 (travel_*). These are under /var/www/html/StobeServer/lib/.

## Evidence
Timeline (local):
- 19:48:58.02 chat box opened (stobe.log line 67, CreateChatUI).
- 19:49:01.74 and 19:49:03.63: STOBE starting window open and close ("=" key, stobe.log 71-74). KenshiFP.log 136-137 shows the game speed 1->0 and 0->1 at the same instants, so KenshiFP's [speed] log tracks Stobe's userPause calls.
- 19:49:36.07-19:49:37.15: push-to-talk recording, 1.08 s (stobe.log 142-153).
- 19:49:37.17: STT upload received by server (stobeserver.log 2156965); STT completed at 19:49:49.12 with stt_service_ms=11942 (2156999).
- 19:49:49.28: send. The send path calls CloseChatUI() (ChatBox.cpp:4741), so the chat box closes on every send. The player bubble executed at 19:49:49.294 (stobe.log 199-200), which proves the game was NOT paused then.
- 19:49:57.18: last movement key released (KenshiFP.log 207 "gait hold end"). 19:49:57.60: speed 1->0 (KenshiFP.log 212). No Stobe log line in this window.
- 19:50:02.15: reply line received (stobe.log 223, STREAM_LINE); queued as ACT_SAY (230); "ACTION_QUEUE: paused" logs every 1.5 s (232-298).
- 19:51:29.20: last paused log. 19:51:30.064: ACT_SAY executes, bubble and TTS start (stobe.log 299-303). KenshiFP 0->1 at 19:51:30.067 (KenshiFP.log 213).
- 19:51:35.29: movement resumes (KenshiFP.log 215).
Server request for the reply (req_6ad0313d4e3da, stobeserver.log): ingress 2157002; pre-LLM 1,249 ms (2157054); TTFT 1,060 ms (2157065); LLM complete 10,016 ms, llm_after_first_text 8,956 ms (2157119); TTS synth 1,451 ms (2157133); request 12,840 ms (2157137). output_from_llm.log block 2026-10-15T01:50:00: prompt_tokens 12321, cached_tokens 0, completion_tokens 257, reasoning_tokens 0. The response JSON carries about 40 keys, most of them empty travel_*, region_plan_*, preference_updates and followup_update fields.
Parakeet (/home/dwemer/parakeet-api-server/log.txt): process started 16:55 WSL clock (PID 444); line 92 "NeMo model loaded"; line 106 first transcription "11.32s/it"; subsequent "10-25 it/s". Slow first calls also logged on 2026-10-12 19:27 (20.4 s), 2026-10-12 19:41 (8.8 s) and 2026-10-13 03:14 (1.7 s).

## What you ruled out
- Client to server transport: the server request took 12,840 ms and the client saw the line 12.86 s after dispatch. Nothing is lost in transit.
- Server pre-LLM and database: 1.25 s, fine. The PostgreSQL "connection refused" lines in service.log are from 2026-10-13 21:07, not this run.
- LLM provider latency: TTFT 1.06 s is within the normal range of recent calls (549-1,089 ms). The cost is output length.
- TTS: 1.45 s, not the cause.
- Stobe speech-delay gate (g_nextSpeechActionTick) and the TTS hold: not reached; the pause gate returns first.
- Rechat follow-up by Polik (19:51:30.15): it happens after the line plays.
- Client-side STT: upload started 0.03 s after recording stopped.
- NETWORK_ERROR 12002 at 19:49:28.100 (stobe.log 120): the only one in the log, before the chat, not on this path.
- Harness speed hold: no speed command in the window (harness.log has only fps lines).
- Stobe-initiated pause in the window: all Stobe userPause(true) calls log on open (CreateChatUI, CreateStartingUI). The only silent open is the rename window, which opens only from a button click. None in the window. Stobe's releases are silent but can only unpause.

## Proposed fix (apply later; each is independent)
Fix 1, Parakeet warm-up (main cause of the 12 s). File: /home/dwemer/parakeet-api-server/server.py, function lifespan (lines 59-69), before "yield":
```diff
     if stt_model is None:
         print("ERROR: Model not initialized. This should not happen.")
         sys.exit(1)
+    # First real transcription in a process pays ~11 s of CUDA/cuDNN init. Pay it at startup.
+    try:
+        stt_model.transcribe(np.zeros(config.DEFAULT_SAMPLE_RATE, dtype=np.float32))
+        print("STT warm-up done")
+    except Exception as e:
+        print(f"STT warm-up failed (continuing): {e}")
     yield  # Server is running
```
np and config are already imported in server.py (used by transcribe()). Restart the STT service after the change (wsl-voice.sh stt stop, then start). The warm-up runs before the server accepts requests, so the health check waits for it. Note: this needs to be re-run after each Parakeet restart, which the warm-up in lifespan covers.

Fix 2, slim the reply schema for talk turns (main cause of the 10 s). Files: /var/www/html/StobeServer/lib/social_followups.php:73-77, lib/npc_preferences.php:142, lib/region_plan.php:84-91, lib/travel_companionship.php:357 (stobeTravelResponseFormat). Add each of these four add-on schema fields only when that feature has open state for the NPC (a pending travel agreement, a region plan in progress, a due follow-up, a preference update possible), not on every reply. Keep the existing `??` defaults so the parser tolerates the missing keys (confirm in the Stobe client parser before deploying). Expected: completion_tokens 257 to about 60-90; llm_total_ms 10,000 to about 3,000-4,000 (estimate from the measured ~28 tokens/s). Deploy both trees (live and ss-merge) per CLAUDE.md, run `stobe-tests`, then one in-game talk.
Optional, same area: start TTS on the "message" field as soon as it is parsed instead of after the full JSON (saves about 1.5 s; larger change).

Fix 3, pause visibility and logging (client). File: C:\KenshiModding\components\STOBE\src\Functions.cpp, ExecuteQueuedActions, right after the gamePaused computation (around line 7118):
- Add a diagnostic: a static bool that logs "PAUSE_STATE: paused=<0|1> queued_actions=<n> space_down=<0|1>" on each transition. Today the pause cause is not logged at all.
- Add feedback: when paused and the queue front is ACT_SAY, show one notice "[STOBE] A reply is waiting: the game is paused." Set a local flag inside the g_uiMutex section and call thisptr->showPlayerAMessage_withLog(..., true) AFTER LeaveCriticalSection. Do not call the game UI while holding g_uiMutex. Reset the static flag when not paused.
Keep the hold itself (a paused game should not talk); the product choice (hold versus play while paused) is Shay's. Chat is closed on send (ChatBox.cpp:4741), so today nothing on screen says a reply is waiting.

## How to confirm the fix worked
- Fix 1: stop and start the STT service, then POST a 1-second WAV twice to 127.0.0.1:8022/v1/audio/transcriptions. Before: first call about 11 s. After: first call under 0.3 s, and log.txt shows no 11 s line.
- Fix 2: for the next talk turn, stobeserver.log "Latency stage llm complete" llm_total_ms about 3-4 s (was 10,016), and output_from_llm.log completion_tokens about 60-90 (was 257). The NPC line must still arrive (stobe.log STREAM_LINE) and ACTION_EXEC SAY must fire. `stobe-tests` must pass.
- Fix 3: in game, send a message, press pause, wait; the notice appears; unpause; the bubble plays. stobe.log shows PAUSE_STATE paused=1 then paused=0 with space_down set accordingly.
- End to end: time from releasing push-to-talk to the NPC line in stobe.log should be about 7 s with the game running (was about 25 s).

## What is not settled
- The pause from 19:49:57.6 to 19:51:30.1 is not explained by any log. Candidates: (a) Shay's own pause key (Space) or Kenshi's pause, which fits the pattern (movement keys released at 19:49:57.18, pause 0.4 s later, resume 19:51:30, walking again 19:51:35); (b) a Kenshi-native auto-pause on an in-game event (the harness comment says the game pauses on some in-game messages); (c) an unlogged Stobe path (none found). Shay should say whether he pressed a pause key near 19:49:57 and 19:51:30. Fix 3 would log it next time.
- Whether the reply text was visible on screen during the hold. The code says the chat box closes on send; no screenshot was checked.
- Whether the other slow first STT calls (2026-10-12 19:27, 19:41; 10-13 03:14) were all first calls after a process start. Only the 10-15 call was checked against the process start time.
- The LLM speed-up figure is an estimate from the measured token rate, not a measured result.
- Whether the Stobe client parser tolerates missing add-on keys. Not checked; required before Fix 2 is deployed.
- Speed-key presses at 19:49:08-19:49:12 (KenshiFP.log 138-143) show the user uses game-speed keys in this session, which supports hypothesis (a) but does not prove it.
