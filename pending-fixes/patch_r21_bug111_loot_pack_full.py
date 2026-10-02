#!/usr/bin/env python3
"""Bug 111: a full pack is reported as "found no weapons to take".

When the looter has no room, g_stg_give fails, the item goes back to the body
and the loot goal ends BLOCKED "found no <item> to take on the nearby bodies"
(or COMPLETE with items left behind). Remember that a hand-over failed for
lack of room and say so: BLOCKED "no room to carry ..." / COMPLETE "... left
the rest (no room)".

Usage: patch_r21_bug111_loot_pack_full.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
if 'g_stg_loot_no_room' in text:
    print('already patched')
    sys.exit(0)
edits = [
    ("static int g_stg_dirty;\n",
     "static int g_stg_dirty;\n"
     "static int g_stg_loot_no_room; /* bug 111: a hand-over failed for lack of room */\n"),
    ("        if(!g_stg_give(dst_char,det,0,0)){g_stg_add(src,det,actual,1,0);break;}\n",
     "        if(!g_stg_give(dst_char,det,0,0)){g_stg_add(src,det,actual,1,0);g_stg_loot_no_room=1;break;}\n"),
    ("    if(g->completed<=0){ /* bug 104: nothing taken is not \"done\" */\n"
     "        int matched=stg_loot_scan_log(gw,actor,g);\n"
     "        char r[256];\n"
     "        if(g->target[0]&&matched==0)snprintf(r,sizeof(r),\"couldn't find %s's body nearby\",g->target);\n",
     "    if(g->completed<=0){ /* bug 104: nothing taken is not \"done\" */\n"
     "        int matched=stg_loot_scan_log(gw,actor,g);\n"
     "        char r[256];\n"
     "        if(g->target[0]&&matched==0)snprintf(r,sizeof(r),\"couldn't find %s's body nearby\",g->target);\n"
     "        else if(g_stg_loot_no_room)snprintf(r,sizeof(r),\"no room to carry the %s (pack and slots full)\",g->item[0]&&strcmp(g->item,\"all\")?g->item:\"items\");\n"),
    ("                logline(\"[stobe] TASK_GOAL accepted id=%s actor=%s kind=%s item=%s qty=%d target=%s dest=%s\",\n",
     "                g_stg_loot_no_room=0;\n"
     "                logline(\"[stobe] TASK_GOAL accepted id=%s actor=%s kind=%s item=%s qty=%d target=%s dest=%s\",\n"),
    ("    stg_finish(g,STG_STATE_COMPLETE,\"no more matching items on nearby downed targets\");\n",
     "    stg_finish(g,STG_STATE_COMPLETE,g_stg_loot_no_room?\"took what fit; left the rest (no room to carry more)\":\"no more matching items on nearby downed targets\");\n"),
]
for old, new in edits:
    assert text.count(old) == 1, 'anchor not found exactly once: %r' % old[:70]
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
