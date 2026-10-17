# tail-relay-dedupe-selftest.ps1 (PI-57, Shay 2026-10-16): tail-relay.ps1 drops a relay whose content hash equals one already delivered for the
# same agent within the last 2 h (an agent waiting on its own background job re-sent the same DONE report 7 times).
# Temp runs dir only (KAH_RUNS_DIR / KPL_DIR); never touches C:\KenshiTestRuns. Prints PASS/FAIL lines and "SELFTEST PASS n/m" (exit 1 on any FAIL).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tail-relay-dedupe-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$rdir = Join-Path $tmp 'runs'; $inbox = Join-Path $rdir 'inbox\coordinator'
$old = @{ KAH_RUNS_DIR = $env:KAH_RUNS_DIR; KPL_DIR = $env:KPL_DIR; KPL_WS = $env:KPL_WS; KAH_RELAY_NODEDUPE = $env:KAH_RELAY_NODEDUPE }
New-Item -ItemType Directory -Force -Path (Join-Path $rdir 'agents'), (Join-Path $rdir 'tail'), (Join-Path $rdir 'programs'), (Join-Path $tmp 'ws'), $inbox | Out-Null
$env:KAH_RUNS_DIR = $rdir; $env:KPL_DIR = Join-Path $rdir 'programs'; $env:KPL_WS = Join-Path $tmp 'ws'
Remove-Item Env:KAH_RELAY_NODEDUPE -ErrorAction SilentlyContinue
$relay = Join-Path $here 'tail-relay.ps1'
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function RunRelay([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $relay @a 2>&1
    [pscustomobject]@{ code = $LASTEXITCODE; out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function Msgs([string]$n) { @(Get-ChildItem -LiteralPath $inbox -Filter "*-tail-$n.msg" -File -ErrorAction SilentlyContinue) }
$log = Join-Path $rdir 'tail\relay-dedupe.log'
try {
    $rep = Join-Path $tmp 'rep.md'; Set-Content -LiteralPath $rep -Value @('# agD', 'RESULT 1 PASS', 'commit abc') -Encoding UTF8
    $r1 = RunRelay @('-Agent', 'agD', '-Kind', 'DONE', '-Report', $rep)
    T ($r1.code -eq 0 -and (Msgs 'agD').Count -eq 1) '1 first relay is delivered (1 inbox file)'
    Start-Sleep -Seconds 1
    $r2 = RunRelay @('-Agent', 'agD', '-Kind', 'DONE', '-Report', $rep)
    T ($r2.code -eq 0 -and (Msgs 'agD').Count -eq 1 -and $r2.out -match 'DROPPED' -and $r2.out -match 'duplicate relay dropped') '2 identical second relay is dropped (still 1 inbox file, exit 0, says DROPPED)'
    T ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'DROP duplicate relay agent=agD kind=DONE')) '3 the drop is logged in tail\relay-dedupe.log'
    # consumed inbox file (coordinator moved it away) is still a duplicate
    Get-ChildItem -LiteralPath $inbox -File | Remove-Item -Force
    $r2b = RunRelay @('-Agent', 'agD', '-Kind', 'DONE', '-Report', $rep)
    T ((Msgs 'agD').Count -eq 0 -and $r2b.out -match 'DROPPED') '3b still dropped after the delivered inbox file was consumed'
    # different agent, same text
    $r3 = RunRelay @('-Agent', 'agE', '-Kind', 'DONE', '-Report', $rep)
    T ((Msgs 'agE').Count -eq 1) '4 the same content from a DIFFERENT agent is delivered'
    # changed report -> new relay
    Add-Content -LiteralPath $rep -Value 'RESULT 2 PASS (new)' -Encoding UTF8
    $r4 = RunRelay @('-Agent', 'agD', '-Kind', 'DONE', '-Report', $rep)
    T ((Msgs 'agD').Count -eq 1 -and $r4.out -notmatch 'DROPPED') '5 a changed report/body is delivered again'
    # different summary only
    $r5 = RunRelay @('-Agent', 'agF', '-Kind', 'DONE', '-Summary', 'result A')
    Start-Sleep -Seconds 1
    $r5b = RunRelay @('-Agent', 'agF', '-Kind', 'DONE', '-Summary', 'result B')
    T ((Msgs 'agF').Count -eq 2) '6 same agent, different summary text: both delivered'
    # STALL is never deduped
    $null = RunRelay @('-Agent', 'agG', '-Kind', 'STALL', '-Summary', 'silent 10 min')
    Start-Sleep -Seconds 1
    $null = RunRelay @('-Agent', 'agG', '-Kind', 'STALL', '-Summary', 'silent 10 min')
    T ((Msgs 'agG').Count -eq 2) '7 repeated identical STALL relays are NOT deduped'
    # -Force bypass
    Start-Sleep -Seconds 1
    $r8 = RunRelay @('-Agent', 'agF', '-Kind', 'DONE', '-Summary', 'result B', '-Force')
    T ((Msgs 'agF').Count -eq 3) '8 -Force bypasses the dedupe'
    # window: age the stored hash past 2 h -> delivered again
    $df = Join-Path $rdir 'tail\relay-dedupe\agH.json'
    $null = RunRelay @('-Agent', 'agH', '-Kind', 'DONE', '-Summary', 'old result')
    $j = @(Get-Content $df -Raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_.time = (Get-Date).AddMinutes(-130).ToString('o'); $_ }
    [IO.File]::WriteAllText($df, (ConvertTo-Json -InputObject @($j) -Depth 3))
    Start-Sleep -Seconds 1
    $null = RunRelay @('-Agent', 'agH', '-Kind', 'DONE', '-Summary', 'old result')
    T ((Msgs 'agH').Count -eq 2) '9 an identical relay older than 2 h is delivered again'
} finally {
    foreach ($k in $old.Keys) { if ($null -eq $old[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:$k" $old[$k] } }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
