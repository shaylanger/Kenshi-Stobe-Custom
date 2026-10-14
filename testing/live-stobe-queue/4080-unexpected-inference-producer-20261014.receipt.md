# Private 4080 background inference producer identified

Read-only native/backend metadata scans were performed during the model owner's request HOLD. This operator has sent no NPC chat, profile UI, offer, acceptance or model request. All request text/prompt/response/key fields were excluded from emitted data.

Native last20MB of64,740,398-byte Stobe log: SERIAL_HTTP332, HOOK_LOAD_PROBE26, LOAD_SYNC1, CHAT_THREAD1, PROFILE_PORTRAIT54. Latest matched load/chat completion metadata was2026-10-14 09:27:34–09:27:43(device local clock); no recent explicit TEST_INBOX say/BORED/REACTION/RECHAT records appeared in this bounded scan. This does not prove no older active request.

Guarded private root `/tmp/stobe-standalone4080/site` backend audit metadata showed recurring background `memory_summary_generate` completions:

| Request | NPC | UTC log time | Status | Prompt/completion tokens |
|---|---|---|---|---|
| req_6acfb40ba3c92 | Boss Logan |16:56:07|ok|426/526|
| req_6acfb4ae7cb64 | Dust Bandit |16:59:23|ok|1248/853|
| req_6acfb59c275c1 | Dust Bandit |17:03:15|ok|1068/822|
| req_6acfb756173c0 | Dust Bandit |17:10:26|ok|1175/620|
| req_6acfb7b6e1a5b | Hungry Bandit |17:11:39|ok|487/377|
| req_6acfb8beb07db | Dust Bandit |17:16:18|ok|1285/542|
| req_6acfba0e18da2 | Dust Bandit |17:22:05|ok|1099/752|

Latest chat full-capture entry remains old Matsuyo `req_6aced4aa5375e` at01:04:00. The current active334-token slot cannot be conclusively bound until its own completion/start metadata is observed, but independent background summary jobs are proven inference producers. A manual-test request hold or pausing the game alone does not stop these jobs.

Root, private_model_performance_recovery and5090_wsl_runtime_recovery were notified. Coordinate the private background worker only at an authorized boundary for benchmarking, restore it afterward, and preserve memory functionality for social validation; do not treat the busy slot as proof of active gameplay tests.

Backend metadata body SHA `5A2F8A2D7E35101BCF2B2533DAB9E0A7A6A3AAB5ED33EEB2186B0B5F66B69D6B`, exit0 in1.402seconds. Native scan exit0 in1.948seconds. No services/processes/game state were changed.
