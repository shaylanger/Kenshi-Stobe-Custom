**Summary**

Shay's first Tengu reply took about 113 s from the moment he released push-to-talk (19:49:37.14 local) to the moment Tengu spoke (19:51:30.06). Three separate delays stacked up:

| Delay | Time | Cause |
|---|---|---|
| Speech-to-text (Parakeet) | 11.9 s | First transcription after the Parakeet server started (cold). Every later one took 50-350 ms. |
| Server reply (LLM + voice synthesis) | 12.8 s | The server buffers the whole reply for non-squad NPCs, and the reply JSON is about 250 tokens. |
| Stobe holding the line | 88 s | The game was paused from 19:49:57.6 to 19:51:30.07. Stobe will not play NPC speech while the game is paused. |

The 88 s is the largest, and the 12 s speech-to-text delay is the easiest to remove.

**Root cause**

1. **Parakeet's first transcription after startup costs about 11 s, because the server never warms up its model.** `initialize_model()` loads the model and `/health` then reports healthy. The first real `transcribe()` call pays the one-time NeMo/CUDA initialisation.
2. **The reply is slow to start because the server waits for the complete JSON before it speaks.**
   - `processor/chat.php` line 1595 sets `defer_structured_stream` to true for every NPC who is not in the player's faction (`$travelConsentTurn`) and for every manual talk turn (`$socialManualTurn`).
   - The reply JSON also carries about 200 tokens of travel, region-plan and social-repair fields on top of the roughly 30-token message.
   - Voice synthesis starts only after the model finishes.
3. **Stobe holds NPC lines while the game is paused.** `Functions.cpp` returns from the action-queue update whenever `thisptr->isPaused()` is true. The line was ready at 19:50:02 and played the instant the game unpaused. This is by design. Who paused the game is not proven.

**Evidence**

*Speech-to-text (cold start):*
- Server log, 2026-10-15 01:49:49 UTC (the server log is UTC, so subtract 6 h for game-local time): `STT transcription completed ... "stt_service_ms":11942` for request `req_6ad031312a1e5`. The upload arrived at 01:49:37.
- The same job's other transcriptions: 108 ms (01:51:44), 49-61 ms (01:52), 353 ms, then 50-110 ms.
- `/home/dwemer/parakeet-api-server/log.txt`: the first request after `Parakeet health check passed after 22s` shows `Transcribing: 100%|██████████| 1/1 [00:11<00:00, 11.32s/it]`. Every later request shows 10-25 it/s.
- Game `stobe.log`: `19:49:37.147 STT_CAPTURE: selected input=Microphone (Blue Snowball) duration_ms=1079`, then `19:49:49.117 STT_UPLOAD: completed`. The second utterance took 0.14 s (19:51:44.800 to 19:51:44.935).
- `server.py` has no warm-up. `initialize_model()` (line 238) is called at line 388, before `uvicorn.run()` at line 401.

*Server reply:*
- `stobeserver.log` for `req_6ad0313d4e3da`:
  - Request ingress 01:49:49.32.
  - `pre_llm_ms: 1249`.
  - `llm_ttft_ms: 1060`.
  - `llm_total_ms: 10016` at 01:50:00.6, with 257 completion tokens.
  - `tts start` at `request_elapsed_ms: 11363`.
  - `Request completed duration_ms: 12840`.
- The same line says `LLM stream response generated ... "chunks_emitted":0`. Nothing was spoken before the full reply arrived.
- The response in `output_from_llm.log` has `message` as the third field. About 200 of the 257 tokens are fixed scaffolding: `travel_*`, `region_plan_*`, `preference_updates`, `followup_update` and `social_repair_updates`.
- `chat.php`:
  - Line 887-894 defines `$socialManualTurn`, which is true for any `inputtext` event in talk, whisper or shout mode.
  - Line 1448 defines `$travelConsentTurn`, which is true for any NPC outside the player faction.
  - Line 1595 is `'defer_structured_stream' => $negotiationDefer || $relFreeAskDefer || $travelConsentTurn || $activityTurn !== null || $socialManualTurn`.
  - Lines 1616-1619 and 1998 show that streaming early disables social-repair capture and the relationship evaluation for the turn. The deferral is intentional.
- `lib/chat_helper_functions.php` around line 15100: when `$deferStructuredStream` is true, `processStructuredSnapshot()` is never called during streaming, so `$chunksEmitted` stays 0.
- `chunks_emitted` was above 0 until 2026-10-13 04:08:41 UTC (Laru: 5). Every chat reply after that (Icthy, Beak, Dealer, Tsetseg, Tengu, Mouse) shows 0.
- Completion tokens went from about 100-150 to about 250. The first spoken line came at 5-13 s, where before it came at about 2-3 s (for example Wish, Loitpin, Ambulin and Laru).
- The git log search for `socialManualTurn` returned no commit, so this change is uncommitted. `git status` shows `processor/chat.php` and `lib/chat_helper_functions.php` modified.

*Provider speed variance:*
- Around 20:00 UTC, DeepInfra generated about 250 tokens in 5-10 s on every Tengu call, against 3.1-4 s for other NPCs at similar token counts.
- Examples: Tsetseg 260 tokens in 3146 ms, and Mouse 295 tokens in 3262 ms at 01:58.
- `cached_tokens` was 0 on the Tengu calls. Time to first token was still only about 1 s, so the cold prompt cache is not the problem.

*Pause:*
- `stobe.log`: `19:50:02.147 STREAM_LINE actor=Tengu`, followed by about 60 `ACTION_QUEUE: paused; deferring queued actions size=1` lines from 19:50:02.150 to 19:51:29.202. Then `19:51:30.064 ACTION_EXEC: SAY [Tengu]`.
- `KenshiFP.log`: `19:49:57.597 [speed] frameSpeedMult 1.00 -> 0.00`, then `19:51:30.067 frameSpeedMult 0.00 -> 1.00`.
- The Stobe event gamets stayed at 124104 from 19:49:59 to 19:51:19, so game time was not advancing.
- `Functions.cpp` lines 7163-7173: `if (gamePaused) { ... Log("ACTION_QUEUE: paused; ...") ...; return; }`.
- The same thing happened at 19:57:20.8 to 19:58:33.8. Jaegar's lines were held for 61 s while UI panels were open (`ui_open=1` at 19:57:22).

**What you ruled out**
- **Server pre-LLM work:** 1.25 s total (system prompt build 809 ms, database queries under 40 ms each).
- **Cold prompt cache:** time to first token was 1.06 s with 0 cached tokens.
- **Voice synthesis (PocketTTS):** about 1.4 s. It is not the bottleneck.
- **Reasoning tokens:** `reasoning_tokens` was 0.
- **Network or HTTP errors:** every request returned 200, and the game log shows no retry or failure.
- **Server not running:** the server was healthy and the STT request was accepted within 3 ms of the upload.
- **Game-side dispatch delay:** the chat event went out 6 ms after the transcript arrived.

**Proposed fix**

*Fix 1: warm up Parakeet at startup. Certain, about 12 s saved on the first voice message after each server start.*

In `/home/dwemer/parakeet-api-server/server.py`, inside `initialize_model()`, add this after `stt_model = create_backend(...)` and before `print("✓ Server ready!\n")`:

```diff
     stt_model = create_backend(
         precision=precision,
         model_dir=model_dir,
         num_threads=num_threads,
         force_cpu=force_cpu
     )
+    # Warm-up: the first transcribe() after load costs ~11 s (NeMo/CUDA lazy init).
+    # Pay it here, before uvicorn starts, so /health only goes healthy when it is cheap.
+    try:
+        _t0 = time.time()
+        _rng = np.random.default_rng(0)
+        _warm = (0.05 * _rng.standard_normal(config.DEFAULT_SAMPLE_RATE * 2)).astype(np.float32)
+        stt_model.transcribe(_warm)
+        print(f"✓ Warm-up transcription done in {time.time() - _t0:.1f}s")
+    except Exception as _e:
+        print(f"WARN: warm-up transcription failed: {_e}")
     print("✓ Server ready!\n")
```

`time` and `np` are already imported. Startup grows from about 22 s to about 33 s, well inside the 900 s limit in `start_native.sh`. If it still shows a slow first call, warm up with a real 3-4 s speech clip instead of noise, because the cost may depend on audio length.

*Fix 2: make a paused-game wait visible, or let speech through. Optional and a design decision.*
- Smallest change: in `Functions.cpp` at lines 7163-7173, log once when the head of the queue is an NPC SAY and the game is paused. Show a short on-screen note such as "reply waiting, game is paused", so it does not look like a server delay.
- Bigger change: let an NPC SAY run while paused (TTS plays, bubble timers do not tick). I could not verify that this is safe with the `holdForTtsPlayback` and `speechTextTimer` handling below that block, so test it before shipping.

*Fix 3: cut the reply latency, about 6-9 s.* This one has trade-offs, so read `chat.php` lines 1610-1630 and 1975-2010 before applying it.
- **Option A (low risk):** cut the tokens the model must emit. Add the `stobeTravelResponseFormat`, `stobeRegionPlanResponseFormat` and social-capture schemas only when the turn can use them. The gate would be a cheap check of the player's message for travel or follow words ("come with", "take me", "lead", "follow", "go to"), or an active travel or region state. Roughly 150-200 fewer tokens saves about 2-5 s at this provider's current speed.
- **Option B (larger gain, behaviour change):** when that same gate says the turn is plain chit-chat, drop `$travelConsentTurn` and `$socialManualTurn` from the defer condition and omit the capture schemas. Line 1595 would become:

```php
$plainChatTurn = !$negotiationDefer && !$relFreeAskDefer && $activityTurn === null && !stobeLooksLikeTravelOrDealAsk($message, $npcData); // new helper, you write it
'defer_structured_stream' => $negotiationDefer || $relFreeAskDefer || $activityTurn !== null
    || (($travelConsentTurn || $socialManualTurn) && !$plainChatTurn),
```

  Sentence-level streaming then returns, as it was on 10-13 and earlier. The first sentence is spoken as soon as the `message` field completes, at about 1.5-2.5 s. The cost is that on those turns the social-repair capture and the relationship evaluation take the already-streamed path, which disables part of the social capture (lines 1616-1619, 1998). Do not apply this blind. The other fields in the reply can also change what the NPC does.

**How to confirm the fix worked**
- **Fix 1:** restart Parakeet, then do not speak for a minute. In `log.txt` the warm-up line appears before the first `POST /v1/audio/transcriptions`. Speak once through Stobe and run `grep "STT transcription completed" /var/www/html/StobeServer/log/stobeserver.log | tail -1`. `stt_service_ms` should be under 500, not about 11900.
- **Fix 3:** after a talk turn to a non-squad NPC, check `grep "LLM stream response generated" ... | tail -1`. `chunks_emitted` should be above 0 (Option B), or `completion_tokens` in `chat_llm_full_capture.log` should drop from about 250 to about 100 (Option A). Also compare the `request_elapsed_ms` of the first `output_queued_to_plugin` line for the request. It was 12818 for this one.
- **Fix 2:** pause the game, talk to an NPC and unpause. In `stobe.log` the gap between `STREAM_LINE` and `ACTION_EXEC: SAY` should match the pause length. With Fix 2 the player should see a notice.

**What is not settled**
- **Who paused the game at 19:49:57.6.** The pause came 0.4 s after a WASD key release and about 8 s after Shay spoke. It was probably his own pause key (the 19:57 pause coincided with him opening panels), but no log shows the source. Stobe code has no pause call (no `setPaused` in `components/STOBE/src`), and nothing in the log shows another mod pausing it.
- **Whether the DeepInfra slowdown (about 28 tok/s against 80+) was a provider issue or load.** The only evidence is the log throughput. Nothing here controls it.
- **Whether the schema-bloat change was intended.** It is uncommitted work on `chat.php` and `chat_helper_functions.php`, so confirm that nothing else (Shay's other sessions) depends on the buffering before changing the defer condition.
- **Whether Parakeet warm-up with noise fully covers the lazy initialisation.** The warm-up is the standard fix, but I could not run it (read-only).
