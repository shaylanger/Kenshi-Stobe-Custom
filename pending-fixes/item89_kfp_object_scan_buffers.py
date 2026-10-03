#!/usr/bin/env python3
"""Item 89 (KenshiFP): Kenshi died silently on the first tick of a work goal (Basic First Aid Kit at
the Crafting base): the same signature as item 80. The building and world-item searches handed
getObjectsWithinSphere a lektor of exactly `max` slots; with a full result (the Crafting base has
many buildings) the game grows it with its own allocator and frees our buffer -> heap corruption.
Now every object search uses a static scratch lektor with plenty of spare room, copied out; a grown
buffer is never used (logged). Plus throttled WORK_STEP debug lines in the work-goal tick.
Usage: item89_kfp_object_scan_buffers.py <KenshiFP root>"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f'{rel}: already patched'); return
    n = s.count(old)
    assert n == 1, f'{rel}: anchor found {n} times: {old[:70]!r}'
    p.write_text(s.replace(old, new))
    print(f'{rel}: patched')

W = 'client/stobe_work_planner.inc'
patch(W,
r'''static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;
    Vec3 center={0,0,0};
    if (!char_position(actor,&center)) return 0;
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)max; list.stuff=out;
    g_stobe_getobjects(gw,&list,&center,WGP_SCAN_RADIUS,0,max,actor);
    if (!list.stuff || list.count>(uint32_t)max) return 0;
    return (int)list.count;
}''',
r'''/* Item 89: the game grows a full lektor with its own allocator (freeing our buffer): scan into
 * a static scratch lektor with plenty of spare room and copy out. Main thread only. */
#define WGP_SCAN_CAP 4096
static void *g_wgp_scan_buf[WGP_SCAN_CAP];

static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;
    if (max > WGP_SCAN_CAP/2) max = WGP_SCAN_CAP/2;
    Vec3 center={0,0,0};
    if (!char_position(actor,&center)) return 0;
    memset(g_wgp_scan_buf,0,sizeof(g_wgp_scan_buf));
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)WGP_SCAN_CAP; list.stuff=g_wgp_scan_buf;
    g_stobe_getobjects(gw,&list,&center,WGP_SCAN_RADIUS,0,max,actor);
    if (list.stuff!=g_wgp_scan_buf || list.count>(uint32_t)WGP_SCAN_CAP) {
        logline("[stobe] WGP_SCAN lektor grown (count=%u) -- result dropped",list.count);
        return 0;
    }
    int n=0;
    for (uint32_t i=0;i<list.count && n<max;i++) if (g_wgp_scan_buf[i]) out[n++]=g_wgp_scan_buf[i];
    return n;
}''')

# throttled step debug in the work-goal tick
patch(W,
r'''    WgpProducer root;
    if (!wgp_find_producer(gw,actor,g->item,&root)) {
        char r[256]={0};''',
r'''    static DWORD s_step_log_ms; static char s_step_log_id[64];
    int slog=strcmp(s_step_log_id,g->id)!=0||(LONG)(GetTickCount()-s_step_log_ms)>10000;
    if (slog) { s_step_log_ms=GetTickCount(); strncpy(s_step_log_id,g->id,sizeof(s_step_log_id)-1);
        logline("[stobe] WORK_STEP id=%s find_producer start item=%s have=%d/%d",g->id,g->item,g->completed,g->quantity); }
    WgpProducer root;
    int found_root=wgp_find_producer(gw,actor,g->item,&root);
    if (slog) logline("[stobe] WORK_STEP id=%s find_producer done found=%d building=%s crafting=%d",
                      g->id,found_root,found_root?root.building_name:"",found_root?root.is_crafting:0);
    if (!found_root) {
        char r[256]={0};''')
patch(W,
r'''    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(root.production,missing,WGP_MAX_MISSING);
    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));''',
r'''    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(root.production,missing,WGP_MAX_MISSING);
    if (slog) logline("[stobe] WORK_STEP id=%s missing inputs=%d queued_root=%d",g->id,miss,g->queued_root);
    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));''')

T = 'client/stobe_task_goals.inc'
patch(T,
r'''static int stg_scan_world_items(void *gw,void *actor,void **out,int max)
{
    if(!gw||!actor||!out||max<3||!g_stobe_getobjects)return 0;
    Vec3 center={0,0,0};if(!char_position(actor,&center))return 0;
    int count=0;
    const int types[3]={2,3,4};
    for(int ti=0;ti<3 && count<max;ti++){
        StobePtrLektor l;memset(&l,0,sizeof(l));
        l.max_size=(uint32_t)(max-count);l.stuff=out+count;
        g_stobe_getobjects(gw,&l,&center,STG_SCAN_RADIUS,types[ti],max-count,actor);
        if(l.stuff&&l.count<=(uint32_t)(max-count))count+=(int)l.count;
    }
    return count;
}''',
r'''static int stg_scan_world_items(void *gw,void *actor,void **out,int max)
{
    if(!gw||!actor||!out||max<3||!g_stobe_getobjects)return 0;
    Vec3 center={0,0,0};if(!char_position(actor,&center))return 0;
    int count=0;
    const int types[3]={2,3,4};
    for(int ti=0;ti<3 && count<max;ti++){
        /* item 89: room for every result, copied out (the game would grow a full lektor) */
        memset(g_stg_obj_buf,0,sizeof(g_stg_obj_buf));
        StobePtrLektor l;memset(&l,0,sizeof(l));
        l.max_size=(uint32_t)STG_OBJ_CAP;l.stuff=g_stg_obj_buf;
        int want=max-count; if(want>STG_OBJ_CAP/2)want=STG_OBJ_CAP/2;
        g_stobe_getobjects(gw,&l,&center,STG_SCAN_RADIUS,types[ti],want,actor);
        if(l.stuff!=g_stg_obj_buf||l.count>(uint32_t)STG_OBJ_CAP){logline("[stobe] STG_SCAN items lektor grown -- dropped");continue;}
        for(uint32_t i=0;i<l.count&&count<max;i++)if(g_stg_obj_buf[i])out[count++]=g_stg_obj_buf[i];
    }
    return count;
}''')

C = 'client/kenshifp_client.c'
patch(C,
r'''    void *nearby[192] = {0};
    StobePtrLektor out;
    memset(&out, 0, sizeof(out));
    out.max_size = 192;
    out.stuff = nearby;
    g_stobe_getobjects(gw, &out, &center, 450.0f, 0, 192, actor);
    if (!out.stuff || out.count > 192) return NULL;''',
r'''    static void *nearby[1024]; /* item 89: spare room so the game never grows our buffer */
    memset(nearby, 0, sizeof(nearby));
    StobePtrLektor out;
    memset(&out, 0, sizeof(out));
    out.max_size = 1024;
    out.stuff = nearby;
    g_stobe_getobjects(gw, &out, &center, 450.0f, 0, 192, actor);
    if (out.stuff != nearby || out.count > 1024) return NULL;''')
