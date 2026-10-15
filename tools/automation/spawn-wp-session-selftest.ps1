# spawn-wp-session-selftest.ps1 [-Real]
# Offline selftest of spawn-wp-session.ps1 (-DryRun: never starts claude) and agent-session-live.ps1, in a temp runs dir
# (KAH_RUNS_DIR + KPL_DIR), never the real agents\ / programs\ dirs. No game, no server, no LLM.
#   -Real   additionally launches ONE real trivial claude session (sonnet, costs a few cents), checks that it survives the exit of the
#           shell that launched it, heartbeats, shows up in `claude agents --json`, and stops it. Result lines: REAL ...
# Prints PASS/FAIL lines and "SELFTEST PASS n/n"; exit 1 on any failure.
param([switch]$Real)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$spawn = Join-Path $here 'spawn-wp-session.ps1'
$live = Join-Path $here 'agent-session-live.ps1'
$ledger = Join-Path $here 'program-ledger.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("spawn-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saveRuns = $env:KAH_RUNS_DIR; $saveKpl = $env:KPL_DIR
$env:KAH_RUNS_DIR = $tmp; $env:KPL_DIR = Join-Path $tmp 'programs'
New-Item -ItemType Directory -Force -Path $tmp, $env:KPL_DIR, (Join-Path $tmp 'agents') | Out-Null
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function SpawnIt { param([string[]]$a) $ErrorActionPreference = 'Continue'; (& powershell -NoProfile -ExecutionPolicy Bypass -File $spawn @a 2>&1 | Out-String).Trim() }
function LiveOf([string]$n) { $o = (& powershell -NoProfile -ExecutionPolicy Bypass -File $live $n | Out-String).Trim(); return @{ text = $o; code = $LASTEXITCODE } }
function SJ([string]$n) { Get-Content -LiteralPath (Join-Path $tmp "agents\$n.session.json") -Raw | ConvertFrom-Json }
function Set-Status([string]$n, [string]$state, [int]$ageMin = 0) {
    $f = Join-Path $tmp "agents\$n.status"
    Set-Content -LiteralPath $f -Value @("$n | $state | $(Get-Date -Format 'yyyy-MM-dd HH:mm')", 'task: t') -Encoding UTF8
    (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
$sleepers = @()
try {
    $pf = Join-Path $tmp 'brief.md'
    Set-Content -LiteralPath $pf -Value @('wpZ - make the thing', 'GOAL: do it.') -Encoding UTF8

    # ---- spawn -DryRun ----
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger init progT testing/PROGT.md | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledger add-wp progT wpZ items=1 | Out-Null
    $o = SpawnIt @('wpZ-agent', 'generate', $pf, '-Program', 'progT', '-Wp', 'wpZ', '-DryRun')
    T ($o -like 'DRYRUN wpZ-agent model=sonnet effort=high*') "1a dry run prints DRYRUN with policy model/effort: $o"
    $s = SJ 'wpZ-agent'
    T ($s.name -eq 'wpZ-agent' -and $s.model -eq 'sonnet' -and $s.effort -eq 'high' -and $s.tier -eq 'kenshi-generator' -and $s.title -eq 'wpZ-agent' -and $s.workdir -eq 'C:\KenshiModding' -and $s.claude_session_id -match '^[0-9a-f-]{36}$' -and $s.dry_run -eq $true) '1b session.json fields (name, model, effort, tier, title, workdir, session id, dry_run)'
    T (-not (Test-Path (Join-Path $tmp 'agents\wpZ-agent.status')) -and -not (Test-Path (Join-Path $tmp 'inflight\wpZ-agent'))) '1c dry run writes no status file and no inflight marker'
    $pm = Get-Content -Raw (Join-Path $tmp 'agents\wpZ-agent.prompt.md')
    T ($pm -like 'wpZ - make the thing*' -and $pm -match 'Independent session rules' -and $pm -match 'agent-status\.ps1 wpZ-agent RUNNING' -and $pm -match 'inbox\\coordinator' -and $pm -match 'wpZ-agent\.handoff\.md' -and $pm -match 'wpZ-agent2' -and $pm -match 'work package wpZ') '1d prompt copy = brief + standard block (status, handoff, coordinator inbox, successor name, program/wp)'
    $lt = Get-Content -Raw (Join-Path $tmp 'agents\wpZ-agent.launch.ps1')
    $perr = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($lt, [ref]$null, [ref]$perr)
    T (-not $perr.Count -and $lt -match "KAH_AGENT_NAME = 'wpZ-agent'" -and $lt -match "WindowTitle = 'wpZ-agent'" -and $lt -match "--model', 'sonnet', '--effort', 'high'" -and $lt -match "--permission-mode', 'auto'" -and $lt -match "--add-dir', 'C:\\KenshiModding', '" -and $lt -match "-n', 'wpZ-agent'") '1e launcher parses; env KAH_AGENT_NAME, window title, --model/--effort/--permission-mode/-n/--add-dir'
    T ($lt -match "^& claude 'You are the independent agent wpZ-agent" -or $lt -match "(?m)^& claude 'You are the independent agent wpZ-agent") '1f prompt is the first claude argument (--add-dir is variadic and must come last)'
    $lj = Get-Content -Raw (Join-Path $env:KPL_DIR 'progT.json') | ConvertFrom-Json
    $w = @($lj.wps)[0]
    T ($w.agent -eq 'wpZ-agent' -and @($w.sessions).Count -eq 1 -and @($w.sessions)[0] -like 'wpZ-agent|0||*') '1g ledger: sessions entry + wp agent set'
    $o = SpawnIt @('x1', 'debug', $pf, '-DryRun'); $d = SJ 'x1'
    T ($d.model -eq 'sonnet' -and $d.effort -eq 'xhigh') '2a case debug -> sonnet xhigh'
    $o = SpawnIt @('x2', 'escalate', $pf, '-DryRun'); $d = SJ 'x2'
    T ($d.model -eq 'opus' -and $d.effort -eq 'medium') '2b case escalate -> opus medium'
    $o = SpawnIt @('x3', 'kenshi-debugger', $pf, '-DryRun', '-PermissionMode', 'default'); $d = SJ 'x3'
    T ($d.tier -eq 'kenshi-debugger' -and $d.effort -eq 'xhigh' -and ((Get-Content -Raw (Join-Path $tmp 'agents\x3.launch.ps1')) -notmatch '--permission-mode')) '2c tier name accepted; -PermissionMode default passes no flag'
    T ((SpawnIt @('x4', 'nonsense', $pf, '-DryRun')) -match 'unknown case/tier') '3a unknown case rejected'
    T ((SpawnIt @('bad name', 'generate', $pf, '-DryRun')) -match 'bad agent name') '3b bad name rejected'
    T ((SpawnIt @('x5', 'generate', (Join-Path $tmp 'nope.md'), '-DryRun')) -match 'prompt file not found') '3c missing prompt file rejected'
    T ((SpawnIt @('x6', 'generate', $pf, '-Program', 'progT', '-DryRun')) -match 'go together') '3d -Program without -Wp rejected'

    # ---- agent-session-live ----
    $r = LiveOf 'ghost'
    T ($r.code -eq 2 -and $r.text -like 'DEAD no session record*') '4a no session record -> DEAD (exit 2)'
    $sl = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120'
    $sleepers += $sl
    Start-Sleep -Milliseconds 600
    $st = $sl.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
    $mk = {
        param($n, $procId, $start)
        $o = [ordered]@{ name = $n; claude_pid = $procId; claude_start = $start; launcher_pid = 0 }
        [IO.File]::WriteAllText((Join-Path $tmp "agents\$n.session.json"), ($o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
    & $mk 'lv1' $sl.Id $st; Set-Status 'lv1' 'RUNNING' 1
    $r = LiveOf 'lv1'; T ($r.code -eq 0 -and $r.text -like 'LIVE claude pid*') "4b pid alive + fresh RUNNING heartbeat -> LIVE ($($r.text))"
    Set-Status 'lv1' 'RUNNING' 20
    $r = LiveOf 'lv1'; T ($r.code -eq 1 -and $r.text -like 'DEAD heartbeat stale*') "4c alive but heartbeat 20 min old -> DEAD ($($r.text))"
    Set-Status 'lv1' 'DONE' 0
    $r = LiveOf 'lv1'; T ($r.code -eq 1 -and $r.text -like 'DEAD status is DONE*') '4d alive but status DONE -> DEAD'
    Set-Status 'lv1' 'RUNNING' 0
    & $mk 'lv2' $sl.Id '2001-01-01T00:00:00.000+00:00'; Set-Status 'lv2' 'RUNNING' 0
    $r = LiveOf 'lv2'; T ($r.code -eq 1 -and $r.text -like 'DEAD process gone*') '4e pid alive but start time differs (recycled pid) -> DEAD'
    Stop-Process -Id $sl.Id -Force; Start-Sleep -Milliseconds 500
    $r = LiveOf 'lv1'; T ($r.code -eq 1 -and $r.text -like 'DEAD process gone*') '4f process killed -> DEAD'
    # a live session blocks a double spawn (real, non-dry-run refusal happens before any launch)
    $sl2 = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120'; $sleepers += $sl2
    Start-Sleep -Milliseconds 600
    & $mk 'dup' $sl2.Id ($sl2.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')); Set-Status 'dup' 'RUNNING' 0
    $o = SpawnIt @('dup', 'generate', $pf)
    T ($o -match 'already LIVE') '5 spawning over a LIVE session of the same name is refused'

    if ($Real) {
        $rp = Join-Path $tmp 'real-brief.md'
        Set-Content -LiteralPath $rp -Value @('REAL TRIVIAL TEST CHILD: run agent-status.ps1 selftest-real DONE "real child" "ok" "" "" with exactly that name, then end your turn. Do nothing else; ignore rule 5 and the rest of the appended block.') -Encoding UTF8
        # Real run uses the real runs dir so the child (which does not see KAH_RUNS_DIR) writes where we look.
        $env:KAH_RUNS_DIR = $saveRuns
        $realRuns = if ($saveRuns) { $saveRuns } else { 'C:\KenshiTestRuns' }
        $env:KAH_RUNS_DIR = $realRuns
        $hp = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "& '$spawn' selftest-real generate '$rp' *> '$tmp\real-spawn.txt'"
        $hp.WaitForExit()
        $line = Get-Content -Raw "$tmp\real-spawn.txt"
        "REAL spawn: $($line.Trim())"
        $rs = Get-Content -Raw (Join-Path $realRuns 'agents\selftest-real.session.json') | ConvertFrom-Json
        $survived = [bool](Get-Process -Id $rs.claude_pid -ErrorAction SilentlyContinue)
        T ($survived) "REAL child survives the exit of the shell that launched it (claude pid $($rs.claude_pid))"
        $listed = 0
        for ($i = 0; $i -lt 10 -and -not $listed; $i++) {
            $agents = (& claude agents --json | Out-String) | ConvertFrom-Json
            $listed = @($agents | Where-Object { $_.sessionId -eq $rs.claude_session_id }).Count
            if (-not $listed) { Start-Sleep -Seconds 3 }
        }
        T ($listed -eq 1) 'REAL child is listed by `claude agents --json` (another session can find it)'
        $dl = (Get-Date).AddSeconds(120); $done = $false
        while ((Get-Date) -lt $dl -and -not $done) { Start-Sleep -Seconds 3; $done = ((Get-Content (Join-Path $realRuns 'agents\selftest-real.status') -TotalCount 1) -match '\| DONE \|') }
        T ($done) 'REAL child ran agent-status.ps1 DONE unattended (permission mode auto)'
        Stop-Process -Id $rs.launcher_pid -Force -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($rs.launcher_pid)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $rs.claude_pid -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $realRuns 'agents\selftest-real.*'), (Join-Path $realRuns 'inflight\selftest-real'), (Join-Path $realRuns 'inbox\selftest-real') -Recurse -Force -ErrorAction SilentlyContinue
        $env:KAH_RUNS_DIR = $tmp
    }
    T (-not (Test-Path 'C:\KenshiTestRuns\agents\wpZ-agent.session.json') -or $Real) '6 the selftest wrote nothing into the real agents dir'
} finally {
    foreach ($p in $sleepers) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    $env:KAH_RUNS_DIR = $saveRuns; $env:KPL_DIR = $saveKpl
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
