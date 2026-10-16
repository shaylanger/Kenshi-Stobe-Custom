# session-start-budget.ps1: output budget for `session-start.ps1 -Brief` (PI-07, Shay 2026-10-15).
# Dot-source it, then:  Limit-BriefOutput -Lines <string[]> [-MaxBytes 12288]
# Sections start at lines "=== ...", "WAKER STATUS", "PROCESS IDEAS FOR SHAY". Each section has a line cap and a per-line
# character cap; lines over the cap are dropped and replaced by "  (N more; run without -Brief)". If the whole output is still
# over the budget the caps are scaled down in steps. MUST-KEEP lines are never dropped, never cut, never counted against a cap:
# WAKER STATUS, ORPHANED, NO SUCCESSOR, DEAD, OWNED-BY-LIVE-TAIL, TAIL, PROCESS IDEAS FOR SHAY (+ its entries), WARNING/ALERT/HEALTH STALL,
# respawn todos, the final Next: line, SETUP-FAIL ticket lines (session-start caps them at 12). Empty sections (header only) are omitted.
$script:BriefMustKeep = '^WAKER STATUS|\bORPHANED\b|\bNO SUCCESSOR\b|^DEAD |^\s*DEAD |OWNED-BY-LIVE-TAIL|^TAIL |^COORDINATOR POINTER|^\s+tail \S+: relays |^PROCESS IDEAS FOR SHAY|^\s+PI-\d+ |^\s+\(after asking|^WARNING|^ALERT|HEALTH STALL|LANE STUCK|^respawn todos|^Next:|^  \S+ age=\S+ needs=\S+ owner='
# section-header substring -> @(max non-must-keep lines, max chars per line)
$script:BriefCaps = [ordered]@{
    'PROGRAM LEDGER'  = @(10, 300)
    'SETUP-FAIL TICKETS' = @(14, 160)
    'handoff.ready'   = @(6, 300)
    'HANDOFF.md'      = @(8, 450)
    'agents (C:'      = @(14, 190)
    'agent health'    = @(8, 400)
    'roll call'       = @(10, 250)
    'in flight'       = @(14, 250)
    'stale test'      = @(6, 200)
    'WSL services'    = @(3, 200)
    'review verdicts' = @(5, 200)
    'tail sessions'   = @(6, 300)
    'ledger agents'   = @(6, 300)
}
function Get-BriefCap([string]$header) {
    foreach ($k in $script:BriefCaps.Keys) { if ($header.Contains($k)) { return $script:BriefCaps[$k] } }
    return @(12, 300)
}
function Format-BriefSections($sections, [double]$scale) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in $sections) {
        $cap = Get-BriefCap $s.Header
        $maxLines = [Math]::Max(1, [int][Math]::Floor($cap[0] * $scale))
        $maxChars = [Math]::Max(80, [int][Math]::Floor($cap[1] * [Math]::Max($scale, 0.5)))
        $kept = 0; $dropped = 0
        $body = New-Object System.Collections.Generic.List[string]
        foreach ($l in $s.Lines) {
            if ($l -cmatch $script:BriefMustKeep) { $body.Add($l); continue }
            if ($l.Trim() -eq '') { continue }
            if ($kept -lt $maxLines) { $kept++; $body.Add($(if ($l.Length -gt $maxChars) { $l.Substring(0, $maxChars) + '...' } else { $l })) } else { $dropped++ }
        }
        if ($dropped) { $body.Add("  ($dropped more; run without -Brief)") }
        if (-not $body.Count -and $s.Header -notmatch $script:BriefMustKeep) { continue }   # empty section: omit
        if ($s.Header) { $out.Add($(if ($s.Header -cmatch $script:BriefMustKeep -or $s.Header.Length -le 120) { $s.Header } else { $s.Header.Substring(0, 117) + '...' })) }
        $body | ForEach-Object { $out.Add($_) }
    }
    return $out
}
function Limit-BriefOutput {
    param([string[]]$Lines, [int]$MaxBytes = 12288)
    $sections = New-Object System.Collections.Generic.List[object]
    $cur = [pscustomobject]@{ Header = ''; Lines = (New-Object System.Collections.Generic.List[string]) }
    foreach ($l in $Lines) {
        if ($l -match '^(=== |WAKER STATUS|PROCESS IDEAS FOR SHAY|Next:)') {
            if ($cur.Header -or $cur.Lines.Count) { $sections.Add($cur) }
            $cur = [pscustomobject]@{ Header = $l; Lines = (New-Object System.Collections.Generic.List[string]) }
        } else { $cur.Lines.Add($l) }
    }
    if ($cur.Header -or $cur.Lines.Count) { $sections.Add($cur) }
    $res = $null
    foreach ($scale in 1.0, 0.75, 0.5, 0.35, 0.2, 0.0) {
        $res = Format-BriefSections $sections $scale
        if ([Text.Encoding]::UTF8.GetByteCount(($res -join "`n")) -le $MaxBytes) { break }
    }
    return $res
}
