# session-start.ps1: the fixed first step of every coordinator session (CLAUDE.md "Start here").
# Prints, compactly: the handoff marker (then archives it), testing/HANDOFF.md "Right now", each agent status
# file (C:\KenshiTestRuns\agents\<name>.status), inflight markers (+ the batch out dir a marker names: DONE/SUMMARY),
# game lock and Kenshi state.
param([switch]$Brief, [switch]$AgentsOnly)  # -AgentsOnly: stop after the agent roll call (selftest). -Brief (Shay 2026-10-15): ~10x smaller output; agents not DONE and < 6 h old only, long lines cut, no rig-runner/stale sections
$ws = 'C:\KenshiModding'
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }

# First line (Shay 2026-10-15): is a background event wait running? A session without one is unreachable for peer messages and stalls.
$ew = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and [string]$_.CommandLine -match 'event-wait\.sh' -and [string]$_.CommandLine -notmatch '\b(grep|rg|git|sed|python3?|cat|head|tail)\b|bash -n' -and $_.Name -match '^(wsl|bash|sh)\.exe$' } | Select-Object -First 2)
if ($ew.Count) { "WAKER STATUS: running (event-wait.sh, pid $($ew[0].ProcessId))" }
else { 'WAKER STATUS: NOT running (start: Bash run_in_background  MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash /mnt/c/KenshiModding/tools/automation/event-wait.sh [--batch /mnt/c/<out-dir>]; restart it every time it wakes you)' }

# Program ledgers (Shay 2026-10-15): unfinished work packages of every program (C:\KenshiTestRuns\programs\*.json, tools\automation\program-ledger.ps1); fail-open.
try { & (Join-Path $ws 'tools\automation\program-ledger.ps1') brief } catch { }

# Process ideas (Shay 2026-10-15; docs/PROCESS_IDEAS.md, tools/automation/process-ideas.ps1): open entries, short, to ask Shay ONCE in the first summary. Never apply them. Fail-open.
try {
    $piLines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'process-ideas.ps1') list 2>&1 | ForEach-Object { "$_" })
    if ($piLines.Count -and "$($piLines[0])" -ne 'none') {
        'PROCESS IDEAS FOR SHAY (ask once, together, in your first summary; do not apply any):'
        $piLines | ForEach-Object { "  $_" }
        '  (after asking: process-ideas.ps1 asked <id>..; Shay''s answer: process-ideas.ps1 answer <id> no|yes; unanswered ideas are re-reviewed and asked again at the next handoff)'
    }
} catch { "process ideas check failed open: $($_.Exception.Message)" }

# Tail sessions + COLD START (docs/TAIL_HANDOFF_CONTRACT.md sections 5-7; Shay 2026-10-15). A tail session is an old coordinator kept alive
# (flag C:\KenshiTestRuns\tail\<session>.flag) so its in-session subagents keep running: those agents are OWNED by it, never respawn them.
# A tail whose process is gone = its agents are DEAD. Every other ledger agent that is not alive is DEAD too (PC shutdown): respawn from its checkpoint.
$tailOwned = @{}   # agent -> tail session id (LIVE tails only; used to drop respawn lines for them below)
try {
    $recs = @()
    try { $recs = @((& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ws 'tools\automation\program-ledger.ps1') records | Out-String) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
    $tailDir = Join-Path $runs 'tail'
    $tails = @{}
    foreach ($tf in @(Get-ChildItem -LiteralPath $tailDir -Filter '*.flag' -File -ErrorAction SilentlyContinue)) {
        try { $tj = Get-Content -LiteralPath $tf.FullName -Raw | ConvertFrom-Json } catch { $tails[$tf.BaseName] = [pscustomobject]@{ alive = $false; pid = 0; agents = @(); created = ''; why = 'unreadable flag' }; continue }
        $tp = $null; $tpid = 0; if ($tj.pid) { $tpid = [int]$tj.pid; $tp = Get-Process -Id $tpid -ErrorAction SilentlyContinue }
        $alive = [bool]$tp
        if ($tp -and $tj.created) { try { if ($tp.StartTime.ToUniversalTime() -gt ([datetime]$tj.created).ToUniversalTime().AddMinutes(1)) { $alive = $false } } catch { } }   # pid recycled by a newer process
        $tails[$tf.BaseName] = [pscustomobject]@{ alive = $alive; pid = $tpid; agents = @($tj.agents); created = "$($tj.created)"; why = $(if ($alive) { '' } else { "process $tpid gone" }) }
    }
    if ($tails.Count) {
        '=== tail sessions (C:\KenshiTestRuns\tail\*.flag: old coordinators kept alive for their in-session agents; they relay results to this session) ==='
        foreach ($tn in ($tails.Keys | Sort-Object)) {
            $t = $tails[$tn]
            $names = @($t.agents | Where-Object { $_ })
            if ($t.alive) { "TAIL $tn LIVE (pid $($t.pid), since $($t.created)): owns $(if ($names.Count) { $names -join ', ' } else { '(no agents listed)' }) -- leave them running; ack each relayed result with tail-ack.ps1 -Agent <name>" }
            else { "TAIL $tn DEAD ($($t.why)): its agents are DEAD with it: $(if ($names.Count) { $names -join ', ' } else { '(none listed)' }) -- continue them from their checkpoints (lines below)" }
        }
    }
    foreach ($tn in $tails.Keys) { if ($tails[$tn].alive) { foreach ($x in @($tails[$tn].agents)) { if ($x) { $tailOwned["$x"] = $tn } } } }
    foreach ($r in $recs) { if ("$($r.owner_session)" -like 'tail:*') { $tid = "$($r.owner_session)".Substring(5); if ($tails.ContainsKey($tid) -and $tails[$tid].alive) { $tailOwned["$($r.agent)"] = $tid } } }

    $agDir = Join-Path $runs 'agents'
    function Get-AgentStatusLine([string]$n) {
        $sf = Join-Path $agDir "$n.status"
        if (-not (Test-Path -LiteralPath $sf)) { return $null }
        $first = (Get-Content -LiteralPath $sf -TotalCount 1) -split '\|' | ForEach-Object { $_.Trim() }
        return [pscustomobject]@{ state = $(if ($first.Count -ge 2) { $first[1] } else { '' }); age = [int]((Get-Date) - (Get-Item -LiteralPath $sf).LastWriteTime).TotalMinutes }
    }
    function Get-NextAgentName([string]$n) { if ($n -match '^(.*?)(\d+)$') { "$($Matches[1])$([int]$Matches[2] + 1)" } else { "${n}2" } }
    $own = @(); $dead = @()
    foreach ($r in $recs) {
        $wst = "$($r.state)"
        $stat = Get-AgentStatusLine "$($r.agent)"
        $tn = if ("$($r.owner_session)" -like 'tail:*') { "$($r.owner_session)".Substring(5) } else { '' }
        $tailLive = $tn -and $tails.ContainsKey($tn) -and $tails[$tn].alive
        $unacked = $tn -and -not $r.acked_by_new_coordinator
        if ($tailLive -and ($wst -ne 'done' -or $unacked)) {
            $own += "OWNED-BY-LIVE-TAIL $($r.agent) ($($r.program)/$($r.wp), wp $wst, status $(if ($stat) { "$($stat.state) $($stat.age) min ago" } else { 'none' })) tail $tn, acked=$(if ($r.acked_by_new_coordinator) { 'yes' } else { 'NO' })$(if ($r.result_file) { ', result ' + $r.result_file }); leave it running, wait for its relay.$(if ($r.routing_note) { ' routing note: ' + $r.routing_note })"
            continue
        }
        if ($wst -notin 'running', 'stopped') { continue }
        if ($stat -and $stat.state -eq 'DONE') { continue }
        if ($stat -and $stat.state -eq 'RUNNING' -and $stat.age -lt 30 -and -not ($tn -and -not $tailLive)) { continue }   # fresh heartbeat: alive
        $why = if ($tn -and -not $tailLive) { "owner tail $tn is gone" } elseif ($stat) { "status $($stat.state) $($stat.age) min ago (not alive)" } else { 'no status file' }
        $nx = Get-NextAgentName "$($r.agent)"
        $ck = if ($stat -or (Test-Path -LiteralPath (Join-Path $agDir "$($r.agent).handoff.md"))) { "agents\$($r.agent).status / agents\$($r.agent).handoff.md" } else { 'ledger outputs/handoff' }
        $dead += "DEAD $($r.agent) ($($r.program)/$($r.wp), wp $wst): $why -> respawn a FRESH agent $nx (Agent tool, same work dir) from its checkpoint $ck$(if ($r.routing_note) { ". Routing note: $($r.routing_note)" } else { '. (no routing note in the ledger)' })"
    }
    if ($own.Count -or $dead.Count) {
        '=== ledger agents: owned by a live tail / DEAD (cold start: respawn from checkpoints; fresh names agent -> agent2) ==='
        $own | ForEach-Object { if ($Brief -and $_.Length -gt 600) { $_.Substring(0, 600) + '...' } else { $_ } }
        $dead | ForEach-Object { if ($Brief -and $_.Length -gt 700) { $_.Substring(0, 700) + '...' } else { $_ } }
    }
} catch { "tail/cold-start check failed open: $($_.Exception.Message)" }

$mk = Join-Path $runs 'handoff.ready'
if (Test-Path -LiteralPath $mk) {
    '=== handoff.ready ==='
    Get-Content -LiteralPath $mk | Select-Object -First 6
    $done = Join-Path $runs 'handoff.done'
    New-Item -ItemType Directory -Force -Path $done | Out-Null
    Move-Item -LiteralPath $mk -Destination (Join-Path $done ("handoff-{0}.ready" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
    Get-ChildItem -LiteralPath $done -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force
} else {
    '=== no handoff.ready (previous session ended without a context-limit handoff) ==='
}

'=== testing/HANDOFF.md: Right now ==='
$h = Get-Content -LiteralPath (Join-Path $ws 'testing\HANDOFF.md')
$i = [array]::FindIndex($h, [Predicate[string]]{ param($l) $l -like '## Right now*' })
if ($i -ge 0) {
    $j = $i + 1
    while ($j -lt $h.Count -and $h[$j] -notlike '## *') { $j++ }
    $h[$i..($j - 1)] | Select-Object -First $(if ($Brief) { 12 } else { 40 }) | ForEach-Object { if ($Brief -and $_.Length -gt 700) { $_.Substring(0,700) + ' ...[cut: read testing/HANDOFF.md]' } else { $_ } }
    if (-not $Brief -and $j - $i -gt 40) { "... ($($j - $i - 40) more lines: read testing/HANDOFF.md lines $($i + 41)-$j)" }
} else { $h | Select-Object -First 25 }

'=== agents (C:\KenshiTestRuns\agents) ==='
$ag = @(Get-ChildItem -LiteralPath (Join-Path $runs 'agents') -Filter '*.status' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if (-not $ag.Count) { 'none' }
if ($Brief) { $ag = @($ag | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) -and ((Get-Content -LiteralPath $_.FullName -TotalCount 2) -join ' ') -notmatch '\| DONE \|' }) }
foreach ($a in $ag) {
    "--- $($a.BaseName) (updated $(Get-Date $a.LastWriteTime -Format 'MM-dd HH:mm'))"
    Get-Content -LiteralPath $a.FullName | Select-Object -First $(if ($Brief) { 5 } else { 12 }) | ForEach-Object { if ($Brief -and $_.Length -gt 220) { $_.Substring(0,220) + '...' } else { $_ } }
}

'=== agent health (agent-guard-lib.ps1: RUNNING > 30 min = orphaned; stopped/failed agents without a successor; respawn todos) ==='
try {
    . (Join-Path $PSScriptRoot 'agent-guard-lib.ps1')
    Remove-SupersededTodos
    $ah = @(Get-AgentHealthLines)
    $ah = @($ah | Where-Object { $l = $_; -not ($tailOwned.Keys | Where-Object { $l -match ('(?<![\w.-])' + [regex]::Escape($_) + '(?![\w.-])') }) })   # agents owned by a LIVE tail are not respawned
    if ($Brief) { $ah = @($ah | ForEach-Object { if ($_.Length -gt 400) { $_.Substring(0,400) + '...' } else { $_ } }) }
    if ($ah.Count) { $ah | ForEach-Object { $_ } } else { 'every agent is DONE, RUNNING (fresh) or has a successor: nothing to respawn' }
    $rt = @(Get-ChildItem -LiteralPath (Join-Path $runs 'respawn') -Filter '*.todo' -File -ErrorAction SilentlyContinue | ForEach-Object BaseName)
    $rt = @($rt | Where-Object { -not $tailOwned.ContainsKey($_) })
    if ($rt.Count) { "respawn todos (C:\KenshiTestRuns\respawn\): $($rt -join ', ')" }
} catch { "agent health check failed open: $($_.Exception.Message)" }
'=== agent roll call (agent-rollcall.ps1: kind INDEPENDENT = hidden agent-host job with a session.json, survives this coordinator; INPROC = subagent of a session, DIES when its session ends) + agent-host daemon ==='
try {
    $rcLines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agent-rollcall.ps1'))
    $rcLines | ForEach-Object { $_ }
    if (@($rcLines | Where-Object { $_ -match 'kind=INPROC' }).Count) { 'WARNING: INPROC agents die when this coordinator ends: finish them first or respawn them as independent jobs (spawn-wp-session.ps1) before a handoff.' }
    if (@($rcLines | Where-Object { $_ -match 'kind=INDEPENDENT proc=DEAD' }).Count) { 'WARNING: INDEPENDENT agent(s) with proc=DEAD: the monitor marks them FAILED; respawn a fresh successor (agent health above).' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agent-host-ensure.ps1') $(if ($env:KAH_RUNS_DIR) { '-DryRun' })
} catch { "roll call failed open: $($_.Exception.Message)" }
if ($AgentsOnly) { return }
if (-not $Brief) {
'=== rig runners (rig-runner.ps1: one daemon per rig runs the queue\<rig>\ and queue\any\ list files; ALERT on idle/stuck) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'rig-runner.ps1') -Ensure
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'rig-runner.ps1') -Status
'=== paired runner supervisor (45 s paired progress + heartbeat monitor; exact-hash recovery pin required) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'paired-runner-supervisor.ps1') -Ensure
'=== GPU telemetry (gpulog.ps1: 2 s nvidia-smi samples per rig in C:\KenshiTestRuns\gpulog\ for TDR/BSOD evidence) ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gpulog-ensure.ps1') -Rig both
Get-Content (Get-ChildItem 'C:\KenshiTestRuns' -Filter 'ALERT-*.txt' -File -ErrorAction SilentlyContinue).FullName -ErrorAction SilentlyContinue
} else { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'rig-runner.ps1') -Ensure | Out-Null }
'=== in flight ==='
$k = if (Get-Process -Name 'kenshi_x64' -ErrorAction SilentlyContinue) { 'running' } else { 'closed' }
$lock = if (Test-Path -LiteralPath (Join-Path $runs 'game.lock')) { (Get-Content -Raw -LiteralPath (Join-Path $runs 'game.lock')).Trim() } else { 'free' }
"kenshi: $k | game.lock: $lock"
# Ready queue per rig (Shay 2026-10-10): the next batch lists for each rig, queued before the current one ends
foreach ($rig in '5090', '4080', 'any', 'running') {
    $l = @(Get-ChildItem -LiteralPath (Join-Path $runs "queue\$rig") -Filter '*.list' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
    "queue\${rig}: $(if ($l.Count) { $l -join ', ' } else { 'empty' })"
}
foreach ($rig in '5090', '4080') {
    $q = Join-Path $runs "queue\$rig.next"
    if (Test-Path -LiteralPath $q) { "queue\$rig.next (old note file, since $(Get-Date (Get-Item -LiteralPath $q).LastWriteTime -Format 'MM-dd HH:mm')): $(((Get-Content -LiteralPath $q -TotalCount 3) -join ' / '))" }
}
$dn = @(Get-ChildItem -LiteralPath (Join-Path $runs 'queue\done'), (Join-Path $runs 'queue\failed') -Filter '*.result' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
foreach ($d in $dn) { "result $($d.Name): $(Get-Content -LiteralPath $d.FullName -TotalCount 1)" }
$inf = @(Get-ChildItem -LiteralPath (Join-Path $runs 'inflight') -File -ErrorAction SilentlyContinue)
if (-not $inf.Count) { 'inflight markers: none' }
foreach ($m in $inf) {
    $c = (Get-Content -Raw -LiteralPath $m.FullName -ErrorAction SilentlyContinue)
    $c = if ($c) { $c.Trim() } else { '' }
    "marker $($m.Name) (since $(Get-Date $m.LastWriteTime -Format 'MM-dd HH:mm')) $c"
    # A marker may hold a batch out dir (WSL /mnt/c/... or C:\...): report DONE + SUMMARY.txt
    $d = $c -replace '^/mnt/([a-z])/', '$1:/'
    if ($d -and (Test-Path -LiteralPath $d -PathType Container -ErrorAction SilentlyContinue)) {
        $s = Join-Path $d 'SUMMARY.txt'
        if (Test-Path -LiteralPath (Join-Path $d 'DONE')) { "  DONE; SUMMARY.txt:"; Get-Content -LiteralPath $s -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { "  $_" } }
        else { "  still running (no DONE): start a waker on it" }
    }
}
'=== stale test leftovers (testruns-sweep.ps1; delete or -Keep <path> "<reason>") ==='
$sw = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'testruns-sweep.ps1') 2>$null)
$sw | Select-Object -Last 1
$sw | Where-Object { $_ -like 'STALE*' } | Select-Object -First 20
'=== WSL services (cache-trim is (re)started here; STOBE server must be off for non-STOBE work) ==='
# speed-scout 2026-10-11: after the 13:31 BSOD reboot the WSL start left cache-trim off (its start line sat after
# start_env's shutdown 'read'; vmmem kept ~6 GB of page cache) and the STOBE server ON during FP work (LLM credits)
$wslq = 'bash /mnt/c/KenshiModding/tools/automation/wsl-cache-trim.sh start | tail -1; bash /mnt/c/KenshiModding/tools/automation/stobe-server.sh status 2>&1 | tail -2'
@(& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c $wslq 2>&1) | ForEach-Object { "  $_" }
$rv = Join-Path $runs 'review-verdicts.tsv'
if (Test-Path -LiteralPath $rv) { '=== newest review verdicts ==='; Get-Content -LiteralPath $rv -Tail 8 }
''
'Next: respawn every agent whose status is not DONE (except OWNED-BY-LIVE-TAIL ones, which keep running) as a FRESH agent pointed at its status file; start a <=120 s waker if anything is in flight; continue from HANDOFF.md.'
