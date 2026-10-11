# gpulog-state.ps1 (4080, C:\KAH): one line "STATE <pid> <alive True|False> <age s of the newest csv, -1 none> <csv name>" (gpulog-ensure.ps1)
$l = 'C:\KenshiTestRuns\gpulog\4080.pid'; $p = $null
if (Test-Path $l) { $p = Get-Content $l | Select-Object -First 1 }
$a = [bool]($p -and (Get-Process -Id $p -ErrorAction SilentlyContinue))
$f = Get-ChildItem C:\KenshiTestRuns\gpulog -Filter '4080-*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$g = if ($f) { [int]((Get-Date) - $f.LastWriteTime).TotalSeconds } else { -1 }
'STATE {0} {1} {2} {3}' -f $(if ($p) { $p } else { 0 }), $a, $g, $(if ($f) { $f.Name } else { '-' })
