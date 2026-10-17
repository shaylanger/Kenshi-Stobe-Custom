#!/usr/bin/env python3
"""cut3-make-candidates.py: build the brief-template candidates for credit cut #3 by ANCHOR PATCHES (every anchor must match exactly once).
Never edits the live files (queued/running briefs may be generated from them):
  tools/automation/lane-brief.ps1  -> lane-brief.ps1.cut3.candidate
  testing/AGENT_PROMPTS.md         -> testing/AGENT_PROMPTS.md.cut3.candidate
Swap (after the hooks are wired): see C:\\KenshiTestRuns\\inbox\\operators\\cut3.txt section 3. Re-run is idempotent (rebuilds from the live files).
Usage: python cut3-make-candidates.py [repo_root]   (default C:/KenshiModding)
"""
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'C:/KenshiModding'
NOTE = r'powershell -NoProfile -File C:\KenshiModding\tools\automation\agent-note.ps1'


def patch(path, edits):
    with open(path, 'r', encoding='utf-8', newline='') as f:
        s = f.read()
    crlf = '\r\n' in s
    s = s.replace('\r\n', '\n')
    for label, old, new in edits:
        n = s.count(old)
        if n != 1:
            raise SystemExit('ANCHOR FAIL (%d matches) in %s: %s' % (n, os.path.basename(path), label))
        s = s.replace(old, new)
    if crlf:
        s = s.replace('\n', '\r\n')
    out = path + '.cut3.candidate'
    with open(out, 'w', encoding='utf-8', newline='') as f:
        f.write(s)
    print('wrote', out, '(%d edits)' % len(edits))


# ------------------------------------------------------------------ lane-brief.ps1
lb = os.path.join(ROOT, 'tools/automation/lane-brief.ps1')
patch(lb, [
    ('pilot Status rule',
     "'- Status: agent-status.ps1 at start and after every row (pilot-mark.sh does it for you after each call); silence > 20 min = killed. Keep your handoff file current.",
     "'- Status is AUTOMATIC (cut3): no status-call turns; hooks write RUNNING, progress and the end state. Note a successor must read: agent-note.ps1 <name> \"<step>\" ; <next real command>. Silence > 20 min = killed. Keep your handoff file current."),
    ('operator Status discipline',
     "'- Status discipline: agent-status after EVERY row (silence > 20 min = killed); keep the handoff file current.",
     "'- Status (cut3): NO status calls; hooks write RUNNING, progress (5 min) and DONE/FAILED/STOPPED-CONTEXT from your final message; status-mark.sh logs rows. Successor-visible note: agent-note.ps1 <name> \"<step>\" \"<out>\" \"<next>\" ; <real command>. Silence > 20 min = killed; keep the handoff current."),
    ('successor first status call',
     '''        $null = $sb.AppendLine("  first status call (paste): $as $Name RUNNING `"$taskQ`" `"started, reading brief`" `"<evidence dir>`" `"wait for $Predecessor handoff`"")''',
     '''        $null = $sb.AppendLine("  first status call: none (SubagentStart hook writes RUNNING from agents\$Name.task). Hooks off: $as $Name RUNNING `"$taskQ`" `"started`" `"<ev>`" `"wait for $Predecessor`"")'''),
    ('Commands status line',
     '''    $null = $sb.AppendLine("- status: $as $Name RUNNING `"$taskQ`" `"<row/step>`" `"<evidence dir>`" `"<next row>`"   (DONE|FAILED|STOPPED-CONTEXT when ending)")''',
     '''    $null = $sb.AppendLine("- status: AUTOMATIC. Merged note: $as_note $Name `"<step>`" `"<ev dir>`" `"<next>`" ; <command>  (-State STOPPED-CONTEXT|FAILED|DONE to end)")'''),
    ('Commands warn line',
     '''    $null = $sb.AppendLine("- context warning (~120k): $as $Name RUNNING `"$taskQ`" `"WARN-120k <row/step>`" `"<evidence dir>`" `"<next row>`"   (writes agents\\$Name.warn)")''',
     '''    $null = $sb.AppendLine("- context warning (~120k): $as_note $Name `"WARN-120k <step>`" `"<ev dir>`" `"<next>`" ; <command>  (writes agents\$Name.warn)")'''),
    ('define $as_note',
     "$as = 'powershell -NoProfile -File C:\\KenshiModding\\tools\\automation\\agent-status.ps1'\n",
     "$as = 'powershell -NoProfile -File C:\\KenshiModding\\tools\\automation\\agent-status.ps1'\n$as_note = 'powershell -NoProfile -File C:\\KenshiModding\\tools\\automation\\agent-note.ps1'\n"),
    ('write agents\\<Name>.task beside the brief',
     '$text\n[Console]::Error.WriteLine("lane-brief: $Lane brief size',
     '# cut3: the SubagentStart hook (hooks\\agent-status-hook.py) writes RUNNING with the exact task text the agent-guard successor rule needs\n'
     'if ($Out -and $PSBoundParameters.ContainsKey(\'Name\') -and $Name) { try { [System.IO.File]::WriteAllText((Join-Path $ag "$Name.task"), $taskTxt, (New-Object System.Text.UTF8Encoding($false))) } catch { } }\n'
     '$text\n[Console]::Error.WriteLine("lane-brief: $Lane brief size'),
])

# ------------------------------------------------------------------ AGENT_PROMPTS.md
ap = os.path.join(ROOT, 'testing/AGENT_PROMPTS.md')
patch(ap, [
    ('standard block status instruction',
     '''> Your name is `<name>`. Report to a file, not only to this session: run
> `powershell -NoProfile -ExecutionPolicy Bypass -File C:\\KenshiModding\\tools\\automation\\agent-status.ps1 <name> RUNNING "<task>" "<latest step>" "<output paths>" "<next step>"`
> at start and after every milestone, and with DONE or FAILED plus the final result paths before your final report.''',
     '''> Your name is `<name>` (put `[status-name:<name>]` or "You are <name>" first in your brief so the hooks can read it). **Status is AUTOMATIC (cut3, 2026-10-16): do NOT spend a turn on a status call.**
> The SubagentStart / PostToolUse / SubagentStop hooks (`tools\\automation\\hooks\\agent-status-hook.py`) write RUNNING at spawn, stamp `latest:` from your tool calls every 5 min, and close the status from your final message
> (DONE; FAILED when its first line says FAILED or it is empty; STOPPED-CONTEXT when it contains that word). A milestone a successor must read (an outputs path, a next step) is MERGED into your next real command, never its own turn:
> `powershell -NoProfile -File C:\\KenshiModding\\tools\\automation\\agent-note.ps1 <name> "<step>" "<output paths>" "<next step>" ; <real command>` (Git Bash: `powershell.exe -NoProfile -File C:/KenshiModding/tools/automation/agent-note.ps1 <name> "<step>" ; <real command>`; row recorders `status-mark.sh` / `pilot-mark.sh` already do it). Ending as STOPPED-CONTEXT: add `-State STOPPED-CONTEXT` to that merged call after the handoff file is written. A status you write yourself (`agent-status.ps1 ... DONE`) still works and wins: the hook never touches a non-RUNNING status.'''),
    ('Reports line DONE first',
     '''`agent-status.ps1 <name> DONE ... "<that path>"` first.''',
     '''the hook closes your status as DONE from this hand-back (put the saved path in it); no separate status call.'''),
    ('Status cadence',
     '''update your status file (`agent-status.ps1 <name> RUNNING ...`) at least every 10 min, also during long waits (game load, batch, sleep).''',
     '''the hooks stamp your status every 5 min while you make tool calls (no status call): during long waits keep polling with 30-120 s calls (or merge `agent-note.ps1 <name> "waiting: <what>" ;` into the poll). Wait-type calls only (Monitor/sleep/event-wait) for > 20 min stop the stamps on purpose, so a spinning poller still goes stale.'''),
])
