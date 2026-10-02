#!/usr/bin/env python3
"""Bug 124: "wait here for Lorn" becomes a plain hold, not a WAIT_FOR goal.

Run 9 (test 42): "Malzin, wait here for Lorn." -> "Fine." + HOLD_POSITION;
no task goal. The HoldPosition prompt hint maps every "wait here" to
HoldPosition. Waiting *for a named person* now points at WaitForGoal.

Usage: patch_r21_bug124_wait_for_hint.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'lib' / 'chat_helper_functions.php'
text = path.read_text(encoding='utf-8')
old = """        $actionLine .= " Requests such as 'wait here', 'stay here', or 'hold this position' should use HoldPosition when the NPC agrees to remain at the current spot; use Idle only when merely stopping the current activity without a hold-position intent.";
"""
new = old + """        if (in_array('WaitForGoal', $parts['actions'] ?? [], true)) { // bug 124
            $actionLine .= " Exception: waiting FOR a named person ('wait here for Lorn', 'wait until Wendy gets back') must use WaitForGoal with that person in target, not HoldPosition.";
        }
"""
if 'bug 124' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
