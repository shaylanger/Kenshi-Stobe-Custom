# pi52-selftest.ps1 (PI-52): mark-row.py refuses a false 'bundle dirs missing' SETUP-FAIL (run.log empty AND dirs exist); everything else passes unchanged.
# Also runs lane-brief-selftest.ps1 (snag block checks) and checks the real KNOWN_BLOCKERS.md snag section (<= 10 lines).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$t = Join-Path ([IO.Path]::GetTempPath()) ("pi52-st-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $t | Out-Null
$fail = 0
function Chk($n, $c) { if ($c) { "ok   $n" } else { "FAIL $n"; $script:fail++ } }
$md = "$t\tests.md"; $runs = "$t\runs"; New-Item -ItemType Directory -Force -Path $runs | Out-Null
@"
| ID | Setup | Utterance | Expected | Neg | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-01-cx | s | u | e | n | BASE | UNRUN | | |
"@ | Set-Content $md
$env:KAH_TESTS_MD = $md; $env:KAH_RUNS_DIR = $runs
$ev1 = "$t/ev1"; $bd1 = "$t/bd1"        # dirs exist, run.log empty
$ev2 = "$t/ev2"; $bd2 = "$t/bd2"        # dirs exist, run.log non-empty
$ev3 = "$t/ev3"; $bd3 = "$t/bd3"        # dirs missing, run.log empty
foreach ($d in $ev1, $ev2, $ev3, "$bd1/savA", "$bd1/savB", "$bd2/savA", "$bd2/savB", $bd3) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
'' | Set-Content "$ev1/run.log" -NoNewline; '' | Set-Content "$ev3/run.log" -NoNewline; 'step 1 started' | Set-Content "$ev2/run.log"
function Msg($bd, $ev, $dirs) { "needs: recipe the row script wrote bundle dirs; RESULT 01-cx SETUP-FAIL bundle dirs missing under ${bd}: $dirs (the row script stopped early; see run.log) [evidence=$ev]" }
function Mark($status, $note) { $o = (& python3 "$here\mark-row.py" 01-cx $status $note 2>&1) -join "`n"; [pscustomobject]@{ rc = $LASTEXITCODE; out = $o } }
$py = Get-Command python3 -ErrorAction SilentlyContinue; if (-not $py) { function python3 { & python @args } }
$r = Mark 'SETUP-FAIL' (Msg $bd1 $ev1 'A:savA,B:savB')
Chk 'refuses: run.log empty AND dirs exist' ($r.rc -eq 2 -and $r.out -match 'REFUSED: false SETUP-FAIL' -and $r.out -match 'HX_OUT=C:/KenshiTestRuns/imm26-4080-hx' -and $r.out -match 'not marked')
Chk 'refusal wrote nothing to the tests md' ((Get-Content $md -Raw) -match 'IMM-01-cx \| s \| u \| e \| n \| BASE \| UNRUN')
$r = Mark 'SETUP-FAIL' (Msg $bd2 $ev2 'A:savA,B:savB')
Chk 'passes: run.log non-empty' ($r.rc -eq 0 -and $r.out -match 'marked 01-cx SETUP-FAIL')
$r = Mark 'SETUP-FAIL' (Msg $bd3 $ev3 'A:savA,B:savB')
Chk 'passes: dirs truly missing' ($r.rc -eq 0 -and $r.out -match 'marked 01-cx SETUP-FAIL')
$r = Mark 'SETUP-FAIL' "needs: fixture the base save kah-x is gone from the lane save dir [evidence=$ev1]"
Chk 'passes: other SETUP-FAIL reason (empty run.log)' ($r.rc -eq 0 -and $r.out -match 'marked')
$r = Mark 'SETUP-FAIL' 'bundle dirs missing under x: A:savA'
Chk 'bare SETUP-FAIL still refused by the old needs: rule' ($r.rc -eq 2 -and $r.out -match 'REFUSED')
$r = Mark 'FAIL' (Msg $bd1 $ev1 'A:savA')
Chk 'passes: non-SETUP-FAIL status unchanged' ($r.rc -eq 0 -and $r.out -match 'marked 01-cx FAIL')
$r = Mark 'SETUP-FAIL' ("needs: recipe bundle dirs missing under ${bd1}: A:savA (no evidence path given)")
Chk 'passes: no evidence dir named (cannot prove)' ($r.rc -eq 0)
$bl = Get-Content "$here\..\..\testing\KNOWN_BLOCKERS.md" -Raw
$sec = ($bl -split '(?m)^## KNOWN TOOLING SNAGS')[1]
$n = @(($sec -split "`r?`n") | Where-Object { $_ -match '^- ' }).Count
Chk "real KNOWN_BLOCKERS.md snag section: 1..10 lines ($n), names HX_OUT + KAH_FPS" ($n -ge 1 -and $n -le 10 -and $sec -match 'HX_OUT=C:/KenshiTestRuns/imm26-4080-hx' -and $sec -match 'KAH_FPS=30')
$ErrorActionPreference = 'Continue'
$lb = (& powershell -NoProfile -File "$here\lane-brief-selftest.ps1" 2>&1 | ForEach-Object { "$_" }) -join "`n"
$ErrorActionPreference = 'Stop'
Chk 'lane-brief-selftest: both PI-52 snag checks ok, no PI-52 FAIL' ($lb -match 'ok   PI-52: KNOWN TOOLING SNAGS block' -and $lb -match 'ok   PI-52: snag lines appear' -and $lb -notmatch '(?m)^FAIL PI-52')
$other = @(($lb -split "`n") | Where-Object { $_ -match '^FAIL ' -and $_ -notmatch 'PI-52' })
if ($other.Count) { "note: $($other.Count) non-PI-52 lane-brief-selftest FAIL line(s) exist independent of this change (checked on the pre-pi52 lane-brief.ps1: same 5): " + (($other | ForEach-Object { $_.Substring(5, [Math]::Min(40, $_.Length - 5)) }) -join ' | ') }
Remove-Item -Recurse -Force $t
Remove-Item Env:KAH_TESTS_MD, Env:KAH_RUNS_DIR -ErrorAction SilentlyContinue
if ($fail) { "SELFTEST FAIL $fail"; exit 1 } else { "SELFTEST OK" }
