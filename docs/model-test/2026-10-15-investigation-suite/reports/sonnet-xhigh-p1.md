## Summary

Your first reply from Tengu reached your screen about 101 s after you sent the message. It was about 113 s after you released the talk key. A normal reply in the same session took about 10 s.

Three things added up, and one of them is dominant:

| Step | Wall time | Share |
|---|---|---|
| 1. Speech-to-text (Parakeet) cold start | 11.9 s | 10% |
| 2. Server and LLM turn | 12.8 s | 11% |
| 3. Finished reply held in Stobe's action queue because the game was paused | 87.9 s | 78% |

- **Step 1.** Parakeet's very first transcription after start-up took 11.9 s. Every later call took 0.05 to 0.35 s.
- **Step 2.** This is normal for every chat. It is slower than it needs to be because the server waits for the whole LLM answer before speaking.
- **Step 3.** The game was paused, and Stobe holds every spoken line until the game unpauses.

Without the pause, the reply would have arrived about 25 s after you released the key. Of the three, only the pause was unique to this reply.

Times below: client logs are MDT (local, UTC-6). Server logs are UTC, so 19:49:49 MDT is 01:49:49 UTC.

## Root cause

**Main cause.** At 19:49:57.597 the game's speed multiplier dropped to 0, meaning the game was paused. It stayed at 0 until 19:51:30.067. Tengu's reply reached the client at 19:50:02.147, 4.5 s into the pause. `ExecuteQueuedActions` returns early whenever the world is paused, and that includes speech and TTS. So the finished reply sat in the queue for 88 s and was spoken the moment you unpaused.

**Secondary cause.** The first call to the Parakeet speech-to-text service after it was loaded paid an 11.3 s one-time initialisation. The server has no warm-up call.

**Always-on cost.** For every manual chat with a non-squad NPC, the server holds the NPC's spoken line until the LLM has finished the entire JSON reply. About 90% of that JSON is empty bookkeeping fields.

## Evidence

**The pause (the 88 s)**
- `D:\Steam\steamapps\common\Kenshi\KenshiFP.log`, lines 212-213:
  - `[19:49:57.597] [speed] frameSpeedMult 1.00 -> 0.00 (... 61672 ms after LMB up)`
  - `[19:51:30.067] [speed] frameSpeedMult 0.00 -> 1.00`
- The game clock stopped over the same interval. `EVENT_STREAM gamets` is 124104 at 19:49:59 and still 124104 at 19:51:19. It resumes at 124271 at 19:51:35.
- `RE_Kenshi\stobe.log`, line 223: `19:50:02.147 CHAT_TIMING: STREAM_LINE actor=Tengu ...`. Line 230 shows the SAY queued at 19:50:02.150.
- Then 59 lines of `ACTION_QUEUE: paused; deferring queued actions size=1 next_type=0` follow, one every 1.5 s, from 19:50:02.150 to 19:51:29.202.
- Line 299: `19:51:30.064 ACTION_EXEC: SAY [Tengu]: "Tango"? You address an emperor...`. This is 3 ms before KenshiFP logs the unpause.
- Code:
  - `C:\KenshiModding\components\STOBE\src\Functions.cpp` lines 7163-7173, in `ExecuteQueuedActions`. If `gamePaused`, it logs "ACTION_QUEUE: paused", releases `g_uiMutex` and returns. There is no exception for ACT_SAY, ACT_PLAY_TTS or narrator notifications.
  - In the build tree `/root/STOBE-src/src/Functions.cpp` the same block is at line 7138. The whole file differs from the repo snapshot, probably line endings, but the logic is the same.
- It is not a one-off. The same hold happened again at 19:57:20 to 19:58:33. Jaegar's line was queued at 19:57:32.348 and spoken at 19:58:33.845. The "paused" lines cluster in 19:50, 19:51, 19:57 and 19:58 only.
- The second Tengu reply, in an unpaused game, was queued at 19:51:55.1 (`ACTION_EXEC`/TTS enqueue 19:51:55.135). That was 10.3 s after the key was released at 19:51:44.79.

**Parakeet cold start (the 11.9 s)**
- `stobeserver.log`, UTC:
  - `01:49:37 Latency stage stt provider dispatch ... parakeet`
  - `01:49:49 STT transcription completed ... "stt_service_ms":11942`, for a 1.08 s clip of 33,582 bytes.
- The next 13 STT calls that evening took 49 to 353 ms, for example 108, 52, 49, 49, 61 and 353.
- `/home/dwemer/parakeet-api-server/log.txt`: the server was ready at 16:55 CDT and idle for about 4 h. Then the first POST shows `Transcribing: 100% 1/1 [00:11, 11.32s/it]`. Every later POST shows 3.5 to 25 `it/s`.
- `server.py` lines 289-295: the model is created and "Server ready" is printed, with no warm-up transcription.
- Torch is `2.14.0+cu130` with `sm_120` in its arch list, so this is not a missing-kernel JIT of torch itself.

**Server and LLM turn (the 12.8 s)**
- Request `req_6ad0313d4e3da` in `stobeserver.log`:
  - ingress 01:49:49
  - pre-LLM stages total 1,249 ms (`system_prompt_and_scene` 809 ms)
  - `llm_ttft_ms` 1,060
  - `llm_total_ms` 10,016
  - `tts_synthesis_ms` 1,451
  - `Request completed ... duration_ms 12840`
  - `output_to_plugin request_elapsed_ms 12818` at 01:50:02
- The client logged the line 10 ms after the server queued it (19:50:02.147).
- `LLM stream response generated ... "chunks_emitted":0`. No sentence was emitted while the model was still generating.
- The same `chunks_emitted 0` shows on every Tengu reply that evening, with `llm_total_ms` of 5.3 to 9.2 s.
- The reply JSON in `output_from_llm.log` (line ~326754 onward) has 257 completion tokens. The spoken `message` is 113 characters, roughly 28 tokens. The rest is empty fields: `travel_*`, `region_plan_decision`, `proposed_region`, `preference_updates`, `followup_update` and `social_repair_updates`.
- Why nothing streams, in `/var/www/html/StobeServer` (live working tree; `lib/chat_helper_functions.php` has uncommitted edits):
  - `processor/chat.php:1595` sets `'defer_structured_stream' => $negotiationDefer || $relFreeAskDefer || $travelConsentTurn || $activityTurn !== null || $socialManualTurn`.
  - `$socialManualTurn` (lines 887-894) is true for every manual talk, whisper or shout to an NPC with data.
  - `$travelConsentTurn` (line 1448) is true for every non-squad NPC. Tengu is Anti-Slavers.
  - `lib/chat_helper_functions.php:15100-15110` and `:15124`: with the defer flag set, `processStructuredSnapshot` and `ttsQueue->pump()` are skipped during streaming, and the dialogue is parsed only after the whole stream ends.
  - Lines 1480-1488 of `chat.php` add the travel, region-plan, social-preference, follow-up and repair blocks to the response schema for every such turn. That is why the JSON is so long.

## What you ruled out

- **Network or transport.** The request reached the server in under 300 ms. The reply reached the client 10 ms after the server queued it.
- **LLM provider.** Time to first token was 1.06 s, and total time was in line with every other reply that evening.
- **TTS synthesis.** PocketTTS took 1.45 s, and the clip was ready and cached.
- **Prompt cache.** `cached_tokens` was 0, but several later replies also had 0 and ran at the same speed.
- **Client pipeline after unpause.** `ACTION_EXEC` ran within a few ms of the unpause. After that, TTS enqueue, playback and the bubble behaved normally.
- **Stobe's own UI pause.** The chat window, starting window and rename window pause the game by design, in `ChatBox.cpp:5974` and `StartingWindow.cpp:274`. The last of them closed at 19:49:03.629. Nothing Stobe-UI related was logged at 19:49:57.
- **KenshiFP's pause toggle.** There is no `[jump] FP pause toggle` line in `KenshiFP.log`.
- **A mouse click on the pause button.** KenshiFP reports no left-click in the 61 s before the pause.
- **The load-time pause.** `frameSpeedMult` was 0 from 19:48:34 to 19:48:56. That is the Auto-Pause-on-Load mod pausing after the save loaded, and it ended a minute before you spoke to Tengu.
- **The empty narrator welcome.** `CHAT_THREAD: Empty stream response` at 19:48:48 is the load-time narrator init. It is a separate event from the Tengu chat.

## Proposed fix

There are three independent changes. Fix 1 removes the 88 s, Fix 2 removes the 12 s, and Fix 3 is optional and removes about 7 s from every reply.

### Fix 1: let spoken lines through while the game is paused (client)

File: `components/STOBE/src/Functions.cpp` in the repo snapshot, and the same change in `/root/STOBE-src/src/Functions.cpp` (the tree that is actually built). Function: `ExecuteQueuedActions`.

TTS audio and the speech bubble are wall-clock, so only world-changing actions need a running world. Three edits.

1. Add a helper above `ExecuteQueuedActions`, in the file's own style (the project compiles with VS2010 / v100):
```cpp
static bool IsSpeechQueuedAction(const QueuedAction &a) {
  return a.type == ACT_SAY || a.type == ACT_PLAY_TTS ||
         (a.type == ACT_NOTIFY && a.narratorNotification);
}
```
2. Replace the paused gate at about line 7163:
```diff
-    if (gamePaused) {
+    const bool frontIsSpeech =
+        !g_uiActionQueue.empty() && IsSpeechQueuedAction(g_uiActionQueue.front());
+    if (gamePaused && !frontIsSpeech) {
       if (!g_uiActionQueue.empty() && nowTick - pausedQueueLogTick >= 1500) {
         ...unchanged log...
       }
       LeaveCriticalSection(&g_uiMutex);
       return;
     }
```
3. Inside the `while` loop, right after `nextActionIsSpeech` is computed (about line 7237), add:
```cpp
      if (gamePaused && !nextActionIsSpeech) break;  // moves/gives/etc. still wait for a running world
```
This `break` is safe. The loop already breaks the same way at lines 7247 and 7251, and the mutex is released at line 11021.

Why only these edits:
- The pacing clock at lines 7139-7160 does not tick while paused, but `g_nextSpeechActionTick` is an absolute tick, so it expires in real time anyway.
- `ResolveDialogueGameSpeedMultiplier` and `ResolveSpeechQueueRemainingRealMs` already guard a speed of 0.
- `holdForTtsPlayback` is wall-clock via `IsTtsPlaybackActive()`.

Side effect to test in game: the bubble timers (`speechTextTimer`) count in game time. On a paused world the bubble should stay visible until you unpause, which is probably fine and even helpful. I could not verify this without running the game.

Smaller fallback if you do not want speech to play while paused: in the paused branch, when the front item is speech and has waited more than about 3 s, call `thisptr->showPlayerAMessage_withLog("[STOBE] <name> has replied - unpause to hear it", true)` once. That at least stops it looking frozen.

### Fix 2: warm Parakeet up before it serves (WSL)

File: `/home/dwemer/parakeet-api-server/server.py`, inside `initialize_model`, after `stt_model = create_backend(...)` and before `print("✓ Server ready!\n")` (around line 295). `np` is already imported at the top of the file.
```diff
     stt_model = create_backend(
         precision=precision,
         model_dir=model_dir,
         num_threads=num_threads,
         force_cpu=force_cpu
     )
+    # Warm-up: the first real transcription costs ~11 s one-time init
+    # (log.txt "11.32s/it"; stobeserver.log stt_service_ms=11942). Pay it before the port opens.
+    try:
+        for seconds in (1, 3):
+            stt_model.transcribe(np.zeros(16000 * seconds, dtype=np.float32))
+        print("✓ Warm-up transcription done\n")
+    except Exception as exc:
+        print(f"Warm-up failed (non-fatal): {exc}\n")
     print("✓ Server ready!\n")
```
- Model loading happens before uvicorn starts, so the extra 10 to 12 s only delays readiness. `start_native.sh` allows 900 s.
- If NeMo rejects pure silence, use `np.random.randn(16000*seconds).astype(np.float32) * 0.01`.
- This is a third-party install, so a reinstall or update will drop the edit.
- No-edit alternative: send one dummy POST to `http://127.0.0.1:8022/v1/audio/transcriptions` (a 1 s silent WAV) right after the health check passes, for example at the end of the Parakeet block in `/etc/start_env`. Put it after the existing health wait at line ~647-655.
- Apply it with the usual `wsl-voice.sh stt stop` then `start`.

### Fix 3 (optional, a design decision): stop buying the whole JSON before speaking (server)

Do not apply this without the negotiation and travel regression tests. The deferral exists so that outsider speech is not spoken before consent and orders are validated.

Today `processor/chat.php:1595` defers the stream on every manual chat to a non-squad NPC. The schema additions at lines 1480-1488 are also unconditional. Two options:
- Add the travel, region-plan, activity and social blocks to the schema, and set `defer_structured_stream`, only when a cheap intent check on the player's text says they could apply. A plain "what's up" would then stream normally.
- Keep the deferral but drop those blocks from the schema for turns that cannot use them. That cuts the output from about 257 tokens to about 60, so LLM time falls from about 10 s to about 3 s.

Estimate: a first spoken sentence about 5 to 6 s after sending, instead of about 12.8 s. That figure comes from my arithmetic on the logged timings and has not been measured.

## How to confirm the fix worked

**Fix 1 (in game, with the new DLL):**
1. Talk to any non-squad NPC.
2. Press Space or P right after sending.
3. In `stobe.log`, the gap between `CHAT_TIMING: pipe queued ... NPC_SAY` and `ACTION_EXEC: SAY [NPC]` must be under 1 s. Before the fix it was 88 s.
4. There must be no `ACTION_QUEUE: paused` lines for that SAY.
5. `KenshiFP.log` must still show `frameSpeedMult ... 0.00` during the speech. That proves it spoke while paused.
6. Then queue a non-speech action (for example an NPC give or follow) while paused. It must still print `ACTION_QUEUE: paused` with `next_type` other than SAY.

**Fix 2:**
1. Stop and start Parakeet and wait for health.
2. Hold the talk key once and release it.
3. The first `STT transcription completed` line in `stobeserver.log` must show `stt_service_ms` under about 500. It was 11,942.
4. The first `Transcribing` line in `log.txt` must be 0.1 s or less, not 11.32 s.

**Fix 3:** `LLM stream response generated` must show `chunks_emitted` greater than 0 for a plain chat. `output_to_plugin request_elapsed_ms` should fall from 8,000-13,000 to about 5,000.

## What is not settled

- **What paused the game at 19:49:57.597, and what unpaused it at 19:51:30.067.** The logs cannot say. It was not Stobe's UI, KenshiFP's pause key, a mouse click or the load-time pause. That leaves a keyboard pause (Space or P), or the Auto-Pause-on-Load mod. That mod is configured with `pause_on_inventory_open: true` and `pause_on_trade: true`, and its debug logging is off, so it would leave no trace. Do you remember pressing Space or opening an inventory or trade window around then? Fix 1 makes the cause irrelevant to whether you hear the reply.
- **Whether the bubble and TTS behave correctly on a paused world.** This needs one in-game test. I only know the code path, not what Kenshi renders.
- **Whether the running `Stobe.dll` matches the source I read.** The log strings match the source, but I did not hash the DLL.
- **Whether the 11.3 s Parakeet delay is purely first-call initialisation.** The evidence is strong (one slow call, then all fast, with a ready model), but the warm-up is what will prove it.
- **`NETWORK_ERROR: HTTP request failed with error 12002` at 19:49:28.100.** This is 21 s before the chat. I could not tell which request it was. The chat request itself succeeded.
- **The STT heard "Tango" instead of "Tengu".** That is a recognition quality issue, not a latency one.
- **How many of the later 5 to 10 s replies you would accept.** Fix 3 is a trade-off between speed and validation, and the call is yours.

I changed nothing. All reads were from logs, source and the database, and no service was restarted.
