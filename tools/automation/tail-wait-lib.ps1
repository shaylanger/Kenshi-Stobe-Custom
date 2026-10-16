# tail-wait-lib.ps1 (PI-28 + PI-27, Shay 2026-10-15): helpers for the TAIL session's single background wait (tail-wait.ps1) and the Stop-hook check
# (hooks\kenshi-waker-guard.ps1, tail branch only). Functions only; dot-source it. Needs tail-mode.ps1 (dot-sourced here when not yet loaded).
#
# Contract: a tail arms ONE wait (tail-wait.ps1 -Session <id>, run as a background task). It writes <runs>\tail\<session>.wait
# (pid, process start, heartbeat every <=15 s, armed time) and exits as soon as the tail has something to DO. While that wait is provably alive
# and armed AND the tail has nothing to do, the Stop hook lets the turn end (the session idles and is woken by the wait's completion notification).
# Everything is fail closed: any error, missing/corrupt file, dead pid, wrong process, stale heartbeat = "not armed" = the old blocking behaviour.

if (-not (Get-Command Get-TailAgentSet -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'tail-mode.ps1') }

$TAILWAIT_HB_MAX_SEC = 45     # heartbeat older than this = stale (the wait beats every <= 15 s)

function Get-TailWaitPath([string]$runs, [string]$session) { Join-Path (Get-TailDir $runs) (($session -replace '[\\/:*?"<>|]', '_') + '.wait') }

# Cheap tail (Shay 2026-10-16): the wait must not wake the model for a finished agent that the auto-relay (tail-autorelay.ps1, 7 s poll) is
# about to relay. A terminal agent without a relay file/state is "in retry" for TAILWAIT_RELAY_RETRY_MIN minutes (the wait itself re-runs
# `tail-autorelay.ps1 -Once` every TAILWAIT_RETRY_SEC while any is unrelayed); only after that is the relay genuinely missing and the tail
# is needed. A relay file ANYWHERE under inbox\coordinator (top level, delivered\, done\, ...) or the autorelay state counts as relayed
# (Get-TailRelayState in tail-mode.ps1), and an acked agent is never pending.
$TAILWAIT_RELAY_RETRY_MIN = 3
$TAILWAIT_RETRY_SEC = 15

# Terminal, unacked agents with no relay yet (the ones the autorelay still has to do).
function Get-TailUnrelayedAgents([string]$runs, $flag) {
    @(Get-TailAgentSet $runs $flag | Where-Object { $_.Pending -and $_.Why -ne 'running' -and $_.Hint -like 'not relayed yet*' })
}

# What the tail still has to DO (empty = nothing: only running agents, relays awaiting the autorelay's retry, or relays written and waiting for
# delivery/grace). Non-empty = the reason the wait must end / the hook must keep blocking.
function Get-TailWaitAction([string]$runs, $flag) {
    $set = @(Get-TailAgentSet $runs $flag | Where-Object { $_.Pending })
    if (-not $set.Count) { return 'all owned agents are released: nothing left to wait for (the tail may end and closes itself)' }
    foreach ($a in $set) {
        if ($a.Why -eq 'running') { continue }
        if ($a.Hint -like 'relay not delivered yet*') { continue }   # relay already written: only the new coordinator's delivery / the 5 min grace is pending
        if ($a.Hint -like 'not relayed yet*' -and $a.AgeMin -lt $TAILWAIT_RELAY_RETRY_MIN) { continue }   # autorelay still within its retry window
        return "agent $($a.Agent) needs the tail: $($a.Why)$(if ($a.Hint) { ' (' + $a.Hint + ')' })"
    }
    return ''
}

# Is the tail's own wait provably alive and armed? Returns @{ Armed = bool; Why = string }. Never throws (any error = not armed).
function Test-TailWaitArmed([string]$runs, [string]$session, $flag) {
    try {
        $wf = Get-TailWaitPath $runs $session
        if (-not (Test-Path -LiteralPath $wf)) { return @{ Armed = $false; Why = 'no wait registered' } }
        $j = $null
        foreach ($try in 1..3) {   # the wait rewrites the file atomically (temp + move); retry covers a rename in flight
            try { $j = (Get-Content -LiteralPath $wf -Raw -ErrorAction Stop).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 150 }
        }
        if (-not $j) { return @{ Armed = $false; Why = 'wait file unreadable' } }
        if ([string]$j.session -ne $session) { return @{ Armed = $false; Why = 'wait file belongs to another session' } }
        $wpid = 0; if (-not [int]::TryParse([string]$j.pid, [ref]$wpid) -or $wpid -le 0) { return @{ Armed = $false; Why = 'bad pid' } }
        if ($wpid -eq $PID) { return @{ Armed = $false; Why = 'pid is this process' } }
        $hb = [datetimeoffset]::Parse([string]$j.hb)
        if (([datetimeoffset]::Now - $hb).TotalSeconds -gt $TAILWAIT_HB_MAX_SEC) { return @{ Armed = $false; Why = 'heartbeat stale' } }
        if (([datetimeoffset]::Now - $hb).TotalSeconds -lt -5) { return @{ Armed = $false; Why = 'heartbeat in the future' } }
        $pr = Get-Process -Id $wpid -ErrorAction SilentlyContinue
        if (-not $pr) { return @{ Armed = $false; Why = 'wait pid not running' } }
        $ps = [datetimeoffset]::Parse([string]$j.proc_start)
        if ([math]::Abs(($pr.StartTime.ToUniversalTime() - $ps.UtcDateTime).TotalSeconds) -gt 3) { return @{ Armed = $false; Why = 'pid reused by another process' } }
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$wpid" -ErrorAction Stop
        $cl = [string]$ci.CommandLine
        if ($cl -notmatch 'tail-wait\.ps1' -or $cl -notmatch [regex]::Escape($session)) { return @{ Armed = $false; Why = 'process command line is not this session''s tail-wait.ps1' } }
        if ($flag -and $flag.Created) {
            $fc = [datetimeoffset]::Parse([string]$flag.Created)
            if ([datetimeoffset]::Parse([string]$j.armed) -lt $fc.AddSeconds(-5)) { return @{ Armed = $false; Why = 'wait was armed before this tail started' } }
        }
        return @{ Armed = $true; Why = "wait pid $wpid alive, heartbeat $([int]([datetimeoffset]::Now - $hb).TotalSeconds) s old" }
    } catch { return @{ Armed = $false; Why = "check error: $($_.Exception.Message)" } }
}
