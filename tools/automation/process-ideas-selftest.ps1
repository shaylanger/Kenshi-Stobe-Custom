# process-ideas-selftest.ps1: selftest for process-ideas.ps1 + its hooks into session-start.ps1, context-meter.project.ps1 and handoff-ready.ps1.
# Runs in a temp dir (KAH_PROCESS_IDEAS / KAH_RUNS_DIR); never touches docs/PROCESS_IDEAS.md or C:\KenshiTestRuns.
# Prints PASS/FAIL lines and "SELFTEST PASS n/m" (exit 1 on any FAIL).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$ws = Split-Path (Split-Path $here)
$pi = Join-Path $here 'process-ideas.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pi-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp, (Join-Path $tmp 'agents'), (Join-Path $tmp 'tail'), (Join-Path $tmp 'programs') | Out-Null
$old = @{ KAH_RUNS_DIR = $env:KAH_RUNS_DIR; KAH_PROCESS_IDEAS = $env:KAH_PROCESS_IDEAS; KPL_DIR = $env:KPL_DIR }
$env:KAH_RUNS_DIR = $tmp; $env:KPL_DIR = Join-Path $tmp 'programs'
$f = Join-Path $tmp 'ideas.md'; $env:KAH_PROCESS_IDEAS = $f
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
function Run([string]$file, [string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $file @a 2>&1
    [pscustomobject]@{ code = $LASTEXITCODE; out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
function P([string[]]$a) { Run $pi $a }
$EV = 'On 2026-10-15 the operator burned 200k tokens on one row (selftest evidence text).'
function Entry([string]$id, [string]$status, [string]$idea, [string]$hooks = 'no') {
    "### $id | $status`n- idea: $idea`n- evidence: $EV $id`n- saving: 10k tokens`n- risk: none`n- hooks: $hooks`n- weakens: no`n- added: 2026-10-15`n"
}
function Fixture([string[]]$active, [string[]]$retired = @()) {
    $t = "# Process ideas (selftest)`nintro line`n`n## Active`n`n" + ($active -join "`n") + "`n## Retired`n`n" + ($retired -join "`n")
    [IO.File]::WriteAllText($f, $t, (New-Object Text.UTF8Encoding($false)))
}
function Status([string]$id) { $m = [regex]::Match((Get-Content -LiteralPath $f -Raw), "(?m)^### $id \| (.+?)\s*$"); if ($m.Success) { $m.Groups[1].Value } else { 'ABSENT' } }
function Section([string]$id) { $t = Get-Content -LiteralPath $f -Raw; $r = $t.IndexOf('## Retired'); $i = $t.IndexOf("### $id |"); if ($i -lt 0) { 'ABSENT' } elseif ($i -gt $r) { 'RETIRED' } else { 'ACTIVE' } }
function Decide([string]$id, [bool]$applies, [string]$evidence = 'Seen this session: the situation did / did not occur in imm26 (selftest).', [string]$moment = '', [string]$label = ('r' + [guid]::NewGuid().ToString('N').Substring(0, 6))) {
    $d = @{ review = $label; decisions = @(@{ id = $id; applies = $applies; evidence = $evidence; moment = $moment }); new = @() }
    $j = Join-Path $tmp 'dec.json'; ($d | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $j -Encoding UTF8
    P @('review', $j)
}
try {
    T ($f.StartsWith($tmp)) '0 temp file in use'
    # ---- list: open entries only ----
    Fixture @((Entry 'PI-01' 'open' 'idea one'), (Entry 'PI-02' 'asked' 'idea two' ), (Entry 'PI-03' 'rejected x1' 'idea three'), (Entry 'PI-04' 'rejected x2' 'idea four'), (Entry 'PI-05' 'open' 'idea five' 'yes')) @((Entry 'PI-90' 'done' 'retired idea'))
    $r = P @('list')
    T ($r.code -eq 0 -and $r.out -match 'PI-01' -and $r.out -match 'PI-02' -and $r.out -match 'PI-05' -and $r.out -notmatch 'PI-03' -and $r.out -notmatch 'PI-04' -and $r.out -notmatch 'PI-90') '1a list shows open/asked, skips rejected + retired'
    T ($r.out -match 'PI-05.*touches hooks/settings' -and $r.out -notmatch 'PI-01.*touches hooks') '1b hooks flag shown only where set'
    T ((P @('list', '-All')).out -match 'PI-90') '1c list -All includes Retired'
    # ---- session-start lists open entries, -Brief works ----
    $ss = Run (Join-Path $here 'session-start.ps1') @('-Brief', '-AgentsOnly')
    T ($ss.out -match 'PROCESS IDEAS FOR SHAY \(ask once, together, in your first summary; do not apply any\)' -and $ss.out -match 'PI-01' -and $ss.out -match 'PI-05') '2a session-start -Brief prints the heading and the open entries'
    T ($ss.out -notmatch 'PI-03' -and $ss.out -notmatch 'PI-04' -and $ss.out -notmatch 'PI-90') '2b session-start skips rejected/retired entries'
    $piBlock = ($ss.out -split "`n" | Where-Object { $_ -match '^PROCESS IDEAS|^  PI-|^  \(after asking' }) -join "`n"
    T ($piBlock.Length -lt 4000) "2c process ideas block is short ($($piBlock.Length) chars < 4000, < 1k tokens)"
    Fixture @((Entry 'PI-03' 'rejected x1' 'idea three')) @()
    T ((Run (Join-Path $here 'session-start.ps1') @('-Brief', '-AgentsOnly')).out -notmatch 'PROCESS IDEAS FOR SHAY') '2d no heading when nothing is open'
    # ---- handoff texts mention the review step ----
    $env:KAH_RUNS_DIR = $tmp
    $in = [pscustomobject]@{ session_id = 'selftest-sid'; agent_id = $null }
    $env:KAH_AGENT_NAME = $null
    . (Join-Path $ws '.claude\context-meter.project.ps1')
    T ($HANDOFF_MSG_MAIN -match 'PROCESS IDEAS REVIEW' -and $HANDOFF_MSG_MAIN -match 'process-ideas\.ps1 review') '3a context-meter handoff text mentions the review step'
    T ($HANDOFF_MSG_MAIN.IndexOf('PROCESS IDEAS REVIEW') -lt $HANDOFF_MSG_MAIN.IndexOf('(5) Run:')) '3b the review comes before opening the new session (step 5)'
    $hr = Get-Content -LiteralPath (Join-Path $here 'handoff-ready.ps1') -Raw
    T ($hr -match 'PROCESS IDEAS' -and $hr -match 'process-ideas\.ps1 review') '3c handoff-ready.ps1 checklist mentions the review step'
    $ap = Get-Content -LiteralPath (Join-Path $ws 'testing\AGENT_PROMPTS.md') -Raw
    T ($ap -match '2b\. \*\*PROCESS IDEAS REVIEW') '3d AGENT_PROMPTS overlap-handoff section has the step'
    # ---- cap ----
    Fixture @(1..10 | ForEach-Object { Entry ('PI-{0:00}' -f $_) 'open' "idea $_" })
    $r = P @('add', '-Idea', 'eleventh', '-Evidence', $EV, '-Saving', '5k', '-Risk', 'none', '-Hooks', 'no')
    T ($r.code -ne 0 -and $r.out -match 'REFUSED' -and $r.out -match 'cap 10') '4a add refused at the 10-entry cap'
    Fixture @(1..7 | ForEach-Object { Entry ('PI-{0:00}' -f $_) 'open' "idea $_" })
    $r = P @('add', '-Idea', 'eighth', '-Evidence', $EV, '-Saving', '5k', '-Risk', 'none', '-Hooks', 'no')
    T ($r.code -eq 0 -and $r.out -match 'added PI-08' -and $r.out -match 'WARNING') '4b add at 8 active succeeds with a warning'
    Fixture @(1..7 | ForEach-Object { Entry ('PI-{0:00}' -f $_) 'open' "idea $_" })
    $r = P @('add', '-Idea', 'no evidence', '-Evidence', 'short', '-Saving', '5k', '-Risk', 'none', '-Hooks', 'no')
    T ($r.code -ne 0 -and $r.out -match 'evidence') '4c add without a concrete evidence text refused'
    # review: 4 new at 5 active -> 3 added; and cap holds inside review
    Fixture @(1..5 | ForEach-Object { Entry ('PI-{0:00}' -f $_) 'open' "idea $_" })
    $nw = 1..4 | ForEach-Object { @{ idea = "new idea $_"; evidence = "$EV new $_"; saving = '3k'; risk = 'none'; hooks = 'no' } }
    $j = Join-Path $tmp 'dec.json'; (@{ review = 'rn'; decisions = @(); new = $nw } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $j -Encoding UTF8
    $r = P @('review', $j)
    T ($r.out -match 'ADDED PI-06' -and $r.out -match 'ADDED PI-08' -and $r.out -notmatch 'ADDED PI-09' -and $r.out -match 'at most 3') '4d review adds at most 3 new entries'
    Fixture @(1..9 | ForEach-Object { Entry ('PI-{0:00}' -f $_) 'open' "idea $_" })
    (@{ review = 'rc'; decisions = @(); new = $nw } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $j -Encoding UTF8
    $r = P @('review', $j)
    T (([regex]::Matches($r.out, 'ADDED')).Count -eq 1 -and $r.out -match 'REFUSED new entry') '4e review new entries respect the cap (9 active -> only 1 added)'
    # ---- transitions: one step per handoff ----
    Fixture @((Entry 'PI-01' 'open' 'a'), (Entry 'PI-02' 'rejected x1' 'b'), (Entry 'PI-03' 'rejected x2' 'c'), (Entry 'PI-04' 'asked' 'd'))
    Decide 'PI-01' $false | Out-Null
    T ((Status 'PI-01') -eq 'rejected x1') '5a open + does not apply -> rejected x1'
    Decide 'PI-02' $false | Out-Null
    T ((Status 'PI-02') -eq 'rejected x2') '5b rejected x1 + does not apply -> rejected x2'
    $r = Decide 'PI-03' $false
    T ((Section 'PI-03') -eq 'RETIRED' -and (Status 'PI-03') -eq 'removed' -and $r.out -match 'REMOVED PI-03') '5c rejected x2 + does not apply -> removed, moved to Retired'
    T ((Get-Content -LiteralPath $f -Raw) -match '(?s)## Retired.*### PI-03 \| removed.*- retired: .*not applicable in 3 consecutive handoffs.*- log: ') '5d the Retired entry carries a reason and a log line'
    Decide 'PI-04' $false | Out-Null
    T ((Status 'PI-04') -eq 'rejected x1') '5e asked + does not apply -> rejected x1'
    Fixture @((Entry 'PI-01' 'rejected x1' 'a'), (Entry 'PI-02' 'rejected x2' 'b'), (Entry 'PI-03' 'open' 'c'))
    Decide 'PI-01' $true | Out-Null
    T ((Status 'PI-01') -eq 'open') '5f rejected x1 + applies -> open'
    Decide 'PI-02' $true | Out-Null
    T ((Status 'PI-02') -eq 'rejected x1') '5g rejected x2 + applies -> rejected x1'
    $r = Decide 'PI-03' $true
    T ((Status 'PI-03') -eq 'open' -and $r.out -match 'moment') '5h open + applies WITHOUT a named moment -> stays open (confirmed needs a moment)'
    Decide 'PI-03' $true -moment 'At 17:12 coordinator #6 read the 94 KB session-start output and lost ~23k tokens; the cap would have saved them.' | Out-Null
    T ((Status 'PI-03') -eq 'confirmed') '5i open + applies + moment -> confirmed'
    # silence and no-evidence = unchanged
    Fixture @((Entry 'PI-01' 'open' 'a'), (Entry 'PI-02' 'rejected x1' 'b'))
    $j = Join-Path $tmp 'dec.json'; (@{ review = 'rs'; decisions = @(); new = @() } | ConvertTo-Json) | Set-Content -LiteralPath $j -Encoding UTF8
    P @('review', $j) | Out-Null
    T ((Status 'PI-01') -eq 'open' -and (Status 'PI-02') -eq 'rejected x1') '5j silence (no decision) -> unchanged'
    $r = Decide 'PI-01' $false -evidence ''
    T ((Status 'PI-01') -eq 'open' -and $r.out -match 'without evidence') '5k a decision without evidence counts as silence -> unchanged'
    # one step per handoff
    Fixture @((Entry 'PI-01' 'open' 'a'))
    $d2 = @{ review = 'rone'; decisions = @(@{ id = 'PI-01'; applies = $false; evidence = 'first judgement from this session, long enough' }, @{ id = 'PI-01'; applies = $false; evidence = 'second judgement in the same review, long enough' }); new = @() }
    $j = Join-Path $tmp 'dec.json'; ($d2 | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $j -Encoding UTF8
    $r = P @('review', $j)
    T ((Status 'PI-01') -eq 'rejected x1' -and $r.out -match 'one step per handoff') '5l at most one step per entry per review (two decisions -> x1 only)'
    P @('review', $j) | Out-Null
    T ((Status 'PI-01') -eq 'rejected x1') '5m the same review label cannot step the entry twice'
    # ---- answers ----
    Fixture @((Entry 'PI-01' 'asked' 'a'), (Entry 'PI-02' 'open' 'b'), (Entry 'PI-03' 'open' 'c'))
    P @('answer', 'PI-01', 'no') | Out-Null
    T ((Section 'PI-01') -eq 'RETIRED' -and (Get-Content -LiteralPath $f -Raw) -match 'Shay said No') '6a answer no removes the entry and logs it in Retired'
    P @('answer', 'PI-02', 'yes') | Out-Null
    P @('answer', 'PI-03', 'approve') | Out-Null
    T ((Status 'PI-02') -eq 'confirmed' -and (Status 'PI-03') -eq 'confirmed') '6b answer yes / approve -> confirmed'
    Fixture @((Entry 'PI-01' 'open' 'a'))
    P @('asked', 'PI-01') | Out-Null
    T ((Status 'PI-01') -eq 'asked') '6c asked marks open -> asked'
    $r = P @('done', 'PI-01')
    T ($r.code -ne 0 -and (Status 'PI-01') -eq 'asked') '6d done without -Measured refused'
    P @('done', 'PI-01', '-Measured', 'before 94 KB, after 36 KB') | Out-Null
    T ((Section 'PI-01') -eq 'RETIRED' -and (Status 'PI-01') -eq 'done' -and (Get-Content -LiteralPath $f -Raw) -match 'measured: before 94 KB') '6e done moves to Retired with the measured numbers'
    # ---- guard: never weaken monitoring ----
    Fixture @((Entry 'PI-01' 'open' 'a'))
    $r = P @('add', '-Idea', 'Raise the agent stall timeout from 20 to 60 minutes', '-Evidence', $EV, '-Saving', 'fewer wakes', '-Risk', 'real stalls found later', '-Hooks', 'no')
    T ($r.code -ne 0 -and $r.out -match 'GUARD') '7a an idea that weakens the stall catch is refused without the hooks flag'
    $r = P @('add', '-Idea', 'Disable the dead-agent check for operators', '-Evidence', $EV, '-Saving', 'fewer wakes', '-Risk', 'none', '-Hooks', 'no', '-Weakens', 'no')
    T ($r.code -ne 0 -and $r.out -match 'GUARD') '7b the guard also catches wording even when weakens=no'
    $r = P @('add', '-Idea', 'Raise the agent stall timeout from 20 to 60 minutes', '-Evidence', $EV, '-Saving', 'fewer wakes', '-Risk', 'real stalls found later', '-Hooks', 'yes')
    $lst = (P @('list')).out
    T ($r.code -eq 0 -and $lst -match 'WEAKENS MONITORING: FOR SHAY ONLY' -and (Get-Content -LiteralPath $f -Raw) -match 'for_shay: yes') '7c with hooks=yes it is recorded, flagged FOR SHAY ONLY'
    $nw = @(@{ idea = 'Skip the idle check on lanes'; evidence = "$EV x"; saving = '1k'; risk = 'none'; hooks = 'no' })
    $j = Join-Path $tmp 'dec.json'; (@{ review = 'rg'; decisions = @(); new = $nw } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $j -Encoding UTF8
    T ((P @('review', $j)).out -match 'REFUSED new entry.*GUARD') '7d review refuses a weakening new entry too'
    # ---- the real file parses and has the seeds ----
    Remove-Item Env:\KAH_PROCESS_IDEAS
    $real = Run $pi @('list', '-All')
    T ($real.code -eq 0 -and $real.out -match 'PI-01 \[done\]' -and $real.out -match '\[open\]') '8a the real docs/PROCESS_IDEAS.md parses (seeded done + open entries)'
    $realOpen = @(($real.out -split "`n") | Where-Object { $_ -match '^PI-\d+ \[(open|asked|confirmed)\]' }).Count
    T ($realOpen -le 10) "8b the real file is within the 10-active cap ($realOpen)"
}
finally {
    foreach ($k in $old.Keys) { if ($null -ne $old[$k]) { Set-Item "Env:\$k" $old[$k] } else { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue } }
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}
"SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
if ($script:fail) { exit 1 }
