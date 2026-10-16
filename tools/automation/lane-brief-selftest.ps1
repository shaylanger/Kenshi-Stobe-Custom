# lane-brief-selftest.ps1: builds a fake runs dir + fake repo in a temp dir and checks lane-brief.ps1 output.
# Covers: lane facts, dynamic DLL SHA, handoff TODO order, embedded row definitions + row script, KNOWN_BLOCKERS filtering by lane/row/DLL,
# condensed rules block, helper list, size <= 14.5 KB (printed on stderr), PREDECESSOR HANDOVER only with -Predecessor.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$t = Join-Path ([IO.Path]::GetTempPath()) ("lane-brief-st-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$runs = Join-Path $t 'runs'; $repo = Join-Path $t 'repo'; $inst = Join-Path $t 'inst\4'
$rt = "$repo\testing\live-stobe-queue\imm26-assert\rowtools"
New-Item -ItemType Directory -Force -Path "$runs\lanes", "$runs\agents", "$repo\testing", "$repo\tools\automation", "$repo\pending-fixes\npc-immersion-26\NC7", "$repo\pending-fixes\npc-immersion-26\NC2", "$inst\RE_Kenshi\mods\Stobe", $rt | Out-Null
[IO.File]::WriteAllBytes("$inst\RE_Kenshi\mods\Stobe\Stobe.dll", [byte[]](1, 2, 3, 4))
[IO.File]::WriteAllBytes("$repo\pending-fixes\npc-immersion-26\NC7\Stobe.dll", [byte[]](1, 2, 3, 4))
[IO.File]::WriteAllBytes("$repo\pending-fixes\npc-immersion-26\NC2\Stobe.dll", [byte[]](9, 9, 9))
(Get-Item "$repo\pending-fixes\npc-immersion-26\NC2\Stobe.dll").LastWriteTime = (Get-Date).AddHours(-3)
$want = (Get-FileHash "$inst\RE_Kenshi\mods\Stobe\Stobe.dll").Hash.Substring(0, 8)
$lj = @{ rig = '5090'; lanes = @(@{ id = 'i4'; instance = 4; dir = $inst; save_name = 'kah-fake'; save_dir = "$inst\save"; backend_port = 18087; bridge_port = 18100; pg_port = 15438; db = 'stobe_fake'; wsl_root = '/tmp/x'; lock = 'L'; lock_owner = 'o'; inflight = 'I'; stobe_log = 'a'; harness_log = 'b'; video_mode = '1024 x 768'; gfx = 'low'; framecap = 30; window = @{ display = 'DISPLAY2'; x = 1; y = 2; w = 3; h = 4 } }) }
$lj | ConvertTo-Json -Depth 6 | Set-Content "$runs\lanes\lanes-5090.json"
'{"5090-i4":{"ops":["imm26-5090-i4opX"],"dirs":["d"]}}' | Set-Content "$runs\lane-owners.json"
"# fake handoff`nHelpers: h4.sh`nTODO (not run): 02-a, 02-c/d, 03-a`nLESSONS: be careful`n" + ("filler " * 3000) | Set-Content "$runs\agents\imm26-5090-i4opX.handoff.md"
"# fake predecessor handoff`nHelpers: pred.sh`nTODO: 02-b`n" | Set-Content "$runs\agents\imm26-pred-op.handoff.md"
@"
| ID | Setup | Utterance / action | Expected evidence | Negative control | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-01-a | s1 | say: "hi" | e | n | BASE | PASS | ev | d |
| IMM-02-a | s2 SETUPTEXT-A | say: "a" | EXPECTED-A prompt lists the tie | NEG-A control | BASE | UNRUN | | |
| IMM-02-b | s2b | say: "b" | e | n | BASE | UNRUN | | |
| IMM-02-c | s2c | say: "c" | e | n | BASE | SETUP-FAIL | x | |
| IMM-02-d | s2d | say: "d" | e | n | BASE | PASS | x | |
| IMM-03-a | s3 | say: "e" | e | n | BASE | GATED | | |
"@ | Set-Content "$repo\testing\NPC_IMMERSION_26_TESTS.md"
@"
#!/usr/bin/env bash
rd_02a() {  # FX: aff 70, ROWSCRIPT-NOTE-A, two says
  :
}
rd_99z() {  # unrelated row script
  :
}
"@ | Set-Content "$rt\rowdefs.sh"
@"
# Known blockers
- Blocker alpha is real and global for ALL lanes (5090 i3, 5090 i5, 4080 i4)
- Blocker beta has no lane or row at all
- 5090 i3 only blocker GAMMA-I3 for 03-a
- 4080 i3 only blocker DELTA-4080I3 (rows 09-x)
- 5090 i4 blocker EPSILON-OWN-LANE
- Row blocker ZETA-ROWMATCH touches 02-a/b on 5090 i5
- Wildcard blocker ETA-WILD rows 03-* on 5090 i5
- DLL blocker THETA-DLL: DLL $want is broken on 4080 i3
"@ | Set-Content "$repo\testing\KNOWN_BLOCKERS.md"
New-Item -ItemType Directory -Force -Path "$repo\testing\live-stobe-queue\imm26-assert" | Out-Null
'' | Set-Content "$repo\testing\live-stobe-queue\imm26-assert\go-row.sh"; '' | Set-Content "$repo\tools\automation\save-report.ps1"
$fail = 0
function Chk($n, $c) { if ($c) { "ok   $n" } else { "FAIL $n"; $script:fail++ } }
$ErrorActionPreference = 'Continue'
$out = Join-Path $t 'o\brief.md'
$errf = Join-Path $t 'err.txt'
$txt = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Out $out -Runs $runs -Repo $repo -Name imm26-test-op 2>$errf) -join "`n"
$errt = Get-Content $errf -Raw
$sz = [Text.Encoding]::UTF8.GetByteCount($txt)
Chk 'out file written' (Test-Path $out)
Chk "lane DLL sha read dynamically ($want)" ($txt -match "lane Stobe.dll: $want")
Chk 'newest NC DLL = NC7 and match note' ($txt -match 'newest NC DLL: \w{8} NC7' -and $txt -match 'lane runs the newest NC DLL')
Chk 'lane facts (port 18087, DISPLAY2, kah-fake)' ($txt -match '18087' -and $txt -match 'DISPLAY2 at 1,2' -and $txt -match 'kah-fake')
Chk 'handoff from lane-owners override' ($txt -match 'imm26-5090-i4opX.handoff.md')
Chk 'handoff TODO order 02-a then 02-c, PASS 02-d skipped' ($txt -match '(?s)### IMM-02-a \[UNRUN\].*### IMM-02-c \[SETUP-FAIL\].*### IMM-03-a \[GATED\]' -and $txt -notmatch 'IMM-02-d \[')
Chk 'fallback row 02-b fills to the list' ($txt -match '### IMM-02-b \[UNRUN\].*unowned fallback')
Chk 'row definition embedded (setup, expected, negative)' ($txt -match 'setup: s2 SETUPTEXT-A' -and $txt -match 'expected evidence: EXPECTED-A prompt lists the tie' -and $txt -match 'negative control: NEG-A control')
Chk 'row script helper for 02-a with its note; none for 02-b' ($txt -match 'go-row.sh 02-a 5090-i4' -and $txt -match 'ROWSCRIPT-NOTE-A' -and $txt -match '(?s)IMM-02-b.*no row script' -and $txt -match 'with a go-row.sh script \(2\): 02-a 99-z')
Chk 'blockers: global (3 lanes) + no-lane + own lane + row match + wildcard + DLL' ($txt -match 'Blocker alpha' -and $txt -match 'Blocker beta' -and $txt -match 'EPSILON-OWN-LANE' -and $txt -match 'ZETA-ROWMATCH' -and $txt -match 'ETA-WILD' -and $txt -match 'THETA-DLL')
foreach ($k in 'Blocker alpha','Blocker beta','EPSILON-OWN-LANE','ZETA-ROWMATCH','ETA-WILD','THETA-DLL') { if ($txt -notmatch $k) { "  missing $k" } }
Chk 'blockers: 5090 i3 line with a picked row (03-a) is kept, 4080 i3 line with no picked row is dropped' ($txt -match 'GAMMA-I3' -and $txt -notmatch 'DELTA-4080I3')
Chk 'rules block: debug budget, handbacks, PI-06, never live install, status, checkpoints' ($txt -match 'ONE attempt per row' -and $txt -match 'AT MOST 8 lines: verdict.*SHA/paths.*DECISION/QUESTION for Shay' -and $txt -match '--allow-retry' -and $txt -match 'Never the live install' -and $txt -match 'Status discipline' -and $txt -match 'Checkpoint' -and $txt -match 'need NOT be read')
$rulesN = @(($txt -split "`n") | Where-Object { $_ -match '^- (Scope|Debug budget|PI-06|SETUP-FAIL|LLM health|Alerts|Game speed|A PASS|Batching|Server/DLL|Ending|Status discipline|Handbacks)' }).Count
Chk 'rules block: SETUP-FAIL needs-keyword rule + setupfail.ps1 list' ($txt -match 'must say needs: recipe\|server-fix\|native\|design\|fixture' -and $txt -match 'never just retry' -and $txt -match 'setupfail\.ps1 list')
Chk 'rules block: LLM health rule (PI-15)' ($txt -match 'llm-health\.sh' -and $txt -match 'Never mark LLM rows during LLM-HEALTH FAIL')
Chk "rules block <= 40 lines ($rulesN rule lines)" ($rulesN -ge 10 -and $rulesN -le 40)
Chk 'helper list: existing files listed with usage, missing ones dropped' ($txt -match '## Helper scripts' -and $txt -match '- go-row.sh: bash go-row.sh' -and $txt -match 'go-row.sh: .*\[R\]' -and $txt -notmatch '- go-batch.sh:')
Chk 'LANE STATE block: loaded save line, game pid/lock/inflight, launch recipe with instance/owner/env' ($txt -match '## LANE STATE' -and $txt -match "loaded save \(last harness 'load save='\)" -and $txt -match 'game pid none \(closed\); lock free; inflight clear' -and $txt -match 'launch: wsl lane-backend.sh start i4 ; env KAH_INSTANCE=4 KAH_OWNER=' -and $txt -match 'lane-window.ps1 -Lane i4 -Action place')
Chk 'rows: first 3 in full, 4th (02-b) as one line with its row-card pointer' ($txt -match '(?m)^### IMM-02-b \[UNRUN\].*unowned fallback.*\| no row script \| full card: bash .*row-card\.sh 02-b' -and $txt -notmatch '(?m)^### IMM-02-b.*\r?\n- setup:' -and $txt -match '(?m)^- setup: s2 SETUPTEXT-A')
Chk 'helper list names the ctxfix tools when they exist (next-row/row-card/logwin/usage/status-mark/wait-row only listed if on disk)' ($txt -notmatch '- next-row.sh:' -and $txt -notmatch '- go-batch.sh:')
Chk 'status/handoff/report commands carry the name' ($txt -match 'agent-status.ps1 imm26-test-op RUNNING' -and $txt -match 'imm26-test-op.handoff.md' -and $txt -match 'save-report.ps1 imm26-test-op')
Chk 'WARN-120k command present' ($txt -match 'WARN-120k')
Chk "size <= 14500 bytes ($sz)" ($sz -le 14500)
$fsz = (Get-Item $out).Length; Chk "size printed on stderr equals file size ($fsz)" ($errt -match "brief size $fsz bytes")
Chk 'no PREDECESSOR HANDOVER section without -Predecessor' ($txt -notmatch 'PREDECESSOR HANDOVER')
# with -Predecessor
$txtp = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -Name imm26-test-op2 -Predecessor imm26-pred-op 2>$null) -join "`n"
Chk 'PREDECESSOR HANDOVER section present with -Predecessor' ($txtp -match '## PREDECESSOR HANDOVER')
Chk 'handover: names predecessor files, no-game-commands rule, until-loop, lock' ($txtp -match 'imm26-pred-op.status' -and $txtp -match 'imm26-pred-op.handoff.md' -and $txtp -match 'imm26-pred-op.warn' -and $txtp -match 'NO game commands' -and $txtp -match 'kenshi-ctl launch/stop' -and $txtp -match 'lane lock' -and $txtp -match 'sleep 60' -and $txtp -match 'PREDECESSOR-READY' -and $txtp -match 'STOPPED-CONTEXT\|FAILED')
Chk 'handover: predecessor handoff is the excerpt source (Helpers: pred.sh)' ($txtp -match 'Helpers: pred.sh')
Chk 'handover: bash loop is syntactically valid (bash -n)' $(
    $m = [regex]::Match($txtp, '(?m)^    (A=/c/KenshiTestRuns.*)$')
    if (-not $m.Success) { $false } else { $f1 = Join-Path $t 'loop.sh'; [IO.File]::WriteAllText($f1, $m.Groups[1].Value + "`n"); $bash = Get-Command bash -ErrorAction SilentlyContinue; if (-not $bash) { $true } else { & bash -n ($f1 -replace '\\', '/') 2>$null; $LASTEXITCODE -eq 0 } }
)
Chk "size with -Predecessor <= 14500 ($([Text.Encoding]::UTF8.GetByteCount($txtp)))" ([Text.Encoding]::UTF8.GetByteCount($txtp) -le 14500)
# PI-19: predecessor status TASK text + successor registration in lane-owners.json; PI-20: game speed rule
"imm26-pred-op | RUNNING | 2026-10-15 20:00`ntask: 5090 i4 operator `"quoted`" row batch`nlatest: x`n" | Set-Content "$runs\agents\imm26-pred-op.status"
$txtr = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -Name imm26-succ-a -Predecessor imm26-pred-op 2>$null) -join "`n"
Chk 'PI-19 brief prints the predecessor task text exactly' ($txtr.Contains('STATUS TASK') -and $txtr.Contains('): 5090 i4 operator "quoted" row batch'))
Chk 'PI-19 ready-to-paste agent-status command carries the escaped task and the successor name' ($txtr.Contains('agent-status.ps1 imm26-succ-a RUNNING "5090 i4 operator `"quoted`" row batch" "started, reading brief"'))
Chk 'PI-19 status/WARN commands use the predecessor task text, not a made-up one' ($txtr.Contains('imm26-succ-a RUNNING "5090 i4 operator `"quoted`" row batch" "<row/step>"') -and $txtr.Contains('imm26-succ-a RUNNING "5090 i4 operator `"quoted`" row batch" "WARN-120k'))
$jr = Get-Content "$runs\lane-owners.json" -Raw | ConvertFrom-Json
Chk 'PI-19 successor registered first in lane-owners.json (predecessor not listed: -InLane fallback)' ((@($jr.'5090-i4'.ops) -join ',') -eq 'imm26-succ-a,imm26-test-op2,imm26-5090-i4opX' -or (@($jr.'5090-i4'.ops)[0] -eq 'imm26-succ-a')) ((@($jr.'5090-i4'.ops) -join ','))
Chk 'PI-19 brief says REGISTERED' ($txtr -match 'Lane-owners registration: REGISTERED lane 5090-i4')
$null = & powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -Name imm26-succ-a -Predecessor imm26-pred-op 2>$null
$jr2 = Get-Content "$runs\lane-owners.json" -Raw | ConvertFrom-Json
Chk 'PI-19 registration idempotent (second run, no duplicate)' (@(@($jr2.'5090-i4'.ops) | Where-Object { $_ -eq 'imm26-succ-a' }).Count -eq 1)
$opsBefore = @($jr2.'5090-i4'.ops) -join ','
$txtn = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -NoRemote -Name imm26-succ-b -Predecessor imm26-pred-op 2>$null) -join "`n"
$jr3 = Get-Content "$runs\lane-owners.json" -Raw | ConvertFrom-Json
Chk 'PI-19 -NoRemote: registration skipped with a one-line note, file unchanged' ($txtn -match 'registration skipped \(-NoRemote' -and ((@($jr3.'5090-i4'.ops) -join ',') -eq $opsBefore))
$txtm = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -NoRemote -Name imm26-succ-c -Predecessor imm26-nostatus 2>$null) -join "`n"
Chk 'PI-19 predecessor status missing: says so, falls back to lane default task' ($txtm -match 'task line NOT found')
Chk 'PI-20 speed rule in the brief (with and without -Predecessor)' ($txt -match 'Game speed \(PI-20\): above 5 ONLY under bash tools/stobe-goal-watch.sh' -and $txt -match 'never speed 10 for minutes' -and $txt -match 'hunger about every 60 s' -and $txtr -match 'PI-20')
Chk "size with PI-19/20 additions <= 14500 ($([Text.Encoding]::UTF8.GetByteCount($txtr)))" ([Text.Encoding]::UTF8.GetByteCount($txtr) -le 14500)
# changing the DLL changes the brief (nothing baked)
[IO.File]::WriteAllBytes("$inst\RE_Kenshi\mods\Stobe\Stobe.dll", [byte[]](7, 7))
$want2 = (Get-FileHash "$inst\RE_Kenshi\mods\Stobe\Stobe.dll").Hash.Substring(0, 8)
$txt2 = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo 2>$null) -join "`n"
Chk 'new DLL sha shown, mismatch warned' ($txt2 -match "lane Stobe.dll: $want2" -and $txt2 -match 'differs from newest NC')
# ---- PILOT variant (-Pilot haiku-i4): shadow brief, rows from pilot/rows-i4.txt, no claims/mark/status-mark/setupfail instructions ----
New-Item -ItemType Directory -Force -Path "$runs\pilot" | Out-Null
"# fake`n02-cx :: bash rowtools/hxrun_v2.sh 02-cx 5090-i4 --allow-retry `"pilot haiku-i4`" | tee C:/x/out/02-cx.out | tail -4`n23-b :: bash rowtools/sfrrun.sh 23-b 5090-i4 --save kah-imm26-i4`n" | Set-Content "$runs\pilot\rows-i4.txt"
$txtp = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -NoRemote -Name imm26-hk-test -Pilot haiku-i4 2>$null) -join "`n"
$txtn0 = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -NoRemote -Name imm26-hk-test 2>$null) -join "`n"
Chk 'PILOT: pilot header + shadow mode + SETUP.md pointer' ($txtp -match 'PILOT haiku-i4 \(SHADOW MODE' -and $txtp -match 'SETUP\.md' -and $txtp -match 'SHADOW MODE \(hard\)')
Chk 'PILOT: rows come from rows-i4.txt in order with the exact commands' ($txtp.IndexOf('- 02-cx :: bash rowtools/hxrun_v2.sh 02-cx 5090-i4') -gt 0 -and $txtp.IndexOf('- 23-b :: bash rowtools/sfrrun.sh') -gt $txtp.IndexOf('- 02-cx ::') -and $txtp.Contains('tee C:/x/out/02-cx.out'))
Chk 'PILOT: pilot-mark.sh is the recording tool (START / verdict / ESCALATE / 00-ask) with the operator name' ($txtp.Contains('pilot-mark.sh imm26-hk-test <ROW> START') -and $txtp -match '00-ask ESCALATE' -and $txtp -match 'exit 3 = you disagreed with the checker')
Chk 'PILOT: no claim/mark-row/status-mark/next-row/row-card/go-batch helper, no TESTS row definitions' ($txtp -notmatch '- status-mark\.sh:' -and $txtp -notmatch '- next-row\.sh:' -and $txtp -notmatch '- row-card\.sh:' -and $txtp -notmatch '- go-batch\.sh:' -and $txtp -notmatch '### IMM-' -and $txtp -notmatch 'SETUPTEXT-A' -and $txtp -notmatch 'Mark each row in testing')
Chk 'PILOT: keeps agent-status commands, report command, lane-deploy-only rule, pilot task text' ($txtp -match 'agent-status\.ps1 imm26-hk-test RUNNING "5090-i4 pilot operator \(shadow, haiku-i4\)"' -and $txtp -match 'lane-deploy\.sh is the ONLY server deploy path' -and $txtp -match 'save-report\.ps1')
Chk 'PILOT + normal: explicit 8-line hand-back rule with the five items' ($txtp -match 'AT MOST 8 lines: verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay' -and $txt -match 'AT MOST 8 lines: verdict, files/commits, SHA/paths, one next action, any DECISION/QUESTION for Shay')
Chk 'PILOT: asks the coordinator instead of improvising' ($txtp -match 'do NOT improvise')
Chk 'PI-48 stobe-auto ban in the normal brief (rule + lane harness dir form, no launch hint to run bare stobe-auto)' ($txt -match 'STOBE-AUTO BAN \(PI-48\): NEVER run bare' -and $txt -match 'KAH_DIR=''[^'']*mods.AutomationHarness'' stobe-auto' -and $txt -notmatch 'then stobe-auto wait-world')
Chk 'PI-48 stobe-auto ban in the pilot brief' ($txtp -match 'STOBE-AUTO BAN \(PI-48\): NEVER run bare')
Chk 'PI-48 stobe-auto ban also with -Predecessor' ($txtr -match 'STOBE-AUTO BAN \(PI-48\)')

Chk "PILOT: size <= 14500 ($([Text.Encoding]::UTF8.GetByteCount($txtp)))" ([Text.Encoding]::UTF8.GetByteCount($txtp) -le 14500)
Chk 'PILOT: the normal brief is unchanged (no PILOT text, still status-mark + TESTS rows + next-row)' ($txtn0 -notmatch 'PILOT haiku-i4' -and $txtn0 -match '### IMM-02-a' -and $txtn0 -match 'Next rows: first 3 in full' -and $txtn0 -notmatch 'SHADOW MODE')
$ErrorActionPreference = 'Continue'
$null = & powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo -NoRemote -Pilot nope 2>$null; Chk 'PILOT: unknown pilot name exits 2' ($LASTEXITCODE -eq 2)
$null = & powershell -NoProfile -File "$here\lane-brief.ps1" 4080-i4 -Runs $runs -Repo $repo -NoRemote -Pilot haiku-i4 2>$null; Chk 'PILOT: pilot on another lane exits 2' ($LASTEXITCODE -eq 2)
$ErrorActionPreference = 'Continue'; $null = & powershell -NoProfile -File "$here\lane-brief.ps1" nope -Runs $runs -Repo $repo 2>$null; Chk 'bad lane exits 2' ($LASTEXITCODE -eq 2)
Remove-Item -Recurse -Force $t
if ($fail) { "SELFTEST FAIL $fail"; exit 1 }
'SELFTEST OK'; exit 0
