# Current-build changed-plan row

`changed-plan.sh` is a standalone executable P0 follow-on. It never edits the frozen `current-build-travel-driver/` files. It uses only the existing isolated `stobe-auto` route, asks one ordinary `stobe_say` question, waits for the native streamed-response completion marker and its queued speech, and observes the native log plus `stobe_state`.

The row supports two reviewable outcomes. A single explicit refusal to change to the requested destination passes only when no native `TRAVEL_LOCATION` action occurs and repeated native observations show the original destination remains active. A single clear first-person acceptance passes only when exactly one `TRAVEL_LOCATION` dispatch for the exact requested destination and actor serial appears, and repeated `stobe_state` samples match the dispatch's XYZ endpoint within 5m with `path_failed=false` and at least one `moving=true`, `destination_reached=false` sample. The action's display name and quoted destination label must exactly match the current actor and requested destination. Duplicated dispatches, a dispatch following explicit refusal, a native destination contradicting the action endpoint, or path failure are product failures. Conditional, ambiguous, incomplete, or mismatched dialogue/action evidence is `FAIL evidence`; setup and stale pins are `FAIL setup`.

The request is fixed by the row as: “I need to change our trip from {active} to {new}. Will you agree to change the trip and take me to {new} instead? If you do not agree, keep the existing trip to {active}.” It is sent once through ordinary `stobe-auto stobe_say`. No additional acceptance message is sent.

## Required inputs

Before invoking, source `tools/automation/rig-env.sh` and satisfy the owner’s current copied-save/private-session/input-isolation preflight. The driver verifies `RIG=5090|4080`, `KAH_INSTANCE=3`, and the exact selected i3 game/harness paths. It requires:

- `NPC`: exact current name as shown by `where`/`stobe_state`, including template suffix.
- `ACTIVE_DESTINATION`, `NEW_DESTINATION`: exact distinct labels.
- `ACTIVE_TRAVEL_OUT`: fresh output from the frozen start/movement row, with matching `endpoint.json`, `progress.json`, `state.final.txt`, and `accept.native.delta.log` proving one previous accepted dispatch and movement for this same actor.
- `PREFLIGHT_RECEIPT`, `BUILD_RECEIPT`, `SAVE_RECEIPT`, `SESSION_RECEIPT`, `ACTIVE_START_RECEIPT`: all fresh owner-supplied receipts. The build/save/session files must contain exact `build_sha=<BUILD_SHA>`, `save_id=<SAVE_ID>`, and `session_id=<SESSION_ID>` lines. Both preflight and active-start receipts must repeat those exact values and include exact `rig=<RIG>`, `kah_instance=3`, `native_log=<NATIVE_LOG>`, and `active_travel_out=<ACTIVE_TRAVEL_OUT>`. The preflight must attest private backend, input isolation and clear inbox; both receipts bind `actor=<NPC> serial=<current serial>`. These are checked against current `where`, current `stobe_state`, the saved accepted-start row's final state, and its exact actor/destination/native action serial.
- `BUILD_SHA`, `SAVE_ID`, `SESSION_ID`: exact IDs matching the receipts and current isolated run.
- `OUT`: new output directory whose parent already exists; it is atomically claimed before the first handler call.
- `NATIVE_LOG`: current isolated instance’s native log.

`WAIT_SECONDS`, `POLL_SECONDS`, `SETTLE_SECONDS`, and `MAX_RECEIPT_AGE_SECONDS` can tune the bounded waits/receipt freshness. Defaults are 180 seconds, 3 seconds, 9 seconds, and 3600 seconds. Example after route setup:

```bash
RIG=5090 KAH_INSTANCE=3 \
  NPC='Cind [Hungry Bandit]' ACTIVE_DESTINATION='Heft' NEW_DESTINATION='Stack' \
  ACTIVE_TRAVEL_OUT=/path/to/fresh-start-move-output \
  PREFLIGHT_RECEIPT=/path/to/fresh-private-i3-preflight.txt \
  BUILD_RECEIPT=/path/to/build-receipt.txt SAVE_RECEIPT=/path/to/copied-save-receipt.txt \
  SESSION_RECEIPT=/path/to/private-session-receipt.txt ACTIVE_START_RECEIPT=/path/to/active-start-binding.txt \
  BUILD_SHA=<sha256> SAVE_ID=<copy-id> SESSION_ID=<session-id> \
  OUT=/tmp/p0-travel-changed-plan-001 \
  NATIVE_LOG=/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log \
  bash testing/live-stobe-queue/current-build-travel-followons/changed-plan.sh
```

## Supported and unsupported evidence

The selected current handler source exposes exact target/serial speech records (`NPC_SAY`), chat completion (`CHAT_THREAD: Queued N streamed chat lines and N action lines`), `ACTION_EXEC: TRAVEL_LOCATION` with actor serial/destination label, and nested `stobe_state.ai.destination`, `moving`, `destination_reached`, and `path_failed`. The driver correlates these live observations. The checked-in `NEG_TEST_INJECT` switch scopes by row/NPC/context but does not bind the player speaker and exact request message, so this row deliberately does not use it or claim deterministic-fixture coverage.

There is no supported `stobe-auto` reader in the selected handler surface for a durable scoped agreement/request revision, owned-order identity, or lifecycle/cleanup ledger. The row therefore marks `durable_trip_ledger=UNSUPPORTED`; an observed destination alone does not prove consent persistence, ownership, terminal release, or cleanup. This follow-on does not cover arrival/cleanup. It does not use teleport, direct `TRAVEL_LOCATION`, test injection, SQL writes, or trip-state mutation.

## Local verification and pins

Run the mocked-handler checks with the configured Python runtime:

```powershell
& 'C:\Users\Shay\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' testing/live-stobe-queue/current-build-travel-followons/changed-plan-selftest.py
```

The selftest models the `stobe-auto` handler boundary and requires a refusal to preserve the original native route, rejects a replacement dispatch after refusal, accepts one evidenced replacement, rejects duplicate dispatch, rejects action/state XYZ mismatch, rejects conditional language, classifies “I can not” as refusal, rejects wrong display-name/destination labels for prior and changed actions, and rejects a mismatched session/path binding. It is offline only; it is not a gameplay receipt.
