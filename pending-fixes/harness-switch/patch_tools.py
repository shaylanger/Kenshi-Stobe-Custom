#!/usr/bin/env python3
"""Harness switch-over, workspace tools (DRAFT, apply only at the switch-over).

stobe-auto and stobe-say keep their names and commands, so scenarios.sh,
stobe-guard.sh and stobe-goal-watch.sh need no change:
- tools/stobe-auto: now a wrapper around the harness client (kah.py)
- tools/stobe-say: sends through the harness inbox; Stobe's commands get the
  stobe_ prefix there, "speed" is the harness's own; on/off = enabled.flag
- tools/automation/kenshi-ctl.ps1: now a wrapper around the harness repo's
  kenshi-ctl.ps1 (this PC's paths; stobe.log and KenshiFP.log archived too)
- tools/automation/install-dll.ps1: new target "Harness"

Usage: patch_tools.py <workspace root, e.g. /mnt/c/KenshiModding> [--check]
Then copy tools/stobe-auto and tools/stobe-say to /usr/local/bin (WSL).
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
check = '--check' in sys.argv
tools = root / 'tools'
writes = {}


def sub(text, old, new, what):
    n = text.count(old)
    assert n == 1, f'{what}: anchor found {n}x: {old[:70]!r}'
    return text.replace(old, new)


# --- stobe-auto -> wrapper ---------------------------------------------------
old_auto = (tools / 'stobe-auto').read_text(encoding='utf-8')
if 'kah.py' not in old_auto:
    assert "INBOX = MOD + '/auto_inbox.txt'" in old_auto, 'stobe-auto: not the old client'
    writes[tools / 'stobe-auto'] = '''#!/usr/bin/env python3
"""stobe-auto: the Kenshi Automation Harness client (kah.py) with this PC's paths.

Same commands as before (status, wait-world, load, spawn, teleport, ...);
"stobe-auto help" lists them, incl. Stobe's stobe_* commands. Needs the
harness on ("stobe-say on" or "stobe-auto on").
"""
import os
import sys

os.environ.setdefault('KAH_DIR', r'D:\\Steam\\steamapps\\common\\Kenshi\\mods\\AutomationHarness')
KAH = '/mnt/c/KenshiModding/Kenshi-Automation-Harness/client/kah.py'
os.execvp('python3', ['python3', KAH] + sys.argv[1:])
'''

# --- stobe-say -> harness inbox ---------------------------------------------
say = (tools / 'stobe-say').read_text(encoding='utf-8')
if 'AutomationHarness' not in say:
    say = sub(say, '"""stobe-say: drive a running Kenshi through Stobe.dll\'s test inbox.\n',
              '"""stobe-say: drive a running Kenshi through Stobe\'s test commands\n'
              '(stobe_say, stobe_state, ...) in the Kenshi Automation Harness inbox.\n',
              'stobe-say docstring')
    say = sub(say, '  stobe-say on | off                 enable/disable the inbox (flag file)\n',
              '  stobe-say on | off                 enable/disable the harness (enabled.flag)\n',
              'stobe-say usage on/off')
    say = sub(say,
              "FLAG = MOD + '/test_inbox.flag'\n"
              "INBOX = MOD + '/test_inbox.txt'\n"
              "OUTBOX = MOD + '/test_outbox.txt'\n",
              "HARNESS = '/mnt/d/Steam/steamapps/common/Kenshi/mods/AutomationHarness'\n"
              "FLAG = HARNESS + '/enabled.flag'\n"
              "INBOX = HARNESS + '/inbox.txt'\n"
              "OUTBOX = HARNESS + '/outbox.txt'\n",
              'stobe-say paths')
    say = sub(say, "        f.write('\\t'.join((cid, cmd) + args) + '\\n')\n",
              "        # Stobe's commands are stobe_*; speed is the harness's own.\n"
              "        wire = cmd if cmd == 'speed' else 'stobe_' + cmd\n"
              "        f.write('\\t'.join((cid, wire) + args) + '\\n')\n",
              'stobe-say send')
    writes[tools / 'stobe-say'] = say

# --- kenshi-ctl.ps1 -> wrapper ----------------------------------------------
ctl_path = tools / 'automation' / 'kenshi-ctl.ps1'
ctl = ctl_path.read_text(encoding='utf-8')
if 'Kenshi-Automation-Harness' not in ctl:
    assert "Read-StobeLogMatch 'TEST_AUTO: frame listener running'" in ctl, 'kenshi-ctl: not the old script'
    writes[ctl_path] = r'''<#
kenshi-ctl.ps1 (workspace): the harness repo's kenshi-ctl.ps1 with this PC's
paths; also archives stobe.log and KenshiFP.log (both reset on launch).
Commands: status | launch [-Save x] | stop | restart [-Save x] | health | screenshot [-Save n]
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Save = '',
  [int]$TimeoutSec = 300
)
$Kenshi = 'D:\Steam\steamapps\common\Kenshi'
& 'C:\KenshiModding\Kenshi-Automation-Harness\tools\kenshi-ctl.ps1' $Command -Save $Save -TimeoutSec $TimeoutSec `
  -Kenshi $Kenshi -ArchiveRoot 'C:\KenshiTestRuns' `
  -ExtraLogs @("$Kenshi\RE_Kenshi\mods\Stobe\stobe.log", "$Kenshi\KenshiFP.log")
exit $LASTEXITCODE
'''

# --- install-dll.ps1: Harness target -----------------------------------------
inst_path = tools / 'automation' / 'install-dll.ps1'
inst = inst_path.read_text(encoding='utf-8')
if "'Harness'" not in inst:
    inst = sub(inst, 'install-dll.ps1 Stobe|KenshiFP: install', 'install-dll.ps1 Stobe|KenshiFP|Harness: install',
               'install-dll header')
    inst = sub(inst, "  KenshiFP  WSL /root/KenshiFP/re_plugin/KenshiFP.dll -> the Vortex KenshiFP folder\n",
               "  KenshiFP  WSL /root/KenshiFP/re_plugin/KenshiFP.dll -> the Vortex KenshiFP folder\n"
               "  Harness   Kenshi-Automation-Harness\\out\\AutomationHarness.dll -> Kenshi\\mods\\AutomationHarness\\\n",
               'install-dll usage')
    inst = sub(inst, "[ValidateSet('Stobe', 'KenshiFP')]", "[ValidateSet('Stobe', 'KenshiFP', 'Harness')]",
               'install-dll ValidateSet')
    inst = sub(inst,
               "                 'C:\\Users\\Shay\\AppData\\Roaming\\Vortex\\kenshi\\mods\\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\\KenshiFP\\KenshiFP.dll')\n}",
               "                 'C:\\Users\\Shay\\AppData\\Roaming\\Vortex\\kenshi\\mods\\KenshiFP RE V0.6.1 2063 1 2026-08-30T19-04Z mloL06QcG\\KenshiFP\\KenshiFP.dll')\n"
               "  'Harness'  = @('C:\\KenshiModding\\Kenshi-Automation-Harness\\out\\AutomationHarness.dll',\n"
               "                 'D:\\Steam\\steamapps\\common\\Kenshi\\mods\\AutomationHarness\\AutomationHarness.dll')\n}",
               'install-dll targets')
    writes[inst_path] = inst

if check:
    print('check ok: %d file(s) would change: %s' % (len(writes), ', '.join(p.name for p in writes)))
    sys.exit(0)
for path, text in writes.items():
    path.write_text(text, encoding='utf-8', newline='\n')
    print('updated', path)
if not writes:
    print('already patched')
