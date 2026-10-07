/* Offline checks of the manual melee adapter logic (client/kfp_combat_melee.inc): AI initiative refusal,
 * click buffer with retry and out_of_reach/expired accounting, click->swing latency, combat approach
 * refusal only for the owned fighter's movement (M06), re-arm after an interruption (M08), RMB-only
 * block and the passive test switch. Native layout/runtime are not validated here. */
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
static double fake_ms;
#define KFP_MELEE_NOW_MS() (fake_ms)
#define GW_FRAMESPEED 0x10
static unsigned char pc[16],cc[0x2c0],gw[0x20],mv[0x400],other_mv[0x400],st[0x20],ecc[0x2c0],est[0x20],stats[0x200],techa[0x40],techb[0x40];
static void *mv_vt[0x20];
static int g_ui_open,g_is_down,g_combat_injection=1,focus=1;
static unsigned g_combat_inj_cmds,g_combat_inj_aim_cmds;
static int game_has_focus(void){return focus;}
static void logline(const char *fmt,...){(void)fmt;}
static int in(void *p,size_t n,void *b,size_t bn){return (unsigned char *)p>=(unsigned char *)b&&(unsigned char *)p+n<=(unsigned char *)b+bn;}
static int readable(void *p,size_t n){
    return in(p,n,cc,sizeof(cc))||in(p,n,gw,sizeof(gw))||in(p,n,mv,sizeof(mv))||in(p,n,other_mv,sizeof(other_mv))||
           in(p,n,st,sizeof(st))||in(p,n,mv_vt,sizeof(mv_vt))||in(p,n,ecc,sizeof(ecc))||in(p,n,est,sizeof(est))||
           in(p,n,stats,sizeof(stats))||in(p,n,techa,sizeof(techa))||in(p,n,techb,sizeof(techb));
}
static void *get_combat(void *p){assert(p==pc);return cc;}
static void *(*g_melee_get_combat)(void *)=get_combat;
/* fake natives */
static int orig_attack_calls,orig_block_calls,init_attack_ok,init_attack_calls,approach_calls,stop_calls,check_block_ok;
static void *approach_last_mv;
static char fake_attack_init(void *s){(void)s;++orig_attack_calls;return 1;}
static char fake_check_block(void *c,float a,float b){(void)c;(void)a;(void)b;return (char)check_block_ok;}
static char fake_init_block(void *c,char stumbling){(void)c;(void)stumbling;++orig_block_calls;return 1;}
static char fake_init_attack(void *s,void *t){(void)s;(void)t;++init_attack_calls;return (char)init_attack_ok;}
static void fake_approach(void *m,void *pos,float a,float b,float c,char d,float e){(void)pos;(void)a;(void)b;(void)c;(void)d;(void)e;++approach_calls;approach_last_mv=m;}
static void fake_stop(void *m){assert(m==mv);++stop_calls;}
static int astate_calls,astate_saw_wants;
static char fake_attack_state(void *c){++astate_calls;astate_saw_wants=((unsigned char *)c)[0x120];return 1;}
static uintptr_t combat_unique_signature(const char *sig){
    if (!strcmp(sig,"40 57 48 83 EC 40 48 8B 41 08 48 8B F9")) return (uintptr_t)fake_attack_init;
    if (!strcmp(sig,"40 53 48 83 EC 40 48 8B D9 48 8B 89 88 01 00 00")) return (uintptr_t)fake_check_block;
    if (!strncmp(sig,"48 8B C4 55 41 54",17)) return (uintptr_t)fake_init_block;
    if (!strcmp(sig,"40 56 57 48 81 EC B8 00 00 00 0F 29 B4 24 A0 00 00")) return (uintptr_t)fake_init_attack;
    if (!strcmp(sig,"48 89 5C 24 08 57 48 83 EC 60 48 8B FA 0F 29 74 24 50 BA 01 00 00 00")) return (uintptr_t)fake_approach;
    if (!strcmp(sig,"40 53 56 48 81 EC 98 00 00 00 48 8B D9 48 8B 89 80 01 00 00")) return (uintptr_t)fake_attack_state;
    assert(!"unexpected signature");return 0;
}
static int hooks;
#include <setjmp.h>
static jmp_buf g_guard_jb;static int g_guard_armed,g_fp_mode=1;
static void guard_arm(void){g_guard_armed=1;}
static int char_valid(void *p){return p==pc;}
static void *fp_controlled_char(void *g){(void)g;return pc;}
static int install_hook(void *target,void *detour,void **orig){(void)detour;*orig=target;++hooks;return 1;}
#include "../client/kfp_combat_melee.inc"

static void put_ptr(void *b,size_t off,void *v){memcpy((unsigned char *)b+off,&v,sizeof(v));}
static void put_int(size_t off,int v){memcpy(cc+off,&v,sizeof(v));}
static int get_int(size_t off){int v;memcpy(&v,cc+off,sizeof(v));return v;}
static void tick(int aim,int fire,float dt){fp_melee_manual_tick(gw,pc,aim,fire,dt);}
static char ai_init(void){return melee_attack_init_hook(st);}
static void approach(void *m){melee_approach_hook(m,NULL,0,0,0,0,0);}
static void reset_fight(void){put_int(CC_STATE,MELEE_DECISION);put_int(CC_NEXTMOVE,MELEE_WAIT);cc[CC_ACTIVE]=1;cc[CC_DEADTIME]=0;}
int main(void){
    float one=1.0f;memcpy(gw+GW_FRAMESPEED,&one,4);
    put_ptr(cc,CC_OWNER,pc);put_ptr(cc,CC_MOVEMENT,mv);put_ptr(st,8,cc);put_ptr(mv,0,mv_vt);
    mv_vt[0x98/8]=(void *)fake_stop;
    unsigned serial=1128173824u;memcpy(cc+CC_TARGET_H+0x18,&serial,4);
    reset_fight();
    /* unready before init */
    tick(0,0,.016f);assert(!strcmp(g_melee_why,"unready"));
    fp_melee_manual_init();assert(g_melee_ready&&hooks==5&&g_melee_check_block==fake_check_block);
    /* not owned: approach and AI init stay native */
    approach(mv);assert(approach_calls==1&&approach_last_mv==mv);
    assert(ai_init()==1&&orig_attack_calls==1);
    /* ownership: stop once, approach on the owned movement refused, other movement native */
    tick(0,0,.016f);assert(g_melee_owned_cc==cc&&stop_calls==1&&!strcmp(g_melee_why,"arming"));
    tick(0,0,.016f);assert(g_melee_armed&&!strcmp(g_melee_why,"ok")&&stop_calls==1);
    approach(mv);assert(approach_calls==1&&g_melee_approach_refused==1);
    approach(other_mv);assert(approach_calls==2&&approach_last_mv==other_mv);
    /* M00: AI initiative refused, parked in WAIT */
    put_int(CC_NEXTMOVE,MELEE_CHOP);assert(ai_init()==0&&g_melee_ai_refused==1&&get_int(CC_NEXTMOVE)==MELEE_WAIT&&orig_attack_calls==1);
    /* M01: click -> CHOP/STARTUP; first attack init fails (retry kept pending), second succeeds; latency in real ms */
    fake_ms=1000;tick(0,1,.016f);assert(g_melee_clicks==1&&g_melee_pending&&get_int(CC_STATE)==MELEE_STARTUP&&get_int(CC_NEXTMOVE)==MELEE_CHOP);
    init_attack_ok=0;assert(ai_init()==0&&g_melee_pending&&g_melee_pending_failed&&g_melee_out_of_reach==0&&g_melee_ai_refused==1);
    tick(0,1,.016f);assert(g_melee_clicks==1);           /* held: no new edge */
    init_attack_ok=1;fake_ms=1120;assert(ai_init()==1&&g_melee_swings==1&&!g_melee_pending&&stop_calls==2);
    assert(fabs(g_melee_last_latency_ms-120)<1e-6&&fabs(g_melee_max_latency_ms-120)<1e-6);
    assert(ai_init()==0&&g_melee_ai_refused==2);        /* one click = one swing */
    tick(0,0,.016f);
    /* M06: out-of-reach click retried until the 0.25 s buffer expires -> out_of_reach once, no swing */
    reset_fight();tick(0,1,.016f);assert(g_melee_pending&&g_melee_clicks==2);
    init_attack_ok=0;assert(ai_init()==0);assert(ai_init()==0);assert(init_attack_calls==4);
    tick(0,0,.1f);assert(g_melee_pending);tick(0,0,.2f);assert(!g_melee_pending&&g_melee_out_of_reach==1&&g_melee_swings==1&&g_melee_expired==0);
    assert(ai_init()==0&&g_melee_ai_refused==3);
    /* click whose attack init never runs (native changed state) -> expired, not silent */
    reset_fight();tick(0,1,.016f);tick(0,0,.3f);assert(!g_melee_pending&&g_melee_expired==1&&g_melee_out_of_reach==1);
    /* M02: illegal states and dead time reject, spam during pending rejected */
    put_int(CC_STATE,MELEE_STUMBLE);tick(0,1,.016f);tick(0,0,.016f);assert(g_melee_rejected==1&&!g_melee_pending);
    reset_fight();cc[CC_DEADTIME]=1;tick(0,1,.016f);tick(0,0,.016f);assert(g_melee_rejected==2);
    reset_fight();tick(0,1,.016f);tick(0,0,.016f);tick(0,1,.016f);assert(g_melee_rejected==3&&g_melee_pending);
    tick(0,0,.3f);assert(!g_melee_pending&&g_melee_expired==2);
    /* M03: RMB only block; no click while RMB held; AI auto-block refused with RMB up, stumble native */
    reset_fight();assert(melee_init_block_hook(cc,0)==0&&g_melee_autoblock_refused==1&&orig_block_calls==0);
    assert(melee_init_block_hook(cc,1)==1&&orig_block_calls==1);
    check_block_ok=1;tick(1,0,.016f);assert(cc[CC_WANTS_BLOCK]==1&&g_melee_blocks==1&&g_melee_block_ok==1);
    assert(melee_init_block_hook(cc,0)==1&&orig_block_calls==2);
    tick(1,1,.016f);assert(g_melee_clicks==7&&!g_melee_pending);   /* fire edge with RMB held is not a click */
    tick(0,0,.016f);
    /* chase states counted (diagnostic) */
    put_int(CC_STATE,11);tick(0,0,.016f);assert(g_melee_chase_frames==1);reset_fight();
    /* M09 GreatAnims: an owned fighter left in native chase (10/11) is dropped back to WAIT, so the next click is legal
     * (was: rejected "state" forever, the chase can't finish while owned). A pending click means the native startup was
     * trace-blocked into the chase before it could run the click's attack init (4080 m09: STARTUP -> 10 -> drop looped
     * until every click expired, swings 0): the drop starts the click's swing itself (CHOP); with no technique in reach
     * it goes back to STARTUP and expires as out_of_reach. */
    {unsigned r0=g_melee_rejected,c0=g_melee_clicks,f0=g_melee_chase_frames,o0=g_melee_out_of_reach,x0=g_melee_expired,s0=g_melee_swings;
     int sc0=stop_calls,iok=init_attack_ok;
     unsigned se0=g_melee_swing_ends,sn0=g_melee_slack_n,es0=g_melee_early_starts,us0=g_melee_unfinished_starts;
     double ss0=g_melee_swing_start_s,st0=g_melee_swing_time,ll0=g_melee_last_swing_len,mg0=g_melee_min_swing_gap,ms0=g_melee_min_swing_slack,lt0=g_melee_last_latency_ms,mx0=g_melee_max_latency_ms;
     int is0=g_melee_in_swing;
     put_int(CC_STATE,11);put_int(CC_NEXTMOVE,10);tick(0,0,.016f);
     assert(get_int(CC_STATE)==MELEE_WAIT&&get_int(CC_NEXTMOVE)==MELEE_WAIT&&g_melee_chase_drops==2&&g_melee_chase_frames==f0+1&&g_melee_chase_swings==0);
     put_int(CC_STATE,10);tick(0,1,.016f);assert(g_melee_clicks==c0+1&&g_melee_rejected==r0&&g_melee_pending&&get_int(CC_STATE)==MELEE_STARTUP);
     /* no technique in reach: STARTUP, retried, expires as out_of_reach */
     init_attack_ok=0;put_int(CC_STATE,11);put_int(CC_NEXTMOVE,10);tick(0,0,.016f);
     assert(get_int(CC_STATE)==MELEE_STARTUP&&g_melee_pending&&g_melee_pending_failed&&get_int(CC_NEXTMOVE)==MELEE_CHOP&&g_melee_chase_swings==0);
     tick(0,0,.3f);assert(!g_melee_pending&&g_melee_out_of_reach==o0+1&&g_melee_expired==x0);
     /* in reach: the drop starts the swing (state = nextMove = CHOP, movement stop, one swing) */
     reset_fight();tick(0,1,.016f);assert(g_melee_pending);
     init_attack_ok=1;put_int(CC_STATE,11);put_int(CC_NEXTMOVE,10);tick(0,0,.016f);
     assert(get_int(CC_STATE)==MELEE_CHOP&&get_int(CC_NEXTMOVE)==MELEE_CHOP&&!g_melee_pending&&g_melee_swings==s0+1&&g_melee_chase_swings==1&&stop_calls==sc0+1);
     /* AttackState of another CombatClass is never used: fallback STARTUP, expires */
     {void *keep=g_melee_owned_st;g_melee_owned_st=est;reset_fight();tick(0,0,.016f);tick(0,1,.016f);put_int(CC_STATE,11);tick(0,0,.016f);
      assert(get_int(CC_STATE)==MELEE_STARTUP&&g_melee_pending&&g_melee_chase_swings==1);tick(0,0,.3f);assert(g_melee_expired==x0+1);g_melee_owned_st=keep;}
     /* M09-CHASE test switch: the lock (state 11, nextMove 10) is forced BEFORE the tick reads the state (b29: forced at the
      * end, the native update left 11 before the next tick, chase_drops 0->0) and right after an accepted click, so the
      * real drop branch runs and the click's swing starts from it; a click the drop could not start (STARTUP, pending) is
      * started on a later tick; CHOP and dead time are never forced */
     {unsigned fc0=g_melee_forced_chase,d0=g_melee_chase_drops;
      reset_fight();tick(0,0,.016f);fp_melee_set_force_chase(1);tick(0,0,.016f);
      assert(get_int(CC_STATE)==MELEE_WAIT&&get_int(CC_NEXTMOVE)==MELEE_WAIT&&g_melee_forced_chase==fc0+1&&g_melee_chase_drops==d0+1);
      tick(0,1,.016f);
      assert(get_int(CC_STATE)==MELEE_CHOP&&!g_melee_pending&&g_melee_chase_swings==2&&g_melee_forced_chase==fc0+3&&g_melee_chase_drops==d0+3);
      tick(0,0,.016f);assert(get_int(CC_STATE)==MELEE_CHOP&&g_melee_forced_chase==fc0+3);   /* CHOP never forced */
      reset_fight();tick(0,0,.016f);init_attack_ok=0;tick(0,1,.016f);
      assert(g_melee_pending&&get_int(CC_STATE)==MELEE_STARTUP&&g_melee_chase_swings==2);
      init_attack_ok=1;tick(0,0,.016f);assert(get_int(CC_STATE)==MELEE_CHOP&&g_melee_chase_swings==3);
      reset_fight();cc[CC_DEADTIME]=1;tick(0,0,.016f);assert(get_int(CC_STATE)==MELEE_DECISION);
      {char fb[2048];fp_melee_state_append(fb,sizeof(fb),cc);assert(strstr(fb," chase_swings=3 force_chase=1 forced_chase="));}
      fp_melee_set_force_chase(0);reset_fight();tick(0,0,.016f);assert(get_int(CC_STATE)==MELEE_DECISION);}
     g_melee_expired=2;g_melee_clicks=c0;g_melee_chase_frames=f0;g_melee_chase_drops=4;g_melee_out_of_reach=o0;g_melee_swings=s0;stop_calls=sc0;
     g_melee_rejected=r0;g_melee_chase_swings=0;init_attack_ok=iok;
     g_melee_swing_ends=se0;g_melee_slack_n=sn0;g_melee_early_starts=es0;g_melee_unfinished_starts=us0;g_melee_swing_start_s=ss0;g_melee_swing_time=st0;
     g_melee_last_swing_len=ll0;g_melee_min_swing_gap=mg0;g_melee_min_swing_slack=ms0;g_melee_last_latency_ms=lt0;g_melee_max_latency_ms=mx0;g_melee_in_swing=is0;
     reset_fight();}
    /* M08: UI open releases (native approach again), held LMB through close never swings, release re-arms, fresh click swings */
    g_ui_open=1;tick(0,1,.016f);assert(!g_melee_owned_cc&&!strcmp(g_melee_why,"not_allowed"));
    approach(mv);assert(approach_calls==3);
    g_ui_open=0;tick(0,1,.016f);assert(g_melee_owned_cc==cc&&!g_melee_armed&&!strcmp(g_melee_why,"arming")&&stop_calls==3);
    tick(0,1,.016f);assert(!g_melee_armed&&g_melee_clicks==7);
    approach(mv);assert(approach_calls==3);              /* refused while arming too: owned */
    tick(0,0,.016f);assert(g_melee_armed);tick(0,0,.016f);assert(!strcmp(g_melee_why,"ok"));
    init_attack_ok=1;fake_ms=5000;tick(0,1,.016f);fake_ms=5016;assert(ai_init()==1&&g_melee_swings==2&&fabs(g_melee_last_latency_ms-16)<1e-6);
    tick(0,0,.016f);
    /* KO releases with a pending click -> accounted as expired */
    reset_fight();tick(0,1,.016f);assert(g_melee_pending);g_is_down=1;tick(0,1,.016f);assert(!g_melee_owned_cc&&g_melee_expired==3);g_is_down=0;
    /* paused keeps ownership, drops the click */
    tick(0,0,.016f);tick(0,0,.016f);reset_fight();tick(0,1,.016f);assert(g_melee_pending);
    float zero=0;memcpy(gw+GW_FRAMESPEED,&zero,4);tick(0,1,.016f);assert(g_melee_owned_cc==cc&&!g_melee_pending&&g_melee_expired==4&&!strcmp(g_melee_why,"paused"));
    memcpy(gw+GW_FRAMESPEED,&one,4);tick(0,0,.016f);
    /* passive switch: AI attacks aimed at that serial refused, owned fighter unaffected by it */
    put_ptr(est,8,ecc);unsigned ps=2740478464u;memcpy(ecc+CC_TARGET_H+0x18,&ps,4);
    fp_melee_set_passive(ps);
    /* readable() must also cover the enemy combat object for the passive check */
    {int o=orig_attack_calls;memcpy(ecc+CC_NEXTMOVE,&(int){MELEE_CHOP},4);
     assert(melee_attack_init_hook(est)==0&&orig_attack_calls==o&&g_melee_passive_refused==1);
     int nm;memcpy(&nm,ecc+CC_NEXTMOVE,4);assert(nm==MELEE_WAIT);
     fp_melee_set_passive(0);assert(melee_attack_init_hook(est)==1&&orig_attack_calls==o+1);}
    /* state line carries the new evidence fields */
    char b[1024],fb[1024];fp_melee_state_append(b,sizeof(b),cc);
    assert(strstr(b," approach_refused=2 ")&&strstr(b," chase_frames=1 chase_drops=4 ")&&strstr(b," expired=4 ")&&strstr(b," last_latency_ms=16 ")&&strstr(b," max_latency_ms=120"));
    assert(strstr(b," out_of_reach=1 ")&&strstr(b," swings=2 "));
    /* M06 hold ground: while owned and not driven, combat locomotion (mode 1) or a chase state is halted before the
     * movement update; player direct drive (mode 2), anim-driven motion, CHOP/STUMBLE and other movers stay native */
    {int mode=1,s0=stop_calls;memcpy(mv+MV_COMBAT_MODE,&mode,4);mv[MV_ANIM_OVERRIDE]=0;reset_fight();
     fp_melee_hold_ground(mv);assert(stop_calls==s0+1&&g_melee_hold_halts==1);
     fp_melee_hold_ground(other_mv);assert(stop_calls==s0+1);
     mode=2;memcpy(mv+MV_COMBAT_MODE,&mode,4);fp_melee_hold_ground(mv);assert(stop_calls==s0+1);
     mode=0;memcpy(mv+MV_COMBAT_MODE,&mode,4);fp_melee_hold_ground(mv);assert(stop_calls==s0+1);
     put_int(CC_STATE,10);fp_melee_hold_ground(mv);assert(stop_calls==s0+2);           /* pathfind chase */
     mode=1;memcpy(mv+MV_COMBAT_MODE,&mode,4);
     put_int(CC_STATE,MELEE_CHOP);fp_melee_hold_ground(mv);put_int(CC_STATE,MELEE_STUMBLE);fp_melee_hold_ground(mv);
     assert(stop_calls==s0+2);
     reset_fight();mv[MV_ANIM_OVERRIDE]=1;fp_melee_hold_ground(mv);assert(stop_calls==s0+2);mv[MV_ANIM_OVERRIDE]=0;
     assert(g_melee_hold_halts==2);}
    /* M02 spam switch: n clicks on the game thread at a fixed real-time period through the normal click path; a
     * click during the native swing (CHOP) or its dead time is rejected; swing length and gap are game time */
    {unsigned c0=g_melee_clicks,s0=g_melee_swings,j0=g_melee_rejected,e0=g_melee_swing_ends;
     init_attack_ok=1;reset_fight();fake_ms=10000;fp_melee_spam_start(5,200);assert(g_melee_min_swing_gap<0);
     int swung=0;
     for (int f=0;f<80;++f) {                         /* 80 frames x 20 ms = 1.6 s real = game time (speed 1) */
         tick(0,0,.02f);
         if (g_melee_pending && !swung) {assert(ai_init()==1);put_int(CC_STATE,MELEE_CHOP);swung=1;}
         if (swung==1 && g_melee_game_s-g_melee_swing_start_s>=0.5) {put_int(CC_STATE,MELEE_DECISION);swung=0;}
         fake_ms+=20;
     }
     assert(g_melee_clicks-c0==5&&g_melee_spam_left==0&&!g_melee_spam_pressed);
     assert(g_melee_swings-s0==2&&g_melee_rejected-j0==3);
     assert(g_melee_swing_ends-e0==2&&fabs(g_melee_last_swing_len-0.5)<0.05);
     assert(g_melee_min_swing_gap>=0.5&&g_melee_min_swing_gap<1.2);
     /* per-pair check: the second swing started after the first left CHOP -> one slack sample >= 0, no early start */
     assert(g_melee_slack_n==1&&g_melee_early_starts==0&&g_melee_min_swing_slack>=-1e-9&&g_melee_min_swing_slack<0.7);
     tick(0,0,.02f);assert(melee_spam_fire()==-1);     /* finished: real input again */
     fp_melee_spam_start(3,200);fp_melee_set_spam(0,0);assert(melee_spam_fire()==-1);
     fb[0]=0;fp_melee_state_append(fb,sizeof(fb),cc);assert(strstr(fb," hold_halts=2 ")&&strstr(fb," spam_left=0 ")&&strstr(fb," last_swing_len=0.5"));}
    /* native swing timer: CHOP spans in game time (frame dt x speed), any owner; paused frames add nothing;
     * FP off resets an open span */
    {unsigned e0=g_melee_nat_swing_ends;double t0=g_melee_nat_swing_time;float two=2.0f,zero=0.0f;
     memcpy(gw+GW_FRAMESPEED,&two,4);put_int(CC_STATE,MELEE_DECISION);fp_melee_observe_swing(gw,.1f);
     put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<4;++f) fp_melee_observe_swing(gw,.1f);    /* starts on frame 1 */
     memcpy(gw+GW_FRAMESPEED,&zero,4);fp_melee_observe_swing(gw,.1f);                      /* paused */
     memcpy(gw+GW_FRAMESPEED,&two,4);put_int(CC_STATE,MELEE_DECISION);fp_melee_observe_swing(gw,.1f);
     assert(g_melee_nat_swing_ends==e0+1&&fabs(g_melee_nat_swing_time-t0-0.8)<1e-6&&!g_guard_armed);
     put_int(CC_STATE,MELEE_CHOP);fp_melee_observe_swing(gw,.1f);g_fp_mode=0;fp_melee_observe_swing(gw,.1f);g_fp_mode=1;
     put_int(CC_STATE,MELEE_DECISION);fp_melee_observe_swing(gw,.1f);assert(g_melee_nat_swing_ends==e0+1);
     memcpy(gw+GW_FRAMESPEED,&one,4);
     fb[0]=0;fp_melee_state_append(fb,sizeof(fb),cc);assert(strstr(fb," nat_swing_ends=")&&strstr(fb," nat_swing_time=0.800"));}
    /* click reject reasons + click_legal test switch (M08-CROWD): stumble frames reject with a reason; click_legal
     * waits for the first legal frame, presses once, releases next frame; times out if no legal frame comes */
    {reset_fight();tick(0,0,.02f);unsigned j0=g_melee_rejected,rs0=g_melee_rej_stumble;
     put_int(CC_STATE,MELEE_STUMBLE);tick(0,1,.02f);tick(0,0,.02f);
     assert(g_melee_rejected==j0+1&&g_melee_rej_stumble==rs0+1&&!strcmp(g_melee_last_reject,"stumble")&&g_melee_last_reject_state==MELEE_STUMBLE);
     put_int(CC_STATE,MELEE_CHOP);tick(0,1,.02f);tick(0,0,.02f);assert(!strcmp(g_melee_last_reject,"chop")&&g_melee_rej_chop>=1);
     cc[CC_DEADTIME]=1;put_int(CC_STATE,MELEE_DECISION);tick(0,1,.02f);tick(0,0,.02f);assert(!strcmp(g_melee_last_reject,"dead_time"));cc[CC_DEADTIME]=0;
     unsigned c1=g_melee_clicks,s0=g_melee_swings;fake_ms=20000;
     put_int(CC_STATE,MELEE_STUMBLE);fp_melee_click_legal_start(1000);
     for (int f=0;f<5;++f) {tick(0,0,.02f);fake_ms+=20;}
     assert(g_melee_clicks==c1&&g_melee_cl_wait&&!g_melee_cl_fired);           /* stumble-locked: waits */
     put_int(CC_STATE,MELEE_CIRCLE);tick(0,0,.02f);fake_ms+=20;
     assert(g_melee_clicks==c1+1&&g_melee_cl_fired==1&&!g_melee_cl_wait&&g_melee_pending&&get_int(CC_STATE)==MELEE_STARTUP);
     init_attack_ok=1;assert(ai_init()==1&&g_melee_swings==s0+1);
     tick(0,0,.02f);assert(!g_melee_cl_release&&!g_melee_fire_prev&&g_melee_clicks==c1+1);   /* released, one click */
     put_int(CC_STATE,MELEE_STUMBLE);fp_melee_click_legal_start(100);
     for (int f=0;f<10;++f) {tick(0,0,.02f);fake_ms+=20;}
     assert(g_melee_cl_timeouts==1&&!g_melee_cl_wait&&g_melee_clicks==c1+1);
     fb[0]=0;fp_melee_state_append(fb,sizeof(fb),cc);
     assert(strstr(fb," cl_fired=1 ")&&strstr(fb," cl_timeouts=1")&&strstr(fb," last_reject=")&&strstr(fb," rej_stumble="));}
    /* unfinished_starts (diagnostic): the previous technique (not a block, not cut by a stumble) flagged unfinished */
    {reset_fight();tick(0,0,.02f);put_ptr(cc,CC_TECH,techa);techa[TECH_IS_BLOCK]=0;cc[CC_TECH_DONE]=0;
     g_melee_last_exit_state=MELEE_DECISION;unsigned e0=g_melee_early_starts;
     unsigned u0=g_melee_unfinished_starts;
     tick(0,1,.02f);init_attack_ok=1;assert(ai_init()==1&&g_melee_early_starts==e0&&g_melee_unfinished_starts==u0+1);tick(0,0,.02f);
     put_int(CC_STATE,MELEE_DECISION);tick(0,0,.02f);cc[CC_TECH_DONE]=1;g_melee_last_exit_state=MELEE_DECISION;
     tick(0,1,.02f);assert(ai_init()==1&&g_melee_early_starts==e0&&g_melee_unfinished_starts==u0+1);tick(0,0,.02f);put_int(CC_STATE,MELEE_DECISION);tick(0,0,.02f);
     /* a start while the previous swing is still in CHOP (end never seen) is an early start */
     g_melee_pending=1;put_int(CC_STATE,MELEE_CHOP);g_melee_in_swing=1;assert(ai_init()==1&&g_melee_early_starts==e0+1);
     put_int(CC_STATE,MELEE_DECISION);tick(0,0,.02f);}
    /* swingstat (M04-SPEED): attackSpeed applied at each CHOP start (CharStats+0x188 x technique anim speed),
     * completed CHOP time per technique, stumble-cut spans apart */
    {float spd=1.5f,anim=0.8f,spd2=2.0f;memcpy(stats+STATS_ATTACK_SPEED,&spd,4);memcpy(techa+TECH_ANIM_SPEED,&anim,4);memcpy(techb+TECH_ANIM_SPEED,&anim,4);
     put_ptr(cc,CC_STATS,stats);fp_melee_swingstat_reset();
     put_ptr(cc,CC_TECH,techa);put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<4;++f) fp_melee_observe_swing(gw,.1f);
     cc[CC_DEADTIME]=1;fp_melee_observe_swing(gw,.1f);                                   /* natural end: dead time set in CHOP */
     put_int(CC_STATE,MELEE_WAIT);fp_melee_observe_swing(gw,.1f);cc[CC_DEADTIME]=0;
     memcpy(stats+STATS_ATTACK_SPEED,&spd2,4);put_ptr(cc,CC_TECH,techb);put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<3;++f) fp_melee_observe_swing(gw,.1f);
     put_int(CC_STATE,MELEE_STUMBLE);fp_melee_observe_swing(gw,.1f);                    /* cut: not a technique time */
     put_ptr(cc,CC_TECH,techa);put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<3;++f) fp_melee_observe_swing(gw,.1f);
     cc[CC_DEADTIME]=1;fp_melee_observe_swing(gw,.1f);cc[CC_DEADTIME]=0;                  /* dead time set while still in CHOP */
     put_int(CC_STATE,MELEE_WAIT);fp_melee_observe_swing(gw,.1f);
     assert(g_melee_spd_n==3&&fabs(g_melee_spd_sum-5.5)<1e-6&&fabs(g_melee_spd_last-2.0f)<1e-6&&fabs(g_melee_anim_spd_last-1.6f)<1e-5);
     assert(g_melee_nat_cut==1&&g_melee_techs[0].tech==techa&&g_melee_techs[0].n==2&&fabs(g_melee_techs[0].t-0.9)<1e-6&&!g_melee_techs[1].tech);
     char sb[768];fp_melee_swingstat_append(sb,sizeof(sb));
     assert(strstr(sb,"atk_speed_mean=1.8333 atk_speed_n=3 ")&&strstr(sb," nat_cut=1 nat_cancel=0 ")&&strstr(sb,":2:0.900"));
     /* cancelled at the cancel point (CHOP -> DECISION, no dead time): counted apart, not a technique time */
     put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<2;++f) fp_melee_observe_swing(gw,.1f);
     put_int(CC_STATE,MELEE_DECISION);fp_melee_observe_swing(gw,.1f);
     assert(g_melee_nat_cancel==1&&g_melee_nat_cut==1&&g_melee_techs[0].n==2&&!g_melee_techs[1].tech);
     fp_melee_swingstat_append(sb,sizeof(sb));assert(strstr(sb," nat_cut=1 nat_cancel=1 "));
     /* combat reset (DECISION + dead time in the same call, batch 17): dead time only at the exit sample is not a natural end */
     put_int(CC_STATE,MELEE_CHOP);for (int f=0;f<6;++f) fp_melee_observe_swing(gw,.1f);
     cc[CC_DEADTIME]=1;put_int(CC_STATE,MELEE_DECISION);fp_melee_observe_swing(gw,.1f);cc[CC_DEADTIME]=0;
     assert(g_melee_nat_cancel==2&&g_melee_techs[0].n==2&&!g_melee_techs[1].tech);
     fp_melee_swingstat_reset();fp_melee_swingstat_append(sb,sizeof(sb));assert(strstr(sb,"atk_speed_n=0 ")&&strstr(sb," nat_cancel=0 ")&&strstr(sb,"techs=none"));
     put_ptr(cc,CC_TECH,NULL);put_ptr(cc,CC_STATS,NULL);}
    /* swing cancel-into-block refused for the owned fighter while RMB is up (M04-SPEED, batch 16) */
    {void *own=g_melee_owned_cc;int rmb=g_melee_rmb;g_melee_owned_cc=cc;g_melee_rmb=0;g_melee_cancel_noted=0;unsigned r0=g_melee_cancel_refused;
     cc[CC_WANTS_BLOCK]=1;assert(melee_attack_state_hook(cc)==1&&astate_calls==1&&astate_saw_wants==0&&!cc[CC_WANTS_BLOCK]&&g_melee_cancel_refused==r0+1);
     cc[CC_WANTS_BLOCK]=1;melee_attack_state_hook(cc);assert(astate_saw_wants==0&&g_melee_cancel_refused==r0+1);   /* once per swing */
     g_melee_rmb=1;cc[CC_WANTS_BLOCK]=1;melee_attack_state_hook(cc);assert(astate_saw_wants==1&&cc[CC_WANTS_BLOCK]==1);   /* RMB: native cancel into block */
     g_melee_rmb=0;ecc[0x120]=1;melee_attack_state_hook(ecc);assert(astate_saw_wants==1&&ecc[0x120]==1);   /* other fighters untouched */
     cc[CC_WANTS_BLOCK]=0;ecc[0x120]=0;astate_calls=0;char fb2[2048];fp_melee_state_append(fb2,sizeof(fb2),cc);
     assert(strstr(fb2," cancel_refused="));g_melee_owned_cc=own;g_melee_rmb=rmb;}
    /* checkForNeedBlock refused for the owned fighter while RMB is up (swing abort into a refused block, batch 17) */
    {void *own=g_melee_owned_cc;int rmb=g_melee_rmb;g_melee_owned_cc=cc;g_melee_rmb=0;g_melee_abort_noted=0;unsigned a0=g_melee_abort_refused;
     unsigned one=1,zero=0;check_block_ok=1;put_int(CC_STATE,MELEE_CHOP);memcpy(cc+0x228,&one,4);
     assert(melee_need_block_hook(cc,.5f,.5f)==0&&g_melee_abort_refused==a0+1);
     assert(melee_need_block_hook(cc,.5f,.5f)==0&&g_melee_abort_refused==a0+1);                 /* once per swing */
     g_melee_rmb=1;assert(melee_need_block_hook(cc,.5f,.5f)==1);                                 /* RMB: native check */
     g_melee_rmb=0;assert(melee_need_block_hook(ecc,.5f,.5f)==1);                                /* other fighters untouched */
     memcpy(cc+0x228,&zero,4);check_block_ok=0;put_int(CC_STATE,MELEE_DECISION);
     char fb3[2048];fp_melee_state_append(fb3,sizeof(fb3),cc);assert(strstr(fb3," abort_refused="));
     g_melee_owned_cc=own;g_melee_rmb=rmb;}
    /* ranged path / no combat releases */
    fp_melee_release();assert(!g_melee_owned_cc&&!g_melee_owned_mv);approach(mv);assert(approach_calls==4);
    puts("RESULT B17 PASS manual melee adapter: AI refusal, click buffer retry/out_of_reach/expired, latency, owned-only approach refusal, hold ground (no combat locomotion while owned), spam switch at native pace, swing timing + per-pair slack/early starts, click reject reasons, click_legal switch, swingstat (applied attack speed, per-technique time, cancelled spans apart), native swing timer, no cancel-into-block / need-block abort without RMB, natural-end-only technique time, re-arm after UI/KO/pause, RMB-only block; native layout/runtime unvalidated");
    return 0;
}
