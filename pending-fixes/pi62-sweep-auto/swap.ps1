# PI-62 hook swap (run by Shay AFTER the PI-51 swap): backup live hook, install the pi62 candidate (= PI-51 candidate + "check -Auto"), run selftests.
$ErrorActionPreference = 'Stop'
$h = 'C:\KenshiModding\tools\automation\hooks'
$live = Get-Content -Raw "$h\kenshi-waker-guard.ps1"
if ($live -notmatch 'Get-PersistWaker') { throw 'PI-51 is not swapped in yet (live hook has no Get-PersistWaker): run pending-fixes\pi51-persistent-waker\swap.ps1 first' }
$cand = Get-Content -Raw "$h\kenshi-waker-guard.ps1.pi62.candidate"
if (($cand -notmatch 'Get-PersistWaker') -or ($cand -notmatch 'check -Auto')) { throw 'pi62 candidate is missing PI-51 or -Auto code' }
New-Item -ItemType Directory -Force C:\KenshiTestRuns\backup | Out-Null
Copy-Item "$h\kenshi-waker-guard.ps1" C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi62 -Force
Copy-Item "$h\kenshi-waker-guard.ps1.pi62.candidate" "$h\kenshi-waker-guard.ps1.new" -Force
Move-Item -Force "$h\kenshi-waker-guard.ps1.new" "$h\kenshi-waker-guard.ps1"
Set-Location C:\KenshiModding
powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\testruns-sweep-selftest.ps1 | Select-Object -Last 2
powershell -NoProfile -ExecutionPolicy Bypass -File tools\automation\waker-persist-hook-selftest.ps1 | Select-Object -Last 3
'SWAPPED: live hook is now PI-51 + PI-62; backup at C:\KenshiTestRuns\backup\kenshi-waker-guard.ps1.pre-pi62 (rollback: copy it back over the hook)'
