#!/usr/bin/env python3
"""Bug 94: finished task goals were reported again after every game launch
("Mead's in the chest. Done." at a random knockout): report_triggered is not
saved in stobe_task_goals.tsv. Fix: goals loaded as COMPLETE/BLOCKED/CANCELLED
count as reported.

Bug 104 (KenshiFP part): a loot goal that took 0 items ended COMPLETE, and the
report told her "it's done". Fix: 0 looted -> BLOCKED with a reason ("couldn't
find X's body nearby" when no body matched the target, else "found nothing to
take"), so she walks back and says why.
Usage: patch_r20_bug94_104_goals.py <KenshiFP tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("client/stobe_task_goals.inc", [
    # bug 94
    ("        g.quantity=atoi(fields[11]);g.completed=atoi(fields[12]);g.state=atoi(fields[13]);\n",
     "        g.quantity=atoi(fields[11]);g.completed=atoi(fields[12]);g.state=atoi(fields[13]);\n"
     "        if(g.state==STG_STATE_COMPLETE||g.state==STG_STATE_BLOCKED||g.state==STG_STATE_CANCELLED){g.report_triggered=1;g.rt_return_started=1;} /* bug 94: ended before this launch: already reported */\n"),
    # bug 104: scan returns how many bodies matched the target
    ("static void stg_loot_scan_log(void *gw,void *actor,StgGoal *g)\n{",
     "static int stg_loot_scan_log(void *gw,void *actor,StgGoal *g)\n{"),
    ("            g->id,g->target,g->item,n,dead,downed,valid);\n}\n",
     "            g->id,g->target,g->item,n,dead,downed,valid);\n    return valid;\n}\n"),
    ("    if(g->completed<=0)stg_loot_scan_log(gw,actor,g);\n"
     "    stg_finish(g,STG_STATE_COMPLETE,\"no more matching items on nearby downed targets\");\n",
     "    if(g->completed<=0){ /* bug 104: nothing taken is not \"done\" */\n"
     "        int matched=stg_loot_scan_log(gw,actor,g);\n"
     "        char r[256];\n"
     "        if(g->target[0]&&matched==0)snprintf(r,sizeof(r),\"couldn't find %s's body nearby\",g->target);\n"
     "        else snprintf(r,sizeof(r),\"found no %s to take on the nearby bodies\",g->item[0]&&strcmp(g->item,\"all\")?g->item:\"items\");\n"
     "        stg_finish(g,STG_STATE_BLOCKED,r);\n"
     "        return;\n"
     "    }\n"
     "    stg_finish(g,STG_STATE_COMPLETE,\"no more matching items on nearby downed targets\");\n"),
])
