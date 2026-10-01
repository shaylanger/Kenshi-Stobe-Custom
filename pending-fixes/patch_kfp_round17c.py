#!/usr/bin/env python3
"""KenshiFP round 17c (bug 47): work goals haul machine inputs themselves.

Before ordering "operate" on a production building whose input is empty
(Manual Stone Processor without raw stone, Wheat Farm without water, Grain Silo
without wheatstraw, Bread Oven without flour), the actor:
  1. walks to the nearest player building / mine holding that input (mine output,
     well, farm output, storage) and picks up a batch (<= 10),
  2. walks to the machine and loads it into the machine's inventory,
  3. then operates as before.
Walking and each transfer count as progress for the stall timer. Steps show as
"Fetching X from Y for Z (d)", "Carrying X to Z", "Loaded N X into Z".
Log: "[stobe] WORK_GOAL haul ...".

Usage: patch_kfp_round17c.py <KenshiFP root>
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
    ("    int rt_return_started;  /* runtime only: walk-back already requested */\n} WgpGoal;",
     "    int rt_return_started;  /* runtime only: walk-back already requested */\n"
     "    float haul_last_dist;   /* runtime only: hauling walk progress */\n"
     "    int haul_still;\n"
     "    DWORD haul_next_ms;\n} WgpGoal;"),
    ("/* return 1 ready/available, 0 working/waiting, -1 impossible */\n",
     "static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */\n\n"
     "/* return 1 ready/available, 0 working/waiting, -1 impossible */\n"),
    ("""    if ((LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&p,-1);
        g->last_order_ms=GetTickCount();
    }""",
     """    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if ((LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&p,-1);
        g->last_order_ms=GetTickCount();
    }"""),
    ("""    if ((LONG)(now-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&root,-1);
        g->last_order_ms=now;
    }""",
     """    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if ((LONG)(now-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&root,-1);
        g->last_order_ms=now;
    }"""),
])

patch("stobe_task_goals.inc", [
    ("static int stg_store_from_actor(void *gw,void *actor,const char *query,int qty)\n{",
     r'''/* ---- work-goal input hauling (round 17c, bug 47) ---- */
#define WGP_HAUL_REACH 45.0f
#define WGP_HAUL_NEAR 160.0f
#define WGP_HAUL_BATCH 10

/* 1 = arrived (or as close as pathing gets), 0 = still walking */
static int wgp_haul_walk(void *actor,WgpGoal *g,Vec3 target,float dist,DWORD now)
{
    if(dist<=WGP_HAUL_REACH){g->haul_still=0;g->haul_last_dist=0;return 1;}
    if(g->haul_last_dist<=0||dist<g->haul_last_dist-3.0f){g->haul_last_dist=dist;g->haul_still=0;g->last_progress_ms=now;}
    else g->haul_still++;
    if(dist<=WGP_HAUL_NEAR&&g->haul_still>=4){g->haul_still=0;g->haul_last_dist=0;return 1;}
    if((LONG)(now-g->haul_next_ms)>=0){try_move_to_pos(actor,&target);g->haul_next_ms=now+3000;}
    return 0;
}

/* 1 = hauling in progress this tick (caller must not issue operate), 0 = nothing to haul */
static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)
{
    if(!p||!p->building||!p->production||!stg_exports())return 0;
    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(p->production,missing,WGP_MAX_MISSING);
    if(miss<=0)return 0;
    void *ainv=g_stobe_getinv(actor);
    Vec3 apos={0,0,0};if(!ainv||!char_position(actor,&apos))return 0;
    Vec3 mpos=*(Vec3 *)((uintptr_t)p->building+0x48);
    void *minv=wgp_building_inventory(p->building);
    const char *mname=p->building_name[0]?p->building_name:"the machine";
    DWORD now=GetTickCount();
    for(int i=0;i<miss;i++){
        char dep[128]={0};
        if(!wgp_name(missing[i],dep,sizeof(dep))||!dep[0])continue;
        int carried=wgp_item_count_inventory(ainv,dep);
        if(carried>0){
            float d=wgp_distance(apos,mpos);
            if(!wgp_haul_walk(actor,g,mpos,d,now)){
                snprintf(g->current_step,sizeof(g->current_step),"Carrying %s to %s (%.0f)",dep,mname,d);
                return 1;
            }
            int m=minv?stg_transfer_inventory(ainv,minv,dep,carried):0;
            if(m>0){
                g->last_progress_ms=now;g->last_order_ms=0;g->haul_last_dist=0;g_wgp_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Loaded %d %s into %s",m,dep,mname);
                logline("[stobe] WORK_GOAL haul loaded id=%s %d %s into %s",g->id,m,dep,mname);
                return 1;
            }
            logline("[stobe] WORK_GOAL haul: %s would not accept %s",mname,dep);
            return 0;
        }
        void *b[WGP_MAX_BUILDINGS]={0};
        int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
        void *src=NULL;float best=1e30f;int have=0;
        for(int j=0;j<n;j++){
            void *x=b[j];
            if(!x||x==p->building||!readable(x,0x80))continue;
            int sp=wgp_building_special(x);
            if(!g_wgp_isplayer_building(x)&&sp!=WGP_BF_MINE&&sp!=WGP_BF_MINE_NATURAL)continue;
            int c=wgp_item_count_inventory(wgp_building_inventory(x),dep);
            if(c<=0)continue;
            float d=wgp_distance(apos,*(Vec3 *)((uintptr_t)x+0x48));
            if(d<best){best=d;src=x;have=c;}
        }
        if(!src)continue; /* not stocked anywhere yet: producing it is handled by the planner */
        char sname[160]={0};
        wgp_name(*(void **)((uintptr_t)src+0x40),sname,sizeof(sname));
        if(!wgp_haul_walk(actor,g,*(Vec3 *)((uintptr_t)src+0x48),best,now)){
            snprintf(g->current_step,sizeof(g->current_step),"Fetching %s from %s for %s (%.0f)",dep,sname,mname,best);
            return 1;
        }
        int take=have<WGP_HAUL_BATCH?have:WGP_HAUL_BATCH;
        int m=stg_transfer_to_character(wgp_building_inventory(src),actor,dep,take);
        if(m>0){
            g->last_progress_ms=now;g->haul_last_dist=0;g_wgp_dirty=1;
            snprintf(g->current_step,sizeof(g->current_step),"Picked up %d %s from %s",m,dep,sname);
            logline("[stobe] WORK_GOAL haul picked id=%s %d %s from %s",g->id,m,dep,sname);
            return 1;
        }
        logline("[stobe] WORK_GOAL haul: could not take %s from %s",dep,sname);
        return 0;
    }
    return 0;
}

static int stg_store_from_actor(void *gw,void *actor,const char *query,int qty)
{'''),
])
