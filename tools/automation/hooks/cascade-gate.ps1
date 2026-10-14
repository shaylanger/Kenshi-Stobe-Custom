# cascade-gate.ps1 (Stop hook, main session): a work ticket cannot be left half-done (Shay 2026-10-14).
# A work ticket has a patch, generate, debug or escalate run in the last 6 h (C:\KenshiTestRuns\ledger\agent-runs.tsv, written by
# agent-ledger-post.ps1). Its next cascade step follows from its last run, once that run has finished:
#   patch, generate, escalate -> a verifier (case verify) must run next
#   verify, judge, review     -> verdicts\<ticket>.txt must be written after that run. PASS ends the ticket. FAIL needs a debugger,
#                                unless an escalation already ran. A missing or stale verdict needs the verifier run again.
#   debug                     -> a generator (case patch) must run next, with the diagnosis
# A run has finished when the coordinator's own transcript (transcript_path) holds its task-notification. A ticket with a run still
# going is skipped. stop_hook_active allows the stop, so there is no loop. Review-only tickets are ignored.
# Missing transcript_path: nothing is marked finished, so nothing blocks (fails open). Log: one line per Stop in cascade-gate.log.
# Env AGENT_RUNS, AGENT_VERDICTS and AGENT_GATE_LOG override the paths (tests).
$runsF = if ($env:AGENT_RUNS) { $env:AGENT_RUNS } else { 'C:\KenshiTestRuns\ledger\agent-runs.tsv' }
$verdD = if ($env:AGENT_VERDICTS) { $env:AGENT_VERDICTS } else { 'C:\KenshiTestRuns\verdicts' }
$logF = if ($env:AGENT_GATE_LOG) { $env:AGENT_GATE_LOG } else { 'C:\KenshiTestRuns\ledger\cascade-gate.log' }

function Write-GateLog([string]$msg) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logF) | Out-Null
        Add-Content -LiteralPath $logF -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
    } catch {}
}

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    if ([string]$in.cwd -notmatch '^C:[\\/]KenshiModding([\\/]|$)') { exit 0 }
    $tp = [string]$in.transcript_path
    Write-GateLog ("stop transcript=" + ($tp -ne '' -and (Test-Path -LiteralPath $tp)))
    if ($in.stop_hook_active) { Write-GateLog 'skip: stop_hook_active'; exit 0 }
    if (-not (Test-Path -LiteralPath $runsF)) { exit 0 }
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $cut = (Get-Date).AddHours(-6)
    $runs = @()
    foreach ($row in (Get-Content -LiteralPath $runsF -Encoding UTF8)) {
        $f = $row -split "`t"
        if ($f.Count -lt 8 -or -not $f[4]) { continue }
        try { $t = [datetime]::ParseExact($f[0].Trim(), 'yyyy-MM-dd HH:mm:ss', $inv) } catch { continue }
        if ($t -ge $cut) { $runs += [pscustomobject]@{ ts = $t; aid = $f[1]; case = $f[3]; ticket = $f[4] } }
    }
    $workCases = @('patch', 'generate', 'debug', 'escalate')
    $tickets = @($runs | Where-Object { $workCases -contains $_.case } | ForEach-Object { $_.ticket } | Sort-Object -Unique)
    if ($tickets.Count -eq 0) { exit 0 }

    $tx = [string]$in.transcript_path
    $txOk = [bool]($tx -and (Test-Path -LiteralPath $tx))
    $done = @{}
    if ($txOk) {
        foreach ($m in (Select-String -LiteralPath $tx -Pattern '<task-id>([A-Za-z0-9_-]+)</task-id>')) {
            foreach ($g in $m.Matches) { $done[$g.Groups[1].Value] = $true }
        }
    }
    Write-GateLog ("tickets={0} transcript={1} finished_agents={2}" -f $tickets.Count, $txOk, $done.Count)

    $pending = @()
    foreach ($tk in $tickets) {
        $tr = @($runs | Where-Object { $_.ticket -eq $tk } | Sort-Object ts)
        if (@($tr | Where-Object { -not $done.ContainsKey($_.aid) }).Count -gt 0) { continue }
        $last = $tr[-1]
        $verdict = Join-Path $verdD "$tk.txt"
        if ($last.case -in @('patch', 'generate', 'escalate')) {
            $pending += "ticket ${tk}: spawn a verifier now (Agent, description '[case:verify][ticket:$tk] verify $tk', subagent kenshi-verifier) with the changed files, the checks run and their results. It writes verdicts\$tk.txt: PASS or FAIL, then at least two evidence paths."
        } elseif ($last.case -eq 'debug') {
            $pending += "ticket ${tk}: the debugger's diagnosis is in. Spawn a generator with it now (Agent, description '[case:patch][ticket:$tk] fix $tk', subagent kenshi-generator), then a verifier."
        } elseif ($last.case -in @('verify', 'judge', 'review')) {
            if (-not (Test-Path -LiteralPath $verdict) -or (Get-Item -LiteralPath $verdict).LastWriteTime -lt $last.ts) {
                $pending += "ticket ${tk}: the verifier finished but verdicts\$tk.txt is missing or older than its run. Re-run the verifier."
            } else {
                $word = ((Get-Content -LiteralPath $verdict -TotalCount 1 -Encoding UTF8) -replace '^\uFEFF', '').Trim().Split(' ')[0]
                if ($word -eq 'FAIL') {
                    if (-not @($tr | Where-Object { $_.case -eq 'escalate' }).Count) {
                        $pending += "ticket ${tk}: verdict FAIL. Spawn the debugger now (Agent, description '[case:debug][ticket:$tk] diagnose $tk', subagent kenshi-debugger) with the verifier's evidence."
                    }
                } elseif ($word -ne 'PASS') {
                    $pending += "ticket ${tk}: verdicts\$tk.txt must start with PASS or FAIL."
                }
            }
        }
    }
    Write-GateLog ("pending={0}" -f $pending.Count)
    if ($pending.Count -eq 0) { exit 0 }
    @{ decision = 'block'; reason = ('cascade gate: ' + ($pending -join ' ')) } | ConvertTo-Json -Compress | Write-Output
    exit 0
} catch {
    Write-GateLog ("error: " + $_.Exception.Message)
    exit 0
}
