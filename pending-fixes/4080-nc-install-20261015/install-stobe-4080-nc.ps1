<#
install-stobe-4080-nc.ps1 -Instance 3|4 -Action Plan|SelfTest|Apply|Rollback        (runs ON the 4080, PowerShell 5)
Installs the NC Stobe.dll (SHA256 4D18E32C..., pending-fixes\npc-immersion-26\NC\Stobe.dll) into ONE isolated 4080 lane's active plugin path
C:\KenshiInst\<n>\mods\Stobe\Stobe.dll (the E607 reviewed release -> NC). Lane i3 / i4 only; never the Steam install, never instance 1/2.
Guards: instance marker, no reparse point on the target path, link count 1, lane game NOT running, lock owner rig4080, candidate and preimage
SHA256 pinned, backup + hash verify, atomic File.Replace. Rollback restores the backup from the receipt. SelfTest runs the whole transaction on temp files.
Candidate default: C:\KenshiTestRuns\staged\Stobe-NC-4D18E32C.dll (copy it there first).
#>
[CmdletBinding()]
param([ValidateSet('Plan', 'SelfTest', 'Apply', 'Rollback')][string]$Action = 'Plan', [ValidateSet(3, 4)][int]$Instance = 3,
      [string]$CandidatePath = 'C:\KenshiTestRuns\staged\Stobe-NC-4D18E32C.dll', [string]$ReceiptDir = 'C:\KenshiTestRuns\staged')
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$NewSha = '4D18E32CE45C08B799B56A9FC5E998BAFC270C3F1881543573C61BFAB3568766'
$OldSha = 'E60752C828AB096C7856F79490EC4FB16E015F40887338199471B0E53A0938C6'
$Root = "C:\KenshiInst\$Instance"; $Target = "$Root\mods\Stobe\Stobe.dll"; $Marker = "$Root\instance.txt"
$Lock = "C:\KenshiTestRuns\game-$Instance.lock"; $Receipt = "$ReceiptDir\4080-i$Instance-nc-install-receipt.json"

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
    $bak = "$dst.pre-nc-$([guid]::NewGuid().ToString('N'))"; Copy-Item -LiteralPath $dst -Destination $bak
    if ((Get-Sha $bak) -cne $old) { throw 'backup hash mismatch' }
    [IO.File]::WriteAllText($rcpt, (@{ target = $dst; backup = $bak; oldSha = $old; newSha = $new; status = 'installing' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $tmp = Join-Path (Split-Path $dst) ('.Stobe.dll.nc-' + [guid]::NewGuid().ToString('N')); Copy-Item -LiteralPath $src -Destination $tmp
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
        if ((Get-Sha $Target) -cne $OldSha) { 'NOTE: target is not the E607 preimage (already NC or other); Apply will refuse' }
        'PLAN OK'
    }
    'SelfTest' {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('nc-selftest-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
        try {
            [IO.File]::WriteAllText("$d\cand.dll", 'candidate-bytes'); [IO.File]::WriteAllText("$d\Stobe.dll", 'old-bytes')
            $n = Get-Sha "$d\cand.dll"; $o = Get-Sha "$d\Stobe.dll"
            Swap "$d\cand.dll" "$d\Stobe.dll" $o $n "$d\r.json"
            if ((Get-Sha "$d\Stobe.dll") -cne $n) { throw 'swap failed' }
            Unswap "$d\r.json" "$d\Stobe.dll"
            if ((Get-Sha "$d\Stobe.dll") -cne $o) { throw 'rollback failed' }
            try { Swap "$d\cand.dll" "$d\Stobe.dll" 'DEADBEEF' $n "$d\r2.json"; throw 'preimage guard did not fire' } catch { if ($_.Exception.Message -notmatch 'preimage') { throw } }
            try { Assert-Lane "$Root\RE_Kenshi\mods\Stobe\Stobe.dll"; throw 'wrong-path guard did not fire' } catch { if ($_.Exception.Message -notmatch 'Refusing target') { throw } }
            'SELFTEST PASS: swap, rollback, preimage guard, wrong-path guard'
        } finally { Remove-Item -LiteralPath $d -Recurse -Force }
    }
    'Apply' { Assert-Lane $Target; Assert-Closed; Swap $CandidatePath $Target $OldSha $NewSha $Receipt; "INSTALL PASS: lane=i$Instance target=$Target sha256=$NewSha receipt=$Receipt" }
    'Rollback' { Assert-Lane $Target; Assert-Closed; Unswap $Receipt $Target; "ROLLBACK PASS: lane=i$Instance target=$Target sha256=$OldSha" }
}
