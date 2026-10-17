BENCH-haiku-medium-p1 report (read-only; nothing edited, no service restarted, no DB writes, no POSTs, no pending-fixes read).

## Summary
The first Tengu reply after a fresh load took about 1 min 53 s from speaking to hearing it. It has three parts: (1) the first speech-to-text call after launch took 11.9 s (Parakeet cold start), (2) the LLM plus TTS took 12.9 s, and (3) the game clock was frozen for 88 s (19:50:02 to 19:51:30) and Stobe's action queue held Tengu's line the whole time. Part 3 is the largest. Its trigger is not settled; see "What is not settled".

## Root cause
Two separate delays, each with a different cause:
- **Largest (88 s):** the engine was paused, and Stobe deliberately defers all queued actions while `world->isPaused()` is true. Tengu's reply was queued at 19:50:02.150 and only executed at 19:51:30.064. Nothing in the log says what paused the game.
- **Cold start (11.9 s):** the first Parakeet transcription after WSL start is slow; every later one takes 50 to 110 ms.
- **Reply latency (12.9 s):** the LLM takes about 10 s for a 113-character line, and the server emits no partial text (chunks_emitted 0). TTS synthesis (1.45 s) finishes before the line is returned to the game.

## Evidence
Game log, `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log` (the live one; `D:\KenshiInst\*` copies are stale):
- 19:49:36.065 STT recording starts; 19:49:37.141 stop; 19:49:49.117 `STT_UPLOAD: completed`; 19:49:49.282 `STT_RESULT: dispatching transcript`. Later utterances: stop 19:51:44.798, upload done 19:51:44.935; stop 19:52:03.349, done 19:52:03.429.
- 19:49:49.288 chat dispatched (`CHAT: dispatched inputtext`).
- 19:50:02.147 `CHAT_TIMING: STREAM_LINE actor=Tengu`; 19:50:02.150 `TIMING_META: queued ACT_SAY target=Tengu`.
- 19:50:02.150 to 19:51:29.202: a repeating `ACTION_QUEUE: paused; deferring queued actions size=1` line roughly every 1.5 s (about 58 lines).
- 19:51:30.064 `ACTION_EXEC: SAY [Tengu]` and `TTS_PLAYBACK: enqueued`.
- Game clock check: `gamets` is 124104 at 19:49:59 and still 124104 in the 19:51:19 infoloc event, then 124271 at 19:51:35. Game time was frozen, which matches an engine pause. Before 19:49:59 it advanced normally (122857 at 19:49:19, 123829 at 19:49:49).

Client code:
- `components/STOBE/src/Functions.cpp:7112-7117`: `gamePaused = thisptr->isPaused()`.
- `Functions.cpp:7142-7151`: when `gamePaused` is true, the queue logs the pause line and returns, so nothing in the queue runs.
- Stobe's own pause requests are `userPause(true)` at `ChatBox.cpp:5975` (chat window, `CreateChatUI`), `ChatBox.cpp:4949` (rename), and `StartingWindow.cpp:275`. They are released in `CloseChatUI` (`ChatBox.cpp:2443-2451`) and the rename close path. Chat submit does not close the window.
- Chat-window open: `CHAT_OPEN` at 19:48:58.016.
- `STT` path: `Comm.cpp:1477` posts to `/StobeServer/stt.php`, with a WinHTTP timeout of 15 s (`Comm.cpp:1470`).

Server log, `/var/www/html/StobeServer/log/stobeserver.log` (WSL; its clock is 6 h ahead of the game log for this session, matched by content and `unix_ms`):
- `STT transcription completed` for the first call: `stt_service_ms` 11942 (01:49:37 to 01:49:49). Later calls: 50 to 110 ms (01:59:23 onward).
- Chat request `req_6ad0313d4e3da`: pre-LLM 1249 ms; `llm first text` at 01:49:51.672 (TTFT 1060 ms); `llm complete` at 01:50:00.628 (`llm_total_ms` 10016, `llm_after_first_text_ms` 8956, `response_length` 113, `chunks_emitted` 0); TTS start 01:50:00.683; `TTS audio synthesized` 01:50:02 (`tts_synthesis_ms` 1451); `Request completed` 12840 ms.
- `/etc/start_env` starts Parakeet on port 8022 at WSL start; the first real transcription is the first time its model does work.

Other: `NETWORK_ERROR: HTTP request failed with error 12002` at 19:49:28.100 (WinHTTP timeout), in the same window.

## What you ruled out
- Chat dispatch inside the game: `CHAT_SEND_STAGE` takes about 4 ms (19:49:49.283 to .288).
- Server request ingress and pre-LLM work (1.25 s): not the cause.
- LLM first token (1.06 s): normal.
- TTS synthesis (1.45 s): real but small.
- Repeated STT slowness: only the first call is slow.
- Stobe's startup/chat pause on its own explaining the 88 s: the game clock ran from 19:49:03 to 19:49:59 while the chat window was supposedly open, so a plain "chat window is open" pause does not fit the timeline by itself.

## Proposed fix (for you to apply later)
1. **Warm Parakeet at WSL start (server, no game change).** In `/etc/start_env`, after the `check_port "$PARAKEET_PORT"` success, send one silent WAV (about 1 s of zeros) to `http://127.0.0.1:8022/v1/audio/transcriptions` and discard the result. Expected effect: first real STT drops from about 12 s to about 0.1 s.
2. **Find and log the pause source (client).** In `Functions.cpp` near line 7112, add a transition logger: keep a static `bool lastPaused`; when `world->isPaused()` changes, log `GAME_PAUSE: paused=<0|1> chatPaused=<g_chatPausedGame> renamePaused=<g_renamePausedGame> startingPaused=<g_startingPausedGame> chatOpen=<g_chatWindow!=nullptr>`. Also add the same fields to the existing `ACTION_QUEUE: paused` line. Then rerun the chat flow and see which flag is set during 19:50:00 to 19:51:30.
3. **Do not hold speech on a pause Stobe caused (client, after step 2 confirms the source).** If the pause comes from Stobe's own chat/rename/starting UI, release it when a queued speech action is waiting, or play the bubble and audio without waiting for the pause (the queue at `Functions.cpp:7142-7151` is the place). Do not change engine pause behaviour for user-initiated pauses.
4. **Stream the line before TTS (server).** Check `processor/chat.php` (around line 1766, `LLM stream response generated`) and `connector/openaijson.php` (around line 1332, `llm first text`): the server currently returns the full line only after the LLM finishes and TTS completes (`chunks_emitted` 0). Emit the text line first and let TTS arrive as a separate follow-up event. I did not trace the exact emit order, so verify before editing.

## How to confirm the fix worked
- Step 1: restart WSL, load a save, speak once; `grep "STT transcription completed" stobeserver.log` should show `stt_service_ms` under 500 for the first call.
- Step 2: after the next chat with a pause, `grep "GAME_PAUSE" stobe.log` names the flag set during the wait.
- Step 3: time from `STREAM_LINE` to `ACTION_EXEC SAY` in `stobe.log` should be under 1 s, even when the game is paused by the chat window.
- Step 4: the LLM line's `STREAM_LINE` should arrive about 1.5 s before `TTS audio synthesized` on the server log.

## What is not settled
- **What paused the game at about 19:50:00 (the main unknown).** The chat window's pause request is one candidate, but the timeline says the game ran for about 1 minute while that window was supposedly open, so something else (a Stobe UI path or a game/user pause) is likely. Step 2 settles it; I could not tell from the logs.
- Whether the 12002 timeout at 19:49:28 affected this chat (no evidence it did).
- The exact emit order on the server (step 4) is not traced.
- The 9 s LLM generation for 113 characters is long for DeepInfra DeepSeek V4.1 Flash, but I did not check other turns for the typical rate.
