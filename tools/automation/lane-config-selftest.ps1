<# lane-config-selftest.ps1: offline selftest for lane-ini-lib.ps1 + lane-config-check.ps1 (temp dirs only, no lane touched). Prints PASS/FAIL per case, `RESULT lane-config-selftest PASS|FAIL n/m`. #>
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lane-ini-lib.ps1')
$t = Join-Path $env:TEMP "lane-config-selftest-$PID"; New-Item -ItemType Directory -Force $t | Out-Null
$ok = 0; $n = 0
function Case($name, [bool]$c) { $script:n++; if ($c) { $script:ok++ }; "$(if ($c) { 'PASS' } else { 'FAIL' }) $name" }
$live = "[Settings]`r`nServerHost=1.2.3.4`r`nServerPort=8083`r`nTalkRadius=80`r`nEnableBoredEventConversations=1`r`nSpeakWhilePaused=1`r`n`r`n[DrawnWeapon]`r`nX=1`r`n`r`n[Settings]`r`nServerHost=1.2.3.4`r`nServerPort=8083`r`nTalkRadius=99`r`nOnlyLater=7`r`nEnableBoredEventConversations=0`r`n[Network]`r`nChatHttpTimeoutSeconds=300`r`n"
$f = "$t\a.ini"
[IO.File]::WriteAllText($f, $live, (New-Object Text.UTF8Encoding $true))
Case 'bad ini is detected (BOM, 2 blocks, =0, port)' ((Test-LaneIni $f 18086).Count -eq 4)
Case 'Write-LaneIni reports a change' (Write-LaneIni $f 18086)
$b = [IO.File]::ReadAllBytes($f); $txt = [IO.File]::ReadAllText($f)
Case 'no BOM after fix' (-not ($b[0] -eq 0xEF))
Case 'exactly one [Settings]' (([regex]::Matches($txt, '(?m)^\[Settings\]')).Count -eq 1)
Case 'EnableBoredEventConversations=1 once' (([regex]::Matches($txt, '(?m)^EnableBoredEventConversations=1\r?$')).Count -eq 1 -and $txt -notmatch 'EnableBoredEventConversations=0')
Case 'first block wins for TalkRadius (80)' ($txt -match 'TalkRadius=80' -and $txt -notmatch 'TalkRadius=99')
Case 'key only in the later block is kept (OnlyLater=7 inside [Settings])' ($txt -match '(?s)\[Settings\].*OnlyLater=7.*\[DrawnWeapon\]')
Case 'other sections intact' ($txt -match '\[DrawnWeapon\]' -and $txt -match '\[Network\]' -and $txt -match 'ChatHttpTimeoutSeconds=300')
Case 'port and host rewritten once' ($txt -match 'ServerPort=18086' -and $txt -notmatch '8083' -and $txt -match 'ServerHost=127.0.0.1')
Case 'CRLF preserved' ($txt -match "`r`n")
Case 'fixed ini passes Test-LaneIni' ((Test-LaneIni $f 18086).Count -eq 0)
Case 'second Write-LaneIni is a no-op' (-not (Write-LaneIni $f 18086))
# missing key line is added
[IO.File]::WriteAllText("$t\b.ini", "[Settings]`nServerPort=1`n[Network]`nA=1`n", (New-Object Text.UTF8Encoding $false))
$null = Write-LaneIni "$t\b.ini" 5; Case 'absent EnableBoredEventConversations is added =1' ((Test-LaneIni "$t\b.ini" 5).Count -eq 0)
# check script against a temp 5090-format registry
$dir = "$t\lane"; New-Item -ItemType Directory -Force "$dir\mods\Stobe", "$dir\RE_Kenshi\mods\Stobe" | Out-Null
[IO.File]::WriteAllBytes("$dir\mods\Stobe\Stobe.dll", [byte[]](1, 2, 3))
[IO.File]::WriteAllText("$dir\RE_Kenshi\mods\Stobe\StobeCustom.ini", $live, (New-Object Text.UTF8Encoding $true))
$wk = "/tmp/lane-config-selftest-$PID.key"; $key = -join ((1..64) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -c "printf %s $key > $wk"
$reg = @{ lanes = @(@{ id = 'x1'; dir = $dir; backend_port = 18086; key_file = $wk }) } | ConvertTo-Json -Depth 4
Set-Content "$t\reg.json" $reg -Encoding UTF8
$r1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'lane-config-check.ps1') 5090 -Defs "$t\reg.json" -NoNeg; $e1 = $LASTEXITCODE
Case 'check flags ini and key (2 WARN, exit 1)' (@($r1 | Where-Object { $_ -match ' WARN ' }).Count -eq 2 -and $e1 -eq 1)
$r2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'lane-config-check.ps1') 5090 -Defs "$t\reg.json" -NoNeg -Fix; $e2 = $LASTEXITCODE
Case '-Fix repairs ini and key (2 FIXED, exit 0)' (@($r2 | Where-Object { $_ -match ' FIXED ' }).Count -eq 2 -and $e2 -eq 0)
Case 'key file equals the server key and is never printed' (([IO.File]::ReadAllText("$dir\mods\Stobe\activity-transport.key") -eq $key) -and -not (($r1 + $r2) -join "`n").Contains($key))
$r3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'lane-config-check.ps1') 5090 -Defs "$t\reg.json" -NoNeg; $e3 = $LASTEXITCODE
Case 'after fix: PASS, exit 0' (@($r3 | Where-Object { $_ -match ' WARN ' }).Count -eq 0 -and $e3 -eq 0)
& wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- rm -f $wk
Remove-Item -Recurse -Force $t
"RESULT lane-config-selftest $(if ($ok -eq $n) { 'PASS' } else { 'FAIL' }) $ok/$n"
exit $(if ($ok -eq $n) { 0 } else { 1 })
