#!/usr/bin/env python3
"""Bug 83: goals live in our own files (stobe_work_goals.tsv /
stobe_task_goals.tsv), not in the Kenshi save, so a goal given after a save
came back when that older save was loaded. Stamp each goal with the in-game
world time it was given; drop (silently) any goal stamped later than the
world we are in now.
Usage: patch_r19_bug83_goal_save.py <KenshiFP tree root>   (e.g. /root/KenshiFP)"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]) / "client"

def rep(s, a, b):
    if b in s:
        return s
    assert s.count(a) == 1, ("anchor", a[:80], s.count(a))
    return s.replace(a, b)

# ---------------- work planner ----------------
p = root / "stobe_work_planner.inc"; s = p.read_text()
s = rep(s, "    DWORD created_ms;\n    DWORD last_progress_ms;\n    DWORD last_order_ms;",
        "    DWORD created_ms;\n    double created_gt;   /* in-game seconds when given (bug 83); 0 = unknown */\n"
        "    DWORD last_progress_ms;\n    DWORD last_order_ms;")

CLOCK = r'''static DWORD stobe_game_ms(void)
{
    if (!g_sgc_real_last) return GetTickCount();
    return (DWORD)(unsigned long long)g_sgc_game_ms;
}
'''
WORLD = CLOCK + r'''
/* In-game world time (bug 83): goals live in our own files, not in the Kenshi
 * save, so a goal given after a save came back when that older save was
 * loaded. Goals are stamped with the world time they were given; any goal
 * stamped later than the loaded world is dropped silently. */
#define KLIB_GW_GAMETIME_SYM "?getTimeStamp_inGameHours@GameWorld@@QEAA?AVTimeOfDay@@XZ"
typedef void *(*gw_gametime_t)(void *, double *);
static double g_sgt_now;      /* world seconds at the last tick, 0 = unknown */
static int g_sgt_dead;
static void stobe_world_time_update(void *gw)
{
    if (g_sgt_dead || !gw || !first_player_char(gw)) return; /* world not loaded */
    static gw_gametime_t fn;
    if (!fn) {
        HMODULE k = GetModuleHandleA("KenshiLib.dll");
        if (k) fn = (gw_gametime_t)GetProcAddress(k, KLIB_GW_GAMETIME_SYM);
        if (!fn) { g_sgt_dead = 1; logline("[stobe] GOAL_LOAD world time export missing -- save check off"); return; }
    }
    double hours = 0;
    if (setjmp(g_guard_jb)) { g_guard_armed = 0; g_sgt_dead = 1; logline("[stobe] GOAL_LOAD world time faulted -- save check off"); return; }
    guard_arm();
    fn(gw, &hours); /* TimeOfDay comes back through the hidden pointer: one double, hours */
    g_guard_armed = 0;
    if (hours > 0.01 && hours < 1.0e7) {
        if (g_sgt_now <= 0) logline("[stobe] GOAL_LOAD world time %.0f s", hours * 3600.0);
        g_sgt_now = hours * 3600.0;
    }
}

/* 1 when a goal was given after the world we are in now (an older save was loaded). */
static int stobe_goal_from_future(double created_gt)
{
    return created_gt > 0 && g_sgt_now > 0 && created_gt > g_sgt_now + 30.0;
}
'''
s = rep(s, CLOCK, WORLD)

s = rep(s, '\\t%d\\t%s\\n",\n            g->id,g->actor_serial,g->actor,g->item,g->quantity,g->baseline,g->completed,',
        '\\t%d\\t%s\\t%.0f\\n",\n            g->id,g->actor_serial,g->actor,g->item,g->quantity,g->baseline,g->completed,')
s = rep(s, "            g->state,g->last_count,g->current_step,g->reason,g->report_triggered,subbuf);",
        "            g->state,g->last_count,g->current_step,g->reason,g->report_triggered,subbuf,g->created_gt);")
s = rep(s, "        char *fields[19]={0};\n        int n=0;\n        char *p=line;\n        while (n<19) {",
        "        char *fields[20]={0};\n        int n=0;\n        char *p=line;\n        while (n<20) {")
s = rep(s, "        if (n>17) g.report_triggered=atoi(fields[17]);\n",
        "        if (n>17) g.report_triggered=atoi(fields[17]);\n        if (n>19) g.created_gt=atof(fields[19]);\n")
s = rep(s, "                slot->created_ms=stobe_game_ms();\n                slot->last_progress_ms=stobe_game_ms();\n                slot->rt_seen_active=1;",
        "                slot->created_ms=stobe_game_ms();\n                slot->created_gt=g_sgt_now;\n"
        "                slot->last_progress_ms=stobe_game_ms();\n                slot->rt_seen_active=1;")
s = rep(s, "    wgp_load();\n    wgp_consume_requests(gw);\n    wgp_controls();\n",
        "    wgp_load();\n    stobe_world_time_update(gw);\n    wgp_consume_requests(gw);\n    wgp_controls();\n"
        "    for (int i=0;i<WGP_MAX_GOALS;i++) {\n"
        "        WgpGoal *g=&g_wgp_goals[i];\n"
        "        if (!g->used || (g->state!=0 && g->state!=4) || !stobe_goal_from_future(g->created_gt)) continue;\n"
        "        g->state=3; g->report_triggered=1; g->rt_return_started=1; g->rt_seen_active=0;\n"
        "        strncpy(g->reason,\"given after the loaded save was made; dropped on load\",sizeof(g->reason)-1);\n"
        "        logline(\"[stobe] GOAL_LOAD dropped id=%s actor=%s given_at=%.0f world_now=%.0f\",g->id,g->actor,g->created_gt,g_sgt_now);\n"
        "        g_wgp_dirty=1;\n"
        "    }\n")
p.write_text(s); print("patched", p)

# ---------------- task goals ----------------
p = root / "stobe_task_goals.inc"; s = p.read_text()
s = rep(s, "    DWORD created_ms;\n    DWORD last_action_ms;\n    DWORD last_progress_ms;",
        "    DWORD created_ms;\n    double created_gt;   /* in-game seconds when given (bug 83) */\n"
        "    DWORD last_action_ms;\n    DWORD last_progress_ms;")
s = rep(s, '    slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();\n    snprintf(slot->current_step,sizeof(slot->current_step),"Subgoal for',
        '    slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();slot->created_gt=g->created_gt>0?g->created_gt:g_sgt_now;\n    snprintf(slot->current_step,sizeof(slot->current_step),"Subgoal for')
s = rep(s, "slot->state=STG_STATE_APPROVAL;slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();",
        "slot->state=STG_STATE_APPROVAL;slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();slot->created_gt=g_sgt_now;")
s = rep(s, "                g->created_ms=stobe_game_ms();g->last_progress_ms=stobe_game_ms();\n                g->rt_seen_active=1;",
        "                g->created_ms=stobe_game_ms();g->last_progress_ms=stobe_game_ms();g->created_gt=g_sgt_now;\n                g->rt_seen_active=1;")
s = rep(s, '\\t%d\\t%d\\t%s\\t%s\\t%s\\n",\n            g->id,g->actor_serial,g->actor,g->kind,g->item,g->target,g->destination,',
        '\\t%d\\t%d\\t%s\\t%s\\t%s\\t%.0f\\n",\n            g->id,g->actor_serial,g->actor,g->kind,g->item,g->target,g->destination,')
s = rep(s, "            g->current_step,g->reason,seen);", "            g->current_step,g->reason,seen,g->created_gt);")
s = rep(s, "        char *fields[23]={0};int n=0;char *p=line;\n        while(n<23){",
        "        char *fields[24]={0};int n=0;char *p=line;\n        while(n<24){")
s = rep(s, "        g.created_ms=stobe_game_ms();g.last_progress_ms=stobe_game_ms();\n        for(int i=0;i<STG_MAX_GOALS;i++)if(!g_stg_goals[i].used){g_stg_goals[i]=g;break;}",
        "        if(n>23)g.created_gt=atof(fields[23]);\n"
        "        g.created_ms=stobe_game_ms();g.last_progress_ms=stobe_game_ms();\n"
        "        for(int i=0;i<STG_MAX_GOALS;i++)if(!g_stg_goals[i].used){g_stg_goals[i]=g;break;}")
s = rep(s, "    stg_load();stg_consume_requests();stg_controls();\n",
        "    stg_load();stobe_world_time_update(gw);stg_consume_requests();stg_controls();\n"
        "    for(int i=0;i<STG_MAX_GOALS;i++){\n"
        "        StgGoal *g=&g_stg_goals[i];\n"
        "        if(!g->used||(g->state!=STG_STATE_ACTIVE&&g->state!=STG_STATE_PAUSED&&g->state!=STG_STATE_APPROVAL)||!stobe_goal_from_future(g->created_gt))continue;\n"
        "        g->state=STG_STATE_CANCELLED;g->report_triggered=1;g->rt_return_started=1;g->rt_seen_active=0;\n"
        "        strncpy(g->reason,\"given after the loaded save was made; dropped on load\",sizeof(g->reason)-1);\n"
        "        logline(\"[stobe] GOAL_LOAD dropped id=%s actor=%s kind=%s given_at=%.0f world_now=%.0f\",g->id,g->actor,g->kind,g->created_gt,g_sgt_now);\n"
        "        g_stg_dirty=1;\n"
        "    }\n")
p.write_text(s); print("patched", p)
