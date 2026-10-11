# tdr-handled.ps1 (dot-source): the newest GPU-reset event epoch already handled on a rig, shared by every lane of that rig
# (speed-scout 2026-10-11: lane A 17:28 and 5090c 17:30 re-tripped on the 17:11 event 1791760268 after a restart because
# their TDR guards looked at events since the re-adopted <rig>.cur batch start, which was before the already alerted event).
# Handled = max of runner\<rig>.tdr-handled (written by rig-runner / rig-lane2 / rig-lane2-4080 when they alert, and by
# tdr-watch) and gpulog\tdrwatch.<rig>.last (every event <= it was alerted by tdr-watch, or there was none).
# A guard looks only at events newer than this; an ALERT file that exists still stops the lane by itself (the human gate).
# Lanes 5090b/5090c/4080b map to their rig (same GPU, same System log).
function TdrRigOf([string]$lane) { $lane -replace '[a-z]+$', '' }
function TdrHandledGet([string]$lane, [string]$rd = 'C:\KenshiTestRuns\runner', [string]$gd = 'C:\KenshiTestRuns\gpulog') {
    $r = TdrRigOf $lane; $m = [long]0
    foreach ($f in @((Join-Path $rd "$r.tdr-handled"), (Join-Path $gd "tdrwatch.$r.last"))) {
        if (-not (Test-Path $f)) { continue }
        $v = "$((Get-Content $f -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -split '\s+' | Select-Object -First 1
        if ($v -match '^\d+$' -and [long]$v -gt $m) { $m = [long]$v }
    }
    $m
}
function TdrHandledSet([string]$lane, [long]$epoch, [string]$why, [string]$rd = 'C:\KenshiTestRuns\runner') {
    $f = Join-Path $rd "$(TdrRigOf $lane).tdr-handled"
    $cur = if (Test-Path $f) { $v = "$((Get-Content $f -TotalCount 1 -ErrorAction SilentlyContinue))".Trim() -split '\s+' | Select-Object -First 1; if ($v -match '^\d+$') { [long]$v } else { 0 } } else { 0 }
    if ($epoch -le $cur) { return }
    Set-Content $f "$epoch $($why -replace '\s+', '_') $(Get-Date -Format s) $lane"
}
# newest epoch among "epoch|provider|id|msg" lines (0 = none)
function TdrNewest([string[]]$lines) { $m = [long]0; foreach ($l in $lines) { if ("$l" -match '^(\d+)\|' -and [long]$Matches[1] -gt $m) { $m = [long]$Matches[1] } }; $m }
# TdrHandledSelfTest <filter scriptblock>: fixed cases in a temp dir; returns "ok|FAIL <case>" lines (rig-runner -SelfTest)
function TdrHandledSelfTest([scriptblock]$filter) {
    $d = Join-Path ([IO.Path]::GetTempPath()) "tdrh-$PID"; New-Item -ItemType Directory -Force $d | Out-Null
    try {
        $o = @()
        function C($name, $got, $want) { if ("$got" -eq "$want") { "ok   tdr-handled $name" } else { "FAIL tdr-handled $name : got '$got' want '$want'" } }
        $o += C 'no files = 0' (TdrHandledGet '5090' $d $d) 0
        TdrHandledSet '5090' 1791760268 'test' $d; $o += C 'set by lane A' (TdrHandledGet '5090' $d $d) 1791760268
        $o += C 'lane 5090c reads the rig file' (TdrHandledGet '5090c' $d $d) 1791760268
        TdrHandledSet '5090b' 1791760000 'older' $d; $o += C 'older value never lowers it' (TdrHandledGet '5090' $d $d) 1791760268
        $o += C '4080 separate' (TdrHandledGet '4080b' $d $d) 0
        Set-Content (Join-Path $d 'tdrwatch.4080.last') '1791761937 checked 2026-10-11T17:39:58'; $o += C 'tdr-watch last counts' (TdrHandledGet '4080b' $d $d) 1791761937
        $o += C 'newest of event lines' (TdrNewest @('1791760268|nvlddmkm|153|a', 'junk', '1791760300|Display|4101|b')) 1791760300
        # 17:28 re-trip: re-adopted batch started 17:05 (t0e 1791759900), the 17:11 event already handled -> no hit; a later one -> hit
        $ev = @('1791760268|nvlddmkm|153|old')
        $ts = [Math]::Max(1791759900, (TdrHandledGet '5090' $d $d) + 1)
        $o += C 'old handled event: no re-trip' (@(& $filter $ev $ts).Count) 0
        $o += C 'new event after it: trips' (@(& $filter ($ev + '1791760400|nvlddmkm|153|new') $ts).Count) 1
        $o
    } finally { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
}
