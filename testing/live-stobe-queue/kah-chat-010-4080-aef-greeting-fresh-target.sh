#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-010. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-010 — 4080/i3 AEF greeting with independent fresh target/state preflight
Purpose: one new direct multiword greeting. Eligibility depends on this row's fresh session/build/backend/target/range/state gates; no prior chat row or CHAT-007 result is required. Do not reuse earlier target or reply evidence and do not retry this row unchanged.

HARD BUILD PIN: loaded Stobe DLL SHA-256 must be exactly
  AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C
Required route: 4080 host `DESKTOP-NQQPA73`, isolated instance 3. Resolve and record the actual DLL path loaded by this instance, then hash that exact file. Use only private isolated i3 backend `127.0.0.1:18084`; verify health/schema and a fresh ready session matching the current world/save. Do not use shared instance 1 or another backend.

Independent fresh preflight: record host, instance, PID, current world/save, actual loaded DLL path and exact hash, backend endpoint/health, and native session readiness. Recheck immediately before send. Confirm isolation is on; no `ui`, OS input, UI commands, focus changes, or physical keyboard/mouse. Any missing or mismatched value stops before chat.

Take fresh read-only `stobe-auto chars 300`, `stobe-auto stobe_ping`, and `where` observations for the exact current display name and `#<serial>/<index>`. Require the name and handle to resolve to the same live actor and coherent current location, and verify distance <= TalkRadius 80 using the supported live readout. A prior target movement/setup failure does not block this row, but it cannot substitute for fresh identity/range proof. If observations disagree, target is absent/dead, or distance exceeds 80, stop before send.

Before send, capture current trip, goal, and order state for that exact actor/handle using supported read-only backend/native receipts. Preserve timestamp, actor, world/save and endpoint correlation. If the same-target baseline cannot be obtained without mutation, stop before send. Capture a backend/LLM dialogue correlation cursor or equivalent fresh boundary.

After every gate passes, send exactly once via validated UTF-8 Base64 Bash-body transport (PowerShell 5 quoting safety). The decoded body must explicitly export:
  export KAH_INSTANCE=3
  export KAH_DIR=C:/KenshiInst/3/mods/AutomationHarness
  export PATH=/c/KAH/bin:$PATH
Then issue this exact direct command, replacing only the placeholder with the exact current display name confirmed by the matching fresh reads:
  stobe-auto stobe_say "<exact current NPC name>" "Hello there. How are you doing today?"
Use the tested wrapper form:
  printf '%s' <UTF8-Base64-of-exact-Bash-body> | base64 -d | bash -s
Preserve payload/body, request ID and dispatch timestamp. Do not append `ui`; do not retry on absent reply or ambiguous logs.

PASS requires one correlated request and same target across native `TEST_INBOX: say` with complete exact text and serial/index, backend/LLM event/response from `127.0.0.1:18084`, a native NPC reply, and post-chat trip/goal/order state compared with the pre-chat baseline. ACK or player SAY echo alone is insufficient; report any state delta.

Exact result forms:
  RESULT KAH-CHAT-010 PASS rig=4080 instance=3 pid=<pid> world=<identity> save=<identity> backend=127.0.0.1:18084 session=<receipt> dll_path=<actual-loaded-path> dll=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C target=<name>#<serial/index> distance=<observed m; <=80> native_say=<log-line+full-text> backend_llm=<correlated-record> reply=<native-log-line> state_before=<same-target-receipt> state_after=<same-target-receipt>
Setup stop, no send:
  RESULT KAH-CHAT-010 FAIL setup: <specific fresh host/instance/PID/world/save/build/backend/session/target/range/state-baseline gate>
Post-send evidence failure:
  RESULT KAH-CHAT-010 FAIL evidence: <specific missing/mismatched native say/backend/LLM/reply/state evidence, request ID and receipt paths>
ROW
