## Summary
Tengu's first reply was ready about 13 s after you spoke, but you didn't hear it until 101 s after. The game was paused from 19:49:57.6 to 19:51:30.1. Stobe holds every queued action while the game is paused, and that includes plain speech. So the line sat in the queue for 88 s and played 3 ms after the game was unpaused. The other 13 s was server time: about 10 s of it was the LLM writing a full structured JSON reply before anything is sent (chat replies are not streamed sentence by sentence), plus some one-off cold-start cost on the first request.

## Root cause
In `ExecuteQueuedActions`, Stobe checks whether the game is paused and, if it is, returns without running anything in the queue. It makes no exception for speech (`ACT_SAY` / `ACT_PLAY_TTS`). A reply that arrives while the game is paused waits, silently, until you unpause.

Timeline (client `stobe.log`, server `stobeserver.log`; the server clock is +6 h):

| Time | Event |
|---|---|
| 19:49:49.288 | Your line "What's up, Tango?" is sent to the server |
| 19:49:57.597 | Game paused (`frameSpeedMult 1.00 -> 0.00`) |
| 19:50:02.147 | Tengu's line arrives, already voiced (`STREAM_LINE ... tts_dur_ms=8720`) |
| 19:50:02.150 → 19:51:29.202 | `ACTION_QUEUE: paused; deferring queued actions size=1 next_type=0` about every 1.5 s (type 0 = `ACT_SAY`) |
| 19:51:30.064 | `ACTION_EXEC: SAY [Tengu]` |
| 19:51:30.067 | Game unpaused (`frameSpeedMult 0.00 -> 1.00`) |

The second reply came with the game running: received 19:51:55.129, played 19:51:55.135 (6 ms).

## Evidence
- **Client log** `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`:
  - line 177: send at 19:49:49.283
  - lines 223–230: reply arrives and is queued at 19:50:02.147–.150
  - lines 232–298: the "paused; deferring" lines
  - lines 299–301: SAY plays at 19:51:30.064
- **The pause itself** `D:\Steam\steamapps\common\Kenshi\KenshiFP.log`:
  - line 212: `[19:49:57.597] [speed] frameSpeedMult 1.00 -> 0.00`
  - line 213: `[19:51:30.067] [speed] frameSpeedMult 0.00 -> 1.00`
  - Cross-check in `stobe.log`: game time stays at `gamets=124104` from 19:49:59 (line 216) to 19:51:19 (line 291), and the 8-second `infonpc` events stop between 19:49:59 and 19:51:35.
- **The gate in the code** `C:\KenshiModding\components\STOBE\src\Functions.cpp`:
  - line 7115: `gamePaused = (thisptr && thisptr->isPaused());`
  - lines 7163–7173: `if (gamePaused) { ...Log("ACTION_QUEUE: paused; deferring...") ...; LeaveCriticalSection(&g_uiMutex); return; }`
  - The function starts at line 7084 and is called every frame from `main.cpp:15739`.
  - The live source `/root/STOBE-src/src/Functions.cpp` has the same gate at lines 7086 and 7138 (that file differs from the snapshot elsewhere).
  - The gate is in the oldest snapshot commit, `b0a09a3`, so it was there before any of your own changes.
- **Server timing, first request** (`/var/www/html/StobeServer/log/stobeserver.log`, request `req_6ad0313d4e3da`, 01:49:49–01:50:02):

  | Step | First request | Later requests |
  |---|---|---|
  | Work before the LLM call | 1249 ms (system prompt + scene: 809 ms) | 502–639 ms |
  | LLM time to first token | 1060 ms | similar |
  | LLM total | 10016 ms | 5.3–9.2 s |
  | TTS | 1451 ms | 103–376 ms |
  | Total | 12840 ms | 6.2–10.1 s |

  Other values for the first request:
  - LLM output still being written after the first token: 8956 ms.
  - Streaming: `chunks_emitted:0, actions_streamed:false`.
  - Token usage (`output_from_llm.log`, about line 326760): `prompt_tokens 12321, cached_tokens 0, completion_tokens 257`. Those 257 tokens are mostly empty JSON fields (travel_*, region_plan_*, followup_update, ...) wrapped around a 113-character line.
  - "Bored" events are streamed one sentence at a time and finish in 2–4 s.

## What you ruled out
- **Stobe's own menus did not cause the pause.** Only the chat window and the Stobe menu call `userPause(true)` (`ChatBox.cpp:5975`, `StartingWindow.cpp:275`). Both log a `UI: Create...UI done` line. There is none near 19:49:57; the last ones are at 19:48:58 and 19:49:01, and the game was running again after those.
- **KenshiFP did not cause it.** Its source has no `userPause` / `isPaused` call. It only logged the speed change.
- **Not a server or network failure.** The request finished with status 200 in 12.8 s.
- **Not TTS download or playback.** `download_ms=0`, and playback started 8 ms after the SAY.
- **Not the player-TTS barrier or the speech delay.** Neither log line appears; the only thing blocking was the pause gate.
- **Not a mistake in the client log.** The client and server logs match at every step.

## Proposed fix
**Fix 1 (main fix, client).** Let speech play while the game is paused, but keep holding everything else (attacks, moves, gives). Put it behind a setting, since upstream asks for new behaviour to be switchable.

1. **Add the setting.** In `Globals.h`, add `extern bool g_speakWhilePaused;`. Define it in a .cpp file next to `g_ttsEnabled`: `bool g_speakWhilePaused = true;`. In `Utils.cpp`, next to the `TtsEnabled` read (line 623), add:
   ```cpp
   g_speakWhilePaused = ReadLayeredIniInt(baseIniPath, customIniPath, "Settings", "SpeakWhilePaused", 1) != 0;
   ```
   Then add the matching `WritePrivateProfileStringA("Settings","SpeakWhilePaused", ...)` next to line 745.

2. **Change the pause gate.** In `Functions.cpp`, `ExecuteQueuedActions`, around lines 7163–7173:
   ```diff
   -    if (gamePaused) {
   +    const bool speechOnlyWhilePaused = gamePaused && g_speakWhilePaused;
   +    if (gamePaused && !speechOnlyWhilePaused) {
          if (!g_uiActionQueue.empty() && nowTick - pausedQueueLogTick >= 1500) {
            ...unchanged...
          }
          LeaveCriticalSection(&g_uiMutex);
          return;
        }
   ```

3. **Hold non-speech actions while paused.** In the same function's `while` loop, right after `nextActionIsSpeech` is computed (line 7237) and before the player-TTS barrier check:
   ```diff
   +      if (speechOnlyWhilePaused && !nextActionIsSpeech) {
   +        if (nowTick - pausedQueueLogTick >= 1500) {
   +          pausedQueueLogTick = nowTick;
   +          Log("ACTION_QUEUE: paused; speech allowed, deferring next_type=" +
   +              ToString((int)nextAction.type));
   +        }
   +        break;   // keep order: actions after this line wait for unpause
   +      }
   ```
   The `break` keeps the queue in order: a line can play while paused, but an action the NPC "agreed to" waits until you unpause.

4. **Stop NPC-to-NPC follow-ups while paused (recommended).** Without this, Tengu's line playing while paused immediately starts a follow-up chat with another NPC (the log shows Polik at 19:51:30.154), and that conversation would keep going during the pause. In `ChatBox.cpp`, just before `DispatchRechatFollowup(...)` (line 4072), add a wait that ends when the game is unpaused or the generation changes:
   ```cpp
   while (IsChatInterruptGenerationCurrent(generation) && IsWorldPausedSafe()) Sleep(50);
   ```
   `IsWorldPausedSafe()` would be a small helper that does the same `GetWorldSafe()->isPaused()` read with try/catch that `SleepIfPaused` already does from this thread (`Utils.cpp:1634–1642`).

Build with `build-stobe-sdk`/VS2010 as usual (no new language features are needed), then install.

**Cheaper alternative if you want to keep the "frozen while paused" behaviour.** At the first "deferring" line for a queued `ACT_SAY`, show `thisptr->showPlayerAMessage_withLog("[STOBE] <name> has replied - unpause to hear it", true)` once, so the wait is visible instead of silent.

**Fix 2 (secondary, server, about 3–6 s per reply).**
- Stream chat replies the way bored events already are: send the `message` field and start TTS as soon as it is complete, without waiting for the rest of the JSON.
- And/or trim the chat response schema. Make the travel/region/followup/social fields optional, or move them to a second call, so the model doesn't spend about 250 tokens (about 8 s at the roughly 29 tok/s seen here) before anything can be spoken.
- The cold-start part of the first reply (about 0.7 s of prompt building, about 1.2 s of TTS warm-up, cached_tokens 0) could be removed with a warm-up call to PocketTTS and the prompt builder when a save loads.

## How to confirm the fix worked
1. Load the "Fresh start" copy and talk to Tengu with push-to-talk. Press Space within about 5 s, before the reply arrives.
2. Expected in `stobe.log`:
   - `ACTION_EXEC: SAY [Tengu]` within about 0.1 s of `CHAT_TIMING: STREAM_LINE actor=Tengu`
   - no `ACTION_QUEUE: paused; deferring queued actions ... next_type=0` lines in between
   - `KenshiFP.log` still showing `frameSpeedMult 1.00 -> 0.00` with no unpause before the SAY
   - you hear the line while the game is paused
   - a reply that carries an action (e.g. `MOVE_TO_TARGET`) logs `paused; speech allowed, deferring next_type=<non-zero>` and runs only after you unpause
   - no `RECHAT: dispatched follow-up` until after the unpause
3. Before the fix the same steps reproduce the gap: a `STREAM_LINE` → `ACTION_EXEC: SAY` gap equal to how long the game was paused.
4. Quick check: `grep -n "STREAM_LINE actor=\|ACTION_EXEC: SAY \[\|paused; deferring" stobe.log`.
5. For Fix 2, compare `llm_after_first_text_ms` and `Request completed duration_ms` in `stobeserver.log` before and after.

## What is not settled
- **What paused the game at 19:49:57.6.** No Stobe or KenshiFP log records it. The most likely cause is the Space key (vanilla pause) or one of vanilla Kenshi's auto-pauses. You can confirm what you pressed.
- **Whether Kenshi shows overhead speech bubbles correctly during a pause.** The bubble timer `speechTextTimer` doesn't count down while paused, so the bubble may stay up until you unpause. The `sayALine`/`say` calls are made on the main thread as usual, but showing them while paused has not been tried in the game.
- **Which tree built the installed `Stobe.dll`.** It is dated Oct 14 19:37; the snapshot under `components\STOBE\src` and `/root/STOBE-src` differ. Both have the same gate, so the fix applies to both; only the line numbers differ (about 29 lines earlier in `/root/STOBE-src`).
- **How much of the 8–9 s of LLM output time is the DeepInfra endpoint being slow** versus the JSON schema being large. The token counts suggest the schema is a large part of it, but this was not measured.
