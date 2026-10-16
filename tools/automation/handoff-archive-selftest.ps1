# Selftest for PI-08: handoff-archive.ps1 on a temp copy (never touches the real HANDOFF.md).
$ErrorActionPreference = 'Stop'
$tool = Join-Path $PSScriptRoot 'handoff-archive.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ha-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { $script:pass++; "PASS $n" } else { $script:fail++; "FAIL $n $d" } }
function Run([string]$f, [string]$ad, [hashtable]$extra = @{}) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-File', $f, '-ArchiveDir', $ad, '-Date', '2026-01-01')
    foreach ($k in $extra.Keys) { if ($extra[$k] -is [bool]) { if ($extra[$k]) { $a += "-$k" } } else { $a += "-$k"; $a += "$($extra[$k])" } }
    return (& powershell @a 2>&1 | Out-String)
}
try {
    $src = @'
# Current state

preamble line

## Right now - canonical

**COORDINATOR #7 (started):** seven body
- bullet of seven

**COORDINATOR #6 HANDOFF:** six body
- bullet of six

**COORDINATOR #5 HANDOFF:** five body

**#4 later:** four body

**Standing order Shay still needs:** unnumbered, stays

**OLD UNNUMBERED PROGRAM NOTE:** archived by pattern

### Historical snapshots (superseded)
old snapshot body 1
old snapshot body 2

## Gotchas
gotcha body stays

## Eight-fix release composer checkpoint
composer body
**COORDINATOR #5 (appended at the end):** five late
'@
    $f = Join-Path $tmp 'HANDOFF.md'; $ad = Join-Path $tmp 'archive'
    [IO.File]::WriteAllText($f, ($src -replace "`r`n", "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $orig = [IO.File]::ReadAllLines($f)

    # 1. dry run changes nothing
    $h0 = (Get-FileHash $f).Hash
    $o = Run $f $ad @{ DryRun = $true; Sections = $true }
    Check 'dry run writes nothing' ((Get-FileHash $f).Hash -eq $h0 -and -not (Test-Path $ad)) $o

    # 2. real run (blocks only: no -Sections)
    $o = Run $f $ad @{ ArchivePattern = '^\*\*OLD UNNUMBERED' }
    $live = [IO.File]::ReadAllText($f); $arc = [IO.File]::ReadAllText((Join-Path $ad 'HANDOFF_history_2026-01-01.md'))
    Check 'keeps #7 and #6 blocks' ($live.Contains('seven body') -and $live.Contains('bullet of seven') -and $live.Contains('six body'))
    Check 'archives #5 and #4 blocks' (-not $live.Contains('five body') -and -not $live.Contains('four body') -and $arc.Contains('five body') -and $arc.Contains('four body'))
    Check 'unnumbered standing block stays' ($live.Contains('Standing order Shay still needs'))
    Check 'pattern-matched block archived' (-not $live.Contains('OLD UNNUMBERED') -and $arc.Contains('OLD UNNUMBERED'))
    Check 'sections untouched without -Sections' ($live.Contains('old snapshot body 1') -and $live.Contains('composer body'))
    Check 'anchor "## Right now" still present' ($live -match '(?m)^## Right now')
    Check 'pointer line inserted once' (([regex]::Matches($live, '(?m)^Older entries \(coordinators before')).Count -eq 1)
    Check 'archive keeps original order' ($arc.IndexOf('five body') -lt $arc.IndexOf('four body') -and $arc.IndexOf('four body') -lt $arc.IndexOf('OLD UNNUMBERED'))

    # 3. idempotent
    $h1 = (Get-FileHash $f).Hash; $a1 = (Get-FileHash (Join-Path $ad 'HANDOFF_history_2026-01-01.md')).Hash
    $o = Run $f $ad @{ ArchivePattern = '^\*\*OLD UNNUMBERED' }
    Check 'second run is a no-op' ((Get-FileHash $f).Hash -eq $h1 -and (Get-FileHash (Join-Path $ad 'HANDOFF_history_2026-01-01.md')).Hash -eq $a1 -and $o -match 'nothing to archive') $o

    # 4. -Sections moves the historical sections, keeps Gotchas
    $o = Run $f $ad @{ Sections = $true }
    $live = [IO.File]::ReadAllText($f); $arc = [IO.File]::ReadAllText((Join-Path $ad 'HANDOFF_history_2026-01-01.md'))
    Check '-Sections archives historical + checkpoint sections' (-not $live.Contains('old snapshot body 1') -and -not $live.Contains('composer body') -and $arc.Contains('old snapshot body 2') -and $arc.Contains('composer body'))
    Check '-Sections keeps the Gotchas section' ($live.Contains('gotcha body stays') -and $live -match '(?m)^## Gotchas')

    # 5. no line lost overall (every original line is in live or archive)
    $all = @([IO.File]::ReadAllLines($f)) + @([IO.File]::ReadAllLines((Join-Path $ad 'HANDOFF_history_2026-01-01.md')))
    $lost = @($orig | Where-Object { $_.Trim() -ne '' -and $all -notcontains $_ })
    Check 'no original line lost' ($lost.Count -eq 0) ($lost -join ' | ')

    # 6. concurrent append: the tool appends a line between its read and its write (test hook); the line must survive
    [IO.File]::WriteAllText($f, ($src -replace "`r`n", "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Remove-Item -Recurse -Force $ad
    $env:HANDOFF_ARCHIVE_TEST_APPEND = '**COORDINATOR #8 CONCURRENT APPEND:** must survive'
    try { $o = Run $f $ad @{} } finally { Remove-Item Env:\HANDOFF_ARCHIVE_TEST_APPEND }
    $live = [IO.File]::ReadAllText($f); $arc = [IO.File]::ReadAllText((Join-Path $ad 'HANDOFF_history_2026-01-01.md'))
    Check 'concurrent append survives' ($live.Contains('CONCURRENT APPEND') -and -not $arc.Contains('CONCURRENT APPEND')) $o
    Check 'an append outside Right now does not change the current number (#7 current: #6, #7 kept)' ($live.Contains('seven body') -and $live.Contains('six body') -and -not $arc.Contains('six body'))
    Check 'archive has no duplicated chunk text' (([regex]::Matches($arc, 'five body')).Count -eq 1)

    # 7. no anchor: nothing done
    [IO.File]::WriteAllText($f, "# no anchor here`nline`n", (New-Object Text.UTF8Encoding($false)))
    $o = Run $f $ad @{}
    Check 'file without "## Right now" is left alone' ($o -match 'no "## Right now" anchor' -and [IO.File]::ReadAllText($f) -eq "# no anchor here`nline`n") $o
}
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
"selftest: $pass passed, $fail failed"
if ($fail) { exit 1 }
