#!/usr/bin/env python3
"""KenshiFP round 17b: an NPC walks back to the player when her goal ends.

Shay's request (2026-09-30): when a work/task goal finishes (COMPLETE, BLOCKED,
CANCELLED, or WAITING_APPROVAL), she returns to the player so he can give the next
order. Only for goals seen ACTIVE in this session (no walk-back on load), only
when she has no other active goal, re-ordered every 4 s, stops within 60 m,
gives up after 3 min. Arriving within 180 m also lets the existing report trigger.

Usage: patch_kfp_round17b.py <KenshiFP root>
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
    ("    long long dep_sig_last; /* runtime only: previous tick's sum */\n} WgpGoal;",
     "    long long dep_sig_last; /* runtime only: previous tick's sum */\n"
     "    int rt_seen_active;     /* runtime only: was ACTIVE this session */\n"
     "    int rt_return_started;  /* runtime only: walk-back already requested */\n} WgpGoal;"),
])

patch("stobe_task_goals.inc", [
    ("    int report_triggered;\n} StgGoal;",
     "    int report_triggered;\n"
     "    int rt_seen_active;     /* runtime only: was ACTIVE this session */\n"
     "    int rt_return_started;  /* runtime only: walk-back already requested */\n} StgGoal;"),
    ("static void stobe_task_goal_tick(void *gw)\n{",
     r'''/* ---- walk back to the player when a goal ends (round 17b) ---- */
#define SGR_MAX 8
#define SGR_STOP_DIST 60.0f
#define SGR_GIVEUP_MS 180000
#define SGR_REORDER_MS 4000
typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; } SgrReturn;
static SgrReturn g_sgr[SGR_MAX];

static int sgr_actor_busy(uint32_t serial)
{
    for(int i=0;i<WGP_MAX_GOALS;i++)
        if(g_wgp_goals[i].used&&g_wgp_goals[i].state==0&&g_wgp_goals[i].actor_serial==serial)return 1;
    for(int i=0;i<STG_MAX_GOALS;i++)
        if(g_stg_goals[i].used&&g_stg_goals[i].state==STG_STATE_ACTIVE&&g_stg_goals[i].actor_serial==serial)return 1;
    return 0;
}

static void sgr_start(uint32_t serial,const char *actor)
{
    if(!serial)return;
    SgrReturn *slot=NULL;DWORD now=GetTickCount();
    for(int i=0;i<SGR_MAX;i++)if(g_sgr[i].serial==serial){slot=&g_sgr[i];break;}
    if(!slot)for(int i=0;i<SGR_MAX;i++)if(!g_sgr[i].serial){slot=&g_sgr[i];break;}
    if(!slot)return;
    memset(slot,0,sizeof(*slot));
    slot->serial=serial;strncpy(slot->actor,actor?actor:"",sizeof(slot->actor)-1);
    slot->until_ms=now+SGR_GIVEUP_MS;slot->next_ms=now+1500; /* let the last order settle */
    logline("[stobe] GOAL_RETURN start actor=%s",slot->actor);
}

static void sgr_tick(void *gw)
{
    DWORD now=GetTickCount();
    for(int i=0;i<SGR_MAX;i++){
        SgrReturn *r=&g_sgr[i];if(!r->serial)continue;
        if((LONG)(now-r->until_ms)>0){logline("[stobe] GOAL_RETURN gave up actor=%s",r->actor);memset(r,0,sizeof(*r));continue;}
        if(sgr_actor_busy(r->serial)){memset(r,0,sizeof(*r));continue;} /* a new goal took over */
        if((LONG)(now-r->next_ms)<0)continue;
        r->next_ms=now+SGR_REORDER_MS;
        void *actor=wgp_find_squad_actor(gw,r->serial,r->actor);
        void *player=first_player_char(gw);
        Vec3 a={0,0,0},p={0,0,0};
        if(!actor||!player||actor==player||!char_position(actor,&a)||!char_position(player,&p))continue;
        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            logline("[stobe] GOAL_RETURN arrived actor=%s",r->actor);
            memset(r,0,sizeof(*r));continue;
        }
        if(!try_move_to_pos(actor,&p)){logline("[stobe] GOAL_RETURN move failed actor=%s",r->actor);memset(r,0,sizeof(*r));}
    }
}

static void sgr_scan(void)
{
    for(int i=0;i<WGP_MAX_GOALS;i++){
        WgpGoal *g=&g_wgp_goals[i];if(!g->used)continue;
        if(g->state==0){g->rt_seen_active=1;continue;}
        if(g->rt_seen_active&&!g->rt_return_started&&g->state>=1&&g->state<=3){
            g->rt_return_started=1;sgr_start(g->actor_serial,g->actor);
        }
    }
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];if(!g->used)continue;
        if(g->state==STG_STATE_ACTIVE){g->rt_seen_active=1;continue;}
        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){
            g->rt_return_started=1;sgr_start(g->actor_serial,g->actor);
        }
    }
}

static void stobe_task_goal_tick(void *gw)
{'''),
    ("        stg_maybe_trigger_report(gw,g);\n    }\n    stg_status();",
     "        stg_maybe_trigger_report(gw,g);\n    }\n    sgr_scan();\n    sgr_tick(gw);\n    stg_status();"),
])
