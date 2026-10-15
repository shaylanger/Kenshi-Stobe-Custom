# agent-router-selftest.ps1: offline checks of hooks\agent-router.ps1 (allow / deny / fail-open), incl. the "no in-session long-running agents" rule.
# Runs the hook as a subprocess with JSON on stdin; AGENT_LEDGER points at a temp file. Prints SELFTEST PASS n/n or FAIL.
$hook = Join-Path $PSScriptRoot 'hooks\agent-router.ps1'
$tmp = Join-Path $env:TEMP ("agent-router-selftest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:AGENT_LEDGER = Join-Path $tmp 'ledger.tsv'
$pass = 0; $fail = 0
function Run-Hook([string]$stdin, [hashtable]$envx = @{}) {
    $o = Join-Path $tmp ([guid]::NewGuid().ToString('N'))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    foreach ($k in $envx.Keys) { $psi.EnvironmentVariables[$k] = $envx[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($stdin); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    [pscustomobject]@{ Exit = $p.ExitCode; Out = $out; Err = $err }
}
function Call([string]$desc, [string]$stype = '', $bg = $null, [string]$cwd = 'C:\KenshiModding') {
    $ti = [ordered]@{ description = $desc; prompt = 'do the thing' }
    if ($stype) { $ti['subagent_type'] = $stype }
    if ($null -ne $bg) { $ti['run_in_background'] = $bg }
    Run-Hook (@{ tool_name = 'Agent'; cwd = $cwd; tool_input = $ti } | ConvertTo-Json -Depth 6 -Compress)
}
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; "ok   $name" } else { $script:fail++; "FAIL $name $detail" }
}
function Allowed($r) { $r.Exit -eq 0 -and $r.Out -match '"permissionDecision":"allow"' }
function Denied($r) { $r.Exit -eq 2 }

$r = Call '[case:read] list files' 'kenshi-reader';                   Check 'reader foreground allowed' (Allowed $r) "$($r.Exit) $($r.Err)"
$r = Call '[case:read] list files' 'kenshi-reader' $true;            Check 'reader run_in_background=true denied' (Denied $r)
Check 'bg denial prints spawn-wp-session command' ($r.Err.Contains('spawn-wp-session.ps1 imm26-list-files read C:\KenshiTestRuns\agents\briefs\imm26-list-files.md')) $r.Err
Check 'bg denial says agent-host, never a visible window' ($r.Err -match 'agent-host job' -and $r.Err -match 'never a visible window') $r.Err
$r = Call '[case:read] list files' 'kenshi-reader' 'true';           Check 'run_in_background="true" (string) denied' (Denied $r)
$r = Call '[case:read] list files' 'kenshi-reader' $false;           Check 'run_in_background=false allowed' (Allowed $r)
$r = Call '[case:read] list files [short]' 'kenshi-reader' $true;    Check 'bg + [short] allowed' (Allowed $r)
$r = Call '[case:patch] wpA fix foo';                                Check 'case patch denied' (Denied $r)
Check 'patch denial names tier command' ($r.Err -match 'spawn-wp-session\.ps1 imm26-wpa-fix-foo patch ') $r.Err
$r = Call '[case:generate] write x' 'kenshi-generator';              Check 'case generate denied' (Denied $r)
$r = Call '[case:debug] why y';                                      Check 'case debug denied' (Denied $r)
$r = Call '[case:investigate] bug z';                                Check 'case investigate denied' (Denied $r)
$r = Call '[case:escalate] hard' 'kenshi-escalation';                Check 'case escalate denied' (Denied $r)
Check 'escalate denial uses escalate tier' ($r.Err -match 'spawn-wp-session\.ps1 \S+ escalate ') $r.Err
$r = Call '[case:patch] tiny edit [short]';                          Check 'patch + [short] allowed' (Allowed $r)
Check 'allowed patch got generator routing' ($r.Out -match '"model":"sonnet"' -and $r.Out -match 'Routing: case=patch tier=kenshi-generator') $r.Out
$r = Call '[case:debug] tiny [inproc-ok:one grep]';                  Check 'debug + [inproc-ok:reason] allowed' (Allowed $r)
$r = Call '[case:debug] tiny [inproc-ok:]';                          Check 'empty [inproc-ok:] does not unlock' (Denied $r)
$r = Call '[case:grade] compare outputs' 'kenshi-grader';            Check 'grade (not long-running) allowed' (Allowed $r)
$r = Call 'no tag' 'kenshi-generator';                               Check 'untagged generator still denied (no case)' (Denied $r)
$r = Call '[case:patch] wpA fix foo' '' $null 'C:\Windows';          Check 'cwd outside KenshiModding: no action' ($r.Exit -eq 0 -and -not $r.Out)
$r = Run-Hook 'this is not json {{{';                                Check 'fail-open: garbage stdin' ($r.Exit -eq 0 -and $r.Err -match 'internal error')
$bad = Join-Path $tmp 'bad-policy.json'; Set-Content -LiteralPath $bad -Value '{not json'
$r = Run-Hook (@{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ description = '[case:patch] x'; prompt = 'p' } } | ConvertTo-Json -Depth 6 -Compress) @{ AGENT_POLICY = $bad }
Check 'fail-open: unreadable policy lets a patch call through' ($r.Exit -eq 0 -and -not $r.Out)
$r = Run-Hook '{"tool_name":"Bash","cwd":"C:\KenshiModding","tool_input":{}}'; Check 'non-Agent tool ignored' ($r.Exit -eq 0 -and -not $r.Out)
Check 'ledger has deny rows' ((Get-Content -Raw $env:AGENT_LEDGER) -match "`tdeny`t")

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
$n = $pass + $fail
if ($fail) { "SELFTEST FAIL $pass/$n"; exit 1 } else { "SELFTEST PASS $pass/$n" }
