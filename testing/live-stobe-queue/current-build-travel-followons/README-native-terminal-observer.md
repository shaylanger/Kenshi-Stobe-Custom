# P0 native state snapshot (trip relation unsupported)

`native-terminal-observer.sh` takes a bounded, read-only snapshot of one exact actor's current native movement state. It is not a travel follow-on row and does not claim arrival or cleanup coverage. It calls only `stobe-auto status` and repeated `stobe-auto stobe_state #serial/index`. It never chats, issues orders, releases/cancels travel, writes SQL, or infers arrival from proximity.

The observer requires a structured `CURRENT_CONTEXT_RECEIPT` captured for this same observation. The JSON receipt binds rig/instance/path, loaded build and source-manifest SHA-256 values, copied-save/world/session-generation IDs, exact actor name/serial/index, expected current native destination, native-log path, capture time, and hashes of the accompanying preflight/build/session/destination receipt files. The script compares those values with explicit `EXPECTED_*` environment pins and exact route/actor inputs, validates the four source-file hashes, then requires each live `stobe_state` result to match the exact actor and destination. The current context receipt is a row-input schema, not a new game/backend API; prepare it only from the operator's real contemporaneous read-only receipts.

Two consecutive exact-actor native samples must show a stable terminal movement flag (`destination_reached=true,moving=false` or `path_failed=true,moving=false`) while `ai.destination` remains within 5m of the current context receipt. The output is `PASS-SNAPSHOT`. Every result explicitly states `trip_relation=UNSUPPORTED`, `arrival=UNSUPPORTED`, `ledger=UNSUPPORTED`, and `cleanup=UNSUPPORTED`; it makes no claim that the actor state belongs to any prior start row or scoped agreement. The independent source audit found `NativeTravelLifecycle::SnapshotJson()` only embedded in NPC context sent to the private backend and no supported `stobe-auto` or durable read-only lifecycle reader.

## Invocation

Create a fresh context JSON from the operator's current read-only receipts. Required keys:

```json
{
  "schema": 1,
  "kind": "native-state-snapshot-context",
  "captured_utc": "2026-10-14T12:00:00Z",
  "rig": "5090",
  "instance": 3,
  "kenshi_dir": "/mnt/d/KenshiInst/3",
  "kah_dir": "D:\\KenshiInst\\3\\mods\\AutomationHarness",
  "build_sha256": "<64 hex>",
  "source_manifest_sha256": "<64 hex>",
  "save_id": "<copied save identity>",
  "world_id": "<current world identity>",
  "session_generation": "<current session generation>",
  "actor_name": "Exact current display name",
  "actor_serial": 123456,
  "actor_index": 2,
  "native_destination": [100.0, 0.0, 0.0],
  "native_log_path": "/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log",
  "evidence_sha256": {
    "preflight": "<sha256 of PREFLIGHT_RECEIPT file>",
    "build": "<sha256 of BUILD_RECEIPT file>",
    "session": "<sha256 of SESSION_RECEIPT file>",
    "destination": "<sha256 of DESTINATION_RECEIPT file>"
  }
}
```

Set expected pins from those same actual receipts, then run through the selected rig's documented `rig-env.sh` route:

```bash
RIG=5090 KAH_INSTANCE=3 \
KENSHI_DIR=/mnt/d/KenshiInst/3 \
KAH_DIR='D:\KenshiInst\3\mods\AutomationHarness' \
NPC='Exact current display name' ACTOR_HANDLE='123456/2' \
EXPECTED_BUILD_SHA256='<64 hex>' EXPECTED_SOURCE_MANIFEST_SHA256='<64 hex>' \
EXPECTED_SAVE_ID='<copied save identity>' EXPECTED_WORLD_ID='<current world identity>' \
EXPECTED_SESSION_GENERATION='<current session generation>' EXPECTED_NATIVE_DESTINATION='100,0,0' \
CURRENT_CONTEXT_RECEIPT=/path/to/current-context.json \
PREFLIGHT_RECEIPT=/path/to/preflight.md BUILD_RECEIPT=/path/to/build.md \
SESSION_RECEIPT=/path/to/session.md DESTINATION_RECEIPT=/path/to/destination.md \
NATIVE_LOG='/mnt/d/KenshiInst/3/RE_Kenshi/mods/Stobe/stobe.log' \
OUT=/tmp/native-state-snapshot-001 WAIT_SECONDS=60 POLL_SECONDS=2 \
bash testing/live-stobe-queue/current-build-travel-followons/native-terminal-observer.sh
```

For rig 4080, use `KENSHI_DIR=/c/KenshiInst/3` and `KAH_DIR=C:\KenshiInst\3\mods\AutomationHarness`. `OUT` is atomically claimed before the first handler call. The context receipt must be no older than six hours, and its four evidence hashes must match the provided files. Save, world, and session-generation expected pins and receipt fields must each be nonempty strings. The deterministic selftest rejects mismatches across rig, instance, build, save, world, session, actor, and destination, null/absent save-world-session pins, and live actor/destination mismatches; it contacts no rig, game, backend, service, save, or queue.

Run `python testing/live-stobe-queue/current-build-travel-followons/native-terminal-observer-selftest.py`.
