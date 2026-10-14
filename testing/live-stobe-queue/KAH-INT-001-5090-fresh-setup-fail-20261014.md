# KAH-INT-001 5090 fresh attempt — setup failure

- Date: 2026-10-14
- Exact immutable emitter SHA-256 verified: `5EA4BD563D0697ECA7B7939F0666F1557D23DCA66598E61EAD24738DE44219F5`.
- Required 5090 local-UI packet: `integrated-AEF84C0A/kah-int-001-local-ui-exception-5090.packet.md`.
- Setup gate failed before any rig/runtime command or injected input: the integrated candidate README says every row remains blocked until safe isolated staging completes and explicitly says not to use the shared-Steam installer. No fresh staging receipt establishing an authorized isolated 5090 instance, copied save, live PID, loaded module paths/manifests, Harness, and config was present in this packet directory. The existing 2026-10-13 install/runtime receipts refer to the main Steam install / instance 1 and are stale for this fresh attempt.
- No 5090 host/runtime gate was probed, no input was sent, and no backend/session, NPC chat, or LLM contact was made. `backend_session=NOT_REQUIRED_LOCAL_UI` per packet.
- Assertions: not run. No PASS or product verdict.

`RESULT KAH-INT-001 FAIL setup: authorized isolated 5090 staging and fresh copied-save/runtime receipt absent; stopped before rig or input`
