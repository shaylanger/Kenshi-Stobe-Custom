# save-report-selftest.ps1: selftest of save-report.ps1 (the subagent report saver; the harness blocks Write of REPORT*/SUMMARY*/
# FINDINGS*/ANALYSIS* .md files for subagents). Everything runs against a temp runs dir (env KAH_RUNS_DIR); the real
# C:\KenshiTestRuns is never touched.
# Usage: powershell -NoProfile -File tools\automation\save-report-selftest.ps1      Last line: "SELFTEST save-report: PASS|FAIL (n/m)".
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tool = Join-Path $here 'save-report.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("savereport-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:KAH_RUNS_DIR = $tmp
$script:pass = 0; $script:fail = 0
function Ok([bool]$c, [string]$what) { if ($c) { $script:pass++ } else { $script:fail++; "  FAIL: $what" } }
$blocked = '^(REPORT|SUMMARY|FINDINGS|ANALYSIS).*\.md$'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$dash = [string][char]0x2014

# run the tool as a child powershell with optional raw stdin bytes; returns @{code; out; err}
function Run([string[]]$argv, [byte[]]$stdin = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $q = ($argv | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$tool`" $q"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($stdin) { $p.StandardInput.BaseStream.Write($stdin, 0, $stdin.Length) }
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEnd(); $e = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    @{ code = $p.ExitCode; out = $o.Trim(); err = $e.Trim() }
}
function Saved([string]$out) { if ($out -match 'saved (.+?) \(\d+ lines') { $Matches[1] } else { '' } }

try {
    # 1. file source: CRLF + non-ASCII + BOM in, LF + UTF-8 no BOM out, safe name, latest.md copy
    $src = Join-Path $tmp 'in.txt'
    [IO.File]::WriteAllBytes($src, ([byte[]](0xEF, 0xBB, 0xBF)) + $utf8.GetBytes("# Title $dash x`r`nline two`r`n`r`n"))
    $r = Run @('selftest-agent', $src)
    $dest = Saved $r.out
    Ok ($r.code -eq 0 -and $dest) "file source saved (code $($r.code) out '$($r.out)' err '$($r.err)')"
    if ($dest) {
        $b = [IO.File]::ReadAllBytes($dest)
        Ok (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF)) 'no BOM'
        Ok (-not ($b -contains 13)) 'LF only'
        Ok ($utf8.GetString($b) -eq "# Title $dash x`nline two`n") "content normalised (got '$($utf8.GetString($b) -replace "`n", '\n')')"
        Ok ($dest -like "$tmp\agents\out\selftest-agent\out-*.md") "path under agents\out\<agent> ($dest)"
        Ok ([IO.Path]::GetFileName($dest) -notmatch $blocked) 'name is not a harness-blocked name'
        Ok ([IO.File]::ReadAllText((Join-Path (Split-Path $dest) 'latest.md')) -eq $utf8.GetString($b)) 'latest.md equals the saved file'
    }

    # 2. stdin source with UTF-8 bytes
    $r = Run @('selftest-agent', '-Label', 'diagnosis') $utf8.GetBytes("stdin $dash report`nsecond`n")
    $d2 = Saved $r.out
    Ok ($r.code -eq 0 -and $d2) "stdin source saved (code $($r.code) err '$($r.err)')"
    if ($d2) {
        Ok ([IO.Path]::GetFileName($d2) -like 'out-diagnosis-*.md') "label in name ($([IO.Path]::GetFileName($d2)))"
        Ok ($utf8.GetString([IO.File]::ReadAllBytes($d2)) -eq "stdin $dash report`nsecond`n") 'stdin UTF-8 content intact'
    }

    # 3. agent called report-files (the investigated agent) and a label that looks like a blocked name: still a safe name
    $r = Run @('report-files', '-Label', 'REPORT') $utf8.GetBytes("x`n")
    $d3 = Saved $r.out
    Ok ($d3 -and [IO.Path]::GetFileName($d3) -notmatch $blocked) "agent report-files + label REPORT gives a safe name ($d3)"

    # 4. two saves inside one second never overwrite each other
    $a = Saved (Run @('twice') $utf8.GetBytes("one`n")).out
    $b2 = Saved (Run @('twice') $utf8.GetBytes("two`n")).out
    Ok ($a -and $b2 -and $a -ne $b2) 'two saves in the same second get different files'
    Ok ((Get-Content -LiteralPath (Join-Path (Split-Path $b2) 'latest.md') -Raw) -eq "two`n") 'latest.md is the newest'

    # 5. /mnt/<drive>/ source path
    $wsl = '/mnt/' + $src.Substring(0, 1).ToLower() + '/' + ($src.Substring(3) -replace '\\', '/')
    $r = Run @('selftest-agent', $wsl)
    Ok ($r.code -eq 0 -and (Saved $r.out)) "/mnt path accepted (code $($r.code) err '$($r.err)')"

    # 6. refusals: bad agent names, missing source, empty report
    foreach ($bad in @('..\evil', 'a/b', 'a b', '-x', 'a..b')) {
        $r = Run @($bad) $utf8.GetBytes("x`n")
        Ok ($r.code -ne 0) "agent name '$bad' refused (code $($r.code))"
    }
    Ok (-not (Test-Path -LiteralPath (Join-Path $tmp 'evil'))) 'nothing escaped agents\out'
    $r = Run @('selftest-agent', (Join-Path $tmp 'nope.txt'))
    Ok ($r.code -eq 2 -and $r.err -match 'not found') "missing source refused (code $($r.code) err '$($r.err)')"
    $before = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'agents\out\selftest-agent') -File).Count
    $r = Run @('selftest-agent') ([byte[]]@())
    Ok ($r.code -eq 2) "empty stdin refused (code $($r.code))"
    $r = Run @('selftest-agent') $utf8.GetBytes("   `r`n`r`n")
    Ok ($r.code -eq 2) "whitespace-only stdin refused (code $($r.code))"
    $after = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'agents\out\selftest-agent') -File).Count
    Ok ($before -eq $after) 'refused saves wrote nothing'

    # 7. real usage from Git Bash (heredoc piped into powershell.exe), the way agents call it
    $bashExe = @('C:\Program Files\Git\usr\bin\bash.exe', 'C:\Program Files\Git\bin\bash.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($bashExe) {
        $toolFwd = $tool -replace '\\', '/'
        $env:KAH_RUNS_DIR = $tmp
        $o = & $bashExe -c "printf 'from bash \342\200\224 ok\n' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$toolFwd' bash-agent" 2>&1
        $d7 = Saved (($o | Out-String).Trim())
        Ok ($d7 -and (Test-Path -LiteralPath $d7)) "git-bash pipe saved ($o)"
        if ($d7 -and (Test-Path -LiteralPath $d7)) { Ok ($utf8.GetString([IO.File]::ReadAllBytes($d7)) -eq "from bash $dash ok`n") 'git-bash pipe keeps UTF-8 bytes' }
    } else { 'note: git bash not found, bash pipe test skipped' }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
$tot = $script:pass + $script:fail
"SELFTEST save-report: $(if ($script:fail -eq 0) { 'PASS' } else { 'FAIL' }) ($($script:pass)/$tot)"
if ($script:fail -ne 0) { exit 1 }
