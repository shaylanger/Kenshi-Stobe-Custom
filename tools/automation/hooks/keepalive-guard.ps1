# keepalive-guard (PowerShell): PreToolUse hook, matcher Bash|PowerShell (credit review cut #4, Shay approved 2026-10-16).
# Why: the prompt cache lives 5 min. A subagent (or lane operator / tail / any non-coordinator session) whose SINGLE Bash/PowerShell call
# blocks > 5 min lets the cache expire; its next turn re-writes the whole context at ~10x the read price (155 wakes = $36.50/day, ~$35
# avoidable). If no single call blocks longer than ~4 min the agent re-turns in time and the cache stays warm (simulation: net ~$33/day).
#
# WHAT IT DENIES (exit 2 + a message that says how to do it instead) for a NON-coordinator caller, when the call is NOT run_in_background:
#   1. a single `sleep N` / `Start-Sleep N` (-Seconds/-s/-Milliseconds/-m) / `timeout N` / `timeout /t N` / `ping -n N` / python `time.sleep(N)` /
#      `wait-row.sh <file> N` / `event-wait.sh --backstop N` / `Wait-Process|Wait-Job|Wait-Event -Timeout N` with N > 240 s (units s/m/h/d understood);
#   2. a Bash/PowerShell `timeout` argument > 240000 ms (the call may then block that long) unless the command is provably short (no sleep/loop/wait/
#      timeout/bash/sh/python/wsl/ssh/.sh/.py/build/install/batch/... token; agent-status.ps1 / save-report.ps1 are ignored), e.g. `git commit ... && git push`
#      with timeout 600000 is allowed (logged as ALLOW-SHORT). With no timeout argument the harness default (BASH_DEFAULT_TIMEOUT_MS, else 120000) is used.
#   Loops (`for/while/until ... do ... done`, `do { } while`, `while (...) { }`) are estimated (iterations x sleeps, or AddSeconds/SECONDS/date+%s deadline,
#   `while true` = unbounded) and the estimate is named in the message; they only matter when the tool timeout is > 240 s (a call with timeout <= 240000
#   is killed by the tool at that limit, so it cannot hold the turn longer; no loop/sleep inside it is denied by rule 2).
#   wsl.exe / ssh / bash -c wrappers need no special handling: the inner text is part of the command string and the same regexes see it.
# WHAT IT ALLOWS: run_in_background:true, other tools (Monitor, Read, ...), the live coordinator (its own rules in kenshi-waker-guard.ps1 are unchanged),
#   calls with an effective timeout <= 240 s and no explicit rule-1 wait, and everything while C:\KenshiTestRuns\keepalive.off exists (or KAH_KEEPALIVE_OFF=1).
# WHO IS THE COORDINATOR: hook input has `agent_id` for subagents (-> subject to the guard). Without agent_id the session is the coordinator iff
#   session_id == C:\KenshiTestRuns\coordinator.current .session (written at claim, `updated` refreshed by every coordinator tool call). Missing/stale (> 15 min)
#   coordinator.current or missing session_id = cannot tell = FAIL OPEN (allow). Any error in this script = allow.
# KNOWN FALSE POSITIVES (measure them in the log): text that merely mentions `sleep 300` / `timeout 400` inside quotes of a command that is not executed it
#   (echo/grep/git commit -m ... with the words); a loop that would `break` after seconds but whose static upper bound > 240 with a big tool timeout; a big timeout
#   argument on a command containing a long-ish token that actually finishes fast. Heredoc bodies fed to cat/python/etc. are stripped (kept for bash/sh/wsl/powershell).
#   False negatives: unbounded foreground commands under a tool timeout <= 240000 are cut by the tool anyway (cache-safe); `Start-Process -Wait`, long single
#   programs (a build with no sleep) under timeout <= 240000 are cut by the tool at that limit.
# MEASURED on the last 30 h of subagent transcripts (1510 foreground Bash/PowerShell calls with timeout > 240000): 303 really ran > 240 s (233 > 300 s = cache expired) and are
#   all denied; 1204 finished in <= 240 s (484 in <= 30 s: agents put timeout 600000 on everything) and are also denied = one extra cheap turn each (about $0.01),
#   zero false negatives for that class. Calls with timeout <= 240000 are never denied by rule 2 (6 of 22679 ran > 240 s).
# Log: C:\KenshiTestRuns\keepalive-denies.log (tab separated: time, DENY|ALLOW-SHORT, who, tool, rules, effective timeout s, command).
# Selftest: tools\automation\hooks\keepalive-guard-selftest.ps1 (fixtures keepalive-guard-fixtures.json from real transcripts).
$raw = [Console]::In.ReadToEnd()
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
try {
    $runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
    $LIMIT = 240
    if ($env:KAH_KEEPALIVE_OFF -eq '1' -or (Test-Path -LiteralPath (Join-Path $runs 'keepalive.off'))) { exit 0 }
    $tool = [string]$in.tool_name
    if ($tool -ne 'Bash' -and $tool -ne 'PowerShell') { exit 0 }
    $ti = $in.tool_input
    if ($null -eq $ti) { exit 0 }
    if ([string]$ti.run_in_background -match '^(?i:true)$') { exit 0 }
    $cmd = [string]$ti.command
    if (-not $cmd) { exit 0 }

    function Strip-Heredocs([string]$s) {
        # remove heredoc bodies unless the line that opens them runs a shell (bash/sh/wsl/powershell/pwsh executes the body)
        $lines = $s -split "\r?\n"
        $o = New-Object System.Collections.Generic.List[string]
        $delim = $null; $keep = $false
        foreach ($ln in $lines) {
            if ($null -ne $delim) {
                if ($ln.Trim() -eq $delim) { $delim = $null; $o.Add($ln) } elseif ($keep) { $o.Add($ln) }
                continue
            }
            $o.Add($ln)
            $m = [regex]::Match($ln, '<<-?\s*[''"]?([A-Za-z_][A-Za-z0-9_]*)[''"]?')
            if ($m.Success) {
                $delim = $m.Groups[1].Value
                $keep = $ln -match '(?i)(?<![\w.-])(bash|sh|zsh|wsl(\.exe)?|powershell(\.exe)?|pwsh)(?![\w-])'
            }
        }
        return ($o -join "`n")
    }

    function To-Sec([string]$n, [string]$u) {
        $v = [double]::Parse($n, [Globalization.CultureInfo]::InvariantCulture)
        switch ($u.ToLower()) { 'm' { return $v * 60 } 'h' { return $v * 3600 } 'd' { return $v * 86400 } default { return $v } }
    }

    function Get-Sleeps([string]$c) {
        # returns a list of seconds, one per sleep invocation
        $res = @()
        foreach ($m in [regex]::Matches($c, '(?i)(?<![\w./\\$-])(sleep|start-sleep)(?![\w-])([^;&|\r\n)}]*)')) {
            $kind = $m.Groups[1].Value.ToLower(); $a = $m.Groups[2].Value.Trim()
            if (-not $a) { continue }
            if ($kind -eq 'start-sleep') {
                $mm = [regex]::Match($a, '(?i)-m(?:illiseconds)?\s+(\d+(?:\.\d+)?)')
                if ($mm.Success) { $res += [double]$mm.Groups[1].Value / 1000.0; continue }
                $mm = [regex]::Match($a, '(?i)^(?:-s(?:econds)?\s+)?(\d+(?:\.\d+)?)')
                if ($mm.Success) { $res += [double]$mm.Groups[1].Value }
            } else {
                $sum = 0.0; $first = $true; $ok = $false
                foreach ($tk in ($a -split '\s+')) {
                    $t = [regex]::Match($tk, '^(\d+(?:\.\d+)?)([smhd]?)$')
                    if ($t.Success) { $sum += To-Sec $t.Groups[1].Value $t.Groups[2].Value; $ok = $true } elseif ($first) { break } else { break }
                    $first = $false
                }
                if ($ok) { $res += $sum }
            }
        }
        return ,$res
    }

    function Get-Violations([string]$c) {
        $v = New-Object System.Collections.Generic.List[string]
        foreach ($s in (Get-Sleeps $c)) { if ($s -gt $LIMIT) { $v.Add(("sleep {0:0} s" -f $s)) } }
        foreach ($m in [regex]::Matches($c, '(?i)(?<![\w./\\$-])timeout\s+((?:-[-\w=]+\s+)*)(\d+(?:\.\d+)?)([smhd]?)(?![\w.])')) {
            $s = To-Sec $m.Groups[2].Value $m.Groups[3].Value
            if ($s -gt $LIMIT) { $v.Add(("timeout {0:0} s" -f $s)) }
        }
        foreach ($m in [regex]::Matches($c, '(?i)(?<![\w./\\-])timeout(?:\.exe)?\s+/t\s+(\d+)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("timeout /t " + $m.Groups[1].Value) } }
        foreach ($m in [regex]::Matches($c, '(?i)time\.sleep\(\s*(\d+(?:\.\d+)?)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("python time.sleep " + $m.Groups[1].Value) } }
        foreach ($m in [regex]::Matches($c, '(?i)\bping(?:\.exe)?\s+(?:-\w+\s+)*-n\s+(\d+)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("ping -n " + $m.Groups[1].Value) } }
        foreach ($m in [regex]::Matches($c, '(?i)wait-row\.sh\s+\S+\s+(\d+)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("wait-row.sh " + $m.Groups[1].Value + " s") } }
        foreach ($m in [regex]::Matches($c, '(?i)event-wait\.sh[^\r\n;|&]*?--backstop[ =](\d+)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("event-wait --backstop " + $m.Groups[1].Value) } }
        foreach ($m in [regex]::Matches($c, '(?i)wait-(?:process|job|event)\b[^\r\n;|]*?-timeout\s+(\d+)')) { if ([double]$m.Groups[1].Value -gt $LIMIT) { $v.Add("Wait-* -Timeout " + $m.Groups[1].Value) } }
        return $v.ToArray()
    }

    function Get-LoopEstimate([string]$c) {
        $bash = $c -match '(?s)(?<![\w-])(for|while|until)(?![\w-]).*?(?<![\w-])do(?![\w-]).*?(?<![\w-])done(?![\w-])'
        $ps = ($c -match '(?i)(?<![\w-])do\s*\{') -or ($c -match '(?i)(?<![\w-])(while|for|foreach)\s*\(')
        if (-not ($bash -or $ps)) { return $null }
        $per = 0.0
        foreach ($s in (Get-Sleeps $c)) { $per += $s }
        foreach ($m in [regex]::Matches($c, '(?i)wait-row\.sh\s+\S+\s+(\d+)')) { $per += [double]$m.Groups[1].Value }
        if ($per -le 0) { return $null }
        $m = [regex]::Match($c, '(?i)AddSeconds\(\s*(\d+)')
        if ($m.Success) { return @{ Est = [double]$m.Groups[1].Value; Why = "deadline AddSeconds($($m.Groups[1].Value))" } }
        $m = [regex]::Match($c, '(?i)AddMinutes\(\s*(\d+)')
        if ($m.Success) { return @{ Est = 60.0 * [double]$m.Groups[1].Value; Why = "deadline AddMinutes($($m.Groups[1].Value))" } }
        $m = [regex]::Match($c, '(?i)SECONDS\s*-lt\s*(\d+)')
        if ($m.Success) { return @{ Est = [double]$m.Groups[1].Value; Why = "SECONDS -lt $($m.Groups[1].Value)" } }
        $m = [regex]::Match($c, 'date\s+\+%s\)?\s*\+\s*(\d+)')
        if ($m.Success) { return @{ Est = [double]$m.Groups[1].Value; Why = "date +%s + $($m.Groups[1].Value)" } }
        $it = $null; $why = ''
        $m = [regex]::Match($c, 'seq\s+(\d+)\s+(\d+)')
        if ($m.Success) { $it = [double]$m.Groups[2].Value - [double]$m.Groups[1].Value + 1; $why = "seq $($m.Groups[1].Value) $($m.Groups[2].Value)" }
        if ($null -eq $it) { $m = [regex]::Match($c, 'seq\s+(\d+)(?![\d\s]*\d)'); if ($m.Success) { $it = [double]$m.Groups[1].Value; $why = "seq $($m.Groups[1].Value)" } }
        if ($null -eq $it) { $m = [regex]::Match($c, '\{(\d+)\.\.(\d+)\}'); if ($m.Success) { $it = [double]$m.Groups[2].Value - [double]$m.Groups[1].Value + 1; $why = $m.Value } }
        if ($null -eq $it) { $m = [regex]::Match($c, '(?<![\w.])(\d+)\.\.(\d+)'); if ($m.Success) { $it = [double]$m.Groups[2].Value - [double]$m.Groups[1].Value + 1; $why = $m.Value } }
        if ($null -eq $it) { $m = [regex]::Match($c, '(?<![\w-])for\s+\w+\s+in\s+((?:\d+\s+)+)do'); if ($m.Success) { $it = ($m.Groups[1].Value.Trim() -split '\s+').Count; $why = "for in <$it items>" } }
        if ($null -eq $it) { $m = [regex]::Match($c, '(?i)\$\w+\s+-(?:lt|le)\s+(\d+)'); if ($m.Success) { $it = [double]$m.Groups[1].Value; $why = "counter -lt $($m.Groups[1].Value)" } }
        if ($null -ne $it) { return @{ Est = $it * $per; Why = ("{0} x {1:0.#} s per iteration (upper bound, break exits earlier)" -f $why, $per) } }
        return @{ Est = [double]::PositiveInfinity; Why = 'unbounded while/until/do-while loop with sleep (a break may end it earlier)' }
    }

    function Test-ProvablyShort([string]$c) {
        $x = [regex]::Replace($c, '(?i)(?:powershell(?:\.exe)?|pwsh)\s+(?:-\w+\s+(?:Bypass\s+)?)*-File\s+\S*(?:agent-status|save-report|session-start)\.ps1', ' ')
        $x = [regex]::Replace($x, '(?i)\S*(?:agent-status|save-report|session-start)\.ps1', ' ')
        $long = '(?i)(?<![\w-])(sleep|start-sleep|while|until|for|foreach|wait\w*|timeout|wsl(\.exe)?|bash|sh|zsh|python3?|py|ssh|scp|node|dotnet|msbuild|cmake|make|curl|wget|stobe-auto|kenshi-ctl|run-batch|event-wait|selftest|batch|build\w*|install\w*|npm|pip|cargo|robocopy|tar|zip|7z|ffmpeg|cmd(\.exe)?|powershell(\.exe)?|pwsh)(?![\w-])|\.(sh|py|bat|cmd|exe)(?![\w])|-File(?![\w])|-Command(?![\w])|Invoke-\w+|\.ps1(?![\w])'
        if (-not [regex]::IsMatch($x, $long)) { return $true }
        # positive test: every statement starts with a command that cannot wait (git/cd/cat/grep/tail/...), quoted strings blanked first
        $q = [regex]::Replace($c, '"(?:[^"\\]|\\.)*"|''[^'']*''', 'Q')
        $q = [regex]::Replace($q, '\d*>&\d|&>>?', ' ')
        $safe = '^(?i:cd|git|cat|ls|grep|egrep|rg|head|tail|wc|echo|printf|sed|awk|cut|sort|uniq|diff|test|\[|\[\[|mkdir|cp|mv|rm|touch|date|true|false|export|pwd|stat|find|tr|tee|basename|dirname|realpath|type|where|findstr|more|Get-Content|Get-ChildItem|Select-String|Test-Path|Set-Location|Write-Output|Write-Host|Copy-Item|Move-Item|Remove-Item|New-Item)$'
        $coordTools = [regex]::IsMatch($c, '(?i)(agent-status|save-report|session-start|alert-ack|tail-ack)\.ps1')
        foreach ($st in [regex]::Split($q, '&&|\|\||;|\||\r?\n|&')) {
            $t = $st.Trim(); if (-not $t) { continue }
            $t = [regex]::Replace($t, '^(?:\w+=\S*\s+)+', '')
            $t = $t -replace '^[({]\s*', ''
            $w = ($t -split '\s+')[0]
            if ($w -match '^(?i:powershell(\.exe)?|pwsh)$' -and $coordTools) { continue }
            if ($w -notmatch $safe) { return $false }
        }
        return $true
    }

    $c = Strip-Heredocs $cmd
    $viol = @(Get-Violations $c)
    $defMs = 120000
    if ($env:BASH_DEFAULT_TIMEOUT_MS -match '^\d+$') { $defMs = [double]$env:BASH_DEFAULT_TIMEOUT_MS }
    $effMs = if ($ti.timeout) { [double]$ti.timeout } else { $defMs }
    $effS = $effMs / 1000.0
    $allowShort = $false
    $loop = $null
    if ($effS -gt $LIMIT) {
        if (Test-ProvablyShort $c) { $allowShort = $true }
        else { $viol += ("tool timeout {0:0} s (> {1} s) on a command that can wait" -f $effS, $LIMIT) }
        $loop = Get-LoopEstimate $c
    }
    if ($viol.Count -eq 0 -and -not $allowShort) { exit 0 }

    # who is calling?
    $sid = [string]$in.session_id
    $aid = [string]$in.agent_id
    $isAgent = [bool]($aid -or $env:KAH_AGENT_NAME)
    if (-not $isAgent) {
        $cur = $null; $upd = $null
        try {
            $cj = Get-Content -LiteralPath (Join-Path $runs 'coordinator.current') -Raw -ErrorAction Stop | ConvertFrom-Json
            $cur = [string]$cj.session; $upd = [datetime]$cj.updated
        } catch { exit 0 }
        if (-not $cur -or -not $sid) { exit 0 }                      # cannot tell: fail open
        if ($upd -lt (Get-Date).AddMinutes(-15)) { exit 0 }          # stale pointer: cannot tell: fail open
        if ($sid -eq $cur) { exit 0 }                                # the live coordinator
    }
    $who = if ($aid) { "agent:$aid" } elseif ($env:KAH_AGENT_NAME) { "agent:$($env:KAH_AGENT_NAME)" } else { "session:" + $sid.Substring(0, [Math]::Min(8, $sid.Length)) }

    $logf = Join-Path $runs 'keepalive-denies.log'
    function Write-KaLog([string]$kind, [string]$rules) {
        try {
            if ((Test-Path -LiteralPath $logf) -and (Get-Item -LiteralPath $logf).Length -gt 1MB) { Move-Item -LiteralPath $logf -Destination ($logf + '.1') -Force }
            $one = ($cmd -replace '\s+', ' '); if ($one.Length -gt 240) { $one = $one.Substring(0, 240) }
            $line = ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $kind, $who, $tool, $rules, ('{0:0}' -f $effS), $one) -join "`t"
            Add-Content -LiteralPath $logf -Value $line -Encoding UTF8
        } catch { }
    }
    if ($viol.Count -eq 0) { Write-KaLog 'ALLOW-SHORT' 'big timeout, provably short'; exit 0 }

    $loopTxt = ''
    if ($loop) { $loopTxt = if ([double]::IsInfinity($loop.Est)) { " Loop estimate: $($loop.Why)." } else { (" Loop estimate: about {0:0} s ({1})." -f $loop.Est, $loop.Why) } }
    $msg = "keepalive-guard: DENIED. This $tool call can block your turn longer than $LIMIT s ($($viol -join '; ')).$loopTxt " +
        "Why: the prompt cache lasts 5 min; one call that blocks longer lets it expire and the next turn re-writes your whole context at ~10x the read price. " +
        "Do this instead: (1) start the long job DETACHED: the Bash/PowerShell call with run_in_background:true (output goes to a file/notification), or " +
        "'(nohup bash <script> > <out> 2>&1 &)' / run-batch.sh for batches and game rows; (2) POLL with short calls of at most $LIMIT s, one cheap turn each: " +
        "`"bash tools/automation/wait-row.sh <out> 200`" or `"timeout 200 bash -c 'until grep -q <DONE-pattern> <out>; do sleep 3; done'; tail -3 <out>`" (a bare 'sleep N; ...' is also denied by the harness / kenshi-waker-guard for N > 120), with the tool timeout argument at most 240000; " +
        "(3) repeat until the result line (RESULT/DONE/verdict) appears. A foreground command that really is short: lower the timeout argument to at most 240000 (or drop it). " +
        "Never put a wait longer than $LIMIT s in one call. Log of denies: $logf. Coordinator escape for a false positive: create $(Join-Path $runs 'keepalive.off')."
    Write-KaLog 'DENY' ($viol -join '; ')
    [Console]::Error.WriteLine($msg)
    exit 2
} catch { exit 0 }
