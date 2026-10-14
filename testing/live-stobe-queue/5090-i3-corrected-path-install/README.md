# 5090 i3 corrected-path native install packet

Preparation only. This packet was not executed and made no external writes. It targets the actual loaded plugin path `D:\KenshiInst\3\RE_Kenshi\mods\Stobe\Stobe.dll`. The sibling `D:\KenshiInst\3\mods\Stobe\Stobe.dll` is a wrong-path copy and is never accepted as proof of installation.

Read-only inventory at packet preparation:

- Instance marker: `D:\KenshiInst\3\instance.txt` → `instance=3 synced=2026-10-11T20:27:44 from=D:\Steam\steamapps\common\Kenshi`
- Lock owner: `5090c-ui-setup-20261014`
- Required stopped game PID: `113932`; installer also refuses any running D3 `RE_Kenshi\kenshi_x64.exe` process.
- Actual runtime target SHA-256: `40414D8C70E5E377D2FE1EB8C42C167D6B21F3D20CD7077B5ECB8D5661E7101D` (3,809,280 bytes). This exact DLL becomes the rollback source.
- Wrong-path sibling SHA-256: `BC9D2F91F8DD134CD8E8BA79514703C158923DC43EB2B8D9F4C361A8E34494A2` (3,865,088 bytes). It is not installed at the target path.
- Candidate pin under investigation: `BC9D2F91F8DD134CD8E8BA79514703C158923DC43EB2B8D9F4C361A8E34494A2`.

## Candidate hold

The pinned BC9D candidate is **rejected unconditionally** by `install-corrected-path.ps1`. Read-only PE inspection proves that it imports `?getColourWriteEnabled@Pass@Ogre@@QEBA_NXZ`, but the exact D3 `OgreMain_x64.dll` exports only `?getColourWriteEnabled@Pass@Ogre@@QEBAEXZ`. This missing ABI-decorated import prevents the plugin DLL from loading. Its architecture and `startPlugin` export are correct, but that does not make it loadable. Do not deploy BC9D to either location.

A future candidate needs a new SHA-256, an independent exact-hash **CLEAR**, fresh boundary receipt, and a complete `check-pe-imports.ps1` pass against `D:\KenshiInst\3` and the current Windows system DLLs. The import gate checks x64 architecture, the exact `startPlugin` export, resolves every imported module, and verifies every imported name against that resolved DLL's exports. It reports dependency hashes alongside the result. The checker is read-only.

## Install and rollback behavior

The install script is plan-only by default. `-Apply` requires all receipt and hash pins, the exact canonical instance marker and lock owner, PID 113932 absent, all D3 game processes stopped, the actual target still at the recorded runtime hash, and the full import/export gate passing. It refuses the known BC9D hash before any write. The wrong-path sibling is recorded as informational only and is never used for the target hash or rollback.

After every gate passes, it copies the current target into a unique same-volume rollback directory through atomic `File.Replace`; it verifies that backup against the recorded current-runtime SHA and verifies the new target against the future candidate SHA. Rollback is compare-and-swap: it requires the target to remain exactly the candidate hash and the backup to remain exactly the original runtime hash, then atomically restores while retaining the displaced candidate.

## Explicit plan-only command for the next compatible candidate

Use fresh paths and hashes from the next reviewed candidate and receipts. The placeholders below are intentionally invalid until supplied. Omit `-Apply` for the plan-only preflight:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\testing\live-stobe-queue\5090-i3-corrected-path-install\install-corrected-path.ps1 `
  -CandidateDll 'C:\KenshiModding\pending-fixes\<new-compatible-candidate>\Stobe.dll' `
  -CandidateSha256 '<new-64-hex-candidate-hash>' `
  -ReviewReceipt 'C:\KenshiModding\pending-fixes\<new-compatible-candidate>\INDEPENDENT-REVIEW.json' `
  -ReviewReceiptSha256 '<review-receipt-sha256>' `
  -BoundaryReceipt 'C:\KenshiTestRuns\<fresh-authorized-boundary>.json' `
  -BoundaryReceiptSha256 '<boundary-receipt-sha256>' `
  -BackupDirectory 'D:\KenshiInst\3\stobe-corrected-path-rollback-<unique-id>' `
  -Dumpbin 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64\dumpbin.exe'
```

Do not run this against BC9D. The focused selftest and both timestamp regressions are listed in `selftest-corrected-path.ps1` and the shared packet timestamp test. Neither executes an install.
