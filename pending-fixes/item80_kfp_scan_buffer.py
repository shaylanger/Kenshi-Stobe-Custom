#!/usr/bin/env python3
"""Item 80 (KenshiFP): Kenshi died silently (no dump) about a second after a BUY goal started walking to
Apothecary Abia (item 75's 1000-unit trader search). stg_scan_chars_r gave getCharactersWithinSphere
a lektor of exactly `max` slots while asking for maxFar=max AND maxNear=max (up to 2*max results);
getObjectsWithinSphere got a 128-slot lektor for 128 results. A lektor that fills its slots is grown
by the game's allocator, which then frees our stack buffer -> heap corruption -> fail-fast exit.
Now: a static scratch lektor with room for every requested result (maxNear 0, capacity 2*max+32;
objects 256 for 128), copied into the caller's array; a reallocated buffer is never used; plus
throttled TRADE_SEARCH / TRADE_WALK debug lines. Usage: item80_kfp_scan_buffer.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'STG_SCAN_CAP' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:80]!r}'
    s = s.replace(old, new)

rep(r'''static int stg_scan_chars_r(void *gw,void *actor,void **out,int max,float radius)
{
    if(!gw||!actor||!out||max<1)return 0;''',
r'''/* Item 80: scratch lektors big enough for every result the game may add (it grows a full
 * lektor with its own allocator, which would free our buffer). Main thread only. */
#define STG_SCAN_CAP 1024
#define STG_OBJ_CAP 512
static void *g_stg_scan_buf[STG_SCAN_CAP];
static void *g_stg_obj_buf[STG_OBJ_CAP];

static int stg_scan_chars_r(void *gw,void *actor,void **out,int max,float radius)
{
    if(!gw||!actor||!out||max<1)return 0;
    if(max>(STG_SCAN_CAP-32)/2)max=(STG_SCAN_CAP-32)/2;''')
rep(r'''    StobePtrLektor l; memset(&l,0,sizeof(l)); l.max_size=max; l.stuff=out;
    g_stobe_getchars(gw,&l,&c,radius,0,0,max,max,actor);
    if(!l.stuff||l.count>(uint32_t)max)return 0;
    int n=(int)l.count;''',
r'''    memset(g_stg_scan_buf,0,sizeof(g_stg_scan_buf));
    StobePtrLektor l; memset(&l,0,sizeof(l)); l.max_size=STG_SCAN_CAP; l.stuff=g_stg_scan_buf;
    g_stobe_getchars(gw,&l,&c,radius,0,0,max,0,actor);
    if(l.stuff!=g_stg_scan_buf||l.count>(uint32_t)STG_SCAN_CAP){
        logline("[stobe] STG_SCAN lektor grown (count=%u) -- result dropped",l.count);
        return 0;
    }
    int n=0;
    for(uint32_t i=0;i<l.count&&n<max;i++)if(g_stg_scan_buf[i])out[n++]=g_stg_scan_buf[i];''')
rep(r'''        void *extra[128]={0};
        StobePtrLektor l2; memset(&l2,0,sizeof(l2)); l2.max_size=128; l2.stuff=extra;
        g_stobe_getobjects(gw,&l2,&c,radius,1,128,actor);
        if(l2.stuff&&l2.count<=128){
            for(uint32_t i=0;i<l2.count&&n<max;i++){
                void *x=extra[i];int dup=0;''',
r'''        memset(g_stg_obj_buf,0,sizeof(g_stg_obj_buf));
        StobePtrLektor l2; memset(&l2,0,sizeof(l2)); l2.max_size=STG_OBJ_CAP; l2.stuff=g_stg_obj_buf;
        g_stobe_getobjects(gw,&l2,&c,radius,1,128,actor);
        if(l2.stuff==g_stg_obj_buf&&l2.count<=STG_OBJ_CAP){
            for(uint32_t i=0;i<l2.count&&n<max;i++){
                void *x=g_stg_obj_buf[i];int dup=0;''')

# throttled debug lines around the trader search and the walk
rep(r'''    char trader_name[128]={0};float dist=0;
    void *trader=stg_find_trader(gw,actor,g->target,trader_name,sizeof(trader_name),&dist);
    if(!trader){''',
r'''    char trader_name[128]={0};float dist=0;
    static DWORD s_trade_log_ms;static char s_trade_log_id[64];
    DWORD tnow=GetTickCount();
    int tlog=strcmp(s_trade_log_id,g->id)!=0||(LONG)(tnow-s_trade_log_ms)>10000;
    if(tlog){s_trade_log_ms=tnow;strncpy(s_trade_log_id,g->id,sizeof(s_trade_log_id)-1);
        logline("[stobe] TRADE_SEARCH start goal=%s target=%s",g->id,g->target[0]?g->target:"(nearest)");}
    void *trader=stg_find_trader(gw,actor,g->target,trader_name,sizeof(trader_name),&dist);
    if(tlog)logline("[stobe] TRADE_SEARCH done goal=%s found=%s dist=%.0f",g->id,trader?trader_name:"(none)",trader?dist:-1.0f);
    if(!trader){''')
rep(r'''        if(char_position(trader,&tp)&&try_move_to_pos(actor,&tp)){''',
r'''        int have_pos=char_position(trader,&tp);
        if(tlog)logline("[stobe] TRADE_WALK issue goal=%s to=%s pos=%.0f,%.0f,%.0f",g->id,trader_name,tp.x,tp.y,tp.z);
        int walk_ok=have_pos&&try_move_to_pos(actor,&tp);
        if(tlog)logline("[stobe] TRADE_WALK done goal=%s ok=%d",g->id,walk_ok);
        if(walk_ok){''')
p.write_text(s)
print('patched')
