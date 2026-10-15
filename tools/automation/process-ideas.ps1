# process-ideas.ps1: the PROCESS IDEAS review kept at every coordinator handoff (Shay 2026-10-15): ideas that make the process faster or
# cheaper are RECORDED in docs/PROCESS_IDEAS.md, asked to Shay once in the new coordinator's first summary, never applied by this tool.
#   process-ideas.ps1 list [-All]                       open/asked/confirmed entries, one short line each (id, idea, evidence, flag); -All adds rejected + Retired
#   process-ideas.ps1 add -Idea .. -Evidence .. -Saving .. -Risk .. -Hooks yes|no [-Weakens yes|no]
#                                                       refuses at 10 active (open|asked|confirmed) entries, warns from 8, needs a concrete evidence text
#   process-ideas.ps1 review <decisions.json>           the handoff review (see below); prints one line per transition
#   process-ideas.ps1 asked <id> [<id>..]               open -> asked (the coordinator asked Shay in its first summary)
#   process-ideas.ps1 answer <id> no|yes|approve        Shay's answer: no = removed (logged in Retired); yes/approve = confirmed
#   process-ideas.ps1 done <id> -Measured "<before/after>"   idea built: moves to Retired as done with the measured numbers
# decisions.json: { "review": "<label, optional>", "decisions": [ { "id": "PI-06", "applies": true|false, "evidence": "<what happened THIS session>",
#                   "moment": "<specific moment it would have helped; required for confirmed>" } ], "new": [ { idea, evidence, saving, risk, hooks, weakens } ] }
# Transitions (ONE step per entry per handoff; silence, or a decision without evidence, = unchanged):
#   open|asked + not apply -> rejected x1 | rejected x1 + not apply -> rejected x2 | rejected x2 + not apply -> removed (Retired)
#   rejected x1 + applies -> open | rejected x2 + applies -> rejected x1 | open|asked + applies + moment -> confirmed (applies without moment: unchanged)
# New entries: at most 3 per review, each with concrete evidence, never above the 10-active cap (resolve/retire one first).
# GUARD: an idea that would weaken a timeout, stall catch, idle catch or dead-agent catch is refused unless it carries hooks=yes
# ("touches hooks/settings"); then it is recorded with weakens=yes and listed as FOR SHAY ONLY. Nothing here edits hooks or settings.
# Test switch: env KAH_PROCESS_IDEAS (file), or -File. Selftest: process-ideas-selftest.ps1. Exit 0 ok, 2 refused/bad input.
param(
    [Parameter(Position = 0)][string]$Command = 'list',
    [Parameter(Position = 1)][string]$Arg1 = '',
    [Parameter(Position = 2)][string]$Arg2 = '',
    [Parameter(Position = 3, ValueFromRemainingArguments = $true)][string[]]$More,
    [string]$Idea = '', [string]$Evidence = '', [string]$Saving = '', [string]$Risk = '',
    [string]$Hooks = '', [string]$Weakens = '', [string]$Measured = '',
    [string]$File = '',
    [switch]$All
)
$ErrorActionPreference = 'Stop'
$CAP = 10; $WARN_AT = 8; $MAX_NEW = 3
if (-not $File) { $File = if ($env:KAH_PROCESS_IDEAS) { $env:KAH_PROCESS_IDEAS } else { 'C:\KenshiModding\docs\PROCESS_IDEAS.md' } }
function Fail([string]$m) { [Console]::Error.WriteLine("process-ideas: $m"); exit 2 }
function One([string]$s) { ("$s" -replace '[\r\n]+', ' ').Trim() }

$WEAKEN_RX = '(?i)(weaken|relax|disable|remove|skip|raise|increase|lengthen|extend|loosen|suppress|drop|ignore|turn off|silence|mute|bypass|longer)\w*\b.{0,70}\b(timeout|stall|idle|dead[- ]agent|orphan|watchdog|monitor|heartbeat|waker|stop hook|guard)'

# ---- parse / write ----
function Read-Ideas([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "no ideas file $path" }
    $pre = New-Object System.Collections.ArrayList; $act = New-Object System.Collections.ArrayList; $ret = New-Object System.Collections.ArrayList
    $sec = 'pre'; $cur = $null
    foreach ($l in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ($l -match '^## Active\s*$') { $sec = 'act'; $cur = $null; continue }
        if ($l -match '^## Retired\s*$') { $sec = 'ret'; $cur = $null; continue }
        if ($sec -eq 'pre') { [void]$pre.Add($l); continue }
        if ($l -match '^### (PI-\d+)\s*\|\s*(.+?)\s*$') {
            $cur = [ordered]@{ id = $Matches[1]; status = $Matches[2]; log = New-Object System.Collections.ArrayList }
            if ($sec -eq 'act') { [void]$act.Add($cur) } else { [void]$ret.Add($cur) }
            continue
        }
        if ($cur -and $l -match '^- ([A-Za-z_]+):\s?(.*)$') {
            if ($Matches[1] -eq 'log') { [void]$cur.log.Add($Matches[2]) } else { $cur[$Matches[1]] = $Matches[2] }
        }
    }
    [pscustomobject]@{ pre = $pre; act = $act; ret = $ret }
}
function Entry-Lines($e) {
    $o = New-Object System.Collections.ArrayList
    [void]$o.Add("### $($e.id) | $($e.status)")
    foreach ($k in $e.Keys) { if ($k -in 'id', 'status', 'log') { continue }; [void]$o.Add("- ${k}: $($e[$k])") }
    foreach ($g in $e.log) { [void]$o.Add("- log: $g") }
    [void]$o.Add('')
    $o
}
function Write-Ideas([string]$path, $db) {
    $out = New-Object System.Collections.ArrayList
    foreach ($l in $db.pre) { [void]$out.Add($l) }
    [void]$out.Add('## Active'); [void]$out.Add('')
    foreach ($e in $db.act) { foreach ($l in (Entry-Lines $e)) { [void]$out.Add($l) } }
    [void]$out.Add('## Retired'); [void]$out.Add('')
    foreach ($e in $db.ret) { foreach ($l in (Entry-Lines $e)) { [void]$out.Add($l) } }
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, (($out -join "`n").TrimEnd() + "`n"), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Is-Active($e) { $e.status -in 'open', 'asked', 'confirmed' }
function Active-Count($db) { @($db.act | Where-Object { Is-Active $_ }).Count }
function Next-Id($db) {
    $max = 0
    foreach ($e in @($db.act) + @($db.ret)) { if ($e.id -match '(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) } }
    'PI-{0:00}' -f ($max + 1)
}
function Find-Entry($db, [string]$id) { foreach ($e in $db.act) { if ($e.id -eq $id) { return $e } } $null }
function Retire($db, $e, [string]$status, [string]$why) {
    $db.act.Remove($e)
    $e.status = $status; $e['retired'] = "$(Get-Date -Format 'yyyy-MM-dd') $why"
    [void]$db.ret.Add($e)
}
function Stamp { Get-Date -Format 'yyyy-MM-dd HH:mm' }

# Validates + builds a new entry from a hashtable-like object; returns @{ entry=..; err=.. }
function New-EntryFrom($db, $src) {
    $idea = One $src.idea; $ev = One $src.evidence; $sv = One $src.saving; $rk = One $src.risk
    $hk = (One $src.hooks).ToLower(); $wk = (One $src.weakens).ToLower()
    if (-not $idea) { return @{ err = 'idea is required' } }
    if ($ev.Length -lt 25) { return @{ err = "evidence needs a concrete example from this session (what happened and what it cost), got '$ev'" } }
    if (-not $sv) { return @{ err = 'expected saving is required' } }
    if (-not $rk) { return @{ err = 'risk to monitoring / stall / idle / dead-agent catches is required (write "none" only if true)' } }
    if ($hk -notin 'yes', 'no') { return @{ err = 'hooks must be yes or no (does the idea touch hooks/settings?)' } }
    if ($wk -and $wk -notin 'yes', 'no') { return @{ err = 'weakens must be yes or no' } }
    $weak = ($wk -eq 'yes') -or ($idea -match $WEAKEN_RX) -or ($sv -match $WEAKEN_RX)
    if ($weak -and $hk -ne 'yes') { return @{ err = "GUARD: the idea would weaken a timeout/stall/idle/dead-agent catch; refused unless it carries hooks=yes (touches hooks/settings) and is for Shay only" } }
    $e = [ordered]@{ id = (Next-Id $db); status = 'open'; log = New-Object System.Collections.ArrayList }
    $e['idea'] = $idea; $e['evidence'] = $ev; $e['saving'] = $sv; $e['risk'] = $rk
    $e['hooks'] = $hk; $e['weakens'] = $(if ($weak) { 'yes' } else { 'no' })
    if ($weak) { $e['for_shay'] = 'yes: weakens a monitoring catch; only Shay can approve, never build on a coordinator decision' }
    $e['added'] = Stamp
    @{ entry = $e }
}
function Cut([string]$s, [int]$n) { if ($s.Length -gt $n) { $s.Substring(0, $n - 3) + '...' } else { $s } }
function Flag($e) {
    $f = @()
    if ($e.hooks -eq 'yes') { $f += 'touches hooks/settings' }
    if ($e.weakens -eq 'yes') { $f += 'WEAKENS MONITORING: FOR SHAY ONLY' }
    if ($f.Count) { ' [' + ($f -join '; ') + ']' } else { '' }
}

$db = Read-Ideas $File
switch ($Command.ToLower()) {
    'list' {
        $rows = @($db.act | Where-Object { $All -or (Is-Active $_) })
        if (-not $rows.Count) { 'none'; break }
        foreach ($e in $rows) { "$($e.id) [$($e.status)] $(Cut $e.idea 100) | evidence: $(Cut $e.evidence 150)$(Flag $e)" }
        if ($All) { foreach ($e in $db.ret) { "$($e.id) [$($e.status)] $(Cut $e.idea 80)$(if ($e.measured) { ' | measured: ' + (Cut $e.measured 120) })" } }
    }
    'add' {
        $n = Active-Count $db
        if ($n -ge $CAP) { Fail "REFUSED: $n active entries (cap $CAP). Resolve or retire one first (review / answer / done)." }
        $r = New-EntryFrom $db @{ idea = $Idea; evidence = $Evidence; saving = $Saving; risk = $Risk; hooks = $Hooks; weakens = $Weakens }
        if ($r.err) { Fail "REFUSED: $($r.err)" }
        [void]$db.act.Add($r.entry); Write-Ideas $File $db
        "added $($r.entry.id)"
        if ($n + 1 -ge $WARN_AT) { "WARNING: $($n + 1) of $CAP active entries; retire one before the next handoff" }
    }
    'review' {
        if (-not $Arg1 -or -not (Test-Path -LiteralPath $Arg1)) { Fail 'usage: review <decisions.json>' }
        try { $dj = Get-Content -LiteralPath $Arg1 -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Fail "bad json: $($_.Exception.Message)" }
        $label = if ($dj.review) { "$($dj.review)" } else { Stamp }
        $seen = @{}
        foreach ($d in @($dj.decisions)) {
            if (-not $d -or -not $d.id) { continue }
            $id = "$($d.id)"
            $e = Find-Entry $db $id
            if (-not $e) { "SKIP $id : not an active entry"; continue }
            if ($seen[$id]) { "SKIP $id : second decision in the same review (one step per handoff)"; continue }
            $seen[$id] = $true
            if ($e['last_review'] -eq $label) { "SKIP $id : already stepped in review '$label'"; continue }
            $ev = One $d.evidence
            if ($ev.Length -lt 15) { "UNCHANGED $id [$($e.status)] : decision without evidence from this session counts as silence"; continue }
            $applies = [bool]$d.applies
            $from = $e.status; $to = $from
            if ($applies) {
                switch ($from) {
                    'rejected x1' { $to = 'open' }
                    'rejected x2' { $to = 'rejected x1' }
                    { $_ -in 'open', 'asked' } {
                        if ((One $d.moment).Length -ge 15) { $to = 'confirmed'; $e['moment'] = One $d.moment }
                        else { "UNCHANGED $id [$from] : applies, but 'moment' (a specific moment it would have helped) is required for confirmed" }
                    }
                }
            } else {
                switch ($from) {
                    { $_ -in 'open', 'asked' } { $to = 'rejected x1' }
                    'rejected x1' { $to = 'rejected x2' }
                    'rejected x2' { $to = 'REMOVE' }
                }
            }
            if ($to -eq $from) { continue }
            [void]$e.log.Add("$(Stamp) review '$label': $from -> $to ($(if ($applies) { 'applies' } else { 'does not apply' }): $(Cut $ev 200))")
            $e['last_review'] = $label
            if ($to -eq 'REMOVE') { Retire $db $e 'removed' 'not applicable in 3 consecutive handoffs'; "REMOVED $id (logged in Retired)" }
            else { $e.status = $to; "$id : $from -> $to" }
        }
        $added = 0
        foreach ($n in @($dj.new)) {
            if (-not $n) { continue }
            if ($added -ge $MAX_NEW) { "REFUSED new entry '$(Cut (One $n.idea) 60)': at most $MAX_NEW new entries per review"; continue }
            if ((Active-Count $db) -ge $CAP) { "REFUSED new entry '$(Cut (One $n.idea) 60)': $CAP active entries; retire or resolve one first"; continue }
            $r = New-EntryFrom $db $n
            if ($r.err) { "REFUSED new entry '$(Cut (One $n.idea) 60)': $($r.err)"; continue }
            [void]$r.entry.log.Add("$(Stamp) review '$label': added")
            [void]$db.act.Add($r.entry); $added++; "ADDED $($r.entry.id) $(Cut $r.entry.idea 80)"
        }
        Write-Ideas $File $db
        $c = Active-Count $db
        "review done: $c active of $CAP$(if ($c -ge $WARN_AT) { ' (WARNING: near the cap)' })"
    }
    'asked' {
        $ids = @($Arg1, $Arg2) + @($More) | Where-Object { $_ }
        if (-not $ids) { Fail 'usage: asked <id> [<id>..]' }
        foreach ($id in $ids) {
            $e = Find-Entry $db $id
            if (-not $e) { "SKIP $id : not active"; continue }
            if ($e.status -eq 'open') { $e.status = 'asked'; [void]$e.log.Add("$(Stamp) asked Shay"); "$id : open -> asked" } else { "UNCHANGED $id [$($e.status)]" }
        }
        Write-Ideas $File $db
    }
    'answer' {
        $e = Find-Entry $db $Arg1
        if (-not $e) { Fail "no active entry '$Arg1'" }
        switch ($Arg2.ToLower()) {
            'no' { [void]$e.log.Add("$(Stamp) Shay answered no"); Retire $db $e 'rejected (Shay said no)' 'Shay said No'; "$($e.id) removed (Shay said No), logged in Retired" }
            { $_ -in 'yes', 'approve' } { $e.status = 'confirmed'; [void]$e.log.Add("$(Stamp) Shay answered $($Arg2.ToLower())"); "$($e.id) -> confirmed (build it only on Shay's order; this tool does not apply ideas)" }
            default { Fail 'usage: answer <id> no|yes|approve' }
        }
        Write-Ideas $File $db
    }
    'done' {
        $e = Find-Entry $db $Arg1
        if (-not $e) { Fail "no active entry '$Arg1'" }
        if (-not (One $Measured)) { Fail 'done needs -Measured "<before/after numbers or a note that none could be measured>"' }
        $e['measured'] = One $Measured
        Retire $db $e 'done' 'built'
        Write-Ideas $File $db; "$($e.id) -> done (Retired)"
    }
    default { Fail "unknown command '$Command' (list|add|review|asked|answer|done)" }
}
