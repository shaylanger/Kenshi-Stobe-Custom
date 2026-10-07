/* Manual melee adapter (Gate 4, M01-M09; RE notes docs/MELEE_ADAPTER_RE.md).
 * Every native swing starts in AttackState::initialise (decision path and the
 * enemy's counter path). For the manual-owned CombatClass that hook refuses
 * swings unless the player clicked: the click makes the same writes the native
 * decision makes (nextMove=CHOP, state=STARTUP) at a legal moment, and the
 * game's own initialise picks the technique, so commitment, impact, dead time
 * and recovery stay native. RMB asks the native reactive block check; the
 * AI's own auto-block is refused while RMB is up (Shay 2026-10-05: blocking
 * is the player's job; stumbles stay native).
 * Runs on the game thread under the caller's crash guard. */
typedef char (*melee_attack_init_t)(void *);
typedef char (*melee_check_block_t)(void *,float,float);
typedef char (*melee_init_block_t)(void *,char);
typedef char (*melee_init_attack_t)(void *,void *);
static melee_attack_init_t g_melee_attack_init_orig;
static melee_check_block_t g_melee_check_block;
static melee_init_block_t g_melee_init_block_orig;
static melee_init_attack_t g_melee_init_attack; /* AttackState::initialiseAttack(st, target) */
static int g_melee_rmb;                  /* block input held this frame */
static unsigned g_melee_cancel_refused;  /* swings whose native cancel-into-block was refused (RMB up), see melee_attack_state_hook */
static int g_melee_cancel_noted;
static unsigned g_melee_abort_refused;  /* swings whose native need-block abort was refused (RMB up), see melee_need_block_hook */
static int g_melee_abort_noted;
static int g_melee_ready;                /* hook installed + bindings found */
static void *g_melee_owned_cc;           /* CombatClass under manual ownership */
static void *g_melee_owned_st;           /* its AttackState (seen in AttackState::initialise, st+8 == cc) */
static int g_melee_pending;              /* one click request, no queue (M07) */
static float g_melee_pending_left;
static int g_melee_armed, g_melee_fire_prev, g_melee_block_prev;
/* input diagnostics: manual ticks, the last aim/fire the tick saw, LMB edges ignored because aim (RMB) was held */
static unsigned g_melee_ticks, g_melee_fire_masked; static int g_melee_in_aim, g_melee_in_fire;
static unsigned g_melee_clicks, g_melee_swings, g_melee_ai_refused, g_melee_rejected, g_melee_blocks, g_melee_block_ok, g_melee_autoblock_refused, g_melee_out_of_reach;
static const char *g_melee_why="init";
/* Click->swing latency in real ms, measured in the product (M01: the harness round trip of a test's
 * input/poll commands is ~0.3 s each, so wall-clock timing in the wrapper can't prove "within 1 s"). */
#ifndef KFP_MELEE_NOW_MS
static double melee_now_ms(void) {
    LARGE_INTEGER f,c;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&c);
    return f.QuadPart?(double)c.QuadPart*1000.0/(double)f.QuadPart:0.0;
}
#define KFP_MELEE_NOW_MS() melee_now_ms()
#endif
static double g_melee_click_ms,g_melee_last_latency_ms=-1,g_melee_max_latency_ms;
static int g_melee_pending_failed;       /* the click's initialiseAttack failed at least once (retried until expiry) */
static unsigned g_melee_expired;         /* clicks whose buffer ran out before any attack init ran (not silent) */
/* Combat approach refusal (M06, Shay: player controls spacing, no remote chase). Every native combat approach
 * (WaitingStateAI/CircleStateAI per-frame updates, startupState's failed-block tail, AttackState::initialise and
 * initialiseAttack failure tails) goes through one CharMovement mover (RVA 0x2AE8C0, docs/MELEE_ADAPTER_RE.md).
 * While manual melee owns a fighter, calls on its movement object (CombatClass+0x170) are refused; the player's
 * locomotion (Task_Move / raw mover) uses other paths. Pointer compare only: the hook never dereferences. */
typedef void (*melee_approach_t)(void *,void *,float,float,float,char,float);
static melee_approach_t g_melee_approach_orig;
static void *g_melee_owned_mv;
static unsigned g_melee_approach_refused,g_melee_chase_frames,g_melee_chase_drops,g_melee_chase_swings;
/* Test switch (fp_melee force_chase on|off): every manual tick that finds the owned fighter in STARTUP/DECISION/
 * CIRCLE/WAIT (not dead) puts it in state=11/nextMove=10, the native trace-blocked chase lock (M09 GreatAnims), right
 * before the tick reads the state, i.e. exactly what the tick sees when the native update left the lock behind, so
 * the real chase-drop branch (state 10/11) runs deterministically (M09-CHASE). Forcing it at the END of the tick
 * (4080 b29: forced_chase 0->76, chase_drops 0->0) let the native update leave 11 before the next tick saw it.
 * forced_chase counts the forced frames. */
static int g_melee_force_chase;static unsigned g_melee_forced_chase;
static void fp_melee_set_force_chase(int on) {g_melee_force_chase=on!=0;}
static void melee_approach_hook(void *mv,void *pos,float a,float b,float c,char d,float e) {
    if (mv && mv==g_melee_owned_mv) {++g_melee_approach_refused;return;}
    g_melee_approach_orig(mv,pos,a,b,c,d,e);
}
/* Test switch (fp_melee passive <serial>|off): AI attack starts aimed at one character (target_h serial,
 * normally the manual fighter) are refused, so manual-click rows measure the fighter without being
 * stumble-locked by an enemy it may not auto-block (4080 batch 2: M01 4/5 clicks rejected in STUMBLE).
 * The fighter's own (owned) CombatClass is never affected. Cleared by `off`. */
/* Test switch (fp_melee spam <n> <period_ms>|off): n LMB press edges generated on the game thread at a fixed
 * real-time period (pressed for half of it), fed into the same click path as physical/injected input. Wrapper-driven
 * spam can't do this: every harness command is a ~0.3 s round trip, so 5090 batch 1's "15 clicks in 3 s" (M02) really
 * took ~12 s (8 swings + 7 rejected = native pace at ~0.8 s per click). */
static unsigned g_melee_spam_left,g_melee_spam_period_ms;
static int g_melee_spam_pressed;
static double g_melee_spam_next_ms,g_melee_spam_release_ms;
static void fp_melee_set_spam(unsigned n,unsigned period_ms) {
    g_melee_spam_left=n;g_melee_spam_period_ms=period_ms<20?20:period_ms;g_melee_spam_pressed=0;g_melee_spam_next_ms=-1;
}
static double g_melee_min_swing_gap,g_melee_min_swing_slack;
static unsigned g_melee_slack_n,g_melee_early_starts,g_melee_unfinished_starts;
static void fp_melee_spam_start(unsigned n,unsigned period_ms) {fp_melee_set_spam(n,period_ms);g_melee_min_swing_gap=-1;g_melee_slack_n=0;g_melee_min_swing_slack=0;g_melee_early_starts=0;g_melee_unfinished_starts=0;}
/* -1 = no spam (use the real input), else the synthesized LMB level for this frame */
static int melee_spam_fire(void) {
    if (!g_melee_spam_left && !g_melee_spam_pressed) return -1;
    double now=KFP_MELEE_NOW_MS();
    if (g_melee_spam_next_ms<0) g_melee_spam_next_ms=now;
    if (g_melee_spam_pressed) {
        if (now>=g_melee_spam_release_ms) {g_melee_spam_pressed=0;--g_melee_spam_left;}
    } else if (g_melee_spam_left && now>=g_melee_spam_next_ms) {
        g_melee_spam_pressed=1;g_melee_spam_release_ms=now+g_melee_spam_period_ms*0.5;g_melee_spam_next_ms+=g_melee_spam_period_ms;
        if (g_melee_spam_next_ms<now) g_melee_spam_next_ms=now+g_melee_spam_period_ms; /* slow frames: no burst catch-up */
    }
    return g_melee_spam_pressed;
}
/* Native swing timing in game seconds (M02/M04: proves the rate cap is the native swing, not click cadence).
 * swing = from the allowed AttackState::initialise until the CombatClass leaves CHOP; gap = between two allowed
 * swing starts. min_swing_gap resets when a spam starts. */
static double g_melee_game_s,g_melee_swing_start_s=-1,g_melee_last_swing_len,g_melee_swing_time,g_melee_min_swing_gap=-1;
static unsigned g_melee_swing_ends,g_melee_in_swing;
/* Per-pair swing check (M02, 4080 batch 11: min_swing_gap 0.941 s vs last_swing_len 1.304 s compared two different
 * swings; technique lengths vary 0.7-1.4 s). At each allowed swing start: slack = gap to the previous swing start minus
 * THAT swing's own CHOP length; early_starts = the previous swing had not left CHOP (end not seen). unfinished_starts
 * (diagnostic only, not a verdict) = CombatClass+0x158 (SDK techniqueFinished) still 0 at the next start after an uncut
 * swing: 4080 batch 11 state polls show finished=0 in DECISION/STUMBLE long after a swing, so the flag is not a
 * reliable end-of-swing marker. Reset when a spam starts. */
static int g_melee_last_exit_state=-1;   /* g_melee_min_swing_slack/slack_n/early_starts: declared with the spam switch */
/* Hold ground (M06): the approach hook alone left the owned fighter walking 1.4 m idle / 3 m per click toward a
 * target pinned 8 m away (5090 batch 1: approach_refused=4185, chase_frames=0). CombatClassAI::update sets
 * CharMovement mode 1 (combat locomotion, call at RVA 0x60CEF1) every frame outside the chase states, and the
 * combat mover (0x2AF1A0 on CharMovement+0x118) then steers into its range around a target it also resolves from a
 * second handle (CharMovement+0x248) that neither the approach setter nor halt clears. While the player owns the
 * fighter and is not driving (WASD direct drive/glide = mode 2), the CharMovement update hook halts (vt+0x98, the
 * stop native AttackState::initialise itself uses) any combat locomotion before the update runs: spacing is the
 * player's job. Anim-driven motion (animationOverride: swing commitment, stumble, reactions) and the CHOP/STUMBLE
 * states stay native. */
#define MV_COMBAT_MODE 0x378
#define MV_ANIM_OVERRIDE 0x37C
static unsigned g_melee_hold_halts;
static void fp_melee_hold_ground(void *mv) {
    if (!mv || mv!=g_melee_owned_mv || !g_melee_owned_cc) return;
    void *cc=g_melee_owned_cc;
    if (!readable((void *)((uintptr_t)cc+0x1f0),4) || !readable((void *)((uintptr_t)mv+MV_COMBAT_MODE),8)) return;
    int state=*(int *)((uintptr_t)cc+0x1f0);
    if (state==0 || state==8) return;                                   /* CHOP / STUMBLE: native */
    if (*(unsigned char *)((uintptr_t)mv+MV_ANIM_OVERRIDE)) return;     /* anim-driven motion: native */
    int mode=*(int *)((uintptr_t)mv+MV_COMBAT_MODE);
    if (mode!=1 && state!=10 && state!=11) return;   /* 2 = player direct drive/glide; 0 = no combat locomotion */
    void **vt=*(void ***)mv;
    if (!readable(vt,0xa0)) return;
    ((void (*)(void *))vt[0x98/8])(mv);++g_melee_hold_halts;
}
/* Click reject reasons (M08-CROWD, 4080 batch 11: 4 wrapper-"legal" clicks all rejected; the poll->click round trip is
 * ~1-2 s and a stumble-locked fighter flips 8<->3 several times a second). NULL = legal. */
static const char *g_melee_last_reject="none";
static int g_melee_last_reject_state=-1;
static unsigned g_melee_rej_stumble,g_melee_rej_chop,g_melee_rej_dead,g_melee_rej_other;
static const char *melee_click_block_why(int active,unsigned target,int dead,int state) {
    if (!active || !target) return "no_fight";
    if (g_melee_pending) return "pending";
    if (dead) return "dead_time";
    if (state==0) return "chop";
    if (state==8) return "stumble";
    if (state==1 || state==2) return "block";
    if (state==3 || state==4 || state==5 || state==6) return NULL;
    return "state";
}
/* Test switch (fp_melee click_legal [timeout_ms]): one LMB press edge generated on the game thread in the first frame
 * where a click is legal (same predicate as a real click), released the next frame; the evidence is the normal click
 * path (swings/out_of_reach/expired). cl_fired/cl_timeouts report whether a legal frame came. */
static int g_melee_cl_wait,g_melee_cl_release;
static double g_melee_cl_deadline_ms;
static unsigned g_melee_cl_fired,g_melee_cl_timeouts;
static void fp_melee_click_legal_start(unsigned timeout_ms) {
    g_melee_cl_wait=1;g_melee_cl_release=0;g_melee_cl_deadline_ms=KFP_MELEE_NOW_MS()+timeout_ms;
}
static unsigned g_melee_passive_serial;
static unsigned g_melee_passive_refused;
static void fp_melee_set_passive(unsigned serial) {g_melee_passive_serial=serial;}
enum { MELEE_CHOP=0, MELEE_BLOCK=1, MELEE_REACTION_BLOCK=2, MELEE_STARTUP=3, MELEE_DECISION=4,
       MELEE_CIRCLE=5, MELEE_WAIT=6, MELEE_STUMBLE=8 };
#define CC_WANTS_BLOCK 0x120
#define CC_ACTIVE      0x130
#define CC_DEADTIME    0x144
#define CC_STATE       0x1f0
#define CC_NEXTMOVE    0x1f4
#define CC_OWNER       0x188
#define CC_TARGET_H    0x298
#define CC_TARGET      0x290
#define CC_MOVEMENT    0x170
/* Native swing timer (M04-SPEED control, 5090 batch 2): CHOP spans of the controlled character's CombatClass in game
 * time, whoever starts the swing (our click or the native AI with fp_combat off), so manual and native-AI swing times
 * come from one meter. Runs every frame in FP mode, independent of manual ownership. */
static unsigned g_melee_nat_swing_ends;
static double g_melee_nat_swing_time,g_melee_nat_game_s,g_melee_nat_start_s=-1;
static void *g_melee_nat_cc;
/* Applied swing speed (M04-SPEED, 4080 batch 11: manual mean CHOP 0.837->1.085 s, native AI 1.174->1.007 s for attack
 * 5->80, single swings 0.08-1.38 s). Manual clicks and the native AI start a swing through the same initialiseAttack,
 * which plays the technique at speedMult = CharStats::attackSpeed(stats+0x188, derived from the attack skill) x
 * CombatTechniqueData::animSpeedMultiplier(+0x28) (RVA 0x2B48A4). Mean CHOP time mixes techniques (chosen by distance,
 * skill and the previous technique) and stumble-cut swings, so the meter records, per CHOP start, the attackSpeed the
 * game applied, and per technique the completed CHOP time (spans cut by STUMBLE/BLOCK counted apart as nat_cut).
 * `fp_melee swingstat [reset]`. */
#define CC_TECH 0x150
#define CC_TECH_DONE 0x158
#define CC_STATS 0x190
#define STATS_ATTACK_SPEED 0x188
#define TECH_ANIM_SPEED 0x28
#define TECH_IS_BLOCK 0x2c
#define MELEE_TECH_SLOTS 8
static struct {void *tech;unsigned n;double t;} g_melee_techs[MELEE_TECH_SLOTS];
static unsigned g_melee_tech_overflow,g_melee_nat_cut,g_melee_spd_n;
/* nat_cancel: CHOP spans that ended without the native natural end. A natural end (base attack state 0x609B00:
 * stateTimer<=0 and anim done) sets inDeadTime (+0x144) while the state is still CHOP; the next update moves to WAIT.
 * Every other exit cuts the swing whatever the attack speed: CombatClassAI::update aborts to DECISION with no dead time
 * when the target is KO/down (0x60CCB6..0x60CD6E, once the anim passes technique+0x40) or lost (0x60CF40); checkForNeedBlock
 * aborts an early swing to STARTUP; the combat enter/exit reset (0x664F20) sets DECISION + inDeadTime in the same call
 * (4080 batch 17: 0.63 s swings of a ~1.2 s technique passed because dead time was only checked at the exit sample).
 * Only spans with dead time seen in CHOP count as technique time. */
static unsigned g_melee_nat_cancel;static int g_melee_nat_dead_seen;
static double g_melee_spd_sum;
static float g_melee_spd_last=-1,g_melee_anim_spd_last=-1;
static void *g_melee_nat_tech;
static void fp_melee_swingstat_reset(void) {
    memset(g_melee_techs,0,sizeof(g_melee_techs));g_melee_tech_overflow=g_melee_nat_cut=g_melee_nat_cancel=g_melee_spd_n=0;g_melee_spd_sum=0;
    g_melee_spd_last=g_melee_anim_spd_last=-1;
}
static void melee_tech_add(void *tech,double t) {
    if (!tech) return;
    for (int i=0;i<MELEE_TECH_SLOTS;++i) {
        if (!g_melee_techs[i].tech) g_melee_techs[i].tech=tech;
        if (g_melee_techs[i].tech==tech) {++g_melee_techs[i].n;g_melee_techs[i].t+=t;return;}
    }
    ++g_melee_tech_overflow;
}
static void melee_swing_speed_sample(void *cc) {
    void *tech=*(void **)((uintptr_t)cc+CC_TECH),*stats=*(void **)((uintptr_t)cc+CC_STATS);
    g_melee_nat_tech=tech;
    if (!readable((void *)((uintptr_t)stats+STATS_ATTACK_SPEED),4)) return;
    float spd=*(float *)((uintptr_t)stats+STATS_ATTACK_SPEED);
    if (!isfinite(spd)) return;
    g_melee_spd_last=spd;g_melee_spd_sum+=spd;++g_melee_spd_n;
    g_melee_anim_spd_last=readable((void *)((uintptr_t)tech+TECH_ANIM_SPEED),4)?spd**(float *)((uintptr_t)tech+TECH_ANIM_SPEED):-1;
}
static int fp_melee_swingstat_append(char *b,size_t n) {
    int l=snprintf(b,n,"atk_speed_mean=%.4f atk_speed_n=%u atk_speed_last=%.4f anim_speed_last=%.4f nat_cut=%u nat_cancel=%u tech_overflow=%u techs=",
        g_melee_spd_n?g_melee_spd_sum/g_melee_spd_n:-1.0,g_melee_spd_n,g_melee_spd_last,g_melee_anim_spd_last,g_melee_nat_cut,g_melee_nat_cancel,g_melee_tech_overflow);
    int any=0;
    for (int i=0;i<MELEE_TECH_SLOTS && l>0 && (size_t)l<n;++i) if (g_melee_techs[i].tech) {
        l+=snprintf(b+l,n-l,"%s%llx:%u:%.3f",any?";":"",(unsigned long long)(uintptr_t)g_melee_techs[i].tech&0xffffffffull,g_melee_techs[i].n,g_melee_techs[i].t);any=1;
    }
    if (!any && l>0 && (size_t)l<n) l+=snprintf(b+l,n-l,"none");
    return l;
}
static void fp_melee_native_swing_step(void *pc,void *cc,float game_dt) {
    if (!readable(cc,0x2b8) || *(void **)((uintptr_t)cc+CC_OWNER)!=pc) {g_melee_nat_cc=NULL;g_melee_nat_start_s=-1;return;}
    if (cc!=g_melee_nat_cc) {g_melee_nat_cc=cc;g_melee_nat_start_s=-1;}
    if (!(isfinite(game_dt)&&game_dt>0)) return;                     /* paused: no time, no edge */
    g_melee_nat_game_s+=game_dt;
    int st=*(int *)((uintptr_t)cc+CC_STATE),dead=*(unsigned char *)((uintptr_t)cc+CC_DEADTIME);
    if (st==MELEE_CHOP) {
        if (g_melee_nat_start_s<0) {g_melee_nat_start_s=g_melee_nat_game_s;g_melee_nat_dead_seen=0;melee_swing_speed_sample(cc);}
        if (dead) g_melee_nat_dead_seen=1;
    }
    else if (g_melee_nat_start_s>=0) {
        double d=g_melee_nat_game_s-g_melee_nat_start_s;
        g_melee_nat_swing_time+=d;++g_melee_nat_swing_ends;g_melee_nat_start_s=-1;
        if (st==MELEE_STUMBLE || st==MELEE_BLOCK || st==MELEE_REACTION_BLOCK) ++g_melee_nat_cut;
        else if (!g_melee_nat_dead_seen) ++g_melee_nat_cancel;   /* exit-sample dead time alone = combat reset, not a natural end */
        else melee_tech_add(g_melee_nat_tech,d);
    }
}
static void fp_melee_observe_swing(void *gw,float dt) {
    if (!g_melee_ready || !g_melee_get_combat || !g_fp_mode || !gw) {g_melee_nat_start_s=-1;return;}
    void *pc=fp_controlled_char(gw);
    if (!char_valid(pc)) {g_melee_nat_start_s=-1;return;}
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?*(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    if (setjmp(g_guard_jb)) {g_guard_armed=0;g_melee_nat_start_s=-1;return;}
    guard_arm();
    void *cc=g_melee_get_combat(pc);
    g_guard_armed=0;
    fp_melee_native_swing_step(pc,cc,dt*speed);
}

/* The click's swing start: initialise's own success path (initialiseAttack, then the movement stop vcall +0x98).
 * Called from AttackState::initialise for a pending click, and from the chase drop (melee tick) when the native
 * startup is trace-blocked into chase and would never initialise the click (M09). 0 = no technique fits (the click
 * stays pending and retries until its buffer expires -> out_of_reach). */
static char melee_click_swing(void *st,void *cc) {
    void *target=*(void **)((uintptr_t)cc+CC_TARGET);
    /* previous technique still unfinished although its swing was not cut by a stumble/block = early re-init */
    void *ptech=*(void **)((uintptr_t)cc+CC_TECH);
    int unfinished=ptech && readable((void *)((uintptr_t)ptech+TECH_IS_BLOCK),1) && !*(unsigned char *)((uintptr_t)ptech+TECH_IS_BLOCK) &&
        !*(unsigned char *)((uintptr_t)cc+CC_TECH_DONE) && g_melee_last_exit_state!=MELEE_STUMBLE &&
        g_melee_last_exit_state!=MELEE_BLOCK && g_melee_last_exit_state!=MELEE_REACTION_BLOCK;
    if (!g_melee_init_attack(st,target)) {g_melee_pending_failed=1;return 0;}
    g_melee_pending=0;g_melee_pending_failed=0;
    void *mv=*(void **)((uintptr_t)cc+CC_MOVEMENT);
    if (mv) ((void (*)(void *))(*(void ***)mv)[0x98/8])(mv);
    ++g_melee_swings;g_melee_cancel_noted=0;g_melee_abort_noted=0;
    if (g_melee_swing_start_s>=0) {
        double gap=g_melee_game_s-g_melee_swing_start_s;
        if (g_melee_min_swing_gap<0 || gap<g_melee_min_swing_gap) g_melee_min_swing_gap=gap;
        if (unfinished) ++g_melee_unfinished_starts;
        if (g_melee_in_swing) ++g_melee_early_starts;
        else {double slack=gap-g_melee_last_swing_len;if (!g_melee_slack_n || slack<g_melee_min_swing_slack) g_melee_min_swing_slack=slack;++g_melee_slack_n;}
    }
    if (g_melee_in_swing) {   /* end never seen: close it here so the next pair compares the right swing */
        g_melee_last_swing_len=g_melee_game_s-g_melee_swing_start_s;g_melee_swing_time+=g_melee_last_swing_len;++g_melee_swing_ends;
    }
    g_melee_swing_start_s=g_melee_game_s;g_melee_in_swing=1;
    g_melee_last_latency_ms=KFP_MELEE_NOW_MS()-g_melee_click_ms;
    if (g_melee_last_latency_ms>g_melee_max_latency_ms) g_melee_max_latency_ms=g_melee_last_latency_ms;
    return 1;
}
static char melee_attack_init_hook(void *st) {
    void *cc=readable(st,0x10)?*(void **)((uintptr_t)st+8):NULL;
    if (cc && g_melee_passive_serial && cc!=g_melee_owned_cc && readable((void *)((uintptr_t)cc+CC_TARGET_H),0x20) &&
        *(unsigned *)((uintptr_t)cc+CC_TARGET_H+0x18)==g_melee_passive_serial) {
        *(int *)((uintptr_t)cc+CC_NEXTMOVE)=MELEE_WAIT;++g_melee_passive_refused;return 0;
    }
    if (cc && cc==g_melee_owned_cc) {
        g_melee_owned_st=st;
        if (!g_melee_pending) {
            /* AI initiative refused: park in WAIT, block/stumble untouched. */
            *(int *)((uintptr_t)cc+CC_NEXTMOVE)=MELEE_WAIT;++g_melee_ai_refused;return 0;
        }
        /* The click path runs initialise's own success path (initialiseAttack, then
         * the movement stop vcall +0x98) but not initialise's failure tail. initialiseAttack
         * itself also walks toward the target when no technique fits (0x2B4714): that call
         * is refused by melee_approach_hook, so an out-of-reach click whiffs in place (M06).
         * A failed attempt keeps the click pending (startupState retries next update) until its
         * buffer expires; then it counts as out_of_reach. At most one swing per click. */
        return melee_click_swing(st,cc);
    }
    return g_melee_attack_init_orig(st);
}
static char melee_init_block_hook(void *cc,char stumbling) {
    if (cc && cc==g_melee_owned_cc && !stumbling && !g_melee_rmb) {++g_melee_autoblock_refused;return 0;}
    return g_melee_init_block_orig(cc,stumbling);
}
/* Swing cancel without RMB (M04-SPEED, 4080 batch 16). The base CombatClass attack state (RVA 0x609B00, vt+0x58 body,
 * reached through CombatClassAI's wrapper 0x609EE0) cancels a committed CHOP into DECISION once the anim passes the
 * technique's cancel frame while wantsToBlock (+0x120) is set, and skips the dead time; the AI wrapper sets the flag
 * from the incoming-threat count every frame. The native AI follows that cancel with a block; for the owned fighter
 * the block is refused while RMB is up (melee_init_block_hook), so the swing was simply cut at its hit point with no
 * block and no recovery (batch 16: manual swings at attack 5 0.88-0.91 s vs the native 1.21 s for the same technique,
 * the exits went CHOP -> STARTUP with dead=0), which flattened the attack-speed curve. While owned and RMB is up the
 * flag is cleared just before the native attack state runs; with RMB held the native value stays (cancel into block). */
typedef char (*melee_attack_state_t)(void *);
static melee_attack_state_t g_melee_attack_state_orig;
static char melee_attack_state_hook(void *cc) {
    if (cc && cc==g_melee_owned_cc && !g_melee_rmb && *(unsigned char *)((uintptr_t)cc+CC_WANTS_BLOCK)) {
        *(unsigned char *)((uintptr_t)cc+CC_WANTS_BLOCK)=0;
        if (!g_melee_cancel_noted) {g_melee_cancel_noted=1;++g_melee_cancel_refused;}
    }
    return g_melee_attack_state_orig(cc);
}
/* checkForNeedBlock (RVA 0x607940, (cc, myAttackThr xmm1, incomingThr xmm2)): if the fighter's attack progress (+0x140)
 * is below myAttackThr and getBiggestThreat finds an incoming attack it writes state=STARTUP, nextMove=BLOCK, which
 * aborts a swing in its first half (CombatClassAI's attack state calls it with 0.5 every CHOP frame). For the owned
 * fighter the block that should follow is refused while RMB is up, so the swing was cut with no block. While owned and
 * RMB is up the native auto-block request is refused (blocking is the player's job); with RMB held it runs (M03).
 * abort_refused counts swings where it was refused in CHOP with an incoming threat listed (+0x228). */
static melee_check_block_t g_melee_need_block_orig;
static char melee_need_block_hook(void *cc,float my_thr,float in_thr) {
    if (cc && cc==g_melee_owned_cc && !g_melee_rmb) {
        if (*(int *)((uintptr_t)cc+CC_STATE)==MELEE_CHOP && *(unsigned *)((uintptr_t)cc+0x228) && !g_melee_abort_noted) {
            g_melee_abort_noted=1;++g_melee_abort_refused;
        }
        return 0;
    }
    return g_melee_need_block_orig(cc,my_thr,in_thr);
}
static void fp_melee_release(void) {
    if (g_melee_pending) {if (g_melee_pending_failed) ++g_melee_out_of_reach; else ++g_melee_expired;}
    g_melee_in_swing=0;g_melee_swing_start_s=-1;
    g_melee_owned_cc=NULL;g_melee_owned_mv=NULL;g_melee_owned_st=NULL;g_melee_pending=0;g_melee_pending_failed=0;g_melee_armed=0;g_melee_rmb=0;g_melee_cl_release=0;
}
/* Chase-lock drop (state 10/11 seen by the manual tick, see the call site): a pending click starts its swing here,
 * otherwise back to STARTUP (click pending) or WAIT. Returns the new state. */
static int melee_chase_drop(void *cc) {
    int state;
    ++g_melee_chase_frames;++g_melee_chase_drops;
    void *ost=g_melee_owned_st;
    if (g_melee_pending && ost && readable(ost,0x10) && *(void **)((uintptr_t)ost+8)==cc && melee_click_swing(ost,cc)) {
        state=MELEE_CHOP;++g_melee_chase_swings;
    } else state=g_melee_pending?MELEE_STARTUP:MELEE_WAIT;
    *(int *)((uintptr_t)cc+CC_STATE)=state;
    *(int *)((uintptr_t)cc+CC_NEXTMOVE)=g_melee_pending||state==MELEE_CHOP?MELEE_CHOP:MELEE_WAIT;   /* no stale 10 */
    return state;
}
static void fp_melee_manual_tick(void *gw,void *pc,int aim,int fire,float dt) {
    {int sp=melee_spam_fire();if (sp>=0) fire=sp;}
    ++g_melee_ticks;g_melee_in_aim=aim;g_melee_in_fire=fire;
    if (!g_melee_ready || !g_melee_get_combat) {g_melee_why="unready";fp_melee_release();return;}
    void *cc=g_melee_get_combat(pc);
    if (!readable(cc,0x2b8) || *(void **)((uintptr_t)cc+CC_OWNER)!=pc) {g_melee_why="no_combat";fp_melee_release();return;}
    float speed=readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)?*(float *)((uintptr_t)gw+GW_FRAMESPEED):0;
    int allowed=!g_ui_open && !g_is_down && (g_combat_injection||game_has_focus());
    if (!allowed || !(isfinite(speed)&&speed>0)) {
        g_melee_why=!allowed?"not_allowed":"paused";
        /* Paused: keep ownership (no AI swing), drop the click. UI/KO: yield to native. */
        if (!allowed) fp_melee_release();
        else if (g_melee_pending) {g_melee_pending=0;g_melee_pending_failed=0;++g_melee_expired;}
        g_melee_fire_prev=fire;g_melee_block_prev=aim;return;
    }
    void *mv=*(void **)((uintptr_t)cc+CC_MOVEMENT);
    if (g_melee_owned_cc!=cc) {
        fp_melee_release();g_melee_owned_cc=cc;
        /* Cancel an AI approach already under way when ownership starts (the CharMovement
         * vt+0x98 stop native initialise uses); later approaches are refused by the hook. */
        if (readable(mv,8) && readable(*(void **)mv,0xa0)) ((void (*)(void *))(*(void ***)mv)[0x98/8])(mv);
    }
    g_melee_owned_mv=mv;g_wound_melee_attacker=pc;   /* melee_hits: addWound calls by this fighter */
    g_melee_game_s+=dt*speed;
    if (g_melee_in_swing && *(int *)((uintptr_t)cc+CC_STATE)!=MELEE_CHOP) {
        g_melee_last_swing_len=g_melee_game_s-g_melee_swing_start_s;g_melee_swing_time+=g_melee_last_swing_len;
        ++g_melee_swing_ends;g_melee_in_swing=0;
        g_melee_last_exit_state=*(int *)((uintptr_t)cc+CC_STATE);
    }
    if (g_melee_pending) {
        g_melee_pending_left-=dt*speed;
        if (g_melee_pending_left<=0) {
            if (g_melee_pending_failed) ++g_melee_out_of_reach; else ++g_melee_expired;
            g_melee_pending=0;g_melee_pending_failed=0;
        }
    }
    if (!g_melee_armed) {                       /* no inherited click */
        if (!fire && !aim) g_melee_armed=1;
        g_melee_fire_prev=fire;g_melee_block_prev=aim;g_melee_why="arming";return;
    }
    g_melee_rmb=aim;
    if (g_melee_force_chase) {
        int s=*(int *)((uintptr_t)cc+CC_STATE);
        if (!*(unsigned char *)((uintptr_t)cc+CC_DEADTIME) && (s==MELEE_STARTUP || s==MELEE_DECISION || s==MELEE_CIRCLE || s==MELEE_WAIT)) {
            *(int *)((uintptr_t)cc+CC_STATE)=11;*(int *)((uintptr_t)cc+CC_NEXTMOVE)=10;++g_melee_forced_chase;
        }
    }
    int state=*(int *)((uintptr_t)cc+CC_STATE);
    int active=*(unsigned char *)((uintptr_t)cc+CC_ACTIVE);
    int dead=*(unsigned char *)((uintptr_t)cc+CC_DEADTIME);
    unsigned target=*(unsigned *)((uintptr_t)cc+CC_TARGET_H+0x18);
    g_melee_why="ok";
    /* Native trace-blocked/pathfind chase (states 10/11, CharMovement vt+0x80). While owned the chase can never finish
     * (its approach is refused, hold ground halts its locomotion), so the fighter stayed in it and every click was
     * rejected as "state" (M09 GreatAnims, 4080: 110/185 polls in state 11 after the first swing, swung=1 rejected+4;
     * root motion leaves the target out of reach). Drop it back to WAIT (STARTUP with a click pending, so the buffered
     * click still retries its attack init): spacing stays the player's job, an out-of-reach click still whiffs (M06). */
    if (state==10 || state==11) {
        /* With a click pending the startup that sent us here was trace-blocked (startupState: blocked -> 10 before it
         * ever calls initialise), so putting it back in STARTUP looped STARTUP -> 10 -> drop until the click expired
         * (4080 m09 gam/dodge: next=10, expired 1->30, swings 202->202, M04-INJ swings=0): the click's swing starts
         * here through the same path initialise would run (state = nextMove = CHOP on success, as startupState does).
         * No technique in reach: back to STARTUP, the click retries until it expires (out_of_reach, M06). */
        state=melee_chase_drop(cc);
    }
    if (g_melee_cl_release) {fire=0;g_melee_cl_release=0;}
    else if (g_melee_cl_wait) {
        if (KFP_MELEE_NOW_MS()>g_melee_cl_deadline_ms) {g_melee_cl_wait=0;++g_melee_cl_timeouts;}
        else if (!aim && !fire && !g_melee_fire_prev && !melee_click_block_why(active,target,dead,state)) {
            fire=1;g_melee_cl_wait=0;g_melee_cl_release=1;++g_melee_cl_fired;
        }
    }
    if (fire && !g_melee_fire_prev && aim) ++g_melee_fire_masked;
    if (fire && !g_melee_fire_prev && !aim) {
        ++g_melee_clicks;
        const char *bwhy=melee_click_block_why(active,target,dead,state);
        if (!bwhy) {
            g_melee_pending=1;g_melee_pending_left=0.25f;g_melee_pending_failed=0;g_melee_click_ms=KFP_MELEE_NOW_MS();
            *(int *)((uintptr_t)cc+CC_NEXTMOVE)=MELEE_CHOP;*(int *)((uintptr_t)cc+CC_STATE)=MELEE_STARTUP;
            if (g_melee_force_chase) {
                /* force_chase: the startup this click queued is trace-blocked (STARTUP -> 11/10) before the native
                 * update can run it, so the swing must start from the chase drop (b29: the native startup took it,
                 * chase_swings stayed 0) */
                *(int *)((uintptr_t)cc+CC_STATE)=11;*(int *)((uintptr_t)cc+CC_NEXTMOVE)=10;++g_melee_forced_chase;
                state=melee_chase_drop(cc);
            }
        } else {
            ++g_melee_rejected;g_melee_last_reject=bwhy;g_melee_last_reject_state=state;
            if (state==MELEE_STUMBLE && !dead) ++g_melee_rej_stumble; else if (state==MELEE_CHOP && !dead) ++g_melee_rej_chop;
            else if (dead) ++g_melee_rej_dead; else ++g_melee_rej_other;
        }
    }
    if (aim) {
        *(unsigned char *)((uintptr_t)cc+CC_WANTS_BLOCK)=1;
        if (!g_melee_block_prev) ++g_melee_blocks;
        if (state!=MELEE_CHOP && state!=MELEE_BLOCK && state!=MELEE_STUMBLE && !dead &&
            g_melee_check_block(cc,0.5f,0.5f)) ++g_melee_block_ok;
    }
    g_melee_fire_prev=fire;g_melee_block_prev=aim;
}
static int fp_melee_state_append(char *b,size_t n,const void *cc) {
    /* why=not_allowed diagnosis (4080 m09 dodge M08-CROWD: owned=0 not_allowed for 2 min with the fighter's combat
     * frozen and no KenshiFP.log): ui_open/is_down/focus are the gate's inputs (controlled actor), prone/unconscious/
     * ko_timer the read character's own medical state (-1 = no readable owner) */
    void *own=cc&&readable((const void *)((uintptr_t)cc+CC_OWNER),8)?*(void **)((uintptr_t)cc+CC_OWNER):NULL;
    if (own && !char_valid(own)) own=NULL;
    return snprintf(b,n," manual_ready=%d owned=%d why=%s armed=%d pending=%d clicks=%u swings=%u ai_refused=%u rejected=%u blocks=%u block_ok=%u autoblock_refused=%u out_of_reach=%u passive=%d passive_refused=%u approach_refused=%u chase_frames=%u chase_drops=%u chase_swings=%u force_chase=%d forced_chase=%u expired=%u last_latency_ms=%.0f max_latency_ms=%.0f hold_halts=%u spam_left=%u swing_ends=%u swing_time=%.3f last_swing_len=%.3f min_swing_gap=%.3f nat_swing_ends=%u nat_swing_time=%.3f early_starts=%u unfinished_starts=%u slack_n=%u min_swing_slack=%.3f last_reject=%s last_reject_state=%d rej_stumble=%u rej_chop=%u rej_dead=%u rej_other=%u cl_wait=%d cl_fired=%u cl_timeouts=%u cancel_refused=%u abort_refused=%u ticks=%u in_aim=%d in_fire=%d fire_masked=%u injection=%d inj_cmds=%u inj_aim_cmds=%u melee_hits=%u melee_cut=%.1f melee_blunt=%.1f wounds_any=%u ui_open=%d is_down=%d focus=%d prone=%d unconscious=%d ko_timer=%.1f head_above=%.2f",
        g_melee_ready,cc!=NULL&&cc==g_melee_owned_cc,g_melee_why,g_melee_armed,g_melee_pending,g_melee_clicks,
        g_melee_swings,g_melee_ai_refused,g_melee_rejected,g_melee_blocks,g_melee_block_ok,g_melee_autoblock_refused,g_melee_out_of_reach,g_melee_passive_serial!=0,g_melee_passive_refused,
        g_melee_approach_refused,g_melee_chase_frames,g_melee_chase_drops,g_melee_chase_swings,g_melee_force_chase,g_melee_forced_chase,g_melee_expired,g_melee_last_latency_ms,g_melee_max_latency_ms,
        g_melee_hold_halts,g_melee_spam_left,g_melee_swing_ends,g_melee_swing_time,g_melee_last_swing_len,g_melee_min_swing_gap,g_melee_nat_swing_ends,g_melee_nat_swing_time,
        g_melee_early_starts,g_melee_unfinished_starts,g_melee_slack_n,g_melee_min_swing_slack,g_melee_last_reject,g_melee_last_reject_state,
        g_melee_rej_stumble,g_melee_rej_chop,g_melee_rej_dead,g_melee_rej_other,g_melee_cl_wait,g_melee_cl_fired,g_melee_cl_timeouts,g_melee_cancel_refused,g_melee_abort_refused,
        g_melee_ticks,g_melee_in_aim,g_melee_in_fire,g_melee_fire_masked,g_combat_injection,g_combat_inj_cmds,g_combat_inj_aim_cmds,
        g_wound_melee_hits,g_wound_melee_cut,g_wound_melee_blunt,g_wound_any,
        g_ui_open,g_is_down,game_has_focus(),own?char_prone_state(own):-1,own?combat_char_unconscious(own):-1,own?combat_char_ko_timer(own):-1.0f,g_head_above);
}
static void fp_melee_manual_init(void) {
    uintptr_t init=combat_unique_signature("40 57 48 83 EC 40 48 8B 41 08 48 8B F9");
    uintptr_t needblk=combat_unique_signature("40 53 48 83 EC 40 48 8B D9 48 8B 89 88 01 00 00");
    g_melee_check_block=(melee_check_block_t)needblk;
    uintptr_t block=combat_unique_signature("48 8B C4 55 41 54 41 55 41 56 41 57 48 8D 68 A1 48 81 EC C0 00 00 00 48 C7 45 E7 FE FF FF");
    g_melee_init_attack=(melee_init_attack_t)combat_unique_signature("40 56 57 48 81 EC B8 00 00 00 0F 29 B4 24 A0 00 00");
    /* CharMovement combat mover (RVA 0x2AE8C0): the single approach entry of all combat states. */
    uintptr_t approach=combat_unique_signature("48 89 5C 24 08 57 48 83 EC 60 48 8B FA 0F 29 74 24 50 BA 01 00 00 00");
    /* base CombatClass attack state (RVA 0x609B00): swing cancel-into-block refusal while RMB is up */
    uintptr_t astate=combat_unique_signature("40 53 56 48 81 EC 98 00 00 00 48 8B D9 48 8B 89 80 01 00 00");
    if (init && block && approach && astate && g_melee_init_attack && g_melee_check_block && g_melee_get_combat)
        g_melee_ready=install_hook((void *)init,(void *)melee_attack_init_hook,(void **)&g_melee_attack_init_orig) &&
                      install_hook((void *)block,(void *)melee_init_block_hook,(void **)&g_melee_init_block_orig) &&
                      install_hook((void *)approach,(void *)melee_approach_hook,(void **)&g_melee_approach_orig) &&
                      install_hook((void *)astate,(void *)melee_attack_state_hook,(void **)&g_melee_attack_state_orig) &&
                      install_hook((void *)needblk,(void *)melee_need_block_hook,(void **)&g_melee_need_block_orig);
    if (g_melee_ready) g_melee_check_block=g_melee_need_block_orig;   /* our RMB block check calls the native directly */
    logline("[melee] manual adapter attack_init=%p init_attack=%p init_block=%p check_block=%p approach=%p attack_state=%p ready=%d; manual default OFF",
        (void *)init,(void *)g_melee_init_attack,(void *)block,(void *)g_melee_check_block,(void *)approach,(void *)astate,g_melee_ready);
}
