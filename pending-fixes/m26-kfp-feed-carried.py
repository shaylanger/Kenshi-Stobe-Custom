#!/usr/bin/env python3
"""m26 (16-fullbase batch J): load the inputs she already carries into a machine BEFORE
working on that machine's missing sub-dependencies.

Batch J: Junkbow goal, Hinge producer = Arrow Making Bench (powered). The depth-first
planner went into the Hinge chain first (queue 1 Hinge, fetch Iron Plates from storage)
while Avarek still carried the 6 Steel Bars + 1 Hinge meant for the Crossbow bench; her
pack was full, the Iron Plates take failed 5x and the whole goal blocked 7 s after it was
accepted ("her pack is full: can't carry Iron Plates"), so no Junkbow was ever crafted.

Usage: python3 m26-kfp-feed-carried.py <KenshiFP root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
tg = root / "client/stobe_task_goals.inc"
wp = root / "client/stobe_work_planner.inc"

def patch(path, old, new, tag):
    s = path.read_text()
    if tag in s:
        print(f"{path.name}: already patched ({tag})"); return
    assert s.count(old) == 1, f"{path.name}: anchor count {s.count(old)} for {tag}"
    path.write_text(s.replace(old, new))
    print(f"{path.name}: patched {tag}")

# 1) feed_inputs: carried-only mode (skip deps she doesn't carry)
patch(tg,
"static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)\n{\n",
"static int g_wgp_feed_carried_only; /* m26: wgp_feed_carried */\n"
"static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)\n{\n",
"g_wgp_feed_carried_only;")
patch(tg,
"""            logline("[stobe] WORK_GOAL haul: %s would not accept %s",mname,dep);
            return 0;
        }
""",
"""            logline("[stobe] WORK_GOAL haul: %s would not accept %s",mname,dep);
            return 0;
        }
        if(g_wgp_feed_carried_only)continue; /* m26 */
""",
"if(g_wgp_feed_carried_only)continue;")
patch(tg,
"static int stg_store_from_actor(void *gw,void *actor,const char *query,int qty)\n",
"""/* m26 (16-fullbase): load what she already carries for this machine first, so her pack
 * isn't full of its inputs while she fetches a sub-dependency's inputs (batch J: 6 Steel
 * Bars + 1 Hinge in her pack, Iron Plates for the 2nd Hinge didn't fit -> goal blocked). */
static int wgp_feed_carried(void *gw,void *actor,WgpGoal *g,WgpProducer *p)
{
    g_wgp_feed_carried_only=1;
    int r=wgp_feed_inputs(gw,actor,g,p);
    g_wgp_feed_carried_only=0;
    return r;
}

static int stg_store_from_actor(void *gw,void *actor,const char *query,int qty)
""",
"static int wgp_feed_carried(void *gw,void *actor,WgpGoal *g,WgpProducer *p)\n{")

# 2) planner: prototype + calls before the dependency loops
patch(wp,
"static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */\n",
"static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */\n"
"static int wgp_feed_carried(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* m26 */\n",
"static int wgp_feed_carried(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* m26 */")
patch(wp,
"""    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(p.production,missing,WGP_MAX_MISSING);
    for (int i=0;i<miss;i++) {
""",
"""    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(p.production,missing,WGP_MAX_MISSING);
    if (miss>0 && wgp_feed_carried(gw,actor,g,&p)) return 0; /* m26 */
    for (int i=0;i<miss;i++) {
""",
"if (miss>0 && wgp_feed_carried(gw,actor,g,&p)) return 0; /* m26 */")
patch(wp,
"""    int budget=0;
    for (int i=0;i<miss;i++) {
""",
"""    int budget=0;
    if (miss>0 && wgp_feed_carried(gw,actor,g,&root)) return; /* m26 */
    for (int i=0;i<miss;i++) {
""",
"if (miss>0 && wgp_feed_carried(gw,actor,g,&root)) return; /* m26 */")
