# spawn-wp-session.ps1 <name> <tier-or-case> <prompt-file> [-Program <p> -Wp <wp>] [-Task "<text>"] [-PermissionMode auto] [-DryRun]
# Launches a work-package agent as an INDEPENDENT Claude Code session: its own terminal window, its own process tree, NOT a subagent of
# any coordinator, so it outlives the coordinator that started it and a later coordinator can adopt it (Shay 2026-10-15; subagents die
# with the session that spawned them). Needs no LLM: the supervisor / watchdog can call it. Same launch pattern as
# ~/.claude/hooks/context-meter.ps1 `handoff` and coord-supervisor.ps1 (new PowerShell window, CLAUDE* session markers dropped,
# `claude '<prompt>' --add-dir ...`), made robust by a generated launcher script (no quoting of long prompts on a command line).
#   <name>          agent name (letters digits _ . -); the status file is agents\<name>.status
#   <tier-or-case>  a case (patch generate debug investigate escalate read ...) or a tier (kenshi-generator ...) of model-policy.json;
#                   model and effort are taken from the tier (claude --model <m> --effort <e>)
#   <prompt-file>   the task brief (see docs/WP_SIZING.md section 7); the standard independent-agent block is appended to a copy
#   -Program/-Wp    record the session on that work package of C:\KenshiTestRuns\programs\<program>.json (program-ledger.ps1 session)
#   -Task           one-line task text for agent-status.ps1 (default: first line of the prompt)
#   -PermissionMode claude --permission-mode value (default auto: the permission classifier approves routine work, no prompt blocks an
#                   unattended session). 'default' passes no flag. Never bypassPermissions unless Shay orders it.
#   -Model/-Effort  override the policy (for tests)
#   -Force          spawn even when agent-session-live.ps1 says the same name is LIVE
#   -DryRun         write every file (prompt copy, launcher, session.json, ledger entry) but do NOT start claude/status/inflight marker
# Files (C:\KenshiTestRuns, or KAH_RUNS_DIR): agents\<name>.prompt.md  agents\<name>.launch.ps1  agents\<name>.session.json (schema in
#   docs/WP_SIZING.md section 10)  agents\<name>.status (RUNNING)  inflight\<name>  inbox\<name>\  programs\<program>.json (sessions field).
# Output: one line "SPAWNED <name> launcher_pid=<n> claude_pid=<n|?> model=<m> effort=<e> session_json=<path>" (DRYRUN <name> ... with -DryRun).
param(
    [Parameter(Mandatory, Position = 0)][string]$Name,
    [Parameter(Mandatory, Position = 1)][string]$TierOrCase,
    [Parameter(Mandatory, Position = 2)][string]$PromptFile,
    [string]$Program = '',
    [string]$Wp = '',
    [string]$Task = '',
    [string]$PermissionMode = 'auto',
    [string]$Model = '',
    [string]$Effort = '',
    [switch]$Force,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$runs = if ($env:KAH_RUNS_DIR) { $env:KAH_RUNS_DIR } else { 'C:\KenshiTestRuns' }
$work = 'C:\KenshiModding'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if ($Name -notmatch '^[A-Za-z0-9_.-]+$') { throw "bad agent name '$Name'" }
if ($Program -and $Program -notmatch '^[A-Za-z0-9_.-]+$') { throw "bad program '$Program'" }
if ($Wp -and $Wp -notmatch '^[A-Za-z0-9_.-]+$') { throw "bad wp '$Wp'" }
if ($PermissionMode -notmatch '^[A-Za-z]+$') { throw "bad permission mode '$PermissionMode'" }
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) { throw "prompt file not found: $PromptFile" }
if (($Program -and -not $Wp) -or ($Wp -and -not $Program)) { throw '-Program and -Wp go together' }

# ---- model + effort from the policy ----
$pol = Get-Content -Raw -LiteralPath (Join-Path $here 'model-policy.json') | ConvertFrom-Json
$tier = $null
if ($pol.cases.PSObject.Properties[$TierOrCase]) { $tier = [string]$pol.cases.$TierOrCase }
elseif ($pol.tiers.PSObject.Properties[$TierOrCase]) { $tier = $TierOrCase }
else { throw "unknown case/tier '$TierOrCase' (cases: $(@($pol.cases.PSObject.Properties.Name) -join ', '); tiers: $(@($pol.tiers.PSObject.Properties.Name) -join ', '))" }
if (-not $Model) { $Model = [string]$pol.tiers.$tier.model }
if (-not $Effort) { $Effort = [string]$pol.tiers.$tier.effort }
if ($Model -notmatch '^[A-Za-z0-9._-]+$' -or $Effort -notmatch '^[a-z]+$') { throw "bad model/effort '$Model'/'$Effort'" }

$ad = Join-Path $runs 'agents'
New-Item -ItemType Directory -Force -Path $ad, (Join-Path $runs "inbox\$Name") | Out-Null
$promptOut = Join-Path $ad "$Name.prompt.md"
$launcher = Join-Path $ad "$Name.launch.ps1"
$sessJson = Join-Path $ad "$Name.session.json"
$statusF = Join-Path $ad "$Name.status"

# ---- refuse to double-spawn a live session ----
if ((Test-Path -LiteralPath $sessJson) -and -not $Force -and -not $DryRun) {
    $live = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-session-live.ps1') $Name
    if ("$live" -like 'LIVE*') { throw "session '$Name' is already LIVE ($live); use a fresh successor name (${Name}2) or -Force" }
}

# ---- prompt copy = brief + standard independent-agent block ----
$brief = Get-Content -Raw -LiteralPath $PromptFile
if (-not $Task) { $Task = (($brief -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1) -replace '[\r\n]+', ' ') }
$Task = ($Task -replace '["`]', "'")
if ($Task.Length -gt 160) { $Task = $Task.Substring(0, 160) }
$ctx = if ($Program) { "program $Program, work package $Wp" } else { 'no program ledger entry' }
$std = @"


---
## Independent session rules (appended by spawn-wp-session.ps1; you are NOT a subagent)
You are the independent Claude Code session "$Name" ($ctx, model $Model, effort $Effort). The coordinator that started you may end at any time; you keep working and a later coordinator adopts you from your files. There is no SubagentHandback and no parent to message: everything you report goes to FILES.
1. STATUS / HEARTBEAT: run ``powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\agent-status.ps1 $Name RUNNING "<task>" "<latest step>" "<output paths>" "<next step>"`` at start, after every milestone and at least every 5 minutes of work (more than 10 minutes silent = you are judged DEAD by agent-session-live.ps1 and a fresh session may be spawned over you). The environment variable KAH_AGENT_NAME=$Name is already set in your shell.
2. CHECKPOINT every milestone or ~40k tokens: regenerate your patch/outputs, compile-check, commit and push verified work per the project rules, update the status ``latest`` and your handoff file C:\KenshiTestRuns\agents\$Name.handoff.md.
3. INBOX: other sessions reach you by dropping a file in C:\KenshiTestRuns\inbox\$Name\ . At every checkpoint run ``Get-ChildItem C:\KenshiTestRuns\inbox\$Name -File`` ; read each file, act on it, move it to C:\KenshiTestRuns\inbox\$Name\delivered\ . While waiting for a long job run ``bash C:/KenshiModding/tools/automation/event-wait.sh --me $Name`` in the background instead of sleep loops (sleeps over 120 s are denied).
4. AT ~150k TOKENS (context warn): finish the edit, checkpoint, write the handoff, then ``agent-status.ps1 $Name STOPPED-CONTEXT ...``. Your successor is a FRESH session named ${Name}2 (spawn-wp-session.ps1), never a resume of you.
5. WHEN FINISHED (or stuck after 3 failed attempts): write the full report with ``save-report.ps1 $Name`` (C:\KenshiModding\tools\automation\save-report.ps1, report text on stdin; saves agents\out\$Name\latest.md), then ``agent-status.ps1 $Name DONE`` (or FAILED) with that path in outputs, then drop ONE message file C:\KenshiTestRuns\inbox\coordinator\<yyyyMMdd-HHmmss>-$Name.msg containing: ``$Name <DONE|FAILED|STOPPED-CONTEXT>: <one sentence>; report <path>``. Then end your turn with a 3-line summary and do not wait for input.
6. The standard agent block in C:\KenshiModding\testing\AGENT_PROMPTS.md (game rules, batch/queue rules, report rules, speed rules) applies to you as written. Never touch another agent's work, Shay's live install, server tree, DB or saves.
"@
[IO.File]::WriteAllText($promptOut, $brief.TrimEnd() + $std, $utf8)

# ---- launcher script (runs inside the new window) ----
$sid = [guid]::NewGuid().ToString()
$bootstrap = "You are the independent agent $Name. Read $promptOut now and follow it exactly (the brief first, then the independent session rules at its end). Start by running agent-status.ps1 as rule 1 says."
$permArg = if ($PermissionMode -ieq 'default') { '' } else { "'--permission-mode', '$PermissionMode', " }
$launchText = @"
# generated by spawn-wp-session.ps1 for $Name; run in its own window
`$ErrorActionPreference = 'Continue'
`$Host.UI.RawUI.WindowTitle = '$Name'
Get-ChildItem Env: | Where-Object { `$_.Name -like 'CLAUDE*' -and -not [Environment]::GetEnvironmentVariable(`$_.Name, 'User') -and -not [Environment]::GetEnvironmentVariable(`$_.Name, 'Machine') } | ForEach-Object { Remove-Item -LiteralPath "Env:`$(`$_.Name)" -ErrorAction SilentlyContinue }
`$env:KAH_AGENT_NAME = '$Name'
Set-Location '$work'
& claude '$bootstrap' '--model', '$Model', '--effort', '$Effort', ${permArg}'--session-id', '$sid', '-n', '$Name', '--add-dir', '$work', '$runs'
`$code = `$LASTEXITCODE
try {
    `$j = Get-Content -LiteralPath '$sessJson' -Raw | ConvertFrom-Json
    `$j | Add-Member -NotePropertyName exited -NotePropertyValue (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz') -Force
    `$j | Add-Member -NotePropertyName exit_code -NotePropertyValue `$code -Force
    [IO.File]::WriteAllText('$sessJson', (`$j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
} catch { }
"@
[IO.File]::WriteAllText($launcher, $launchText, $utf8)
$null = [scriptblock]::Create($launchText)   # must parse

function Write-Session($o) { [IO.File]::WriteAllText($sessJson, ($o | ConvertTo-Json -Depth 6), $utf8) }
$sess = [ordered]@{
    name = $Name; program = $Program; wp = $Wp; tier = $tier; model = $Model; effort = $Effort; permission_mode = $PermissionMode
    claude_session_id = $sid; workdir = $work; title = $Name; mode = 'terminal'
    prompt_file = $promptOut; launch_script = $launcher; status_file = $statusF; inbox = (Join-Path $runs "inbox\$Name")
    started = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'); launcher_pid = 0; launcher_start = ''; claude_pid = 0; claude_start = ''
    spawned_by_pid = $PID; dry_run = [bool]$DryRun
}
Write-Session $sess

# ---- ledger entry (before RUNNING, so agent-status's sync finds the WP) ----
$pl = Join-Path $here 'program-ledger.ps1'
function Record-Ledger([int]$lp, [int]$cp) {
    if (-not $Program) { return }
    try {
        $la = @('session', $Program, $Wp, $Name, "$lp"); if ($cp -gt 0) { $la += "$cp" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $pl @la | Out-Null
    } catch { Write-Warning "ledger session entry failed: $($_.Exception.Message)" }
}

if ($DryRun) {
    Record-Ledger 0 0
    "DRYRUN $Name model=$Model effort=$Effort permission=$PermissionMode launcher=$launcher prompt=$promptOut session_json=$sessJson"
    return
}

# ---- start: status RUNNING (heartbeat 0 + inflight marker), then the window ----
Record-Ledger 0 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-status.ps1') $Name RUNNING $Task 'launching independent session' $promptOut 'agent starts, then heartbeats here' | Out-Null
$proc = Start-Process -FilePath (Get-Process -Id $PID).Path -WorkingDirectory $work -WindowStyle Normal -PassThru -ErrorAction Stop `
    -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$launcher`"")
$sess.launcher_pid = $proc.Id
try { $sess.launcher_start = $proc.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } catch { }
Write-Session $sess
# find the claude process the launcher window starts (child of the launcher shell), up to 40 s
$cp = 0
for ($i = 0; $i -lt 80 -and -not $cp; $i++) {
    Start-Sleep -Milliseconds 500
    $kid = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(claude|node)\.exe$' })
    if ($kid.Count) {
        $cp = [int]$kid[0].ProcessId
        try { $sess.claude_start = (Get-Process -Id $cp).StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') } catch { }
    }
    if ($proc.HasExited) { break }
}
$sess.claude_pid = $cp
Write-Session $sess
Record-Ledger $proc.Id $cp
"SPAWNED $Name launcher_pid=$($proc.Id) claude_pid=$(if ($cp) { $cp } else { '?' }) model=$Model effort=$Effort session_json=$sessJson"
