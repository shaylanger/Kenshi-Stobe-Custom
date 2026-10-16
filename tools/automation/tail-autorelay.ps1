# tail-autorelay.ps1 (PI-25, Shay 2026-10-15): the tail session relays its agents' results WITHOUT a model turn.
#   tail-autorelay.ps1 -TailSession <id> [-PollSec 7] [-Once] [-MaxMinutes 0] [-RunsDir <dir>]
# Polls (no LLM) the agents the tail owns (flag agents + ledger owner_session tail:<id>). When one reaches DONE / FAILED / STOPPED-CONTEXT
# it calls tail-relay.ps1 itself (same TAIL-RELAY message + inbox\coordinator file the coordinator's waker already reads) with a summary built from
#   agents\out\<name>\latest.md   (STOPPED-CONTEXT: agents\<name>.handoff.md first), falling back to the other file, then to the status file:
#   the first 30 non-empty lines + every line starting DECISION or QUESTION (case-insensitive; never dropped by the 30-line message cut:
#   decisions are reserved room first). DONE -> Kind DONE; FAILED and STOPPED-CONTEXT -> Kind FAILED (STOPPED-CONTEXT adds a respawn line).
# Idempotent: <runs>\tail\<id>.autorelay.json records "agent|STATE" already relayed; a second run never relays the same agent+status again.
# Exits when every owned agent is relayed, when the tail flag is gone, or after -MaxMinutes (0 = no limit). -Once = one pass (selftest).
# One log line per relay on stdout and in <runs>\tail\autorelay.log. Manual tail-relay.ps1 relays stay allowed (an agent relayed by hand
# before this runs is still relayed once more only if it has no state entry: use -Skip <agent,...> to leave such agents out).
# Cheap tail (Shay 2026-10-16): owned = flag agents + ledger owner tail:<id> + agents registered in agents\ids.json by the tail's session (agents that are in
# no program ledger still get relayed); the state file is re-read under a cross-process mutex for every pass, so two instances (or tail-wait's -Once
# retry) never relay the same agent+status twice; an agent whose relay file already exists (manual tail-relay.ps1, or moved to delivered\ / done\) is
# recorded as relayed, not re-sent; a second long-running instance for the same tail exits at once. `tail-mode.ps1 enter` starts this script itself.
# Env: KAH_RUNS_DIR (default C:\KenshiTestRuns), KPL_DIR. Selftest: tail-autorelay-selftest.ps1.
param(
    [Parameter(Mandatory)][string]$TailSession,
    [int]$PollSec = 7,
    [switch]$Once,
    [int]$MaxMinutes = 0,
    [string]$RunsDir = '',
    [string[]]$Skip = @()
)
# NOTE: dot-sourcing tail-mode.ps1 defines its own script-scope names (Session, Runs, Agent, Agents, Name, runsDir, ...): do not reuse them here.
. (Join-Path $PSScriptRoot 'tail-mode.ps1')
$ErrorActionPreference = 'Continue'
$arRuns = Get-TailRuns $RunsDir
$env:KAH_RUNS_DIR = $arRuns                       # children (tail-relay, program-ledger) see the same dir
if ($RunsDir -and -not $env:KPL_DIR) { $env:KPL_DIR = Join-Path $arRuns 'programs' }
$arRelay = Join-Path $PSScriptRoot 'tail-relay.ps1'
$arTail = Get-TailDir $arRuns
$arSafe = ($TailSession -replace '[\/:*?"<>|]', '_')
$arStateFile = Join-Path $arTail "$arSafe.autorelay.json"
$arLog = Join-Path $arTail 'autorelay.log'
$arSkipList = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

function Read-ArState {
    $h = @{}
    try {
        $j = (Get-Content -LiteralPath $arStateFile -Raw -ErrorAction Stop).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
        foreach ($p in $j.relayed.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    } catch { }
    return $h
}
function Save-ArState($h) {
    $o = [ordered]@{}
    foreach ($k in ($h.Keys | Sort-Object)) { $o[$k] = $h[$k] }
    $obj = [ordered]@{ session = $TailSession; updated = (Get-Date).ToString('o'); relayed = $o }
    New-Item -ItemType Directory -Force -Path $arTail | Out-Null
    [IO.File]::WriteAllText($arStateFile, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}
function Write-ArLog([string]$line) {
    $l = "$((Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')) tail-autorelay $TailSession $line"
    $l
    try { New-Item -ItemType Directory -Force -Path $arTail | Out-Null; Add-Content -LiteralPath $arLog -Value $l } catch { }
}

# The agents this tail owns now (flag list + ledger owner + ids.json, tail-mode.ps1 Get-TailOwnedNames).
function Get-OwnedNames($flag) { return @(Get-TailOwnedNames $arRuns $flag) }

# One pass at a time per tail, across processes (named mutex; abandoned = the previous owner died, still ours).
$arPass = New-Object Threading.Mutex($false, "Global\tail-autorelay-pass-$arSafe")
function Enter-ArPass { try { return $arPass.WaitOne(90000) } catch [Threading.AbandonedMutexException] { return $true } }

# Summary: first 30 non-empty lines + every DECISION/QUESTION line (reserved room first, so the relay's 30-line cut cannot drop one).
function Build-Summary([string]$agentName, [string]$state, [string]$reportPath, [string]$statusPath) {
    $src = @()
    if ($reportPath -and (Test-Path -LiteralPath $reportPath -PathType Leaf)) { $src = @(Get-Content -LiteralPath $reportPath -TotalCount 5000 -ErrorAction SilentlyContinue) }
    elseif ($statusPath -and (Test-Path -LiteralPath $statusPath -PathType Leaf)) { $src = @(Get-Content -LiteralPath $statusPath -TotalCount 60 -ErrorAction SilentlyContinue) }
    $src = @($src | ForEach-Object { ([string]$_).TrimEnd().Replace('"', "'") } | Where-Object { $_.Trim() })
    $dec = @($src | Where-Object { $_ -match '^\s*(?i:DECISION|QUESTION)' } | Select-Object -Unique)
    if ($dec.Count -gt 10) { $dec = @($dec | Select-Object -First 10) }
    $pre = @()
    if ($state -eq 'STOPPED-CONTEXT') { $pre += "STATUS STOPPED-CONTEXT: $agentName stopped at its context limit; respawn a FRESH agent (${agentName}2) from its handoff/status file." }
    elseif ($state -eq 'FAILED') { $pre += "STATUS FAILED: $agentName reported FAILED; read the report." }
    $room = 22 - $pre.Count - $dec.Count     # relay body room is about 26-27 lines; keep a margin for the 'more lines' marker
    if ($room -lt 4) { $room = 4 }
    $head = @($src | Select-Object -First 30 | Select-Object -First $room)
    $tail = @($dec | Where-Object { $head -notcontains $_ })
    return @($pre + $head + $tail)
}

function Invoke-OneRelay([string]$agentName, [string]$state) {
    $statusPath = Join-Path (Join-Path $arRuns 'agents') "$agentName.status"
    $latest = Join-Path $arRuns "agents\out\$agentName\latest.md"
    $handoff = Join-Path $arRuns "agents\$agentName.handoff.md"
    $cands = if ($state -eq 'STOPPED-CONTEXT') { @($handoff, $latest) } else { @($latest, $handoff) }
    $report = ''
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Leaf) { $report = $c; break } }
    $summary = (Build-Summary $agentName $state $report $statusPath) -join "`n"
    if (-not $summary.Trim()) { $summary = "$agentName reached $state; no report file found (agents\out\$agentName\latest.md, $agentName.handoff.md) and the status file is empty." }
    $kind = if ($state -eq 'DONE') { 'DONE' } else { 'FAILED' }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $arRelay, '-Agent', $agentName, '-Kind', $kind, '-Summary', $summary)
    if ($report) { $a += @('-Report', $report) }
    $out = & powershell @a 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Report = $report; Info = (($out | Select-Object -Last 2) -join ' / ') } }
    $info = ($out | Where-Object { $_ -like '(inbox file:*' } | Select-Object -First 1)
    return @{ Ok = $true; Report = $report; Info = [string]$info }
}

$deadline = if ($MaxMinutes -gt 0) { (Get-Date).AddMinutes($MaxMinutes) } else { $null }
if (-not $Once) {   # single long-running instance per tail
    $arLife = New-Object Threading.Mutex($false, "Global\tail-autorelay-life-$arSafe")
    $got = $false
    try { $got = $arLife.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { Write-ArLog 'exit: another auto-relay instance already runs for this tail'; exit 0 }
}
Write-ArLog "start poll=${PollSec}s once=$([bool]$Once) state=$arStateFile"
while ($true) {
    $fp = Get-TailFlagPath $arRuns $TailSession
    $flag = if (Test-Path -LiteralPath $fp) { Read-TailFlag $fp } else { $null }
    if (-not $flag) { Write-ArLog 'exit: tail flag gone (or unreadable)'; break }
    if (-not (Enter-ArPass)) { Write-ArLog 'WARNING: pass lock busy > 90 s, skipping this pass'; Start-Sleep -Seconds $PollSec; continue }
    try {
        $state = Read-ArState        # re-read under the lock: another instance may have relayed meanwhile
        $names = @(Get-OwnedNames $flag)
        $allDone = ($names.Count -gt 0)
        foreach ($n in $names) {
            if ($arSkipList -contains $n) { continue }
            $st = Get-AgentStatusState $arRuns $n
            if ($TAIL_TERMINAL -notcontains $st.State) { $allDone = $false; continue }
            $key = "$n|$($st.State)"
            if ($state.ContainsKey($key)) { continue }
            # already relayed by hand / moved to delivered\ or done\ since this status was written: record it, do not send a duplicate
            $doneAt = (Get-Date).AddMinutes(-$st.AgeMin)
            $had = Get-TailRelayState $arRuns $flag $n $doneAt.AddMinutes(1)
            if ($had.Relayed) {
                $state[$key] = (Get-Date).ToString('o'); Save-ArState $state
                Write-ArLog "already-relayed $n $($st.State) (relay file exists, not re-sent)"
                continue
            }
            $r = Invoke-OneRelay $n $st.State
            if ($r.Ok) {
                $state[$key] = (Get-Date).ToString('o'); Save-ArState $state
                Write-ArLog "relayed $n $($st.State) report=$(if ($r.Report) { $r.Report } else { '(none)' }) $($r.Info)"
            } else {
                $allDone = $false
                Write-ArLog "RELAY-FAILED $n $($st.State): $($r.Info) (retry next poll)"
            }
        }
    } finally { try { $arPass.ReleaseMutex() } catch { } }
    if ($names.Count -eq 0) { Write-ArLog 'exit: the tail owns no agents'; break }
    if ($allDone) { Write-ArLog "exit: all $($names.Count) owned agent(s) relayed"; break }
    if ($Once) { Write-ArLog 'exit: -Once pass done'; break }
    if ($deadline -and (Get-Date) -gt $deadline) { Write-ArLog "exit: -MaxMinutes $MaxMinutes reached"; break }
    Start-Sleep -Seconds $PollSec
}
