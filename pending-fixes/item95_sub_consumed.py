#!/usr/bin/env python3
"""Item 95 (STOBE 16 v4, run m16): "2 Junkbows" with 1 Hinge in stock queued 2 Hinges (subs Hinge=2), not the
missing 1. First tick: the Hinge's bench had no power, so the planner used the stock and returned before it
created the Hinge substate; the root craft then consumed the Hinge; next tick have=0 -> shortfall 2-0-0 = 2.
Fix: the substate exists from the first look at a crafted intermediate (before the no-power return), and every
tick the units of it that disappeared (consumed by the goal's own crafts) are counted in `consumed`; the
shortfall is need - have - queued - consumed. When root units complete, the same number comes off `consumed`
(need already shrank by them; crafting uses 1 per unit, as dneed=need assumes). Runtime only (not persisted).
Usage: item95_sub_consumed.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 95' in s: sys.exit('already applied')
def rep(old, new):
    global s
    if s.count(old) != 1: sys.exit('anchor missing: ' + old[:70])
    s = s.replace(old, new)

rep("""    int last_have;  /* runtime only: count seen last tick (-1 = unknown) */
} WgpSubstate;""",
"""    int last_have;  /* runtime only: count seen last tick (-1 = unknown) */
    int consumed;   /* Item 95, runtime only: units that disappeared (used by the goal's own crafts) */
} WgpSubstate;""")
rep("""        g->subs[i].last_have=-1;
        return &g->subs[i];""",
"""        g->subs[i].last_have=-1;
        g->subs[i].consumed=0;
        return &g->subs[i];""")

# ensure_item: substate before the early returns; consumed counts as covered
rep("""    int have=wgp_item_count_world(gw,actor,item);
    g->dep_sig+=(long long)have*(depth+1);
    if (have>=need) return 1;

    WgpProducer p;
    if (!wgp_find_producer(gw,actor,item,&p)) {""",
"""    int have=wgp_item_count_world(gw,actor,item);
    g->dep_sig+=(long long)have*(depth+1);
    if (have>=need) return 1;

    WgpProducer p;
    int found_p=wgp_find_producer(gw,actor,item,&p);
    /* Item 95: track a crafted intermediate from the first look (stock used now must not be re-queued later) */
    WgpSubstate *ss95=NULL;
    if (found_p && p.is_crafting) {
        ss95=wgp_substate(g,item);
        if (ss95 && ss95->last_have<0) ss95->last_have=have;
        if (ss95 && have+ss95->consumed>=need) return 1;
    }
    if (!found_p) {""")
rep("""        WgpSubstate *ss=wgp_substate(g,item);
        if (!ss) {
            snprintf(reason,reason_sz,"too many distinct dependency items while trying to make %s",item);
            return -1;
        }
        /* Queue only the shortfall that is not already waiting at the bench. */
        int shortfall=need-have-ss->queued;""",
"""        WgpSubstate *ss=ss95?ss95:wgp_substate(g,item);
        if (!ss) {
            snprintf(reason,reason_sz,"too many distinct dependency items while trying to make %s",item);
            return -1;
        }
        /* Queue only the shortfall that is not already waiting at the bench
         * (Item 95: nor already used by this goal's crafts). */
        int shortfall=need-have-ss->queued-ss->consumed;""")

# tick: count consumption for every substate; completed root units release their share
rep("""    int current=wgp_item_count_world(gw,actor,g->item);
    g->completed=current-g->baseline;
    if (g->completed<0) g->completed=0;""",
"""    int current=wgp_item_count_world(gw,actor,g->item);
    int completed_before95=g->completed;
    g->completed=current-g->baseline;
    if (g->completed<0) g->completed=0;
    if (g->completed>completed_before95) { /* Item 95: finished root units no longer need their inputs */
        int done=g->completed-completed_before95;
        for (int i=0;i<WGP_MAX_SUBSTATE;i++) {
            if (!g->subs[i].item[0]) continue;
            g->subs[i].consumed-=done; if (g->subs[i].consumed<0) g->subs[i].consumed=0;
        }
    }""")
rep("""        if (!ss->item[0] || ss->queued<=0) continue; /* only intermediates still being crafted */
        int have=wgp_item_count_world(gw,actor,ss->item);
        if (ss->last_have>=0 && have>ss->last_have && ss->queued>0) {""",
"""        if (!ss->item[0]) continue;
        int have=wgp_item_count_world(gw,actor,ss->item);
        if (ss->last_have>=0 && have<ss->last_have) { /* Item 95: used by the goal's own crafts */
            ss->consumed+=ss->last_have-have;
            logline("[stobe] WORK_STEP id=%s %s used %d (consumed=%d queued=%d)",g->id,ss->item,ss->last_have-have,ss->consumed,ss->queued);
        }
        if (ss->queued<=0) { ss->last_have=have; continue; } /* only intermediates still being crafted below */
        if (ss->last_have>=0 && have>ss->last_have && ss->queued>0) {""")
p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
