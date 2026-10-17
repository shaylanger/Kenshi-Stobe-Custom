# lane-hold-selftest.ps1 (PI-50): a 'parked' abandon puts the lane on lanes.held for 2 h (carrying the reason); a new operator releases it; expiry stops suppression.
# Offline: temp runs dir via KAH_RUNS_DIR / -Runs; no lane is touched.  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\lane-hold-selftest.ps1
$ErrorActionPreference = 'Stop'
$auto = $PSScriptRoot
$d = Join-Path ([IO.Path]::GetTempPath()) ("lanehold-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'agents'), (Join-Path $d 'inflight'), (Join-Path $d 'respawn') | Out-Null
$oldRuns = $env:KAH_RUNS_DIR; $env:KAH_RUNS_DIR = $d
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "SELFTEST PASS $n" } else { $script:fail++; "SELFTEST FAIL $n" } }
function Set-St([string]$name, [string]$state, [int]$ageMin = 1) {
    $f = Join-Path $d "agents\$name.status"
    Set-Content -LiteralPath $f -Value @("$name | $state | $(Get-Date -Format 'yyyy-MM-dd HH:mm')", 'task: t', 'latest: l', 'outputs: o', 'next: n') -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
function Idle { @(& (Join-Path $auto 'lane-idle.ps1') -NoMemory -Runs $d 2>&1 | ForEach-Object { "$_" }) }
function NoOp([string]$lane) { @(Idle | Where-Object { $_ -match "^LANE NO-OPERATOR $([regex]::Escape($lane)) " }).Count }
function Abandon([string]$name, [string]$why) { (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'agent-abandon.ps1') $name $why 2>&1 | ForEach-Object { "$_" }) -join ' ' }
$held = Join-Path $d 'lanes.held'
try {
    . (Join-Path $auto 'lane-hold-lib.ps1')
    # 1. before: a stopped operator -> the lane raises NO-OPERATOR
    Set-St 'imm26-5090-i3op3' 'STOPPED-CONTEXT' 5
    T ((NoOp '5090-i3') -eq 1) 'no hold: stopped operator raises LANE NO-OPERATOR'
    # 2. a non-parked abandon never holds
    $o = Abandon 'imm26-5090-i3op3' 'dropped on purpose'
    T (-not (Test-Path -LiteralPath $held) -and (Test-Path -LiteralPath (Join-Path $d 'agents\imm26-5090-i3op3.abandoned'))) "non-parked abandon: no lanes.held ($o)"
    # 3. parked abandon -> auto-hold, 2 h, reason carried
    Remove-Item (Join-Path $d 'agents\imm26-5090-i3op3.abandoned')
    $o = Abandon 'imm26-5090-i3op3' 'parked: waiting for fixer candidates'
    $txt = (Get-Content -Raw -LiteralPath $held)
    T ($txt -match '(?m)^5090-i3\s+# auto-hold from=' -and $txt.Contains('by=imm26-5090-i3op3') -and $txt.Contains('reason=parked: waiting for fixer candidates')) "parked abandon writes the hold with the reason ($($txt.Trim()))"
    $h = @(Read-LaneHolds $d)[0]
    T ($h.Auto -and [math]::Abs(($h.Until - $h.From).TotalMinutes - 120) -le 1 -and $h.Until -gt (Get-Date).AddMinutes(100)) 'expiry is 2 h after the abandon'
    T ($o -match 'lane 5090-i3 held 2 h') "abandon prints the hold ($o)"
    # 4. held lane raises nothing; other lanes unaffected
    T ((NoOp '5090-i3') -eq 0 -and (NoOp '4080-i4') -eq 1) 'held lane: no NO-OPERATOR; other lanes still report'
    # 6. expired hold stops suppressing
    $exp = (Get-Date).AddMinutes(-5).ToString('yyyy-MM-dd HH:mm')
    (Get-Content -Raw -LiteralPath $held) -replace 'until=\d{4}-\d\d-\d\d \d\d:\d\d', "until=$exp" | Set-Content -LiteralPath $held -Encoding UTF8
    T ((NoOp '5090-i3') -eq 1) 'expired hold no longer suppresses'
    T (@(Get-ActiveHolds $d).Count -eq 0) 'Get-ActiveHolds skips the expired hold'
    # 7. re-park replaces the old line (one line per lane); manual lines survive
    Add-Content -LiteralPath $held -Value "4080-i3`n# my note" -Encoding UTF8
    $null = Abandon 'imm26-5090-i3op3' 'parked: again'
    $lines = @(Get-Content -LiteralPath $held)
    T (@($lines | Where-Object { $_ -match '^5090-i3\s' }).Count -eq 1 -and ($lines -contains '4080-i3') -and ($lines -contains '# my note')) 'one auto line per lane; manual lines and comments untouched'
    T ((NoOp '5090-i3') -eq 0 -and (NoOp '4080-i3') -eq 0) 'fresh hold and manual (no expiry) hold both suppress'
    # 8. a new RUNNING operator status for the lane releases the auto-hold (not the manual one)
    Set-St 'imm26-5090-i3op4' 'RUNNING' 0
    Set-Content -LiteralPath (Join-Path $d 'lane-owners.json') -Value '{"5090-i3":{"ops":["imm26-5090-i3op4","imm26-5090-i3op3"],"dirs":["x"]}}' -Encoding UTF8
    $null = Idle
    $lines = @(Get-Content -LiteralPath $held)
    T (@($lines | Where-Object { $_ -match '^5090-i3\s' }).Count -eq 0 -and ($lines -contains '4080-i3')) 'new RUNNING operator status releases the auto-hold, manual hold stays'
    # 9. an OLD running status (before the hold) does not release
    $null = Abandon 'imm26-5090-i3op4' 'parked: second park'
    Set-St 'imm26-5090-i3op4' 'RUNNING' 30
    $null = Idle
    T (@(Get-Content -LiteralPath $held | Where-Object { $_ -match '^5090-i3\s' }).Count -eq 1) 'a status older than the hold does not release it'
    # 10. lane-brief.ps1 -Name <successor> releases the auto-hold
    $ErrorActionPreference = 'Continue'
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $auto 'lane-brief.ps1') 5090-i3 -Name imm26-5090-i3op5 -Predecessor imm26-5090-i3op4 -NoRemote -Runs $d -Repo $d 2>&1
    $ErrorActionPreference = 'Stop'
    T (@(Get-Content -LiteralPath $held | Where-Object { $_ -match '^5090-i3\s' }).Count -eq 0) 'lane-brief.ps1 -Name <successor> removes the lane from lanes.held'
    T ((Get-Content -Raw -LiteralPath $held).Contains('4080-i3')) 'manual hold survives lane-brief of another lane'
    # 11. unknown agent for 'parked': no crash, no hold
    Set-St 'some-random-agent' 'DONE' 3
    $o = Abandon 'some-random-agent' 'parked: x'
    T ($o -match 'no lane known' -and -not (Get-Content -Raw -LiteralPath $held).Contains('some-random')) "agent with no lane: abandoned, hold unchanged ($o)"
    # 12. selftests of the unchanged callers still read lanes.held lines with comments (old parser compatibility)
    T (((Get-Content -LiteralPath $held) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }) -contains '4080-i3') 'old comment-stripping readers still see plain lane names'
} finally {
    if ($null -eq $oldRuns) { Remove-Item Env:KAH_RUNS_DIR -ErrorAction SilentlyContinue } else { $env:KAH_RUNS_DIR = $oldRuns }
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST lane-hold $script:pass pass / $script:fail fail"
if ($script:fail) { exit 1 }
exit 0
