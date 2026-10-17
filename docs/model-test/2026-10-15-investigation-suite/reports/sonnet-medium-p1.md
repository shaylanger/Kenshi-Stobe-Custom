**Summary**

The first Tengu reply took about 25 s from the moment you spoke. About 12 s was speech-to-text (STT, Parakeet) and about 13 s was the chat reply.
- STT: Parakeet did its first transcription after a restart with no warm-up pass, so that call paid the one-time GPU initialisation. It took 11.9 s; every later call took 50-110 ms. Only this part is specific to the first message.
- Chat: about 12.8 s, but not specially slow. Every Tengu reply that session took 5-10 s, because the model writes a large JSON object (about 250 tokens) for a 113-character line, and generation is slow.

**Root cause**

Parakeet has no warm-up pass. `initialize_model()` in `/home/dwemer/parakeet-api-server/server.py` only builds the model, and `lifespan()` only checks it exists. The first real transcription therefore pays the CUDA/NeMo first-run cost.

The chat latency is a separate steady cost. Each reply is a strict-schema JSON object with about 20 fields (travel, region plan, followup, social repair and so on). With a cold prompt cache, a 12.3k-token prompt and about 28 tokens/s generation, that adds up to 8-10 s.

**Evidence**

All times are UTC, from `/var/www/html/StobeServer/log/`.
- `stobeserver.log` lines 2156964-2156999:
  - 01:49:37: `stt.php` POST received (33,582 bytes, about 1 s of speech).
  - 01:49:49: `STT transcription completed ... "stt_service_ms":11942`.
- Parakeet's own log, `/home/dwemer/parakeet-api-server/log.txt` line 106: `Transcribing: 100%|██████████| 1/1 [00:11<00:00, 11.32s/it]`. Lines 108 onward show 10-25 it/s. This is the first transcription since the service started at 16:55 local on Oct 14 (log lines 100-105).
- Warm STT calls in `stobeserver.log`: 108, 52, 49, 49, 61 ms (01:51-01:52). The only other multi-second STT calls are on Oct 12: 20,436 ms at 19:27 and 8,755 ms at 19:41.
- `server.py`: `lifespan()` (line 59) and `initialize_model()` (lines 238-296, `create_backend(...)` at 289) run no dummy transcription.
- Chat request `req_6ad0313d4e3da`, lines from 2157001 in `stobeserver.log`:
  - Pre-LLM work: 1,249 ms.
  - First LLM text: 1,060 ms.
  - `llm_total_ms` 10,016.
  - TTS: 1,451 ms.
  - Whole request: `duration_ms` 12,840.
- `audit_request.log` line 4918: 12,321 prompt tokens, 257 completion tokens, `cached_tokens` 0.
- `output_from_llm.log` line 326754 onward: the spoken line is 113 characters, but the JSON also carries `travel_*`, `region_plan_*`, `followup_update` and `social_repair_updates`, all empty or "NONE".
- Other Tengu chat calls that session (`audit_request.log` lines 4919-4926): 9.2 s, 8.1 s, 7.3 s, 9.2 s and 5.3 s. The two with a prompt-cache hit (about 4k cached tokens) were 7.3 s and 9.2 s, so caching alone doesn't explain the gap.

**What I ruled out**

- Database, event storage, memory lookup, embeddings and geo lookup: the pre-LLM stage totals 1.25 s, and the biggest piece is building the 27k-character system prompt (809 ms).
- TTS: 1.45 s for the synthesis.
- Server overload: WSL load average is about 0.03, and nothing else was queued ahead of the request.
- A cold chat prompt cache as the main cause: later requests were not clearly faster.
- A server-side failure or retry: every request returned 200 with `status:ok`.

**Proposed fix**

1. **Warm up Parakeet (removes the 12 s on the first message).** In `/home/dwemer/parakeet-api-server/server.py`, at the end of `initialize_model()` just after the `stt_model = create_backend(...)` call (lines 289-294), add a throwaway transcription:

```python
    import numpy as np
    try:
        print("Warming up (first-inference CUDA init)...")
        _ = stt_model.transcribe(np.zeros(16000 * 2, dtype=np.float32))  # 2 s silence, 16 kHz mono
        _ = stt_model.transcribe(np.zeros(16000 * 5, dtype=np.float32))
        print("✓ Warm-up done")
    except Exception as e:
        print(f"Warm-up failed (continuing): {e}")
```

   - Place it before `print("✓ Server ready!")`, so the `/health` poll in `start_native.sh` only passes once warm-up has finished. Startup is already about 22 s and will grow by roughly 12 s.
   - Silent audio may return empty text; that is fine, because only the kernel and graph initialisation matters. If a silent array is rejected, use a short real WAV through `transcribe_file()`.

2. **Optional: trim the chat output (about 2-4 s per reply).** Where the `stobe_dialogue_response` schema is built, make the rarely used fields (travel, region plan, followup, social repair) optional, or drop them from the schema on ordinary talk turns. I did not locate the exact PHP location (`grep stobe_dialogue_response` in `lib/` and `stream.php`). Because the schema is `strict`, this is a design change and needs testing.

3. **Optional: try a faster chat model or route.** A short "llmtest" request in `audit_request.log` ran at roughly 100 tokens/s, versus about 28 tokens/s for the real chat call. Try the same model without `response_format: json_schema`, or a model with faster constrained decoding.

**How to confirm the fix worked**

1. Restart Parakeet (via `/etc/start_env` or `start.sh`). `log.txt` should show a warm-up line, and the first real `POST /v1/audio/transcriptions` should show 10 it/s or better instead of 11.32 s/it.
2. After the game has been idle for more than 30 minutes, speak to an NPC. `grep "STT transcription completed" stobeserver.log | tail -1` should show `stt_service_ms` under 300, not about 12,000.
3. For the chat side, compare `Latency stage llm complete ... llm_total_ms` before and after any schema change.

**What is not settled**

- Which first-inference step costs the 11 s (CUDA kernels, cuDNN autotune, or NeMo lazy init). A warm-up pass should absorb it either way, but I have not tested the warm-up.
- Whether Parakeet stalls again after a long idle gap. The Oct 12 slow calls might be a re-init after idle, or just fresh starts, and the logs don't say.
- The time between your key press and the audio upload on the game side. That isn't logged on the server.
- Why chat generation runs at about 28 tokens/s when the same endpoint managed about 100 tokens/s in the "llmtest" runs. Strict JSON-schema decoding and the longer prompt are the likely reasons, but I have not shown it.
