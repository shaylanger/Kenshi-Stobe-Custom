# coord-chores-selftest.ps1 - selftest for coord-chores.ps1 (rules in coord-chores.rules.json, fixtures in coord-chores-fixtures\).
# Everything runs against a temp Runs dir (never C:\KenshiTestRuns, never the live alert ledger / repo / waker). Exit 0 = all pass.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\coord-chores-selftest.ps1
param([switch]$Keep)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$fx = Join-Path $here 'coord-chores-fixtures'
$cc = Join-Path $here 'coord-chores.ps1'
$u8 = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $env:TEMP ('cc-selftest-' + $PID)
if (Test-Path -LiteralPath $tmp) { Remove-Item -Recurse -Force -LiteralPath $tmp }
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name $detail" }
}
function New-Runs([string]$tag) {
    $r = Join-Path $tmp $tag
    foreach ($d in 'agents', 'setupfail', 'alerts\open', 'alerts\closed', 'alerts\acked', 'coordinator-digest') { New-Item -ItemType Directory -Force -Path (Join-Path $r $d) | Out-Null }
    $r
}
function Put-Status([string]$runs, [string]$name, [string]$state, [string]$task = 'a task', [string]$latest = 'L', [string]$outputs = 'O', [string]$next = 'N') {
    $txt = "$name | $state | 2026-10-16 21:00:00`ntask: $task`nlatest: $latest`noutputs: $outputs`nnext: $next`n"
    [IO.File]::WriteAllText((Join-Path (Join-Path $runs 'agents') ($name + '.status')), $txt, (New-Object System.Text.UTF8Encoding($true)))
}
function Put-Alert([string]$runs, [string]$kind, [string]$subject, [string]$text) {
    $id = ($kind + '-' + $subject).ToLowerInvariant() -replace '[^a-z0-9._-]+', '_'
    $o = [ordered]@{ id = $id; kind = $kind; subject = $subject; text = $text; source = 'selftest'; opened_at = (Get-Date).AddMinutes(-10).ToString('s'); last_seen = (Get-Date).ToString('s') }
    [IO.File]::WriteAllText((Join-Path $runs "alerts\open\$id.json"), ($o | ConvertTo-Json), $u8)
    $id
}
function Run-Stream([string]$runs, [string]$file) {
    $env:KAH_RUNS_DIR = $runs
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc stream -Runs $runs -InputFile $file 2>&1 | ForEach-Object { [string]$_ }
    Remove-Item Env:\KAH_RUNS_DIR -ErrorAction SilentlyContinue
    , @($o)
}

# ======================================================================= 1. rule classification (in-process, library mode)
$r1 = New-Runs 'cls'
Put-Status $r1 'op-done' 'DONE'
Put-Status $r1 'op-run' 'RUNNING'
Put-Status $r1 'succ-run' 'RUNNING'
Put-Status $r1 'agent-a' 'DONE' 'finish A' 'built A' 'C:\x\a.md' 'nothing'
[IO.File]::WriteAllText((Join-Path $r1 'setupfail\02-bx.json'), '{"row":"02-bx","owner":"op-run","state":"planned"}', $u8)
[IO.File]::WriteAllText((Join-Path $r1 'setupfail\03-bx.json'), '{"row":"03-bx","owner":"-","state":"open"}', $u8)
[IO.File]::WriteAllText((Join-Path $r1 'lanes.held'), "5090-i7 # held by test`n", $u8)
$env:KAH_RUNS_DIR = $r1
. $cc -LibOnly -Runs $r1
function Cl([string]$t) { (Classify-Item $t) }
function IsAuto([string]$t, [string]$rule) { $c = Cl $t; ($c.Class -eq 'AUTO' -and $c.Rule -eq $rule) }
function IsJudg([string]$t) { $c = Cl $t; ($c.Class -eq 'JUDGMENT') }

Check 'rule done-status' (IsAuto 'DONE: STATUS agent-a DONE: task: finish A' 'done-status')
Check 'rule done-relay' (IsAuto 'DONE: INBOX 2026.msg: TAIL-RELAY imm26-x DONE 2026-10-16T20:22:16 report: C:\x' 'done-relay')
Check 'rule done-inbox' (IsAuto 'DONE: INBOX 2026.msg: imm26-x DONE: task finished' 'done-inbox')
Check 'rule dup' (IsAuto 'DUP: 2026.msg: TAIL-RELAY imm26-x DONE x' 'dup')
Check 'rule setupfail-ready' (IsAuto 'SETUP-FAIL-READY: 14-d ready' 'setupfail-ready')
Check 'rule info-done' (IsAuto 'INFO: STATUS agent-a DONE: task: x' 'info-done')
Check 'rule tail-relay-done' (IsAuto 'INBOX 2026.msg: TAIL-RELAY tail-5161 TAILDONE 2026-10-16 report: (none)' 'tail-relay-done')
Check 'rule pilot-other' (IsAuto 'INBOX 2026.msg: PILOT-START 27-a lane=5090-i4' 'pilot-other')
Check 'rule backstop' (IsAuto 'BACKSTOP after 602s' 'backstop')
Check 'rule sweep-clean' (IsAuto 'SWEEP CLEAN' 'sweep-clean')
Check 'rule sweep-marker-noout' (IsAuto 'SWEEP MARKER 4080-imm26 no out dir in marker' 'sweep-marker-noout')
Check 'rule waker-started' (IsAuto 'WAKER started pid=4193066 me=coordinator' 'waker-started')

# conditional rules: SETUP-FAIL / PILOT-ESCALATE / sweep queue / lane alerts
$sf = 'INBOX 2026.msg: SETUP-FAIL 03-bx needs unblock plan: unknown lane=5090-i5 reason: SCENE-BAD x'
$sfo = 'INBOX 2026.msg: SETUP-FAIL 02-bx needs unblock plan: unknown lane=5090-i5 reason: SCENE-BAD x'
$pe = 'INBOX 2026.msg: PILOT-ESCALATE 27-a lane=5090-i4 agent=ab2-haiku-27-a operator_verdict=ESCALATE reason=x'
$q = 'SWEEP QUEUE 5090-i4 empty (no rows)'
Check 'setupfail unowned, no wind-down -> JUDGMENT' (IsJudg $sf)
Check 'setupfail owned by a RUNNING agent -> AUTO' (IsAuto $sfo 'setupfail-owned')
Check 'pilot-escalate, no wind-down -> JUDGMENT' (IsJudg $pe)
Check 'sweep queue empty, no wind-down -> JUDGMENT' (IsJudg $q)
$laneIdle = 'LANE IDLE 5090-i3 6.7m operator=op-run (newest activity: evidence x) -> ask the operator what it is doing'
$laneNoOp = 'LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-done,op-x (rows pending)'
Check 'lane idle, no condition -> JUDGMENT' (IsJudg $laneIdle)
Check 'lane no-operator, no condition -> JUDGMENT' (IsJudg $laneNoOp)
Check 'lane idle on a HELD lane -> AUTO lane-ack-held' (IsAuto 'LANE IDLE 5090-i7 6.0m operator=op-run (newest activity: x) -> ask' 'lane-ack-held')
Check 'lane no-operator on a HELD lane -> AUTO' (IsAuto 'LANE NO-OPERATOR 5090-i7 : no RUNNING operator among op-done' 'lane-ack-held')
# operator DONE + no claimable rows (next-row stubbed)
$script:NextRowFn = { param($lane) "NEXT $lane`: no claimable rows" }
Check 'lane no-operator, operator DONE + no rows -> AUTO' (IsAuto 'LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-done,op-x' 'lane-ack-done-norows')
$script:NextRowFn = { param($lane) "NEXT $lane`: 02-bx" }
Check 'lane no-operator, operator DONE but a row is claimable -> JUDGMENT' (IsJudg 'LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-done,op-x')
$script:NextRowFn = { param($lane) "NEXT $lane`: no claimable rows" }
Check 'lane no-operator, first operator RUNNING (not DONE) -> JUDGMENT' (IsJudg 'LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-run,op-done')
Check 'lane idle never uses doneNoRows (only NO-OPERATOR) -> JUDGMENT' (IsJudg 'LANE IDLE 4080-i3 9.0m operator=op-done (newest activity: x) -> ask')

# successor / rollcall
Check 'has-successor with a RUNNING successor -> AUTO' (IsAuto 'HAS-SUCCESSOR: STATUS agent-b STOPPED-CONTEXT: task: x (successor succ-run)' 'has-successor')
Check 'has-successor whose successor is missing -> JUDGMENT' (IsJudg 'HAS-SUCCESSOR: STATUS agent-b STOPPED-CONTEXT: task: x (successor nobody-at-all)')
Check 'rollcall fresh -> AUTO' (IsAuto 'SWEEP ROLLCALL op-run kind=INPROC proc=n/a status_age=12.2m log_age=0.4m latest=x' 'sweep-rollcall-fresh')
Check 'rollcall stale (60m) -> JUDGMENT' (IsJudg 'SWEEP ROLLCALL op-run kind=INPROC proc=n/a status_age=60.0m log_age=0.4m latest=x')
Check 'rollcall proc=DEAD -> JUDGMENT' (IsJudg 'SWEEP ROLLCALL op-run kind=INPROC proc=DEAD status_age=1.0m log_age=0.4m latest=x')

# wind-down flag
[IO.File]::WriteAllText((Join-Path $r1 'WIND_DOWN.flag'), 'wind-down', $u8)
Check 'wind-down: setupfail -> AUTO' (IsAuto $sf 'setupfail-winddown')
Check 'wind-down: pilot-escalate -> AUTO' (IsAuto $pe 'pilot-escalate-winddown')
Check 'wind-down: empty queue sweep -> AUTO' (IsAuto $q 'sweep-queue-winddown')
Check 'wind-down: lane idle -> AUTO lane-ack-winddown' (IsAuto $laneIdle 'lane-ack-winddown')
Check 'wind-down: lane no-operator -> AUTO lane-ack-winddown' (IsAuto $laneNoOp 'lane-ack-winddown')
Check 'wind-down: lane idle 75m (stall candidate) -> JUDGMENT' (IsJudg 'LANE IDLE 5090-i3 75.0m operator=op-run (newest activity: x) -> ask')
Check 'wind-down: LANE STALLED -> JUDGMENT' (IsJudg 'LANE STALLED 5090-i5 40m (escalated from LANE IDLE) operator=op-run status silent 40m')
Check 'wind-down: idle line mentioning STALLED -> JUDGMENT (guard)' (IsJudg 'LANE IDLE 5090-i3 6.0m operator=op-run (newest activity: STALLED marker) -> ask')
Remove-Item -LiteralPath (Join-Path $r1 'WIND_DOWN.flag') -Force

# hard constraints: never AUTO, whatever the flag / lane hold says
[IO.File]::WriteAllText((Join-Path $r1 'WIND_DOWN.flag'), 'wind-down', $u8)
$hard = Get-Content -LiteralPath (Join-Path $fx 'hard-constraints.txt') -Encoding UTF8
$bad = @()
foreach ($l in $hard) {
    $sp = Split-WakerLine $l
    foreach ($it in $sp.Items) { $c = Classify-Item $it; if ($c.Class -ne 'JUDGMENT' -and $l -notmatch 'IDLE 5090-i3 75m') { $bad += $it } }
}
Check 'hard-constraints fixture: every item is JUDGMENT under wind-down' ($bad.Count -eq 0) ($bad -join ' || ')
foreach ($t in 'AGENT STALL op-run: RUNNING, silent 31 min (status_age=31m)', 'AGENT ORPHANED a: x', 'AGENT DEAD a: x', 'AGENT KILLED a: x', 'LLM-HEALTH FAIL x', 'STATUS a STOPPED-CONTEXT: task: no successor', 'STATUS a FAILED: task: t', 'STALL agent-host: x') {
    Check ("never auto: " + $t.Substring(0, [Math]::Min(40, $t.Length))) (IsJudg $t)
}
Remove-Item -LiteralPath (Join-Path $r1 'WIND_DOWN.flag') -Force

# code-level refusal: even a (mis)configured rule cannot ack a never-ack kind
$rf = Do-LaneAck @{ Text = 'x'; Rule = 'forced'; Ctx = @{ Kind = 'STALLED'; Lane = '5090-i5'; Name = ''; Row = '' } }
Check 'Do-LaneAck refuses a kind outside ackableKinds (stalled)' ($rf -like 'refused*') $rf

# ======================================================================= 2. lane-ack through alert-ack.ps1 (temp ledger)
$r2 = New-Runs 'ack'
Put-Status $r2 'op-run' 'RUNNING'
[IO.File]::WriteAllText((Join-Path $r2 'WIND_DOWN.flag'), 'wind-down', $u8)
$idle = Put-Alert $r2 'lane-idle' '5090-i3' 'LANE IDLE 5090-i3 10m operator=op-run'
$noop = Put-Alert $r2 'lane-no-operator' '4080-i3' 'LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-run'
$stall = Put-Alert $r2 'lane-stalled' '5090-i5' 'LANE STALLED 5090-i5 40m'
$llm = Put-Alert $r2 'llm-health-fail' 'openrouter' 'LLM-HEALTH FAIL openrouter'
$ag = Put-Alert $r2 'agent-stall' 'imm26-x' 'AGENT STALL imm26-x'
$f2 = Join-Path $r2 'in.log'
[IO.File]::WriteAllText($f2, ("2026-10-16T22:00:00 EVENT LANE LANE IDLE 5090-i3 10.0m operator=op-run (newest activity: evidence x) -> ask`n2026-10-16T22:00:01 EVENT LANE LANE NO-OPERATOR 4080-i3 : no RUNNING operator among op-run (rows pending)`n2026-10-16T22:00:02 EVENT LANE LANE STALLED 5090-i5 40m (escalated from LANE IDLE) operator=op-run`n2026-10-16T22:00:03 EVENT AGENT STALL imm26-x: RUNNING, silent 31 min`n"), $u8)
$o2 = Run-Stream $r2 $f2
Check 'stream: idle alert auto-acked (alerts\acked)' (Test-Path -LiteralPath (Join-Path $r2 "alerts\acked\$idle.json"))
Check 'stream: no-operator alert auto-acked' (Test-Path -LiteralPath (Join-Path $r2 "alerts\acked\$noop.json"))
Check 'stream: lane-stalled alert stays OPEN' (Test-Path -LiteralPath (Join-Path $r2 "alerts\open\$stall.json"))
Check 'stream: llm-health alert stays OPEN' (Test-Path -LiteralPath (Join-Path $r2 "alerts\open\$llm.json"))
Check 'stream: agent-stall alert stays OPEN' (Test-Path -LiteralPath (Join-Path $r2 "alerts\open\$ag.json"))
Check 'stream: prints [auto-acked <id>: <rule>] for both acks' ((@($o2) -contains "[auto-acked ${idle}: lane-ack-winddown]") -and (@($o2) -contains "[auto-acked ${noop}: lane-ack-winddown]")) ($o2 -join ' | ')
Check 'stream: LANE STALLED + AGENT STALL lines pass through verbatim' ((@($o2) -contains '2026-10-16T22:00:02 EVENT LANE LANE STALLED 5090-i5 40m (escalated from LANE IDLE) operator=op-run') -and (@($o2) -contains '2026-10-16T22:00:03 EVENT AGENT STALL imm26-x: RUNNING, silent 31 min'))
Check 'stream: summary line counts 2 alerts acked + ATTENTION: 2' ((@($o2) | Where-Object { $_ -like 'CHORES: 2 auto*alert acked*ATTENTION: 2' }).Count -eq 1) ($o2 -join ' | ')
$ackd = Get-Content -LiteralPath (Join-Path $r2 "alerts\acked\$idle.json") -Raw
Check 'acked record names coord-chores + 30 min re-open' ($ackd -match 'coord-chores' -and $ackd -match '30 min')
# ack-sweep command (a later-appearing alert)
$idle2 = Put-Alert $r2 'lane-idle' '4080-i4' 'LANE IDLE 4080-i4 9.0m operator=op-run (newest activity: x)'
$env:KAH_RUNS_DIR = $r2
$sw = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc ack-sweep -Runs $r2 2>&1 | Out-String)
Check 'ack-sweep acks the lane-idle alert under wind-down' ($sw -match 'ack-sweep: 1 acked' -and (Test-Path -LiteralPath (Join-Path $r2 "alerts\acked\$idle2.json"))) $sw
Check 'ack-sweep leaves the hard alerts open' ((Test-Path -LiteralPath (Join-Path $r2 "alerts\open\$stall.json")) -and (Test-Path -LiteralPath (Join-Path $r2 "alerts\open\$llm.json")))
# without wind-down / hold: nothing is acked
$r2b = New-Runs 'ack2'
Put-Status $r2b 'op-run' 'RUNNING'
$idle3 = Put-Alert $r2b 'lane-idle' '5090-i3' 'LANE IDLE 5090-i3 10m operator=op-run'
$f2b = Join-Path $r2b 'in.log'
[IO.File]::WriteAllText($f2b, "2026-10-16T22:00:00 EVENT LANE LANE IDLE 5090-i3 10.0m operator=op-run (newest activity: evidence x) -> ask`n", $u8)
$o2b = Run-Stream $r2b $f2b
Check 'no condition: idle alert NOT acked, line passes verbatim' ((Test-Path -LiteralPath (Join-Path $r2b "alerts\open\$idle3.json")) -and (@($o2b) -contains '2026-10-16T22:00:00 EVENT LANE LANE IDLE 5090-i3 10.0m operator=op-run (newest activity: evidence x) -> ask')) ($o2b -join ' | ')

# ======================================================================= 3. stream on recorded real events (2026-10-16)
$r3 = New-Runs 'real'
New-Item -ItemType File -Force -Path (Join-Path $r3 'WIND_DOWN.flag') | Out-Null
$real = Join-Path $fx 'events-2026-10-16.txt'
$realLines = @(Get-Content -LiteralPath $real -Encoding UTF8 | Where-Object { $_.Trim() })
# classify (no actions) to learn which lines are fully AUTO / fully JUDGMENT
$env:KAH_RUNS_DIR = $r3
$cl = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc classify -Runs $r3 -InputFile $real 2>&1 | ForEach-Object { [string]$_ }
$nAuto = @($cl | Where-Object { $_ -match '^AUTO\s' }).Count; $nJ = @($cl | Where-Object { $_ -match '^JUDGMENT\s' }).Count
Check 'real events: classify finds both AUTO and JUDGMENT items' ($nAuto -gt 20 -and $nJ -gt 3) "auto=$nAuto judgment=$nJ"
$o3 = Run-Stream $r3 $real
$sumLines = @($o3 | Where-Object { $_ -like 'CHORES:*' })
Check 'real events: exactly one summary line' ($sumLines.Count -eq 1) ($sumLines -join ' | ')
$unexpected = @($realLines | Where-Object { ($_ -match 'DONE') -and ($_ -match 'EVENT STATUS \S+ DONE:') -and ($o3 -contains $_) })
Check 'real events: DONE status lines are NOT printed' ($unexpected.Count -eq 0)
$stopLines = @($realLines | Where-Object { $_ -match 'EVENT STATUS \S+ STOPPED-CONTEXT' })
$missing = @($stopLines | Where-Object { $o3 -notcontains $_ })
Check 'real events: every STOPPED-CONTEXT status wake is printed verbatim' ($stopLines.Count -gt 0 -and $missing.Count -eq 0) ("n=" + $stopLines.Count + " missing=" + $missing.Count)
$swBad = @($realLines | Where-Object { $_ -match '^\S+ SWEEP STATUS ' } | Where-Object { $o3 -notcontains $_ })
Check 'real events: SWEEP STATUS bad-format / stale-RUNNING lines are printed verbatim' ($swBad.Count -eq 0) ($swBad -join ' | ')
$dg = Join-Path $r3 ('coordinator-digest\' + (Get-Date).ToString('yyyy-MM-dd') + '.md')
$dl = if (Test-Path -LiteralPath $dg) { @(Get-Content -LiteralPath $dg -Encoding UTF8 | Where-Object { $_ -like '- *' }) } else { @() }
Check 'real events: digest file has dated DONE/relay/setupfail lines' ($dl.Count -ge 20 -and ($dl | Where-Object { $_ -match 'DONE ' }).Count -ge 10) ("lines=" + $dl.Count)
Check 'real events: each digest line starts with "- <date> <time>"' ((@($dl | Where-Object { $_ -notmatch '^- \d{4}-\d\d-\d\d \d\d:\d\d' })).Count -eq 0)
Check 'real events: DONE lines carry task/latest/outputs/next fields' ((@($dl | Where-Object { $_ -match 'DONE \S+ \| ' -and $_ -notmatch 'latest: .* \| outputs: .* \| next: ' -and $_ -notmatch 'no status file' })).Count -eq 0)
# replay: same file again is deduped (seen-hash), nothing new reaches the model
$o3b = Run-Stream $r3 $real
$dl2 = @(Get-Content -LiteralPath $dg -Encoding UTF8 | Where-Object { $_ -like '- *' })
Check 'real events: replaying the same lines logs nothing twice' ($dl2.Count -eq $dl.Count) ("before=" + $dl.Count + " after=" + $dl2.Count)
$expectedJudg = @($cl | Where-Object { $_ -match '^JUDGMENT\s' }).Count
Check 'real events: replay prints no new attention lines' (@($o3b | Where-Object { $_ -notlike 'CHORES:*' -and $_ -notlike '`[auto-acked*' }).Count -eq 0) ($o3b -join ' | ')

# ======================================================================= 4. hard-constraints fixture through the full stream, wind-down ON
$r4 = New-Runs 'hard'
New-Item -ItemType File -Force -Path (Join-Path $r4 'WIND_DOWN.flag') | Out-Null
Put-Status $r4 'imm26-5090-i3-op' 'RUNNING'
$hf = Join-Path $fx 'hard-constraints.txt'
$hlines = @(Get-Content -LiteralPath $hf -Encoding UTF8 | Where-Object { $_.Trim() })
$o4 = Run-Stream $r4 $hf
$notPassed = @($hlines | Where-Object { $o4 -notcontains $_ })
Check 'hard-constraints: every line reaches the model verbatim' ($notPassed.Count -eq 0) ($notPassed -join ' || ')
Check 'hard-constraints: summary says 0 auto, ATTENTION: ' ((@($o4 | Where-Object { $_ -like 'CHORES: 0 auto*ATTENTION: ' + $hlines.Count })).Count -eq 1) ($o4[0])
Check 'hard-constraints: no [auto-acked] line, no digest line' (((@($o4 | Where-Object { $_ -like '`[auto-acked*' })).Count -eq 0) -and -not (Test-Path -LiteralPath (Join-Path $r4 ('coordinator-digest\' + (Get-Date).ToString('yyyy-MM-dd') + '.md'))))

# mixed digest: one AUTO item + one JUDGMENT item -> only the JUDGMENT item is printed
$r5 = New-Runs 'mixed'
Put-Status $r5 'agent-a' 'DONE' 'finish A' 'built A' 'C:\x\a.md' 'nothing'
$f5 = Join-Path $r5 'in.log'
[IO.File]::WriteAllText($f5, "2026-10-16T22:10:00 EVENT DIGEST 2 items ;; DONE: STATUS agent-a DONE: task: finish A ;; STATUS agent-z FAILED: task: nothing | respawn fresh`n", $u8)
$o5 = Run-Stream $r5 $f5
Check 'mixed digest: DONE item handled, FAILED item printed, DONE item not printed' ((@($o5 | Where-Object { $_ -match 'agent-z FAILED' }).Count -eq 1) -and (@($o5 | Where-Object { $_ -match 'agent-a DONE' }).Count -eq 0)) ($o5 -join ' | ')
$dp5 = Join-Path $r5 ('coordinator-digest\' + (Get-Date).ToString('yyyy-MM-dd') + '.md')
Check 'mixed digest: DONE logged with task/latest/outputs/next' ((Test-Path -LiteralPath $dp5) -and ((Get-Content -LiteralPath $dp5 -Raw) -match 'DONE agent-a \| finish A \| latest: built A \| outputs: C:\\x\\a.md \| next: nothing'))

# fail open: a corrupted rules file must not eat events
$badRules = Join-Path $tmp 'bad.rules.json'
$jr = Get-Content -LiteralPath (Join-Path $here 'coord-chores.rules.json') -Raw
[IO.File]::WriteAllText($badRules, ($jr -replace '"match": "\^DONE: STATUS', '"match": "(unclosed'), $u8)
$r6 = New-Runs 'failopen'
$f6 = Join-Path $r6 'in.log'
[IO.File]::WriteAllText($f6, "2026-10-16T22:10:00 EVENT STATUS agent-a DONE: task: finish A`n", $u8)
$env:KAH_RUNS_DIR = $r6
$o6 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc stream -Runs $r6 -Rules $badRules -InputFile $f6 2>&1 | ForEach-Object { [string]$_ }
Check 'fail open: a broken rule never swallows the event (printed, not dropped)' ((@($o6 | Where-Object { $_ -match 'agent-a DONE' }).Count -ge 1)) ($o6 -join ' | ')

# ======================================================================= 5. register-new (agent id recovery)
$r7 = New-Runs 'reg'
$sub = Join-Path $tmp 'subagents'; New-Item -ItemType Directory -Force -Path $sub | Out-Null
Put-Status $r7 'imm26-fixone' 'RUNNING'
Put-Status $r7 'imm26-fixtwo' 'RUNNING'
$rec1 = '{"type":"user","message":{"role":"user","content":"You are imm26-fixone, a subagent. Keep the status current: powershell tools/automation/agent-status.ps1 imm26-fixone RUNNING \"t\" \"s\" \"o\" \"n\""}}'
$rec2 = '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Do the ticket. Status file C:\\KenshiTestRuns\\agents\\imm26-fixtwo.status"}]}}'
$rec3 = '{"type":"user","message":{"role":"user","content":"You are imm26-nostatus, a subagent."}}'
[IO.File]::WriteAllText((Join-Path $sub 'agent-aaa111.jsonl'), $rec1 + "`n", $u8)
[IO.File]::WriteAllText((Join-Path $sub 'agent-bbb222.jsonl'), $rec2 + "`n", $u8)
[IO.File]::WriteAllText((Join-Path $sub 'agent-ccc333.jsonl'), $rec3 + "`n", $u8)
$env:KAH_RUNS_DIR = $r7
$dry = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc register-new -DryRun -Runs $r7 -SubagentsDir $sub 2>&1 | Out-String)
Check 'register-new -DryRun: resolves both names, nothing written' ($dry -match 'would register imm26-fixone -> aaa111' -and $dry -match 'would register imm26-fixtwo -> bbb222' -and -not (Test-Path -LiteralPath (Join-Path $r7 'agents\ids.json'))) $dry
Check 'register-new: agent without a status file is "pending", not registered' ($dry -match 'pending ccc333 -> imm26-nostatus')
$real7 = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc register-new -Runs $r7 -SubagentsDir $sub 2>&1 | Out-String)
$ids = if (Test-Path -LiteralPath (Join-Path $r7 'agents\ids.json')) { Get-Content -LiteralPath (Join-Path $r7 'agents\ids.json') -Raw } else { '' }
Check 'register-new: ids.json holds name -> id' ($real7 -match 'registered imm26-fixone -> aaa111' -and $ids -match 'aaa111' -and $ids -match 'bbb222') ($real7 + $ids)
$again = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc register-new -Runs $r7 -SubagentsDir $sub 2>&1 | Out-String)
Check 'register-new: a second run does not register twice' ($again -notmatch 'registered ')

# ======================================================================= 6. flush-to-live (temp git repo, explicit pathspec, identity)
$repo = Join-Path $tmp 'repo'; New-Item -ItemType Directory -Force -Path (Join-Path $repo 'testing') | Out-Null
& git -C $repo init -q 2>&1 | Out-Null
& git -C $repo config user.name 'someone-else'; & git -C $repo config user.email 'wrong@example.com'
[IO.File]::WriteAllText((Join-Path $repo 'testing\COORDINATOR_LIVE.md'), "# live`n", $u8)
[IO.File]::WriteAllText((Join-Path $repo 'other.txt'), "unrelated`n", $u8)
& git -C $repo add -A 2>&1 | Out-Null
& git -C $repo -c user.name=t -c user.email=t@t commit -q -m init 2>&1 | Out-Null
[IO.File]::WriteAllText((Join-Path $repo 'other.txt'), "unrelated change`n", $u8)   # dirty, NOT to be committed
& git -C $repo add other.txt 2>&1 | Out-Null                                         # staged, NOT to be committed
$r8 = New-Runs 'flush'
$d8 = '2026-10-16'
[IO.File]::WriteAllText((Join-Path $r8 "coordinator-digest\$d8.md"), "# Chores digest $d8`n- 2026-10-16 21:00 DONE agent-a | t | latest: l | outputs: o | next: n`n- 2026-10-16 21:05 DONE agent-b | t | latest: l | outputs: o | next: n`n", $u8)
$env:KAH_RUNS_DIR = $r8
$fl = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc flush-to-live -Runs $r8 -Repo $repo -Date $d8 -NoPush 2>&1 | Out-String)
$live = Get-Content -LiteralPath (Join-Path $repo 'testing\COORDINATOR_LIVE.md') -Raw
Check 'flush-to-live: block appended to COORDINATOR_LIVE.md' ($live -match "## Chores digest $d8" -and $live -match 'DONE agent-b') $fl
$au = (& git -C $repo log -1 --format='%an <%ae>').Trim()
Check 'flush-to-live: commit identity shaylanger' ($au -eq 'shaylanger <shaylanger2@gmail.com>') $au
$files = @(& git -C $repo show --name-only --format= HEAD)
Check 'flush-to-live: explicit pathspec (only COORDINATOR_LIVE.md in the commit, staged other.txt untouched)' ($files.Count -eq 1 -and $files[0] -eq 'testing/COORDINATOR_LIVE.md') ($files -join ',')
$fl2 = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc flush-to-live -Runs $r8 -Repo $repo -Date $d8 -NoPush 2>&1 | Out-String)
Check 'flush-to-live: second run flushes nothing' ($fl2 -match 'nothing new') $fl2
# index.lock retry: hold a lock for ~3 s while a new line is flushed
Add-Content -LiteralPath (Join-Path $r8 "coordinator-digest\$d8.md") -Value '- 2026-10-16 21:10 DONE agent-c | t | latest: l | outputs: o | next: n' -Encoding UTF8
$lock = Join-Path $repo '.git\index.lock'
[IO.File]::WriteAllText($lock, '')
$rel = Start-Job -ScriptBlock { param($p) Start-Sleep -Seconds 3; Remove-Item -LiteralPath $p -Force } -ArgumentList $lock
$fl3 = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cc flush-to-live -Runs $r8 -Repo $repo -Date $d8 -NoPush 2>&1 | Out-String)
Wait-Job $rel | Out-Null; Remove-Job $rel -Force
$cnt = @(& git -C $repo log --format=%s).Count
Check 'flush-to-live: retries over a .git/index.lock and commits' ($fl3 -match 'committed' -and $cnt -eq 3) ($fl3 + " commits=$cnt")

# ======================================================================= 7. wrapper + files
Check 'wrapper waker-persist-chores.sh exists and calls coord-chores.ps1 stream' ((Test-Path -LiteralPath (Join-Path $here 'waker-persist-chores.sh')) -and ((Get-Content -LiteralPath (Join-Path $here 'waker-persist-chores.sh') -Raw) -match 'coord-chores\.ps1.*stream'))
$ascii = [IO.File]::ReadAllBytes($cc) | Where-Object { $_ -gt 127 }
Check 'coord-chores.ps1 source is ASCII' (@($ascii).Count -eq 0)

Remove-Item Env:\KAH_RUNS_DIR -ErrorAction SilentlyContinue
if (-not $Keep) { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
Write-Host ("coord-chores-selftest: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
