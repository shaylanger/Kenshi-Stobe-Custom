#!/usr/bin/env python3
"""KenshiFP round 18d (feature 4): goals in Kenshi's job list + on-screen goal label.

A) Real jobs: when a work goal puts the NPC on a machine (mine, processor, farm,
   well, silo, oven, bench) it also adds that machine as a real Kenshi job
   (Character::addJob), so it shows in her in-game job list ("Operate Stone Mine").
   When the plan moves to another machine, or the goal ends/pauses, the job it added
   is removed (found by its Tasker pointer). Custom steps (walking, hauling, patrol,
   fetch/store) stay outside the job list. Safety: after each removal the job count
   must drop by exactly one and our job must be gone; otherwise job mirroring is
   switched off for the session (log "GOAL_JOB ... disabled").
B) Label: a MyGUI TextBox "StobeGoalLabel" at the top centre shows the SELECTED squad
   member's goal (any camera mode), refreshed 4x/s:
       Malzin - Make 5 Building Material (3/5)
       Making Building Material at Manual Stone Processor
       +1 more queued
   Ended goals (complete/blocked/cancelled) stay visible for 60 s with the result or
   block reason. Hidden when the selected character has no goal. A fault disables
   the label for the session (log "GOAL_LABEL ... disabled").

Usage: patch_kfp_round18d.py <KenshiFP root>
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
    # runtime fields
    ("    void *rt_task_building; /* runtime only: building the last operate order was for */\n",
     "    void *rt_task_building; /* runtime only: building the last operate order was for */\n"
     "    const void *rt_job_tasker; /* runtime only: the Kenshi job (Tasker) this goal added */\n"
     "    uint32_t rt_job_serial;    /* runtime only: whose job list it is in */\n"
     "    DWORD rt_end_ms;           /* runtime only: when the goal ended (label) */\n"),
    # job helpers + use in wgp_issue_goal_task
    ("/* Operate order for a goal; clears the old order first when the target building changes. */\nstatic int wgp_issue_goal_task(void *actor, WgpGoal *g, WgpProducer *p)\n{\n    if (!actor || !p || !p->building) return 0;\n    if (g->rt_task_building != p->building) {",
     r'''/* ---- real Kenshi jobs for goal machines (round 18d) ---- */
#define KLIB_CHR_ADDJOB_SYM "?addJob@Character@@QEAAXW4TaskType@@PEAVRootObject@@_N2AEBVVector3@Ogre@@@Z"
#define KLIB_CHR_PJCOUNT_SYM "?getPermajobCount@Character@@QEBAHXZ"
#define KLIB_CHR_PJDATA_SYM "?getPermajobData@Character@@QEBAPEBVTasker@@H@Z"
#define KLIB_CHR_PJREMOVE_SYM "?removePermajob@Character@@QEAAXH@Z"
typedef void (*chr_addjob_t)(void *, int, void *, char, char, const Vec3 *);
typedef int (*chr_pjcount_t)(void *);
typedef const void *(*chr_pjdata_t)(void *, int);
typedef void (*chr_pjremove_t)(void *, int);
static chr_addjob_t g_chr_addjob;
static chr_pjcount_t g_chr_pjcount;
static chr_pjdata_t g_chr_pjdata;
static chr_pjremove_t g_chr_pjremove;
static int g_goal_jobs_dead;

static int wgp_job_exports(void)
{
    if (g_goal_jobs_dead) return 0;
    if (g_chr_addjob && g_chr_pjcount && g_chr_pjdata && g_chr_pjremove) return 1;
    HMODULE k = GetModuleHandleA("KenshiLib.dll");
    if (!k) return 0;
    g_chr_addjob = (chr_addjob_t)GetProcAddress(k, KLIB_CHR_ADDJOB_SYM);
    g_chr_pjcount = (chr_pjcount_t)GetProcAddress(k, KLIB_CHR_PJCOUNT_SYM);
    g_chr_pjdata = (chr_pjdata_t)GetProcAddress(k, KLIB_CHR_PJDATA_SYM);
    g_chr_pjremove = (chr_pjremove_t)GetProcAddress(k, KLIB_CHR_PJREMOVE_SYM);
    if (!(g_chr_addjob && g_chr_pjcount && g_chr_pjdata && g_chr_pjremove)) {
        g_goal_jobs_dead = 1;
        logline("[stobe] GOAL_JOB exports missing -- job mirroring disabled");
        return 0;
    }
    return 1;
}

/* Remove the job this goal added (matched by Tasker pointer). */
static void wgp_job_release_actor(void *actor, WgpGoal *g)
{
    if (!g->rt_job_tasker) return;
    const void *mine = g->rt_job_tasker;
    g->rt_job_tasker = NULL;
    if (!actor || !wgp_job_exports()) return;
    int n = g_chr_pjcount(actor);
    if (n <= 0 || n > 64) return;
    int idx = -1;
    for (int i = 0; i < n; i++) if (g_chr_pjdata(actor, i) == mine) { idx = i; break; }
    if (idx < 0) return; /* player removed it already */
    g_chr_pjremove(actor, idx);
    int after = g_chr_pjcount(actor);
    int still = 0;
    for (int i = 0; i < after && i < 64; i++) if (g_chr_pjdata(actor, i) == mine) still = 1;
    if (after != n - 1 || still) {
        g_goal_jobs_dead = 1;
        logline("[stobe] GOAL_JOB unexpected removal (before=%d after=%d still=%d) -- job mirroring disabled", n, after, still);
        return;
    }
    logline("[stobe] GOAL_JOB removed id=%s index=%d", g->id, idx);
}

/* Add the goal's current machine as a real job in her job list. */
static void wgp_job_add(void *actor, WgpGoal *g, WgpProducer *p)
{
    if (!actor || !p || !p->building || !wgp_job_exports()) return;
    int n = g_chr_pjcount(actor);
    if (n < 0 || n > 60) return;
    Vec3 pos = *(Vec3 *)((uintptr_t)p->building + 0x48);
    int task = p->task > 0 ? p->task : 87;
    g_chr_addjob(actor, task, p->building, 1 /*shift: append*/, 1 /*don't clear*/, &pos);
    int after = g_chr_pjcount(actor);
    if (after == n + 1) {
        g->rt_job_tasker = g_chr_pjdata(actor, after - 1);
        uint32_t *h = (uint32_t *)((uintptr_t)actor + CHAR_HANDLE + HAND_IDS);
        g->rt_job_serial = readable(h, 20) ? h[4] : g->actor_serial;
        logline("[stobe] GOAL_JOB added id=%s job=%s task=%d", g->id,
                p->building_name[0] ? p->building_name : "building", task);
    } else {
        logline("[stobe] GOAL_JOB add did not create one job (before=%d after=%d)", n, after);
    }
}

/* Operate order for a goal; clears the old order first when the target building changes. */
static int wgp_issue_goal_task(void *actor, WgpGoal *g, WgpProducer *p)
{
    if (!actor || !p || !p->building) return 0;
    if (g->rt_task_building != p->building) {
        wgp_job_release_actor(actor, g);
        wgp_job_add(actor, g, p);'''),
    # release jobs + remember end time when the goal is not active
    ("""            if (!already_running) {
                active_actors[active_actor_count++]=g->actor_serial;
                wgp_goal_tick_guarded(gw,g);""",
     """            if (!already_running) {
                active_actors[active_actor_count++]=g->actor_serial;
                wgp_goal_tick_guarded(gw,g);
                if (g->state!=0) g->rt_end_ms=GetTickCount();"""),
    ("        wgp_maybe_trigger_report(gw,g);\n    }\n    wgp_status_write();",
     "        if (g->used && g->state!=0 && g->rt_job_tasker) {\n"
     "            /* goal ended or paused: take its job out of her list */\n"
     "            if (!g->rt_end_ms) g->rt_end_ms=GetTickCount();\n"
     "            wgp_job_release_actor(wgp_find_squad_actor(gw,g->actor_serial,g->actor),g);\n"
     "            g->rt_task_building=NULL; /* re-add on resume */\n"
     "        }\n"
     "        wgp_maybe_trigger_report(gw,g);\n    }\n    wgp_status_write();"),
])

patch("stobe_task_goals.inc", [
    ("    float walk_last_dist;   /* runtime only: walking to a storage building */\n",
     "    float walk_last_dist;   /* runtime only: walking to a storage building */\n"
     "    DWORD rt_end_ms;        /* runtime only: when the goal ended (label) */\n"),
    # stamp end time for task goals in sgr_scan (runs every tick)
    ("        if(g->state==STG_STATE_ACTIVE){g->rt_seen_active=1;continue;}\n        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){",
     "        if(g->state==STG_STATE_ACTIVE){g->rt_seen_active=1;g->rt_end_ms=0;continue;}\n"
     "        if(g->rt_seen_active&&!g->rt_end_ms)g->rt_end_ms=GetTickCount();\n"
     "        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){"),
    # the label
    ("static void stobe_task_goal_tick(void *gw)\n{",
     r'''/* ---- on-screen goal label for the selected squad member (round 18d) ---- */
#define GOAL_LABEL_KEEP_MS 60000
static void caption_set(void *w, const char *text, textbox_setcap_t setter); /* kenshifp_client.c */
static void *make_mstr_long(unsigned char *b32, const char *s);              /* kenshifp_client.c */
static void *g_goal_label;
static int g_goal_label_dead;
static DWORD g_goal_label_next;
static char g_goal_label_text[600];

static const char *goal_label_state(int state)
{
    switch(state){case 1:return "DONE";case 2:return "BLOCKED";case 3:return "CANCELLED";case 4:return "PAUSED";case 5:return "NEEDS APPROVAL";default:return "";}
}

static void goal_label_build(void *gw,char *out,size_t outsz)
{
    out[0]='\0';
    void *sel=first_player_char(gw);
    if(!sel||!readable((void *)((uintptr_t)sel+CHAR_HANDLE+HAND_IDS),20))return;
    uint32_t serial=((uint32_t *)((uintptr_t)sel+CHAR_HANDLE+HAND_IDS))[4];
    DWORD now=GetTickCount();
    const char *actor="";char head[200]="",step[260]="";int more=0,found=0;
    /* work goals first: active/paused, else the most recent ended one still in the keep window */
    for(int pass=0;pass<2&&!found;pass++){
        for(int i=0;i<WGP_MAX_GOALS;i++){
            WgpGoal *g=&g_wgp_goals[i];
            if(!g->used||g->actor_serial!=serial)continue;
            int live=(g->state==0||g->state==4);
            int recent=g->rt_end_ms&&(LONG)(now-g->rt_end_ms)<GOAL_LABEL_KEEP_MS;
            if(pass==0?!live:!recent)continue;
            if(found){if(live)more++;continue;}
            found=1;actor=g->actor;
            const char *st=goal_label_state(g->state);
            if(st[0])snprintf(head,sizeof(head),"Make %d %s  (%d/%d) %s",g->quantity,g->item,g->completed,g->quantity,st);
            else snprintf(head,sizeof(head),"Make %d %s  (%d/%d)",g->quantity,g->item,g->completed,g->quantity);
            snprintf(step,sizeof(step),"%s",g->state==2&&g->reason[0]?g->reason:g->current_step);
        }
    }
    for(int pass=0;pass<2&&!found;pass++){
        for(int i=0;i<STG_MAX_GOALS;i++){
            StgGoal *g=&g_stg_goals[i];
            if(!g->used||g->actor_serial!=serial)continue;
            int live=(g->state==STG_STATE_ACTIVE||g->state==STG_STATE_PAUSED||g->state==STG_STATE_APPROVAL);
            int recent=g->rt_end_ms&&(LONG)(now-g->rt_end_ms)<GOAL_LABEL_KEEP_MS;
            if(pass==0?!live:!recent)continue;
            if(found){if(live)more++;continue;}
            found=1;actor=g->actor;
            char what[160];
            if(!strcmp(g->kind,"STOCK"))snprintf(what,sizeof(what),"Keep %d %s stocked",g->minimum_stock,g->item);
            else if(!strcmp(g->kind,"PATROL"))snprintf(what,sizeof(what),"Patrol");
            else if(!strcmp(g->kind,"GUARD"))snprintf(what,sizeof(what),"Guard %s",g->target[0]?g->target:"position");
            else if(g->quantity>0)snprintf(what,sizeof(what),"%s %s  (%d/%d)",g->kind,g->item,g->completed,g->quantity);
            else snprintf(what,sizeof(what),"%s %s",g->kind,g->item);
            const char *st=goal_label_state(g->state);
            snprintf(head,sizeof(head),"%s%s%s",what,st[0]?"  ":"",st);
            snprintf(step,sizeof(step),"%s",g->state==STG_STATE_BLOCKED&&g->reason[0]?g->reason:g->current_step);
        }
    }
    if(!found)return;
    if(more>0)snprintf(out,outsz,"%s - %s\n%s\n+%d more queued",actor,head,step,more);
    else snprintf(out,outsz,"%s - %s\n%s",actor,head,step);
}

static void stobe_goal_label_update(void *gw)
{
    if(g_goal_label_dead||!gw||!g_gui_getinstance||!g_gui_createwidget||!g_widget_setvisible||!g_textbox_setcap)return;
    DWORD now=GetTickCount();
    if(g_goal_label_next&&(LONG)(now-g_goal_label_next)<0)return;
    g_goal_label_next=now+250;
    if(setjmp(g_guard_jb)){
        g_guard_armed=0;g_goal_label_dead=1;
        logline("[stobe] GOAL_LABEL faulted -- disabled for this session");
        return;
    }
    guard_arm();
    if(!g_goal_label){
        void *gui=g_gui_getinstance();
        if(!readable(gui,8)){g_guard_armed=0;return;}
        int cx=GetSystemMetrics(SM_CXSCREEN),cy=GetSystemMetrics(SM_CYSCREEN);
        if(cx<=0)cx=1920;
        (void)cy;
        unsigned char ty[32],sk[32],ly[32],nm[32];
        void *f1=make_mstr_long(ty,"TextBox");
        void *f2=make_mstr_long(sk,"Kenshi_GenericTextBoxFlat");
        void *f3=make_mstr_long(ly,"Pointer");
        void *f4=make_mstr_long(nm,"StobeGoalLabel");
        void *w=g_gui_createwidget(gui,ty,sk,cx/2-330,70,660,78,0,ly,nm);
        if(f1)free(f1);if(f2)free(f2);if(f3)free(f3);if(f4)free(f4);
        if(!readable(w,8)){g_guard_armed=0;g_goal_label_dead=1;logline("[stobe] GOAL_LABEL create failed -- disabled");return;}
        g_widget_setvisible(w,0);
        g_goal_label=w;
        g_goal_label_text[0]='\0';
        logline("[stobe] GOAL_LABEL widget created %p",w);
    }
    char text[600];
    goal_label_build(gw,text,sizeof(text));
    if(!text[0]){
        if(g_goal_label_text[0]){g_widget_setvisible(g_goal_label,0);g_goal_label_text[0]='\0';}
    }else if(strcmp(text,g_goal_label_text)){
        caption_set(g_goal_label,text,g_textbox_setcap);
        g_widget_setvisible(g_goal_label,1);
        strncpy(g_goal_label_text,text,sizeof(g_goal_label_text)-1);
    }
    g_guard_armed=0;
}

static void stobe_task_goal_tick(void *gw)
{'''),
])

patch("kenshifp_client.c", [
    ("    fp_gui_update();                      /* post-frame: all MyGUI widget work */\n",
     "    fp_gui_update();                      /* post-frame: all MyGUI widget work */\n"
     "    if (gw) stobe_goal_label_update(gw);  /* selected squad member's goal (round 18d) */\n"),
])
