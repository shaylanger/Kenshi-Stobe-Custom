# KAH-TRAVEL-DEST-BASELINE-001 — 5090 receipt

- Terminal status: **PASS — NPC-selected preference captured; no consent or trip was inferred.**
- Completed: 2026-10-14 01:03 UTC.
- Rig/process: 5090 main instance 1, PID 86884, world `kah-5090-legacy-auth-20261013-1740`; game time advancing, paused=0, speed=1.0, isolation ON, focused=0, DISPLAY2.
- Loaded Stobe SHA-256: `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`.
- AutomationHarness SHA-256: `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`.
- Backend: isolated local service on port 8083; HTTP 200, database/schema ready. PHP manifest at dispatch: 412 files, SHA-256 `d8a2b620dfafff071ea2b5b19344c56b47cd2bf83bef87343312c40ed5d865b7`.
- Session gate: ready/current campaign, normal legacy load (new_game=false), empty load identity, receipt/canonical fingerprints matched. No identity or profile mutation was performed.

## One-turn dispatch

- KAH request: `k1791939604997_53641_1`; one dispatch only.
- Native TEST_INBOX at 2026-10-13 19:00:05.241 local (2026-10-14 01:00:05.241 UTC): speaker Beak, target Tsetseg (#3191284224/1), exact text: “If you were free to choose, what place or region would you want to travel to, if any? I’m only asking what you’d choose; we aren’t agreeing to a trip.”
- Backend correlation: `req_6aced4154d05e`, chat, status=ok, HTTP 200, 3146 ms, streamed; model `deepseek-ai/DeepSeek-V4.1-Flash`. Full prompt/history and structured result remain in `/var/www/html/StobeServer/log/chat_llm_full_capture.log`, line 146 at readback, record SHA-256 `2875c4785fd0031c7d96a358dbfbed3f0996702fecb017b9258d595a7380a55c`. The log file at readback was 9,680,621 bytes, SHA-256 `e541e94b113df8c5c54c589c16a6765a36c6b0b85d054f7043c2df11c888a85f`. Prompt message count=4; user message SHA-256 `09990a3695c16ece5aff61ed45c1729430d1bf94be1972fd1828fabf6235a158`.
- Structured response: `action=Talk`, `travel_decision=NONE`, empty `travel_destination`, `followup_update.decision=NONE`, no preference updates. It does not accept a trip or dispatch movement.
- Native response, all three queued to Tsetseg:
  1. “Vain, if I had the pick. The soil there is soft and wet, and there's water moving through it — not like this dust.”
  2. “I've seen the red rivers from a distance, never walked them.”
  3. “A place that grows food without a fight is worth the risk of the walk.”
- Native evidence: `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`; backend reply queue: `/var/www/html/StobeServer/log/output_to_plugin.log`, lines 9615–9617, all correlated to the backend request above.

## State and interpretation

- Same-target preflight: Tsetseg alive, no orders or player orders, `current_goal=OTHER`; she was moving autonomously.
- Same-target post-read: still alive, no orders/player orders, `current_goal=OTHER`; no travel agreement/order/dispatch. Position changed during her autonomous movement; it is not counted as test-directed travel.
- The backend recorded the utterance as current-location context (Squin / Stenn Desert). This is geolocation of the conversation, not resolution of Vain as a travel destination.
- The NPC can state a broad-region preference without the player naming a place. No machine-readable destination candidate list was attached to the capture metadata (`metadata_keys=[]`), and the structured travel destination remained empty. Vain is therefore a preference answer only; executable routing to Vain remains untested.
- No retry, follow-up question, movement command, save write, or identity/profile change occurred.
- Next: run a separately cleared P0 test that checks whether the named region can be resolved into an actual destination and, if possible, proceeds through explicit consent and observed goal/order movement. Keep the result of this row separate from navigation success.
