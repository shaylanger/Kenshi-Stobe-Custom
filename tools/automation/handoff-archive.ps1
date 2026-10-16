# handoff-archive.ps1 (PI-08, Shay 2026-10-15): keep testing/HANDOFF.md short. Moves OLD "Right now" entries (verbatim, in order)
# to archive/HANDOFF_history_<date>.md. Idempotent: a second run finds nothing to move and writes nothing.
#
#   handoff-archive.ps1 [-File <HANDOFF.md>] [-ArchiveDir <dir>] [-Date yyyy-MM-dd] [-Current N] [-Keep 2]
#                       [-ArchivePattern <one regex, use | for alternatives>] [-Sections] [-DryRun]
#
# Rules (the "## Right now" anchor line itself, the preamble above it, and every heading line used by session-start.ps1 / handoff-ready.ps1 stay):
#  * A "Right now" entry = a block of lines up to the next blank line. Its coordinator number = the number in its first line
#    (`COORDINATOR #N ...`, `**#N later:**`, `**18:xx #N (...`). Current = the highest `COORDINATOR #N` found (or -Current). Entries numbered
#    below Current-Keep+1 move to the archive (default -Keep 2 = keep the current and the previous coordinator).
#  * Entries with NO number stay (they may be fresh text from a concurrent agent) unless their first line matches an -ArchivePattern regex.
#  * -Sections (one-time cleanup): also move whole sections after "Right now" whose heading matches the historical regex below (and not the standing-keep regex).
#  * Concurrent appends: the file is read, the new text computed and written in one quick step; if the file changed in between (length/mtime), it is
#    recomputed from the new content, so a line appended by another agent is never lost.
# New entries: add them at the TOP of "## Right now" with "COORDINATOR #N ..." in the first line so they are archived on schedule.
param(
    [string]$File = 'C:\KenshiModding\testing\HANDOFF.md',
    [string]$ArchiveDir = 'C:\KenshiModding\archive',
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
    [int]$Current = 0,
    [int]$Keep = 2,
    [string]$ArchivePattern = '',
    [switch]$Sections,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$secArchive = '(?i)historical|superseded|checkpoint|snapshot|correction|update|milestone|audit findings|issue inventory|candidate|smoke|persistent queue|refresh|staging|follow-up|route'
$secKeep = '(?i)standing rules|test efficiency|how to run|gotchas|next work|status per mod|builds installed|the mods and|^#{1,6} right now'
$numRx = '^\s*(?:\*\*)?\s*(?:COORDINATOR[^*\r\n]{0,40}?#(\d+)|[^*\r\n]{0,20}?#(\d+)\b)'

function Get-Plan([string]$text) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $endsNl = $text.EndsWith("`n")
    $lines = @($text -split "`r?`n"); if ($endsNl -and $lines.Count -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
    $rn = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -like '## Right now*') { $rn = $i; break } }
    if ($rn -lt 0) { return [pscustomobject]@{ ok = $false; why = 'no "## Right now" anchor'; nl = $nl } }
    # flat sections: [start, end) between heading lines
    $heads = @(); for ($i = $rn; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,6} ') { $heads += $i } }
    $bodyEnd = if ($heads.Count -gt 1) { $heads[1] } else { $lines.Count }
    # blocks inside the Right now body
    $blocks = @(); $s = $rn + 1
    while ($s -lt $bodyEnd) {
        while ($s -lt $bodyEnd -and $lines[$s].Trim() -eq '') { $s++ }   # leading blanks stay with the previous block / heading
        if ($s -ge $bodyEnd) { break }
        $e = $s; while ($e -lt $bodyEnd -and $lines[$e].Trim() -ne '') { $e++ }
        while ($e -lt $bodyEnd -and $lines[$e].Trim() -eq '') { $e++ }   # trailing blanks belong to the block
        $m = [regex]::Match($lines[$s], $numRx)
        $n = $null; if ($m.Success) { $n = if ($m.Groups[1].Success) { [int]$m.Groups[1].Value } else { [int]$m.Groups[2].Value } }
        $blocks += [pscustomobject]@{ start = $s; end = $e; num = $n; first = $lines[$s]; coord = ($lines[$s] -match 'COORDINATOR[^*\r\n]{0,40}?#\d+') }
        $s = $e
    }
    $cur = $Current
    if ($cur -le 0) { foreach ($b in $blocks) { if ($b.coord -and $b.num -gt $cur) { $cur = $b.num } } }
    $thr = $cur - $Keep + 1
    $move = New-Object 'System.Collections.Generic.List[object]'
    foreach ($b in $blocks) {
        $old = ($null -ne $b.num -and $cur -gt 0 -and $b.num -lt $thr)
        if (-not $old -and $ArchivePattern -and $b.first -match $ArchivePattern) { $old = $true }
        if ($old) { $move.Add([pscustomobject]@{ start = $b.start; end = $b.end; why = "block $($b.num) $($b.first.Substring(0, [Math]::Min(50, $b.first.Length)))" }) }
    }
    if ($Sections) {
        for ($k = 1; $k -lt $heads.Count; $k++) {
            $h = $lines[$heads[$k]]
            $end = if ($k + 1 -lt $heads.Count) { $heads[$k + 1] } else { $lines.Count }
            if ($h -match $secArchive -and $h -notmatch $secKeep) { $move.Add([pscustomobject]@{ start = $heads[$k]; end = $end; why = "section $($h.Substring(0, [Math]::Min(60, $h.Length)))" }) }
        }
    }
    return [pscustomobject]@{ ok = $true; lines = $lines; nl = $nl; endsNl = $endsNl; rn = $rn; move = $move; cur = $cur; thr = $thr }
}

function Build-Output($plan) {
    $drop = New-Object 'bool[]' $plan.lines.Count
    foreach ($m in $plan.move) { for ($i = $m.start; $i -lt $m.end; $i++) { $drop[$i] = $true } }
    $keepL = New-Object System.Collections.Generic.List[string]; $arch = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $plan.lines.Count; $i++) { if ($drop[$i]) { $arch.Add($plan.lines[$i]) } else { $keepL.Add($plan.lines[$i]) } }
    return [pscustomobject]@{ keep = $keepL; arch = $arch }
}

$attempt = 0
while ($true) {
    $attempt++
    if ($attempt -gt 6) { throw 'HANDOFF.md kept changing while archiving (6 attempts); nothing written' }
    $fi = Get-Item -LiteralPath $File
    $len0 = $fi.Length; $mt0 = $fi.LastWriteTimeUtc
    $text = [IO.File]::ReadAllText($File, $utf8)
    $plan = Get-Plan $text
    if (-not $plan.ok) { "handoff-archive: $($plan.why); nothing done"; exit 0 }
    $out = Build-Output $plan
    $pointer = "Older entries (coordinators before #$($plan.thr), historical snapshots) are archived verbatim in archive/HANDOFF_history_*.md (moved by tools/automation/handoff-archive.ps1). Add new entries at the TOP of this section, first line ``COORDINATOR #N ...``."
    # pointer line: replace an existing one, else insert after the Right now heading
    $keepL = $out.keep
    $pi = -1; for ($i = 0; $i -lt $keepL.Count; $i++) { if ($keepL[$i] -like 'Older entries (coordinators before*') { $pi = $i; break } }
    $changedPointer = $false
    if ($plan.move.Count -gt 0 -or $pi -ge 0) {
        if ($pi -ge 0) { if ($keepL[$pi] -ne $pointer -and $plan.move.Count -gt 0) { $keepL[$pi] = $pointer; $changedPointer = $true } }
        elseif ($plan.move.Count -gt 0) { $r = [array]::FindIndex($keepL.ToArray(), [Predicate[string]] { param($l) $l -like '## Right now*' }); $keepL.Insert($r + 1, ''); $keepL.Insert($r + 2, $pointer); $changedPointer = $true }
    }
    if ($plan.move.Count -eq 0) { "handoff-archive: nothing to archive (current coordinator #$($plan.cur), keeping #$($plan.thr)+); $([Math]::Round($len0 / 1KB, 1)) KB"; exit 0 }
    $movedLines = $out.arch.Count
    $newText = ($keepL -join $plan.nl) + $(if ($plan.endsNl) { $plan.nl } else { '' })
    $chunkHdr = "## Archived $(Get-Date -Format 'yyyy-MM-dd HH:mm') (coordinator #$($plan.cur) handoff; entries before #$($plan.thr) and old snapshot sections, verbatim, original order)"
    $arcFile = Join-Path $ArchiveDir "HANDOFF_history_$Date.md"
    $chunk = ($out.arch -join $plan.nl)
    if ($DryRun) { "handoff-archive DRYRUN: would move $($plan.move.Count) parts / $movedLines lines ($([Math]::Round([Text.Encoding]::UTF8.GetByteCount($chunk) / 1KB, 1)) KB) to $arcFile; live file $([Math]::Round($len0 / 1KB, 1)) KB -> $([Math]::Round([Text.Encoding]::UTF8.GetByteCount($newText) / 1KB, 1)) KB"; $plan.move | ForEach-Object { "  $($_.why)" }; exit 0 }
    # archive first (dedupe by exact chunk), then the live file
    New-Item -ItemType Directory -Force -Path $ArchiveDir | Out-Null
    $existing = if (Test-Path -LiteralPath $arcFile) { [IO.File]::ReadAllText($arcFile, $utf8) } else { "# HANDOFF history archived $Date`n`nMoved verbatim from testing/HANDOFF.md by tools/automation/handoff-archive.ps1 (PI-08). Newer text stays in the live file; older text is also in git history.`n" }
    if (-not $existing.Contains($chunk)) { [IO.File]::WriteAllText($arcFile, $existing.TrimEnd() + $plan.nl + $plan.nl + '---' + $plan.nl + $chunkHdr + $plan.nl + $plan.nl + $chunk + $plan.nl, $utf8) }
    if ($env:HANDOFF_ARCHIVE_TEST_APPEND -and $attempt -eq 1) { [IO.File]::AppendAllText($File, $env:HANDOFF_ARCHIVE_TEST_APPEND + $plan.nl, $utf8) }   # selftest hook: simulate a concurrent append
    $fi2 = Get-Item -LiteralPath $File
    if ($fi2.Length -ne $len0 -or $fi2.LastWriteTimeUtc -ne $mt0) { continue }   # changed meanwhile: recompute from the new content
    [IO.File]::WriteAllText($File, $newText, $utf8)
    $chk = [IO.File]::ReadAllText($File, $utf8)
    if ($chk -ne $newText) { continue }   # someone wrote between our check and our write: recompute from what is there now
    break
}
"handoff-archive: moved $($plan.move.Count) parts / $movedLines lines to $arcFile ; $File $([Math]::Round($len0 / 1KB, 1)) KB -> $([Math]::Round($newText.Length / 1KB, 1)) KB (kept coordinator #$($plan.thr)+, current #$($plan.cur))"
