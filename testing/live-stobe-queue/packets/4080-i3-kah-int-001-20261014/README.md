# KAH-INT-001 on the isolated 4080 instance 3

**Prepared for row-specific review only. Not cleared, not queued, and not run.** This packet reuses the immutable KAH-INT-001 assertions. It is a Stobe UI hotkey check only; it does not test NPC dialogue, travel, destination discovery, or travel-backend recovery. It may run only while the top-priority travel-backend recovery still has an active owner and is making progress. It must not preempt or delay that work.

## Pinned row and i3 route

- Original row emitter: `testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-chat-hotkey-isolated.sh`
- Original row SHA-256: `5EA4BD563D0697ECA7B7939F0666F1557D23DCA66598E61EAD24738DE44219F5`. Its bytes and behavioral assertions remain unchanged. It is an instruction emitter, not a game runner.
- Current 4080 guarded transport: `tools/automation/remote-bash-stdin-4080.ps1`, SHA-256 `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354`.
- Route helper: `tools/automation/rig-env.sh`, SHA-256 `A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D`.
- Route reference: `testing/live-stobe-queue/4080-i3-command-route.md`, SHA-256 `BAD511F01ADE7726B67F6DCA63F483FA8157CE1996AED99E8FB1D80ABA3B0822`.

Use only the guarded instance-3 route, whose required Bash preamble is exactly:

```bash
export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
```

The row body must then call `rig4080_i3_preflight` before KAH commands. The trusted transport invocation, after the exact body has been reviewed and pinned, is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath <approved-UTF8-Bash-body>
```

Do not use instance 1, the Steam install, another rig route, or a fallback SSH command if the i3 route check fails. A missing route helper, unexpected wrapper/hash, route mismatch, or pending/locked harness inbox is `FAIL setup`; stop before any injected input and preserve the inbox state.

## Exact build and config requirements

Fresh preflight must tie all evidence to the live i3 process and copied test save. Required paths and pins:

| Item | Required current evidence |
|---|---|
| Game process | Executable path `C:\KenshiInst\3\RE_Kenshi\kenshi_x64.exe`; record its PID and i3 identity. |
| Stobe DLL | Loaded path `C:\KenshiInst\3\mods\Stobe\Stobe.dll`, SHA-256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`. |
| Harness DLL | Loaded path `C:\KenshiInst\3\mods\AutomationHarness\AutomationHarness.dll`, SHA-256 `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D`. |
| Build provenance | Source manifest SHA-256 `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C`; payload manifest SHA-256 `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A`. These are verified against the local source manifests; the live install still needs fresh process/module evidence. |
| Stobe config | Read-only path `C:\KenshiInst\3\RE_Kenshi\mods\Stobe\StobeCustom.ini`; record its current SHA-256 and prove `ChatHotkey=/`. Do not modify it. |
| Save/world | `stobe-auto status` must prove the loaded world is unpaused and identify the exact copied test save. Record the save identity; a historical install receipt or a new-game label is not proof that the current process has loaded a copied save. |
| Input safety | Read-only `stobe-auto input_isolation status` must show `isolation=on focused=0`. `focused=0` must be the naturally observed state. Do not activate, foreground, move, or demote the game window to manufacture it. |

Any missing, stale, ambiguous, or mismatched gate is `RESULT KAH-INT-001 FAIL setup: <reason>` and **zero test input**. Do not call PHP, check `:18084`, query a backend, request or refresh a session, or claim backend/session readiness. Record `backend_session=NOT_REQUIRED_LOCAL_UI`; no backend request is part of this row.

## Row behavior and evidence

Use only `stobe-auto key_inject` and screenshot-coordinate `stobe-auto mouse_inject`; never physical keyboard/mouse, `AppActivate`, foreground/focus helpers, or OS-level input. A KAH acknowledgement is not behavior evidence. Preserve `stobe-auto ui` output and a uniquely named screenshot after each state change, and recheck `input_isolation status` before/after each interaction group. Do not use a chat-send command.

1. From a fresh, closed-chat state, inject `/` once. Prove the chat opened in UI state and screenshot.
2. Use the screenshot to inject-click the message textbox. Prove its caret in the screenshot and textbox presence in UI output.
3. Inject `/` once while the textbox is focused. Prove the chat stayed open and the draft contains exactly one literal `/` in UI output and screenshot. **Never send the draft.**
4. Discard the draft only by injected click on the visible cancel/close control. If it does not close or the control is ambiguous, record the evidence/setup failure and stop; do not send the draft or continue in an uncertain UI state.
5. Inject `/` to open a second, separate chat. Leave it untouched: no click, typing, paste, edit, or virtual cursor movement inside it.
6. Inject `/` again and prove that this fresh untouched chat closes in UI output and screenshot.

Keep the existing five-minute bound after all preflight gates pass. The runner has no pending-evidence terminal state; it recognizes `RESULT <row> PASS|FAIL`. Since the caret assertion requires screenshot review, this body always ends with `RESULT KAH-INT-001 FAIL evidence: ... visual review required before PASS`, even when its automated UI assertions complete. This line records captured evidence and explicitly withholds PASS. A reviewer may record a final PASS only after inspecting the required screenshots and confirming the caret and all other visual assertions; unclear or failed visual proof remains `FAIL evidence`. Wrong observed behavior is `FAIL product`; a gate mismatch before input is `FAIL setup`. Any result must include `rig=4080 instance=3 pid=<pid> save=<copied-save-identity> backend_session=NOT_REQUIRED_LOCAL_UI` and evidence paths. No retry of an unchanged state.

## Prior evidence and its limits

- The i3 AEF install receipt `pending-fixes/rig4080-validation/aef-install-4080i3-20261013.md` has SHA-256 `04C59FF58944191B47D45DDE0F1E625E08A5E32C75DA5E1C72C49018C11B0615`. It documents an on-disk AEF install and an old copied-save path; it explicitly says that the binary had not yet been launched/loaded. It is not current runtime proof.
- The previous `KAH-INT-001` run was on 5090 and ended `FAIL evidence`: open was visible, but caret and literal slash were not proven, the close click did not close the window, and untouched-second-slash behavior was not tested. That receipt does not establish an i3 result or prove a product defect.
- The existing 5090 UI-only exception packet has SHA-256 `918FCD6C8A571F6719AD9AACFFCD4964C25908D583005104ADAD3B313DD882A3`. Its narrow backend/session exception is conceptually applicable because this same row is UI-only, but its 5090 route/config cannot be reused as i3 evidence. This file explicitly supplies the instance-3 adaptation and all fresh i3 gates.

## Before any execution

1. Obtain a fresh **row-specific Agent Validator CLEAR** for `KAH-INT-001`, 4080 instance 3, this exact transport/build/config, the current user priority, and the exact final body. A prior validator result for 5090 or another row does not apply.
2. Confirm the P0 travel-backend recovery owner is actively progressing in parallel. This packet is not a substitute or prerequisite for NPC travel validation.
3. Recompute the hashes above and review the final exact Bash body. Any changed row, wrapper, route helper, config, build pin, or body requires re-review.
4. Only after those conditions hold may the i3 operator run a fresh preflight and the row. If any gate fails, stop with `FAIL setup`; do not launch/restart Kenshi, alter config/save/queue, change focus, send chat, or use the backend.

## Local preparation checks (completed; no rig contacted)

These checks are local syntax/integrity checks only:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -n testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-chat-hotkey-isolated.sh
& 'C:\Program Files\Git\bin\bash.exe' -n tools/automation/rig-env.sh
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'tools/automation/remote-bash-stdin-4080.ps1').Path,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw $errors }
$files = @(
  'testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-chat-hotkey-isolated.sh',
  'testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-local-ui-exception-5090.packet.md',
  'testing/live-stobe-queue/4080-i3-command-route.md',
  'tools/automation/remote-bash-stdin-4080.ps1',
  'tools/automation/rig-env.sh',
  'pending-fixes/rig4080-validation/aef-install-4080i3-20261013.md',
  'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/SOURCE-MANIFEST.json',
  'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/PAYLOAD-MANIFEST.json',
  'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/build-v100/Stobe.dll',
  'pending-fixes/release-staging/stobe-integrated/4080/AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C/Stobe.dll'
)
foreach ($file in $files) { Get-FileHash -Algorithm SHA256 -LiteralPath $file }
git diff --check
```

Observed: both Git Bash syntax checks passed; the transport wrapper parsed with PowerShell's parser without executing it; the local manifests matched their declared hashes; the i3 staged DLL matched its declared AEF hash. `git diff --check` returned no whitespace errors (it printed existing LF/CRLF notices for unrelated files). The first `bash` alias invocation hit Windows `E_ACCESSDENIED`; rerunning with the installed Git Bash executable above passed. No remote wrapper, SSH, KAH command, game, rig, server, save, or queue was used.

## Final body candidate (authored locally; still requires independent exact-body review)

- `body.sh` SHA-256: `A2D876CD0DC1DC9F1F288A1EFAD546EE434135F982F3DF85972CC21C58855879`.
- It begins with the exact wrapper-required i3 preamble and immediately sources the pinned `rig-env.sh`, then calls `rig4080_i3_preflight` before any KAH request.
- It gates the copied save/world, exact loaded Stobe and Harness paths/hashes, pinned manifests, `/` config, unpaused initial state, already-ON input isolation, and naturally observed focus `0`. It never turns isolation on, changes window focus, queries PHP/backend/session state, or sends the chat draft.
- Chat opening pauses Kenshi by design (`ChatBox.cpp` requests user pause in `CreateChatUI` and releases it in `CloseChatUI`), so the body requires `paused=0` before its first slash, expects `paused=1` only while each chat is open, and requires the same save/world with pause released after each close.
- Mouse coordinates are derived from the live visible `Stobe_ChatInput` widget and the uniquely matching close-labeled descendant of `ui tree Stobe_ChatWindow up 0`. Before mouse input, the body requires the render screenshot dimensions to equal a read-only Win32 client-rect measurement for the exact game PID, then checks each widget rectangle lies fully inside those bounds and the close target lies in the titlebar's top-right region. Missing, duplicate, or out-of-bounds controls stop before the click; the draft stays unsent.
- Screenshots capture the closed baseline, first open, textbox click, slash draft, draft discard, untouched second open, and untouched second close. Because caret visibility requires screenshot review, the body emits `FAIL evidence` pending that review and cannot emit PASS.
- No device or game was contacted and the body was not run. The exact body requires the current row-specific Agent Validator CLEAR and confirmation that the P0 travel-backend owner is actively progressing before invocation.
- Local source inspection: `CreateChatUI` calls `RequestProfileModelSlotRefresh(true)` on every opening path. That forced refresh starts a background `GET /conf_opts?id=stobe_profile_model` request. The targetless hotkey path and selected-target path both call `CreateChatUI`; no existing local open path was found that suppresses this request. This is source inspection only; no production files were changed.

After the exact body receives independent clearance, the transport command is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-i3-kah-int-001-20261014\body.sh
```
