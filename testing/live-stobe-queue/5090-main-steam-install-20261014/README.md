# Main Steam manual-play Stobe install packet — 2026-10-14

Preparation only. No DLLs were changed and no game was launched.

The approved destination chosen by Shay is the 5090 Main Steam installation. The two Stobe plugin files are separate ordinary files (not links; each path chain had no reparse points) with distinct NTFS file IDs at packet preparation. Both had full SHA-256 `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C`:

| Label | Exact path | Observed current SHA-256 | NTFS file ID |
|---|---|---|---|
| RE_Kenshi | `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll` | `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` | `0x0000000000000000005c000000006829` |
| root-mods | `D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll` | `AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C` | `0x0000000000000000008100000000681c` |

Runtime receipts establish the ambiguity: older loaded-module evidence names the RE_Kenshi path; later main-instance module probes name the root `mods` path. Because the paths are distinct files, this packet pins and replaces both so either loader choice gets the same exact DLL. The process check blocks if any `kenshi_x64` game is running. Every component from `D:\Steam` through each DLL is checked and must remain a non-reparse path. The script has no target/source override and contains no 4080, instance-2/3, SSH, or launch route.

## Exact build pins

- Candidate: `C:\KenshiModding\pending-fixes\portrait-black-render\native-auth-chatbox-portrait-composite-abi-fix-20261014\build-v100\Stobe.dll`
- Candidate SHA-256: `769859CB364D1C719F94FC465265BEF9C7EF6803D40FAD7F6B695E8425354E9A`
- Exact-candidate review: `INDEPENDENT-REVIEW-769859CB.md`, SHA-256 `3A61A9FFD83EDFFD5A266400A5ED275DEBDF18A2BE2AAA1CB4D3E3F75CA8E5CB`; script verifies this receipt hash, CLEAR verdict, and candidate hash before planning/applying. The parser helper is itself pinned at SHA-256 `ABEC75329C6A2B80CB0FD96E9164AAA0B2B1CCE3F3E467C48C97A107873F9307`.
- Candidate scope is auth + ChatBox actor cache + portrait diagnostics atop AEF/AD63. It is not the complete set of project fixes and does not prove the portrait renders correctly. The deployment is for the requested manual play build; do not describe it as containing every unfinished backlog item.

## Guarded procedure (do not execute until packet review is CLEAR)

1. Confirm the candidate review, both scripts, and this packet’s independent exact review are CLEAR. Ensure the game is closed and there is no other game session running.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\install-main-steam.ps1` for plan-only preflight. It must report both exact targets, their pinned AEF baselines, candidate and review hashes, and a unique operation ID. Abort on any path/reparse/hash/process mismatch.
3. Apply only with that same operation ID: `powershell -NoProfile -ExecutionPolicy Bypass -File .\install-main-steam.ps1 -Apply -OperationId <printed-id>`.
4. The installer rechecks all pins, writes a unique same-directory temporary copy at each target, verifies both temp hashes, rechecks both target baselines, then uses atomic `File.Replace` with a unique per-target backup. It verifies each installed full hash and backup full baseline hash. If either replacement/check fails, it attempts a strict CAS rollback of already replaced target(s) and preserves the displaced candidate for investigation.
5. Save the generated `INSTALL-<operation-id>.receipt.md`; before opening the game, read-only hash both target paths and compare to the receipt. Runtime module loading is established only after the user opens the game; this packet never launches it.

Rollback is plan-only by default: `powershell -NoProfile -ExecutionPolicy Bypass -File .\rollback-main-steam.ps1 -OperationId <receipt-id>`. It restores a path only if its current full hash is exactly this candidate and the same operation’s backup is exactly that path’s AEF baseline; an already-restored baseline is left alone. Any drift, missing backup, reparse point, or running game aborts. Use `-Apply` only after confirming the exact receipt and stopped game. It preserves the displaced candidate beside the target.

Never use `tools/automation/install-dll.ps1 Stobe` for this packet: it reads the mutable `C:\StobeBuild\out\Stobe.dll`, only writes the root-mods path, copies in place without a full hash pin or rollback backup, and does not prove candidate review identity.

Test only the packet-contract self-test: `powershell -NoProfile -ExecutionPolicy Bypass -File .\selftest.ps1`. It parses all scripts, checks the fixed target allowlist and safety guards, validates the actual pinned review receipt, rejects wrong receipt/candidate hashes and a modified `REVISE` receipt, and confirms there are no other rig/instance or launch routes. It writes/removes only a unique negative-case file in `%TEMP%`; it does not contact or mutate the game, rigs, saves, or services.
