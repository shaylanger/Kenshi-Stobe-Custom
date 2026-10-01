#!/usr/bin/env python3
"""KenshiFP round 17 (bug 44): work goals no longer block while a dependency is being gathered.

- Stall timer now resets when the count of any dependency item changes (mined raw
  stone, harvested wheat, ...), not only the final item.
- Dependency steps get a longer stall window (WGP_DEP_STALL_MS, 15 min real time):
  farms and mines can take a long time before the first unit shows up.
- RESUME also restarts a BLOCKED goal (retry after the player fixes the cause).

Usage: patch_kfp_round17.py <KenshiFP root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
f = root / "client" / "stobe_work_planner.inc"
s = f.read_text()

def rep(old, new, count=1):
    global s
    n = s.count(old)
    assert n == count, f"anchor count {n} != {count}: {old[:60]!r}"
    s = s.replace(old, new)

rep("#define WGP_STALL_MS 180000\n",
    "#define WGP_STALL_MS 180000\n#define WGP_DEP_STALL_MS 900000\n")

rep("    int report_triggered;\n    WgpSubstate subs[WGP_MAX_SUBSTATE];\n} WgpGoal;",
    "    int report_triggered;\n    WgpSubstate subs[WGP_MAX_SUBSTATE];\n"
    "    long long dep_sig;      /* runtime only: sum of dependency counts this tick */\n"
    "    long long dep_sig_last; /* runtime only: previous tick's sum */\n} WgpGoal;")

rep("    int have=wgp_item_count_world(gw,actor,item);\n    if (have>=need) return 1;\n",
    "    int have=wgp_item_count_world(gw,actor,item);\n    g->dep_sig+=(long long)have*(depth+1);\n    if (have>=need) return 1;\n")

rep("    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));\n",
    "    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));\n    g->dep_sig=0;\n")

rep("""        if (r==0) {
            if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_STALL_MS) {""",
    """        if (r==0) {
            if (g->dep_sig!=g->dep_sig_last) {
                /* Gathering inputs counts as progress (mined stone, harvested wheat). */
                g->dep_sig_last=g->dep_sig; g->last_progress_ms=now;
            }
            if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_DEP_STALL_MS) {""")

rep("    else if(!_stricmp(cmd,\"RESUME\")&&g->state==4)g->state=0;\n",
    "    else if(!_stricmp(cmd,\"RESUME\")&&(g->state==4||g->state==2)){\n"
    "        if(g->state==2){g->reason[0]='\\0';g->report_triggered=0;g->last_progress_ms=GetTickCount();}\n"
    "        g->state=0;\n    }\n")

f.write_text(s)
print("patched", f)
