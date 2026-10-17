BENCH-haiku-high-p1 report (read-only; no files, services, DB or game state changed)

SUMMARY
The first Tengu reply after loading the save took about 25 s from the end of Shay's speech to the line appearing (stop at 19:49:37.141, Tengu line at 19:50:02.147 local). About 12 s of that is speech-to-text: the first transcription of the session took 11.9 s inside the Parakeet STT service, while warm calls take 40-110 ms. The rest is normal per-reply cost (LLM about 10 s, TTS 1.5 s, pre-LLM 1.2 s), and the first call of each of those was also a little slower. Later replies from the same session took 9-10 s from send to line. Two fixes: keep the STT model warm, and stop waiting for the whole structured reply before the line is shown or voiced.

ROOT CAUSE
Primary: the Parakeet STT model answers the first request after an idle period slowly. The slow call happens inside the Parakeet process (stt_service_ms = 11942), not in the game, the PHP layer or the network. The process itself was not restarted. The pattern repeats on every cold call in the log, each after an idle gap:
- 2026-10-12 19:27:28: 20436 ms
- 2026-10-12 19:41:47: 8755 ms, after an 822 s (13.7 min) gap
- 2026-10-13 03:14:59: 1667 ms, after a 19326 s (5.4 h) gap
- 2026-10-15 01:49:49 (local 19:49:49): 11942 ms, after a 163610 s (45 h) gap
Warm calls after gaps of 7 s, 91 s, 116 s and 258 s took 125, 100, 108 and 353 ms. The cold mechanism is not settled (see below), but the threshold is between about 4 and 14 minutes idle.
Secondary, every reply: the server waits for the whole structured JSON reply before sending anything to the game. The game got the line exactly when the server finished (server "Request completed" 12840 ms). The log shows "structured_json":true and "chunks_emitted":0.

EVIDENCE
Clock: server log time = local + 6 h (verified by matching gamets 123829 and the text "What's up, Tango?").
Game log D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log (session started 19:47:51 local):
- 19:49:36.065 STT_CAPTURE recording started; 19:49:37.141 stop requested (about 1.1 s of audio)
- 19:49:49.117 STT_UPLOAD completed (12 s after stop)
- 19:49:49.288 CHAT: dispatched inputtext to StobeServer
- 19:50:02.147 CHAT_TIMING STREAM_LINE actor=Tengu (line 223)
Server log /var/www/html/StobeServer/log/stobeserver.log, same request (server time):
- 01:49:37 stt.php upload received (2 ms in), dispatched to Parakeet 127.0.0.1:8022 at +3 ms
- 01:49:49 "STT transcription completed", stt_service_ms 11942 (request_elapsed 11945)
- 01:49:50 pre-llm complete, pre_llm_ms 1249 (system_prompt_and_scene 809 ms)
- 01:49:51 llm first text, llm_ttft_ms 1060
- 01:50:00 llm complete, llm_total_ms 10016 (llm_after_first_text 8956), "chunks_emitted":0, "structured_json":true
- 01:50:00 tts start (pocket_tts, 127.0.0.1:8086); 01:50:02 TTS audio synthesized, tts_synthesis_ms 1451
- 01:50:02 Request completed, duration 12840 ms
Warm comparison, second reply (game 19:51:44.941 send, line 19:51:55.129): STT 108 ms, pre-LLM 590 ms, TTFT 815 ms, llm_total 9194 ms, TTS synth 284 ms.
Third reply (19:52:03.433 send, line 19:52:12.596): STT 52 ms, pre-LLM 611 ms, TTFT 1015 ms, llm_total 8063 ms, TTS 376 ms.
First-to-line totals: reply 1 12.9 s from send (about 25 s from speech stop), reply 2 10.2 s, reply 3 9.2 s.
Parakeet: /home/dwemer/parakeet-api-server/server.py. Route /v1/audio/transcriptions takes multipart field "file" (line 166-169). Model is NeMo fp32 on CUDA (log.txt: "moving model to cuda"); cuda-python is missing, so CUDA graphs are off (a speed loss on every call, not a cold-start cause).
Chat output path: lib/chat_helper_functions.php ~14928-15240 (streaming emit; sentence-level TTS queue exists for the non-JSON path around 15000-15010 and 15184-15240); processor/chat.php ~1766 logs "LLM stream response generated" after the full result.
PocketTTS first synth 1451 ms vs 103-376 ms on later calls (tts/tts-pockettts.php:1755 logs "Latency stage tts start").

WHAT YOU RULED OUT
- Game side: the player line was queued at once (PLAYER_SAY queued immediately, CHAT_TIMING); no hold or timer in the chat path. The 1.1 s recording is not the cause.
- Upload and PHP: stt.php received the audio 2 ms after the stop and dispatched in 3 ms.
- Network: loopback 127.0.0.1.
- Parakeet restart or model load: PID 444 has been running since before the slow call (etime 6 h 55 min at check time); no reload was logged in that window.
- Swap: pswpin = 0 and pswpout = 0 since WSL boot (2026-10-14 16:54); VmSwap 0 kB. Parakeet RssFile is only 2.8 MB, so the weights are anonymous memory that was never evicted to swap.
- Windows VRAM pressure now: nvidia-smi shows 8.3 of 32.6 GB used, 6% GPU use. It is not known whether VRAM was tight during the idle period.
- LLM as the cold cause: the LLM time is similar warm (5-9 s) and cold (10 s). It is slow every reply, not only the first.
- Parakeet's /health endpoint does not run the model, so it would not warm it.

PROPOSED FIX
Fix 1 (removes the 12 s cold STT; apply first). Keep Parakeet warm with a silent 1 s transcription every 120 s, started the same way as tools/automation/wsl-cache-trim.sh (from /etc/start_env, under setsid nohup). New file tools/automation/stt-keepalive.sh (WSL root):
```
#!/bin/bash
# Keep the Parakeet GPU model warm: one 1 s silent transcription every 120 s (warm calls ~50-110 ms).
WAV=/tmp/stt-silence-1s.wav
if [ ! -f "$WAV" ]; then
  python3 -c 'import wave; w=wave.open("/tmp/stt-silence-1s.wav","wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(b"\x00\x00"*16000); w.close()'
fi
while true; do
  curl -s -o /dev/null --max-time 60 -F "file=@$WAV" -F "response_format=text" http://127.0.0.1:8022/v1/audio/transcriptions
  sleep 120
done
```
Start it from /etc/start_env next to the cache trim. It only does something while Parakeet listens on 8022 (curl fails silently otherwise). It bypasses stt.php, so stobeserver.log is not touched. Cost: about 50 ms of GPU every 2 minutes. Optionally also warm PocketTTS at 127.0.0.1:8086 with one short synthesis from the same loop (copy the request body from tts/tts-pockettts.php); this would cut the 1.1-1.4 s first-synth cost.
Fix 2 (cuts every reply by about 4-8 s; the bigger fix for everyday use): stream the reply text as it arrives. Today the structured JSON reply emits no chunks, so the line and TTS wait for the whole generation. In lib/chat_helper_functions.php, the structured-JSON stream path (~15184-15240) should extract the "message" string from the partial JSON as it arrives and feed completed sentences into the same $ttsQueue that the plain-text path already uses (~15000-15010). Then the first sentence can show and voice after about 1-2 s. This needs a reader to confirm the exact parser, so it is not verified here.
Fix 3 (check, not a fix yet): the generation runs about 9 s for 113 characters after the first token. Check the DeepInfra connector request for reasoning or thinking output, and whether max_tokens or response_format slow it down.

HOW TO CONFIRM
- Fix 1: restart the game, wait 15 minutes idle, then talk. In stobeserver.log, the "STT transcription completed" stt_service_ms should stay under about 200 ms (it was 11942 before). Stobe log: CHAT_SEND_STAGE begin to STREAM_LINE should drop about 12 s on the first reply.
- Fix 2: the first STREAM_LINE should arrive about 1-2 s after LLM first text, with chunks_emitted > 0 in "LLM stream response generated".
- Check the mechanism: add timers around the transcribe call in server.py's /v1/audio/transcriptions handler, then compare a call after 15 minutes idle with a warm call; sample nvidia-smi memory.used on Windows across the idle period.

WHAT IS NOT SETTLED
- Why Parakeet goes cold after idle. The evidence points inside the process and not to swap, and the process was not restarted. Candidates are GPU-side eviction of idle allocations (WDDM/WSL GPU paravirtualisation) or a CUDA-side re-init. VRAM was not sampled at the time, so the cause is unproven. The timers above would settle it.
- Whether the cold penalty also hits when Kenshi is running and VRAM is busy.
- Whether typed chat (no STT) shows the same reply delay; the LLM part should be the same.
- The NETWORK_ERROR 12002 at stobe.log 19:49:28.100 (an HTTP timeout on an event push, not on the chat path). The server log shows the trade request taking 3.3 s, and the link between the two is not established.
- Why DeepSeek takes about 9 s to finish 113 characters (reasoning output or provider queueing is unchecked).
- The speech-stop-to-key-release delay was not measured; only the server and game timings above were.

Read-only: no DB query, no POST, no service restarted, nothing written. pending-fixes\ and the HANDOFF file were not read. Git was not used.
