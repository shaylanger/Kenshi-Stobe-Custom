# stobe-auto-guard-selftest.ps1: PI-48 PreToolUse guard in hooks\kenshi-waker-guard.ps1 (bare `stobe-auto` denied while a pilot ACTIVE marker is fresh).
# Offline: temp KAH_RUNS_DIR, feeds hook JSON on stdin, checks the exit code (2 = denied, 0 = allowed).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$hook = Join-Path $here 'hooks\kenshi-waker-guard.ps1'
$t = Join-Path ([IO.Path]::GetTempPath()) ("sa-guard-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path "$t\pilot\ab2\haiku" | Out-Null
$env:KAH_RUNS_DIR = $t
$fail = 0
function Hook([string]$cmd) {
    $j = @{ cwd = 'C:\KenshiModding'; tool_name = 'Bash'; tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress
    $ErrorActionPreference = 'Continue'
    $j | & powershell -NoProfile -ExecutionPolicy Bypass -File $hook pre 2>$null | Out-Null
    $LASTEXITCODE
}
function Chk($n, $want, $cmd) { $rc = Hook $cmd; if ($rc -eq $want) { "ok   $n" } else { "FAIL $n (rc=$rc want $want)"; $script:fail++ } }
# no ACTIVE marker: nothing is denied
Chk 'no marker: bare stobe-auto allowed' 0 'stobe-auto wait-world 120'
New-Item -ItemType File -Force -Path "$t\pilot\ab2\haiku\ACTIVE" | Out-Null
Chk 'ACTIVE: bare stobe-auto denied' 2 'stobe-auto wait-world 120'
Chk 'ACTIVE: wsl bash -c bare denied' 2 "wsl.exe -d X -- bash -c 'stobe-auto status'"
Chk 'ACTIVE: after && denied' 2 'cd /c/x && stobe-auto status | head -3'
Chk 'ACTIVE: with other env var but no KAH_DIR denied' 2 'FOO=1 stobe-auto status'
Chk 'ACTIVE: KAH_DIR= prefix allowed' 0 "KAH_DIR='D:\KenshiInst\4\mods\AutomationHarness' stobe-auto status"
Chk 'ACTIVE: KAH_INSTANCE rig-env route allowed' 0 'export KAH_INSTANCE=4; . rig-env.sh; stobe-auto status'
Chk 'ACTIVE: --dir allowed' 0 'stobe-auto --dir D:/KenshiInst/4/mods/AutomationHarness status'
Chk 'ACTIVE: grep/cat mentioning stobe-auto allowed' 0 'grep -n "stobe-auto" tools/automation/lane-brief.ps1'
Chk 'ACTIVE: lane-setup.sh allowed' 0 'bash tools/automation/lane-setup.sh 5090 4 kah-imm26-i4 --with Cind'
Chk 'ACTIVE: sleep rule still works' 2 'sleep 300'
# stale marker (> 12 h) = not active
(Get-Item "$t\pilot\ab2\haiku\ACTIVE").LastWriteTime = (Get-Date).AddHours(-13)
Chk 'stale ACTIVE (13 h): bare stobe-auto allowed' 0 'stobe-auto status'
Remove-Item -Recurse -Force $t
if ($fail) { "SELFTEST FAIL ($fail)"; exit 1 } else { 'SELFTEST OK' }
