/* STOBE persistent work-goal planner. Included by kenshifp_client.c.
 * Natural-language dialogue creates finite output goals; this module uses
 * Kenshi's real production/crafting/job APIs and recursively resolves missing
 * inputs. No LLM calls occur in this executor. */
#define WGP_MAX_GOALS 16
#define WGP_MAX_SUBSTATE 24
#define WGP_MAX_DEPTH 10
#define WGP_MAX_PLAN_NODES 64
#define WGP_MAX_BUILDINGS 256
#define WGP_MAX_CRAFTS 128
#define WGP_MAX_MISSING 32
#define WGP_TICK_MS 1000
#define WGP_STALL_MS 180000
#define WGP_DEP_STALL_MS 900000
#define WGP_TRAVEL_STALL_MS 240000
#define WGP_ARRIVE_DIST 65.0f
#define WGP_SCAN_RADIUS 1400.0f

#define WGP_BF_MINE 1
#define WGP_BF_CRAFTING 9
#define WGP_BF_MINE_NATURAL 25
#define WGP_TASK_COLLECT_OUTPUT 92

#define WGP_GETPROD_SYM "?_NV_getProductionBuilding@Building@@QEAAPEAVProductionBuilding@@XZ"
#define WGP_GETINV_BUILDING_SYM "?_NV_getInventory@Building@@QEBAPEAVInventory@@XZ"
#define WGP_ISPLAYER_BUILDING_SYM "?isThePlayer@Building@@QEBA_NXZ"
#define WGP_SPECIAL_SYM "?_NV_getSpecialFunction@Building@@QEBA?AW4BuildingFunction@@XZ"
#define WGP_AVAILABLE_CRAFTS_SYM "?getAvailableCrafts@CraftingBuilding@@QEAAXAEAV?$lektor@VGameDataGroup@@@@@Z"
#define WGP_ADD_CRAFT_SYM "?_addCraft@CraftingBuilding@@QEAAPEAVCraftingItem@@PEAVGameData@@0MVYesNoMaybe@@@Z"

typedef void *(*wgp_getprod_t)(void *);
typedef void *(*wgp_getinv_building_t)(void *);
typedef int (*wgp_isplayer_building_t)(void *);
typedef int (*wgp_special_t)(void *);
typedef void (*wgp_available_crafts_t)(void *, void *);
typedef void *(*wgp_add_craft_t)(void *, void *, void *, float, int);

typedef struct WgpGroup { void *g1; void *g2; } WgpGroup;
typedef struct WgpSubstate {
    char item[128];
    int queued;     /* crafts queued and not yet observed as finished */
    int last_have;  /* runtime only: count seen last tick (-1 = unknown) */
} WgpSubstate;

typedef struct WgpGoal {
    int used;
    char id[64];
    uint32_t actor_serial;
    char actor[128];
    char item[128];
    int quantity;
    int baseline;
    int completed;
    int queued_root;
    int state; /* 0 active, 1 complete, 2 blocked, 3 cancelled */
    int has_dest;
    Vec3 dest;
    char dest_label[128];
    char current_step[192];
    char reason[256];
    DWORD created_ms;
    DWORD last_progress_ms;
    DWORD last_order_ms;
    float last_distance;
    int last_count;
    int report_triggered;
    WgpSubstate subs[WGP_MAX_SUBSTATE];
    long long dep_sig;      /* runtime only: sum of dependency counts this tick */
    long long dep_sig_last; /* runtime only: previous tick's sum */
    int rt_seen_active;     /* runtime only: was ACTIVE this session */
    int rt_return_started;  /* runtime only: walk-back already requested */
    float haul_last_dist;   /* runtime only: hauling walk progress */
    int haul_still;
    DWORD haul_next_ms;
} WgpGoal;

typedef struct WgpProducer {
    void *building;
    void *production;
    void *craft_base;
    void *craft_material;
    int is_crafting;
    int special;
    int task;
    char building_name[160];
    char output_name[160];
} WgpProducer;

static WgpGoal g_wgp_goals[WGP_MAX_GOALS];
static int g_wgp_loaded;
static DWORD g_wgp_next_tick;
static DWORD g_wgp_next_save;
static int g_wgp_dirty;

static wgp_getprod_t g_wgp_getprod;
static wgp_getinv_building_t g_wgp_getinv_building;
static wgp_isplayer_building_t g_wgp_isplayer_building;
static wgp_special_t g_wgp_special;
static wgp_available_crafts_t g_wgp_available_crafts;
static wgp_add_craft_t g_wgp_add_craft;

static int try_move_to_pos(void *pc, const Vec3 *tgt);
static int stg_request_purchase_fallback(void *gw,void *actor,uint32_t actor_serial,const char *actor_name,const char *parent_goal_id,const char *item,int qty,char *reason,size_t reason_sz);
static void *wgp_vcall_ptr(void *obj, size_t byte_off);
static int wgp_building_special(void *building);
static void *wgp_building_inventory(void *building);
static void *wgp_building_production(void *building);

static void wgp_clean(char *s)
{
    if (!s) return;
    for (; *s; ++s) {
        if (*s == '\t' || *s == '\r' || *s == '\n' || *s == '|') *s = ' ';
    }
}

static const char *wgp_state_name(int state)
{
    switch (state) {
        case 1: return "COMPLETE";
        case 2: return "BLOCKED";
        case 3: return "CANCELLED";
        case 4: return "PAUSED";
        default: return "ACTIVE";
    }
}

static int wgp_resolve_exports(void)
{
    if (!stobe_resolve_action_exports()) return 0;
    HMODULE k = GetModuleHandleA("KenshiLib.dll");
    if (!k) return 0;
    if (!g_wgp_getprod) g_wgp_getprod=(wgp_getprod_t)GetProcAddress(k,WGP_GETPROD_SYM);
    if (!g_wgp_getinv_building) g_wgp_getinv_building=(wgp_getinv_building_t)GetProcAddress(k,WGP_GETINV_BUILDING_SYM);
    if (!g_wgp_isplayer_building) g_wgp_isplayer_building=(wgp_isplayer_building_t)GetProcAddress(k,WGP_ISPLAYER_BUILDING_SYM);
    if (!g_wgp_special) g_wgp_special=(wgp_special_t)GetProcAddress(k,WGP_SPECIAL_SYM);
    if (!g_wgp_available_crafts) g_wgp_available_crafts=(wgp_available_crafts_t)GetProcAddress(k,WGP_AVAILABLE_CRAFTS_SYM);
    if (!g_wgp_add_craft) g_wgp_add_craft=(wgp_add_craft_t)GetProcAddress(k,WGP_ADD_CRAFT_SYM);
    return g_wgp_getprod && g_wgp_getinv_building && g_wgp_isplayer_building &&
           g_wgp_special && g_wgp_available_crafts && g_wgp_add_craft;
}

static int wgp_name(void *gd, char *out, size_t outsz)
{
    if (!gd || !readable((void *)((uintptr_t)gd + GD_NAME), 0x20)) return 0;
    return stobe_copy_native_string((void *)((uintptr_t)gd + GD_NAME), out, outsz);
}

static int wgp_name_match(const char *actual, const char *query)
{
    char a[192]={0}, q[192]={0};
    if (!actual || !query || !*actual || !*query) return 0;
    strncpy(a,actual,sizeof(a)-1); strncpy(q,query,sizeof(q)-1);
    stobe_ascii_lower(a); stobe_ascii_lower(q);
    if (!strcmp(a,q)) return 3;
    if (strstr(a,q) || strstr(q,a)) return 2;
    if ((!strcmp(q,"copper") && strstr(a,"raw copper")) ||
        (!strcmp(q,"iron") && strstr(a,"raw iron"))) return 3;
    return 0;
}

static void *wgp_find_squad_actor(void *gw, uint32_t serial, const char *name)
{
    if (!readable(gw, GW_PLAYER + 8)) return NULL;
    void *player=*(void **)((uintptr_t)gw+GW_PLAYER);
    if (!readable(player,PI_PLAYERCHARS+LEK_STUFF+8)) return NULL;
    uint32_t count=*(uint32_t *)((uintptr_t)player+PI_PLAYERCHARS+LEK_COUNT);
    void **stuff=*(void ***)((uintptr_t)player+PI_PLAYERCHARS+LEK_STUFF);
    if (!stuff || count>4096 || !readable(stuff,count*sizeof(void*))) return NULL;
    for (uint32_t i=0;i<count;i++) {
        void *c=stuff[i];
        if (!char_valid(c) || !readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20)) continue;
        uint32_t *h=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
        if (serial && h[4]==serial) return c;
        if (!serial && name && *name) {
            char display[128]={0};
            if (stobe_copy_native_string((void *)((uintptr_t)c+0x18),display,sizeof(display)) &&
                !_stricmp(display,name)) return c;
        }
    }
    return NULL;
}

static int wgp_item_count_inventory(void *inv, const char *query)
{
    if (!inv || !query || !*query ||
        !readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor))) return 0;
    StobePtrLektor *items=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if (!items->stuff || items->count>4096 || !readable(items->stuff,items->count*sizeof(void*))) return 0;
    int total=0;
    for (uint32_t i=0;i<items->count;i++) {
        void *item=items->stuff[i];
        if (!readable(item,0x130)) continue;
        void *gd=stobe_item_gamedata(item);
        char n[160]={0};
        if (!gd || !wgp_name(gd,n,sizeof(n)) || !wgp_name_match(n,query)) continue;
        int qty=*(int *)((uintptr_t)item+0x12C);
        total += qty>0 ? qty : 1;
        if (total>1000000) return 1000000;
    }
    return total;
}

static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;
    Vec3 center={0,0,0};
    if (!char_position(actor,&center)) return 0;
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)max; list.stuff=out;
    g_stobe_getobjects(gw,&list,&center,WGP_SCAN_RADIUS,0,max,actor);
    if (!list.stuff || list.count>(uint32_t)max) return 0;
    return (int)list.count;
}

static int wgp_item_count_world(void *gw, void *actor, const char *query)
{
    int total=0;
    void *inv=g_stobe_getinv ? g_stobe_getinv(actor) : NULL;
    total += wgp_item_count_inventory(inv,query);
    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,buildings,WGP_MAX_BUILDINGS);
    for (int i=0;i<n;i++) {
        void *b=buildings[i];
        if (!readable(b,0x80)) continue;
        int special=wgp_building_special(b);
        int allowed=g_wgp_isplayer_building(b) ||
            special==WGP_BF_MINE || special==WGP_BF_MINE_NATURAL;
        if (!allowed) continue;
        void *binv=wgp_building_inventory(b);
        total += wgp_item_count_inventory(binv,query);
        if (total>1000000) return 1000000;
    }
    return total;
}

static void *wgp_vcall_ptr(void *obj, size_t byte_off)
{
    if (!obj || !readable(obj,8)) return NULL;
    void **vt=*(void ***)obj;
    size_t slot=byte_off/8;
    if (!readable(vt,(slot+1)*8)) return NULL;
    void *fn=vt[slot];
    return in_module(fn) ? fn : NULL;
}

static int wgp_building_special(void *building)
{
    typedef int (*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(building,0x2F0);
    return fn ? fn(building) : 0;
}

static void *wgp_building_inventory(void *building)
{
    typedef void *(*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(building,0x160);
    return fn ? fn(building) : NULL;
}

static void *wgp_building_production(void *building)
{
    typedef void *(*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(building,0x3B0);
    return fn ? fn(building) : NULL;
}

static void *wgp_prod_item(void *prod)
{
    typedef void *(*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(prod,0x550);
    return fn ? fn(prod) : NULL;
}

static int wgp_default_task(void *building)
{
    typedef int (*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(building,0x418);
    return fn ? fn(building) : 87;
}

static int wgp_missing(void *prod, void **out, int max)
{
    typedef void (*fn_t)(void *, StobePtrLektor *);
    fn_t fn=(fn_t)wgp_vcall_ptr(prod,0x560);
    if (!fn || !out || max<1) return 0;
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)max; list.stuff=out;
    fn(prod,&list);
    if (!list.stuff || list.count>(uint32_t)max) return 0;
    return (int)list.count;
}

static int wgp_find_producer(void *gw, void *actor, const char *query, WgpProducer *out)
{
    if (!out || !wgp_resolve_exports()) return 0;
    memset(out,0,sizeof(*out));
    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,buildings,WGP_MAX_BUILDINGS);
    int best=0;
    for (int i=0;i<n;i++) {
        void *b=buildings[i];
        if (!readable(b,0x80)) continue;
        int special=wgp_building_special(b);
        int allowed=g_wgp_isplayer_building(b) ||
            special==WGP_BF_MINE || special==WGP_BF_MINE_NATURAL;
        if (!allowed) continue;
        void *prod=wgp_building_production(b);
        if (!prod) continue;
        char bname[160]={0};
        void *bgd=*(void **)((uintptr_t)b+0x40);
        wgp_name(bgd,bname,sizeof(bname));

        if (special==WGP_BF_CRAFTING) {
            WgpGroup groups[WGP_MAX_CRAFTS]; memset(groups,0,sizeof(groups));
            StobePtrLektor list; memset(&list,0,sizeof(list));
            list.max_size=WGP_MAX_CRAFTS; list.stuff=(void **)groups;
            g_wgp_available_crafts(b,&list);
            int count=(int)(list.count>WGP_MAX_CRAFTS?WGP_MAX_CRAFTS:list.count);
            for (int j=0;j<count;j++) {
                char name1[160]={0};
                if (!wgp_name(groups[j].g1,name1,sizeof(name1))) continue;
                int score=wgp_name_match(name1,query);
                if (score>best) {
                    best=score; out->building=b; out->production=prod;
                    out->craft_base=groups[j].g1; out->craft_material=groups[j].g2;
                    out->is_crafting=1; out->special=special;
                    out->task=wgp_default_task(b);
                    strncpy(out->building_name,bname,sizeof(out->building_name)-1);
                    strncpy(out->output_name,name1,sizeof(out->output_name)-1);
                }
            }
        } else {
            void *gd=wgp_prod_item(prod);
            char pname[160]={0};
            if (!wgp_name(gd,pname,sizeof(pname))) continue;
            int score=wgp_name_match(pname,query);
            if (score>best) {
                best=score; out->building=b; out->production=prod;
                out->is_crafting=0; out->special=special; out->task=wgp_default_task(b);
                strncpy(out->building_name,bname,sizeof(out->building_name)-1);
                strncpy(out->output_name,pname,sizeof(out->output_name)-1);
            }
        }
        if (best>=3) break;
    }
    return best>0;
}

static int wgp_issue_building_task(void *actor, WgpProducer *p, int override_task)
{
    if (!actor || !p || !p->building || !wgp_resolve_exports()) return 0;
    void *orders=g_stobe_getorders(actor);
    if (!orders) return 0;
    Vec3 pos=*(Vec3 *)((uintptr_t)p->building+0x48);
    void *hand=(void *)((uintptr_t)p->building+CHAR_HANDLE);
    if (!readable(hand,0x20)) return 0;
    int task=override_task>=0 ? override_task : (p->task>0?p->task:87);
    g_stobe_addorder(orders,task,hand,&pos,0,0);
    g_stobe_rethink(actor);
    return 1;
}

static WgpSubstate *wgp_substate(WgpGoal *g, const char *item)
{
    for (int i=0;i<WGP_MAX_SUBSTATE;i++)
        if (g->subs[i].item[0] && !_stricmp(g->subs[i].item,item)) return &g->subs[i];
    for (int i=0;i<WGP_MAX_SUBSTATE;i++) if (!g->subs[i].item[0]) {
        strncpy(g->subs[i].item,item,sizeof(g->subs[i].item)-1);
        g->subs[i].last_have=-1;
        return &g->subs[i];
    }
    return NULL;
}

static int wgp_chain_has(char chain[][128], int n, const char *item)
{
    for (int i=0;i<n;i++) if (!_stricmp(chain[i],item)) return 1;
    return 0;
}

static int wgp_queue_craft(WgpProducer *p, int count)
{
    if (!p || !p->is_crafting || !p->craft_base || count<1) return 0;
    int made=0;
    if (count>32) count=32;
    for (int i=0;i<count;i++) {
        void *ci=g_wgp_add_craft(p->building,p->craft_base,p->craft_material,0.0f,2);
        if (!ci) break;
        made++;
    }
    return made;
}

static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */

/* return 1 ready/available, 0 working/waiting, -1 impossible */
static int wgp_ensure_item(void *gw, void *actor, WgpGoal *g, const char *item,
                           int need, int depth, char chain[][128], int chain_n,
                           int *budget, char *reason, size_t reason_sz)
{
    if (++(*budget)>WGP_MAX_PLAN_NODES) {
        snprintf(reason,reason_sz,"planning limit reached while trying to obtain %s",item);
        return -1;
    }
    if (depth>WGP_MAX_DEPTH) {
        snprintf(reason,reason_sz,"dependency depth exceeded %d while trying to obtain %s",WGP_MAX_DEPTH,item);
        return -1;
    }
    if (wgp_chain_has(chain,chain_n,item)) {
        snprintf(reason,reason_sz,"dependency cycle detected at %s",item);
        return -1;
    }
    int have=wgp_item_count_world(gw,actor,item);
    g->dep_sig+=(long long)have*(depth+1);
    if (have>=need) return 1;

    WgpProducer p;
    if (!wgp_find_producer(gw,actor,item,&p)) {
        int purchase=stg_request_purchase_fallback(gw,actor,g->actor_serial,g->actor,g->id,item,need,reason,reason_sz);
        if(purchase>0){
            snprintf(g->current_step,sizeof(g->current_step),"%s",reason);
            return 0;
        }
        if(purchase<0)return -1;
        snprintf(reason,reason_sz,"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",item);
        return -1;
    }

    char next_chain[WGP_MAX_DEPTH+2][128];
    memset(next_chain,0,sizeof(next_chain));
    for (int i=0;i<chain_n && i<WGP_MAX_DEPTH+1;i++)
        strncpy(next_chain[i],chain[i],sizeof(next_chain[i])-1);
    if (chain_n<WGP_MAX_DEPTH+1) strncpy(next_chain[chain_n],item,sizeof(next_chain[0])-1);
    int next_n=chain_n<WGP_MAX_DEPTH+1 ? chain_n+1 : chain_n;

    if (p.is_crafting) {
        WgpSubstate *ss=wgp_substate(g,item);
        if (!ss) {
            snprintf(reason,reason_sz,"too many distinct dependency items while trying to make %s",item);
            return -1;
        }
        /* Queue only the shortfall that is not already waiting at the bench. */
        int shortfall=need-have-ss->queued;
        if (shortfall>0) {
            ss->last_have=have; /* finished crafts are measured from here */
            int q=wgp_queue_craft(&p,shortfall);
            if (!q) {
                snprintf(reason,reason_sz,"could not queue %s at %s",item,p.building_name);
                return -1;
            }
            ss->queued+=q;
            g_wgp_dirty=1;
        }
    }

    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(p.production,missing,WGP_MAX_MISSING);
    for (int i=0;i<miss;i++) {
        char dep[128]={0};
        if (!wgp_name(missing[i],dep,sizeof(dep)) || !dep[0]) continue;
        int r=wgp_ensure_item(gw,actor,g,dep,need,depth+1,next_chain,next_n,budget,reason,reason_sz);
        if (r<0) return -1;
        if (r==0) {
            snprintf(g->current_step,sizeof(g->current_step),"Obtaining %s for %s",dep,item);
            return 0;
        }
    }

    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if ((LONG)(GetTickCount()-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&p,-1);
        g->last_order_ms=GetTickCount();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Producing %s at %s",item,
             p.building_name[0]?p.building_name:"production building");
    return 0;
}

static void wgp_goal_block(WgpGoal *g, const char *reason)
{
    g->state=2;
    strncpy(g->reason,reason?reason:"work goal blocked",sizeof(g->reason)-1);
    g_wgp_dirty=1;
    logline("[stobe] WORK_GOAL blocked id=%s actor=%s item=%s reason=%s",
            g->id,g->actor,g->item,g->reason);
}

static float wgp_distance(Vec3 a, Vec3 b)
{
    float dx=a.x-b.x, dy=a.y-b.y, dz=a.z-b.z;
    return sqrtf(dx*dx+dy*dy+dz*dz);
}

static void wgp_goal_tick(void *gw, WgpGoal *g)
{
    if (!g->used || g->state!=0) return;
    void *actor=wgp_find_squad_actor(gw,g->actor_serial,g->actor);
    if (!actor) {
        strncpy(g->current_step,"Waiting for NPC to be loaded",sizeof(g->current_step)-1);
        return;
    }

    DWORD now=GetTickCount();
    Vec3 pos={0,0,0};
    if (!char_position(actor,&pos)) return;

    if (g->has_dest==2 && wgp_distance(pos,g->dest)<=WGP_SCAN_RADIUS*0.75f) {
        /* Arrived earlier; walking between machines and storage is part of the job. */
    } else if (g->has_dest) {
        float dist=wgp_distance(pos,g->dest);
        if (g->last_distance<=0 || dist<g->last_distance-5.0f) {
            g->last_distance=dist; g->last_progress_ms=now;
        }
        if (dist>WGP_ARRIVE_DIST) {
            snprintf(g->current_step,sizeof(g->current_step),"Traveling to %s (%.0fm remaining)",
                     g->dest_label[0]?g->dest_label:"destination",dist);
            if ((LONG)(now-g->last_order_ms)>3000) {
                if (!try_move_to_pos(actor,&g->dest)) {
                    wgp_goal_block(g,"Kenshi could not issue the travel order");
                    return;
                }
                g->last_order_ms=now;
            }
            if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_TRAVEL_STALL_MS) {
                char r[256]; snprintf(r,sizeof(r),"could not reach %s; travel made no progress",
                                      g->dest_label[0]?g->dest_label:"destination");
                wgp_goal_block(g,r);
            }
            return;
        }
        if (g->has_dest!=2) { g->has_dest=2; g_wgp_dirty=1; } /* arrival latch (persisted) */
    }

    if (g->baseline<0) {
        g->baseline=wgp_item_count_world(gw,actor,g->item);
        g->last_count=g->baseline;
        g->last_progress_ms=now;
        g_wgp_dirty=1;
    }

    int current=wgp_item_count_world(gw,actor,g->item);
    g->completed=current-g->baseline;
    if (g->completed<0) g->completed=0;
    if (current!=g->last_count) {
        g->last_count=current; g->last_progress_ms=now; g_wgp_dirty=1;
    }
    /* Finished intermediate crafts: new units observed come off the queued count.
     * (The old code zeroed the counter whenever any existed, which re-queued the
     * full amount again and again -- a runaway crafting queue.) */
    for (int i=0;i<WGP_MAX_SUBSTATE;i++) {
        WgpSubstate *ss=&g->subs[i];
        if (!ss->item[0] || ss->queued<=0) continue; /* only intermediates still being crafted */
        int have=wgp_item_count_world(gw,actor,ss->item);
        if (ss->last_have>=0 && have>ss->last_have && ss->queued>0) {
            ss->queued-=have-ss->last_have;
            if (ss->queued<0) ss->queued=0;
            g_wgp_dirty=1;
        }
        ss->last_have=have;
    }

    if (g->completed>=g->quantity) {
        WgpProducer root;
        if (wgp_find_producer(gw,actor,g->item,&root))
            wgp_issue_building_task(actor,&root,WGP_TASK_COLLECT_OUTPUT);
        g->state=1;
        snprintf(g->current_step,sizeof(g->current_step),"Completed %d/%d %s",
                 g->completed,g->quantity,g->item);
        g->reason[0]='\0'; g_wgp_dirty=1;
        logline("[stobe] WORK_GOAL complete id=%s actor=%s item=%s qty=%d",
                g->id,g->actor,g->item,g->quantity);
        return;
    }

    WgpProducer root;
    if (!wgp_find_producer(gw,actor,g->item,&root)) {
        char r[256]={0};
        int outstanding=g->quantity-g->completed;if(outstanding<1)outstanding=1;
        int purchase=stg_request_purchase_fallback(gw,actor,g->actor_serial,g->actor,g->id,g->item,outstanding,r,sizeof(r));
        if(purchase>0){snprintf(g->current_step,sizeof(g->current_step),"%s",r);return;}
        if(purchase<0){wgp_goal_block(g,r);return;}
        snprintf(r,sizeof(r),"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",g->item);
        wgp_goal_block(g,r); return;
    }
    if (root.is_crafting && g->queued_root<g->quantity) {
        int added=wgp_queue_craft(&root,g->quantity-g->queued_root);
        if (added<=0) {
            char r[256]; snprintf(r,sizeof(r),"could not queue %s at %s",g->item,root.building_name);
            wgp_goal_block(g,r); return;
        }
        g->queued_root+=added; g_wgp_dirty=1;
    }

    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(root.production,missing,WGP_MAX_MISSING);
    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));
    g->dep_sig=0;
    strncpy(chain[0],g->item,sizeof(chain[0])-1);
    int budget=0;
    for (int i=0;i<miss;i++) {
        char dep[128]={0}, reason[256]={0};
        if (!wgp_name(missing[i],dep,sizeof(dep)) || !dep[0]) continue;
        int outstanding=g->quantity-g->completed;
        if (outstanding<1) outstanding=1;
        int r=wgp_ensure_item(gw,actor,g,dep,outstanding,1,chain,1,&budget,reason,sizeof(reason));
        if (r<0) {
            char full[256];
            snprintf(full,sizeof(full),"cannot make %s because %s",g->item,reason);
            wgp_goal_block(g,full); return;
        }
        if (r==0) {
            if (g->dep_sig!=g->dep_sig_last) {
                /* Gathering inputs counts as progress (mined stone, harvested wheat). */
                g->dep_sig_last=g->dep_sig; g->last_progress_ms=now;
            }
            if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_DEP_STALL_MS) {
                char full[256];
                snprintf(full,sizeof(full),"production stalled while %s",g->current_step);
                wgp_goal_block(g,full);
            }
            return;
        }
    }

    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if ((LONG)(now-g->last_order_ms)>2000) {
        wgp_issue_building_task(actor,&root,-1);
        g->last_order_ms=now;
    }
    snprintf(g->current_step,sizeof(g->current_step),"Making %s: %d/%d complete at %s",
             g->item,g->completed,g->quantity,
             root.building_name[0]?root.building_name:"production building");
    if (g->last_progress_ms && (LONG)(now-g->last_progress_ms)>WGP_STALL_MS) {
        char r[256];
        snprintf(r,sizeof(r),"%s exists but made no progress; it may be unpowered, full, occupied, or unable to receive inputs",
                 root.building_name[0]?root.building_name:"the required production building");
        wgp_goal_block(g,r);
    }
}

static void wgp_save(void)
{
    char path[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_work_goals.tsv")) return;
    FILE *f=fopen(path,"wb");
    if (!f) return;
    for (int i=0;i<WGP_MAX_GOALS;i++) {
        WgpGoal *g=&g_wgp_goals[i];
        if (!g->used) continue;
        wgp_clean(g->actor);
        wgp_clean(g->item);
        wgp_clean(g->dest_label);
        wgp_clean(g->current_step);
        wgp_clean(g->reason);
        char subbuf[4096]={0};
        for (int s=0;s<WGP_MAX_SUBSTATE;s++) {
            if (!g->subs[s].item[0]) continue;
            wgp_clean(g->subs[s].item);
            char part[192]={0};
            snprintf(part,sizeof(part),"%s=%d;",g->subs[s].item,g->subs[s].queued);
            if (strlen(subbuf)+strlen(part)<sizeof(subbuf)-1) strcat(subbuf,part);
        }
        fprintf(f,"%s\t%u\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%.3f\t%.3f\t%.3f\t%s\t%d\t%d\t%s\t%s\t%d\t%s\n",
            g->id,g->actor_serial,g->actor,g->item,g->quantity,g->baseline,g->completed,
            g->queued_root,g->has_dest,g->dest.x,g->dest.y,g->dest.z,g->dest_label,
            g->state,g->last_count,g->current_step,g->reason,g->report_triggered,subbuf);
    }
    fclose(f);
    g_wgp_dirty=0;
}
static void wgp_status_write(void)
{
    char path[MAX_PATH*2]={0}, tmp[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_work_goal.status")) return;
    snprintf(tmp,sizeof(tmp),"%s.tmp",path);
    FILE *f=fopen(tmp,"wb");
    if (!f) return;
    for (int i=0;i<WGP_MAX_GOALS;i++) {
        WgpGoal *g=&g_wgp_goals[i];
        if (!g->used) continue;
        fprintf(f,"%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n",
            g->id,g->actor,wgp_state_name(g->state),g->item,g->quantity,g->completed,
            g->dest_label,g->current_step,g->reason);
    }
    fclose(f);
    MoveFileExA(tmp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}

static void wgp_load(void)
{
    if (g_wgp_loaded) return;
    g_wgp_loaded=1;
    char path[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_work_goals.tsv")) return;
    FILE *f=fopen(path,"rb");
    if (!f) return;
    static char line[8192];
    while (fgets(line,sizeof(line),f)) {
        WgpGoal g;
        memset(&g,0,sizeof(g));
        g.baseline=-1;
        char *fields[19]={0};
        int n=0;
        char *p=line;
        while (n<19) {
            fields[n++]=p;
            char *t=strchr(p,'\t');
            if (!t) break;
            *t='\0';
            p=t+1;
        }
        if (n<17) continue;
        char *e=strpbrk(fields[n-1],"\r\n");
        if (e) *e='\0';
        strncpy(g.id,fields[0],sizeof(g.id)-1);
        g.actor_serial=(uint32_t)strtoul(fields[1],NULL,10);
        strncpy(g.actor,fields[2],sizeof(g.actor)-1);
        strncpy(g.item,fields[3],sizeof(g.item)-1);
        g.quantity=atoi(fields[4]);
        g.baseline=atoi(fields[5]);
        g.completed=atoi(fields[6]);
        g.queued_root=atoi(fields[7]);
        g.has_dest=atoi(fields[8]);
        g.dest.x=(float)atof(fields[9]);
        g.dest.y=(float)atof(fields[10]);
        g.dest.z=(float)atof(fields[11]);
        strncpy(g.dest_label,fields[12],sizeof(g.dest_label)-1);
        g.state=atoi(fields[13]);
        g.last_count=atoi(fields[14]);
        strncpy(g.current_step,fields[15],sizeof(g.current_step)-1);
        strncpy(g.reason,fields[16],sizeof(g.reason)-1);
        if (n>17) g.report_triggered=atoi(fields[17]);
        if (n>18 && fields[18]) {
            char *subp=fields[18];
            while (subp && *subp) {
                char *semi=strchr(subp,';');
                if (semi) *semi='\0';
                if (*subp) {
                    char *eq=strrchr(subp,'=');
                    if (eq) {
                        *eq='\0';
                        WgpSubstate *ss=wgp_substate(&g,subp);
                        if (ss) ss->queued=atoi(eq+1);
                    }
                }
                if (!semi) break;
                subp=semi+1;
            }
        }
        g.used=1;
        g.created_ms=GetTickCount();
        g.last_progress_ms=GetTickCount();
        for (int i=0;i<WGP_MAX_GOALS;i++) {
            if (!g_wgp_goals[i].used) {
                g_wgp_goals[i]=g;
                break;
            }
        }
    }
    fclose(f);
}

static void wgp_consume_requests(void *gw)
{
    char path[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_work_goal.request")) return;
    FILE *f=fopen(path,"rb");
    if (!f) return;
    char lines[8192]={0};
    size_t got=fread(lines,1,sizeof(lines)-1,f);
    fclose(f);
    DeleteFileA(path);
    if (!got) return;

    char *line=lines;
    while (line && *line) {
        char *next=strpbrk(line,"\r\n");
        if (next) {
            *next='\0';
            char *after=next+1;
            while (*after=='\r' || *after=='\n') after++;
            next=after;
        }
        char *fields[9]={0};
        int n=0;
        char *p=line;
        while (n<9 && p) {
            fields[n++]=p;
            char *t=strchr(p,'\t');
            if (!t) break;
            *t='\0';
            p=t+1;
        }
        if (n>=5) {
            WgpGoal *slot=NULL;
            for (int i=0;i<WGP_MAX_GOALS;i++)
                if (!g_wgp_goals[i].used) { slot=&g_wgp_goals[i]; break; }
            if (!slot) {
                for (int i=0;i<WGP_MAX_GOALS;i++)
                    if (g_wgp_goals[i].state!=0 && g_wgp_goals[i].state!=4) { slot=&g_wgp_goals[i]; break; }
            }
            if (!slot) {
                logline("[stobe] WORK_GOAL rejected: all goal slots are active");
            } else {
                memset(slot,0,sizeof(*slot));
                slot->used=1;
                slot->baseline=-1;
                strncpy(slot->id,fields[0],sizeof(slot->id)-1);
                slot->actor_serial=(uint32_t)strtoul(fields[1],NULL,10);
                strncpy(slot->actor,fields[2],sizeof(slot->actor)-1);
                strncpy(slot->item,fields[3],sizeof(slot->item)-1);
                slot->quantity=atoi(fields[4]);
                if (slot->quantity<1) slot->quantity=1;
                if (slot->quantity>1000) slot->quantity=1000;
                if (n>=9 && fields[5] && fields[5][0]) {
                    slot->has_dest=1;
                    strncpy(slot->dest_label,fields[5],sizeof(slot->dest_label)-1);
                    slot->dest.x=(float)atof(fields[6]);
                    slot->dest.y=(float)atof(fields[7]);
                    slot->dest.z=(float)atof(fields[8]);
                }
                slot->created_ms=GetTickCount();
                slot->last_progress_ms=GetTickCount();
                snprintf(slot->current_step,sizeof(slot->current_step),
                         "Accepted goal: make/obtain %d %s",slot->quantity,slot->item);
                g_wgp_dirty=1;
                logline("[stobe] WORK_GOAL accepted id=%s actor=%s serial=%u item=%s qty=%d dest=%s",
                        slot->id,slot->actor,slot->actor_serial,slot->item,
                        slot->quantity,slot->dest_label);
            }
        }
        line=next;
    }
    wgp_save();
    wgp_status_write();
}

static WgpGoal *wgp_find_id(const char *id)
{
    if(!id||!*id)return NULL;
    for(int i=0;i<WGP_MAX_GOALS;i++) if(g_wgp_goals[i].used&&!strcmp(g_wgp_goals[i].id,id)) return &g_wgp_goals[i];
    return NULL;
}

static void wgp_control_line(char *line);
static void wgp_controls(void)
{
    char path[MAX_PATH*2]={0};
    if(!stobe_mod_path(path,sizeof(path),"stobe_work_goal.control"))return;
    FILE *f=fopen(path,"rb");if(!f)return;
    char line[1024];
    int any=0;
    while(fgets(line,sizeof(line),f)){ wgp_control_line(line); any=1; }
    fclose(f);DeleteFileA(path);
    (void)any;
}

static void wgp_control_line(char *line)
{
    char *id=strtok(line,"\t\r\n");char *cmd=strtok(NULL,"\t\r\n");char *arg=strtok(NULL,"\t\r\n");
    if(!id||!cmd)return;
    WgpGoal *g=wgp_find_id(id);if(!g)return;
    if(!_stricmp(cmd,"PAUSE")&&g->state==0)g->state=4;
    else if(!_stricmp(cmd,"RESUME")&&(g->state==4||g->state==2)){
        if(g->state==2){g->reason[0]='\0';g->report_triggered=0;g->last_progress_ms=GetTickCount();}
        g->state=0;
    }
    else if(!_stricmp(cmd,"CANCEL"))g->state=3;
    else if(!_stricmp(cmd,"QUANTITY")&&arg){int q=atoi(arg);if(q>0&&q<=1000)g->quantity=q;else return;}
    else if(!_stricmp(cmd,"DESTINATION")&&arg){
        char buf[512]={0};strncpy(buf,arg,sizeof(buf)-1);
        char *a=buf,*b=strchr(a,'^'),*c=NULL,*d=NULL;
        if(!b)return;*b++='\0';c=strchr(b,'^');if(!c)return;*c++='\0';d=strchr(c,'^');if(!d)return;*d++='\0';
        strncpy(g->dest_label,a,sizeof(g->dest_label)-1);
        g->dest.x=(float)atof(b);g->dest.y=(float)atof(c);g->dest.z=(float)atof(d);g->has_dest=1;
        g->last_distance=0;g->last_progress_ms=GetTickCount();
    }
    else return;
    g_wgp_dirty=1;
}

static void wgp_maybe_trigger_report(void *gw, WgpGoal *g)
{
    if (!g->used || g->report_triggered || (g->state!=1 && g->state!=2)) return;
    void *actor=wgp_find_squad_actor(gw,g->actor_serial,g->actor);
    void *player=first_player_char(gw);
    Vec3 a={0,0,0}, p={0,0,0};
    if (!actor || !player || !char_position(actor,&a) || !char_position(player,&p)) return;
    if (wgp_distance(a,p)>180.0f) return;
    char flag[MAX_PATH*2]={0};
    if (!stobe_mod_path(flag,sizeof(flag),"lifelike_initiative.flag")) return;
    HANDLE h=CreateFileA(flag,GENERIC_WRITE,
                         FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                         NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if (h!=INVALID_HANDLE_VALUE) {
        CloseHandle(h);
        g->report_triggered=1;
        g_wgp_dirty=1;
    }
}

static void wgp_goal_tick_guarded(void *gw, WgpGoal *g)
{
    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0;
        wgp_goal_block(g, "a native game call faulted while working on this goal; stopped safely to protect the game");
        return;
    }
    guard_arm();
    wgp_goal_tick(gw, g);
    g_guard_armed = 0;
}

static void stobe_work_goal_tick(void *gw)
{
    DWORD now=GetTickCount();
    if (g_wgp_next_tick && (LONG)(now-g_wgp_next_tick)<0) return;
    g_wgp_next_tick=now+WGP_TICK_MS;
    wgp_load();
    wgp_consume_requests(gw);
    wgp_controls();

    uint32_t active_actors[WGP_MAX_GOALS]={0};
    int active_actor_count=0;
    for (int i=0;i<WGP_MAX_GOALS;i++) {
        WgpGoal *g=&g_wgp_goals[i];
        if (g->used && g->state==0) {
            int already_running=0;
            for (int j=0;j<active_actor_count;j++) {
                if (active_actors[j]==g->actor_serial) {
                    already_running=1;
                    break;
                }
            }
            if (!already_running) {
                active_actors[active_actor_count++]=g->actor_serial;
                wgp_goal_tick_guarded(gw,g);
            } else if (g->baseline<0) {
                snprintf(g->current_step,sizeof(g->current_step),
                         "Queued behind an earlier active work goal");
            }
        }
        wgp_maybe_trigger_report(gw,g);
    }
    wgp_status_write();
    if (g_wgp_dirty && (!g_wgp_next_save || (LONG)(now-g_wgp_next_save)>=0)) {
        wgp_save();
        g_wgp_next_save=now+3000;
    }
}
