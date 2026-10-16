# setupfail-selftest.ps1: selftest for setupfail.py/.ps1, mark-row.py and the attempts.py hook (SETUP-FAIL unblock tickets). Fixture dir via KAH_RUNS_DIR.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$py = (Get-Command python).Source
$t = Join-Path $env:TEMP ("sfst-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force "$t\runs" | Out-Null
$md = "$t\tests.md"
@(
'| ID | setup | say | pass | fail | exp | Status | Evidence | Date |',
'|---|---|---|---|---|---|---|---|---|',
'| IMM-01-a | s | say | p | f | BASE | UNRUN |  |  |',
'| IMM-08-d | s | say | p | f | BASE | SETUP-FAIL | 4080 i4 NC6: trip topics suppressed by travel consent so no followup exists | 2026-10-15 |',
'| IMM-10-b | s | say | p | f | BASE | SETUP-FAIL | 4080 i4: blocked by 10-a, no apology baseline | 2026-10-15 |',
'| IMM-22-a | s | say | p | f | BASE | SETUP-FAIL | 5090 i5 NC9: ACTIVITY_WILD_REFUSED homeBuilding=1; NC10 must drop it | 2026-10-15 |',
'| IMM-30-a | s | say | p | f | BASE | SETUP-FAIL | PREFLIGHT-FAIL llm provider down | 2026-10-15 |',
'| IMM-31-a | s | say | p | f | BASE | PASS | fine | 2026-10-15 |'
) | Set-Content -Encoding utf8 $md
$env:KAH_RUNS_DIR = "$t\runs"; $env:KAH_TESTS_MD = $md
$pass = 0; $fail = 0
function Chk([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { $script:pass++; "ok   $n" } else { $script:fail++; "FAIL $n $d" } }
function Mark { param([string[]]$A) $ErrorActionPreference = 'Continue'; $o = & $py (Join-Path $here 'mark-row.py') @A 2>&1; $script:mrc = $LASTEXITCODE; ($o | ForEach-Object { "$_" }) -join "`n" }
function SF { param([string[]]$A) $ErrorActionPreference = 'Continue'; (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'setupfail.ps1') @A 2>&1 | ForEach-Object { "$_" }) -join "`n" }
function Tk($row) { Get-Content "$t\runs\setupfail\$row.json" -Raw | ConvertFrom-Json }
function PutTk($j) { $j | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 "$t\runs\setupfail\$($j.row).json" }
$mdBefore = Get-Content $md -Raw

# 1. gate
$o = Mark @('01-a', 'SETUP-FAIL', 'could not run it')
Chk 'bare SETUP-FAIL refused (exit 2, message names needs:)' ($mrc -eq 2 -and $o -match 'needs: recipe\|server-fix\|native\|design\|fixture') $o
Chk 'refused mark leaves md untouched and creates no ticket' ((Get-Content $md -Raw) -eq $mdBefore -and -not (Test-Path "$t\runs\setupfail\01-a.json"))
$o = Mark @('01-a', 'SETUP-FAIL', 'needs: recipe')
Chk 'needs keyword without a reason refused' ($mrc -eq 2 -and $o -match 'not enough')
$o = Mark @('01-a', 'SETUP-FAIL', 'needs: bogus - the row needs something')
Chk 'unknown needs keyword refused' ($mrc -eq 2)
$o = Mark @('01-a', 'SETUP-FAIL', 'PREFLIGHT-FAIL llm provider down', '--lane', '5090-i3')
Chk 'PREFLIGHT-FAIL text exempt: marked, no ticket, no inbox note' ($mrc -eq 0 -and -not (Test-Path "$t\runs\setupfail\01-a.json") -and -not (Test-Path "$t\runs\inbox\coordinator"))
$o = Mark @('01-a', 'UNRUN', '')
# 2. ticket creation
$o = Mark @('IMM-01-a', 'SETUP-FAIL', 'needs: fixture - squad member with a hired Bodyguard contract; harness cannot create one', '--lane', '5090-i4')
$tk = Tk '01-a'
Chk 'SETUP-FAIL with needs creates the ticket (row, lane, needs, owner -, state open, reason)' ($mrc -eq 0 -and $tk.row -eq '01-a' -and $tk.lane -eq '5090-i4' -and $tk.needs -eq 'fixture' -and $tk.owner -eq '-' -and $tk.state -eq 'open' -and $tk.reason -match 'Bodyguard' -and $tk.marked_at -and $tk.last_update -and $tk.PSObject.Properties.Name -contains 'plan_path') $o
$msgs = @(Get-ChildItem "$t\runs\inbox\coordinator" -Filter '*-setupfail-01-a.msg' -ErrorAction SilentlyContinue)
Chk 'inbox note <ts>-setupfail-<row>.msg with the required first line' ($msgs.Count -eq 1 -and $msgs[0].Name -match '^\d{8}-\d{6}-setupfail-01-a\.msg$' -and (Get-Content $msgs[0].FullName -TotalCount 1) -eq 'SETUP-FAIL 01-a needs unblock plan: fixture')
Chk 'md row carries the status and the text' ((Get-Content $md -Raw) -match 'IMM-01-a \| s \| say \| p \| f \| BASE \| SETUP-FAIL \| needs: fixture')
$o = Mark @('01-a', 'SETUP-FAIL', 'needs: recipe - second attempt text, still no contract', '--lane', '5090-i4')
$tk = Tk '01-a'
Chk 're-mark updates needs/reason, no duplicate inbox note' ($tk.needs -eq 'recipe' -and $tk.reason -match 'second attempt' -and @(Get-ChildItem "$t\runs\inbox\coordinator" -Filter '*-setupfail-01-a.msg').Count -eq 1)
# 3. assign / state / list
$o = SF @('assign', '01-a', 'agentX', 'agents/out/x/plan.md')
$tk = Tk '01-a'
Chk 'assign sets owner, plan_path, open -> planned' ($tk.owner -eq 'agentX' -and $tk.state -eq 'planned' -and $tk.plan_path -eq 'agents/out/x/plan.md') $o
$o = SF @('state', '01-a', 'building', 'NC10 installing')
Chk 'state building with a note' ((Tk '01-a').state -eq 'building' -and ((Tk '01-a').notes -join ' ') -match 'NC10')
$o = SF @('state', '01-a', 'bogus')
Chk 'bad state rejected' ($LASTEXITCODE -ne 0)
$o = SF @('list')
Chk 'list shows row, age, needs, owner, state' ($o -match '^01-a age=\S+ needs=recipe owner=agentX state=building') $o
# 4. auto close
$o = Mark @('01-a', 'FAIL', 'ran this time; assertion failed')
$tk = Tk '01-a'
Chk 'FAIL mark closes the ticket (ran)' ($tk.state -eq 'closed' -and $tk.closed_by -eq 'FAIL' -and (SF @('list')) -eq 'none')
$o = Mark @('01-a', 'SETUP-FAIL', 'needs: native - NC11 hook missing in the DLL')
$tk = Tk '01-a'
Chk 'new SETUP-FAIL reopens the closed ticket with owner - and a new inbox note' ($tk.state -eq 'open' -and $tk.owner -eq '-' -and $tk.reopened -eq 1 -and @(Get-ChildItem "$t\runs\inbox\coordinator" -Filter '*-setupfail-01-a.msg').Count -eq 2)
$o = Mark @('01-a', 'PASS', 'state changed, stobe.log line')
Chk 'PASS mark closes the ticket' ((Tk '01-a').state -eq 'closed' -and (Tk '01-a').closed_by -eq 'PASS')
$o = Mark @('01-a', 'SETUP-FAIL', 'needs: design - policy question open')
$o = Mark @('01-a', 'GATED', 'GATED: waits for WP-E')
Chk 'GATED mark closes the ticket (not a SETUP-FAIL)' ((Tk '01-a').state -eq 'closed' -and (Tk '01-a').closed_by -eq 'GATED')
# 5. backfill
$o = SF @('backfill')
Chk 'backfill creates tickets for the SETUP-FAIL rows, skips PREFLIGHT-FAIL / PASS / UNRUN rows' ((Test-Path "$t\runs\setupfail\08-d.json") -and (Test-Path "$t\runs\setupfail\10-b.json") -and (Test-Path "$t\runs\setupfail\22-a.json") -and -not (Test-Path "$t\runs\setupfail\30-a.json") -and -not (Test-Path "$t\runs\setupfail\31-a.json")) $o
$a = Tk '22-a'; $b = Tk '10-b'; $c = Tk '08-d'
Chk 'backfill seed: 22-a native/imm26-5090-i5-op7/building' ($a.needs -eq 'native' -and $a.owner -eq 'imm26-5090-i5-op7' -and $a.state -eq 'building')
Chk 'backfill seed: 10-b imm26-5090-i3-hard2b planned; 08-d imm26-inv-setupfail planned with plan_path' ($b.owner -eq 'imm26-5090-i3-hard2b' -and $b.state -eq 'planned' -and $c.owner -eq 'imm26-inv-setupfail' -and $c.plan_path -match 'imm26-inv-setupfail/latest.md')
Chk 'backfill: lane taken from the evidence text, reason is the evidence' ($c.lane -eq '4080-i4' -and $c.reason -match 'travel consent')
$null = SF @('assign', '22-a', 'someone-else')
$o = SF @('backfill')
Chk 'backfill idempotent: existing owner kept' ((Tk '22-a').owner -eq 'someone-else')
Chk 'backfill sends no inbox notes' (@(Get-ChildItem "$t\runs\inbox\coordinator" -Filter '*-setupfail-08-d.msg' -ErrorAction SilentlyContinue).Count -eq 0)
# 6. list ordering: unowned first, then oldest first
$j = Tk '10-b'; $j.owner = '-'; $j.marked_at = '2026-10-15T01:00:00'; PutTk $j
$j = Tk '08-d'; $j.owner = '-'; $j.marked_at = '2026-10-15T00:00:00'; PutTk $j
$lines = @((SF @('list')) -split "`n")
Chk 'list: unowned first (oldest first among them), owned after' ($lines[0] -match '^08-d ' -and $lines[1] -match '^10-b ' -and $lines[0] -match ' - unowned$' -and $lines[2] -match '^22-a ' -and $lines[2] -notmatch 'unowned') ($lines -join ' | ')
$o = SF @('list', '-Lane', '5090-i5')
Chk 'list -Lane filters by lane' ($o -match '^22-a ' -and $o -notmatch '08-d') $o
# 7. sync
$new = @(Get-Content $md) | ForEach-Object { if ($_ -like '| IMM-01-a |*') { '| IMM-01-a | s | say | p | f | BASE | SETUP-FAIL | edited by hand needs: recipe - fixture missing | 2026-10-15 |' } else { $_ } }
$new | Set-Content -Encoding utf8 $md
$o = SF @('sync')
Chk 'sync creates a ticket for an ad hoc md SETUP-FAIL edit' ((Tk '01-a').state -eq 'open' -and $o -match 'created .*01-a') $o
$new = @(Get-Content $md) | ForEach-Object { if ($_ -like '| IMM-22-a |*') { '| IMM-22-a | s | say | p | f | BASE | PASS | fine | 2026-10-15 |' } else { $_ } }
$new | Set-Content -Encoding utf8 $md
$o = SF @('sync')
Chk 'sync leaves a fresh ticket alone (stale-md guard < 30 min)' ((Tk '22-a').state -ne 'closed')
$j = Tk '22-a'; $j.last_update = '2026-10-14T00:00:00'; PutTk $j
$o = SF @('sync')
Chk 'sync closes an old ticket whose md row is now PASS' ((Tk '22-a').state -eq 'closed' -and (Tk '22-a').closed_by -eq 'md:PASS') $o
# 8. attempts.py hook (go-row path)
$att = Join-Path $here '..\..\testing\live-stobe-queue\imm26-assert\rowtools\attempts.py'
$ad = "$t\runs\row-attempts"
& $py $att record $ad 5090-i3 05-a SETUP-FAIL 'row not ported to go-row.sh' | Out-Null
$h = Tk '05-a'
Chk 'attempts.py record SETUP-FAIL opens a ticket under <runs>/setupfail (needs inferred: recipe)' ($h.state -eq 'open' -and $h.needs -eq 'recipe' -and $h.lane -eq '5090-i3')
& $py $att record $ad 5090-i3 06-a PREFLIGHT-FAIL 'PREFLIGHT-FAIL lane down' | Out-Null
& $py $att record $ad 5090-i3 06-a SETUP-FAIL 'PREFLIGHT-FAIL lane down' | Out-Null
Chk 'attempts.py PREFLIGHT-FAIL (either form) makes no ticket' (-not (Test-Path "$t\runs\setupfail\06-a.json"))
& $py $att record $ad 5090-i3 05-a PASS 'ok' | Out-Null
Chk 'attempts.py record PASS closes the ticket' ((Tk '05-a').state -eq 'closed')
# 9. brief section
1..14 | ForEach-Object { $r = "{0:00}-z" -f $_; & $py (Join-Path $here 'setupfail.py') open $r 4080-i3 "needs: recipe - filler $r reason text" | Out-Null }
$b = @((SF @('brief')) -split "`n")
Chk 'brief: header + <= 12 ticket lines + overflow note' ($b[0] -match '^=== SETUP-FAIL TICKETS \(\d+ open' -and $b.Count -eq 14 -and $b[13] -match '^\s+\(\+\d+ more') ($b.Count)
Chk 'brief: unowned flagged' ($b[1] -match ' - unowned$')
$env:KAH_RUNS_DIR = "$t\empty"; $env:KAH_TESTS_MD = "$t
one.md"
Chk 'brief with no tickets prints nothing' ((SF @('brief')).Trim() -eq '')
Remove-Item -Recurse -Force $t
"selftest: $pass passed, $fail failed"
if ($fail) { exit 1 }
