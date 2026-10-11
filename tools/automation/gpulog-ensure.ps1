# gpulog-ensure.ps1 [-Rig 5090|4080|both] [-Status]: make sure gpulog.ps1 (2 s nvidia-smi telemetry, C:\KenshiTestRuns\gpulog\
# <rig>-*.csv) runs on the rig(s); start it hidden where it doesn't. session-start.ps1 calls it for both rigs (m103: Shay wants
# every crash diagnosable; a TDR at 16:35 had no GPU record).
#   5090: Start-Process hidden powershell (the pid lock in gpulog.ps1 refuses a second copy).
#   4080: copies gpulog.ps1 + gpulog.vbs to C:\KAH, puts gpulog.vbs into Shay's Startup folder (runs at every logon; the 4080
#         has no auto-logon, no admin needed) and starts it now through a kept scheduled task KAH-gpulog (/it: runs in
#         Shay's desktop session, survives the ssh session; an ssh-started process dies with the session).
# Prints one line per rig: GPULOG <rig> RUNNING pid=<n> file=<csv> age=<s>s | STARTED ... | FAILED <why>
param([ValidateSet('5090', '4080', 'both')][string]$Rig = 'both', [switch]$Status)
$auto = $PSScriptRoot
$src = Join-Path $auto 'gpulog.ps1'

function Check5090 {
    $d = 'C:\KenshiTestRuns\gpulog'; $lock = Join-Path $d '5090.pid'
    $p = if (Test-Path $lock) { (Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1) } else { $null }
    $alive = $p -and (Get-Process -Id $p -ErrorAction SilentlyContinue)
    $f = Get-ChildItem $d -Filter '5090-*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $age = if ($f) { [int]((Get-Date) - $f.LastWriteTime).TotalSeconds } else { -1 }
    if ($alive -and $age -ge 0 -and $age -lt 30) { return "GPULOG 5090 RUNNING pid=$p file=$($f.Name) age=${age}s" }
    if ($Status) { return "GPULOG 5090 DOWN (pid=$p alive=$([bool]$alive) age=${age}s)" }
    if ($alive) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }   # alive but not writing = stuck
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $src, '-Rig', '5090') | Out-Null
    Start-Sleep 5
    $p = Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { "GPULOG 5090 STARTED pid=$p" } else { 'GPULOG 5090 FAILED: no live pid after start' }
}

function Probe4080 { @(& ssh -o ConnectTimeout=10 4080 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\gpulog-state.ps1' 2>&1 | ForEach-Object { "$_" }) | Where-Object { $_ -like 'STATE*' } | Select-Object -First 1 }
function Check4080 {
    # always refresh the scripts (cheap): gpulog.ps1 edits reach the 4080 at the next ensure
    & scp -q $src (Join-Path $auto 'rig4080\gpulog-state.ps1') (Join-Path $auto 'rig4080\gpulog-start.ps1') '4080:C:/KAH/' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return 'GPULOG 4080 FAILED: scp to C:\KAH (4080 unreachable?)' }
    $s = Probe4080
    if (-not $s) { return 'GPULOG 4080 FAILED: state probe gave no answer' }
    $w = $s -split ' '   # STATE <pid> <alive> <age> <file>
    if ($w[2] -eq 'True' -and [int]$w[3] -ge 0 -and [int]$w[3] -lt 30) { return "GPULOG 4080 RUNNING pid=$($w[1]) file=$($w[4]) age=$($w[3])s" }
    if ($Status) { return "GPULOG 4080 DOWN ($s)" }
    $stuck = if ($w[2] -eq 'True') { $w[1] } else { 0 }
    $r = @(& ssh 4080 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\KAH\gpulog-start.ps1 -Stuck $stuck" 2>&1 | ForEach-Object { "$_" }) -join ' '
    Start-Sleep 6
    $s = Probe4080; $w = "$s" -split ' '
    if ($w[2] -eq 'True') { "GPULOG 4080 STARTED pid=$($w[1]) (Startup folder + task KAH-gpulog)" } else { "GPULOG 4080 FAILED: not running after start ($r / $s)" }
}

if ($Rig -in '5090', 'both') { Check5090 }
if ($Rig -in '4080', 'both') { Check4080 }
