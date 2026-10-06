#!/usr/bin/env python3
"""Stobe StobeGoals.cpp, row 16-fb (m48): a carried crafted intermediate loaded into the machine by
wgp_feed_carried (m26) before wgp_ensure_item ever looked at it had no item-95 substate, so its use was
never counted (consumed=0) and the full amount was queued again (Arrow Making Bench queue=2 Hinges for a
2-Hinge need with 1 Hinge in stock). Pre-existing in KenshiFP since m26; it only passed when the Hinge
producer was unpowered (item 90 path ran ensure_item first). Fix: on such a load, create the substate
with last_have = the count before the load, so the next tick logs `<item> used N (consumed=N ...)`.
Usage: patch_stobe_feed_carried_95.py <STOBE-src root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "src" / "StobeGoals.cpp"
s = p.read_text(encoding="utf-8", errors="surrogateescape")
old = """            int m=minv?stg_transfer_inventory(ainv,minv,dep,carried):0;
            if(m>0){
                g_haul_fails=0; /* item 42 */"""
new = """            int before95=wgp_item_count_world(gw,actor,dep);
            int m=minv?stg_transfer_inventory(ainv,minv,dep,carried):0;
            if(m>0){
                { /* m48 16-fb: item 95 for a crafted intermediate loaded before the planner looked at it */
                    WgpProducer pp;
                    if(wgp_find_producer(gw,actor,dep,&pp)&&pp.is_crafting){
                        WgpSubstate *ss=wgp_substate(g,dep);
                        if(ss&&ss->last_have<0)ss->last_have=before95;
                    }
                }
                g_haul_fails=0; /* item 42 */"""
if new in s:
    print("already applied"); sys.exit(0)
assert s.count(old) == 1, "anchor not found"
s = s.replace(old, new)
# wgp_substate / WgpProducer / wgp_find_producer must be visible before wgp_feed_inputs
for sym in ("static WgpSubstate *wgp_substate(", "static int wgp_find_producer(", "static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)\n{"):
    assert sym in s, "missing " + sym
assert s.index("static WgpSubstate *wgp_substate(") < s.index("static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)\n{")
p.write_text(s, encoding="utf-8", errors="surrogateescape")
print("patched", p)
