## Summary
Your first line to Tengu ("What's up, Tango?", spoken at 19:49:36) did not play until 19:51:30, about 113 s later. Three delays add up to that:
1. **Game paused: about 88 s, the biggest part.** Tengu's reply reached the game at 19:50:02, but the game had been paused since 19:49:57. Stobe holds every queued NPC line while the game is paused, so the reply only played at 19:51:30, the same moment the game was unpaused.
2. **Speech-to-text cold start: about 12 s, first line only.** Parakeet took 11.9 s on its first transcription. Every later one took 50–350 ms.
3. **LLM plus TTS: about 12.8 s.** This is normal for this setup: later Tengu turns took 5–9 s for the LLM alone.

Delay 2 is the one that hits only the first response. Delay 1 is the one you felt most.

## Root cause
- **Pause:** Stobe's action-queue update returns early whenever `isPaused()` is true. The reply sat in the queue and Stobe gave no sign that it had arrived (`components/STOBE/src/Functions.cpp` lines 7112–7119 and 7163–7172).
- **Cold start:** the Parakeet STT server loads the model at startup but never runs a test transcription. The first real request pays the one-time CUDA/NeMo setup cost of about 11 s.

## Evidence
**Delay 2, speech-to-text:**
- `stobe.log` 19:49:37.147: `STT_CAPTURE: selected input=Microphone (Blue Snowball ) duration_ms=1079`. Then 19:49:49.117: `STT_UPLOAD: completed bytes=33582`. That is 12 s.
- `/var/www/html/StobeServer/log/stobeserver.log` (times there are 6 h ahead of the game log):
  - `[2026-10-15 01:49:37] Latency stage stt provider dispatch {"provider":"parakeet"...}`
  - `[01:49:49] STT transcription completed {"stt_service_ms":11942}`
  - Later calls: 108, 52, 49, 49, 61, 353 … 50 ms.
- `/home/dwemer/parakeet-api-server/log.txt`: the server started at 16:55 and reported "Server ready" with no test transcription. The first request logged `Transcribing: 100% 1/1 [00:11<00:00, 11.32s/it]`; the next ones ran at 10–25 it/s. So the 11 s is spent inside the model on its first inference, not in the upload.
- `server.py` `initialize_model()` (around lines 238–295) calls `create_backend(...)`, then prints "✓ Server ready!". It never calls `transcribe`.

**Delay 3, LLM and TTS (server log, request `req_6ad0313d4e3da`):**
- Prep before the LLM call: `pre_llm_ms:1249`.
- LLM: `llm_ttft_ms:1060`, `llm_total_ms:10016`; 257 completion tokens, `cached_tokens:0`.
- TTS: `tts_synthesis_ms:1451`.
- Whole request: `Request completed duration_ms:12840` at 01:50:02.

**Delay 1, pause:**
- `stobe.log` 19:50:02.149: `Queuing SAY for Tengu`. Then 19:50:02.150: `ACTION_QUEUE: paused; deferring queued actions size=1 next_type=0`. That line repeats every 1.5 s through 19:51:29.202. Then 19:51:30.064: `ACTION_EXEC: SAY [Tengu]`.
- `KenshiFP.log`: `[19:49:57.597] [speed] frameSpeedMult 1.00 -> 0.00` and `[19:51:30.067] [speed] frameSpeedMult 0.00 -> 1.00`. These mark the game pausing and unpausing.
- Game time in `stobe.log` stayed at `gamets=124104` from 19:49:59 to 19:51:19, then moved again (124271 at 19:51:35).
- The second turn was not paused. STT took 108 ms and the line played the moment it arrived (19:51:55.135 `ACTION_EXEC` right after `Queuing SAY`).

## What you ruled out
- **Server work before the LLM call:** 1.25 s in total. Memory lookups took 36 ms, the system prompt 809 ms.
- **LLM first-turn slowness:** time to first text was 1.06 s. The 10 s total matches later turns (7.3–9.2 s for Tengu).
- **TTS:** synthesis took 1.45 s. The clip played with `download_ms=0`.
- **Upload or network:** the server received the upload 2 ms after the request started.
- **Chat window pause:** `CreateChatUI` pauses the game while the chat box is open, but the box was not open then. It was used once at 19:48:58 for Persut and closed at 19:49:03. Your line came from push-to-talk.
- **Mods pausing the game:** KenshiFP has no pause call. The Auto-Pause-on-Load mod only acts at load time.

## Proposed fix
**Fix 1 (removes the first-line speech-to-text delay): warm up Parakeet at startup.**
In `/home/dwemer/parakeet-api-server/server.py`, at the end of `initialize_model()`, run one dummy transcription before "Server ready". The startup script waits for the health check (up to 900 s), so the server only counts as up once it is warm.
```diff
     stt_model = create_backend(
         precision=precision,
         model_dir=model_dir,
         num_threads=num_threads,
         force_cpu=force_cpu
     )
+    # Warm-up: the first CUDA inference costs ~11 s (kernel load/autotune);
+    # pay it here instead of on the player's first voice line.
+    try:
+        import time
+        import numpy as np
+        t0 = time.time()
+        warm = (np.random.default_rng(0).standard_normal(16000) * 0.01).astype(np.float32)
+        stt_model.transcribe(warm)   # 1 s of quiet noise at 16 kHz
+        stt_model.transcribe(warm)
+        print(f"✓ Warm-up transcription done in {time.time() - t0:.1f}s")
+    except Exception as e:
+        print(f"WARN: STT warm-up failed: {e}")
     print("✓ Server ready!\n")
```
Then restart STT: `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh stt stop`, then `... stt start`.

Optional: `log.txt` also says `No conditional node support for Cuda ... No cuda-python module` (CUDA graphs disabled, so decoding is slower), even though line 12 lists cuda-python 13.4.1. Fixing that venv import would make every STT call a little faster. It does not cause the 11 s.

**Fix 2 (the 88 s): make a reply that arrives during a pause visible.** Stobe holds speech on purpose while paused: Kenshi's bubble timers do not run then. So the smallest safe change is a one-time notice, not playing speech during the pause. In `Functions.cpp`, in the `if (gamePaused)` block around line 7163:
```diff
     if (gamePaused) {
+      static unsigned int pausedNoticeSerial = 0;
+      if (!g_uiActionQueue.empty()) {
+        const QueuedAction &head = g_uiActionQueue.front();
+        if ((head.type == ACT_SAY || head.type == ACT_PLAY_TTS) &&
+            head.actor.serial != pausedNoticeSerial) {
+          pausedNoticeSerial = head.actor.serial;
+          Character *who = ResolveLiveCharacter(thisptr, head.actor);
+          thisptr->showPlayerAMessage_withLog(
+              "[STOBE] " + (who ? who->getName() : std::string("An NPC")) +
+              " has replied - unpause to hear it.", false);
+        }
+      } else {
+        pausedNoticeSerial = 0;
+      }
       if (!g_uiActionQueue.empty() && nowTick - pausedQueueLogTick >= 1500) {
```
This edits the same paused branch shown in the evidence; `ACT_SAY` is in `Globals.h:81`. Rebuild with `tools/automation/build-stobe.ps1`, then install with `install-dll.ps1 Stobe` (Kenshi closed).

A bigger alternative: let `ACT_SAY` / `ACT_PLAY_TTS` run while paused, so the audio plays and the bubble is kept alive. The TTS hold already keeps it alive through `speechTextTimer` (lines 7185–7194). But the speech-delay and hold logic around lines 7139 and 7175 counts game time, so this needs more testing. Choose this only if you want replies to talk during a pause.

**Fix 3 (optional, every turn):** the LLM sends nothing until the full JSON is done (`chunks_emitted:0`, `actions_streamed:false`), so TTS starts only after `llm complete`, about 9 s after the first text. Streaming the subtitle field into TTS early would cut every reply by several seconds. That is a larger server change and not the cause of this report.

## How to confirm the fix worked
- **Fix 1:** after restarting STT, `log.txt` shows `✓ Warm-up transcription done` before `Server ready`. Load the save and speak one line. `grep stt_service_ms /var/www/html/StobeServer/log/stobeserver.log | tail -1` should show under about 500 ms, instead of about 11942. Before the fix, the first line after every STT restart shows about 11–12 s.
- **Fix 2:** speak to an NPC, press Space (pause) before the reply arrives. The "[STOBE] Tengu has replied - unpause to hear it." notice appears once. `stobe.log` still shows `ACTION_QUEUE: paused` and then `ACTION_EXEC: SAY` on unpause.

## What is not settled
- **Who paused the game at 19:49:57.** It was not Stobe's chat box and not KenshiFP. A Space press (or Kenshi's own pause) is likely, perhaps because no reply had come about 20 s after speaking, but no log records the key. If you did not pause it, check Kenshi's settings for a pause-on-focus-loss option.
- Whether the `cached_tokens:0` on the first LLM call (4096 on later calls) cost meaningful time. The 10 s total looks normal next to later turns.
- The warm-up input (quiet noise) is an assumption. If NeMo still needs a longer clip to load every kernel, the first real line could still be slower than later ones. Check with the confirm step above.
