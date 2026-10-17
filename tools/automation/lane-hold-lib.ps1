# lane-hold-lib.ps1 (PI-50, Shay 2026-10-16): auto lane holds in <runs>\lanes.held. Dot-source it.
# A deliberately parked lane (agent-abandon.ps1 <op> "parked: <why>") gets ONE line:
#   <lane>  # auto-hold from=yyyy-MM-dd HH:mm until=yyyy-MM-dd HH:mm by=<op> reason=<abandon reason>
# Old readers strip '#...' and see the plain lane name. Manual lines (no 'auto-hold') never expire and are never removed by code.
# Expired auto holds stop suppressing (Get-ActiveHolds skips them); they are cleaned out of the file on the next Add/Remove.
# A hold is released by: lane-brief.ps1 -Name <successor> (Remove-LaneHold), or lane-idle.ps1 seeing a RUNNING operator status for the lane
# newer than the hold's from= time (Release-HoldsForNewOperator).
$script:HoldFmt = 'yyyy-MM-dd HH:mm'
function Get-LaneOfOperator([string]$Name, [string]$Runs) {
    $ov = Join-Path $Runs 'lane-owners.json'
    if (Test-Path -LiteralPath $ov) {
        try { $j = Get-Content -LiteralPath $ov -Raw | ConvertFrom-Json; foreach ($p in $j.psobject.Properties) { if (@($p.Value.ops) -contains $Name) { return $p.Name } } } catch { }
    }
    if ($Name -match '^imm26-(5090|4080)-i(\d)op') { return "$($Matches[1])-i$($Matches[2])" }
    if ($Name -match '^imm26-5090-ctxop') { return '5090-i5' }
    if ($Name -match '^imm26-4080-op') { return '4080-i3' }
    return $null
}
function Read-LaneHolds([string]$Runs) {
    $f = Join-Path $Runs 'lanes.held'; $out = @()
    if (-not (Test-Path -LiteralPath $f)) { return $out }
    foreach ($line in @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
        $lane = ($line -replace '#.*$', '').Trim()
        if (-not $lane) { continue }
        $auto = $line -match '#\s*auto-hold\b'
        $from = $null; $until = $null
        if ($line -match 'from=(\d{4}-\d\d-\d\d \d\d:\d\d)') { $from = [datetime]::ParseExact($Matches[1], $script:HoldFmt, $null) }
        if ($line -match 'until=(\d{4}-\d\d-\d\d \d\d:\d\d)') { $until = [datetime]::ParseExact($Matches[1], $script:HoldFmt, $null) }
        $out += [pscustomobject]@{ Lane = $lane; Auto = $auto; From = $from; Until = $until; Line = $line }
    }
    $out
}
function Test-HoldExpired($h, [datetime]$Now = (Get-Date)) { $h.Auto -and $h.Until -and $Now -ge $h.Until }
function Get-ActiveHolds([string]$Runs, [datetime]$Now = (Get-Date)) {
    @(Read-LaneHolds $Runs | Where-Object { -not (Test-HoldExpired $_ $Now) } | ForEach-Object { $_.Lane })
}
function Write-LaneHolds([string]$Runs, [string[]]$Lines) {
    $f = Join-Path $Runs 'lanes.held'
    $tmp = "$f.tmp"; Set-Content -LiteralPath $tmp -Value $Lines -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $f -Force
}
# keep comments/manual lines; drop auto lines for $DropLane (or expired ones when $DropExpired)
function Update-LaneHolds([string]$Runs, [string]$DropLane, [string[]]$Append = @(), [datetime]$Now = (Get-Date)) {
    $f = Join-Path $Runs 'lanes.held'; $keep = @(); $dropped = $false
    if (Test-Path -LiteralPath $f) {
        $parsed = @{}; foreach ($h in @(Read-LaneHolds $Runs)) { $parsed[$h.Line] = $h }
        foreach ($line in @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
            $h = $parsed[$line]
            if ($h -and $h.Auto -and ((Test-HoldExpired $h $Now) -or ($DropLane -and $h.Lane -eq $DropLane))) { if ($DropLane -and $h.Lane -eq $DropLane) { $dropped = $true }; continue }
            $keep += $line
        }
    }
    $keep += $Append
    if ($keep.Count -gt 0 -or (Test-Path -LiteralPath $f)) { Write-LaneHolds $Runs $keep }
    $dropped
}
function Add-LaneHold([string]$Runs, [string]$Lane, [string]$Reason, [string]$By, [double]$Hours = 2, [datetime]$Now = (Get-Date)) {
    $r = ($Reason -replace '\s+', ' ').Trim()
    $line = "$Lane  # auto-hold from=$($Now.ToString($script:HoldFmt)) until=$($Now.AddHours($Hours).ToString($script:HoldFmt)) by=$By reason=$r"
    $null = Update-LaneHolds $Runs $Lane @($line) $Now   # replaces an older auto hold of the same lane
    $line
}
function Remove-LaneHold([string]$Runs, [string]$Lane) { [bool](Update-LaneHolds $Runs $Lane @()) }
# lane-idle.ps1: an auto-held lane whose operator list now has a RUNNING (non-abandoned) status written after from= is no longer parked
function Release-HoldsForNewOperator([string]$Runs, $Lanes, [datetime]$Now = (Get-Date)) {
    $rel = @()
    foreach ($h in @(Read-LaneHolds $Runs)) {
        if (-not $h.Auto -or (Test-HoldExpired $h $Now) -or -not $h.From -or -not $Lanes.Contains($h.Lane)) { continue }
        foreach ($op in @($Lanes[$h.Lane].ops)) {
            $sf = Join-Path $Runs "agents\$op.status"
            if (-not (Test-Path -LiteralPath $sf) -or (Test-Path -LiteralPath (Join-Path $Runs "agents\$op.abandoned"))) { continue }
            $first = ((Get-Content -LiteralPath $sf -TotalCount 1) -as [string]) -replace '^\uFEFF', ''
            if ($first -match '\|\s*RUNNING\s*\|' -and (Get-Item -LiteralPath $sf).LastWriteTime -gt $h.From) { if (Remove-LaneHold $Runs $h.Lane) { $rel += $h.Lane }; break }
        }
    }
    $rel
}
