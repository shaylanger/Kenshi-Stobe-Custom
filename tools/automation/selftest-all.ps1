# selftest-all.ps1 (PI-13, Shay 2026-10-15): run EVERY selftest one by one, print one line per test, never paste logs.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\selftest-all.ps1 [-TimeoutSec 120] [-Include slow] [-Only <wildcard,...>] [-List]
# Discovers: tools\automation\*-selftest.ps1 (powershell), *-selftest.sh (WSL bash), *-selftest.py (WSL python3),
#            and the rowtools selftests under testing\live-stobe-queue\imm26-assert (selftest.sh, rowtools\selftest.sh; WSL bash).
# Output:    SELFTEST <name> PASS|FAIL|SKIP <secs>      one line per test
#            SELFTEST-ALL <n> pass / <n> fail / <n> skip   final line; exit 1 on any FAIL (a timeout counts as FAIL)
#            full output of every FAIL -> C:\KenshiTestRuns\selftest\<name>.txt (path printed after the FAIL line, nothing else).
# PASS = exit code 0 and no output line "SELFTEST ... FAIL" (a selftest must exit non-zero on failure; RESULT lines with FAIL are data, e.g. expected-FAIL cases). Selftests must use fixtures / temp dirs, never live state or a lane.
# SKIP: tests in $SkipTable (start a game, touch a lane / Shay's live install / server / DB, or take > 2 min) run only with -Include slow;
#       a test that needs WSL is SKIPped (not FAILed) when WSL is not available. Add a new slow/unsafe test to $SkipTable with the reason.
# This script only READS and runs the selftests; it edits nothing. Run it at every handoff (testing\AGENT_PROMPTS.md step 4b) and after tooling changes.
param(
    [int]$TimeoutSec = 120,
    [string[]]$Include = @(),      # 'slow' = also run the SkipTable tests
    [string[]]$Only = @(),         # wildcard filters on the test name
    [switch]$List,
    [string]$OutDir = 'C:\KenshiTestRuns\selftest',
    [string]$Distro = 'DwemerAI4Skyrim3'
)
$ErrorActionPreference = 'Continue'
$ws = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # C:\KenshiModding
$auto = $PSScriptRoot

# name -> reason. Documented skip flags (run with -Include slow). Keep empty entries out; a reason is mandatory.
$SkipTable = @{
    'rowtools' = 'takes about 3.5 min (51 checks incl. the trip family; rowtools\selftest.sh also runs trip-selftest.sh)'
}
# name -> own timeout (s) for tests that are legitimately long but under 2-3 min; -TimeoutSec is the default for everything else
$TimeoutTable = @{ 'tail-close' = 240; 'rowtools' = 480 }

function ConvertTo-WslPath([string]$p) { '/mnt/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/') }

$tests = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem -LiteralPath $auto -File | Where-Object { $_.Name -match '-selftest\.(ps1|sh|py)$' } | Sort-Object Name)) {
    $kind = switch ($f.Extension) { '.ps1' { 'ps' } '.sh' { 'sh' } '.py' { 'py' } }
    [void]$tests.Add([pscustomobject]@{ Name = ($f.Name -replace '-selftest\.(ps1|sh|py)$',''); Path = $f.FullName; Kind = $kind })
}
$rt = Join-Path $ws 'testing\live-stobe-queue\imm26-assert'
# rowtools\trip-selftest.sh is run by rowtools\selftest.sh (its 'trip-family-selftest' line), so it is not listed separately
foreach ($r in @(@('imm26-assert','selftest.sh'), @('rowtools','rowtools\selftest.sh'))) {
    $p = Join-Path $rt $r[1]
    if (Test-Path -LiteralPath $p) { [void]$tests.Add([pscustomobject]@{ Name = $r[0]; Path = $p; Kind = 'sh' }) }
}
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ }); $Include = @($Include | ForEach-Object { $_ -split ',' })   # -File passes 'a,b' as one string
if ($Only.Count) { $tests = @($tests | Where-Object { $n = $_.Name; ($Only | Where-Object { $n -like $_ }).Count -gt 0 }) }

if ($List) { foreach ($t in $tests) { "{0,-34} {1,-3} {2}" -f $t.Name, $t.Kind, $(if ($SkipTable.ContainsKey($t.Name)) { 'SKIP-FLAG slow: ' + $SkipTable[$t.Name] } else { '' }) }; return }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$wslOk = $false
try { $o = (& wsl.exe -d $Distro -- echo ok 2>$null | Out-String) -replace "`0",''; $wslOk = $o -match 'ok' } catch { }

function Stop-Tree([int]$id) { & taskkill.exe /T /F /PID $id 2>&1 | Out-Null }

$script:BaseTimeout = $TimeoutSec
$pass = 0; $fail = 0; $skip = 0
foreach ($t in $tests) {
    $name = $t.Name
    $TimeoutSec = if ($TimeoutTable.ContainsKey($name)) { [math]::Max($TimeoutTable[$name], $script:BaseTimeout) } else { $script:BaseTimeout }
    if ($SkipTable.ContainsKey($name) -and ($Include -notcontains 'slow')) {
        "SELFTEST $name SKIP 0 (slow: $($SkipTable[$name]); -Include slow)"; $skip++; continue
    }
    if ($t.Kind -ne 'ps' -and -not $wslOk) { "SELFTEST $name SKIP 0 (WSL $Distro not available)"; $skip++; continue }
    $so = [IO.Path]::GetTempFileName(); $se = [IO.Path]::GetTempFileName()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        if ($t.Kind -eq 'ps') {
            $argl = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$t.Path)
            $pr = Start-Process -FilePath 'powershell.exe' -ArgumentList $argl -RedirectStandardOutput $so -RedirectStandardError $se -PassThru -WindowStyle Hidden
        } else {
            $wp = ConvertTo-WslPath $t.Path
            $interp = if ($t.Kind -eq 'py') { 'python3' } else { 'bash' }
            # 'timeout' inside WSL kills the Linux side too; the Windows-side kill below is the backstop
            $argl = @('-d',$Distro,'--','timeout','-k','5',"$TimeoutSec",$interp,$wp)
            $pr = Start-Process -FilePath 'wsl.exe' -ArgumentList $argl -RedirectStandardOutput $so -RedirectStandardError $se -PassThru -WindowStyle Hidden
        }
        $null = $pr.Handle   # cache the handle so ExitCode is readable after exit
        $limit = if ($t.Kind -eq 'ps') { $TimeoutSec } else { $TimeoutSec + 15 }
        if (-not $pr.WaitForExit($limit * 1000)) { $timedOut = $true; Stop-Tree $pr.Id }
        else { $pr.WaitForExit() }
        $code = if ($timedOut) { -1 } else { $pr.ExitCode }
    } catch { $code = -2; Add-Content -LiteralPath $se -Value "runner error: $($_.Exception.Message)" }
    $sw.Stop()
    $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $text = ''
    foreach ($f in @($so, $se)) { try { $text += [IO.File]::ReadAllText($f) -replace "`0",'' } catch { } ; Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    if ($t.Kind -ne 'ps' -and $code -eq 124) { $timedOut = $true }
    $badLine = ($text -split "`r?`n" | Where-Object { $_ -match '^\s*SELFTEST(\s+\S+)?\s+FAIL(ED)?\b' } | Select-Object -First 1)
    $okRun = (-not $timedOut) -and ($code -eq 0) -and (-not $badLine)
    if ($okRun) { "SELFTEST $name PASS $secs"; $pass++; Remove-Item -LiteralPath (Join-Path $OutDir (($name -replace '[\/:*?"<>|]','_') + '.txt')) -Force -ErrorAction SilentlyContinue }
    else {
        $why = if ($timedOut) { "timeout ${TimeoutSec}s" } elseif ($code -ne 0) { "exit $code" } else { 'FAIL line in output' }
        $fn = Join-Path $OutDir (($name -replace '[\\/:*?"<>|]','_') + '.txt')
        Set-Content -LiteralPath $fn -Value (@("SELFTEST $name FAIL ($why) $secs s", "path: $($t.Path)", '-----', $text) -join "`r`n") -Encoding UTF8
        "SELFTEST $name FAIL $secs ($why) -> $fn"; $fail++
    }
}
"SELFTEST-ALL $pass pass / $fail fail / $skip skip"
if ($fail -gt 0) { exit 1 }
exit 0
