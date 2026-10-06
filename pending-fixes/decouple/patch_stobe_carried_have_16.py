#!/usr/bin/env python3
"""Stobe StobeGoals.cpp, row 16-fb (dec-5090-2): "make 2 Junkbows" queued 2 Hinges although Avarek carried 1.

Evidence (stobe_goals.log / stobe.log, goal wg-d4238a21...): 10:06:10 feed loaded her 6 carried Steel Bars,
10:06:11 the Crossbow bench job was handed to the game, 10:06:12 `Junkbow missing input Hinge (have=0 ...)`,
stobe.log 10:06:18 `INV_TRANSFER: unmatched loss from=Avarek item=Hinge` (with the bars), no pickup event,
yet 10:06:43 `haul loaded 1 Hinge` from her pack again. The game's job AI briefly holds the carried Hinge
outside every inventory the planner counts (pack + backpack + player buildings), so the first look at the
Hinge (wgp_ensure_item, only reached after feed_carried) saw have=0, had no item-95 substate yet, and queued
the full 2. The m48 fix (substate on feed) only covers a dep loaded by feed itself.

Fix: (1) wgp_seed_carried_deps: before feed_carried (root and nested), any crafted missing input already in
stock gets its item-95 substate seeded with the count (log `<dep> stock N seen before feeding (16-fb ...)`),
so a vanish is counted as used (consumed) and only the real shortfall is queued. (2) wgp_substate_observe
(the per-tick substate update, now a helper): a rise that shows up in her own pack while consumed>0 is that
stock coming back (log `<dep> back N`), not a finished craft, so it cancels the consumed count instead of the
queued count (else a real queued Hinge would be queued again later).
Usage: patch_stobe_carried_have_16.py <STOBE-src root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / "src" / "StobeGoals.cpp"
s = p.read_text(encoding="utf-8", errors="surrogateescape")
if "wgp_seed_carried_deps" in s:
    print("already applied"); sys.exit(0)


def rep(old, new, count=1):
    global s
    assert s.count(old) == count, "anchor count %d != %d: %r" % (s.count(old), count, old[:80])
    s = s.replace(old, new)


# 1. substate: own-pack count of the last tick
rep("""    int consumed;   /* Item 95, runtime only: units that disappeared (used by the goal's own crafts) */
} WgpSubstate;""",
"""    int consumed;   /* Item 95, runtime only: units that disappeared (used by the goal's own crafts) */
    int last_inv;   /* 16-fb, runtime only: of last_have, the units in her own pack (-1 = unknown) */
} WgpSubstate;""")

# 2. init + observe helper
rep("""        g->subs[i].last_have=-1;
        g->subs[i].consumed=0;
        return &g->subs[i];
    }
    return NULL;
}
""",
"""        g->subs[i].last_have=-1;
        g->subs[i].consumed=0;
        g->subs[i].last_inv=-1;
        return &g->subs[i];
    }
    return NULL;
}

/* Per-tick item-95 update of one substate. have = world count (pack + player buildings), inv = her pack.
 * 16-fb: the game's job AI can hold her carried stock outside every counted inventory for a while (the
 * drop is counted as used); when it shows up in her pack again it is that stock, not a finished craft
 * (crafts finish in the bench), so it cancels the consumed count instead of the queued count. */
static void wgp_substate_observe(WgpGoal *g, WgpSubstate *ss, int have, int inv)
{
    if (ss->last_have>=0 && have<ss->last_have) { /* Item 95: used by the goal's own crafts */
        ss->consumed+=ss->last_have-have;
        logline("[stobe] WORK_STEP id=%s %s used %d (consumed=%d queued=%d)",g->id,ss->item,ss->last_have-have,ss->consumed,ss->queued);
    }
    if (ss->last_have>=0 && have>ss->last_have && ss->consumed>0 && ss->last_inv>=0 && inv>ss->last_inv) {
        int back=have-ss->last_have;
        if (back>inv-ss->last_inv) back=inv-ss->last_inv;
        if (back>ss->consumed) back=ss->consumed;
        ss->consumed-=back; ss->last_have+=back; g_wgp_dirty=1;
        logline("[stobe] WORK_STEP id=%s %s back %d in her pack (16-fb: consumed=%d queued=%d)",g->id,ss->item,back,ss->consumed,ss->queued);
    }
    ss->last_inv=inv;
    if (ss->queued<=0) { ss->last_have=have; return; } /* only intermediates still being crafted below */
    if (ss->last_have>=0 && have>ss->last_have && ss->queued>0) {
        ss->queued-=have-ss->last_have;
        if (ss->queued<0) ss->queued=0;
        g_wgp_dirty=1;
    }
    ss->last_have=have;
}
""")

# 3. the tick loop uses the helper
rep("""        int have=wgp_item_count_world(gw,actor,ss->item);
        if (ss->last_have>=0 && have<ss->last_have) { /* Item 95: used by the goal's own crafts */
            ss->consumed+=ss->last_have-have;
            logline("[stobe] WORK_STEP id=%s %s used %d (consumed=%d queued=%d)",g->id,ss->item,ss->last_have-have,ss->consumed,ss->queued);
        }
        if (ss->queued<=0) { ss->last_have=have; continue; } /* only intermediates still being crafted below */
        if (ss->last_have>=0 && have>ss->last_have && ss->queued>0) {
            ss->queued-=have-ss->last_have;
            if (ss->queued<0) ss->queued=0;
            g_wgp_dirty=1;
        }
        ss->last_have=have;
    }""",
"""        int have=wgp_item_count_world(gw,actor,ss->item);
        wgp_substate_observe(g,ss,have,g_wgp_count_inv);
    }""")

# 4. seed helper, before wgp_ensure_item
rep("""/* return 1 ready/available, 0 working/waiting, -1 impossible */
static int wgp_ensure_item(""",
"""/* 16-fb: seed item 95 for crafted inputs already in stock before feed_carried / the game's job AI
 * move them (the planner may first look at them only after they left every counted inventory). */
static void wgp_seed_carried_deps(void *gw, void *actor, WgpGoal *g, void **missing, int miss)
{
    for (int i=0;i<miss;i++) {
        char dep[128]={0};
        if (!wgp_name(missing[i],dep,sizeof(dep)) || !dep[0]) continue;
        int known=0;
        for (int k=0;k<WGP_MAX_SUBSTATE;k++)
            if (g->subs[k].item[0] && !_stricmp(g->subs[k].item,dep) && g->subs[k].last_have>=0) { known=1; break; }
        if (known) continue;
        int have=wgp_item_count_world(gw,actor,dep);
        int inv=g_wgp_count_inv;
        if (have<=0) continue;
        WgpProducer pp;
        if (!wgp_find_producer(gw,actor,dep,&pp) || !pp.is_crafting) continue;
        WgpSubstate *ss=wgp_substate(g,dep);
        if (!ss || ss->last_have>=0) continue;
        ss->last_have=have; ss->last_inv=inv;
        logline("[stobe] WORK_STEP id=%s %s stock %d seen before feeding (16-fb, in her pack %d)",g->id,dep,have,inv);
    }
}

/* return 1 ready/available, 0 working/waiting, -1 impossible */
static int wgp_ensure_item(""")

# 5. call it before both feed_carried calls
rep("""    if (miss>0 && wgp_feed_carried(gw,actor,g,&p)) return 0; /* m26 */""",
"""    if (miss>0) wgp_seed_carried_deps(gw,actor,g,missing,miss); /* 16-fb */
    if (miss>0 && wgp_feed_carried(gw,actor,g,&p)) return 0; /* m26 */""")
rep("""    if (miss>0 && wgp_feed_carried(gw,actor,g,&root)) return; /* m26 */""",
"""    if (miss>0) wgp_seed_carried_deps(gw,actor,g,missing,miss); /* 16-fb */
    if (miss>0 && wgp_feed_carried(gw,actor,g,&root)) return; /* m26 */""")

# order checks: helpers defined before use
for a, b in (("static void wgp_substate_observe(", "wgp_substate_observe(g,ss,have,g_wgp_count_inv)"),
             ("static void wgp_seed_carried_deps(", "wgp_seed_carried_deps(gw,actor,g,missing,miss); /* 16-fb */"),
             ("static int g_wgp_count_scanned, g_wgp_count_inv;", "static void wgp_substate_observe("),
             ("static int wgp_find_producer(", "static void wgp_seed_carried_deps(")):
    assert s.index(a) < s.index(b), "order: %s before %s" % (a, b)
p.write_text(s, encoding="utf-8", errors="surrogateescape")
print("patched", p)
