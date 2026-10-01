# STOBE Training Data Archive

This directory preserves data that may later be used to train, distill, or evaluate a smaller STOBE/Kenshi dialogue model.

## Live capture

`live/YYYY-MM-DD/events.jsonl` is append-only and survives Kenshi/STOBE restarts. Records are joined by `request_id`.

Current event types:
- `llm_exchange`: exact LLM request/messages, raw provider result, model, token usage, cache metadata, timing, and errors.
- `chat_turn_final`: player input plus STOBE's final sanitized dialogue, validated actions, negotiation state, and late directives.

`live/game-logs/` continuously mirrors game-side logs that Kenshi normally resets on launch.
`live/raw-log-archives/` permanently mirrors server logs whenever `stobe-rotate-logs` runs.

The entire `live/` directory is intentionally not committed to Git because it can grow indefinitely.
## Historical material

`historical/server-log-archives/` contains the server log archives that existed before permanent capture was added.
`historical/server-log-snapshots/` contains a non-destructive snapshot of the live server logs taken when this archive was created.

See `historical/CATALOG.md` for the project documents, test runs, bugs, patches, and regression sources that are useful as labels/evaluation data.

## Later dataset construction

Do not train directly on every raw record. Build a curated dataset by joining `llm_exchange` and `chat_turn_final` on `request_id`, then use game logs/test results to determine whether the response/action was actually good.

Useful labels include:
- accepted response vs known bug
- correct/incorrect action
- action actually verified in Kenshi
- relationship/personality consistency
- hallucinated or unsupported fact
- schema/format validity
- latency and token cost

Known bugs are especially valuable negative examples. Corrected behavior and passing regression runs are preferred positive examples.

## Shadow mode

The current shadow model is Qwen3.5-9B Q4_K_M running through the existing 5090 llama.cpp build.

- Local API: `http://127.0.0.1:8091/v1`
- Context: 16K
- Thinking/reasoning: off
- Quantized model weights: about 5.78 GB
- DeepSeek remains authoritative for all NPC speech/actions.
- Shadow inference never dispatches actions or TTS.

Use the desktop shortcuts:
- `Start STOBE Shadow Mode.cmd`
- `Stop STOBE Shadow Mode.cmd`
- `STOBE Shadow Report.cmd`

Each shadow turn records local TTFT, total generation time, queue delay, token usage, structured-output validity, response text, and GPU/VRAM telemetry. The matching authoritative `llm_exchange` records DeepSeek TTFT and total request time. `tts_output` records PocketTTS synthesis time and whether shadow mode was enabled.
