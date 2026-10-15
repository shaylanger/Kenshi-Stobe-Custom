# program-ledger.ps1: PROGRAM LEDGER = the state of a multi-agent program in FILES, not in one session's head (Shay 2026-10-15).
# One JSON file per program: C:\KenshiTestRuns\programs\<name>.json (contract read AND rewritten by coord-supervisor.ps1: keep it):
#   {name, md, updated, wps:[{id, items, size_estimate_tokens, depends:[ids], state todo|running|stopped|done|blocked,
#                              agent, successors:[names], outputs:[paths], handoff, last_checkpoint (ISO time)}]}
# `md` = path (relative to C:\KenshiModding) of the human-readable mirror, generated only by `show <name> -Md -Write`.
# Commands (powershell -NoProfile -File tools\automation\program-ledger.ps1 <cmd> ...):
#   init <name> <md> [-Force]            create an empty ledger (refuses to overwrite without -Force)
#   add-wp <name> <id> [key=value ...]   add a work package (state defaults to todo)
#   set <name> <wp> key=value ...        change fields; keys: items size_estimate_tokens depends state agent successors outputs
#                                        handoff last_checkpoint. Lists (depends successors outputs) take a,b or a;b;
#                                        key+=value appends. last_checkpoint=now (also set automatically on every `set`).
#   show [<name>] [-Md] [-Write]         one line per WP (all ledgers when no name); -Md = markdown mirror on stdout,
#                                        -Md -Write = write it to the ledger's `md` file
#   brief                                unfinished WPs of every ledger, one line each (session-start.ps1 prints this)
#   next [<name>]                        todo WPs whose depends are all done (ready to start)
#   session <name> <wp> <agent> <launcher_pid> [claude_pid]   record an independent claude session (spawn-wp-session.ps1): sets/replaces the
#                                        `sessions` entry "agent|launcher_pid|claude_pid|startedISO" and makes <agent> the WP's agent (when the WP has
#                                        none, or already has this one) or appends it to `successors` (agent-status.ps1 RUNNING then takes it over)
#   sync <agent> <STATE>                 what agent-status.ps1 calls: the WP whose `agent` is <agent> (or whose `successors` lists
#                                        it: then it becomes the WP's agent) follows the status: RUNNING->running, DONE->done,
#                                        STOPPED-CONTEXT|FAILED->stopped, last_checkpoint=now. done is sticky (never regressed).
#   reconcile [<name>]                   set every not-done WP's state/last_checkpoint from agents\<agent>.status
#   restore <name>                       swap the ledger with its .bak (programs\.bak\<name>.json.bak, kept per write); twice = undo
#   -Selftest                            temp dir via env, never the real programs dir
# Safety: every write is temp file + [IO.File]::Replace (atomic) with a .bak copy of the previous version; writers serialize on
# programs\.ledger.lock (exclusive file lock, waits KPL_LOCK_SEC, default 10 s); a malformed ledger is never rewritten.
# Env: KPL_DIR (programs dir; default %KAH_RUNS_DIR%\programs or C:\KenshiTestRuns\programs), KPL_WS (workspace for md paths),
# KPL_LOCK_SEC. Everything called from agent-status.ps1 / session-start.ps1 is wrapped fail-open by the caller.
param(
    [Parameter(Position = 0)][string]$Cmd = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [switch]$Md, [switch]$Write, [switch]$Force, [switch]$Selftest
)
$ErrorActionPreference = 'Stop'
$SelfPath = $PSCommandPath
$KnownKeys = @('items', 'size_estimate_tokens', 'depends', 'state', 'agent', 'successors', 'outputs', 'handoff', 'last_checkpoint', 'sessions')
$ListKeys = @('depends', 'successors', 'outputs', 'sessions')
$States = @('todo', 'running', 'stopped', 'done', 'blocked')

function Get-ProgDir {
    if ($env:KPL_DIR) { return $env:KPL_DIR }
    $r = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
    return (Join-Path $r 'programs')
}
function Get-Workspace { if ($env:KPL_WS) { $env:KPL_WS } else { Split-Path (Split-Path (Split-Path $SelfPath -Parent) -Parent) -Parent } }
function Get-Iso { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }
function Get-LedgerPath([string]$name) {
    if ($name -notmatch '^[A-Za-z0-9_.-]+$') { throw "bad program name '$name'" }
    Join-Path (Get-ProgDir) "$name.json"
}
function Set-Prop($o, [string]$k, $v) {
    if ($o.PSObject.Properties[$k]) { $o.$k = $v } else { Add-Member -InputObject $o -NotePropertyName $k -NotePropertyValue $v }
}
function Get-Time($v) {
    if ($v -is [datetime]) { return $v }
    $t = [datetime]::MinValue
    if ("$v" -and [datetime]::TryParse("$v", [ref]$t)) { return $t }
    return $null
}
function Format-Age($v) {
    $t = Get-Time $v
    if (-not $t) { return '?' }
    $s = [int]((Get-Date) - $t).TotalSeconds
    if ($s -lt 0) { $s = 0 }
    if ($s -lt 60) { return "${s}s" }
    if ($s -lt 3600) { return "$([int]($s / 60))m" }
    if ($s -lt 86400) { return "$([int]($s / 3600))h" }
    return "$([int]($s / 86400))d"
}

# ---- lock + read/write ----
function Enter-Lock {
    $dir = Get-ProgDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lp = Join-Path $dir '.ledger.lock'
    $limit = if ($env:KPL_LOCK_SEC) { [int]$env:KPL_LOCK_SEC } else { 10 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try { return [IO.File]::Open($lp, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] {
            if ($sw.Elapsed.TotalSeconds -ge $limit) { throw "ledger lock busy ($lp) after ${limit}s" }
            Start-Sleep -Milliseconds 80
        }
    }
}
function Invoke-Locked([scriptblock]$Body) {
    $fs = Enter-Lock
    try { & $Body } finally { $fs.Dispose() }
}
function Format-Wp($w) {
    if ($null -eq $w.PSObject.Properties['id']) { Set-Prop $w 'id' '' }
    foreach ($k in $KnownKeys) {
        if (-not $w.PSObject.Properties[$k]) {
            $d = if ($k -in $ListKeys) { , @() } elseif ($k -eq 'size_estimate_tokens') { 0 } elseif ($k -eq 'state') { 'todo' } else { '' }
            Set-Prop $w $k $d
        }
    }
    foreach ($k in $ListKeys) { $w.$k = @($w.$k | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { "$_" }) }
    if ($w.last_checkpoint -is [datetime]) { $w.last_checkpoint = $w.last_checkpoint.ToString('yyyy-MM-ddTHH:mm:sszzz') }
}
function Read-Ledger([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "no ledger $path" }
    $j = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $j -or $j -is [array] -or $j -isnot [pscustomobject]) { throw "not a ledger object: $path" }
    if (-not $j.PSObject.Properties['name']) { Set-Prop $j 'name' ([IO.Path]::GetFileNameWithoutExtension($path)) }
    if (-not $j.PSObject.Properties['md']) { Set-Prop $j 'md' '' }
    $wl = @(if ($j.PSObject.Properties['wps'] -and $null -ne $j.wps) { $j.wps })
    foreach ($w in $wl) { Format-Wp $w }
    Set-Prop $j 'wps' $wl
    return $j
}
function Write-Ledger([string]$path, $obj) {
    Set-Prop $obj 'updated' (Get-Iso)
    $json = $obj | ConvertTo-Json -Depth 30
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    $bdir = Join-Path (Split-Path $path -Parent) '.bak'
    New-Item -ItemType Directory -Force -Path $bdir | Out-Null
    $bak = Join-Path $bdir ((Split-Path $path -Leaf) + '.bak')
    Move-Atomic $tmp $path $bak
}
function Move-Atomic([string]$tmp, [string]$path, [string]$bak) {
    $err = $null
    for ($i = 0; $i -lt 8; $i++) {
        try {
            if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, $bak) } else { [IO.File]::Move($tmp, $path) }
            return
        } catch { $err = $_; Start-Sleep -Milliseconds 120 }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw $err
}
function Get-Wp($obj, [string]$id) {
    $m = @($obj.wps | Where-Object { "$($_.id)" -eq $id })
    if (-not $m.Count) { throw "ledger $($obj.name): no wp '$id'" }
    return $m[0]
}

# ---- field updates ----
function Set-Fields($w, [string[]]$kvs, [bool]$stamp = $true) {
    $gotCk = $false
    foreach ($kv in $kvs) {
        if ($kv -notmatch '^([a-z_]+)(\+?)=(.*)$') { throw "expected key=value or key+=value, got '$kv'" }
        $k = $Matches[1]; $app = ($Matches[2] -eq '+'); $v = $Matches[3]
        if ($k -notin $KnownKeys) { throw "unknown key '$k' (known: $($KnownKeys -join ' '))" }
        if ($k -in $ListKeys) {
            $sep = if ($k -eq 'outputs') { ';' } else { '[,;]' }
            $new = @($v -split $sep | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $w.$k = if ($app) { @(@($w.$k) + $new | Select-Object -Unique) } else { $new }
        } elseif ($k -eq 'state') {
            if ($v -notin $States) { throw "bad state '$v' (one of $($States -join ' '))" }
            $w.state = $v
        } elseif ($k -eq 'size_estimate_tokens') {
            $n = 0
            if (-not [int]::TryParse($v, [ref]$n)) { throw "size_estimate_tokens must be an integer, got '$v'" }
            $w.size_estimate_tokens = $n
        } elseif ($k -eq 'last_checkpoint') {
            $gotCk = $true
            if ($v -eq 'now') { $w.last_checkpoint = Get-Iso }
            else { $t = Get-Time $v; if (-not $t) { throw "bad time '$v'" }; $w.last_checkpoint = $t.ToString('yyyy-MM-ddTHH:mm:sszzz') }
        } else { $w.$k = $v }
    }
    if ($stamp -and -not $gotCk) { $w.last_checkpoint = Get-Iso }
}

# ---- agent-status hook ----
function Sync-Agent([string]$agent, [string]$state) {
    $changes = @()
    $dir = Get-ProgDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $changes }
    $newState = switch ($state) { 'RUNNING' { 'running' } 'DONE' { 'done' } 'STOPPED-CONTEXT' { 'stopped' } 'FAILED' { 'stopped' } default { $null } }
    if (-not $newState) { return $changes }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if (-not $files.Count) { return $changes }
    Invoke-Locked {
        foreach ($f in $files) {
            try { $o = Read-Ledger $f.FullName } catch { continue }   # malformed ledger: never touched
            $dirty = $false
            foreach ($w in $o.wps) {
                $isAgent = ("$($w.agent)" -ieq $agent)
                $isSucc = (-not $isAgent) -and (@($w.successors) | Where-Object { "$_" -ieq $agent })
                if (-not ($isAgent -or $isSucc)) { continue }
                if ("$($w.state)" -eq 'done' -and $newState -ne 'done') { continue }          # done is sticky
                if ($isSucc -and $newState -eq 'stopped' -and "$($w.state)" -eq 'running') { continue }   # a queued successor stopping must not stop the live agent
                if ($isSucc -and $newState -eq 'done' -and "$($w.state)" -eq 'running' -and "$($w.agent)") { continue }  # likewise
                if ($isSucc) { $w.agent = $agent }
                $w.state = $newState
                $w.last_checkpoint = Get-Iso
                $dirty = $true
                $changes += "$($o.name)/$($w.id) -> $newState"
            }
            if ($dirty) { Write-Ledger $f.FullName $o }
        }
    }
    return $changes
}

# ---- views ----
function Get-StateCounts($o) {
    $c = @{}
    foreach ($s in $States) { $c[$s] = @($o.wps | Where-Object { "$($_.state)" -eq $s }).Count }
    return $c
}
function Get-Ready($o) {
    $done = @($o.wps | Where-Object { "$($_.state)" -eq 'done' } | ForEach-Object { "$($_.id)" })
    return @($o.wps | Where-Object { "$($_.state)" -eq 'todo' -and -not @($_.depends | Where-Object { $_ -notin $done }).Count })
}
function Format-WpLine($w) {
    $it = "$($w.items)"; if ($it.Length -gt 38) { $it = $it.Substring(0, 35) + '...' }
    return ('  {0,-14} {1,-8} {2,-18} ckpt {3,-4} {4}' -f $w.id, $w.state, $w.agent, $(if ("$($w.state)" -eq 'todo' -and -not $w.agent) { '-' } else { Format-Age $w.last_checkpoint }), $it)
}
function Read-AllLedgers {
    $res = @()
    $dir = Get-ProgDir
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $res += , (Read-Ledger $f.FullName) } catch { "  (skipped malformed ledger $($f.Name): $($_.Exception.Message))" }
    }
    return $res
}
function Get-Markdown($o) {
    $L = New-Object Collections.Generic.List[string]
    $L.Add("# $($o.name) program: work package ledger (mirror)")
    $L.Add('')
    $L.Add("Generated by ``tools/automation/program-ledger.ps1 show $($o.name) -Md -Write`` from ``C:\KenshiTestRuns\programs\$($o.name).json`` (ledger updated $($o.updated)). The JSON is the truth: change it with ``program-ledger.ps1 set``, never edit this file by hand.")
    $L.Add('')
    $c = Get-StateCounts $o
    $L.Add("Summary: $(@($o.wps).Count) work packages: " + (($States | ForEach-Object { "$($c[$_]) $_" }) -join ', '))
    $L.Add('')
    $L.Add('| WP | state | items | agent | depends | est. tokens | last checkpoint |')
    $L.Add('|---|---|---|---|---|---|---|')
    foreach ($w in $o.wps) {
        $row = @($w.id, $w.state, "$($w.items)".Replace('|', '/'), $w.agent, (@($w.depends) -join ', '), $w.size_estimate_tokens, $w.last_checkpoint)
        $L.Add('| ' + (($row | ForEach-Object { "$_" }) -join ' | ') + ' |')
    }
    $L.Add('')
    $L.Add('## Details')
    foreach ($w in $o.wps) {
        $L.Add('')
        $L.Add("### $($w.id) ($($w.state))")
        if ($w.items) { $L.Add("- items: $($w.items)") }
        if ($w.agent) { $L.Add("- agent: $($w.agent)") }
        if (@($w.successors).Count) { $L.Add("- successors: $(@($w.successors) -join ', ')") }
        if ($w.handoff) { $L.Add("- handoff: $($w.handoff)") }
        foreach ($p in @($w.outputs)) { $L.Add("- output: $p") }
        foreach ($p in @($w.sessions)) { $L.Add("- session: $p") }
    }
    return ($L -join "`n") + "`n"
}

# ---- commands ----
function Invoke-Cmd([string]$cmd, [string[]]$a) {
    switch ($cmd) {
        'init' {
            if ($a.Count -lt 2) { throw 'usage: init <name> <md>' }
            $p = Get-LedgerPath $a[0]
            Invoke-Locked {
                if ((Test-Path -LiteralPath $p) -and -not $Force) { throw "ledger exists: $p (use -Force)" }
                $o = [pscustomobject]@{ name = $a[0]; md = $a[1]; updated = ''; wps = @() }
                Write-Ledger $p $o
            }
            "created $p"
        }
        'add-wp' {
            if ($a.Count -lt 2) { throw 'usage: add-wp <name> <id> [key=value ...]' }
            $p = Get-LedgerPath $a[0]
            Invoke-Locked {
                $o = Read-Ledger $p
                if (@($o.wps | Where-Object { "$($_.id)" -eq $a[1] }).Count) { throw "wp '$($a[1])' already exists in $($o.name)" }
                $w = [pscustomobject]@{ id = $a[1] }
                Format-Wp $w
                Set-Fields $w @($a | Select-Object -Skip 2) $true
                $o.wps = @(@($o.wps) + $w)
                Write-Ledger $p $o
            }
            "added $($a[0])/$($a[1])"
        }
        'set' {
            if ($a.Count -lt 3) { throw 'usage: set <name> <wp> key=value ...' }
            $p = Get-LedgerPath $a[0]
            Invoke-Locked {
                $o = Read-Ledger $p
                $w = Get-Wp $o $a[1]
                Set-Fields $w @($a | Select-Object -Skip 2) $true
                Write-Ledger $p $o
            }
            "set $($a[0])/$($a[1])"
        }
        'show' {
            $objs = if ($a.Count) { , (Read-Ledger (Get-LedgerPath $a[0])) } else { Read-AllLedgers }
            foreach ($o in $objs) {
                if ($o -is [string]) { $o; continue }
                if ($Md) {
                    $text = Get-Markdown $o
                    if ($Write) {
                        if (-not $o.md) { throw "ledger $($o.name) has no md path" }
                        $mp = if ([IO.Path]::IsPathRooted($o.md)) { $o.md } else { Join-Path (Get-Workspace) $o.md }
                        New-Item -ItemType Directory -Force -Path (Split-Path $mp -Parent) | Out-Null
                        [IO.File]::WriteAllText($mp, $text, (New-Object Text.UTF8Encoding($false)))
                        "wrote $mp"
                    } else { $text }
                } else {
                    $c = Get-StateCounts $o
                    "== $($o.name) (md $($o.md), updated $($o.updated)): " + (($States | ForEach-Object { "$($c[$_]) $_" }) -join ', ')
                    foreach ($w in $o.wps) { Format-WpLine $w }
                }
            }
        }
        'brief' {
            foreach ($o in (Read-AllLedgers)) {
                if ($o -is [string]) { $o; continue }
                $open = @($o.wps | Where-Object { "$($_.state)" -ne 'done' })
                if (-not $open.Count) { continue }
                "=== PROGRAM LEDGER $($o.name) ($($o.md)): $($open.Count) of $(@($o.wps).Count) wps unfinished, updated $(Format-Age $o.updated) ago ==="
                foreach ($w in $open) {
                    Format-WpLine $w
                    # independent agent sessions (spawn-wp-session.ps1): LIVE = adopt, DEAD = respawn from the handoff (WP_SIZING.md section 10)
                    $ss = @($w.sessions)
                    if ($ss.Count -and "$($ss[-1])") {
                        $sn = ([string]$ss[-1]).Split('|')[0]
                        $lv = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agent-session-live.ps1') $sn 2>&1 | Select-Object -First 1)
                        "      independent session ${sn}: $lv" + $(if ("$lv" -like 'DEAD*') { "  -> respawn: spawn-wp-session.ps1 ${sn}b <case> <prompt-file> -Program $($o.name) -Wp $($w.id) (brief from agents\$sn.handoff.md)" } else { '' })
                    }
                }
                $rd = @(Get-Ready $o | ForEach-Object { $_.id })
                if ($rd.Count) { "  ready to start (todo, depends done): $($rd -join ', ')" }
            }
        }
        'next' {
            $objs = if ($a.Count) { , (Read-Ledger (Get-LedgerPath $a[0])) } else { Read-AllLedgers }
            foreach ($o in $objs) {
                if ($o -is [string]) { $o; continue }
                foreach ($w in (Get-Ready $o)) { "$($o.name)/$($w.id)  est $($w.size_estimate_tokens)  $($w.items)" }
            }
        }
        'session' {
            if ($a.Count -lt 4) { throw 'usage: session <name> <wp> <agent> <launcher_pid> [claude_pid]' }
            $p = Get-LedgerPath $a[0]
            $ag = $a[2]
            if ($ag -notmatch '^[A-Za-z0-9_.-]+$') { throw "bad agent name '$ag'" }
            if ($a[3] -notmatch '^\d+$' -or ($a.Count -gt 4 -and $a[4] -notmatch '^\d+$')) { throw 'pids must be integers' }
            $entry = "$ag|$($a[3])|$(if ($a.Count -gt 4) { $a[4] } else { '' })|$(Get-Iso)"
            Invoke-Locked {
                $o = Read-Ledger $p
                $w = Get-Wp $o $a[1]
                $w.sessions = @(@($w.sessions | Where-Object { ("$_" -split '\|')[0] -ine $ag }) + $entry)
                if (-not "$($w.agent)" -or "$($w.agent)" -ieq $ag) { $w.agent = $ag }
                elseif (-not (@($w.successors) | Where-Object { "$_" -ieq $ag })) { $w.successors = @(@($w.successors) + $ag) }
                $w.last_checkpoint = Get-Iso
                Write-Ledger $p $o
            }
            "session $($a[0])/$($a[1]) <- $entry"
        }
        'sync' {
            if ($a.Count -lt 2) { throw 'usage: sync <agent> <STATE>' }
            foreach ($c in (Sync-Agent $a[0] $a[1])) { "ledger $c" }
        }
        'reconcile' {
            $names = if ($a.Count) { @($a[0]) } else { @(Get-ChildItem -LiteralPath (Get-ProgDir) -Filter '*.json' -File | ForEach-Object { $_.BaseName }) }
            $ad = Join-Path (Split-Path (Get-ProgDir) -Parent) 'agents'
            foreach ($n in $names) {
                $p = Get-LedgerPath $n
                Invoke-Locked {
                    $o = Read-Ledger $p; $dirty = $false
                    foreach ($w in $o.wps) {
                        if ("$($w.state)" -eq 'done' -or -not $w.agent) { continue }
                        $sf = Join-Path $ad "$($w.agent).status"
                        if (-not (Test-Path -LiteralPath $sf)) { continue }
                        $parts = ((Get-Content -LiteralPath $sf -TotalCount 1) -split '\|') | ForEach-Object { $_.Trim() }
                        if ($parts.Count -lt 3) { continue }
                        $ns = switch ($parts[1]) { 'RUNNING' { 'running' } 'DONE' { 'done' } 'STOPPED-CONTEXT' { 'stopped' } 'FAILED' { 'stopped' } default { $null } }
                        if (-not $ns) { continue }
                        $t = Get-Time ($parts[2] + ':00')
                        if ("$($w.state)" -ne $ns) { "reconcile $($o.name)/$($w.id): $($w.state) -> $ns (agent $($w.agent))" }
                        $w.state = $ns
                        if ($t) { $w.last_checkpoint = $t.ToString('yyyy-MM-ddTHH:mm:sszzz') }
                        $dirty = $true
                    }
                    if ($dirty) { Write-Ledger $p $o }
                }
            }
        }
        'restore' {
            if ($a.Count -lt 1) { throw 'usage: restore <name>' }
            $p = Get-LedgerPath $a[0]
            $bak = Join-Path (Join-Path (Split-Path $p -Parent) '.bak') ((Split-Path $p -Leaf) + '.bak')
            if (-not (Test-Path -LiteralPath $bak)) { throw "no backup $bak" }
            Invoke-Locked {
                $null = Read-Ledger $bak     # must parse
                $tmp = "$p.$PID.tmp"
                Copy-Item -LiteralPath $bak -Destination $tmp -Force
                Move-Atomic $tmp $p $bak     # current version becomes the new .bak (running restore twice undoes it)
            }
            "restored $p from $bak (previous version kept as the new .bak)"
        }
        default {
            Get-Content -LiteralPath $SelfPath -TotalCount 28 | Where-Object { $_ -like '#*' } | ForEach-Object { $_.Substring(1).TrimStart() }
        }
    }
}

# ---- selftest ----
function Invoke-Selftest {
    $real = if ($env:KAH_RUNS_DIR) { Join-Path $env:KAH_RUNS_DIR 'programs' } else { 'C:\KenshiTestRuns\programs' }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("kpl-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $env:KPL_DIR = Join-Path $tmp 'programs'
    $env:KPL_WS = Join-Path $tmp 'ws'
    $env:KPL_LOCK_SEC = '10'
    New-Item -ItemType Directory -Force -Path $env:KPL_DIR, $env:KPL_WS | Out-Null
    $script:pass = 0; $script:fail = 0
    function T([bool]$ok, [string]$msg) { if ($ok) { $script:pass++; "PASS  $msg" } else { $script:fail++; "FAIL  $msg" } }
    function Throws([scriptblock]$b) { try { & $b | Out-Null; return $false } catch { return $true } }
    function Run([string]$c, [string[]]$x) { Invoke-Cmd $c $x | Out-Null }
    function J([string]$n) { Get-Content -LiteralPath (Join-Path $env:KPL_DIR "$n.json") -Raw | ConvertFrom-Json }
    function J2([string]$n) { Get-Content -LiteralPath (Join-Path $tmp "programs\$n.json") -Raw | ConvertFrom-Json }
    try {
        T ($env:KPL_DIR -ne $real -and $env:KPL_DIR.StartsWith($tmp)) '0 selftest dir is a temp dir, not the real programs dir'
        Run 'init' @('t1', 'testing/T1.md')
        $j = J 't1'
        T ($j.name -eq 't1' -and $j.md -eq 'testing/T1.md' -and @($j.wps).Count -eq 0 -and $j.updated) '1 init: name, md, updated, empty wps'
        T (Throws { Run 'init' @('t1', 'x') }) '2a init twice refuses'
        $Force = [switch]::new($true); Run 'init' @('t1', 'testing/T1.md'); $Force = [switch]::new($false)
        T ((J 't1').md -eq 'testing/T1.md') '2b init -Force overwrites'
        Run 'add-wp' @('t1', 'a', 'items=1,2,3', 'size_estimate_tokens=90000', 'agent=agA', 'state=running')
        Run 'add-wp' @('t1', 'b', 'items=4', 'depends=a')
        Run 'add-wp' @('t1', 'c', 'items=5', 'depends=a,b', 'successors=cOld;cNew', 'outputs=C:\x\one.patch;C:\x\two.patch')
        $j = J 't1'
        T (@($j.wps).Count -eq 3 -and $j.wps[0].size_estimate_tokens -eq 90000 -and $j.wps[0].state -eq 'running' -and $j.wps[1].state -eq 'todo') '3a add-wp fields and defaults'
        T (@($j.wps[2].depends).Count -eq 2 -and @($j.wps[2].successors).Count -eq 2 -and @($j.wps[2].outputs).Count -eq 2 -and $j.wps[2].outputs[0] -eq 'C:\x\one.patch') '3b list fields (, ; separators, outputs split on ;)'
        T (Throws { Run 'add-wp' @('t1', 'a') }) '3c duplicate wp id refuses'
        T ((J 't1').wps[0].last_checkpoint -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d') '3d last_checkpoint is ISO'
        Run 'set' @('t1', 'b', 'agent=agB', 'handoff=C:\h.md', 'successors+=agB2', 'successors+=agB3')
        $j = J 't1'
        T ($j.wps[1].agent -eq 'agB' -and $j.wps[1].handoff -eq 'C:\h.md' -and (@($j.wps[1].successors) -join ',') -eq 'agB2,agB3') '4a set + append'
        T ((Throws { Run 'set' @('t1', 'b', 'state=bogus') }) -and (Throws { Run 'set' @('t1', 'b', 'nope=1') }) -and (Throws { Run 'set' @('t1', 'zz', 'state=done') }) -and (Throws { Run 'set' @('t1', 'b', 'size_estimate_tokens=x') })) '4b bad state / unknown key / unknown wp / bad int rejected'
        T ((J 't1').wps[1].state -eq 'todo') '4c rejected set left the ledger unchanged'
        $nx = @(Invoke-Cmd 'next' @('t1'))
        T ($nx.Count -eq 0) '5a next: b and c wait for a (a running)'
        Run 'set' @('t1', 'a', 'state=done')
        $nx = @(Invoke-Cmd 'next' @('t1'))
        T ($nx.Count -eq 1 -and $nx[0] -like 't1/b *') '5b next: b ready after a done, c still blocked by b'
        # sync
        Run 'set' @('t1', 'b', 'state=todo')
        Run 'sync' @('agB', 'RUNNING');                 T ((J 't1').wps[1].state -eq 'running') '6a sync RUNNING -> running'
        Run 'sync' @('AGB', 'STOPPED-CONTEXT');         T ((J 't1').wps[1].state -eq 'stopped') '6b sync STOPPED-CONTEXT -> stopped (case-insensitive agent)'
        Run 'sync' @('agB2', 'RUNNING');                $w = (J 't1').wps[1]
        T ($w.state -eq 'running' -and $w.agent -eq 'agB2') '6c sync by successors name: becomes the wp agent'
        Run 'sync' @('agB2', 'FAILED');                 T ((J 't1').wps[1].state -eq 'stopped') '6d sync FAILED -> stopped'
        Run 'sync' @('agB2', 'DONE');                   T ((J 't1').wps[1].state -eq 'done') '6e sync DONE -> done'
        Run 'sync' @('agB2', 'RUNNING');                T ((J 't1').wps[1].state -eq 'done') '6f done is sticky'
        Run 'sync' @('nobody', 'DONE');                 T ((J 't1').wps[2].state -eq 'todo') '6g unknown agent: no change'
        Run 'set' @('t1', 'c', 'agent=agC', 'state=running')
        Run 'sync' @('cNew', 'STOPPED-CONTEXT');        T ((J 't1').wps[2].state -eq 'running' -and (J 't1').wps[2].agent -eq 'agC') '6h a queued successor stopping does not stop the live agent'
        $ck = (J 't1').wps[0].last_checkpoint; Run 'sync' @('agA', 'RUNNING'); T ((J 't1').wps[0].state -eq 'done') '6i sync RUNNING on a done wp keeps done'
        # independent sessions
        Run 'session' @('t1', 'b', 'sessB', '4242', '4343')
        $w = (J 't1').wps[1]
        T (@($w.sessions).Count -eq 1 -and @($w.sessions)[0] -match '^sessB\|4242\|4343\|\d{4}-' -and $w.agent -eq 'agB2' -and (@($w.successors) -contains 'sessB')) '6j session: entry name|launcher|claude|iso; wp with another agent gets it as successor'
        Run 'session' @('t1', 'b', 'sessB', '5000')
        $w = (J 't1').wps[1]
        T (@($w.sessions).Count -eq 1 -and @($w.sessions)[0] -like 'sessB|5000||*' -and @($w.successors | Where-Object { $_ -eq 'sessB' }).Count -eq 1) '6k session twice replaces the entry, successor not duplicated'
        Run 'add-wp' @('t1', 'sx', 'items=9')
        Run 'session' @('t1', 'sx', 'sessX', '77')
        T ((J 't1').wps[3].agent -eq 'sessX' -and (Throws { Run 'session' @('t1', 'sx', 'bad name', '1') }) -and (Throws { Run 'session' @('t1', 'sx', 'ok', 'x') }) -and (Throws { Run 'session' @('t1', 'nope', 'ok', '1') })) '6l session on a wp without agent sets it; bad name/pid/wp rejected'
        # backup / restore / atomic / contract
        $bd = Join-Path $env:KPL_DIR '.bak'
        T (Test-Path (Join-Path $bd 't1.json.bak')) '7a .bak exists after writes'
        Run 'set' @('t1', 'c', 'handoff=NEW')
        Run 'set' @('t1', 'c', 'handoff=NEWER')
        Run 'restore' @('t1')
        T ((J 't1').wps[2].handoff -eq 'NEW') '7b restore returns the previous version'
        Run 'restore' @('t1')
        T ((J 't1').wps[2].handoff -eq 'NEWER') '7c restore twice undoes the restore'
        T (-not @(Get-ChildItem -LiteralPath $env:KPL_DIR -Filter '*.tmp').Count) '7d no temp files left'
        T (-not @(Get-ChildItem -LiteralPath $env:KPL_DIR -Filter '*.bak' -File).Count) '7e backups live in .bak\ (not matched by the supervisor *.json glob)'
        # coord-supervisor contract: foreign properties survive, file stays parseable with id/state per wp
        $sup = [pscustomobject]@{ name = 't2'; md = ''; extra = @{ k = 'v' }; wps = @([pscustomobject]@{ id = 'x'; state = 'running'; agent = 'zed'; weird = 7 }) }
        [IO.File]::WriteAllText((Join-Path $env:KPL_DIR 't2.json'), ($sup | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        Run 'sync' @('zed', 'DONE')
        $j2 = J 't2'
        T ($j2.wps[0].state -eq 'done' -and $j2.wps[0].weird -eq 7 -and $j2.extra.k -eq 'v' -and $j2.wps[0].PSObject.Properties['depends']) '8a foreign props kept, missing fields filled, wp updated'
        # malformed / empty / array ledgers: never crash, never rewritten
        $bad = Join-Path $env:KPL_DIR 'broken.json'; [IO.File]::WriteAllText($bad, '{"name": "x", "wps": [ {')
        $arr = Join-Path $env:KPL_DIR 'arr.json'; [IO.File]::WriteAllText($arr, '[1,2,3]')
        $emp = Join-Path $env:KPL_DIR 'empty.json'; [IO.File]::WriteAllText($emp, '')
        $h = (Get-FileHash $bad).Hash + (Get-FileHash $arr).Hash
        $ok = $true; try { Run 'sync' @('agA', 'RUNNING'); @(Invoke-Cmd 'brief' @()) | Out-Null; @(Invoke-Cmd 'show' @()) | Out-Null } catch { $ok = $false }
        T ($ok -and (Get-FileHash $bad).Hash + (Get-FileHash $arr).Hash -eq $h) '9 malformed/array/empty ledgers tolerated and left untouched'
        Remove-Item $bad, $arr, $emp -Force
        # views
        $b = @(Invoke-Cmd 'brief' @())
        T (($b | Where-Object { $_ -like '=== PROGRAM LEDGER t1*' }).Count -eq 1 -and ($b | Where-Object { $_ -match '^\s+c\s+running\s+agC' }).Count -eq 1 -and -not ($b | Where-Object { $_ -match '^\s+a\s+done' })) '10a brief: only unfinished wps, one line each, "ledger" header'
        T (-not ($b | Where-Object { $_ -like '*PROGRAM LEDGER t2*' })) '10b brief: finished ledger not printed'
        $m1 = Get-Markdown (Read-Ledger (Join-Path $env:KPL_DIR 't1.json')); $m2 = Get-Markdown (Read-Ledger (Join-Path $env:KPL_DIR 't1.json'))
        T ($m1 -eq $m2 -and $m1 -match '\| c \| running \|' -and $m1 -match '### c \(running\)') '10c markdown deterministic, has table + details'
        $Md = [switch]::new($true); $Write = [switch]::new($true)
        $r = @(Invoke-Cmd 'show' @('t1'))
        T ((Test-Path (Join-Path $env:KPL_WS 'testing\T1.md')) -and $r[0] -like 'wrote *') '10d show -Md -Write writes the md under the (temp) workspace'
        $Md = [switch]::new($false); $Write = [switch]::new($false)
        # reconcile
        $ad = Join-Path $tmp 'agents'; New-Item -ItemType Directory -Force -Path $ad | Out-Null
        Set-Content -LiteralPath (Join-Path $ad 'agC.status') -Value @('agC | DONE | 2026-10-15 14:30', 'task: x') -Encoding UTF8
        $rc = @(Invoke-Cmd 'reconcile' @('t1'))
        T ((J 't1').wps[2].state -eq 'done' -and ($rc -join ' ') -match 'running -> done' -and (J 't1').wps[2].last_checkpoint -like '2026-10-15T14:30*') '11 reconcile follows the agent status file (BOM-safe) incl. its date'
        # two processes at once + lock timeout
        Run 'init' @('par', 'testing/PAR.md')
        $ps = foreach ($i in 1..6) { Start-Process -FilePath powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SelfPath, 'add-wp', 'par', "w$i", "items=$i") -PassThru -WindowStyle Hidden }
        $ps | Wait-Process -Timeout 90
        $jp = J 'par'
        T (@($jp.wps).Count -eq 6 -and (@($jp.wps | ForEach-Object { $_.id } | Sort-Object -Unique).Count -eq 6)) '12a six concurrent writer processes: no lost update'
        $fs = Enter-Lock; $env:KPL_LOCK_SEC = '1'
        $before = (Get-FileHash (Join-Path $env:KPL_DIR 'par.json')).Hash
        $t0 = Get-Date
        $thr = Throws { Run 'set' @('par', 'w1', 'state=done') }
        $el = ((Get-Date) - $t0).TotalSeconds
        $fs.Dispose(); $env:KPL_LOCK_SEC = '10'
        T ($thr -and $el -lt 6 -and (Get-FileHash (Join-Path $env:KPL_DIR 'par.json')).Hash -eq $before) '12b held lock: writer times out with an error, ledger unchanged'
        Run 'set' @('par', 'w1', 'state=done')
        T ([bool]((J 'par').wps | Where-Object { $_.id -eq 'w1' -and $_.state -eq 'done' })) '12c lock released: write works again'
        # command line parsing through the real entry point
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $SelfPath set par w2 items=7,8,9 'depends=w1,w3' state=blocked
        T ([bool]((J 'par').wps | Where-Object { $_.id -eq 'w2' -and $_.items -eq '7,8,9' -and $_.state -eq 'blocked' -and @($_.depends).Count -eq 2 })) '13 command line: key=value with commas parses as strings'
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $SelfPath sync nobody DONE
        T ($LASTEXITCODE -eq 0) '14 sync via command line exits 0 for an unknown agent'
        # real agent-status.ps1 hook (child process, its own temp runs dir via KAH_RUNS_DIR, KPL_DIR cleared)
        $as = Join-Path (Split-Path $SelfPath -Parent) 'agent-status.ps1'
        if (Test-Path -LiteralPath $as) {
            $sk = $env:KPL_DIR; $sr = $env:KAH_RUNS_DIR
            $env:KPL_DIR = $null; $env:KAH_RUNS_DIR = $tmp
            try {
                Run 'init' @('hk', 'testing/HK.md')   # KPL_DIR is null: goes to $tmp\programs
                Run 'add-wp' @('hk', 'w', 'agent=hkAgent', 'successors=hkNext', 'state=todo')
                & powershell -NoProfile -ExecutionPolicy Bypass -File $as hkAgent RUNNING 't' 'l' 'o' 'n' | Out-Null
                $s1 = (J2 'hk').wps[0].state
                & powershell -NoProfile -ExecutionPolicy Bypass -File $as hkAgent STOPPED-CONTEXT 't' 'l' 'o' 'n' | Out-Null
                $s2 = (J2 'hk').wps[0].state
                & powershell -NoProfile -ExecutionPolicy Bypass -File $as hkNext RUNNING 't' 'l' 'o' 'n' | Out-Null
                $w = (J2 'hk').wps[0]
                & powershell -NoProfile -ExecutionPolicy Bypass -File $as hkNext DONE 't' 'l' 'o' 'n' | Out-Null
                $s4 = (J2 'hk').wps[0].state
                T ($s1 -eq 'running' -and $s2 -eq 'stopped' -and $w.state -eq 'running' -and $w.agent -eq 'hkNext' -and $s4 -eq 'done') '14c agent-status.ps1 moves the wp: RUNNING, STOPPED-CONTEXT, successor RUNNING (takes over), DONE'
                & powershell -NoProfile -ExecutionPolicy Bypass -File $as unrelated RUNNING 't' | Out-Null
                T ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $tmp 'agents\unrelated.status'))) '14d agent-status for an agent in no ledger still succeeds'
            } finally { $env:KPL_DIR = $sk; $env:KAH_RUNS_DIR = $sr }
        }
        $kw = $env:KPL_WS; $env:KPL_WS = $null
        T ((Test-Path -LiteralPath (Join-Path (Get-Workspace) 'tools\automation\program-ledger.ps1'))) '14b default workspace resolves to the repo root'
        $env:KPL_WS = $kw
        T ((Get-Item $real -ErrorAction SilentlyContinue) -eq $null -or (Get-ChildItem $real -Filter 'kpl-*' -ErrorAction SilentlyContinue).Count -eq 0) '15 real programs dir untouched'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    "SELFTEST $(if ($script:fail) { 'FAIL' } else { 'PASS' }) $($script:pass)/$($script:pass + $script:fail)"
    if ($script:fail) { exit 1 }
}

if ($Selftest) { Invoke-Selftest; return }
try {
    # re-flatten args: PowerShell may hand "a=1,2" as one string or split pieces; keep strings as they are
    $args2 = @($Rest | Where-Object { $null -ne $_ })
    Invoke-Cmd $Cmd $args2
} catch {
    Write-Error "program-ledger: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
