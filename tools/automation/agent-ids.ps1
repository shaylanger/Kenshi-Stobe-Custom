# agent-ids.ps1 - PI-36 (Shay 2026-10-16): registry name -> SendMessage agent id for in-session subagents.
# SendMessage by NAME to a live subagent fails ("No agent named ... is reachable"); by the agentId from the Agent tool's spawn result it works.
# The spawner records the id right after each Agent call; anyone (coordinator, tail, successor coordinator) looks it up.
#   agent-ids.ps1 add <name> <agentId> [<session>]   record (replaces an older id for the same name)
#   agent-ids.ps1 get <name>                          prints the id (exit 1 if unknown)
#   agent-ids.ps1 list [-Live]                        name, id, spawned-by session, age; -Live = only agents whose status file is RUNNING
# Store: C:\KenshiTestRuns\agents\ids.json (name -> {id, session, at}). An id is only valid while the spawner's session lives
# (a dead tail's agents are DEAD with it: respawn fresh instead, see session-start.ps1).
param(
    [Parameter(Position = 0)][string]$Command = 'list',
    [Parameter(Position = 1)][string]$Name = '',
    [Parameter(Position = 2)][string]$Id = '',
    [Parameter(Position = 3)][string]$Session = '',
    [switch]$Live
)
$ErrorActionPreference = 'Stop'
$store = 'C:\KenshiTestRuns\agents\ids.json'
function Load { if (Test-Path $store) { $o = Get-Content $store -Raw | ConvertFrom-Json; $h = @{}; if ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value } }; $h } else { @{} } }
function Save($h) { $tmp = "$store.tmp"; ($h | ConvertTo-Json -Depth 4) | Set-Content -Path $tmp -Encoding UTF8; Move-Item -Force $tmp $store }
$db = Load
switch ($Command.ToLower()) {
    'add' {
        if (-not $Name -or -not $Id) { Write-Error 'usage: agent-ids.ps1 add <name> <agentId> [<session>]'; exit 2 }
        if (-not $Session -and (Test-Path 'C:\KenshiTestRuns\coordinator.current')) { try { $Session = (Get-Content 'C:\KenshiTestRuns\coordinator.current' -Raw | ConvertFrom-Json).session } catch {} }
        $db[$Name] = @{ id = $Id; session = $Session; at = (Get-Date).ToString('s') }
        Save $db; "recorded $Name -> $Id"
    }
    'get' {
        if (-not $db.ContainsKey($Name)) { Write-Error "no id recorded for '$Name'"; exit 1 }
        $db[$Name].id
    }
    'list' {
        foreach ($k in ($db.Keys | Sort-Object)) {
            $v = $db[$k]
            $st = ''
            $sf = "C:\KenshiTestRuns\agents\$k.status"
            if (Test-Path $sf) { $st = ((Get-Content $sf -TotalCount 1) -split '\|')[1].Trim() }
            if ($Live -and $st -ne 'RUNNING') { continue }
            $age = [int]((Get-Date) - [datetime]$v.at).TotalMinutes
            '{0,-28} {1,-20} {2,-10} {3}m {4}' -f $k, $v.id, $st, $age, $v.session
        }
    }
    default { Write-Error "unknown command '$Command' (add|get|list)"; exit 2 }
}
