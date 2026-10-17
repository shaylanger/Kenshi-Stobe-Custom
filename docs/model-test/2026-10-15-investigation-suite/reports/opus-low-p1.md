## Summary
Tengu's first reply ("Tango"? You address an emperor...) took about 101 s from the moment you finished speaking (19:49:49) until it showed and played in game (19:51:30). That time has two parts:
1. **About 13 s on the server.** The LLM took 10 s, and the line is only sent after the whole JSON reply is finished and the TTS audio is made.
2. **About 88 s in the game.** The finished line reached the plugin at 19:50:02. But the game was paused at that point, and Stobe's action queue does not run SAY actions while the game is paused. It held the line until the game was unpaused at about 19:51:30.

## Root cause
The main cause (88 of the 101 s) is the paused game. `Functions.cpp` returns early from the action queue update whenever `thisptr->isPaused()` is true, so a reply that arrives while the game is paused waits until the game is unpaused. The second, smaller cause (about 13 s) is that the server sends nothing until the full structured LLM reply (257 tokens) and the TTS audio are done.

## Evidence
- stobe.log (`D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`):
  - line 188, 19:49:49.288: the chat is sent to the server.
  - lines 223–230, 19:50:02.147–.150: `CHAT_TIMING: STREAM_LINE actor=Tengu` and `TIMING_META: queued ACT_SAY target=Tengu`. The reply had arrived.
  - line 232, 19:50:02.150: `ACTION_QUEUE: paused; deferring queued actions size=1 next_type=0`. This line repeats every 1.5 s, 100 times in total, up to 19:51:29.202.
  - line 299, 19:51:30.064: `ACTION_EXEC: SAY [Tengu]` is when the line finally plays.
- Game time stood still, which confirms the pause. The gamets value is 124104 at 19:49:59 (line 216) and still 124104 at 19:51:19 (the infoloc event). By 19:51:35 (line 317) it is 124271.
- Code, `components\STOBE\src\Functions.cpp`: lines 7115 (`gamePaused = thisptr->isPaused()`) and 7163–7173 (`if (gamePaused) { ...Log...; LeaveCriticalSection; return; }`).
- Server log `/var/www/html/StobeServer/log/stobeserver.log`, request `req_6ad0313d4e3da` (the WSL clock reads 6 h ahead, so 01:49 there is 19:49 in game):
  - `pre_llm_ms":1249`
  - `llm_ttft_ms":1060`
  - `llm_total_ms":10016, "llm_after_first_text_ms":8956`
  - `tts_synthesis_ms":1451, "request_elapsed_ms":12816`
- `chat_llm_full_capture.log` line 147: `prompt_tokens 12321, completion_tokens 257, cached_tokens 0`, `response_format json_schema`.

## What you ruled out
- **Memory recall and embeddings:** they took 36 ms in total.
- **The HTTP send:** the ingress request completed in 40 ms.
- **The NPC info panel (opened at 19:49:42) pausing the game:** game time kept moving until 19:49:59.
- **Stobe's own chat window pause** (`CreateChatUI` → `TryRequestUserPauseSafe`, ChatBox.cpp 5975): there is no `CreateChatUI` log line after 19:48:58, so Stobe's chat window did not cause this pause.
- **The TTS hold:** it only started after the line ran, at 19:51:30.

## Proposed fix
**A. Main fix (client): let dialogue SAY actions run while the game is paused.**
In `components\STOBE\src\Functions.cpp`, at the early return near line 7163, keep holding back world-changing actions, but let a SAY at the front of the queue through:

```diff
-    if (gamePaused) {
+    bool frontIsSay = !g_uiActionQueue.empty() &&
+                      g_uiActionQueue.front().type == ACT_SAY;
+    if (gamePaused && !frontIsSay) {
       if (!g_uiActionQueue.empty() && nowTick - pausedQueueLogTick >= 1500) {
```

Things to check when you apply it:
- Use the real SAY enum name. The log shows `next_type=0`, which is the SAY type here; check its name in the `QueuedAction` definition.
- The speech-delay and hold code below the early return uses `gameSpeedMultiplier`. That value is already forced to 1.0 while paused (line 7120), so timing still runs in real time.
- Kenshi may not count down the speech bubble timer (`speechTextTimer`) while paused, so the bubble may stay up longer. The TTS audio plays on its own thread.
- Make it switchable with an INI option (for example `SpeakWhilePaused=1` in Stobe.ini, read in Utils.cpp), as the repo conventions ask.

A simpler alternative: leave the code alone and don't keep the game paused after you speak. The line plays as soon as you unpause.

**B. Secondary fix (server): send the speech before the rest of the reply.**
At the moment the line is sent only after the full JSON reply (257 tokens, about 9 s after the first text) and then TTS.
- In the StobeServer stream handler, where the `openaijson` connector stream is read: once the `speech`/dialogue field of the JSON is complete, start TTS and send the NPC_SAY right away, instead of waiting for `llm complete`.
- Also put the speech field first in the `stobe_dialogue` json_schema, so it finishes early in the stream.

Expected effect: about 13 s → about 4–5 s. Also, `cached_tokens: 0` on a 12k-token prompt suggests the prompt cache (`prompt_cache_key stobe:tengu:chat`) did not hit on this first message. On a first talk that is expected.

## How to confirm the fix worked
- **Fix A:** talk to an NPC, then pause the game before the reply arrives. In stobe.log, `ACTION_EXEC: SAY [<npc>]` should follow `TIMING_META: queued ACT_SAY` within about 1 s, with no `ACTION_QUEUE: paused; deferring ... next_type=0` lines in between. Before the fix those lines repeat until you unpause.
- **Fix B:** in stobeserver.log, the request's `TTS audio synthesized` `request_elapsed_ms` should drop below `llm_total_ms`. Today it is 12816 against 10016.

## What is not settled
- What paused the game at about 19:50:00 is not logged. Most likely you pressed pause (Space), or the game window lost focus. Stobe's own chat-window pause has no log line for it.
- The server stream handler file and function were not opened, so the exact edit location for fix B still needs checking.
- The SAY type enum name for fix A needs to be checked against the `QueuedAction` definition.
