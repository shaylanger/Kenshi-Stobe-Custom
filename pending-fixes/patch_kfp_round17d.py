#!/usr/bin/env python3
"""KenshiFP round 17d (bug 48): switch machines when the planner moves to the next step.

Shay saw Malzin keep mining after there was enough raw stone, until the mine and the
processor were both full; no building materials were made. The planner added the
"operate processor" order every 2 s, but her earlier "operate mine" order stayed in
front. Now, when the building the goal wants operated changes, her orders are
cleared first, then the new one is added.

Usage: patch_kfp_round17d.py <KenshiFP root>
"""
import sys, pathlib

f = pathlib.Path(sys.argv[1]) / "client" / "stobe_work_planner.inc"
s = f.read_text()

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f"anchor count {n}: {old[:70]!r}"
    s = s.replace(old, new)

rep("    float haul_last_dist;   /* runtime only: hauling walk progress */\n",
    "    float haul_last_dist;   /* runtime only: hauling walk progress */\n"
    "    void *rt_task_building; /* runtime only: building the last operate order was for */\n")

rep("static WgpSubstate *wgp_substate(WgpGoal *g, const char *item)\n",
    """/* Operate order for a goal; clears the old order first when the target building changes. */
static int wgp_issue_goal_task(void *actor, WgpGoal *g, WgpProducer *p)
{
    if (!actor || !p || !p->building) return 0;
    if (g->rt_task_building != p->building) {
        if (g->rt_task_building && stobe_resolve_fight_exports()) {
            void *orders = g_stobe_getorders(actor);
            if (orders && readable(orders, 8)) g_stobe_clear_orders(orders);
            logline("[stobe] WORK_GOAL switch id=%s -> %s", g->id,
                    p->building_name[0] ? p->building_name : "building");
        }
        g->rt_task_building = p->building;
    }
    return wgp_issue_building_task(actor, p, -1);
}

static WgpSubstate *wgp_substate(WgpGoal *g, const char *item)
""")

rep("""    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if ((LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&p,-1);""",
    """    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if (g->rt_task_building != p.building || (LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_goal_task(actor,g,&p);""")

rep("""    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if ((LONG)(now-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&root,-1);""",
    """    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if (g->rt_task_building != root.building || (LONG)(now-g->last_order_ms)>2000) {
        wgp_issue_goal_task(actor,g,&root);""")

f.write_text(s)
print("patched", f)
