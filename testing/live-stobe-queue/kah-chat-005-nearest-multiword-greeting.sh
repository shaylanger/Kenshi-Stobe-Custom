#!/usr/bin/env bash
# Immutable row emitter KAH-CHAT-005. Prints instructions only; never sends commands.
cat <<'ROW'
ROW KAH-CHAT-005 — current-world direct multiword greeting via fresh nearest target
The validator-cleared isolated `newgame:Empire Citizen` is an authorized test context. Do not require a copied-save-only setup. Preserve this row's preflight and result separately from the one-token transport probe.

Required read-only preflight on the sole authorized 4080 operator route:
1. Record DESKTOP-NQQPA73, instance 3, PID, current `stobe-auto status` world/save identity, `ServerHost/ServerPort`, and successful HTTP/session readiness.
2. Re-hash the loaded `C:\KenshiInst\3\mods\Stobe\Stobe.dll`; require the expected installed hash `40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D` or stop with `FAIL setup` and record the actual hash.
3. Confirm input isolation is on, UI closed and key focus off; do not use keyboard/mouse, focus changes, or UI commands.
4. Fresh `stobe-auto stobe_ping` must report one named `nearest` NPC. Capture its KAH ACK and native target serial. Confirm that native handle remains live and within TalkRadius=80 using the supported current read-only query. Do not require `chars` display name to equal the native alias. If `nearest=none`, target vanished, or distance >80, record `FAIL setup` before sending; do not retry unchanged.

Send exactly once, directly through the proven UTF-8 Base64 Bash-body transport to prevent PowerShell 5 argument truncation; no `ui` suffix:
  stobe-auto stobe_say @nearest "Hello there. How are you doing today?"
Use `tools/automation/remote-bash-arg-selftest.ps1`'s reviewed invocation pattern: UTF-8 Base64 encode a Bash body, then call `bash.exe -lc "printf '%s' <payload> | base64 -d | bash -s"`. The body must set `KAH_INSTANCE=3`, `KAH_DIR=C:/KenshiInst/3/mods/AutomationHarness`, and `PATH=/c/KAH/bin:$PATH`, then call the exact command above. Preserve the payload or decoded body with the receipt.

PASS requires one matching native `TEST_INBOX: say` with complete multiword text and the ACKed native target handle; native NPC reply; correlated backend event/dialogue record; and before/after trip state showing no trip or dispatch from the greeting. A transport ACK/reply alone is not the full greeting PASS. Keep target-name/serial resolver disagreement as separate KAH-CHAT-006 evidence; it does not block this row when fresh @nearest identity is valid.

Expected result:
  RESULT KAH-CHAT-005 PASS rig=4080 instance=3 world=<actual current identity> build=40414D8C...7101D target=<nearest name #serial distance<=80> native_say=<log:line full text> reply=<log:line> backend=<event-id> trip_before_after=<receipt>
Setup stop (no utterance):
  RESULT KAH-CHAT-005 FAIL setup: <specific world/backend/session/build/isolation/nearest/range gate>
Evidence stop (utterance may have been sent):
  RESULT KAH-CHAT-005 FAIL evidence: <specific missing complete native text/reply/backend/trip receipt>
ROW
