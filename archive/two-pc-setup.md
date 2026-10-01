# Two-PC setup (migrated 2026-09-29), HISTORICAL

> **Reverted 2026-09-30.** The 5090 again runs Kenshi and the Dwemer distro with PocketTTS. The 4080 will run only a local LLM for background jobs. See CLAUDE.md. What follows describes the 2026-09-29 attempt, kept for reference: the PocketTTS setup, the latency logging and the benchmarks.

The Dwemer/STOBE stack moved off the 5090 so Kenshi and a local dialogue LLM fit on it together. The Dwemer stack used about 9 GB of VRAM there.

## Machines
| | Main / gaming PC | Server PC |
|---|---|---|
| Hostname | `DESKTOP-JFLPK99` (this PC) | `DESKTOP-NQQPA73` |
| GPU | RTX 5090 32 GB | RTX 4080 16 GB (sm_89) |
| LAN IP | `172.16.1.147` | `172.16.1.100` |
| Runs | Kenshi, RE_Kenshi STOBE plugin, Qwen (started by hand) | DwemerDistro.exe, WSL `DwemerAI4Skyrim3`: Apache/STOBE, PostgreSQL, background processor, STT, PocketTTS |
| Must not run | the local Dwemer distro or its TTS/STT | local Mistral 24B |

- **The 4080 distro is the authoritative copy.** Key STOBE files and the DB state matched the 5090 by SHA-256 check. Don't migrate it again.
- 4080 launcher: `C:\DwemerDistro\DwemerDistro.exe` (v3.3.34). It was copied from the 5090 without the VHDX.
- Ping between the PCs is under 1 ms.

## Request path
Kenshi (5090) → STOBE `172.16.1.100:18083` (4080) → Qwen `172.16.1.147:8090` (5090) → STOBE parse/actions + PocketTTS (4080) → Kenshi.
- `StobeCustom.ini` on the 5090: `ServerHost=172.16.1.100`, `ServerPort=18083`.
- In WSL, Apache listens on 8083. Windows forwards LAN port 18083 to it.

## LLM routing (4080 DB, checked 2026-09-30)
- **Everything goes through OpenRouter again.** On both profiles, connector 4 (DeepSeek V4 Flash `:nitro`) is used for primary, response, diary, dynamic and relationship calls. Connector 11 (Mistral Small 3.2) handles middle-term and background-life calls. Connector 6 (Gemini Flash Lite) handles secondary and autochat calls.
- Connector 19 "Local Qwen 5090" (`http://172.16.1.147:8090/v1`, `Bearer local`) and connectors 17 and 18 (local Mistral) still exist but are unused.
- **Why Qwen was dropped (2026-09-30):** Qwen, PocketTTS and Kenshi together on the 5090 maxed out its VRAM, and the LLM slowed down.
- **Possible later plan:** run Kenshi on the 4080 and use the 5090 only for the LLM and PocketTTS. It isn't scheduled.

## Qwen (5090, shelved)
- Model: Qwen3-30B-A3B-Instruct-2507 Q5_K_M at `C:\Users\Shay\StobeLocalLLM5090\models\qwen30_moe_q5\`. It is served by `C:\Users\Shay\StobeLocalLLM5090\llama-cuda\llama-server.exe`.
- Config: 16K context, 1 slot, Q8 KV cache, flash attention, reasoning off, bound to `0.0.0.0:8090`, metrics on. It uses about 23.6 GB of VRAM, which leaves about 9 GB for Kenshi.
- **Started by hand only:** `C:\Users\Shay\Desktop\Start STOBE Qwen.cmd` (a copy is `StobeLocalLLM5090\start-qwen-stobe.cmd`). Close the window or press Ctrl+C to stop it.
- Why Qwen: average TTFT on the Malzin prompt was gpt-oss 20B 0.55 s, **Qwen3 30B A3B 0.74 s**, Mistral 24B 1.75 s, Qwen3 32B 1.93 s, Gemma 27B 2.39 s and DeepSeek on OpenRouter 3.08 s (with a 7.1 s spike). Known weakness: Qwen sometimes invents context details. That is what the play-test should watch for.

## TTS (4080)
- **Selected: Python PocketTTS** in `/home/dwemer/pocket-tts`. `start.sh` calls `start-gpu.sh`, and `.dwemerdistro-port` is 8024. It uses torch 2.11.0+cu128. `http://127.0.0.1:8024/health` should report `"device": "cuda"`. Timings: first call about 4.6 s (it builds the speaker state), warm calls 2.7–3.0 s.
- The audio.cpp PocketTTS (port 8086) was built for the wrong GPU arch ("no kernel image"). It was disabled by removing `/home/dwemer/audio.cpp/start.sh`; nothing was deleted. A rebuild would need `CMAKE_CUDA_ARCHITECTURES=89`, and it was abandoned as too slow.
- Chatterbox (8023): its venv was CPU-only torch and is now torch/torchaudio 2.7.0+cu128 (`device: cuda`). It still takes about 6 s, against about 2 s on the 5090, so it is not used.
- TTS connectors: 1 Pocket TTS Default (`pocket_tts`, `http://127.0.0.1:8024`, active), 2 XTTS (8020), 3 Chatterbox (8023), 4 OmniVoice (8021).
- `core_profiles.tts_connector_id` (not `tts_connector`) is 1 on both profiles (checked 2026-09-30).

## Latency instrumentation (live 4080 copy only, logging only)
Backups: `/var/www/html/StobeServer/_latency_backup_20260929/`. All edited files passed `php -l`. These edits are **not** in ss-merge.
| File | Adds | Log message |
|---|---|---|
| `processor/chat.php` | `pre_llm_ms` (request arrival to prompt built) | `Latency stage pre-llm complete` |
| `connector/openaijson.php` | `llm_ttft_ms` (first streamed text delta, keyed by `request_id`) | `Latency stage llm first text` |
| `lib/chat_helper_functions.php` | `request_elapsed_ms`, `unix_ms` on `output_to_plugin` | (existing entries) |
| `tts/tts-pockettts.php` | `tts_synthesis_ms` (wall-clock synthesis) | |
- `speech.duration_ms` is the **audio clip length**, not synthesis time.
- `audit_request` already records connector, model, HTTP status, `duration_ms`, stream flag and token counts.
- Health-check TTFTs: local Qwen about 490 ms cold and about 56 ms warm on tiny prompts; DeepSeek about 1.75 s. These were not measured on real ~8K dialogue prompts.

## Pre-play checklist (4080)
Don't assume a service is up just because WSL is running. Check these ports:
`8083` Apache/STOBE · `5432` PostgreSQL · `8082` MiniMe · `8022` Parakeet · `8024` PocketTTS (cuda) · `12346` background processor.
- The background processor's `service/start.sh` lost its exec bit once. Start it with `bash /var/www/html/StobeServer/service/start.sh`.
- Don't start the Dwemer distro on the 5090.
