# KAH-INT-001 — isolated local UI exception (5090)

This packet scopes the existing immutable `kah-int-001-chat-hotkey-isolated.sh` row to the Stobe slash hotkey UI on the 5090. It does not change the row's assertions. The existing emitter SHA-256 is `5EA4BD563D0697ECA7B7939F0666F1557D23DCA66598E61EAD24738DE44219F5`.

## Narrow exception

`KAH-INT-001` exercises only the loaded Stobe UI and isolated injected input. It does not send NPC chat, resolve a target, call the LLM, or use the Stobe backend. Therefore this row does **not** require backend availability, backend authentication, a valid campaign session, or a session-authentication probe. Record `backend_session=NOT_REQUIRED_LOCAL_UI` and do not query or claim backend/session readiness. This exception applies only to this row; it does not waive any other row's gates.

The exception retains every relevant local gate. Before input, record and verify:

- rig `5090`, isolated instance, exact live Kenshi PID, and the loaded copied-save identity;
- the live world is ready and unpaused (record the exact `stobe-auto status` and `stobe-auto time` outputs);
- the loaded Stobe module path and on-disk SHA-256 at that exact path, expected `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` (this verifies the file at the loaded path; it is not a hash of mapped memory); source manifest SHA-256 `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C` and payload manifest SHA-256 `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A`, all tied to that isolated instance and process;
- the AutomationHarness module/command-bridge path tied to the same isolated instance and process, with on-disk SHA-256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`;
- the instance's Stobe config path/hash and `ChatHotkey=/`;
- before starting the row timer, run the common UI setup `stobe-auto input_isolation on`, then `stobe-auto input_isolation status`; require `isolation=on` and `focused=0`. Recheck immediately before input and after each interaction group. If either gate is false, stop before injecting input. Do not toggle isolation again during the row or activate/focus the window.

Any missing, stale, or mismatched local gate is `FAIL setup`; no input is sent. The copied save, instance, PID, loaded-build, Harness, and configuration checks remain mandatory even though backend/session auth is not.

## Input and assertions

Use KAH injected input only: `stobe-auto key_inject` and screenshot-coordinate `stobe-auto mouse_inject`. Never use physical input, AppActivate, foreground/focus helpers, a chat-send command, or an OS-level input path. After each transition, preserve `stobe-auto ui` and a uniquely named `stobe-auto screenshot`; ACKs alone do not prove behavior. Do not send the slash draft.

Complete within five minutes after the local gates pass:

1. From a closed-chat baseline and fresh key state, inject `/`; prove the chat opens in both UI output and screenshot.
2. Inject-click the message textbox; prove the textbox caret in the screenshot and its state in UI output.
3. Inject `/` while the textbox is focused; prove the chat stays open and the draft visibly contains exactly one literal `/` in UI output and screenshot. Never send it.
4. Discard the draft without sending. First use the visible close/cancel control with injected mouse input. If that control does not close the window, make one injected Escape cleanup attempt (`stobe-auto key_inject esc tap 120`) and proceed only if UI output and screenshot prove the chat closed. This Escape is cleanup only, not a tested target behavior. If neither method visibly closes it, record `FAIL evidence: draft cleanup did not close chat` and stop; do not send or continue in an uncertain UI state.
5. Inject `/` to open a separate fresh chat. Do not click, move the injected cursor inside, or type in it. Prove it is open in UI output and screenshot.
6. Inject `/` once in that untouched chat; prove it closes in UI output and screenshot. This is the untouched second-slash assertion.

The three required behavior assertions remain: open, literal slash draft while focused, and close on `/` in a fresh untouched chat. A wrong observed behavior is `FAIL product`; missing/ambiguous visual proof is `FAIL evidence`; a pre-input gate mismatch is `FAIL setup`. Preserve evidence of any partial assertions and do not retry an unchanged state.

## Result line

PASS requires all three assertions and the local gates above:

```text
RESULT KAH-INT-001 PASS rig=5090 instance=<n> pid=<pid> copied_save=<identity> loaded_stobe=AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C backend_session=NOT_REQUIRED_LOCAL_UI isolation=on focused=0 unpaused=1 open=<ui+shot> caret=<shot> slash_draft=<ui+shot> untouched_second_slash_close=<ui+shot>
```

Use exactly one terminal `RESULT` line. The receipt must include both loaded module paths and their on-disk hashes. Do not report a backend/session failure for this local-only row; do not use this exception for chat, travel, or any backend-dependent test.
