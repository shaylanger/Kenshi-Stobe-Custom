# Independent KAH-INT-001 / 4080 i3 draft

Local-only independent draft of the executable row body. It is not cleared, queued, or run. The body uses the packet's exact `remote-bash-stdin-4080.ps1` preamble and enforces fresh instance, process/module, payload, config, copied-save/world/pause, and natural `focused=0` isolation gates before the first input. It uses KAH `key_inject` and screenshot-coordinate `mouse_inject`, captures UI/screenshot evidence, and never sends the slash draft.

## Source pins

| Source | SHA-256 |
|---|---|
| Immutable KAH-INT-001 row emitter `testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-chat-hotkey-isolated.sh` | `5EA4BD563D0697ECA7B7939F0666F1557D23DCA66598E61EAD24738DE44219F5` |
| Route instructions `testing/live-stobe-queue/4080-i3-command-route.md` | `BAD511F01ADE7726B67F6DCA63F483FA8157CE1996AED99E8FB1D80ABA3B0822` |
| Required wrapper `tools/automation/remote-bash-stdin-4080.ps1` | `138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354` |
| Sourced route definitions `tools/automation/rig-env.sh` | `A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D` |
| Standalone i3 route helper `tools/automation/rig4080/instance-route-preflight.sh` | `408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51` |
| Loaded-module probe `tools/automation/loaded-module-probe.ps1` | `121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F` |
| Source manifest `pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/SOURCE-MANIFEST.json` | `AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C` |
| Payload manifest `pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/PAYLOAD-MANIFEST.json` | `475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A` |
| Candidate Stobe DLL | `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` |
| Staged 4080 i3 Stobe DLL | `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` |
| Harness DLL | `974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D` |

## Runtime evidence still required

The runtime `ui tree Stobe_ChatWindow up 0` output has not been observed in this local-only authoring task. The body fails closed unless the scoped tree contains exactly one visible textbox, one titlebar, and exactly one visible close/cancel/dismiss-labeled descendant inside that titlebar. It parses each visible widget's absolute bounds, compares the chat root rectangle against the screenshot-reported client/render size, rejects out-of-bounds or zero coordinates, and only then computes center coordinates for KAH-injected clicks. A mismatch or ambiguous close target stops without a close click and leaves the slash draft unsent. It never calls the global `ui close` command.

No runtime UI evidence exists yet. A later authorized run must supply the fresh scoped tree, screenshot dimensions, UI outputs, and screenshots for independent visual review of the textbox caret and state transitions. The runtime may reveal that the tree's close/textbox names or titlebar geometry do not satisfy the fail-closed selectors; in that case the body must stop and be revised/re-reviewed. This packet is not cleared, queued, or run; fresh row-specific Agent Validator clearance and independent review remain required.

The row is UI-only: `backend_session=NOT_REQUIRED_LOCAL_UI`. The body contains no backend/PHP/session query, chat-send command, physical input, focus/window manipulation, server action, save/config/queue mutation, or remote invocation during authoring checks.

## Local checks only

From PowerShell at `C:\KenshiModding`:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -n testing/live-stobe-queue/packets/4080-i3-kah-int-001-20261014-parallel/body.sh
python testing/live-stobe-queue/packets/4080-i3-kah-int-001-20261014-parallel/selfcheck.py
git diff --check -- testing/live-stobe-queue/packets/4080-i3-kah-int-001-20261014-parallel
```

These commands parse/check local files only. Do not run the body with the 4080 wrapper from this packet; these checks do not contact a rig or constitute execution clearance.
