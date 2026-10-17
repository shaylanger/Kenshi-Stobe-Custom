# snag-scan.ps1 (PI-49): read-only counter over C:\KenshiTestRuns\snags\snags.log (lines written by snag.ps1 / snag.sh).
#   snag-scan.ps1 [-Runs <dir>] [-DryRun]      prints zero or more event lines, nothing else on stdout
#   SNAG REPEAT <key> by <op1>,<op2>[,...]: <symptom> | workaround: <w> | propose root fix
# Key = lowercase basename(script):line, so 'tools/automation/hxdefs.sh:30' and 'hxdefs.sh:30' group. Counts DISTINCT operators
# (case-insensitive). An event fires when the distinct-operator count of a key is >= 2 and greater than the count already recorded in
# <runs>\snags\emitted.txt (lines 'key<TAB>n'), i.e. once at the 2nd operator, again only when a 3rd (4th ...) operator hits it.
# -DryRun does not write emitted.txt. The log is only read (shared read, so a concurrent append is fine); malformed lines are ignored.
# Importable by call: `& snag-scan.ps1 -Runs $dir` from coord-chores.ps1 (do NOT dot-source: the param block would overwrite $Runs/$DryRun there).
param([string]$Runs = '', [switch]$DryRun)
if (-not $Runs) { $Runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' } }
$dir = Join-Path $Runs 'snags'
$log = Join-Path $dir 'snags.log'
$emitted = Join-Path $dir 'emitted.txt'
if (-not (Test-Path -LiteralPath $log)) { return }
function Read-Shared([string]$p) {
    $fs = $null; $sr = $null
    try {
        $fs = New-Object IO.FileStream($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $sr = New-Object IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
        $t = $sr.ReadToEnd()
        return ,@($t -split "`r?`n")
    } catch { return ,@() } finally { if ($sr) { $sr.Dispose() } elseif ($fs) { $fs.Dispose() } }
}
$groups = [ordered]@{}   # key -> @{ ops = ordered list; sym; wk }
foreach ($l in (Read-Shared $log)) {
    if ($l -notmatch '^SNAG\s+(\S+)\s+op=(\S+)\s+(.+?)\s+\|\s+workaround:\s*(.*)$') { continue }
    $sl = $Matches[1]; $op = $Matches[2].ToLowerInvariant(); $sym = $Matches[3]; $wk = $Matches[4].Trim()
    if ($sl -notmatch '^([^:]+):([^:]+)$') { continue }
    $sname = ($Matches[1]).Replace([string][char]92, '/'); $sname = $sname.Substring($sname.LastIndexOf('/') + 1).ToLowerInvariant()
    if (-not $sname) { continue }
    $key = $sname + ':' + $Matches[2].ToLowerInvariant()
    if (-not $groups.Contains($key)) { $groups[$key] = @{ ops = New-Object System.Collections.Generic.List[string]; sym = ''; wk = '' } }
    $g = $groups[$key]
    if (-not $g.ops.Contains($op)) { $g.ops.Add($op) }
    $g.sym = $sym; if ($wk -and $wk -ne 'none') { $g.wk = $wk } elseif (-not $g.wk) { $g.wk = 'none' }
}
$done = @{}
foreach ($l in (Read-Shared $emitted)) {
    if ($l -match '^(\S+)\t(\d+)\s*$') { $n = [int]$Matches[2]; if (-not $done.ContainsKey($Matches[1]) -or $done[$Matches[1]] -lt $n) { $done[$Matches[1]] = $n } }
}
function Cut([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }
foreach ($key in $groups.Keys) {
    $g = $groups[$key]; $n = $g.ops.Count
    $prev = if ($done.ContainsKey($key)) { $done[$key] } else { 0 }
    if ($n -lt 2 -or $n -le $prev) { continue }
    "SNAG REPEAT $key by $($g.ops -join ','): $(Cut $g.sym 140) | workaround: $(Cut $g.wk 140) | propose root fix"
    if (-not $DryRun) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            [IO.File]::AppendAllText($emitted, "$key`t$n`n", (New-Object System.Text.UTF8Encoding($false)))
        } catch { }
    }
}
