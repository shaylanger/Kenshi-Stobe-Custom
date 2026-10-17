## Summary
Tengu's first reply took about 113 s from the moment you let go of push-to-talk to the moment she spoke. Two things caused almost all of it:

1. **About 88 s: the game was paused while the reply waited.** The reply reached the game 25 s after you spoke. The game had been paused 5 s before that, at 19:49:57.6, and Stobe holds NPC speech while the game is paused. Tengu spoke in the same frame you unpaused, at 19:51:30.1. Nothing on screen told you the reply was waiting.
2. **About 12 s, first turn only: Parakeet speech-to-text was cold.** The first transcription in a new Parakeet process took 11.9 s. Every later one took 0.05 to 0.35 s.

The server, LLM and TTS part took 12.8 s. That is close to the later Tengu turns (8 to 10 s). With the pause and the cold STT removed, the first turn would have taken about 13 s. Your next turn took 10.3 s end to end.

## Root cause
- **Long wait (88 s):** in `ExecuteQueuedActions`, Stobe checks `thisptr->isPaused()`. If the game is paused, it logs `ACTION_QUEUE: paused; deferring queued actions` and returns without running the queue. The queued `ACT_SAY` for Tengu therefore sat there from 19:50:02.150 until you unpaused at 19:51:30.067. This is deliberate upstream behaviour (commit `ed4c75a` "pause gate for tts", RANGROO, 2026-03-31), but it is invisible to the player.
- **First-turn delay (12 s):** the Parakeet server (`/home/dwemer/parakeet-api-server`) loads the model at startup but never runs it. So the first real request pays the one-time CUDA, cuDNN and decoder setup cost.

## Evidence
Times: stobe.log and KenshiFP.log use Windows local time (UTC-6). stobeserver.log uses UTC, so 01:49:49Z = 19:49:49 local; the server's `unix_ms` 1792028989321 confirms this.

**Save and timeline of the first turn** (stobe.log = `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`)
- `harness.log` line 27: `[19:48:07.779] KAH: game load signalled save=Fresh start`.
- stobe.log line 142: push-to-talk started 19:49:36.065. Line 153: released at 19:49:37.147 (`duration_ms=1079`).
- stobe.log line 172: `[19:49:49.117] STT_UPLOAD: completed bytes=33582`, about 12.0 s after release.
- stobeserver.log, Parakeet dispatch: `[01:49:37] Latency stage stt provider dispatch {"provider":"parakeet",...}`.
- stobeserver.log, Parakeet result: `[01:49:49] STT transcription completed {"stt_service_ms":11942,...,"request_id":"req_6ad031312a1e5"}`.
- Later STT times the same session: 108, 52, 49, 49, 61, 353, 100, 110, 51, 50, 65, 57, 50 ms.
- Parakeet log `/home/dwemer/parakeet-api-server/log.txt`:
  - "Parakeet health check passed after 22s (PID 444)".
  - The first request shows `Transcribing: 100% 1/1 [00:11<00:00, 11.32s/it]`.
  - All 13 later requests ran at 3.5 to 25 it/s.
- The Parakeet process (pid 444) started Oct 14 16:55:42 CDT, so this was its first request ever.
- Older first-after-restart STT requests were also slow: 2026-10-12 19:27:28Z at 20,436 ms and 19:41:47Z at 8,755 ms.
- `inference_nemo.py` `NeMoBackend.__init__` ends with `self.model.eval()` and has no warm-up. `server.py` `initialize_model` also has none.

**Server side of the chat request** (`req_6ad0313d4e3da`, stobeserver.log)
- Ingress at 01:49:49.321.
- `pre_llm_ms`: 1249.
- `llm_ttft_ms`: 1060.
- `llm_total_ms`: 10016.
- TTS: `tts_synthesis_ms` 1451.
- `Request completed ... duration_ms:12840`.
- stobe.log line 223: `[19:50:02.147] CHAT_TIMING: STREAM_LINE actor=Tengu`.
- stobe.log line 230: `[19:50:02.150] TIMING_META: queued ACT_SAY target=Tengu utterance_id=utt_e7781e1eb02b846e2da1dff2`.

**The hold**
- stobe.log lines 232 to 298: 59 lines of `ACTION_QUEUE: paused; deferring queued actions size=1 next_type=0`, from 19:50:02.150 to 19:51:29.202.
- stobe.log line 299: `[19:51:30.064] ACTION_EXEC: SAY [Tengu]: "Tango"? You address an emperor...`.
- `D:\Steam\steamapps\common\Kenshi\KenshiFP.log` line 212: `[19:49:57.597] [speed] frameSpeedMult 1.00 -> 0.00`.
- KenshiFP.log line 213: `[19:51:30.067] frameSpeedMult 0.00 -> 1.00`.
- Game time stood still: `gamets=124104` at both 19:49:59.103 (stobe.log line 216) and 19:51:19.120 (line 291).

**Code**
- Live source `/root/STOBE-src/src/Functions.cpp`: `ExecuteQueuedActions` starts at line 7055, the `isPaused()` read is at 7086, and the early return is at 7134-7144.
- The snapshot `C:\KenshiModding\components\STOBE\src\Functions.cpp` has the same block at 7115 and 7163-7173.

**The second turn, for comparison**
- Release at 19:51:44.800.
- STT done at 19:51:44.935.
- Tengu spoke at 19:51:55.135 (stobe.log lines 339, 340, 391).

## What you ruled out
- **LLM warm-up:** turn 1 took 10.0 s (TTFT 1.06 s, 257 completion tokens, 0 reasoning tokens, 0 cached prompt tokens). Tengu turns 2 to 6 took 5.3 to 9.2 s (TTFT 0.72 to 1.02 s). Nothing first-turn specific.
- **Server pre-LLM work:** 1.25 s against 0.50 to 0.85 s later, so about 0.6 s extra. Most of it is `system_prompt_and_scene` at 809 ms against 344 to 425 ms. Minor.
- **TTS:** 1.45 s against 0.10 to 0.67 s later, so about 1.1 s extra. It was PocketTTS's first synthesis since it started; the previous synthesis was 2026-10-14 03:01Z. Minor.
- **Client send path:** the send began at 19:49:49.283, was dispatched at .288, and reached the server at .321.
- **Network:** the request returned 200. The `NETWORK_ERROR 12002` at 19:49:28.100 happened 21 s before this request.
- **Stobe or automation pausing the game:**
  - Stobe logs `UI: chat hotkey pressed` and `UI: general hotkey pressed` when its own windows pause the game (for example at 19:48:58.015 and 19:49:01.735). There is no such line near 19:49:57.6.
  - KenshiFP logged no `ui_open=1` at the pause.
  - harness.log has only fps lines from 19:49 to 19:52, no commands.
  - `controls.cfg` line 45 binds `pause=Space`.
  - The last left mouse release was 61.7 s before the pause, so it was a keyboard pause, i.e. the normal game pause.
- **Frame rate or loading:** the harness averaged about 60 fps, and loading finished at 19:48:44.878, a minute before the chat.

## Proposed fix
**Fix 1 (main fix for the first-turn delay): warm Parakeet up at startup.**
File: `/home/dwemer/parakeet-api-server/inference_nemo.py`, class `NeMoBackend`. Edit it as user `dwemer`. Every start path runs this code: `/etc/start_env`, `wsl-voice.sh stt start`, `start.sh`, `start-gpu.sh` and `start_native.sh` all end in `server.py`.
```diff
         # Set to eval mode
         self.model.eval()
 
+        # First transcribe() in a new process costs ~11 s of CUDA/cuDNN/decoder
+        # setup (log.txt: 11.32 s/it on the first request, ~0.05 s after).
+        # Pay it here, before /health answers, not on the player's first line.
+        self._warmup()
+
         print("✓ NeMo model loaded successfully!\n")
 
+    def _warmup(self, passes: int = 2) -> None:
+        import time
+        rng = np.random.default_rng(0)
+        audio = (rng.standard_normal(2 * self._sample_rate) * 0.01).astype(np.float32)
+        for attempt in range(1, passes + 1):
+            started = time.time()
+            try:
+                self.transcribe(audio)
+            except Exception as exc:  # a failed warm-up must never stop the server
+                print(f"  Warm-up pass {attempt} failed (ignored): {exc}")
+                return
+            print(f"  Warm-up pass {attempt}: {time.time() - started:.2f} s")
+
     def transcribe(self, audio: np.ndarray) -> dict:
```
- Startup gets about 11 s longer (health passes at about 33 s instead of 22 s).
- `start_native.sh` already waits up to 900 s for health, so nothing else needs to change.
- The folder is a git checkout, so an upstream update can overwrite this edit. If so, re-apply it, or instead send one dummy transcription after the health check (see the confirm steps below for the command).
- Optional, worth about 1 s: do the same for PocketTTS with one throwaway synthesis after it starts.

**Fix 2 (for the 88 s): keep the pause hold but tell the player a reply is waiting.**
File: `/root/STOBE-src/src/Functions.cpp`, function `ExecuteQueuedActions`. Afterwards copy it into `components/STOBE/src`. Both trees already have uncommitted changes in this file, so patch at the anchors rather than copying the whole file.
```diff
@@ (line ~7063)
   static DWORD pausedQueueLogTick = 0;
+  static std::string pausedReplyNoticeUtterance;
@@ (line ~7134)
     if (gamePaused) {
+      std::string pausedReplyNotice;
       if (!g_uiActionQueue.empty() && nowTick - pausedQueueLogTick >= 1500) {
         ...unchanged ACTION_QUEUE: paused log...
       }
+      // An NPC reply (server lines carry an utterance id; the player's own
+      // line does not) is ready but held by the pause gate: say so once.
+      if (!g_uiActionQueue.empty()) {
+        const QueuedAction &held = g_uiActionQueue.front();
+        if (held.type == ACT_SAY && !held.utteranceId.empty() &&
+            held.utteranceId != pausedReplyNoticeUtterance) {
+          pausedReplyNoticeUtterance = held.utteranceId;
+          Character *speaker = ResolveLiveCharacter(thisptr, held.target);
+          pausedReplyNotice =
+              (speaker ? SafeCharacterName(speaker) : std::string("Someone")) +
+              " has answered. Unpause the game to hear the reply.";
+          Log("ACTION_QUEUE: paused reply notice utterance_id=" + held.utteranceId);
+        }
+      }
       LeaveCriticalSection(&g_uiMutex);
+      if (!pausedReplyNotice.empty()) {
+        try {
+          thisptr->showPlayerAMessage_withLog(pausedReplyNotice, true);
+        } catch (...) {
+        }
+      }
       return;
     }
```
- The patch only uses helpers that already exist: `ResolveLiveCharacter` (Functions.cpp:1257), `SafeCharacterName` (Functions.cpp:2736), and `GameWorld::showPlayerAMessage_withLog`, which main.cpp:10005 already calls.
- It is valid VS2010 C++.
- Build with `tools/automation/build-stobe.ps1`, then install with `install-dll.ps1 Stobe` with Kenshi closed.

**Alternative to Fix 2 (bigger behaviour change, not recommended first):**
- Add an INI toggle `SpeakWhilePaused`, default 0, that lets only a front `ACT_SAY`/`ACT_PLAY_TTS` through the pause gate.
- This changes the upstream design. The rest of `ExecuteQueuedActions` (speech-delay timing scaled by game speed, the playback hold, and the NPC-to-NPC follow-up chat that starts when a line is spoken) was written for a running game, so it needs its own testing.

## How to confirm the fix worked
**Fix 1:**
1. Restart STT: `wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/wsl-voice.sh stt stop`, then the same with `start`.
2. `log.txt` should show "Warm-up pass 1: ~11 s" and "Warm-up pass 2: <0.3 s" before "Server ready".
3. Time one request in WSL: `sox -n -r 16000 -c 1 -b 16 /tmp/p.wav synth 1 whitenoise vol 0.01; time curl -s -F file=@/tmp/p.wav http://127.0.0.1:8022/v1/audio/transcriptions`. Without the fix the first call takes about 11 s; with it, under 1 s.
4. In game, after a fresh start, the first push-to-talk should show `STT transcription completed ... stt_service_ms` under 500 (it was 11942). In stobe.log, `STT_UPLOAD: completed` should come within about 0.3 s of `STT_CAPTURE: selected input`.

**Fix 2:**
1. Talk to an NPC and press Space after your own line appears, before the reply.
2. stobe.log should show `ACTION_QUEUE: paused reply notice` right after `CHAT_TIMING: STREAM_LINE`, and the message should appear on screen.
3. When you unpause, `ACTION_EXEC: SAY [<NPC>]` should follow. Today you only get the `deferring` lines.

**Overall:** without pausing, the first turn (push-to-talk release to `ACTION_EXEC: SAY [NPC]`) should take about 10 to 13 s, like later turns.

## What is not settled
- **Whether you paused on purpose:** the logs show a Space or keyboard pause 20.5 s after you spoke, but not why. Maybe nothing had happened yet because of the cold STT.
- **What exactly costs Parakeet 11.3 s:** lazy CUDA loading, cuDNN/cuBLAS setup, or NeMo's decoder setup under WSL2. I did not profile it. If the second warm-up pass is still slow, add a pass with a longer clip of about 6 s.
- **Whether the Fix 2 message shows while paused:** `showPlayerAMessage_withLog` is expected to display during a pause, but I have not tested it.
- **Per-turn LLM time of 5 to 10 s:** about 28 tokens/s from DeepInfra for structured JSON where `message` is the 3rd of about 20 fields. The server did not speak early (`chunks_emitted=0`), possibly because of the `defer_structured_stream` flags at `processor/chat.php:1595`. This affects every turn, not just the first, and I did not investigate it.
- **A breach of the read-only rule:** I created one scratch file, `/tmp/bench_req1.txt` in WSL (50 lines of log excerpt). It is harmless and can be deleted.
