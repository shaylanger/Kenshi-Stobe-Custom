#!/usr/bin/env python3
"""Bug 92: with no food anywhere, GOAL_MEAL re-armed every tick: `hungry` logged
~every 60 ms and stg_nearest_storage rescanned each tick (583 lines in one goal).
Fix: after "no food anywhere", wait 10 game min before looking again.

Bug 93: "Make 1 building material" BLOCKED twice at the Manual Stone Processor
("exists but made no progress") while Malzin was working it: the planner only
counts a finished unit as progress, and one manual unit takes longer than
WGP_STALL_MS (30 game min). Fix: standing at the machine (inputs ready, she
reached the operate step) counts as progress, up to 4 game h per unit.
Usage: patch_r19_bug92_93_meal_stall.py <KenshiFP tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("client/stobe_task_goals.inc", [
    ("typedef struct { uint32_t serial; int eating; int eaten; int warned; float last_d; int still; DWORD next_ms; } SgmMeal;",
     "typedef struct { uint32_t serial; int eating; int eaten; int warned; float last_d; int still; DWORD next_ms; DWORD retry_ms; } SgmMeal;\n"
     "#define SGM_NOFOOD_RETRY_MS 600000 /* bug 92: no food anywhere -> look again in 10 game min */"),
    ("""    SgmMeal *m=sgm_slot(serial);if(!m)return 0;
    if(!m->eating){
        if(lvl>=SGM_START_LEVEL){if(lvl>=SGM_STOP_LEVEL)m->warned=0;return 0;}
        m->eating=1;m->eaten=0;m->last_d=0;m->still=0;
        logline("[stobe] GOAL_MEAL hungry actor=%s level=%.0f",name,lvl);
    }
    DWORD now=stobe_game_ms();
""",
     """    SgmMeal *m=sgm_slot(serial);if(!m)return 0;
    DWORD now=stobe_game_ms();
    if(!m->eating){
        if(lvl>=SGM_START_LEVEL){if(lvl>=SGM_STOP_LEVEL)m->warned=0;m->retry_ms=0;return 0;}
        if(m->retry_ms&&(LONG)(now-m->retry_ms)<0)return 0; /* bug 92 */
        m->eating=1;m->eaten=0;m->last_d=0;m->still=0;m->retry_ms=0;
        logline("[stobe] GOAL_MEAL hungry actor=%s level=%.0f",name,lvl);
    }
"""),
    ("""    if(!store){
        m->eating=0;
""",
     """    if(!store){
        m->eating=0;m->retry_ms=now+SGM_NOFOOD_RETRY_MS;
"""),
])

patch("client/stobe_work_planner.inc", [
    ("#define WGP_STALL_MS 1800000\n",
     "#define WGP_STALL_MS 1800000\n"
     "#define WGP_UNIT_MAX_MS 14400000 /* bug 93: most game time one unit may take while she stands at the machine */\n"
     "#define WGP_OPERATE_NEAR 120.0f\n"),
    ("    DWORD haul_next_ms;\n} WgpGoal;",
     "    DWORD haul_next_ms;\n    DWORD rt_unit_start_ms;    /* runtime only: since when she has been at the machine for this unit (bug 93) */\n} WgpGoal;"),
    ("""    if (current!=g->last_count) {
        g->last_count=current; g->last_progress_ms=now; g_wgp_dirty=1;
    }""",
     """    if (current!=g->last_count) {
        g->last_count=current; g->last_progress_ms=now; g->rt_unit_start_ms=0; g_wgp_dirty=1;
    }"""),
    ("""    snprintf(g->current_step,sizeof(g->current_step),"Making %s: %d/%d complete at %s",
             g->item,g->completed,g->quantity,
             root.building_name[0]?root.building_name:"production building");
    if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_STALL_MS) {""",
     """    snprintf(g->current_step,sizeof(g->current_step),"Making %s: %d/%d complete at %s",
             g->item,g->completed,g->quantity,
             root.building_name[0]?root.building_name:"production building");
    {   /* bug 93: a manual machine can need longer than WGP_STALL_MS for one unit;
         * her standing at it counts as work, up to WGP_UNIT_MAX_MS per unit. */
        Vec3 bp=*(Vec3 *)((uintptr_t)root.building+0x48);
        if (wgp_distance(pos,bp)<=WGP_OPERATE_NEAR) {
            if (!g->rt_unit_start_ms) g->rt_unit_start_ms=now;
            if ((LONG)(now-g->rt_unit_start_ms)<WGP_UNIT_MAX_MS) g->last_progress_ms=now;
        }
    }
    if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_STALL_MS) {"""),
])
