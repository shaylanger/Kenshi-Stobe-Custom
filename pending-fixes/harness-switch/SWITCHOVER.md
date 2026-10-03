# Harness switch-over checklist (DRAFT: run only when Shay asks)

Replaces Stobe's built-in test harness (TestAutomation.cpp + test_inbox.txt)
with the standalone Kenshi Automation Harness (`Kenshi-Automation-Harness/`,
repo `shaylanger/Kenshi-Automation-Harness`) plus a bridge in Stobe.

Verified before the switch (2026-10-02): `patch_stobe_bridge.py --check` and
`patch_tools.py --check` find every anchor; the patched Stobe compiles
(scratch build, no new warnings, no hard import of the harness DLL);
patched stobe-say/stobe-auto send the right commands to a fake inbox; the
harness's offline tests pass (19/19). **Not yet run in the game.**

## What changes for the tools

| Before | After |
|---|---|
| `stobe-say on/off` = `RE_Kenshi\mods\Stobe\test_inbox.flag` | `Kenshi\mods\AutomationHarness\enabled.flag` |
| `stobe-auto ...` (auto_inbox.txt) | same commands, through `kah.py` (inbox.txt) |
| `stobe-say ping/mode/say/state/give_cats` | same, sent as `stobe_*` harness commands |
| `stobe-say speed` (Stobe) | the harness `speed` (needs a loaded game) |
| launch waits for `TEST_AUTO: frame listener running` in stobe.log | waits for `KAH: frame listener running` in harness.log |
| `stobe-auto attack` breaks Stobe truces directly | Stobe's before-attack hook does it |
| `inv` JSON with description/quality labels | no description/quality label (nothing parses them) |

scenarios.sh, stobe-guard.sh, stobe-goal-watch.sh: unchanged.

## Steps

1. **Pre-check:** Kenshi closed (`kenshi-ctl.ps1 status`), no other session
   using the game; `git status` in the workspace; rerun both scripts with
   `--check` (Stobe's main.cpp changes often). Sync `/root/STOBE-src` into
   `components/STOBE` and commit first: that snapshot is the rollback point.
2. **Build the harness:** `Kenshi-Automation-Harness\build.bat` and
   `tests\run_tests.bat`.
3. **Install the harness mod:** create `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\`,
   copy `mod\AutomationHarness\*` (RE_Kenshi.json, AutomationHarness.mod) and
   `out\AutomationHarness.dll` into it.
4. **Mod list:** add `AutomationHarness.mod` to `Kenshi\data\mods.cfg` on the
   line **before** `Stobe.mod` (line 28), so it loads first (the bridge also
   retries if not). Check after the first launch that Vortex didn't drop it.
5. **Patch Stobe:**
   `python3 pending-fixes/harness-switch/patch_stobe_bridge.py /root/STOBE-src --build-bat /mnt/c/StobeBuild/build_portable.bat`
   then `build-stobe.ps1`, `install-dll.ps1 Stobe`.
6. **Patch the tools:** `python3 pending-fixes/harness-switch/patch_tools.py /mnt/c/KenshiModding`,
   then copy `tools/stobe-auto` and `tools/stobe-say` to `/usr/local/bin`.
7. **Switch on:** `stobe-say on` (creates enabled.flag); remove the old
   `RE_Kenshi\mods\Stobe\test_inbox.flag`.
8. **Smoke test** (`kenshi-ctl.ps1 launch -Save auto-home`, `stobe-auto wait-world`):
   - harness.log: `frame listener running`, `register command stobe_*` (6),
     `register before-attack hook`, autosave off; stobe.log: `TEST_HARNESS: connected ... 6 commands`
   - `stobe-auto help` lists the stobe_* commands
   - `stobe-auto status`, `where Shay`, `inv Malzin`, `give Malzin "Dried Meat" 1`
   - `stobe-say ping`, `stobe-say state Malzin`, `stobe-say speed 0` / `speed 1`
   - `stobe-say say Malzin "Hello"` gets a reply
   - `scenarios.sh fresh`, then a truce scenario: `stobe-auto attack` after a
     deal breaks the truce (stobe.log ceasefire lines)
   - `stobe-goal-watch.sh` pauses on an alert
9. **Then a normal full run**; log it in `archive/test-run-<date>.md`.
10. **Clean up:** sync `components/STOBE` (TestAutomation removed, bridge
    added), commit Stobe + tools (one commit each), update CLAUDE.md (test
    bed section: harness folder, enabled.flag, harness.log, `KAH:` lines,
    kah.py), remove the "in progress" note, delete this folder.

## Rollback

`kenshi-ctl.ps1` wrapper and tools: `git checkout` the four tool files and
recopy stobe-auto/stobe-say to /usr/local/bin. Stobe: copy main.cpp,
CMakeLists.txt and TestAutomation.cpp/.h back from the `components/STOBE`
snapshot committed in step 1, delete StobeHarnessBridge.* and
KenshiAutomationHarness.h from src, put `TestAutomation` back in
build_portable.bat, rebuild, `install-dll.ps1 Stobe`. Remove `AutomationHarness.mod`
from mods.cfg. Turn the old switch back on (`test_inbox.flag`).
