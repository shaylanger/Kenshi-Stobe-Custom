**Summary**

Your first reply from Tengu took about 114 s from the end of your speech to the start of his voice. The log shows three stacked delays:

| Phase | Time | When (game log) |
|---|---|---|
| Speech-to-text, first call after server start | 11.9 s | 19:49:37 to 19:49:49 |
| LLM reply plus voice synthesis | 12.8 s | 19:49:49 to 19:50:02 |
| Reply ready but held back because the game was paused | 88 s | 19:50:02 to 19:51:30 |

The speech-to-text delay is a cold start in the Parakeet server and is fixable. The 88 s hold is the largest part. The log does not show who paused the game, so I can't name a fix for it, only how to find out.

**Root cause**

1. Speech-to-text cold start (fixable). The Parakeet server loads its model at startup but never runs a dummy transcription. Its first real call after a restart pays the one-time warmup inside your request. The server has been up since 16:55, and your first utterance was the first call. It took 11,942 ms. Every later call took 49 to 353 ms.
2. Reply held because the game was paused (cause not proven). The action queue refuses to run while the game is paused, and the queued speech action sat there until 19:51:30.
3. The LLM reply was slow this once. It took 10.0 s against a typical 2.5 s. This is DeepInfra variance, not something the code caused.

**Evidence**

All Stobe log lines are in `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\stobe.log`. All server lines are in `/var/www/html/StobeServer/log/` inside WSL. The server logs are exactly 6 h ahead of the game log (game 19:49:49 is server 01:49:49).

- Speech-to-text:
  - Recording stopped at 19:49:37.147 (stobe.log line 153). `STT_UPLOAD: completed` came at 19:49:49.117 (line 172).
  - `stobeserver.log` shows `STT transcription completed ... provider parakeet ... stt_service_ms 11942` for request `req_6ad031312a1e5`.
  - The same log shows a different request (`req_6ad031b0c9827`, 01:51:44) at `stt_service_ms 108`, with 49 to 61 ms typical afterwards.
  - On 2026-10-13 the same service ran 34 to 80 ms.
  - `/home/dwemer/parakeet-api-server/server.py` lines 255 to 295 only call `create_backend(...)` and then print "Server ready!". There is no warmup. `lifespan` (lines 58 to 70) only checks that the model object exists.
  - The Parakeet process started at 16:55:31.
- LLM:
  - Request `req_6ad0313d4e3da` was timed as follows:

    | Stage | Time |
    |---|---|
    | Before the model call (pre-LLM prep) | 1.25 s |
    | First model text | 1.06 s |
    | Whole model stream | 10.0 s |
    | Voice synthesis (TTS) | 1.45 s |
    | Total | 12.84 s |

  - Usage was 12,321 prompt tokens and 257 completion tokens. Of the 257 tokens, about 25 are the spoken line and most of the rest is the JSON fields.
  - Over the last 400 chat requests the model stream was a median 2.5 s and a p90 of 5.1 s, so this one was an outlier.
- Pause:
  - `components/STOBE/src/Functions.cpp` lines 7163 to 7173 return early when `thisptr->isPaused()` is true and log `ACTION_QUEUE: paused; deferring queued actions size=1`.
  - That line repeats about every 1.5 s from 19:50:02.150 to 19:51:29.202 (stobe.log lines 231 to 298).
  - Game time froze over that window. `gamets=124104` was stamped at 19:49:59 (line 216) and again at 19:51:19 (line 291), then advanced to 124271 at 19:51:35.
  - The queued line only ran at 19:51:30.064, as `ACTION_EXEC: SAY [Tengu]` (line 299).

**What I ruled out**

- Prompt cache: cold and warm requests averaged 3.9 s and 4.5 s over the last 160 chat calls, so cache misses don't explain it. This request did have `cached_tokens` 0.
- Slow server work before the model call: all stages took 0 to 809 ms (system prompt 809 ms, total pre-LLM 1,249 ms).
- Slow voice synthesis: it took 1.45 s.
- Network or HTTP errors: none on this chat. The `NETWORK_ERROR 12002` at 19:49:28 is an unrelated earlier event. The server returned 200.
- Microphone problems: capture picked the Blue Snowball correctly and the clip was 1.08 s.
- Slow database or memory recall: the recall step took 36 ms.

**Proposed fix**

Fix 1: warm up Parakeet at startup (removes the 12 s). Edit `/home/dwemer/parakeet-api-server/server.py`, in the function whose last lines are `stt_model = create_backend(...)` then `print("✓ Server ready!\n")` (around line 290):

```diff
     stt_model = create_backend(
         precision=precision,
         model_dir=model_dir,
         num_threads=num_threads,
         force_cpu=force_cpu
     )
+    # Warm up: the first real transcription pays a one-time ~12 s init cost.
+    try:
+        import numpy as np, time
+        t0 = time.time()
+        silence = np.zeros(int(stt_model.sample_rate), dtype=np.float32)  # 1 s at the model's rate
+        stt_model.transcribe(silence)
+        stt_model.transcribe(silence)  # second pass catches lazy kernel selection
+        print(f"✓ Warmup done in {time.time()-t0:.1f}s")
+    except Exception as e:
+        print(f"WARN: warmup failed: {e}")
     print("✓ Server ready!\n")
```

- `sample_rate` is a property at `backend.py` line 52, and `transcribe(audio: np.ndarray)` is at `backend.py` line 19. Check the dtype and shape `transcribe` expects before relying on the snippet.
- Startup gets about 12 s slower and the first real use gets faster. `/etc/start_env` waits for the port, so that is fine.
- Restart Parakeet to apply it (`/home/dwemer/parakeet-api-server/start.sh` or a WSL restart).
- If silence is rejected, send a short real clip instead. `test_client.py` in the same folder may have one.

Fix 2: find who paused the game (the 88 s).
- If you paused it on purpose, the behaviour is by design: Stobe holds speech while paused.
- If you did not, the likely culprit is `CreateChatUI` in `components/STOBE/src/ChatBox.cpp` lines 5974 to 5978. It calls `world->userPause(true)` whenever the chat window opens and records `g_chatPausedGame`. No log line marks this.
- Add a log line there, for example `Log("CHAT_PAUSE: paused game by chat UI")`, and one at the matching `userPause(false)` release. Then compare against the `ACTION_QUEUE: paused` lines.
- A possible further change is to let a streamed NPC reply resume or ignore the chat-UI pause, or to not pause on voice (hotkey) chat. That is a behaviour decision for you, so I haven't specced it.

Optional: the model stream (about 29 tokens/s that time) is slow for rare tail requests. I found no code cause. `chunks_emitted` was 0, so voice synthesis only started after the whole JSON finished. Streaming the `message` field early would save about 8 s on slow replies, but I did not verify that it can be done safely.

**How to confirm the fix worked**

- Fix 1: after restarting Parakeet, say anything once to an NPC and check `stobeserver.log`. `grep -a "STT transcription completed" stobeserver.log | tail -1` should show `stt_service_ms` under about 500 for the first call (it was 11,942 before). The Parakeet `log.txt` should show the warmup line.
- Fix 2: repeat the first-chat scenario on a fresh start without pausing. `ACTION_QUEUE: paused` should not appear. The gap between `CHAT_TIMING: STREAM_LINE` and `ACTION_EXEC: SAY [Tengu]` in stobe.log should be under 1 s (it was 88 s).

**What is not settled**

- Who paused the game from about 19:50:02 to 19:51:30. If you did not press pause, the chat window is a suspect, but nothing in the log shows it.
- Whether the 10 s LLM time was DeepInfra congestion at that moment. I only have the one data point and the 400-request spread.
- Whether Parakeet's 12 s was a model or GPU cold start, or a lazy library load. Either way the warmup should remove it, but I didn't measure the cost split.
- Whether early message streaming is feasible. I did not read the streaming code.
