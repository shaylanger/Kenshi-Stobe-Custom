# agent-rollcall.ps1 [-Json]  : one line per RUNNING agent (roll call) and the data the agent-host monitor uses.
# Dot-source to get Get-AgentRoll. Test switch: KAH_RUNS_DIR (default C:\KenshiTestRuns).
# Fields: Name State StatusAgeMin LogAgeMin Kind (INDEPENDENT = session.json present, INPROC = none) Alive (launcher/claude process) LauncherPid ClaudePid Started StartedAgeMin Latest
param([switch]$Json)
$script:RcRuns = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }

function Test-PidAlive([int]$ProcId) {
    if ($ProcId -le 0) { return $false }
    return [bool](Get-Process -Id $ProcId -ErrorAction SilentlyContinue)
}

function Get-AgentRoll {
    $ad = Join-Path $script:RcRuns 'agents'
    $now = Get-Date
    foreach ($f in Get-ChildItem -LiteralPath $ad -Filter '*.status' -ErrorAction SilentlyContinue) {
        $name = $f.Name -replace '\.status$', ''
        if (Test-Path -LiteralPath (Join-Path $ad "$name.abandoned")) { continue }
        $lines = @(Get-Content -LiteralPath $f.FullName -TotalCount 4 -ErrorAction SilentlyContinue)
        if ($lines.Count -eq 0) { continue }
        $first = ($lines[0] -replace '^\uFEFF', '')
        $parts = $first -split '\s*\|\s*'
        if ($parts.Count -lt 2 -or $parts[1].Trim() -ne 'RUNNING') { continue }
        $latest = ($lines | Where-Object { $_ -like 'latest:*' } | Select-Object -First 1)
        $sj = Join-Path $ad "$name.session.json"
        $sess = $null
        if (Test-Path -LiteralPath $sj) { try { $sess = Get-Content -LiteralPath $sj -Raw | ConvertFrom-Json } catch { } }
        $log = Join-Path $ad "out\$name.log"
        $logAge = $null
        if (Test-Path -LiteralPath $log) { $logAge = [math]::Round(($now - (Get-Item -LiteralPath $log).LastWriteTime).TotalMinutes, 1) }
        # evidence activity counts as a heartbeat: newest file under a directory named on the status `outputs:` line
        $outLine = ($lines | Where-Object { $_ -like 'outputs:*' } | Select-Object -First 1)
        if ($outLine) {
            foreach ($tok in ($outLine -replace '^outputs:\s*', '') -split '[;,]\s*') {
                $p = $tok.Trim()
                if ($p -and (Test-Path -LiteralPath $p -PathType Container)) {
                    $nf = Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($nf) {
                        $evAge = [math]::Round(($now - $nf.LastWriteTime).TotalMinutes, 1)
                        if ($null -eq $logAge -or $evAge -lt $logAge) { $logAge = $evAge }
                    }
                }
            }
        }
        $lp = 0; $cp = 0; $started = $null; $exited = $false
        if ($sess) {
            $lp = [int]$sess.launcher_pid; $cp = [int]$sess.claude_pid
            if ($sess.started) { try { $started = [datetime]$sess.started } catch { } }
            if ($sess.PSObject.Properties.Name -contains 'exited') { $exited = $true }
        }
        [pscustomobject]@{
            Name = $name; State = 'RUNNING'
            StatusAgeMin = [math]::Round(($now - $f.LastWriteTime).TotalMinutes, 1)
            LogAgeMin = $logAge
            Kind = $(if ($sess) { 'INDEPENDENT' } else { 'INPROC' })
            Alive = ((Test-PidAlive $lp) -or (Test-PidAlive $cp)) -and -not $exited
            LauncherPid = $lp; ClaudePid = $cp; Started = $started
            StartedAgeMin = $(if ($started) { [math]::Round(($now - $started).TotalMinutes, 1) } else { $null })
            Latest = $(if ($latest) { ($latest -replace '^latest:\s*', '') } else { '' })
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $rows = @(Get-AgentRoll)
    if ($Json) { $rows | ConvertTo-Json -Depth 3; return }
    if (-not $rows.Count) { 'ROLLCALL no RUNNING agents'; return }
    foreach ($r in $rows) {
        $lat = if ($r.Latest.Length -gt 80) { $r.Latest.Substring(0, 80) } else { $r.Latest }
        "ROLLCALL $($r.Name) kind=$($r.Kind) proc=$(if ($r.Kind -eq 'INPROC') { 'n/a' } elseif ($r.Alive) { 'alive' } else { 'DEAD' }) status_age=$($r.StatusAgeMin)m log_age=$(if ($null -eq $r.LogAgeMin) { '-' } else { "$($r.LogAgeMin)m" }) latest=$lat"
    }
}
