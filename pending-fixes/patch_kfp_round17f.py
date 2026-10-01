#!/usr/bin/env python3
"""KenshiFP round 17f (bug 59): say *which* goal ended.

When a work/task goal ends near the player, KenshiFP writes lifelike_initiative.flag
(read by Stobe.dll round 17d). It now also appends "<goal id>\\t<actor>\\t<work|task>"
to stobe_goal_report.request, so the server can make that NPC report the result
(server round 17i).

Usage: patch_kfp_round17f.py <KenshiFP root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / "client" / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("stobe_work_planner.inc", [
    ("static void wgp_maybe_trigger_report(void *gw, WgpGoal *g)\n{",
     r'''/* One line per ended goal for the server's report turn (round 17f). */
static void stobe_goal_report_append(const char *id, const char *actor, const char *type)
{
    char path[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_goal_report.request")) return;
    FILE *f=fopen(path,"ab");
    if (!f) return;
    fprintf(f,"%s\t%s\t%s\n",id?id:"",actor?actor:"",type?type:"");
    fclose(f);
}

static void wgp_maybe_trigger_report(void *gw, WgpGoal *g)
{'''),
    ("""    if (h!=INVALID_HANDLE_VALUE) {
        CloseHandle(h);
        g->report_triggered=1;
        g_wgp_dirty=1;
    }""",
     """    if (h!=INVALID_HANDLE_VALUE) {
        CloseHandle(h);
        stobe_goal_report_append(g->id,g->actor,"work");
        g->report_triggered=1;
        g_wgp_dirty=1;
    }"""),
])
patch("stobe_task_goals.inc", [
    ("    if(h!=INVALID_HANDLE_VALUE){CloseHandle(h);g->report_triggered=1;g_stg_dirty=1;}",
     "    if(h!=INVALID_HANDLE_VALUE){CloseHandle(h);stobe_goal_report_append(g->id,g->actor,\"task\");g->report_triggered=1;g_stg_dirty=1;}"),
])
