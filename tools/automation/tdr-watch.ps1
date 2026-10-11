# tdr-watch.ps1 [-Rig 5090|4080|both] [-SelfTest]: always-on TDR watch (coordinator m103 2026-10-11: two nvlddmkm 153 events
# at 16:59 on the 5090 raised no alert because no batch was running; the batch/runner TDR guards only look while a list runs).
# Reads each rig's System log for nvlddmkm/Display 4101|153 since that rig's last check (C:\KenshiTestRuns\gpulog\
# tdrwatch.<rig>.last = epoch of the newest event already handled + the check time; first run = baseline, nothing old is
# re-alerted). A new event: ALERT-<rig>-tdr.txt (kept if one exists, the event appended) + tdr-evidence.ps1 into
# C:\KenshiTestRuns\tdr-<MMdd-HHmm>-<rig>-evidence\ (4080: collected on the 4080, copied back) + a timeline.tsv line.
# Callers: rig-health.sh (every waker) and rig-runner.ps1 (every tick, own rig). A lock file keeps two callers from alerting
# the same event twice. Prints one line per rig only on a hit ("TDR-WATCH <rig> NEW ..."), else nothing (-Show: OK lines).
param([ValidateSet('5090', '4080', 'both')][string]$Rig = 'both', [switch]$SelfTest, [switch]$Show)
$auto = $PSScriptRoot; $runs = 'C:\KenshiTestRuns'; $gd = Join-Path $runs 'gpulog'
New-Item -ItemType Directory -Force $gd | Out-Null
$q = "`$s=[DateTimeOffset]::FromUnixTimeSeconds(SINCE).LocalDateTime; Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,153; StartTime=`$s} -ErrorAction SilentlyContinue | Where-Object { `$_.ProviderName -match '^(nvlddmkm|Display)$' } | ForEach-Object { '{0}|{1}|{2}|{3}' -f ([DateTimeOffset]`$_.TimeCreated).ToUnixTimeSeconds(), `$_.ProviderName, `$_.Id, ((([string]`$_.Message) -replace '\s+',' ') -replace '\|','/') }"

# NewEvents <lines> <lastEpoch>: events strictly newer than the last handled one (pure; -SelfTest)
function NewEvents([string[]]$lines, [long]$last) { @($lines | Where-Object { $_ -match '^(\d+)\|' -and [long]$Matches[1] -gt $last }) }
if ($SelfTest) {
    $bad = 0; $n = 0
    function T($name, $got, $want) { $script:n++; if ("$got" -eq "$want") { "ok   $name" } else { "FAIL $name : got '$got' want '$want'"; $script:bad++ } }
    $ev = @('1000|nvlddmkm|153|x', '1010|Display|4101|y', '990|nvlddmkm|153|old')
    T 'new events after 995' ((NewEvents $ev 995).Count) 2
    T 'the handled one is not new again' ((NewEvents $ev 1010).Count) 0
    T 'garbage lines ignored' ((NewEvents @('', 'WARNING x', '1020|nvlddmkm|153|z') 1010).Count) 1
    "TDRWATCH-SELFTEST $(if ($bad) { "FAIL $bad" } else { 'PASS' }) $n cases"; exit ([int]($bad -gt 0))
}

$lockF = Join-Path $gd 'tdrwatch.lock'
$lk = $null
for ($i = 0; $i -lt 40 -and -not $lk; $i++) { try { $lk = [IO.File]::Open($lockF, 'OpenOrCreate', 'ReadWrite', 'None') } catch { Start-Sleep -Milliseconds 250 } }
if (-not $lk) { exit 0 }   # another watch runs right now: it handles the same events
try {
    foreach ($r in $(if ($Rig -eq 'both') { @('5090', '4080') } else { @($Rig) })) {
        $sf = Join-Path $gd "tdrwatch.$r.last"; $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $last = if (Test-Path $sf) { [long](((Get-Content $sf -Raw) -split '\s+')[0]) } else { -1 }
        if ($last -lt 0) { Set-Content $sf "$now baseline $(Get-Date -Format s)"; if ($Show) { "TDR-WATCH $r baseline" }; continue }
        # an event a runner/lane guard already alerted (runner\<rig>.tdr-handled, tdr-handled.ps1) is not alerted a second time
        $rh = Join-Path $runs "runner\$r.tdr-handled"
        if (Test-Path $rh) { $v = "$((Get-Content $rh -TotalCount 1))".Trim() -split '\s+' | Select-Object -First 1; if ($v -match '^\d+$' -and [long]$v -gt $last) { $last = [long]$v } }
        $cmd = $q -replace 'SINCE', "$($last - 5)"
        $lines = if ($r -eq '5090') { @(& ([scriptblock]::Create($cmd)) | ForEach-Object { "$_" }) }
                 else { $o = @(& ssh -o ConnectTimeout=10 -o BatchMode=yes 4080 "powershell -NoProfile -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("$cmd; exit 0")))" 2>$null | ForEach-Object { "$_" }); if ($LASTEXITCODE -ne 0) { if ($Show) { "TDR-WATCH 4080 unreachable" }; continue }; $o }
        $new = @(NewEvents $lines $last)
        if (-not $new.Count) {   # keep the query window short: checked up to a minute ago (late-logged events: 60 s + 5 s overlap)
            if ($now - 60 -gt $last) { Set-Content $sf "$($now - 60) checked $(Get-Date -Format s)" }
            if ($Show) { "TDR-WATCH $r OK (since $last)" }; continue }
        $newest = ($new | ForEach-Object { [long](($_ -split '\|')[0]) } | Measure-Object -Maximum).Maximum
        $stamp = Get-Date -Format 'MMdd-HHmm'
        $evd = Join-Path $runs "tdr-$stamp-$r-evidence"
        $desc = "$($new.Count) GPU event(s) on rig $r outside/inside a batch, latest: $(($new | Sort-Object | Select-Object -Last 1).Substring(0, [Math]::Min(200, ($new | Sort-Object | Select-Object -Last 1).Length)))"
        $af = Join-Path $runs "ALERT-$r-tdr.txt"
        if (Test-Path $af) { Add-Content $af "tdr-watch $(Get-Date -Format HH:mm): $desc (evidence $evd)" }
        else { Set-Content $af @("ALERT $r $(Get-Date -Format HH:mm) TDR watch: $desc", "Evidence: $evd. A TDR is a crash warning (2026-10-11 BSOD): stop that rig's GPU work, tell Shay; delete this file only once he cleared the cause.") }
        Set-Content $sf "$newest handled $(Get-Date -Format s)"
        if ($r -eq '5090') { $ev = & powershell -NoProfile -ExecutionPolicy Bypass -File "$auto\tdr-evidence.ps1" -Out $evd -Rig 5090 -Minutes 8 2>&1 | Select-Object -Last 1 }
        else {
            $ev = & ssh 4080 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\tdr-evidence.ps1 -Out C:\KenshiTestRuns\tdr-$stamp-4080-evidence -Rig 4080 -Minutes 8" 2>&1 | Select-Object -Last 1
            & scp -q -r "4080:C:/KenshiTestRuns/tdr-$stamp-4080-evidence" "$runs\" 2>&1 | Out-Null
        }
        Add-Content (Join-Path $gd 'timeline.tsv') ("{0}`t{1}`twatch`ttdr`t{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $r, $desc)
        "TDR-WATCH $r NEW $desc -> $af, $ev"
    }
} finally { $lk.Close() }
