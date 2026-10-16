# agent-session-hooks-selftest.ps1: checks the hook behaviour for INDEPENDENT agent sessions (env KAH_AGENT_NAME, Shay 2026-10-15)
# against the coordinator behaviour, by feeding hook JSON to the real scripts with a temp runs dir (KAH_RUNS_DIR / KCS_RUNS).
#   1. kenshi-waker-guard.ps1 stop : agent may end only when its own status is DONE/FAILED/STOPPED-CONTEXT; in-flight markers,
#      game.lock, another heartbeat owner and handoff.ready do not matter for an agent.
#   2. kenshi-waker-guard.ps1 pre  : sleep > 120 s still denied for an agent.
#   3. coord-heartbeat.ps1 (hook mode and -Beat): an agent session never writes/claims the heartbeat; without the env it does.
#   4. context-meter (~/.claude/hooks/context-meter.ps1 + .claude/context-meter.project.ps1): agent text vs coordinator text.
# No real runs-dir file is touched. Usage: powershell -NoProfile -File tools\automation\agent-session-hooks-selftest.ps1  (exit 0 = PASS)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$guard = Join-Path $PSScriptRoot 'hooks\kenshi-waker-guard.ps1'
$hbs = Join-Path $PSScriptRoot 'coord-heartbeat.ps1'
$meter = Join-Path $env:USERPROFILE '.claude\hooks\context-meter.ps1'
$tmp = Join-Path $env:TEMP ('agsess-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'agents'), (Join-Path $tmp 'inflight') -Force | Out-Null
$script:fail = 0
function Check([bool]$ok, [string]$name, [string]$detail = '') {
    if ($ok) { Write-Output "RESULT agent-hooks $name PASS" } else { Write-Output "RESULT agent-hooks $name FAIL $detail"; $script:fail++ }
}
function Run-Hook([string]$script, [string[]]$hookArgs, [string]$json) {
    $ErrorActionPreference = 'Continue'
    $out = $json | & powershell -NoProfile -ExecutionPolicy Bypass -File $script @hookArgs 2>&1
    [pscustomobject]@{ Exit = $LASTEXITCODE; Out = (($out | ForEach-Object { "$_" }) -join "`n").Trim() }
}
function Set-Status([string]$name, [string]$state) {
    [IO.File]::WriteAllText((Join-Path $tmp "agents\$name.status"), "$name | $state | 2026-10-15 12:00`r`ntask: t`r`n", (New-Object Text.UTF8Encoding($true)))
}
$cwd = ($root -replace '\\', '/')
function Stop-Json([string]$sid) { '{"session_id":"' + $sid + '","cwd":"' + $cwd + '","hook_event_name":"Stop","stop_hook_active":false}' }
try {
    $env:KAH_RUNS_DIR = $tmp; $env:KCS_RUNS = $tmp
    # in-flight noise that would block a coordinator: fresh marker, lock, a heartbeat owned by a different session
    New-Item -ItemType File -Path (Join-Path $tmp 'inflight\somebatch') -Force | Out-Null
    Set-Content (Join-Path $tmp 'game.lock') 'someone'
    [IO.File]::WriteAllText((Join-Path $tmp 'coordinator.heartbeat'), ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() + " coord-session-X 2026-10-15 12:00:00`r`n"))

    # --- 1. Stop hook as an agent ---
    $env:KAH_AGENT_NAME = 'selftest-agent'
    $r = Run-Hook $guard @('stop') (Stop-Json 'agent-sess-1')
    Check ($r.Out -match '"decision":"block"' -and $r.Out -match 'agent-status\.ps1 selftest-agent') 'stop-agent-no-status-blocks' $r.Out
    Set-Status 'selftest-agent' 'RUNNING'
    $r = Run-Hook $guard @('stop') (Stop-Json 'agent-sess-1')
    Check ($r.Out -match '"decision":"block"' -and $r.Out -match 'RUNNING') 'stop-agent-RUNNING-blocks' $r.Out
    $r = Run-Hook $guard @('stop') (Stop-Json 'coord-session-X')
    Check ($r.Out -match '"decision":"block"') 'stop-agent-RUNNING-blocks-any-session-id' $r.Out
    foreach ($s in 'DONE', 'FAILED', 'STOPPED-CONTEXT') {
        Set-Status 'selftest-agent' $s
        $r = Run-Hook $guard @('stop') (Stop-Json 'agent-sess-1')
        Check ($r.Exit -eq 0 -and -not $r.Out) "stop-agent-$s-allows-despite-inflight-lock-marker" $r.Out
    }
    # the agent rules ignore other agents' open statuses (a coordinator would be blocked by this one)
    Set-Status 'other-open' 'STOPPED-CONTEXT'
    $r = Run-Hook $guard @('stop') (Stop-Json 'agent-sess-1')
    Check ($r.Exit -eq 0 -and -not $r.Out) 'stop-agent-ignores-other-agents' $r.Out
    Remove-Item (Join-Path $tmp 'agents\other-open.status') -Force
    # another agent's DONE does not release this agent
    Set-Status 'selftest-agent' 'RUNNING'; Set-Status 'someone-else' 'DONE'
    $r = Run-Hook $guard @('stop') (Stop-Json 'agent-sess-2')
    Check ($r.Out -match '"decision":"block"') 'stop-agent-own-status-only' $r.Out
    # stop_hook_active never loops
    $r = Run-Hook $guard @('stop') ((Stop-Json 'agent-sess-1') -replace '"stop_hook_active":false', '"stop_hook_active":true')
    Check ($r.Exit -eq 0 -and -not $r.Out) 'stop-agent-hook-active-allows' $r.Out

    # --- coordinator (no env): the heartbeat-owner exemption of df3daf5 still works for a non-owner session ---
    Remove-Item Env:KAH_AGENT_NAME
    $r = Run-Hook $guard @('stop') (Stop-Json 'retired-session-Y')
    Check ($r.Exit -eq 0 -and -not $r.Out) 'stop-coordinator-nonowner-exempt-kept' $r.Out

    # --- 2. Pre hook still applies to agents ---
    $env:KAH_AGENT_NAME = 'selftest-agent'
    $preJson = { param($c) '{"session_id":"agent-sess-1","cwd":"' + $cwd + '","tool_name":"Bash","tool_input":{"command":"' + $c + '"}}' }
    $r = Run-Hook $guard @('pre') (& $preJson 'sleep 300')
    Check ($r.Exit -eq 2) 'pre-agent-sleep300-denied' "exit=$($r.Exit) $($r.Out)"
    $r = Run-Hook $guard @('pre') (& $preJson 'sleep 60')
    Check ($r.Exit -eq 0) 'pre-agent-sleep60-allowed' "exit=$($r.Exit) $($r.Out)"
    Remove-Item Env:KAH_AGENT_NAME

    # --- 3. heartbeat ---
    $hb = Join-Path $tmp 'coordinator.heartbeat'
    Remove-Item $hb -Force
    $hookJson = '{"session_id":"agent-sess-1","tool_name":"Bash","tool_input":{"command":"echo hi"},"hook_event_name":"PostToolUse"}'
    $env:KAH_AGENT_NAME = 'selftest-agent'
    [void](Run-Hook $hbs @() $hookJson)
    Check (-not (Test-Path $hb)) 'heartbeat-agent-hook-writes-nothing'
    [void](Run-Hook $hbs @('-Beat') '')
    Check (-not (Test-Path $hb)) 'heartbeat-agent-Beat-writes-nothing'
    [void](Run-Hook $hbs @() ('{"session_id":"agent-sess-1","tool_name":"Bash","tool_input":{"command":"powershell -File tools/automation/session-start.ps1"},"hook_event_name":"PostToolUse"}'))
    Check (-not (Test-Path $hb)) 'heartbeat-agent-session-start-does-not-claim'
    Remove-Item Env:KAH_AGENT_NAME
    [void](Run-Hook $hbs @() $hookJson)
    Check ((Test-Path $hb) -and ((Get-Content $hb -Raw) -match 'agent-sess-1')) 'heartbeat-coordinator-hook-still-claims'
    $before = (Get-Content $hb -Raw)
    $env:KAH_AGENT_NAME = 'selftest-agent'
    [void](Run-Hook $hbs @() ($hookJson -replace 'agent-sess-1', 'agent-sess-1'))
    Check ((Get-Content $hb -Raw) -eq $before) 'heartbeat-agent-does-not-refresh-existing'
    Remove-Item Env:KAH_AGENT_NAME

    # --- 4. context meter text ---
    if (Test-Path $meter) {
        $tr = Join-Path $tmp 'transcript.jsonl'
        $line = '{"message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":210000}}}'
        [IO.File]::WriteAllText($tr, $line + "`n")
        $mj = '{"session_id":"s","transcript_path":"' + ($tr -replace '\\', '/') + '","cwd":"' + $cwd + '","hook_event_name":"PostToolUse"}'
        $env:CLAUDE_PROJECT_DIR = $root
        $env:KAH_AGENT_NAME = 'selftest-agent'
        $r = Run-Hook $meter @() $mj
        Check ($r.Out -match 'independent agent session' -and $r.Out -match 'agent-status\.ps1 selftest-agent STOPPED-CONTEXT' -and $r.Out -match 'inbox\\\\coordinator' -and $r.Out -match 'Do NOT open a new session') 'meter-agent-text' $r.Out
        Check ($r.Out -notmatch 'SendMessage' -and $r.Out -notmatch ' handoff \\"C:') 'meter-agent-no-handoff-command' $r.Out
        Remove-Item Env:KAH_AGENT_NAME
        # coordinator handoff text appears at the overlap-handoff threshold (300k since the tail handoff, 2026-10-15), not at 200k
        [IO.File]::WriteAllText($tr, ($line -replace '210000', '310000') + "`n")
        $r = Run-Hook $meter @() $mj
        Check ($r.Out -match 'handoff-ready\.ps1' -and $r.Out -match 'OVERLAP HANDOFF' -and $r.Out -match 'tail-mode\.ps1' -and $r.Out -notmatch 'selftest-agent') 'meter-coordinator-text' $r.Out
        [IO.File]::WriteAllText($tr, $line + "`n")
        # warn tier for an agent (175k)
        [IO.File]::WriteAllText($tr, ($line -replace '210000', '175000') + "`n")
        $env:KAH_AGENT_NAME = 'selftest-agent'
        $r = Run-Hook $meter @() $mj
        Check ($r.Out -match 'agent .{1,8}selftest-agent' -and $r.Out -match 'checkpoint now') 'meter-agent-warn-tier' $r.Out
        Remove-Item Env:KAH_AGENT_NAME
        $r = Run-Hook $meter @() $mj
        Check (-not $r.Out) 'meter-coordinator-silent-below-200k' $r.Out
    } else { Write-Output 'RESULT agent-hooks meter SKIP no global context-meter.ps1' }
} finally {
    foreach ($v in 'KAH_AGENT_NAME', 'KAH_RUNS_DIR', 'KCS_RUNS', 'CLAUDE_PROJECT_DIR') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { Write-Output "SELFTEST FAILED ($($script:fail))"; exit 1 } else { Write-Output 'SELFTEST OK'; exit 0 }
