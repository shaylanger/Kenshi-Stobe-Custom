# keepalive-guard-selftest: runs keepalive-guard.ps1 (as the harness does: hook JSON on stdin, exit 2 = deny) against
#  (a) real command strings taken from today's subagent transcripts (keepalive-guard-fixtures.json: name, tool, timeout, bg, who, command, expect, rule)
#  (b) synthetic cases below (coordinator, flag file, background, PowerShell, wsl wrappers, loops, fail-open).
# Uses a temp runs dir (KAH_RUNS_DIR) with a fake coordinator.current; never touches C:\KenshiTestRuns. Prints one line per failed case and a final
# "SELFTEST keepalive-guard: N passed, M failed" line; exit 0 only when M = 0.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$hook = Join-Path $here 'keepalive-guard.ps1'
$tmp = Join-Path $env:TEMP ('kag-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$coord = 'cccccccc-0000-0000-0000-000000000001'
function Set-Coord([string]$sid, [datetime]$upd) {
    @{ session = $sid; pid = 1; name = 'coordinator'; started = (Get-Date).ToString('o'); updated = $upd.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tmp 'coordinator.current') -Encoding UTF8
}
Set-Coord $coord (Get-Date)
$env:KAH_RUNS_DIR = $tmp
$env:KAH_KEEPALIVE_OFF = ''
Remove-Item Env:\KAH_AGENT_NAME -ErrorAction SilentlyContinue

$script:pass = 0; $script:fail = 0
function Invoke-Hook($obj) {
    $j = $obj | ConvertTo-Json -Depth 6 -Compress
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $hook + '"'
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($j); $p.StandardInput.Close()
    $err = $p.StandardError.ReadToEnd(); [void]$p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    return @{ Code = $p.ExitCode; Err = $err }
}
function Check([string]$name, $in, [string]$expect, [string]$mustSay = '') {
    $r = Invoke-Hook $in
    $got = if ($r.Code -eq 2) { 'deny' } elseif ($r.Code -eq 0) { 'allow' } else { 'exit' + $r.Code }
    $ok = ($got -eq $expect)
    if ($ok -and $mustSay -and $r.Err -notmatch [regex]::Escape($mustSay)) { $ok = $false; $got += " (message lacks '$mustSay')" }
    if ($ok -and $expect -eq 'deny' -and $r.Err -notmatch 'run_in_background') { $ok = $false; $got += ' (message lacks how-to)' }
    if ($ok) { $script:pass++ } else { $script:fail++; Write-Output ("FAIL {0}: expected {1}, got {2}" -f $name, $expect, $got) }
}
function Mk([string]$tool, [string]$cmd, $timeout, [bool]$bg, [string]$who = 'agent') {
    $ti = @{ command = $cmd }
    if ($timeout) { $ti.timeout = [int]$timeout }
    if ($bg) { $ti.run_in_background = $true }
    $o = @{ tool_name = $tool; tool_input = $ti }
    if ($who -eq 'agent') { $o.session_id = 'sub-session'; $o.agent_id = 'a1b2c3' }
    elseif ($who -eq 'coordinator') { $o.session_id = $coord }
    elseif ($who -eq 'other') { $o.session_id = 'dddddddd-1111-2222-3333-444444444444' }
    elseif ($who -eq 'nosid') { }
    return $o
}

# (a) real strings from transcripts
$fx = Join-Path $here 'keepalive-guard-fixtures.json'
if (Test-Path -LiteralPath $fx) {
    foreach ($f in (Get-Content -LiteralPath $fx -Raw -Encoding UTF8 | ConvertFrom-Json)) {
        Check ("real/" + $f.name) (Mk $f.tool $f.command $f.timeout ([bool]$f.bg) 'agent') $f.expect
    }
} else { Write-Output "FAIL fixtures file missing: $fx"; $script:fail++ }

# (b) synthetic
Check 'sleep 300 default timeout' (Mk 'Bash' 'sleep 300; tail -3 /tmp/x' $null $false) 'deny' 'sleep 300'
Check 'sleep 5m' (Mk 'Bash' 'sleep 5m; ls' $null $false) 'deny'
Check 'sleep 240 ok' (Mk 'Bash' 'sleep 240; ls' 240000 $false) 'allow'
Check 'sleep 200 ok' (Mk 'Bash' 'sleep 200; tail -3 /tmp/x' 230000 $false) 'allow'
Check 'sleep 241 deny' (Mk 'Bash' 'sleep 241' $null $false) 'deny'
Check 'sleep 300 background ok' (Mk 'Bash' 'sleep 300; echo done' $null $true) 'allow'
Check 'timeout 400 wsl wrapper' (Mk 'Bash' 'MSYS_NO_PATHCONV=1 timeout 400 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /root/x.sh' 420000 $false) 'deny'
Check 'timeout 400 wsl wrapper low tool timeout' (Mk 'Bash' 'MSYS_NO_PATHCONV=1 timeout 400 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /root/x.sh' 200000 $false) 'deny'
Check 'wsl bash -c sleep inside' (Mk 'Bash' "wsl.exe -d DwemerAI4Skyrim3 -- bash -c 'sleep 600; ls'" $null $false) 'deny'
Check 'ssh 4080 sleep inside' (Mk 'Bash' "ssh 4080 'powershell -c Start-Sleep 400'" $null $false) 'deny'
Check 'timeout 115 ok' (Mk 'Bash' 'timeout 115 bash tools/automation/wait-row.sh /c/x.out 100; tail -c 500 /c/x.out' $null $false) 'allow'
Check 'timeout 5m' (Mk 'Bash' 'timeout 5m bash big.sh' 400000 $false) 'deny'
Check 'wait-row 300' (Mk 'Bash' 'bash tools/automation/wait-row.sh /c/x.out 300' 400000 $false) 'deny'
Check 'wait-row 200 ok' (Mk 'Bash' 'bash tools/automation/wait-row.sh /c/x.out 200' 230000 $false) 'allow'
Check 'event-wait backstop 600' (Mk 'Bash' 'bash tools/automation/event-wait.sh --batch /c/x --backstop 600' $null $false) 'deny'
Check 'event-wait backstop 180 ok' (Mk 'Bash' 'bash tools/automation/event-wait.sh --backstop 180' 230000 $false) 'allow'
Check 'event-wait bare big timeout' (Mk 'Bash' 'bash tools/automation/event-wait.sh' 600000 $false) 'deny'
Check 'event-wait bare background ok' (Mk 'Bash' 'bash tools/automation/event-wait.sh' 600000 $true) 'allow'
Check 'bash big timeout loop' (Mk 'Bash' 'D=/c/x; for i in $(seq 1 100); do [ -s $D/v ] && break; sleep 5; done; cat $D/v' 600000 $false) 'deny' 'Loop estimate'
Check 'bash small timeout loop ok' (Mk 'Bash' 'D=/c/x; for i in $(seq 1 100); do [ -s $D/v ] && break; sleep 5; done; cat $D/v' 230000 $false) 'allow'
Check 'bash default timeout loop ok' (Mk 'Bash' 'for i in $(seq 1 22); do grep -q DONE /c/x.out && break; sleep 5; done; tail -2 /c/x.out' $null $false) 'allow'
Check 'while true unbounded big timeout' (Mk 'Bash' 'while true; do grep -q DONE /c/x.out && break; sleep 10; done' 600000 $false) 'deny' 'unbounded'
Check 'until loop background ok' (Mk 'Bash' 'until [ -s /c/x/v ]; do sleep 5; done; cat /c/x/v' 600000 $true) 'allow'
Check 'ps do-while deadline 300' (Mk 'PowerShell' '$t=(Get-Date).AddSeconds(300); do { if (Test-Path C:\x\v) { break }; Start-Sleep 5 } while ((Get-Date) -lt $t)' 400000 $false) 'deny' '300'
Check 'ps do-while deadline 100 default ok' (Mk 'PowerShell' '$t=(Get-Date).AddSeconds(100); do { if (Test-Path C:\x\v) { break }; Start-Sleep 5 } while ((Get-Date) -lt $t); 1' $null $false) 'allow'
Check 'ps Start-Sleep -Seconds 300' (Mk 'PowerShell' 'Start-Sleep -Seconds 300' $null $false) 'deny'
Check 'ps Start-Sleep -s 241' (Mk 'PowerShell' 'Start-Sleep -s 241' $null $false) 'deny'
Check 'ps Start-Sleep -Milliseconds 300000' (Mk 'PowerShell' 'Start-Sleep -Milliseconds 300000' $null $false) 'deny'
Check 'ps Start-Sleep 5 ok' (Mk 'PowerShell' 'Start-Sleep 5; Get-Date' $null $false) 'allow'
Check 'ps Wait-Process -Timeout 600' (Mk 'PowerShell' 'Wait-Process -Id 123 -Timeout 600' 700000 $false) 'deny'
Check 'ps big timeout install' (Mk 'PowerShell' '& C:\KenshiModding\tools\automation\install-dll.ps1 Stobe' 600000 $false) 'deny'
Check 'python time.sleep 500' (Mk 'Bash' 'python3 -c "import time; time.sleep(500)"' 600000 $false) 'deny'
Check 'ping -n 300' (Mk 'Bash' 'ping -n 300 127.0.0.1 > /dev/null' $null $false) 'deny'
Check 'timeout /t 300' (Mk 'PowerShell' 'timeout /t 300' $null $false) 'deny'
Check 'git commit big timeout is short' (Mk 'Bash' 'cd /c/KenshiModding && git commit -q -m "imm26: fix wait loop" -- tools/a.sh && git push -q origin HEAD 2>&1 | tail -1' 600000 $false) 'allow'
Check 'agent-status big timeout is short' (Mk 'Bash' 'cd /c/KenshiModding && powershell -NoProfile -File tools/automation/agent-status.ps1 imm26-x RUNNING "t" "s" "" "n"' 600000 $false) 'allow'
Check 'cat/grep big timeout is short' (Mk 'Bash' 'grep -n foo /c/x.log | head -5; tail -3 /c/x.log' 600000 $false) 'allow'
Check 'cmd.exe bat run big timeout deny' (Mk 'Bash' 'cd /c/KenshiModding/Kenshi-Automation-Harness && cmd.exe //c "tests\run_tests.bat" 2>&1 | grep -n FAIL | head -20' 500000 $false) 'deny'
Check 'bash script big timeout deny' (Mk 'Bash' 'bash rowtools/hunt26a-run-dest.sh /c/rows/x > /c/rows/x.out 2>&1' 600000 $false) 'deny' 'run_in_background'
Check 'big timeout exactly 240000 ok' (Mk 'Bash' 'bash rowtools/x.sh' 240000 $false) 'allow'
Check 'big timeout 240001 deny' (Mk 'Bash' 'bash rowtools/x.sh' 240001 $false) 'deny'
Check 'heredoc python text mentions sleep 600 (not executed)' (Mk 'Bash' "python3 - <<'EOF'`nopen('/tmp/x','w').write('sleep 600')`nEOF" $null $false) 'allow'
Check 'heredoc bash body sleep 600 (executed)' (Mk 'Bash' "bash <<'EOF'`nsleep 600`nEOF" $null $false) 'deny'
Check 'rw_sleep helper name not a sleep' (Mk 'Bash' 'source defs.sh; rw_sleep 500' $null $false) 'allow'
Check 'Monitor/other tool ignored' (Mk 'Monitor' 'sleep 900' $null $false) 'allow'
# who
Check 'coordinator exempt' (Mk 'Bash' 'sleep 300' $null $false 'coordinator') 'allow'
Check 'other session denied' (Mk 'Bash' 'sleep 300' $null $false 'other') 'deny'
Check 'no session id fails open' (Mk 'Bash' 'sleep 300' $null $false 'nosid') 'allow'
Set-Coord $coord (Get-Date).AddMinutes(-40)
Check 'stale coordinator.current fails open for non-agent' (Mk 'Bash' 'sleep 300' $null $false 'other') 'allow'
Check 'stale coordinator.current still denies subagent' (Mk 'Bash' 'sleep 300' $null $false 'agent') 'deny'
Set-Coord $coord (Get-Date)
Remove-Item -LiteralPath (Join-Path $tmp 'coordinator.current')
Check 'missing coordinator.current fails open for non-agent' (Mk 'Bash' 'sleep 300' $null $false 'other') 'allow'
Check 'missing coordinator.current still denies subagent' (Mk 'Bash' 'sleep 300' $null $false 'agent') 'deny'
Set-Coord $coord (Get-Date)
# escape + log
$flag = Join-Path $tmp 'keepalive.off'
Set-Content -LiteralPath $flag -Value 'off'
Check 'keepalive.off escape' (Mk 'Bash' 'sleep 300' $null $false) 'allow'
Remove-Item -LiteralPath $flag
$env:KAH_KEEPALIVE_OFF = '1'
Check 'KAH_KEEPALIVE_OFF=1 escape' (Mk 'Bash' 'sleep 300' $null $false) 'allow'
$env:KAH_KEEPALIVE_OFF = ''
Check 'garbage stdin fails open' @{ tool_name = 'Bash' } 'allow'
$log = Join-Path $tmp 'keepalive-denies.log'
if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern "`tDENY`t" -Quiet) -and (Select-String -LiteralPath $log -Pattern "`tALLOW-SHORT`t" -Quiet)) { $script:pass++ }
else { $script:fail++; Write-Output 'FAIL log: keepalive-denies.log lacks DENY and/or ALLOW-SHORT lines' }

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ("SELFTEST keepalive-guard: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
