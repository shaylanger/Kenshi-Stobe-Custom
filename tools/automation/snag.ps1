# snag.ps1 (PI-49): record one tooling snag so a repeat by a second operator becomes a coordinator event.
#   snag.ps1 <operator> <script:line> "<symptom>" "<workaround>"
# Appends ONE line to C:\KenshiTestRuns\snags\snags.log (env KAH_RUNS_DIR overrides the root):
#   SNAG <script:line> op=<operator> <symptom> | workaround: <workaround>
# snag-scan.ps1 (called by the chores waker) counts DISTINCT operators per normalized script:line and emits one
# 'SNAG REPEAT ...' line at the 2nd distinct operator (again only when a further distinct operator hits it).
# Never fails the caller's work: bad usage prints a warning and exits 2 without writing. Bash twin: snag.sh.
param(
    [Parameter(Position = 0)][string]$Operator = '',
    [Parameter(Position = 1)][string]$ScriptLine = '',
    [Parameter(Position = 2)][string]$Symptom = '',
    [Parameter(Position = 3)][string]$Workaround = ''
)
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
function Clean([string]$s, [int]$max) { $s = ($s -replace '[\r\n\t]+', ' ' -replace '\|', '/').Trim(); if ($s.Length -gt $max) { $s = $s.Substring(0, $max) }; $s }
$op = (Clean $Operator 40) -replace '\s+', '_'
$sl = (Clean $ScriptLine 80) -replace '\s+', ''
if (-not $op -or $sl -notmatch '^[^:\s]+:[^:\s]+$' -or -not $Symptom.Trim()) {
    [Console]::Error.WriteLine('usage: snag.ps1 <operator> <script:line> "<symptom>" "<workaround>"  (script:line like hxdefs.sh:30)'); exit 2
}
$sym = Clean $Symptom 200
$wk = Clean $Workaround 200; if (-not $wk) { $wk = 'none' }
$dir = Join-Path $runs 'snags'
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$line = "SNAG $sl op=$op $sym | workaround: $wk`n"
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($line)
$fs = $null
try {
    $fs = New-Object IO.FileStream((Join-Path $dir 'snags.log'), [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    $fs.Write($bytes, 0, $bytes.Length)
} finally { if ($fs) { $fs.Dispose() } }
Write-Output "snag recorded: $sl by $op"
