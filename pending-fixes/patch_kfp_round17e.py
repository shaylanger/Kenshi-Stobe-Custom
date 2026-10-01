#!/usr/bin/env python3
"""KenshiFP round 17e: power-aware planner, farm waiting, walk-back fix, walking fetch/store.

Bug 58 (run 4): Well III lost power; the bread goal ordered her to operate it, the
game ignored the order and she stood idle with a dead order. Now, when the machine
the plan needs reports isOutOfPower (UseableStuff vtable 0x4B8 via
getUseableStuff 0x300) for WGP_POWER_WAIT_MS (30 s real), the goal BLOCKS with
"cannot make X because <building> has no power (...)". While waiting the step reads
"Waiting for power at <building>". RESUME (round 17) restarts it.
Farms: once a farm has its inputs, the step reads "Waiting for <farm> to grow"
and counts as progress (crops take game days).

Bug 50: the walk-back after a goal ends lost to her old operate/collect orders.
The first walk-back tick now clears her orders.

Bug 51: FETCH/STORE moved items instantly from/to any chest in range. Now she walks
to the nearest player storage that has the item (fetch) or the nearest player
storage (store), then transfers there. Store falls back to other storage nearby
if the nearest one takes nothing.

Usage: patch_kfp_round17e.py <KenshiFP root>
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
    ("#define WGP_DEP_STALL_MS 900000\n",
     "#define WGP_DEP_STALL_MS 900000\n#define WGP_POWER_WAIT_MS 30000\n"),
    ("    void *rt_task_building; /* runtime only: building the last operate order was for */\n",
     "    void *rt_task_building; /* runtime only: building the last operate order was for */\n"
     "    void *power_wait_building; /* runtime only: building we are waiting on for power */\n"
     "    DWORD power_wait_ms;\n"),
    ("static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */\n",
     r'''static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */

/* 1 when the building's UseableStuff reports it is out of power (same check as Stobe.dll's base snapshot). */
static int wgp_building_unpowered(void *building)
{
    typedef void *(*us_t)(void *);
    typedef float (*oop_t)(void *);
    us_t us_fn=(us_t)wgp_vcall_ptr(building,0x300);   /* Building::getUseableStuff */
    void *us=us_fn?us_fn(building):NULL;
    if (!us || !readable(us,8)) return 0;
    oop_t oop=(oop_t)wgp_vcall_ptr(us,0x4B8);          /* UseableStuff::isOutOfPower */
    return oop ? (oop(us)>0.0f) : 0;
}

static int wgp_icontains(const char *hay, const char *needle)
{
    if (!hay || !needle || !*needle) return 0;
    size_t n=strlen(needle);
    for (const char *h=hay; *h; h++) if (!_strnicmp(h,needle,n)) return 1;
    return 0;
}

/* 0 = powered, 1 = waiting for power (step set), -1 = give up (reason set) */
static int wgp_power_gate(WgpGoal *g, WgpProducer *p, char *reason, size_t reason_sz)
{
    if (!p || !p->building) return 0;
    DWORD now=GetTickCount();
    if (!wgp_building_unpowered(p->building)) {
        if (g->power_wait_building==p->building) { g->power_wait_building=NULL; g->power_wait_ms=0; }
        return 0;
    }
    const char *bn=p->building_name[0]?p->building_name:"the production building";
    if (g->power_wait_building!=p->building || !g->power_wait_ms) {
        g->power_wait_building=p->building; g->power_wait_ms=now;
        logline("[stobe] WORK_GOAL power wait id=%s building=%s",g->id,bn);
    }
    if ((LONG)(now-g->power_wait_ms)>WGP_POWER_WAIT_MS) {
        snprintf(reason,reason_sz,"%s has no power (check generators, batteries and wiring)",bn);
        return -1;
    }
    snprintf(g->current_step,sizeof(g->current_step),"Waiting for power at %s",bn);
    g->last_progress_ms=now; /* the power wait has its own timer */
    return 1;
}
'''),
    ("""    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if (g->rt_task_building != p.building || (LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_goal_task(actor,g,&p);
        g->last_order_ms=GetTickCount();
    }""",
     """    { int pw=wgp_power_gate(g,&p,reason,reason_sz); if (pw<0) return -1; if (pw>0) return 0; }
    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if (g->rt_task_building != p.building || (LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_goal_task(actor,g,&p);
        g->last_order_ms=GetTickCount();
    }
    if (wgp_icontains(p.building_name,"farm")) {
        /* Inputs are in; the crop needs game time. Not a stall. */
        snprintf(g->current_step,sizeof(g->current_step),"Waiting for %s to grow %s",p.building_name,item);
        g->last_progress_ms=GetTickCount();
        return 0;
    }"""),
    ("""    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if (g->rt_task_building != root.building || (LONG)(now-g->last_order_ms)>2000) {""",
     """    {
        char pr[200]={0};
        int pw=wgp_power_gate(g,&root,pr,sizeof(pr));
        if (pw<0) { char full[256]; snprintf(full,sizeof(full),"cannot make %s because %s",g->item,pr); wgp_goal_block(g,full); return; }
        if (pw>0) return;
    }
    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if (g->rt_task_building != root.building || (LONG)(now-g->last_order_ms)>2000) {"""),
])

patch("stobe_task_goals.inc", [
    # bug 50: clear orders on the first walk-back tick
    ("typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; } SgrReturn;",
     "typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; int cleared; } SgrReturn;"),
    ("        if(!try_move_to_pos(actor,&p)){logline(\"[stobe] GOAL_RETURN move failed actor=%s\",r->actor);memset(r,0,sizeof(*r));}",
     "        if(!r->cleared){\n"
     "            /* Her goal's operate/collect orders would win over the walk-back (bug 50). */\n"
     "            if(stobe_resolve_fight_exports()){void *o=g_stobe_getorders(actor);if(o&&readable(o,8))g_stobe_clear_orders(o);}\n"
     "            r->cleared=1;\n"
     "        }\n"
     "        if(!try_move_to_pos(actor,&p)){logline(\"[stobe] GOAL_RETURN move failed actor=%s\",r->actor);memset(r,0,sizeof(*r));}"),
    # bug 51: runtime walk fields
    ("    int rt_return_started;  /* runtime only: walk-back already requested */\n} StgGoal;",
     "    int rt_return_started;  /* runtime only: walk-back already requested */\n"
     "    float walk_last_dist;   /* runtime only: walking to a storage building */\n"
     "    int walk_still;\n"
     "    DWORD walk_next_ms;\n} StgGoal;"),
    ("static void stg_tick_store(void *gw,void *actor,StgGoal *g)\n{",
     r'''/* ---- walking fetch/store (round 17e, bug 51) ---- */
static void *stg_nearest_storage(void *gw,void *actor,const char *query,float *dist_out,char *name,size_t namesz)
{
    Vec3 a={0,0,0};if(!char_position(actor,&a))return NULL;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    void *best=NULL;float bd=1e30f;
    for(int i=0;i<n;i++){
        void *x=b[i];if(!x||!readable(x,0x80))continue;
        int sp=wgp_building_special(x);
        if(sp!=STG_BF_RESOURCE_STORAGE&&sp!=STG_BF_GENERAL_STORAGE)continue;
        if(!g_wgp_isplayer_building(x))continue;
        void *inv=wgp_building_inventory(x);if(!inv)continue;
        if(query&&stg_count_matching(inv,query)<=0)continue;
        float d=wgp_distance(a,*(Vec3 *)((uintptr_t)x+0x48));
        if(d<bd){bd=d;best=x;}
    }
    if(best){
        if(dist_out)*dist_out=bd;
        if(name&&namesz){name[0]='\0';wgp_name(*(void **)((uintptr_t)best+0x40),name,namesz);}
    }
    return best;
}

/* 1 = at the storage (or as close as pathing gets), 0 = walking */
static int stg_walk_to(void *actor,StgGoal *g,void *building,float d)
{
    DWORD now=GetTickCount();
    if(d<=WGP_HAUL_REACH){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if(g->walk_last_dist<=0||d<g->walk_last_dist-3.0f){g->walk_last_dist=d;g->walk_still=0;g->last_progress_ms=now;}
    else g->walk_still++;
    if(d<=WGP_HAUL_NEAR&&g->walk_still>=4){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if((LONG)(now-g->walk_next_ms)>=0){Vec3 t=*(Vec3 *)((uintptr_t)building+0x48);try_move_to_pos(actor,&t);g->walk_next_ms=now+3000;}
    return 0;
}

static void stg_tick_store_any(void *gw,void *actor,StgGoal *g);

static void stg_tick_store(void *gw,void *actor,StgGoal *g)
{
    if(stg_actor_item_count(actor,g->item)>0){
        float d=0;char sn[160]={0};
        void *dst=stg_nearest_storage(gw,actor,NULL,&d,sn,sizeof(sn));
        if(dst&&!stg_walk_to(actor,g,dst,d)){
            snprintf(g->current_step,sizeof(g->current_step),"Walking to %s to store %s (%.0f)",sn[0]?sn:"storage",g->item,d);
            return;
        }
        if(dst){
            int want=g->quantity>0?g->quantity-g->completed:stg_actor_item_count(actor,g->item);
            int m=want>0?stg_transfer_inventory(g_stobe_getinv(actor),wgp_building_inventory(dst),g->item,want):0;
            if(m>0){g->completed+=m;g->last_progress_ms=GetTickCount();g_stg_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Stored %d %s in %s",g->completed,g->item,sn[0]?sn:"storage");
                if((g->quantity>0&&g->completed>=g->quantity)||stg_actor_item_count(actor,g->item)<=0)stg_finish(g,STG_STATE_COMPLETE,"");
                return;
            }
        }
    }
    stg_tick_store_any(gw,actor,g); /* nearest took nothing: try the rest (old behaviour) */
}

static void stg_tick_store_any(void *gw,void *actor,StgGoal *g)
{'''),
    ("static void stg_tick_fetch(void *gw,void *actor,StgGoal *g)\n{\n    int need=g->quantity-g->completed;if(need<=0){stg_finish(g,STG_STATE_COMPLETE,\"\");return;}\n    int moved=stg_fetch_to_actor(gw,actor,g->item,need);",
     "static void stg_tick_fetch(void *gw,void *actor,StgGoal *g)\n{\n    int need=g->quantity-g->completed;if(need<=0){stg_finish(g,STG_STATE_COMPLETE,\"\");return;}\n"
     "    float d=0;char sn[160]={0};\n"
     "    void *src=stg_nearest_storage(gw,actor,g->item,&d,sn,sizeof(sn));\n"
     "    if(src&&!stg_walk_to(actor,g,src,d)){\n"
     "        snprintf(g->current_step,sizeof(g->current_step),\"Walking to %s for %s (%.0f)\",sn[0]?sn:\"storage\",g->item,d);\n"
     "        return;\n"
     "    }\n"
     "    int moved=src?stg_transfer_to_character(wgp_building_inventory(src),actor,g->item,need):0;\n"
     "    if(moved>0){g->completed+=moved;g->last_progress_ms=GetTickCount();g_stg_dirty=1;\n"
     "        snprintf(g->current_step,sizeof(g->current_step),\"Fetched %d/%d %s from %s\",g->completed,g->quantity,g->item,sn[0]?sn:\"storage\");\n"
     "        if(g->completed>=g->quantity)stg_finish(g,STG_STATE_COMPLETE,\"\");\n"
     "        return; /* next tick: next storage if still short */\n"
     "    }\n"
     "    moved=0;"),
])
