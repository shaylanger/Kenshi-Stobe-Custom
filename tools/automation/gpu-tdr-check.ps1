# gpu-tdr-check.ps1 [-Minutes 30] [-Rig 5090|4080]: prints one line per GPU driver timeout (TDR) in the last N minutes,
# then "TDR NONE" or "TDR <n> last=<time>". Exit 0 = none, 1 = TDR seen.
# Why (2026-10-11 hang-r11): a "frozen" Kenshi (Responding, CPU flat, harness silent) was a GPU TDR: nvlddmkm 153 +
# Display 4101 -> DXGI_ERROR_DEVICE_REMOVED -> RenderSystem_Direct3D11 shows a modal "BAD STUFF / out of video memory"
# MessageBoxA hidden behind the background test window. Check this before blaming a KenshiFP/harness lock.
param([int]$Minutes = 30, [string]$Rig = '5090')
$q = @"
`$ProgressPreference = 'SilentlyContinue'
`$ev = Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=(Get-Date).AddMinutes(-$Minutes)} -ErrorAction SilentlyContinue | Where-Object { `$_.ProviderName -in 'nvlddmkm','Display' }
foreach (`$e in `$ev) { 'TDR-EVENT {0} {1} {2}' -f `$e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), `$e.Id, `$e.ProviderName }
if (`$ev) { 'TDR {0} last={1}' -f @(`$ev).Count, @(`$ev)[0].TimeCreated.ToString('HH:mm:ss'); exit 1 } else { 'TDR NONE'; exit 0 }
"@
if ($Rig -eq '4080') {
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($q))
    ssh 4080 "powershell -NoProfile -EncodedCommand $enc"; exit $LASTEXITCODE
}
& ([scriptblock]::Create($q)); exit $LASTEXITCODE
