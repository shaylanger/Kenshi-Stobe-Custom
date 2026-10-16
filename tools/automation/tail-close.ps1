# tail-close.ps1: a TAIL session that has finished all its agents tells the current coordinator and CLOSES itself
# (docs/TAIL_HANDOFF_CONTRACT.md "Closing a finished tail", Shay 2026-10-15), so finished sessions are not left open.
#   tail-close.ps1 -Session <id> [-DryRun] [-DelaySec 20] [-NoRelay] [-Source manual|hook|ack] [-Runs <dir>]
# Steps: (1) re-check that the flag exists, every agent in it is done AND acknowledged, the claude pid still exists AND matches the flag
# (process name + start time recorded by `tail-mode.ps1 enter`; older flags: claude/node and not younger than the flag), and it is NOT the
# current coordinator (coordinator.current session or pid, heartbeat owner) nor an ancestor of this caller (manual use);
# (2) send one TAIL-DONE message (tail-relay.ps1 -Kind TAILDONE: inbox file + the printed text for SendMessage to the current coordinator),
# skipped with -NoRelay (used when the coordinator itself triggers the close via tail-ack.ps1);
# (3) a DETACHED worker waits -DelaySec (default 20 s, so the final text/relay is delivered), re-runs every check, kills the claude process
# tree (taskkill /T /F), and only when it is gone removes the flag. Every outcome is logged to <runs>\tail\closed.log.
# -DryRun prints what would happen and kills nothing. FAIL CLOSED: any error or doubt = nothing is killed, the reason is printed and logged.
# Switches by env: KAH_TAIL_NO_CLOSE=1 (selftests: never schedule a kill), KAH_RUNS_DIR (runs dir). Selftest: tail-close-selftest.ps1.
# Automatic callers: the Stop hook (tools\automation\hooks\kenshi-waker-guard.ps1, tail branch, when the tail may end) and tail-ack.ps1
# (when the acknowledged agent was the tail's last unacknowledged one). Manual: the coordinator after the last ack.
param(
    [Parameter(Mandatory)][string]$Session,
    [switch]$DryRun, [switch]$NoRelay, [switch]$Worker,
    [int]$DelaySec = -1,
    [ValidateSet('manual', 'hook', 'ack')][string]$Source = 'manual',
    [string]$Runs = ''
)
$ErrorActionPreference = 'Stop'
$cfg = @{ Session = $Session; DryRun = [bool]$DryRun; NoRelay = [bool]$NoRelay; Worker = [bool]$Worker; Delay = $DelaySec; Source = $Source; Runs = $Runs; Self = $PSCommandPath; Dir = $PSScriptRoot }
if ($cfg.Delay -lt 0) { $cfg.Delay = if ($env:KAH_TAIL_CLOSE_DELAY) { [int]$env:KAH_TAIL_CLOSE_DELAY } else { 20 } }

# the tail-mode functions come in via dot-source inside a scriptblock (its param block would reset our variables otherwise)
& {
    param($cfg)
    . (Join-Path $cfg.Dir 'tail-mode.ps1')
    $runs = Get-TailRuns $cfg.Runs
    $sid = $cfg.Session
    $log = Join-Path (Get-TailDir $runs) 'closed.log'
    function Write-CloseLog([string]$action, [string]$detail) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null
            Add-Content -LiteralPath $log -Value ("{0} {1} session={2} source={3} {4}" -f (Get-Date).ToString('o'), $action, $sid, $cfg.Source, $detail) -Encoding UTF8
        } catch { }
    }
    try {
        $self = ($cfg.Source -eq 'hook') -or $cfg.Worker   # the hook runs inside the tail's own process tree; the worker is detached
        $chk = Test-TailClosable $runs $sid $self
        if (-not $chk.Ok) {
            if ($chk.Gone -and -not $cfg.DryRun) {
                # process already gone and all agents done+acked: just drop the flag
                $v = Get-TailStopVerdict $runs $sid
                if ($v.Tail -and -not $v.Block) {
                    Remove-Item -LiteralPath (Get-TailFlagPath $runs $sid) -Force -ErrorAction Stop
                    Write-CloseLog 'FLAG-REMOVED' "process $($chk.Pid) already gone, all agents done+acked"
                    "tail-close: process $($chk.Pid) already gone; flag removed (all agents done+acked)."
                    return
                }
            }
            Write-CloseLog 'REFUSED' $chk.Why
            "tail-close: NOT closing tail $sid -- $($chk.Why)"
            return
        }
        if ($cfg.DryRun) {
            Write-CloseLog 'DRYRUN' "would close pid $($chk.Pid) ($($chk.Name)) after $($cfg.Delay) s"
            "tail-close DRY-RUN: would relay TAIL-DONE$(if ($cfg.NoRelay) { ' (skipped: -NoRelay)' }), wait $($cfg.Delay) s, then kill the claude process tree of pid $($chk.Pid) ($($chk.Name)) and remove the flag. Killed: nothing."
            return
        }
        if ($env:KAH_TAIL_NO_CLOSE -and -not $cfg.Worker) {
            Write-CloseLog 'DISABLED' 'KAH_TAIL_NO_CLOSE is set'
            'tail-close: disabled by KAH_TAIL_NO_CLOSE; nothing done.'
            return
        }
        if ($cfg.Worker) {
            Start-Sleep -Seconds $cfg.Delay
            $c2 = Test-TailClosable $runs $sid $true
            $mk = Join-Path (Get-TailDir $runs) (($sid -replace '[\\/:*?"<>|]', '_') + '.closing')
            if (-not $c2.Ok) { Write-CloseLog 'REFUSED-AT-KILL' $c2.Why; Remove-Item -LiteralPath $mk -Force -ErrorAction SilentlyContinue; return }
            Write-CloseLog 'CLOSING' "pid $($c2.Pid) ($($c2.Name)): taskkill /T /F"
            $ErrorActionPreference = 'Continue'
            # Shay 2026-10-15: the tail window must close with the process. Sessions are opened as `powershell -NoExit -Command "claude ..."`,
            # so the -NoExit shell host (the window/tab) outlives a killed claude. Remember that host BEFORE the kill; it is closed after
            # claude is gone, but only if it is a powershell/pwsh with -NoExit and 'claude' in its command line, owns no other claude process
            # and is neither this worker nor one of its ancestors (so a coordinator window is never touched).
            $hostPid = 0
            try {
                $cp = Get-CimInstance Win32_Process -Filter "ProcessId=$($c2.Pid)" -ErrorAction Stop
                $hp = Get-CimInstance Win32_Process -Filter "ProcessId=$($cp.ParentProcessId)" -ErrorAction Stop
                if ($hp -and $hp.Name -match '^(powershell|pwsh)\.exe$' -and $hp.CommandLine -match '(?i)-NoExit' -and $hp.CommandLine -match '(?i)claude') {
                    $others = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($hp.ProcessId)" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $c2.Pid -and $_.Name -match '(?i)claude|node' })
                    $anc = @(); $q = $PID; for ($k = 0; $k -lt 12 -and $q; $k++) { $anc += $q; $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$q" -ErrorAction SilentlyContinue; $q = if ($pp) { $pp.ParentProcessId } else { 0 } }
                    if ($others.Count -eq 0 -and ($anc -notcontains $hp.ProcessId)) { $hostPid = [int]$hp.ProcessId }
                }
            } catch { Write-CloseLog 'HOST-LOOKUP-FAILED' $_.Exception.Message }
            & taskkill.exe /PID $c2.Pid /T /F 2>&1 | Out-Null
            $ErrorActionPreference = 'Stop'
            $gone = $false
            for ($i = 0; $i -lt 25; $i++) { if (-not (Get-Process -Id $c2.Pid -ErrorAction SilentlyContinue)) { $gone = $true; break }; Start-Sleep -Milliseconds 200 }
            if ($gone -and $hostPid -gt 0) {
                $ErrorActionPreference = 'Continue'
                & taskkill.exe /PID $hostPid /T /F 2>&1 | Out-Null
                $ErrorActionPreference = 'Stop'
                Write-CloseLog 'HOST-CLOSED' "shell host pid $hostPid (window/tab) closed after claude pid $($c2.Pid)"
            } elseif ($gone) { Write-CloseLog 'HOST-KEPT' 'no safe -NoExit shell host found for this claude process (window stays open)' }
            if ($gone) {
                Remove-Item -LiteralPath (Get-TailFlagPath $runs $sid) -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $mk -Force -ErrorAction SilentlyContinue
                Write-CloseLog 'CLOSED' "pid $($c2.Pid) gone, flag removed"
            } else { Write-CloseLog 'KILL-FAILED' "pid $($c2.Pid) still running; flag kept" }
            return
        }
        # schedule: one closing marker per session (the Stop hook fires every turn)
        $mark = Join-Path (Get-TailDir $runs) (($sid -replace '[\\/:*?"<>|]', '_') + '.closing')
        if ((Test-Path -LiteralPath $mark) -and ((Get-Date) - (Get-Item -LiteralPath $mark).LastWriteTime).TotalSeconds -lt ([math]::Max(60, $cfg.Delay + 40))) {
            'tail-close: a close for this tail is already scheduled.'
            return
        }
        Set-Content -LiteralPath $mark -Value (Get-Date).ToString('o') -Encoding ASCII
        if (-not $cfg.NoRelay) {
            $ErrorActionPreference = 'Continue'
            try {
                $short = if ($sid.Length -gt 8) { $sid.Substring(0, 8) } else { $sid }
                $txt = "TAIL-DONE $sid`ntail $sid finished all agents, closing (pid $($chk.Pid), in $($cfg.Delay) s)."
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cfg.Dir 'tail-relay.ps1') -Agent "tail-$short" -Kind TAILDONE -Summary $txt 2>&1 | ForEach-Object { "$_" }
            } catch { Write-CloseLog 'RELAY-FAILED' $_.Exception.Message; "tail-close: TAIL-DONE relay failed ($($_.Exception.Message)); closing anyway" }
            $ErrorActionPreference = 'Stop'
        }
        # detached worker (WMI parent), so taskkill /T of the claude tree cannot take it down before it removes the flag
        $wa = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($cfg.Self)`" -Session `"$sid`" -Worker -DelaySec $($cfg.Delay) -Source $($cfg.Source) -Runs `"$runs`""
        $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }   # SW_HIDE: the worker must never open a visible window (Shay 2026-10-15)
        $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "powershell.exe $wa"; ProcessStartupInformation = $si } -ErrorAction Stop
        if ($r.ReturnValue -ne 0) { throw "worker start failed (WMI return $($r.ReturnValue))" }
        Write-CloseLog 'SCHEDULED' "pid $($chk.Pid) ($($chk.Name)) closes in $($cfg.Delay) s (worker pid $($r.ProcessId))"
        "tail-close: tail $sid closes in $($cfg.Delay) s (pid $($chk.Pid), $($chk.Name)); log $log"
    } catch {
        Write-CloseLog 'ERROR' $_.Exception.Message
        "tail-close: ERROR, nothing killed: $($_.Exception.Message)"
    }
} $cfg
