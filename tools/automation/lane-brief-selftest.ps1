# lane-brief-selftest.ps1: builds a fake runs dir + fake repo in a temp dir and checks lane-brief.ps1 output.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$t = Join-Path ([IO.Path]::GetTempPath()) ("lane-brief-st-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$runs = Join-Path $t 'runs'; $repo = Join-Path $t 'repo'; $inst = Join-Path $t 'inst\4'
New-Item -ItemType Directory -Force -Path "$runs\lanes", "$runs\agents", "$repo\testing", "$repo\tools\automation", "$repo\pending-fixes\npc-immersion-26\NC7", "$repo\pending-fixes\npc-immersion-26\NC2", "$inst\RE_Kenshi\mods\Stobe" | Out-Null
[IO.File]::WriteAllBytes("$inst\RE_Kenshi\mods\Stobe\Stobe.dll", [byte[]](1, 2, 3, 4))
[IO.File]::WriteAllBytes("$repo\pending-fixes\npc-immersion-26\NC7\Stobe.dll", [byte[]](1, 2, 3, 4))
[IO.File]::WriteAllBytes("$repo\pending-fixes\npc-immersion-26\NC2\Stobe.dll", [byte[]](9, 9, 9))
(Get-Item "$repo\pending-fixes\npc-immersion-26\NC2\Stobe.dll").LastWriteTime = (Get-Date).AddHours(-3)
$want = (Get-FileHash "$inst\RE_Kenshi\mods\Stobe\Stobe.dll").Hash.Substring(0, 8)
$lj = @{ rig = '5090'; lanes = @(@{ id = 'i4'; instance = 4; dir = $inst; save_name = 'kah-fake'; save_dir = "$inst\save"; backend_port = 18087; bridge_port = 18100; pg_port = 15438; db = 'stobe_fake'; wsl_root = '/tmp/x'; lock = 'L'; lock_owner = 'o'; inflight = 'I'; stobe_log = 'a'; harness_log = 'b'; video_mode = '1024 x 768'; gfx = 'low'; framecap = 30; window = @{ display = 'DISPLAY2'; x = 1; y = 2; w = 3; h = 4 } }) }
$lj | ConvertTo-Json -Depth 6 | Set-Content "$runs\lanes\lanes-5090.json"
'{"5090-i4":{"ops":["imm26-5090-i4opX"],"dirs":["d"]}}' | Set-Content "$runs\lane-owners.json"
"# fake handoff`nHelpers: h4.sh`nTODO (not run): 02-a, 02-c/d, 03-a`nLESSONS: be careful`n" + ("filler " * 3000) | Set-Content "$runs\agents\imm26-5090-i4opX.handoff.md"
@"
| ID | Setup | Utterance / action | Expected | Neg | Build | Status | Evidence | Date |
|---|---|---|---|---|---|---|---|---|
| IMM-01-a | s1 | say: "hi" | e | n | BASE | PASS | ev | d |
| IMM-02-a | s2 | say: "a" | e | n | BASE | UNRUN | | |
| IMM-02-b | s2b | say: "b" | e | n | BASE | UNRUN | | |
| IMM-02-c | s2c | say: "c" | e | n | BASE | SETUP-FAIL | x | |
| IMM-02-d | s2d | say: "d" | e | n | BASE | PASS | x | |
| IMM-03-a | s3 | say: "e" | e | n | BASE | GATED | | |
"@ | Set-Content "$repo\testing\NPC_IMMERSION_26_TESTS.md"
"# Known blockers`n- Blocker alpha is real`n- Blocker beta" | Set-Content "$repo\testing\KNOWN_BLOCKERS.md"
$fail = 0
function Chk($n, $c) { if ($c) { "ok   $n" } else { "FAIL $n"; $script:fail++ } }
$out = Join-Path $t 'o\brief.md'
$txt = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Out $out -Runs $runs -Repo $repo -Name imm26-test-op) -join "`n"
Chk 'out file written' (Test-Path $out)
Chk "lane DLL sha read dynamically ($want)" ($txt -match "lane Stobe.dll: $want")
Chk 'newest NC DLL = NC7 and match note' ($txt -match 'newest NC DLL: \w{8} NC7' -and $txt -match 'lane runs the newest NC DLL')
Chk 'lane facts (port 18087, DISPLAY2, kah-fake)' ($txt -match '18087' -and $txt -match 'DISPLAY2 at 1,2' -and $txt -match 'kah-fake')
Chk 'handoff from lane-owners override' ($txt -match 'imm26-5090-i4opX.handoff.md')
Chk 'handoff TODO order 02-a then 02-c, PASS 02-d skipped' ($txt -match '(?s)- 02-a \[UNRUN\].*- 02-c \[SETUP-FAIL\].*- 03-a \[GATED\]' -and $txt -notmatch '02-d \[')
Chk 'fallback row 02-b fills to the list' ($txt -match '02-b \[UNRUN\].*unowned fallback')
Chk 'blockers listed' ($txt -match 'Blocker alpha')
Chk 'debug budget ONE attempt rule' ($txt -match 'ONE attempt per row' -and $txt -match '<= 8 lines')
Chk 'status/handoff/report commands carry the name' ($txt -match 'agent-status.ps1 imm26-test-op RUNNING' -and $txt -match 'imm26-test-op.handoff.md' -and $txt -match 'save-report.ps1 imm26-test-op')
Chk "size <= 6000 bytes ($([Text.Encoding]::UTF8.GetByteCount($txt)))" ([Text.Encoding]::UTF8.GetByteCount($txt) -le 6000)
# changing the DLL changes the brief (nothing baked)
[IO.File]::WriteAllBytes("$inst\RE_Kenshi\mods\Stobe\Stobe.dll", [byte[]](7, 7))
$want2 = (Get-FileHash "$inst\RE_Kenshi\mods\Stobe\Stobe.dll").Hash.Substring(0, 8)
$txt2 = (& powershell -NoProfile -File "$here\lane-brief.ps1" 5090-i4 -Runs $runs -Repo $repo) -join "`n"
Chk 'new DLL sha shown, mismatch warned' ($txt2 -match "lane Stobe.dll: $want2" -and $txt2 -match 'differs from newest NC')
$ErrorActionPreference = 'Continue'; $null = & powershell -NoProfile -File "$here\lane-brief.ps1" nope -Runs $runs -Repo $repo 2>$null; Chk 'bad lane exits 2' ($LASTEXITCODE -eq 2)
Remove-Item -Recurse -Force $t
if ($fail) { "SELFTEST FAIL $fail"; exit 1 }
'SELFTEST OK'; exit 0
