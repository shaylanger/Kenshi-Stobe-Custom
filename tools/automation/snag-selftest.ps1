# snag-selftest.ps1 (PI-49): offline selftest for snag.ps1 / snag.sh / snag-scan.ps1 (temp runs dir only). Exit 0 = all pass.
param([switch]$Keep)
$here = $PSScriptRoot
$tmp = Join-Path $env:TEMP ('snag-selftest-' + $PID)
if (Test-Path -LiteralPath $tmp) { Remove-Item -Recurse -Force -LiteralPath $tmp }
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:KAH_RUNS_DIR = $tmp
$log = Join-Path $tmp 'snags\snags.log'
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { $script:pass++; Write-Host "PASS $n" } else { $script:fail++; Write-Host "FAIL $n $d" } }
function Snag($op, $sl, $sym, $wk) { & (Join-Path $here 'snag.ps1') $op $sl $sym $wk | Out-Null }
function Scan { @(& (Join-Path $here 'snag-scan.ps1') -Runs $tmp) }

Check 'scan with no log -> no event' ((Scan).Count -eq 0)
Snag 'op9o' 'hxdefs.sh:30' 'false SETUP-FAIL writing /c/...' 'use /mnt/c path'
Check 'helper wrote one line' ((Test-Path $log) -and @(Get-Content $log).Count -eq 1)
Check 'line format' ((Get-Content $log -Raw) -match '^SNAG hxdefs\.sh:30 op=op9o false SETUP-FAIL writing /c/\.\.\. \| workaround: use /mnt/c path')
Snag 'op9o' 'hxdefs.sh:30' 'same again' 'same'
Check 'one operator twice -> no event' ((Scan).Count -eq 0)
Snag 'OP22' 'tools/automation/hxdefs.sh:30' 'SETUP-FAIL false positive (different wording)' 'convert path'
$e = @(Scan)
Check 'second distinct operator (normalized key, case) -> exactly one event' ($e.Count -eq 1) "got $($e.Count)"
Check 'event format' ($e[0] -match '^SNAG REPEAT hxdefs\.sh:30 by op9o,op22: .*\| workaround: convert path \| propose root fix$') "got $($e[0])"
Check 'rescan -> no repeat of same key' ((Scan).Count -eq 0)
Check 'emitted.txt marked' ((Get-Content (Join-Path $tmp 'snags\emitted.txt') -Raw) -match "hxdefs\.sh:30`t2")
Snag 'op14' 'hxdefs.sh:30' 'again' 'x'
$e = @(Scan)
Check 'third operator -> one more event' ($e.Count -eq 1 -and $e[0] -match 'by op9o,op22,op14:') "got $($e -join ' // ')"
Check 'then quiet again' ((Scan).Count -eq 0)
Snag 'op14' 'lane-deploy.sh:77' 'deletes inject seam' 'redeploy seam'
Check 'different key, 1 operator -> no event' ((Scan).Count -eq 0)
Snag 'op9o' 'lane-deploy.sh:78' 'other line' 'x'
Check 'different line number is a different key' ((Scan).Count -eq 0)
# malformed lines ignored
[IO.File]::AppendAllText($log, "garbage line`nSNAG nocolon op=a sym | workaround: w`nSNAG a.sh:1 noop here | workaround: w`nSNAG :5 op=z x | workaround: y`nSNAG a.sh:1 op=q`n")
Check 'malformed lines ignored' ((Scan).Count -eq 0)
# bad usage writes nothing
$before = @(Get-Content $log).Count
& (Join-Path $here 'snag.ps1') 'op1' 'nocolon' 'sym' 'wk' 2>$null | Out-Null
Check 'bad usage exit 2, nothing written' (($LASTEXITCODE -eq 2) -and @(Get-Content $log).Count -eq $before)
# pipes and newlines in text are sanitized
Snag 'op5' 'x.sh:9' "multi`nline | pipe" 'a | b'
Check 'sanitized line parses' ((Get-Content $log)[-1] -match '^SNAG x\.sh:9 op=op5 multi line / pipe \| workaround: a / b$') (Get-Content $log)[-1]
# DryRun does not mark
Snag 'op6' 'x.sh:9' 'second op' 'w'
$d = @(& (Join-Path $here 'snag-scan.ps1') -Runs $tmp -DryRun)
Check 'dry run emits' ($d.Count -eq 1)
Check 'dry run did not mark: next real scan still emits' ((Scan).Count -eq 1)
# bash twin (WSL/Git Bash), same format, same scan
$bash = @('C:\Program Files\Git\bin\bash.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($bash) {
    $sh = ((Join-Path $here 'snag.sh').Replace([string][char]92, '/'))
    $t = $tmp.Replace([string][char]92, '/'); if ($t -match '^([A-Za-z]):(.*)$') { $t = '/' + $Matches[1].ToLower() + $Matches[2] }
    $r = & $bash -c "KAH_RUNS_DIR='$t' bash '$sh' op7 y.sh:3 'bash symptom | p' 'bash wk'" 2>&1
    Check 'snag.sh writes the line' ((Get-Content $log)[-1] -eq 'SNAG y.sh:3 op=op7 bash symptom / p | workaround: bash wk') (Get-Content $log)[-1]
    & $bash -c "KAH_RUNS_DIR='$t' bash '$sh' op8 y.sh:3 'ps symptom' 'w2'" 2>&1 | Out-Null
    $e = @(Scan)
    Check 'snag.sh lines counted by scan' ($e.Count -eq 1 -and $e[0] -match 'y\.sh:3 by op7,op8') "got $($e -join ' // ')"
    & $bash -c "KAH_RUNS_DIR='$t' bash '$sh' op1 nocolon s w" 2>&1 | Out-Null
    Check 'snag.sh bad usage exit 2' ($LASTEXITCODE -eq 2)
} else { Write-Host 'SKIP bash twin (no bash)' }
Remove-Item Env:\KAH_RUNS_DIR -ErrorAction SilentlyContinue
if (-not $Keep) { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
Write-Host "snag-selftest: $pass passed, $fail failed"
exit $(if ($fail) { 1 } else { 0 })
