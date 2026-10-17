# lane-successor-selftest.ps1 (PI-47): lane-idle.ps1's LANE NO-OPERATOR line carries ready-to-run successor spawn text. Offline: temp runs dir (-Runs), no lane touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\lane-successor-selftest.ps1
$ErrorActionPreference = 'Stop'
$idle = Join-Path $PSScriptRoot 'lane-idle.ps1'
$d = Join-Path ([IO.Path]::GetTempPath()) ("lanesucc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'agents') | Out-Null
$script:pass = 0; $script:fail = 0
function T([bool]$ok, [string]$n) { if ($ok) { $script:pass++; "SELFTEST PASS $n" } else { $script:fail++; "SELFTEST FAIL $n" } }
function Set-St([string]$name, [string]$state, [int]$ageMin = 1) {
    $f = Join-Path $d "agents\$name.status"
    Set-Content -LiteralPath $f -Value @("$name | $state | $(Get-Date -Format 'yyyy-MM-dd HH:mm')", 'task: t', 'latest: l', 'outputs: o', 'next: n') -Encoding UTF8
    (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes(-$ageMin)
}
function Lines { @(& $idle -NoMemory -Runs $d 2>&1 | ForEach-Object { "$_" }) }
function LaneLine([string]$lane) { @(Lines | Where-Object { $_ -match "^LANE NO-OPERATOR $([regex]::Escape($lane)) " }) }
try {
    # 1. stopped operator -> next number + predecessor + state, one line
    Set-St 'imm26-5090-i3op3' 'STOPPED-CONTEXT' 3
    $l = @(LaneLine '5090-i3')
    T ($l.Count -eq 1) 'one NO-OPERATOR line for the lane (single line: the waker greps lines)'
    $t = "$($l[0])"
    T ($t.Contains('SUCCESSOR (predecessor imm26-5090-i3op3=STOPPED-CONTEXT)')) 'names the predecessor and its state'
    T ($t.Contains('lane-brief.ps1 5090-i3 -Out C:\KenshiTestRuns\agents\imm26-5090-i3op4.brief.md -Name imm26-5090-i3op4 -Predecessor imm26-5090-i3op3')) 'exact lane-brief command with next name + predecessor'
    T ($t.Contains('[case:generate] You are imm26-5090-i3op4, lane 5090-i3. Read C:\KenshiTestRuns\agents\imm26-5090-i3op4.brief.md, then the handoff it names, and start the next row.')) 'Agent spawn prompt per AGENT_PROMPTS'
    T ($t -match 'AT MOST 8 lines' -and $t -match 'save-report\.ps1') 'prompt ends with the hand-back sentence'
    T ($t.Contains('agent-abandon.ps1 imm26-5090-i3op3 "parked:')) 'the rest-instead (parked) alternative is named'
    # 2. FAILED counts too, and the waker/alert regex still match
    Set-St 'imm26-5090-i3op3' 'FAILED' 3
    $t = "$(@(LaneLine '5090-i3')[0])"
    T ($t -match 'predecessor imm26-5090-i3op3=FAILED' -and $t -match '^LANE (IDLE|NO-OPERATOR|STALLED) (\S+)' -and $Matches[2] -eq '5090-i3') 'FAILED operator: same text; alert-lib lane regex still matches'
    # 3. letter suffix and name collision
    Set-St 'imm26-4080-op2g' 'STOPPED-CONTEXT' 3
    $t = "$(@(LaneLine '4080-i3')[0])"
    T ($t -match '-Name imm26-4080-op2g2 -Predecessor imm26-4080-op2g') "letter-suffixed name gets 2 ($t)"
    Set-St 'imm26-4080-op2g2' 'DONE' 5
    $t = "$(@(LaneLine '4080-i3')[0])"
    T ($t -match '-Name imm26-4080-op2g3 ' -and $t -match '-Predecessor imm26-4080-op2g ') 'an existing status name is skipped: next free name is used'
    # 4. no status at all for the lane -> no predecessor
    $t = "$(@(LaneLine '4080-i4')[0])"
    T ($t -match 'SUCCESSOR \(no predecessor status\)' -and $t -notmatch '-Predecessor' -and $t -match '-Name imm26-4080-i4op6') 'lane without any status: no -Predecessor, name from the lane config'
    # 5. owners override respected
    Set-Content -LiteralPath (Join-Path $d 'lane-owners.json') -Value '{"5090-i4":{"ops":["imm26-5090-i4op9","imm26-5090-i4op3"],"dirs":["x"]}}' -Encoding UTF8
    Set-St 'imm26-5090-i4op9' 'STOPPED-CONTEXT' 2
    $t = "$(@(LaneLine '5090-i4')[0])"
    T ($t -match '-Name imm26-5090-i4op10 -Predecessor imm26-5090-i4op9') 'lane-owners.json ops respected; 9 -> 10'
    # 6. a fresh RUNNING operator: no NO-OPERATOR and no successor text for that lane
    Set-St 'imm26-5090-i4op9' 'RUNNING' 1
    T (@(LaneLine '5090-i4').Count -eq 0 -and -not ((Lines | Where-Object { $_ -match '5090-i4' }) -match 'SUCCESSOR')) 'RUNNING operator: no successor text'
    # 7. alert-lib keeps the successor text (cap raised for lane-no-operator)
    T ((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'alert-lib.ps1')) -match "lane-no-operator'\) \{ 1200 \}") 'alert text cap for lane-no-operator holds the spawn text'
} finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
"SELFTEST lane-successor $script:pass pass / $script:fail fail"
if ($script:fail) { exit 1 }
exit 0
