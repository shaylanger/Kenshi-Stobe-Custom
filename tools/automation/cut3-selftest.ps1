# cut3-selftest.ps1: selftest for hooks\agent-status-hook.py, agent-note.ps1, status-digest.ps1 (credit cut #3). Temp runs dir only (KAH_RUNS_DIR).
# Proves: auto RUNNING/stamp/DONE/FAILED/STOPPED-CONTEXT, throttle, wait cap, ownership, no resurrection, AND that stall/dead-agent detection
# (agent-guard-lib Get-AgentReport: ORPHANED after 30 min, NO SUCCESSOR for FAILED/STOPPED-CONTEXT) is unchanged by the hook.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$py = 'C:\Users\Shay\AppData\Local\Programs\Python\Python312\python.exe'; if (-not (Test-Path $py)) { $py = 'python' }
$hook = Join-Path $here 'hooks\agent-status-hook.py'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('cut3-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ag = Join-Path $tmp 'agents'; New-Item -ItemType Directory -Force -Path $ag, (Join-Path $tmp 'inflight'), (Join-Path $tmp 'respawn'), (Join-Path $tmp 'proj\sess1\subagents') | Out-Null
$env:KAH_RUNS_DIR = $tmp; $env:KAH_STATUS_HOOK_ANYCWD = '1'
$pass = 0; $fail = 0
function T($ok, $msg) { if ($ok) { $script:pass++; "PASS $msg" } else { $script:fail++; "FAIL $msg" } }
function Hook($obj) { $obj.cwd = 'C:\KenshiModding'; $obj.session_id = 'sess1'; $obj.transcript_path = (Join-Path $tmp 'proj\sess1.jsonl'); ($obj | ConvertTo-Json -Depth 6 -Compress) | & $py -I $hook }
function NewAgent($aid, $prompt) {
    $m = @{ type = 'user'; message = @{ role = 'user'; content = $prompt } } | ConvertTo-Json -Depth 5 -Compress
    Set-Content -LiteralPath (Join-Path $tmp "proj\sess1\subagents\agent-$aid.jsonl") -Value $m -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmp "proj\sess1\subagents\agent-$aid.meta.json") -Value '{"description":"[case:generate] selftest agent"}' -Encoding UTF8
}
function St($n) { $f = Join-Path $ag "$n.status"; if (Test-Path $f) { Get-Content $f } else { @() } }
function State($n) { $l = @(St $n); if ($l.Count) { (($l[0] -replace '^\uFEFF', '') -split '\s*\|\s*')[1] } else { 'none' } }
function Reg($aid) { Get-Content -Raw (Join-Path $tmp "agents\auto\$aid.json") | ConvertFrom-Json }
function SetReg($aid, $k, $v) { $p = Join-Path $tmp "agents\auto\$aid.json"; $o = Get-Content -Raw $p | ConvertFrom-Json; $o | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force; ($o | ConvertTo-Json) | Set-Content $p -Encoding UTF8 }
try {
    # ---- 1. SubagentStart: name from the brief, RUNNING + inflight marker through the real agent-status.ps1
    NewAgent 'aaa1' "You are imm26-x1 for the workspace. Keep C:\KenshiTestRuns\agents\imm26-x1.status current via tools/automation/agent-status.ps1."
    Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa1'; agent_type = 'general-purpose' }
    T ((State 'imm26-x1') -eq 'RUNNING') 'start: status RUNNING written for the name found in the brief'
    T (Test-Path (Join-Path $tmp 'inflight\imm26-x1')) 'start: inflight marker created by agent-status.ps1'
    T (((St 'imm26-x1') -join ' ') -match 'started \(auto') 'start: latest says auto start'
    # ---- name resolution variants
    NewAgent 'aaa2' "[status-name:wpA2] do things"; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa2' }
    T ((State 'wpA2') -eq 'RUNNING') 'name: [status-name:] tag wins'
    NewAgent 'aaa3' "You are Fixer #26 in the Kenshi modding workspace"; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa3' }
    T (-not (Test-Path (Join-Path $ag 'Fixer.status'))) 'name: "You are Fixer #26" (bare word) is NOT turned into a status file'
    NewAgent 'aaa4' 'run agent-status.ps1 wp-b RUNNING "t" "s"'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa4' }
    T ((State 'wp-b') -eq 'RUNNING') 'name: agent-status.ps1 <name> RUNNING pattern'
    # ---- 2. PostToolUse throttle + stamp
    $f = Join-Path $ag 'imm26-x1.status'; $t0 = (Get-Item $f).LastWriteTime
    Start-Sleep -Milliseconds 1100
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa1'; tool_name = 'Bash'; tool_input = @{ command = 'bash run-batch.sh list.txt' } }
    T ((Get-Item $f).LastWriteTime -eq $t0) 'post: first call inside the throttle window does not rewrite the file'
    T ((Reg 'aaa1').calls -eq 1) 'post: call counted in the registry'
    SetReg 'aaa1' 'last_stamp' 1
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa1'; tool_name = 'Bash'; tool_input = @{ command = 'bash run-batch.sh list.txt' } }
    T (((St 'imm26-x1') -join ' ') -match 'latest: auto \d\d:\d\d \[calls=2\] Bash: bash run-batch.sh') 'post: due call stamps latest from the tool call'
    T ((State 'imm26-x1') -eq 'RUNNING' -and (Get-Item $f).LastWriteTime -gt $t0) 'post: stays RUNNING, mtime refreshed'
    T (((St 'imm26-x1') -join ' ') -match 'task: ' -and ((St 'imm26-x1') | Select-String 'task: auto:')) 'post: task line preserved'
    # manual latest kept for 10 min
    & powershell.exe -NoProfile -File (Join-Path $here 'agent-note.ps1') 'imm26-x1' 'milestone: rows 1-3 done' 'C:\out\x' 'run 4-6' | Out-Null
    T (((St 'imm26-x1') -join ' ') -match 'latest: milestone: rows 1-3 done' -and ((St 'imm26-x1') -join ' ') -match 'outputs: C:\\out\\x') 'note: agent-note.ps1 writes the milestone, keeps RUNNING and task'
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa1'; tool_name = 'Bash'; tool_input = @{ command = 'powershell agent-note.ps1 imm26-x1 "m"; ls' } }
    SetReg 'aaa1' 'last_stamp' 1
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa1'; tool_name = 'Read'; tool_input = @{ file_path = 'C:\x\y.txt' } }
    T (((St 'imm26-x1') -join ' ') -match 'latest: milestone: rows 1-3 done') 'post: a fresh manual milestone is not overwritten by the auto stamp'
    # ---- 3. wait cap: only wait-type calls for > 20 min -> no more stamps (a spinning poller goes stale)
    SetReg 'aaa1' 'last_stamp' 1; SetReg 'aaa1' 'progress_at' ((Get-Date).AddMinutes(-30).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds)
    $t1 = (Get-Item $f).LastWriteTime; Start-Sleep -Milliseconds 1100
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa1'; tool_name = 'Monitor'; tool_input = @{ description = 'wait' } }
    T ((Get-Item $f).LastWriteTime -eq $t1) 'wait-cap: wait-only calls past 20 min do not keep the status fresh'
    # ---- 4. dead agent detection unchanged
    . (Join-Path $here 'agent-guard-lib.ps1')
    (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-50)
    $rep = Get-AgentReport
    T (@($rep.Orphaned | Where-Object Name -eq 'imm26-x1').Count -eq 1) 'dead: a RUNNING status with no stamps for 50 min is ORPHANED (hook did not hide it)'
    T (@($rep.InFlight | Where-Object Name -eq 'imm26-x1').Count -eq 0) 'dead: and not counted in-flight'
    # a dead agent makes no calls: another agent's calls do not touch its file
    SetReg 'aaa2' 'last_stamp' 1
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa2'; tool_name = 'Bash'; tool_input = @{ command = 'ls' } }
    T ((Get-Item $f).LastWriteTime -lt (Get-Date).AddMinutes(-49)) 'dead: other agents never stamp this status'
    # ---- 5. SubagentStop
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'aaa2'; last_assistant_message = "PASS rows 1-3. 1 earlier attempt FAILED then fixed.`nfiles: x" }
    T ((State 'wpA2') -eq 'DONE') 'stop: normal hand-back -> DONE (a FAILED word inside the text is not FAILED)'
    T (-not (Test-Path (Join-Path $tmp 'inflight\wpA2'))) 'stop: DONE deletes the inflight marker'
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'aaa4'; last_assistant_message = "FAILED: compile error in x.cpp after 3 attempts" }
    T ((State 'wp-b') -eq 'FAILED' -and (Test-Path (Join-Path $tmp 'inflight\wp-b'))) 'stop: first line FAILED -> FAILED, marker kept'
    $rep = Get-AgentReport
    T (@($rep.Open | Where-Object Name -eq 'wp-b').Count -eq 1) 'stop: FAILED agent with no successor is reported NO SUCCESSOR (Stop-hook guard intact)'
    NewAgent 'aaa5' 'You are wp-c1. [status-name:wp-c1]'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa5' }
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'aaa5'; last_assistant_message = '' }
    T ((State 'wp-c1') -eq 'FAILED') 'stop: empty final message -> FAILED, never DONE (a killed agent is not hidden)'
    NewAgent 'aaa6' '[status-name:wp-d1] go'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'aaa6' }
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'aaa6'; last_assistant_message = "STOPPED-CONTEXT at 150k; successor wp-d2 resumes from handoff" }
    T ((State 'wp-d1') -eq 'STOPPED-CONTEXT' -and (Test-Path (Join-Path $tmp 'respawn\wp-d1.todo'))) 'stop: STOPPED-CONTEXT -> status + respawn todo'
    # already reported by the agent itself: untouched
    $before = (St 'wpA2') -join '|'
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'aaa2'; last_assistant_message = 'x' }
    T ((St 'wpA2') -join '|' -eq $before) 'stop: an agent that already wrote DONE is left alone'
    # no resurrection: PostToolUse after DONE does not rewrite
    SetReg 'aaa2' 'last_stamp' 1
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'aaa2'; tool_name = 'Bash'; tool_input = @{ command = 'ls' } }
    T ((State 'wpA2') -eq 'DONE') 'post: a DONE status is never resurrected to RUNNING'
    # ---- 6. ownership: successor takes the name, old agent's stop does not close it
    NewAgent 'bbb1' '[status-name:wp-e] first'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'bbb1' }
    NewAgent 'bbb2' '[status-name:wp-e] second'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'bbb2' }
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'bbb1'; last_assistant_message = 'late stop of the old owner' }
    T ((State 'wp-e') -eq 'RUNNING') 'owner: the old agent id cannot close a name a newer agent now owns'
    # abandoned
    NewAgent 'ccc1' '[status-name:wp-f] x'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'ccc1' }
    Set-Content (Join-Path $ag 'wp-f.abandoned') 'why'
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'ccc1'; last_assistant_message = 'ok' }
    T ((State 'wp-f') -eq 'RUNNING') 'abandoned: left alone'
    # main session call (no agent_id) is a no-op
    $n0 = @(Get-ChildItem (Join-Path $tmp 'agents\auto') -Filter *.json).Count
    Hook @{ hook_event_name = 'PostToolUse'; tool_name = 'Bash'; tool_input = @{ command = 'ls' } }
    T (@(Get-ChildItem (Join-Path $tmp 'agents\auto') -Filter *.json).Count -eq $n0) 'main: calls without agent_id do nothing'
    # unresolvable name: no file, no crash
    NewAgent 'ddd1' 'hello, count to ten'; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'ddd1' }
    Hook @{ hook_event_name = 'PostToolUse'; agent_id = 'ddd1'; tool_name = 'Bash'; tool_input = @{ command = 'ls' } }
    Hook @{ hook_event_name = 'SubagentStop'; agent_id = 'ddd1'; last_assistant_message = 'ten' }
    T ($LASTEXITCODE -eq 0) 'unresolved: no name -> hook exits 0 and writes nothing'
    # real-brief shapes (taken from live transcripts): backticks, trailing dot, "lane operator", Routing header, predecessor mentioned later
    NewAgent 'eee1' ("Routing: case=bench tier=x ticket=`nYou are ``imm26-rv1``, the FRESH successor of imm26-rv0 (see agent-status.ps1 imm26-rv0 DONE)"); Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'eee1' }
    NewAgent 'eee2' "Routing: case=x tier=y ticket=`nYou are lane operator imm26-rv-i3op9 for lane 5090-i3."; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'eee2' }
    NewAgent 'eee3' "You are imm26-inv9. Investigate only."; Hook @{ hook_event_name = 'SubagentStart'; agent_id = 'eee3' }
    T ((State 'imm26-rv1') -eq 'RUNNING' -and (State 'imm26-rv0') -eq 'none') 'name: backticked You-are beats a predecessor named in an agent-status example'
    T ((State 'imm26-rv-i3op9') -eq 'RUNNING' -and (State 'imm26-inv9') -eq 'RUNNING') 'name: "lane operator NAME" and trailing-dot forms'
    # ---- 7. digest
    $dg = (& powershell.exe -NoProfile -File (Join-Path $here 'status-digest.ps1') -NoLanes -Consumer t1 | Out-String)
    T ($dg -match 'DIGEST \d\d:\d\d run=\d+ finished_since=\d+ problems=\d+ alerts=0') 'digest: header line'
    T ($dg -match 'RUN  wp-e ' -and $dg -match 'DONE wpA2 ' -and $dg -match 'FAILED wp-b ' -and $dg -match 'PROBLEM ORPHANED .*imm26-x1') 'digest: running, finished, failed and ORPHANED agents all shown'
    $dg2 = (& powershell.exe -NoProfile -File (Join-Path $here 'status-digest.ps1') -NoLanes -Consumer t1 | Out-String)
    T ($dg2 -match 'finished_since=0') 'digest: second call by the same consumer shows nothing already reported'
    $lines = @($dg -split "`n" | Where-Object { $_.Trim() }).Count
    T ($lines -lt 40) "digest: compact ($lines lines)"
    # ---- 8. existing guard selftest still green
    $gs = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'agent-guard-selftest.ps1') 2>&1 | Out-String)
    T ($gs -notmatch '\bFAIL\b') 'existing agent-guard-selftest.ps1 has no FAIL'
    # ---- 9. template candidates (live files untouched; candidate brief parses, generates, stays under the size limit)
    $cand = Join-Path $here 'lane-brief.ps1.cut3.candidate'
    if (Test-Path $cand) {
        $pe = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($cand, [ref]$null, [ref]$pe)
        T ($pe.Count -eq 0) 'candidate lane-brief parses'
        $ct = Join-Path $here 'zz-cut3-lbtest.ps1'; Copy-Item $cand $ct
        try {
            $ErrorActionPreference = 'Continue'
            $lbo = (& powershell.exe -NoProfile -File $ct 4080-i4 -Out (Join-Path $tmp 'brief.txt') -Name imm26-t-op1 -Predecessor imm26-t-op0 -Runs $tmp -NoRemote 2>&1 | Out-String)
        } finally { $ErrorActionPreference = 'Stop'; Remove-Item $ct -Force -ErrorAction SilentlyContinue }
        $bt = if (Test-Path (Join-Path $tmp 'brief.txt')) { Get-Content -Raw (Join-Path $tmp 'brief.txt') } else { '' }
        T ($bt -match 'agent-note\.ps1 imm26-t-op1' -and $lbo -notmatch 'OVER LIMIT') 'candidate brief generates with agent-note text, under the size limit'
        T ((Get-Content -Raw (Join-Path $tmp 'agents\imm26-t-op1.task')) -eq '4080-i4 operator') 'candidate brief writes agents\<name>.task for the SubagentStart hook'
    }
} finally {
    Remove-Item Env:KAH_RUNS_DIR, Env:KAH_STATUS_HOOK_ANYCWD -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
"CUT3 SELFTEST pass=$pass fail=$fail"
if ($fail) { exit 1 }
