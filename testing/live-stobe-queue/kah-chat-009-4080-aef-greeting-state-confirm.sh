#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-009. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-009 — 4080/i3 AEF multiword greeting with same-target state receipts
Dependency: KAH-CHAT-007 must first produce a PASS for this same running 4080 isolated i3 world/session and exact AEF build. This is a new one-shot confirmation request, not a retry of KAH-CHAT-005 or any earlier send.

HARD BUILD PIN: loaded Stobe DLL SHA-256 must be exactly
  AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C
Required route: 4080 host `DESKTOP-NQQPA73`, isolated instance 3. Resolve and record the actual DLL path loaded by this instance, then hash that file; require the hard pin. Use only the private isolated i3 backend `127.0.0.1:18084` and verify its health/schema/session readiness for this same world. Do not route through shared instance 1, another backend, or a different KAH_DIR.

Fresh setup gates; any failure stops before send:
1. Confirm host, isolated instance 3, current PID, loaded save/world identity, private backend endpoint `127.0.0.1:18084`, fresh native session/readiness, and exact loaded DLL path/hash. Recheck all immediately before this row; do not reuse stale queue state.
2. Require a recorded `RESULT KAH-CHAT-007 PASS` receipt matching the current PID, world/save, session, AEF DLL SHA, and i3 backend. If KAH-CHAT-007 has not passed or any identity differs, stop before chat.
3. Confirm input isolation remains on. Do not use `ui`, keyboard/mouse/OS input, focus changes, or UI commands.
4. Capture fresh `stobe-auto chars 300`, `stobe-auto stobe_ping`, and read-only `where` for the exact target name and `#<serial>/<index>`. Require the name and native handle to identify the same current living actor, with coherent location and distance <= TalkRadius 80. Do not use a historical target/handle or let a name/alias disagreement pass. If nearest/handle/name disagrees, target vanished/died, or distance exceeds 80, stop before sending.
5. Capture target-specific trip, goal, and order state before chat using the supported read-only state receipts. Record the same actor handle, world/save, endpoint, timestamp and request-correlation cursor. If any baseline cannot be captured without mutation, stop before send.

After every gate passes, send exactly once through the tested UTF-8 Base64 Bash-body invocation (PowerShell 5 quoting safety). Set these values explicitly inside the body:
  KAH_INSTANCE=3
  KAH_DIR=C:/KenshiInst/3/mods/AutomationHarness
  PATH=/c/KAH/bin:$PATH
Before the KAH command, run `rig4080_i3_preflight` from `tools/automation/rig-env.sh`; it prints and verifies `KAH_INSTANCE=3`, `KENSHI_DIR=/c/KenshiInst/3`, and `KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness`. It checks inbox and lock presence only. If either exists, stop without reading or changing it. Full PowerShell 5 transport recipe: `4080-i3-command-route.md`.

Then issue the exact direct command, substituting only the exact current display name established by the fresh matching name+handle reads:
  stobe-auto stobe_say "<exact current NPC name>" "Hello there. How are you doing today?"
Invocation wrapper pattern:
  printf '%s' <UTF8-Base64-of-exact-Bash-body> | base64 -d | bash -s
Inside the decoded Bash body, export the variables exactly as follows before the command:
  export KAH_INSTANCE=3
  export KENSHI_DIR=/c/KenshiInst/3
  export KAH_DIR=C:/KenshiInst/3/mods/AutomationHarness
  export PATH=/c/KAH/bin:$PATH
Do not append `ui`; preserve the encoded payload or exact decoded body, request ID and dispatch timestamp. The send is one-shot; do not retry on missing reply or ambiguous logs.

PASS requires the same request and target to correlate across: native `TEST_INBOX: say` showing the full exact utterance and native target serial/index; native NPC reply; backend/LLM event and response from private `127.0.0.1:18084`; and same-target post-chat trip/goal/order reads compared with the pre-chat baseline. Record any state delta. ACK or player SAY echo alone is insufficient.

Exact result forms:
  RESULT KAH-CHAT-009 PASS rig=4080 instance=3 pid=<pid> world=<identity> save=<identity> backend=127.0.0.1:18084 session=<receipt> dll_path=<actual-loaded-path> dll=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C target=<name>#<serial/index> distance=<observed m; <=80> native_say=<log-line+full-text> backend_llm=<correlated-record> reply=<native-log-line> state_before=<same-target-receipt> state_after=<same-target-receipt>
Setup stop, no send:
  RESULT KAH-CHAT-009 FAIL setup: <specific KAH-CHAT-007/install/host/instance/PID/world/save/session/backend/KAH_DIR/target/range/baseline gate>
After-send evidence failure:
  RESULT KAH-CHAT-009 FAIL evidence: <specific missing/mismatched native say/backend reply/NPC reply/same-target before-after state, request ID and receipt paths>

Scope review: this row is limited to one direct natural greeting on the reviewed AEF candidate after KAH-CHAT-007 PASS. It tests no UI, travel, movement, consent, or unrelated behavior; it sends no command until exact build/session/target and baseline gates pass. It uses the current private 18084 endpoint and explicit i3 KAH_DIR, and it has no retry path.
ROW
