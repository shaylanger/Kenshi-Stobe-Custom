#!/usr/bin/env python3
"""Bug 112: looted weapons count as 0, goal ends "found no weapons to take".

The loot step counts progress as the change in the looter's pack
(_allItems). Weapons handed over go straight into her weapon slots, so the
count stays 0 although both Iron Clubs moved. Count what the transfer moved
when that is more than the pack difference.

Usage: patch_r21_bug112_loot_count.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
old = "        if(moved>0||after>before){g->completed+=after-before;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;}\n"
new = ("        int got=after-before;if(moved>got)got=moved; /* bug 112: equipped on arrival = not in the pack */\n"
       "        if(got>0){g->completed+=got;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;}\n")
if new in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
