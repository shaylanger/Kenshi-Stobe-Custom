# 4080 isolated i3 native session-gate initialization packet

Pinned guarded transport wrapper: `tools/automation/remote-bash-stdin-4080.ps1` SHA-256 `6B82BFC6E186B9669058C63239822153A82849A048770D1D26546A6FB8CC7D1B`. This pin is for the reviewed wrapper only; the packet body and this README are separately hashed in the preparation receipt. Any wrapper hash change requires a new exact review before use.

This is a **one-shot native session-gate initialization probe**, not a read-only operation, gameplay test, or backend authentication proof. It records the isolated i3 game lock, exact process PID, loaded-module paths and on-disk hashes, pinned Stobe/Harness build hashes, loopback config, world/save/player/pause state, input-isolation state, and inbox/lock presence. The game lock must be exactly `free` before the probe and remain free after it; any owner, missing output, or ambiguous value stops before ping. It sends exactly one `stobe_ping`, a non-chat KAH read, and requires one matching outbox reply with a request ID. A fresh correlated ACK may change the in-memory `PlaythroughSession::Allowed(Generation())` gate to ready; that side effect is intentional and means the packet is not read-only. It then confirms the same status, process/PID/module paths and hashes, config, isolation, and lock state remain unchanged.

The independent source review establishes only that a fresh correlated ping response is processed after the in-memory `PlaythroughSession::Allowed(Generation())` gate, absent a concurrent load transition. A PASS means the isolated native generation gate accepted the fresh ACK; it does not prove backend authentication, bind the session to a save/world identity, establish interaction permission, or test dialogue/gameplay. If ping is acknowledged while the backend reports `off`/404, source allows the native session gate to become ready; this packet therefore makes no backend-auth claim.

The script fails closed on route mismatch, pending inbox/lock, a non-free or ambiguous game lock, missing/duplicate process/modules, unexpected build/config/world/isolation, non-unique ACK, mismatched ACK, or any detected post-ping state change. Module hashes are on-disk hashes of the loaded module paths, not a read of mapped memory. The packet includes a local synthetic self-test for free/owned/missing/ambiguous locks and process/world changes; it does not contact a rig. No retry is allowed. The real packet does not clear or inspect inbox contents, manipulate focus, send chat, create/load/save a world, issue movement, or change game state beyond the single ping and its possible in-memory native session-gate initialization.

**Not yet authorized to execute.** Parent requested packet preparation only. Before any 4080 contact, obtain a fresh row-specific Agent Validator CLEAR and confirm the game lock/inbox state and no active lane owner. Then execute once through the guarded wrapper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1 -BodyPath C:\KenshiModding\testing\live-stobe-queue\packets\4080-i3-native-ping-gate-20261014\body.sh
```

Expected future result: one `RESULT 4080-I3-PING-GATE PASS ...` or a terminal `FAIL setup`; never rerun unchanged. A PASS authorizes only a separate decision about the next actual gameplay row.
