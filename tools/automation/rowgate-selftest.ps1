# rowgate-selftest.ps1: selftest for the row rework gate (rowgate.py, hooks/rowgate-guard.ps1). Uses today's REAL agent descriptions (agent-calls.tsv)
# and the real agents\*.status for the seed check. All state goes to a temp dir (ROWGATE_RUNS/DIR/AGENTS/TESTS/NOW overrides); nothing live is touched.
# Usage: powershell -NoProfile -File tools\automation\rowgate-selftest.ps1      prints PASS n/n or FAIL lines, exit 1 on any failure.
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = 'C:\Users\Shay\AppData\Local\Programs\Python\Python312\python.exe' }
$rg = Join-Path $here 'rowgate.py'
$hook = Join-Path $here 'hooks\rowgate-guard.ps1'
$t = Join-Path $env:TEMP ('rowgate-st-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ag = Join-Path $t 'agents'; New-Item -ItemType Directory -Force $ag, (Join-Path $t 'rowgate') | Out-Null
$env:ROWGATE_RUNS = $t; $env:ROWGATE_DIR = Join-Path $t 'rowgate'; $env:ROWGATE_AGENTS = $ag
$env:ROWGATE_TESTS = Join-Path $t 'tests.md'
Set-Content -Path $env:ROWGATE_TESTS -Value @('| IMM-02-cx | x | y | z | n | BASE | PASS | ev | 2026-10-16 |', '| IMM-26-f | x | y | z | n | BASE | FAIL | ev | 2026-10-16 |') -Encoding utf8
$script:n = 0; $script:bad = 0
function Ok($name, $cond, $info = '') { $script:n++; if (-not $cond) { $script:bad++; Write-Host "FAIL $name $info" } }
function Guard([string]$desc, [string]$prompt, [string]$cwd = 'C:\KenshiModding') {
    $j = @{ tool_name = 'Agent'; cwd = $cwd; tool_input = @{ description = $desc; prompt = $prompt; subagent_type = 'kenshi-generator' } } | ConvertTo-Json -Depth 5 -Compress
    $j | & $py -I $rg guard 2>$null | Out-Null
    return $LASTEXITCODE
}
function GuardMsg([string]$desc, [string]$prompt) {
    $j = @{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ description = $desc; prompt = $prompt } } | ConvertTo-Json -Depth 5 -Compress
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $m = ($j | & $py -I $rg guard 2>&1 | Out-String); $ErrorActionPreference = $old
    return $m
}
function Status($name, $state, [datetime]$when = (Get-Date)) { $f = Join-Path $ag "$name.status"; Set-Content $f "$name | $state | $($when.ToString('yyyy-MM-dd HH:mm'))`ntask: t`nlatest: t" -Encoding utf8; (Get-Item $f).LastWriteTime = $when }
function Led($row) { $p = Join-Path $env:ROWGATE_DIR "$row.json"; if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json } else { $null } }
function P($name) { "You are $name. Keep C:\KenshiTestRuns\agents\$name.status current.`nDo the thing." }
$rep = Join-Path $t 'prevreport.md'; Set-Content $rep 'handoff' -Encoding utf8
$ev = Join-Path $t 'imm26-5090-i3\rows\26-f'; New-Item -ItemType Directory -Force $ev | Out-Null; Set-Content (Join-Path $ev 'stobe.log') 'x'
$fake = Join-Path $t 'selftest\scene'; New-Item -ItemType Directory -Force $fake | Out-Null; Set-Content (Join-Path $fake 'a.txt') 'x'
function Full($name) { (P $name) + "`nPREV-REPORT: $rep`nWHAT IS DIFFERENT THIS TIME: replays the 21:30 live evidence offline, recipe stages the actor before s4`nREPLAY-EVIDENCE: $ev" }

# row detection on real descriptions
$r = & $py -I $rg rows '[case:investigate] imm26-sfFixA tickets 03-b 23-e 11-b'; Ok 'rows multi' ($r -eq '03-b 23-e 11-b') $r
$r = & $py -I $rg rows '[case:generate] 5090-i3 operator op23 05-cx 15-bx'; Ok 'rows operator' ($r -eq '05-cx 15-bx') $r
$r = & $py -I $rg rows '[case:patch] NC33 build 26-a poll fix 2026-10-16 4080-i3 24-bit 30-min i3op23'; Ok 'rows false positives' ($r -eq '26-a') $r
$r = & $py -I $rg rows '[case:investigate] imm26-sfFixB tickets 13-c 13-c-neg 14-d'; Ok 'rows neg' ($r -eq '13-c 13-c-neg 14-d') $r

# 26-f chain with real descriptions
Ok 'first agent free' ((Guard '[case:patch] 26-f availability gate fixer' (P 'imm26-t26f1')) -eq 0)
Ok 'dedupe retry is not a new attempt' ((Guard '[case:patch] 26-f availability gate fixer' (P 'imm26-t26f1')) -eq 0)
Ok 'dedupe keeps 1 attempt' (@((Led '26-f').attempts).Count -eq 1)
$m = GuardMsg '[case:patch] 26-f camp fixture recipe' (Full 'imm26-t26f2')
Ok 'one open agent per row' ($m -match 'still RUNNING' -and $m -match 'imm26-t26f1') $m
Status 'imm26-t26f1' 'DONE'
$m = GuardMsg '[case:patch] 26-f camp fixture recipe' (P 'imm26-t26f2')
Ok 'attempt 2 needs 3 lines' ($m -match 'PREV-REPORT' -and $m -match 'WHAT IS DIFFERENT' -and $m -match 'REPLAY-EVIDENCE' -and $m -match '(?s)candidates:.*26-f') $m
Ok 'attempt 2 with all lines passes' ((Guard '[case:patch] 26-f camp fixture recipe' (Full 'imm26-t26f2')) -eq 0)
Status 'imm26-t26f2' 'DONE'
$m = GuardMsg '[case:patch] 26-f camp zone rebind' ((P 'imm26-t26f3') + "`nPREV-REPORT: $rep`nWHAT IS DIFFERENT THIS TIME: same`nREPLAY-EVIDENCE: $fake")
Ok 'weak different + fake scene rejected' ($m -match 'WHAT IS DIFFERENT' -and $m -match 'fake/selftest') $m
$m = GuardMsg '[case:patch] 26-f camp zone rebind' ((Full 'imm26-t26f3') -replace [regex]::Escape($rep), (Join-Path $t 'nope.md'))
Ok 'missing prev report rejected' ($m -match 'PREV-REPORT does not exist') $m
Ok 'attempt 3 passes' ((Guard '[case:patch] 26-f camp zone rebind' (Full 'imm26-t26f3')) -eq 0)
Status 'imm26-t26f3' 'DONE'
$m = GuardMsg '[case:patch] 26-f availability gate in_combat blocks seam offer' (Full 'imm26-t26f4')
Ok '4th attempt needs escalate' ($m -match 'cap 3' -and $m -match 'ESCALATE' -and $m -match 'METHOD-QUESTION') $m
Ok '4th with patch case + lines still denied' ((Guard '[case:patch] 26-f availability gate in_combat blocks seam offer' ((Full 'imm26-t26f4') + "`nESCALATE: three fixes failed`nMETHOD-QUESTION: replay-only fix loop?")) -eq 2)
Ok '4th with escalate case + lines passes' ((Guard '[case:escalate] 26-f method change' ((Full 'imm26-t26f4') + "`nESCALATE: three fixes failed`nMETHOD-QUESTION: replay-only fix loop?")) -eq 0)
Ok 'ledger has 4 gated 26-f' (@((Led '26-f').attempts | Where-Object { $_.role -ne 'operator' }).Count -eq 4)

# exempt classes
Ok 'bench never gated' ((Guard '[case:bench] [model:sonnet] [effort:high] ab2-sonnet-02-ax' (P 'ab2-sonnet-02-ax')) -eq 0)
Ok 'bench leaves no ledger' ($null -eq (Led '02-ax'))
Ok 'operator allowed' ((Guard '[case:generate] 5090-i3 operator op23 05-cx 15-bx' (P 'imm26-5090-i3op23')) -eq 0)
Ok 'operator again (no cap, no open block)' ((Guard '[case:check] 5090-i3 operator NC28 15-bx' (P 'imm26-5090-i3op24')) -eq 0)
Ok 'operator recorded as operator' ((Led '15-bx').attempts[0].role -eq 'operator')
Ok 'reader not gated' ((Guard '[case:check] 4080-i3 operator rerun 20-d' (P 'x')) -eq 0)
Ok 'false-positive text creates no ledger' ((Guard '[case:patch] NC33 build poll fix 2026-10-16 4080-i3 24-bit' (P 'imm26-t1')) -eq 0 -and $null -eq (Led '24-bit'))
Ok 'sweep of > 4 rows not gated' ((Guard '[case:investigate] sweep 01-a 02-a 03-a 04-a 05-a 06-a' (P 'imm26-sweep')) -eq 0)

# multi-row: open agent on 11-b blocks the whole call, naming only 11-b
Ok 'sfFixA first' ((Guard '[case:investigate] imm26-sfFixA tickets 03-b 23-e 11-b' (P 'imm26-sfFixA')) -eq 0)
$m = GuardMsg '[case:patch] 11-b sffb v4 recipe' (Full 'imm26-t11b2')
Ok 'multi-row sibling blocked on 11-b' ($m -match 'row 11-b' -and $m -match 'imm26-sfFixA') $m

# skip tag
Ok 'skip tag allows and is logged' ((Guard '[case:patch] 26-f camp fixture rerun [rowgate:skip coordinator asked for a typo fix]' (P 'imm26-t26f5')) -eq 0)
Ok 'skip logged' ((Test-Path (Join-Path $env:ROWGATE_DIR 'skips.log')) -and ((Get-Content (Join-Path $env:ROWGATE_DIR 'skips.log') -Raw) -match 'typo fix'))
Ok 'skip tag without a reason is not accepted' ((Guard '[case:patch] 26-f x2 [rowgate:skip]' (P 'imm26-t26f6')) -eq 2)

# close resets the round; PASS verdict from the tests table is shown
& $py -I $rg close 26-f 'PASS test' | Out-Null
Ok 'after close the next agent is attempt 1' ((Guard '[case:patch] 26-f regression fix' (P 'imm26-t26f7')) -eq 0)
Ok 'after close round 2 has 1 attempt' (@((Led '26-f').attempts | Where-Object { $_.round -eq 2 }).Count -eq 1)
$s = & $py -I $rg status 26-f | Out-String
Ok 'status shows next-agent rule' ($s -match 'next gated agent = attempt 2') $s

# ttl / expiry: an unnamed running entry older than 45 min stops blocking
$env:ROWGATE_NOW = (Get-Date).AddMinutes(-80).ToString('yyyy-MM-dd HH:mm:ss')
Ok 'old unnamed agent' ((Guard '[case:patch] 08-d recipe: ask-window mark before tick 2' 'no status path here') -eq 0)
Remove-Item Env:\ROWGATE_NOW
$m = GuardMsg '[case:patch] 08-d recipe: ask-window mark before tick 3' (Full 'imm26-t08d2')
Ok 'expired agent does not block' ($m -notmatch 'still RUNNING') $m

# post hook marks a foreground run done
Ok 'fg first' ((Guard '[case:patch] 22-b walk recipe fixer' (P 'imm26-t22b1')) -eq 0)
$pj = @{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ description = '[case:patch] 22-b walk recipe fixer'; prompt = (P 'imm26-t22b1') }; tool_response = 'done agentId: a123abc' } | ConvertTo-Json -Depth 5 -Compress
$pj | & $py -I $rg post | Out-Null
Ok 'post marks fg done + agentId' (((Led '22-b').attempts[0].state -eq 'done') -and ((Led '22-b').attempts[0].agentId -eq 'a123abc'))

# end-to-end through the PowerShell hook wrapper (exit codes) and fail-open
$j = @{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ description = '[case:patch] 22-b walk recipe 2'; prompt = (P 'imm26-t22b2') } } | ConvertTo-Json -Depth 5 -Compress
$j | powershell -NoProfile -ExecutionPolicy Bypass -File $hook 2>$null | Out-Null
Ok 'wrapper denies attempt 2 without lines (exit 2)' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
$j = @{ tool_name = 'Agent'; cwd = 'C:\KenshiModding'; tool_input = @{ description = '[case:patch] 09-z first ever'; prompt = (P 'imm26-t09z') } } | ConvertTo-Json -Depth 5 -Compress
$j | powershell -NoProfile -ExecutionPolicy Bypass -File $hook 2>$null | Out-Null
Ok 'wrapper allows a first agent (exit 0)' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
'not json' | powershell -NoProfile -ExecutionPolicy Bypass -File $hook 2>$null | Out-Null
Ok 'bad input fails open' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
Ok 'other cwd ignored' ((Guard '[case:patch] 22-b other tree' (P 'x') 'D:\other') -eq 0)

# seed from TODAY's real status files (read-only on the real agents dir)
$real = 'C:\KenshiTestRuns\agents'
if (Test-Path (Join-Path $real 'imm26-fix23agate2.status')) {
    $env:ROWGATE_AGENTS = $real; $env:ROWGATE_DIR = Join-Path $t 'seeded'; $env:ROWGATE_NOW = '2026-10-16 22:00:00'
    $o = & $py -I $rg seed | Out-String
    $l = Led '23-a'
    Ok 'seed finds 23-a history' ($l -and @($l.attempts | Where-Object { $_.role -ne 'operator' }).Count -ge 4) $o
    Ok 'seed has fix23agate2' (@($l.attempts | Where-Object { $_.name -eq 'imm26-fix23agate2' }).Count -eq 1)
    Ok 'seed skips ab2 bench arms' (-not (Get-ChildItem $env:ROWGATE_DIR -Filter *.json | Where-Object { (Get-Content $_.FullName -Raw) -match '"name": "ab2-' }))
    $o2 = & $py -I $rg seed | Out-String
    Ok 'seed is idempotent' ($o2 -match 'seeded 0 attempt')
    $m = GuardMsg '[case:patch] 26-a arrival latch native patch' (P 'imm26-t26a9')
    Ok 'real 26-a history: next agent is over the cap' ($m -match 'cap 3' -or $m -match 'still RUNNING') $m
    $m = GuardMsg '[case:patch] 23-a next fix' (Full 'imm26-t23a9')
    Ok 'real 23-a: open fix23agate2 (RUNNING status) blocks or cap' ($m -match 'still RUNNING' -or $m -match 'cap 3') $m
    Remove-Item Env:\ROWGATE_NOW
}
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
if ($script:bad -eq 0) { Write-Host "PASS $($script:n)/$($script:n)"; exit 0 } else { Write-Host "FAIL $($script:bad) of $($script:n)"; exit 1 }


