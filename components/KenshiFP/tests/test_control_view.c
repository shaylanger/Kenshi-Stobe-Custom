#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#define GW_PLAYER 0x580
#define PI_PLAYERCHARS 0x2b0
#define PI_SELECTED_CHAR 0xf0
#define CHAR_HANDLE 0x58
#define HAND_IDS 8
#define LEK_COUNT 8
#define LEK_STUFF 0x10
#define KAH_OK 1
#define KAH_ERROR 0
#define _stricmp strcasecmp
typedef long LONG;
typedef unsigned long DWORD;
typedef struct KAH_Reply {void *impl;void (*append)(struct KAH_Reply *,const char *);} KAH_Reply;
static unsigned char world[0x600],pi[0x300],a[0x90],b[0x90],outsider[0x90];
static void *chars[2],*selected,*g_gw_cache=world;
static int g_fp_mode,g_cfg_direct_default=1,g_cfg_key_take_control=0x75,g_ui_open,key,focus=1;
static int GetAsyncKeyState(int code){(void)code;return key?0x8000:0;}
static int game_has_focus(void){return focus;}
static LONG InterlockedExchange(volatile LONG *v,LONG n){LONG old=*v;*v=n;return old;}
static void logline(const char *fmt,...){(void)fmt;}
static int char_valid(void *v){return v==a || v==b || v==outsider;}
static void *first_player_char(void *gw){return gw?selected:NULL;}
static int readable(void *v,size_t n){
    const uintptr_t bases[]={(uintptr_t)world,(uintptr_t)pi,(uintptr_t)a,(uintptr_t)b,(uintptr_t)outsider,(uintptr_t)chars};
    const size_t sizes[]={sizeof(world),sizeof(pi),sizeof(a),sizeof(b),sizeof(outsider),sizeof(chars)};
    for(unsigned i=0;i<6;i++){uintptr_t p=(uintptr_t)v;if(p>=bases[i] && p-bases[i]<=sizes[i] && n<=sizes[i]-(p-bases[i])) return 1;}
    return 0;
}
static int releases;
/* fp_move state reads these client globals (kenshifp_client.c) */
static DWORD fake_tick=1000;
static DWORD GetTickCount(void){return fake_tick;}
static int g_was_moving,g_was_direct,g_is_down,g_ui_moveblock;
static volatile LONG g_dm_active;
static float g_move_speed;
static void fp_control_release_actor(void *pc){(void)pc;++releases;}
#include "../client/kfp_control.inc"
#include "../client/kfp_view.h"
static void put_ptr(unsigned char *p,size_t off,void *v){memcpy(p+off,&v,sizeof(v));}
static void select_actor(void *v){
    selected=v;memcpy(pi+PI_SELECTED_CHAR+HAND_IDS,(unsigned char *)v+CHAR_HANDLE+HAND_IDS,20);
}
static char reply[400];
static void append(KAH_Reply *r,const char *s){(void)r;strncat(reply,s,sizeof(reply)-strlen(reply)-1);}
int main(void){
    put_ptr(world,GW_PLAYER,pi);put_ptr(pi,PI_PLAYERCHARS+LEK_STUFF,chars);
    uint32_t n=2;memcpy(pi+PI_PLAYERCHARS+LEK_COUNT,&n,4);
    uint32_t ha[5]={1,2,3,4,100},hb[5]={1,2,3,4,101},hc[5]={1,7,8,9,300};
    memcpy(a+CHAR_HANDLE+HAND_IDS,ha,20);memcpy(b+CHAR_HANDLE+HAND_IDS,hb,20);memcpy(outsider+CHAR_HANDLE+HAND_IDS,hc,20);
    chars[0]=a;chars[1]=b;select_actor(a);
    fp_control_tick(world);assert(g_fp_mode && fp_controlled_char(world)==a);
    select_actor(b);assert(fp_controlled_char(world)==a); /* all five handle words matter */
    assert(fp_control_take_selected(world));assert(fp_controlled_char(world)==b);assert(releases>0);
    g_fp_mode=0;fp_control_tick(world);assert(!g_fp_mode); /* explicit fallback stays off */
    g_fp_mode=1;select_actor(a);g_ui_open=1;key=1;fp_control_tick(world);assert(fp_controlled_char(world)==b);
    key=0;fp_control_tick(world);g_ui_open=0;key=1;fp_control_tick(world);assert(fp_controlled_char(world)==a);
    key=0;selected=a;memcpy(pi+PI_SELECTED_CHAR+HAND_IDS,hc,20);
    assert(!fp_control_take_selected(world));assert(fp_controlled_char(world)==a); /* inspected outsider is never controlled */
    select_actor(b);chars[0]=b;assert(!fp_controlled_char(world));fp_control_tick(world);assert(!g_fp_mode);
    selected=NULL;fp_control_tick(world);assert(!g_fp_mode && !g_fp_control_pinned);
    chars[0]=a;select_actor(a);fp_control_tick(world);assert(g_fp_mode && fp_controlled_char(world)==a);
    KAH_Reply r={NULL,append};const char *argv[]={"fp_control","state"};reply[0]=0;
    assert(kah_fp_control("test",2,argv,&r,NULL)==KAH_OK);assert(strstr(reply,"direct=1"));
    /* fp_move (TEST ONLY): bounded WASD hold read by kah_move_key, expires on the tick, rejects bad args */
    {const char *mv[]={"fp_move","wa","500"};reply[0]=0;assert(kah_fp_move("test",3,mv,&r,NULL)==KAH_OK);
     assert(kah_move_key(1)&&kah_move_key(4)&&!kah_move_key(2)&&!kah_move_key(8));
     const char *st[]={"fp_move","state"};reply[0]=0;assert(kah_fp_move("test",2,st,&r,NULL)==KAH_OK);
     assert(strstr(reply,"keys=wa left_ms=500 ")&&strstr(reply,"fp_mode=1"));
     fake_tick+=500;assert(!kah_move_key(1)&&!g_kah_move_keys); /* expired hold clears itself */
     const char *bad[]={"fp_move","wx"};assert(kah_fp_move("test",2,bad,&r,NULL)==KAH_ERROR&&!g_kah_move_keys);
     const char *badms[]={"fp_move","w","0"};assert(kah_fp_move("test",3,badms,&r,NULL)==KAH_ERROR&&!g_kah_move_keys);
     const char *none[]={"fp_move","none"};assert(kah_fp_move("test",2,none,&r,NULL)==KAH_OK&&!kah_move_key(1));}
    KfpView v={0};
    kfp_view_wheel(&v,-120);assert(fabsf(v.target-.5f)<.001f);
    kfp_view_wheel(&v,-100000);assert(v.target==KFP_VIEW_MAX);
    kfp_view_wheel(&v,100000);assert(v.target==0);
    v.target=4;v.applied=4;assert(kfp_view_next(&v,.016f)==4);
    v.target=0;assert(kfp_view_next(&v,.016f)==0); /* zoom in immediately */
    v.target=4;v.applied=0;float d=kfp_view_next(&v,1.0f/60.0f);assert(d>0 && d<4);
    KfpView u=v;float x=kfp_view_next(&u,1.0f/30.0f);
    u.applied=d;u.applied=kfp_view_next(&u,1.0f/60.0f);assert(fabsf(u.applied-x)<.0001f);
    v.applied=.1f;assert(kfp_view_is_eye(&v));v.applied=2;assert(!kfp_view_is_eye(&v));
    v.target=NAN;assert(kfp_view_next(&v,.01f)==0);
    puts("RESULT B09 PASS control pinning/inspection/explicit transfer/fallback/unload/reload and view wheel bounds/frame-rate smoothing");
}
