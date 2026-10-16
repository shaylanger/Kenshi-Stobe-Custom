<#
install-harness-4080-i4.ps1 -Action Plan|SelfTest|Apply|Rollback        (runs ON the 4080, PowerShell 5)   row 27-a prerequisite (imm26-u-rowsB)
Installs the current harness build (AutomationHarness.dll SHA256 EEED8C93..., has `contract-bodyguard`) into the ISOLATED lane i4 only:
C:\KenshiInst\4\mods\AutomationHarness\AutomationHarness.dll (preimage 974DBA03..., 1,084,416 B, answers `ERROR: unknown command` for contract-bodyguard).
Same guards as install-stobe-4080-nc6.ps1: instance marker, no reparse point on the path, link count 1, lane-4 game NOT running, lock owner rig4080 (or none),
candidate + preimage SHA256 pinned, backup + hash verify, atomic File.Replace. Rollback restores the backup from the receipt. SelfTest runs the whole
transaction on temp files (touches nothing of the lane). The candidate is already staged on the 4080: C:\KenshiTestRuns\staged\AutomationHarness-eeed8c93.dll
(otherwise: scp C:/KenshiModding/Kenshi-Automation-Harness/out/AutomationHarness.dll 4080:C:/KenshiTestRuns/staged/AutomationHarness-eeed8c93.dll).
After Apply: relaunch the lane from the row's save (C:\KAH\ctl.ps1 launch -Save kah-imm26-4080-i4h -Instance 4 -Owner rig4080) and run
  KAH_PF_ISOLATION=0 bash rowtools/unblockrun_b.sh 27-a 4080-i4 --save kah-imm26-4080-i4h
#>
[CmdletBinding()]
param([ValidateSet('Plan', 'SelfTest', 'Apply', 'Rollback')][string]$Action = 'Plan',
      [string]$CandidatePath = 'C:\KenshiTestRuns\staged\AutomationHarness-eeed8c93.dll', [string]$ReceiptDir = 'C:\KenshiTestRuns\staged')
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$Instance = 4
$NewSha = 'EEED8C932C672AA6BC4C9ACD7DDE45DC1DCB5D6A4EF77147F39236683BD8F4DE'
$OldSha = '974DBA03F136D6CB08153F29ACC497C485C39BAECEB8BF50C8B5291661D3025D'
$Root = "C:\KenshiInst\$Instance"; $Target = "$Root\mods\AutomationHarness\AutomationHarness.dll"; $Marker = "$Root\instance.txt"
$Lock = "C:\KenshiTestRuns\game-$Instance.lock"; $Receipt = "$ReceiptDir\4080-i$Instance-harness-eeed8c93-install-receipt.json"

function Get-Sha([string]$p) { if (Test-Path -LiteralPath $p -PathType Leaf) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() } else { '' } }
function Assert-Lane([string]$t) {
    if ($t -ine $Target) { throw "Refusing target $t (only $Target)" }
    if (-not (Test-Path -LiteralPath $Marker)) { throw "marker $Marker missing" }
    if ((Get-Content -LiteralPath $Marker -Raw) -notmatch "^instance=$Instance synced=") { throw "marker does not identify instance $Instance" }
    $cur = 'C:\'; foreach ($part in $t.Substring(3).Split('\')) { $cur = Join-Path $cur $part; if ((Test-Path -LiteralPath $cur) -and ((Get-Item -LiteralPath $cur -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "reparse point in path: $cur" } }
    $links = @(& fsutil hardlink list $t | Where-Object { $_ }).Count
    if ($links -ne 1) { throw "target has $links hard links (expected 1)" }
}
function Assert-Closed {
    foreach ($g in @(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'")) {
        if (-not $g.ExecutablePath) { throw "cannot identify Kenshi PID $($g.ProcessId)" }
        if ($g.ExecutablePath -like "$Root\*") { throw "lane i$Instance game PID $($g.ProcessId) is running; stop it first" }
    }
    if (Test-Path -LiteralPath $Lock) { $o = (Get-Content -LiteralPath $Lock -TotalCount 1).Trim(); if ($o -cne 'rig4080') { throw "lock owner '$o' not rig4080" } }
}
function Swap([string]$src, [string]$dst, [string]$old, [string]$new, [string]$rcpt) {
    if ((Get-Sha $src) -cne $new) { throw 'candidate SHA256 mismatch' }
    if ((Get-Sha $dst) -cne $old) { throw "target preimage mismatch: $(Get-Sha $dst)" }
    $bak = "$dst.pre-eeed8c93-$([guid]::NewGuid().ToString('N'))"; Copy-Item -LiteralPath $dst -Destination $bak
    if ((Get-Sha $bak) -cne $old) { throw 'backup hash mismatch' }
    [IO.File]::WriteAllText($rcpt, (@{ target = $dst; backup = $bak; oldSha = $old; newSha = $new; status = 'installing' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $tmp = Join-Path (Split-Path $dst) ('.AutomationHarness.dll.u-' + [guid]::NewGuid().ToString('N')); Copy-Item -LiteralPath $src -Destination $tmp
    try { [IO.File]::Replace($tmp, $dst, "$bak.displaced") } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
    if (Test-Path -LiteralPath "$bak.displaced") { Remove-Item -LiteralPath "$bak.displaced" -Force }
    if ((Get-Sha $dst) -cne $new) { throw 'post-install hash mismatch' }
    [IO.File]::WriteAllText($rcpt, (@{ target = $dst; backup = $bak; oldSha = $old; newSha = $new; status = 'installed' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
function Unswap([string]$rcpt, [string]$allowTarget) {
    $r = Get-Content -LiteralPath $rcpt -Raw | ConvertFrom-Json
    if ($r.target -ine $allowTarget) { throw 'receipt target mismatch' }
    if ((Get-Sha $r.backup) -cne $r.oldSha) { throw 'backup missing or changed' }
    $now = Get-Sha $r.target; if ($now -cne $r.newSha -and $now -cne $r.oldSha) { throw "target is unrelated bytes $now" }
    if ($now -ceq $r.newSha) { Copy-Item -LiteralPath $r.backup -Destination $r.target -Force }
    if ((Get-Sha $r.target) -cne $r.oldSha) { throw 'rollback hash mismatch' }
}

switch ($Action) {
    'Plan' {
        Assert-Lane $Target
        "lane=i$Instance target=$Target targetSha=$(Get-Sha $Target) expectedOld=$($OldSha.Substring(0,8)) candidateSha=$(Get-Sha $CandidatePath) expectedNew=$($NewSha.Substring(0,8)) gameRunning=$(@(Get-CimInstance Win32_Process -Filter "Name='kenshi_x64.exe'" | Where-Object { $_.ExecutablePath -like "$Root\*" }).Count)"
        if ((Get-Sha $CandidatePath) -cne $NewSha) { throw 'candidate not staged / wrong SHA' }
        if ((Get-Sha $Target) -ceq $NewSha) { 'NOTE: target already has the new build; Apply will refuse (preimage guard)' }
        elseif ((Get-Sha $Target) -cne $OldSha) { 'NOTE: target is not the pinned preimage; Apply will refuse' }
        'PLAN OK'
    }
    'SelfTest' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('hx-selftest-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
        try {
            [IO.File]::WriteAllText("$d\cand.dll", 'candidate-bytes'); [IO.File]::WriteAllText("$d\AutomationHarness.dll", 'old-bytes')
            $n = Get-Sha "$d\cand.dll"; $o = Get-Sha "$d\AutomationHarness.dll"
            Swap "$d\cand.dll" "$d\AutomationHarness.dll" $o $n "$d\r.json"
            if ((Get-Sha "$d\AutomationHarness.dll") -cne $n) { throw 'swap failed' }
            Unswap "$d\r.json" "$d\AutomationHarness.dll"
            if ((Get-Sha "$d\AutomationHarness.dll") -cne $o) { throw 'rollback failed' }
            try { Swap "$d\cand.dll" "$d\AutomationHarness.dll" 'DEADBEEF' $n "$d\r2.json"; throw 'preimage guard did not fire' } catch { if ($_.Exception.Message -notmatch 'preimage') { throw } }
            try { Assert-Lane "$Root\mods\Stobe\Stobe.dll"; throw 'wrong-path guard did not fire' } catch { if ($_.Exception.Message -notmatch 'Refusing target') { throw } }
            'SELFTEST PASS: swap, rollback, preimage guard, wrong-path guard'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }
    'Apply' { Assert-Lane $Target; Assert-Closed; Swap $CandidatePath $Target $OldSha $NewSha $Receipt; "INSTALL PASS: lane=i$Instance target=$Target sha256=$NewSha receipt=$Receipt" }
    'Rollback' { Assert-Lane $Target; Assert-Closed; Unswap $Receipt $Target; "ROLLBACK PASS: lane=i$Instance target=$Target sha256=$OldSha" }
}
