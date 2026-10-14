# Exact review packet: Stobe progress waker

Review these frozen implementation artifacts and verify each SHA-256. `targets.json` is mutable runtime data and is intentionally excluded from the code pin set; the watcher validates it at every tick against the pinned schema fixture and guards. The activation status records the exact target snapshot hash used for the first real tick.

| Frozen artifact | SHA-256 |
|---|---|
| `tools/automation/live-testing-waker.ps1` | `40E433EE66A122914CE6AEEB65A627C3B975757921D27C48757A6027C6B16A01` |
| `testing/live-stobe-queue/progress-waker/targets-schema-fixture.json` | `BD1FFC851B9758450E099BCDC724C88676400648C5284921B601EE8FE8C86141` |
| `testing/live-stobe-queue/progress-waker-selftest.ps1` | `B5C9F20B93BDBF8A88ACF723E52BCBA6BA73FCCEDA8956D486D928CD04EA31BC` |
| `testing/live-stobe-queue/progress-waker/README.md` | `699B0D456DD2D5A70EE91BC42E269929068DAB7E4B92B07CA6A4FBD3C6B150F1` |

Focused synthetic output: `RESULT LIVE-TESTING-WAKER-SELFTEST PASS cases=34 controls=none`.

Review exact-request event correlation and full-line SHA-256 cursors; baseline behavior; bounded stalls; terminal receipt identity and pin checks; completion deduplication across restarts; dead/idle/dependency states; operator liveness; canonical SSH executable/host/config and isolated i3 paths; remote query failure remaining unknown; and whole-file runtime target validation (schema 1, poll 120, exactly one each 5090/4080, allowed phases, stall bounds). Confirm the watcher only reads rigs and only writes local state/events/lock, never game state, queues, inboxes, services, saves, or physical input.

Latest runtime snapshot (mutable input, not a frozen implementation artifact): `targets.json` SHA-256 `EDF7407CD08AA69C274EDB05C632FBE88588B44D149060C8CB5A5AAE537E7BB5`. It pins both lanes `row=none` with terminal CHAT-004 receipts and current supervisor next-candidate notes. Receipt hashes: 5090 `24F843A8F2C42508E72F16C728B0A08B66F92AD805A2498C5979B2B206401BAE`; 4080 `5B1A96BAFB3E78C310593F99CE0CE17520A8ED9B4527EA5808DC4116AF405632`. The queue supervisor/operator may update runtime rows; re-hash and validate each snapshot at activation.

Implementation review only. Do not start the waker, connect to either rig, read logs from either machine, or write files.
