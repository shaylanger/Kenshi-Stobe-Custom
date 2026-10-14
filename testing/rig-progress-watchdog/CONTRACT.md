# Paired rig progress watchdog contract

## Scope and owners

This monitor covers only the current isolated instance-3 work on the 5090 and 4080 rigs. The 5090 process identities are game PID 26972, model PID 97588, and adapter PID 29152. The 5090 operator reports port 14725 as a WSL/Linux endpoint, which this Windows-local probe cannot observe; the current Windows-local private model endpoint at 18098 returns health 200. Do not treat the absence of a Windows listener on 14725 as a failure or infer that port 18099 is active. The 4080 evidence route is private loopback port 18084, game PID 3452, and model PID 2260. The sole physical operators are `/root/5090_p0_game_operator` and `/root/4080_corrected_session_diagnostic_operator`. Any different process, route, PID, operator, or task requires a fresh owner-confirmed target update before observation.

The monitor is read-only. It must never send game input, change authentication, update manual flags, kill or restart any game/service, change the 4080 summary interval, or initiate consent. Physical game actions belong to the named operators. Report exact evidence and request their next safe action; the root coordinator owns cross-task assignment.

## Producer proof

The producer is a detached process started hidden with standard permissions. Its durable receipt records PID, process start time, command path/hash, exact parent/producer relationship, and heartbeat path. On each bounded cycle it must atomically write a heartbeat containing UTC time, monotonic sequence, producer PID and start time, plus the newest observed correlated state for both rigs. A PID alone, game PID, or refreshed file timestamp is not proof of progress.

The initial launch receipt must be independently checked against the live process table and the process start time. Every heartbeat must re-check that identity. If the producer exits, its PID is reused, or heartbeat age exceeds 150 seconds, emit `PRODUCER_GONE` or `PRODUCER_STALE` and stop claiming paired monitoring.

## Consumer proof and progress

One active consumer watches the heartbeat/event file using a file watcher with a bounded fallback of at most 30 seconds. It records its own PID, start time, heartbeat, last sequence consumed, and the exact evidence cursor. It waits for producer events with bounded waits no longer than 110 seconds; timeout means re-arm and inspect the latest snapshot. It must not busy-poll file listings, SSH, or rig health.

For each rig the snapshot must separately record operator liveness, route/process observation, and task progress. Valid task progress requires a changed, exact-identity-correlated request/stream event, a verified native action-state change, a changed row result/terminal receipt, or a correlated backend completion/error. Game process liveness, model PID liveness, log mtime, generic operator status/timestamp, model token activity without the current request ID, and unrelated native events do not count.

The 5090 record must retain the current `auth PENDING7` identity and correlate native request/stream/action evidence to it; any native fix in flight is tracked as a separate exact artifact/process and may not be inferred from the game PID. The 4080 record must observe the current private endpoint and model request/stream, while preserving the reviewed temporary summary interval of 720 and its reload/healthy R5 baseline. The legacy API-presence diagnostic is metadata only and cannot replace task evidence.

## Stall response

At each consumer wake, reconcile both rigs and the named operators. On two consecutive unchanged 120-second producer snapshots for a rig, inspect actual producer and runner liveness, the game pause/menu state, pending request/stream state, endpoint/session/target state, and terminal evidence. Send the root coordinator a concise receipt with exact timestamps, identities, changed fields, and the next safe action for the named operator. The operator remains responsible for any physical interaction. Root must immediately notify the relevant owner and queue the next READY case once the current case is terminal; never invent filler work.

## Receipts and cleanup

Keep the launch receipt, heartbeat, append-only events, consumer cursor, and compact status pointer under this directory. Record exact paths and rollback/cleanup commands for helpers. Cleanup may stop only helper processes whose PID and start time match the monitor's own launch receipt; it must not touch game, model, adapter, endpoint, queue, or user services. If monitor identity or rig route cannot be verified, record `OBSERVATION_BLOCKED` and report it instead of guessing.
