# Selftest for PI-07: session-start.ps1 -Brief output budget (session-start-budget.ps1).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'session-start-budget.ps1')
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') { if ($ok) { $script:pass++; "PASS $name" } else { $script:fail++; "FAIL $name $detail" } }

# 1. synthetic overflow: every section far over its cap; must-keep lines buried in the middle and at the end
$must = @(
    'WAKER STATUS: NOT running (start: x)',
    'ORPHANED (parent session gone?) agentA: RUNNING, last update 99 min ago. Respawn it.',
    'NO SUCCESSOR agentB: STOPPED-CONTEXT 50 min ago. Respawn fresh agent agentB2',
    'DEAD agentC (p/wp, wp running): no status file -> respawn agentC2',
    'OWNED-BY-LIVE-TAIL agentD (p/wp, wp running) tail t1, acked=NO; leave it running',
    'TAIL t1 LIVE (pid 1): owns agentD',
    'PROCESS IDEAS FOR SHAY (ask once, together, in your first summary; do not apply any):',
    '  PI-99 [confirmed] a test idea | evidence: x',
    'Next: respawn every agent whose status is not DONE')
$junk = { param($n, $p) 1..$n | ForEach-Object { "$p line $_ " + ('x' * 400) } }
$lines = @()
$lines += $must[0]
$lines += '=== PROGRAM LEDGER p ==='; $lines += (& $junk 80 'ledger')
$lines += $must[6]; $lines += $must[7]
$lines += '=== tail sessions (x) ==='; $lines += $must[5]
$lines += '=== ledger agents: owned (x) ==='; $lines += $must[4]; $lines += $must[3]
$lines += '=== testing/HANDOFF.md: Right now ==='; $lines += (& $junk 200 'handoff')
$lines += '=== agents (C:\KenshiTestRuns\agents) ==='; $lines += (& $junk 300 'agent')
$lines += '=== agent health (x) ==='; $lines += (& $junk 40 'health'); $lines += $must[1]; $lines += $must[2]
$lines += '=== agent roll call (x) ==='; $lines += (& $junk 100 'roll')
$lines += '=== in flight ==='; $lines += (& $junk 100 'flight')
$lines += '=== stale test leftovers ==='; $lines += (& $junk 50 'stale')
$lines += $must[8]
$inBytes = [Text.Encoding]::UTF8.GetByteCount($lines -join "`n")
$out = @(Limit-BriefOutput -Lines $lines -MaxBytes 12288)
$outBytes = [Text.Encoding]::UTF8.GetByteCount($out -join "`n")
Check "synthetic input is big ($inBytes B)" ($inBytes -gt 100000)
Check "synthetic output within 12288 B (got $outBytes)" ($outBytes -le 12288) "$outBytes"
foreach ($m in $must) { Check "must-keep survives: $($m.Substring(0, [Math]::Min(40, $m.Length)))" (@($out | Where-Object { $_ -ceq $m }).Count -eq 1) }
Check 'overflow note present' (@($out | Where-Object { $_ -match '^\s+\(\d+ more; run without -Brief\)$' }).Count -ge 3)
Check 'WAKER STATUS stays first' ($out[0] -ceq $must[0])
# lowercase "orphaned"/"dead" in ordinary text must NOT be treated as must-keep (agent status text says "orphaned: parent ...")
$o2 = @(Limit-BriefOutput -Lines (@('=== agents (C:\x) ===') + (1..60 | ForEach-Object { "agent$_ STOPPED 5m: orphaned: parent ended | dead end" })) -MaxBytes 12288)
Check 'lowercase orphaned is capped, not kept' ($o2.Count -lt 25) "$($o2.Count)"
# must-keep alone over budget: still all present
$many = @('=== tail sessions (x) ===') + (1..60 | ForEach-Object { "TAIL t$_ LIVE " + ('y' * 300) })
$o3 = @(Limit-BriefOutput -Lines $many -MaxBytes 12288)
Check 'must-keep never dropped even over budget' (@($o3 | Where-Object { $_ -cmatch '^TAIL ' }).Count -eq 60)

# 2. live workspace: real size and the structural lines
$live = @(& (Join-Path $PSScriptRoot 'session-start.ps1') -Brief *>&1 | ForEach-Object { "$_" })
$lb = [Text.Encoding]::UTF8.GetByteCount($live -join "`n")
Check "live -Brief output <= 13000 B (got $lb)" ($lb -le 13000) "$lb"
Check 'live: first line is WAKER STATUS' ($live[0] -like 'WAKER STATUS:*')
Check 'live: Next: line present' (@($live | Where-Object { $_ -like 'Next:*' }).Count -eq 1)
Check 'live: agent health section present' (@($live | Where-Object { $_ -like '=== agent health*' }).Count -eq 1)
"selftest: $pass passed, $fail failed (live output $lb B)"
if ($fail) { exit 1 }
