#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#define CHAR_RANGEDCOMBAT 0x2f0
#define RC_STATE_OFF 0
#define RC_COMBATMODE 0x36
#define RC_STAT 0x30
#define RC_GUN 0x28
#define RC_ME 0x68
#define GUN_AMMO 0x20
#define KAH_OK 1
#define KAH_ERROR 0
#define _stricmp strcasecmp
typedef struct KAH_Reply {
    void *impl; void (*append)(struct KAH_Reply *, const char *);
} KAH_Reply;
static unsigned char actor_mem[0x310], rc_mem[0x80], gun_mem[0x30];
static float g_frame_dt=0.016f;
static uint64_t GetTickCount64(void) { static uint64_t ms; return ++ms; }
static void *first_player_char(void *gw) { return gw; }
static int readable(void *p, size_t n) {
    const uintptr_t bases[]={(uintptr_t)actor_mem,(uintptr_t)rc_mem,(uintptr_t)gun_mem};
    const size_t sizes[]={sizeof(actor_mem),sizeof(rc_mem),sizeof(gun_mem)};
    for (unsigned i=0;i<3;i++) {
        uintptr_t v=(uintptr_t)p;
        if (v>=bases[i] && v-bases[i]<=sizes[i] && n<=sizes[i]-(v-bases[i])) return 1;
    }
    return 0;
}
#include "../client/kfp_combat_probe.inc"
static char output[32768];
static void append(KAH_Reply *r, const char *s) {
    (void)r; assert(strlen(output)+strlen(s)<sizeof(output)); strcat(output,s);
}
static int command(const char *op, const char *seq) {
    const char *args[]={"fp_combat_probe",op,seq};
    KAH_Reply r={NULL,append}; output[0]=0;
    return kah_fp_combat_probe("test",seq?3:2,args,&r,NULL);
}
static void put_ptr(unsigned char *p,size_t off,void *v) { memcpy(p+off,&v,sizeof(v)); }
static void put_int(unsigned char *p,size_t off,int v) { memcpy(p+off,&v,sizeof(v)); }
int main(void) {
    assert(command("state",NULL)==KAH_OK);
    assert(strstr(output,"recording=0"));
    assert(command("events",NULL)==KAH_OK); /* before first begin */
    assert(strstr(output,"lost=0"));
    fp_combat_tick(actor_mem,0.016f); assert(g_combat_trace.count==0);
    put_ptr(actor_mem,CHAR_RANGEDCOMBAT,rc_mem); put_ptr(rc_mem,RC_GUN,gun_mem);
    put_ptr(rc_mem,RC_ME,actor_mem);
    put_int(rc_mem,RC_STATE_OFF,3); put_int(rc_mem,RC_STAT,37);
    put_int(gun_mem,GUN_AMMO,1); rc_mem[RC_COMBATMODE]=1;
    assert(command("begin",NULL)==KAH_OK);
    assert(command("state","1")==KAH_ERROR);
    fp_combat_tick(actor_mem,0.016f);
    assert(g_combat_trace.count==1);
    const KfpCombatEvent *e=kfp_trace_get(&g_combat_trace,1);
    assert(e && e->ammo==1 && e->state==3 && e->stat==37 && e->gun==(uintptr_t)gun_mem);
    fp_combat_tick(actor_mem,0.016f); assert(g_combat_trace.count==1);
    fp_combat_probe_animation(rc_mem,(void *)42); assert(g_combat_trace.count==2);
    fp_combat_probe_shot(gun_mem,(void *)123,NULL,5,KFP_EV_SHOT_BEFORE);
    assert(g_combat_trace.count==2); /* unrelated actor ignored */
    fp_combat_probe_shot(gun_mem,actor_mem,(void *)42,39,KFP_EV_SHOT_BEFORE);
    put_int(gun_mem,GUN_AMMO,0);
    fp_combat_probe_shot(gun_mem,actor_mem,(void *)42,39,KFP_EV_SHOT_AFTER);
    assert(kfp_trace_get(&g_combat_trace,3)->ammo==1);
    assert(kfp_trace_get(&g_combat_trace,4)->ammo==0);
    assert(kfp_trace_get(&g_combat_trace,4)->stat==39);
    assert(kfp_trace_get(&g_combat_trace,4)->target==42);
    assert(command("events","4")==KAH_OK); assert(strstr(output,"through=4 more=0"));
    assert(command("events","-1")==KAH_ERROR);
    assert(command("events","18446744073709551616")==KAH_ERROR);
    assert(command("events","99")==KAH_ERROR);
    assert(command("invalid",NULL)==KAH_ERROR);
    assert(command("end",NULL)==KAH_OK);
    fp_combat_tick(actor_mem,0.016f); fp_combat_probe_animation(rc_mem,NULL);
    assert(g_combat_trace.count==4);
    assert(command("begin",NULL)==KAH_OK);
    fp_combat_tick(NULL,0.016f);
    e=kfp_trace_get(&g_combat_trace,1);
    assert(e && e->state==-1 && e->ammo==-1 && !e->actor);
    assert(command("state",NULL)==KAH_OK); assert(strstr(output,"actor_observed=0"));
    fp_combat_tick(actor_mem,0.016f);
    for (unsigned i=0;i<KFP_TRACE_CAPACITY+100;i++) fp_combat_probe_animation(rc_mem,NULL);
    assert(g_combat_trace.count==KFP_TRACE_CAPACITY);
    uint64_t oldest=kfp_trace_oldest(&g_combat_trace);
    assert(!kfp_trace_get(&g_combat_trace,oldest-1));
    assert(kfp_trace_lost(&g_combat_trace,0)==oldest-1);
    assert(command("events","0")==KAH_OK);
    char wanted[100];
    snprintf(wanted,sizeof(wanted),"through=%llu more=1",(unsigned long long)(oldest+63));
    assert(strstr(output,wanted));
    snprintf(wanted,sizeof(wanted),"%llu",(unsigned long long)(oldest+63));
    assert(command("events",wanted)==KAH_OK);
    uint64_t old_capture=g_combat_probe_capture;
    assert(command("clear",NULL)==KAH_OK); assert(g_combat_trace.count==0);
    assert(g_combat_probe_capture==old_capture+1);
    fp_combat_tick(actor_mem,0.016f); assert(g_combat_trace.count==1);
    assert(!memcmp(actor_mem+CHAR_RANGEDCOMBAT,&(void *){rc_mem},sizeof(void *)));
    assert(*(int *)(gun_mem+GUN_AMMO)==0); /* observed; never replenished */
    puts("RESULT B07 PASS passive probe gating, snapshots, shot before/after, unknown fields, sequence validation, bounded pagination, overflow reporting");
    return 0;
}
