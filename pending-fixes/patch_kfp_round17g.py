#!/usr/bin/env python3
"""KenshiFP round 17g: bugs 61, 62, 63 (+ walking loot, extends 51).

61: the power gate (17e) blocked the bread goal at once on "Grain Silo has no power"
    before she ever operated the silo (idle machines read as out of power). The gate
    now only applies once she has been ordered onto that machine and its inputs
    are loaded.
62: PATROL used Kenshi's PATROL order with no waypoints = region-wide wandering
    (targets thousands of units away, she didn't move). PATROL goals now walk a
    loop between the player's own buildings near where the patrol started (or 4
    points around it if there are none).
63: "wait here" / "come here" / "guard me" left the patrol running. Direct
    HOLD_POSITION / MOVE_TO_TARGET / BODYGUARD / PATROL orders now cancel her
    standing PATROL/GUARD goals and clear her old orders first.
51+: LOOT goals walk to each downed target before taking items.

Usage: patch_kfp_round17g.py <KenshiFP root>
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
    ("""    if (!p || !p->building) return 0;
    DWORD now=GetTickCount();
    if (!wgp_building_unpowered(p->building)) {""",
     """    if (!p || !p->building) return 0;
    /* Idle machines read as out of power: judge power only once she has been
     * ordered onto this machine and its inputs are loaded (bug 61). */
    if (g->rt_task_building!=p->building) return 0;
    {
        void *m[WGP_MAX_MISSING]={0};
        if (p->production && wgp_missing(p->production,m,WGP_MAX_MISSING)>0) return 0;
    }
    DWORD now=GetTickCount();
    if (!wgp_building_unpowered(p->building)) {"""),
])

patch("kenshifp_client.c", [
    ("static void stobe_general_action_request_tick(void *gw)\n{",
     "static void stobe_general_action_request_tick(void *gw)\n{"),  # sanity anchor (unchanged)
    ("    if (task >= 0) {\n        if ((task == STOBE_TASK_PATROL || task == STOBE_TASK_HOLD_POSITION) && !target)",
     """    if (task == STOBE_TASK_PATROL || task == STOBE_TASK_HOLD_POSITION ||
        task == STOBE_TASK_GET_NEAR_TO || task == STOBE_TASK_BODYGUARD) {
        /* A new standing order replaces patrols/guard duty and old orders (bug 63). */
        stg_cancel_standing_goals(actor_serial);
        if (stobe_resolve_fight_exports()) {
            void *o = g_stobe_getorders(actor);
            if (o && readable(o, 8)) g_stobe_clear_orders(o);
        }
    }
    if (task >= 0) {
        if ((task == STOBE_TASK_PATROL || task == STOBE_TASK_HOLD_POSITION) && !target)"""),
])

# forward declaration: the bridge (kenshifp_client.c) is above the task-goal include
patch("kenshifp_client.c", [
    ("static int stobe_issue_order(void *actor, int task_type, void *subject)\n{",
     "static void stg_cancel_standing_goals(uint32_t actor_serial); /* stobe_task_goals.inc */\n\n"
     "static int stobe_issue_order(void *actor, int task_type, void *subject)\n{"),
])

patch("stobe_task_goals.inc", [
    # runtime patrol fields
    ("    float walk_last_dist;   /* runtime only: walking to a storage building */\n",
     "    float walk_last_dist;   /* runtime only: walking to a storage building */\n"
     "    Vec3 patrol_center;     /* runtime only: custom patrol loop */\n"
     "    int patrol_init;\n"
     "    int patrol_idx;\n"),
    # forward declaration: loot (above) uses the walk helper defined further down
    ("static void stg_tick_loot(void *gw,void *actor,StgGoal *g)\n{",
     "static int stg_walk_to_pos(void *actor,StgGoal *g,Vec3 t,float d);\n\nstatic void stg_tick_loot(void *gw,void *actor,StgGoal *g)\n{"),
    # walk helper by position; building version delegates
    ("/* 1 = at the storage (or as close as pathing gets), 0 = walking */\nstatic int stg_walk_to(void *actor,StgGoal *g,void *building,float d)\n{\n    DWORD now=GetTickCount();",
     """/* 1 = at the position (or as close as pathing gets), 0 = walking */
static int stg_walk_to_pos(void *actor,StgGoal *g,Vec3 t,float d)
{
    DWORD now=GetTickCount();
    if(d<=WGP_HAUL_REACH){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if(g->walk_last_dist<=0||d<g->walk_last_dist-3.0f){g->walk_last_dist=d;g->walk_still=0;g->last_progress_ms=now;}
    else g->walk_still++;
    if(d<=WGP_HAUL_NEAR&&g->walk_still>=4){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if((LONG)(now-g->walk_next_ms)>=0){try_move_to_pos(actor,&t);g->walk_next_ms=now+3000;}
    return 0;
}

/* 1 = at the storage (or as close as pathing gets), 0 = walking */
static int stg_walk_to(void *actor,StgGoal *g,void *building,float d)
{
    DWORD now=GetTickCount();"""),
    # loot: walk to each downed target first
    ("""        if(!ser||stg_seen(g,ser)||!stg_valid_downed(actor,c,g->target))continue;
        void *src=g_stobe_getinv(c); if(!src){stg_mark_seen(g,ser);continue;}""",
     """        if(!ser||stg_seen(g,ser)||!stg_valid_downed(actor,c,g->target))continue;
        void *src=g_stobe_getinv(c); if(!src){stg_mark_seen(g,ser);continue;}
        {
            Vec3 a={0,0,0},cp={0,0,0};
            if(char_position(actor,&a)&&char_position(c,&cp)){
                float d=wgp_distance(a,cp);
                if(!stg_walk_to_pos(actor,g,cp,d)){
                    char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
                    snprintf(g->current_step,sizeof(g->current_step),"Walking to %s to loot %s (%.0f)",cn[0]?cn:"the body",g->item[0]?g->item:"items",d);
                    return;
                }
            }
        }"""),
    # custom patrol
    ("""static void stg_tick_patrol(void *gw,void *actor,StgGoal *g)
{
    if((LONG)(GetTickCount()-g->last_action_ms)>8000){
        stobe_issue_order(actor,STG_TASK_PATROL,NULL);
        g->last_action_ms=GetTickCount();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Patrolling until cancelled or paused");
}""",
     """/* Patrol loop between the player's own buildings near the start point (bug 62).
 * Kenshi's PATROL order without waypoints wanders the whole region. */
#define STG_PATROL_RADIUS 700.0f
static void stg_tick_patrol(void *gw,void *actor,StgGoal *g)
{
    Vec3 a={0,0,0};if(!char_position(actor,&a))return;
    if(!g->patrol_init){g->patrol_center=g->has_dest?g->dest:a;g->patrol_init=1;g->patrol_idx=0;}
    Vec3 pts[12];int np=0;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    for(int i=0;i<n&&np<12;i++){
        void *x=b[i];if(!x||!readable(x,0x80)||!g_wgp_isplayer_building(x))continue;
        Vec3 bp=*(Vec3 *)((uintptr_t)x+0x48);
        if(wgp_distance(bp,g->patrol_center)>STG_PATROL_RADIUS)continue;
        int dup=0;for(int k=0;k<np;k++)if(wgp_distance(pts[k],bp)<60.0f){dup=1;break;}
        if(!dup)pts[np++]=bp;
    }
    if(np<2){
        static const float off[4][2]={{150,0},{0,150},{-150,0},{0,-150}};
        np=0;for(int k=0;k<4;k++){pts[np]=g->patrol_center;pts[np].x+=off[k][0];pts[np].z+=off[k][1];np++;}
    }
    if(g->patrol_idx>=np)g->patrol_idx=0;
    Vec3 t=pts[g->patrol_idx];
    float d=wgp_distance(a,t);
    if(stg_walk_to_pos(actor,g,t,d)){
        g->patrol_idx=(g->patrol_idx+1)%np;
        g->last_progress_ms=GetTickCount();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Patrolling (%d/%d waypoints) until cancelled or paused",g->patrol_idx+1,np);
}

/* A direct standing order (hold, come here, guard, patrol) ends patrol/guard goals (bug 63). */
static void stg_cancel_standing_goals(uint32_t actor_serial)
{
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];
        if(!g->used||g->actor_serial!=actor_serial)continue;
        if(g->state!=STG_STATE_ACTIVE&&g->state!=STG_STATE_PAUSED)continue;
        if(strcmp(g->kind,"PATROL")&&strcmp(g->kind,"GUARD"))continue;
        g->rt_return_started=1; /* replaced by a new order: no walk-back */
        stg_finish(g,STG_STATE_CANCELLED,"replaced by a new order");
    }
}"""),
])
