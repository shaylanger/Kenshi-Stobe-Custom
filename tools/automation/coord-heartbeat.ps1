# coord-heartbeat.ps1: liveness signal of the COORDINATOR session, read by coord-supervisor.ps1.
# 2026-10-15: the coordinator died at 12:45 and nothing noticed until 14:20; the supervisor needs a heartbeat to see that.
#
# File: C:\KenshiTestRuns\coordinator.heartbeat, one line: "<epoch seconds> <session id> <ISO time>".
#
# Usage
#   Hook mode (no args): PostToolUse hook of the project settings.json; reads the hook JSON on stdin.
#       - first beat ever, or a Bash command that runs session-start.ps1 (= a coordinator starting up): this session CLAIMS
#         ownership (the file's session id becomes this session).
#       - later beats count only from the owner session (subagent calls of the owner session carry the same session id, so a
#         coordinator that waits on subagents still beats); other sessions (Shay's relay, peer sessions) never overwrite it,
#         so they cannot mask a dead coordinator.
#   -Beat   refresh the epoch only, keep the owner (used by event-wait.sh: `powershell -NoProfile -File coord-heartbeat.ps1 -Beat`).
#   -Claim [-Session <id>]   force ownership (manual / scripts); id defaults to 'manual'.
#   -Status print age + owner; exit 0.   -Selftest   temp-dir tests, no real file touched.
# Always exits 0 and prints nothing in hook mode (never blocks a tool call). Env KCS_RUNS overrides C:\KenshiTestRuns.
param([switch]$Beat, [switch]$Claim, [string]$Session = '', [switch]$Status, [switch]$Selftest)

$ErrorActionPreference = 'Stop'

function Get-HbPath([string]$runs) { Join-Path $runs 'coordinator.heartbeat' }

function Read-Hb([string]$path) {
    # returns @{Epoch;Session} or $null (absent/unparseable)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $t = (Get-Content -LiteralPath $path -Raw -ErrorAction Stop).Trim()
        $p = $t -split '\s+'
        if ($p.Count -ge 1 -and $p[0] -match '^\d+$') {
            return @{ Epoch = [int64]$p[0]; Session = $(if ($p.Count -ge 2) { $p[1] } else { '' }) }
        }
    } catch {}
    return $null
}

function Write-Hb([string]$path, [string]$session, [int64]$epoch) {
    $iso = [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, "$epoch $session $iso`r`n", (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

# Core decision: returns 'claimed' | 'beat' | 'ignored'
function Invoke-Beat([string]$runs, [string]$session, [bool]$claim, [bool]$refreshOnly, [int64]$now) {
    $path = Get-HbPath $runs
    New-Item -ItemType Directory -Force -Path $runs | Out-Null
    $cur = Read-Hb $path
    if ($refreshOnly) {
        $s = if ($cur) { $cur.Session } else { 'event-wait' }
        Write-Hb $path $s $now
        return 'beat'
    }
    if (-not $session) { $session = 'unknown' }
    if ($claim -or -not $cur) { Write-Hb $path $session $now; return 'claimed' }
    if ($cur.Session -eq $session) { Write-Hb $path $session $now; return 'beat' }
    return 'ignored'
}

function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

if ($Selftest) {
    $fails = 0
    function T([bool]$ok, [string]$n) { if ($ok) { "PASS $n" } else { "FAIL $n"; $script:fails++ } }
    $d = Join-Path ([IO.Path]::GetTempPath()) ("coordhb-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $p = Get-HbPath $d
        T ((Invoke-Beat $d 'A' $false $false 1000) -eq 'claimed') 'first beat claims'
        T ((Read-Hb $p).Session -eq 'A' -and (Read-Hb $p).Epoch -eq 1000) 'file has epoch + session'
        T ((Invoke-Beat $d 'A' $false $false 1010) -eq 'beat' -and (Read-Hb $p).Epoch -eq 1010) 'owner beats'
        T ((Invoke-Beat $d 'B' $false $false 1020) -eq 'ignored' -and (Read-Hb $p).Epoch -eq 1010) 'other session cannot mask'
        T ((Invoke-Beat $d '' $false $true 1030) -eq 'beat' -and (Read-Hb $p).Session -eq 'A' -and (Read-Hb $p).Epoch -eq 1030) '-Beat keeps owner'
        T ((Invoke-Beat $d 'B' $true $false 1040) -eq 'claimed' -and (Read-Hb $p).Session -eq 'B') 'claim takes over (session-start)'
        [IO.File]::WriteAllText($p, 'garbage')
        T ($null -eq (Read-Hb $p)) 'garbage = absent'
        T ((Invoke-Beat $d 'C' $false $false 1050) -eq 'claimed') 'garbage file re-claimed'
        Remove-Item -LiteralPath $p -Force
        T ((Invoke-Beat $d '' $false $true 1060) -eq 'beat' -and (Read-Hb $p).Session -eq 'event-wait') '-Beat with no file creates it'
    } finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    if ($fails) { "SELFTEST FAILED ($fails)"; exit 1 } else { 'SELFTEST OK'; exit 0 }
}

try {
    $runs = if ($env:KCS_RUNS) { $env:KCS_RUNS } else { 'C:\KenshiTestRuns' }
    $now = Get-Now
    if ($Status) {
        $h = Read-Hb (Get-HbPath $runs)
        if ($h) { "heartbeat age $($now - $h.Epoch) s, owner session $($h.Session)" } else { 'no heartbeat file' }
        exit 0
    }
    # Independent agent sessions (spawn-wp-session.ps1 sets KAH_AGENT_NAME) are not the coordinator: never beat, claim or refresh
    # (a working agent must not mask a dead coordinator; event-wait.sh -Beat from an agent session is skipped too).
    if ($env:KAH_AGENT_NAME) { exit 0 }
    # Tail sessions (overlap handoff, runs\tail\<session>.flag) never beat: only the live coordinator does. -Beat (event-wait.sh) has no
    # session id, so it is skipped while the heartbeat owner is a tail session (the new coordinator claims ownership via session-start.ps1).
    function Test-TailSid([string]$sid0) { [bool]($sid0 -and (Test-Path -LiteralPath (Join-Path (Join-Path $runs 'tail') (($sid0 -replace '[\/:*?"<>|]', '_') + '.flag')))) }
    if ($Beat) {
        $cur0 = Read-Hb (Get-HbPath $runs)
        if ($cur0 -and (Test-TailSid $cur0.Session)) { exit 0 }
        [void](Invoke-Beat $runs '' $false $true $now); exit 0
    }
    if ($Claim) { [void](Invoke-Beat $runs $(if ($Session) { $Session } else { 'manual' }) $true $false $now); exit 0 }
    # hook mode
    $sid = $Session; $claim = $false
    if ([Console]::IsInputRedirected) {
        $raw = [Console]::In.ReadToEnd()
        if ($raw) {
            $in = $raw | ConvertFrom-Json
            if ($in.session_id) { $sid = "$($in.session_id)" }
            elseif ($in.transcript_path) { $sid = [IO.Path]::GetFileNameWithoutExtension("$($in.transcript_path)") }
            $cmd = ''
            if ($in.tool_input -and $in.tool_input.command) { $cmd = "$($in.tool_input.command)" }
            # a coordinator starting up runs session-start.ps1 as its first step (and not an agent doing so)
            if (-not $in.agent_id -and $cmd -match 'session-start\.ps1') { $claim = $true }
        }
    }
    if (Test-TailSid $sid) { exit 0 }   # a tail session never beats or claims
    [void](Invoke-Beat $runs $sid $claim $false $now)
} catch {}
exit 0
