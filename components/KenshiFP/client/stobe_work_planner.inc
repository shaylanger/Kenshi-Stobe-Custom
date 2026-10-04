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
/* Game-time budgets (bug 80): these were real-time values tuned while testing
 * at 10x; on the goal clock (bug 78) they must be 10x larger in game ms. */
#define WGP_STALL_MS 1800000
#define WGP_REORDER_MS 30000 /* bug 106: re-send the operate order only after 30 game s idle */
#define WGP_UNIT_MAX_MS 14400000 /* bug 93: most game time one unit may take while she stands at the machine */
#define WGP_OPERATE_NEAR 120.0f
#define WGP_DEP_STALL_MS 9000000
#define WGP_POWER_WAIT_MS 300000
#define WGP_TRAVEL_STALL_MS 2400000
#define WGP_ARRIVE_DIST 65.0f
#define WGP_SCAN_RADIUS 1400.0f

#define WGP_BF_MINE 1
#define WGP_BF_CRAFTING 10 /* item 93b: BF_CRAFTING (9 is BF_SHOP) */
#define WGP_BF_MINE_NATURAL 27 /* item 93b: BF_MINE_NATURAL (25 is BF_SKELETON_BED) */
#define WGP_TASK_COLLECT_OUTPUT 92

#define WGP_GETPROD_SYM "?_NV_getProductionBuilding@Building@@QEAAPEAVProductionBuilding@@XZ"
#define WGP_GETINV_BUILDING_SYM "?_NV_getInventory@Building@@QEBAPEAVInventory@@XZ"
#define WGP_ISPLAYER_BUILDING_SYM "?isThePlayer@Building@@QEBA_NXZ"
#define WGP_SPECIAL_SYM "?_NV_getSpecialFunction@Building@@QEBA?AW4BuildingFunction@@XZ"
#define WGP_AVAILABLE_CRAFTS_SYM "?getAvailableCrafts@CraftingBuilding@@QEAAXAEAV?$lektor@VGameDataGroup@@@@@Z"
#define WGP_ADD_CRAFT_SYM "?_addCraft@CraftingBuilding@@QEAAPEAVCraftingItem@@PEAVGameData@@0MVYesNoMaybe@@@Z"

typedef void *(*wgp_getprod_t)(void *);
typedef void *(*wgp_getinv_building_t)(void *);
typedef unsigned char (*wgp_isplayer_building_t)(void *);
typedef int (*wgp_special_t)(void *);
typedef void (*wgp_available_crafts_t)(void *, void *);
typedef void *(*wgp_add_craft_t)(void *, void *, void *, float, const int *); /* item 93c: YesNoMaybe by reference (MSVC x64, non-trivial copy ctor) */

typedef struct WgpGroup { void *g1; void *g2; } WgpGroup;
typedef struct WgpSubstate {
    char item[128];
    int queued;     /* crafts queued and not yet observed as finished */
    int last_have;  /* runtime only: count seen last tick (-1 = unknown) */
    int consumed;   /* Item 95, runtime only: units that disappeared (used by the goal's own crafts) */
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
    double created_gt;   /* in-game seconds when given (bug 83); 0 = unknown */
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
    void *rt_task_building; /* runtime only: building the last operate order was for */
    const void *rt_job_tasker; /* runtime only: the Kenshi job (Tasker) this goal added */
    uint32_t rt_job_serial;    /* runtime only: whose job list it is in */
    DWORD rt_end_ms;           /* runtime only: when the goal ended (label) */
    void *power_wait_building; /* runtime only: building we are waiting on for power */
    DWORD power_wait_ms;
    DWORD farm_dry_ms;          /* runtime only: farm missing an input nobody can bring */
    int haul_still;
    DWORD haul_next_ms;
    DWORD rt_unit_start_ms;    /* runtime only: since when she has been at the machine for this unit (bug 93) */
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

/* Goal clock (bug 78): real time x game speed (GameWorld::frameSpeedMult), so
 * waits, stalls and the decision rate cost the same game time at any speed,
 * and goals freeze while paused. Ticks still run at most every 50 ms real. */
#define STOBE_GOAL_MIN_TICK_REAL_MS 50
static DWORD g_sgc_real_last;
static double g_sgc_game_ms;
static float g_sgc_speed=1.0f;
static float stobe_game_speed(void *gw)
{
    if (!gw || !readable((void *)((uintptr_t)gw+GW_FRAMESPEED),4)) return 1.0f;
    float s=*(float *)((uintptr_t)gw+GW_FRAMESPEED);
    if (!(s>=0.0f) || s>100.0f) return 1.0f;
    return s;
}
static void stobe_game_clock_update(void *gw)
{
    DWORD now=GetTickCount();
    g_sgc_speed=stobe_game_speed(gw);
    if (!g_sgc_real_last) { g_sgc_real_last=now; g_sgc_game_ms=(double)now; return; }
    DWORD dt=now-g_sgc_real_last; g_sgc_real_last=now;
    if (dt>2000) dt=2000; /* loading screens, hitches */
    g_sgc_game_ms+=(double)dt*g_sgc_speed;
}
static DWORD stobe_game_ms(void)
{
    if (!g_sgc_real_last) return GetTickCount();
    return (DWORD)(unsigned long long)g_sgc_game_ms;
}

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
static int sgm_meal_tick(void *gw,uint32_t serial,const char *name,char *step,size_t stepsz); /* stobe_task_goals.inc */
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

/* Bug 125: lower-case letters/digits with single spaces ("Lorn [Hungry Bandit]"
 * -> "lorn hungry bandit"); the server's sanitizer strips the brackets. */
static void wgp_name_squash(const char *in, char *out, size_t outsz)
{
    size_t n=0; int space=0;
    for (; *in && n+2<outsz; in++) {
        unsigned char c=(unsigned char)*in;
        if (isalnum(c)) {
            if (space && n) out[n++]=' ';
            out[n++]=(char)tolower(c); space=0;
        } else space=1;
    }
    out[n]=0;
}

static int wgp_name_match(const char *actual, const char *query)
{
    char a[192]={0}, q[192]={0};
    if (!actual || !query || !*actual || !*query) return 0;
    strncpy(a,actual,sizeof(a)-1); strncpy(q,query,sizeof(q)-1);
    stobe_ascii_lower(a); stobe_ascii_lower(q);
    if (!strcmp(a,q)) return 3;
    if (strstr(a,q) || strstr(q,a)) return 2;
    {
        char sa[192], sq[192];
        wgp_name_squash(a,sa,sizeof(sa)); wgp_name_squash(q,sq,sizeof(sq));
        if (sa[0] && sq[0] && !strcmp(sa,sq)) return 3;
    }
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
    void *partial=NULL; int partials=0;
    for (uint32_t i=0;i<count;i++) {
        void *c=stuff[i];
        if (!char_valid(c) || !readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20)) continue;
        uint32_t *h=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
        if (serial && h[4]==serial) return c;
        if (!serial && name && *name) {
            char display[128]={0};
            if (stobe_copy_native_string((void *)((uintptr_t)c+0x18),display,sizeof(display))) {
                int m=wgp_name_match(display,name); /* bug 125: "Rovar Dust Bandit Bowman" */
                if (m==3) return c;
                if (m==2) { partial=c; partials++; }
            }
        }
    }
    return partials==1 ? partial : NULL;
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

/* Item 89: the game grows a full lektor with its own allocator (freeing our buffer): scan into
 * a static scratch lektor with plenty of spare room and copy out. Main thread only. */
#define WGP_SCAN_CAP 4096
static void *g_wgp_scan_buf[WGP_SCAN_CAP];

static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius);
static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    return wgp_scan_buildings_r(gw,actor,out,max,WGP_SCAN_RADIUS);
}

/* Item 93: radius as a parameter (a busy town fills the 1400 m scan) */
static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;
    if (max > WGP_SCAN_CAP/2) max = WGP_SCAN_CAP/2;
    Vec3 center={0,0,0};
    if (!char_position(actor,&center)) return 0;
    memset(g_wgp_scan_buf,0,sizeof(g_wgp_scan_buf));
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)WGP_SCAN_CAP; list.stuff=g_wgp_scan_buf;
    g_stobe_getobjects(gw,&list,&center,radius,0,max,actor);
    if (list.stuff!=g_wgp_scan_buf || list.count>(uint32_t)WGP_SCAN_CAP) {
        logline("[stobe] WGP_SCAN lektor grown (count=%u) -- result dropped",list.count);
        return 0;
    }
    int n=0;
    for (uint32_t i=0;i<list.count && n<max;i++) if (g_wgp_scan_buf[i]) out[n++]=g_wgp_scan_buf[i];
    return n;
}

static int g_wgp_count_scanned, g_wgp_count_inv; /* Item 99b: last count's sources (log only) */
static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius);
static int wgp_item_count_world(void *gw, void *actor, const char *query)
{
    int total=0;
    void *inv=g_stobe_getinv ? g_stobe_getinv(actor) : NULL;
    total += wgp_item_count_inventory(inv,query);
    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,buildings,WGP_MAX_BUILDINGS);
    /* Item 99b: a full town scan can miss the base chest next door: count within 300 m instead */
    if (n>=WGP_MAX_BUILDINGS) { memset(buildings,0,sizeof(buildings)); n=wgp_scan_buildings_r(gw,actor,buildings,WGP_MAX_BUILDINGS,300.0f); }
    g_wgp_count_scanned=n; g_wgp_count_inv=total;
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

static void *g_wgp_missing_buf[256]; /* item 90: room so the game never grows our buffer */
static int wgp_missing(void *prod, void **out, int max)
{
    typedef void (*fn_t)(void *, StobePtrLektor *);
    fn_t fn=(fn_t)wgp_vcall_ptr(prod,0x560);
    if (!fn || !out || max<1) return 0;
    memset(g_wgp_missing_buf,0,sizeof(g_wgp_missing_buf));
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=256; list.stuff=g_wgp_missing_buf;
    fn(prod,&list);
    if (list.stuff!=g_wgp_missing_buf || list.count>256) return 0;
    int n=0;
    for (uint32_t i=0;i<list.count && n<max;i++) if (g_wgp_missing_buf[i]) out[n++]=g_wgp_missing_buf[i];
    return n;
}

/* Bug 38: how many units of input `dep_gd` the machine eats for `outputs` units of
 * its product, from its consumption rates (input.rate / output.rate). Falls back
 * to 1:1 when the data can't be read. */
static int wgp_input_need(void *prod, const char *machine, void *dep_gd, int outputs)
{
    typedef int (*num_t)(void *);
    typedef void *(*get_t)(void *, int);
    if (outputs<1 || !prod || !dep_gd || !readable(prod,0x468)) return outputs;
    num_t nf=(num_t)wgp_vcall_ptr(prod,0x588);
    get_t gf=(get_t)wgp_vcall_ptr(prod,0x590);
    void *out=*(void **)((uintptr_t)prod+0x448);
    if (!nf || !gf || !readable(out,0x20)) return outputs;
    float orate=*(float *)((uintptr_t)out+4);
    if (!(orate>0.0f)) return outputs;
    int n=nf(prod);
    if (n<1 || n>8) return outputs;
    for (int i=0;i<n;i++) {
        void *ci=gf(prod,i);
        if (!ci || ci==out || !readable(ci,0x20)) continue;
        if (*(void **)((uintptr_t)ci+0x10)!=dep_gd) continue;
        float r=*(float *)((uintptr_t)ci+4);
        if (!(r>0.0f)) return outputs;
        float ratio=r/orate;
        if (ratio<0.05f || ratio>20.0f) return outputs;
        int need=(int)(outputs*ratio+0.999f);
        if (need<1) need=1;
        {
            static void *last_dep; static float last_ratio;
            if (last_dep!=dep_gd || last_ratio!=ratio) {
                char dn[128]={0}; wgp_name(dep_gd,dn,sizeof(dn));
                { /* Item 105: once per (machine, input, result) per 30 s, not every pass */
                    static unsigned s_ratio_key[8]; static DWORD s_ratio_ms[8]; static int s_ratio_next; int slot=-1;
                    unsigned k=(unsigned)(uintptr_t)prod ^ ((unsigned)(uintptr_t)dep_gd<<1) ^ ((unsigned)need<<7) ^ (unsigned)outputs;
                    for (int q=0;q<8;q++) if (s_ratio_key[q]==k) slot=q;
                    if (slot<0 || (LONG)(GetTickCount()-s_ratio_ms[slot])>30000) { if (slot<0) { slot=s_ratio_next; s_ratio_next=(s_ratio_next+1)%8; } s_ratio_key[slot]=k; s_ratio_ms[slot]=GetTickCount();
                    logline("[stobe] WORK_GOAL input ratio %s: %s x%.2f (in %.3f / out %.3f) -> %d for %d",
                        machine&&machine[0]?machine:"machine",dn,ratio,r,orate,need,outputs);
                    }
                }
                last_dep=dep_gd; last_ratio=ratio;
            }
        }
        return need;
    }
    return outputs;
}

static int wgp_find_producer_r(void *gw, void *actor, const char *query, WgpProducer *out, float radius, int *scanned, int diag);
/* Item 93: a full 1400 m scan in a town can miss the bench next door: retry within 300 m. */
static int wgp_find_producer(void *gw, void *actor, const char *query, WgpProducer *out)
{
    int scanned=0;
    int r=wgp_find_producer_r(gw,actor,query,out,WGP_SCAN_RADIUS,&scanned,0);
    if (!r && scanned>=WGP_MAX_BUILDINGS)
        r=wgp_find_producer_r(gw,actor,query,out,300.0f,&scanned,0);
    return r;
}

/* Item 93: what the planner saw, once per goal, when no producer was found */
static void wgp_log_producer_diag(void *gw, void *actor, const char *query)
{
    WgpProducer tmp; int scanned=0;
    wgp_find_producer_r(gw,actor,query,&tmp,WGP_SCAN_RADIUS,&scanned,1);
    logline("[stobe] WORK_DIAG no producer for %s: scanned=%d (cap %d) radius=1400",query,scanned,WGP_MAX_BUILDINGS);
    if (scanned>=WGP_MAX_BUILDINGS) {
        wgp_find_producer_r(gw,actor,query,&tmp,300.0f,&scanned,1);
        logline("[stobe] WORK_DIAG no producer for %s: scanned=%d radius=300",query,scanned);
    }
}

static int wgp_find_producer_r(void *gw, void *actor, const char *query, WgpProducer *out, float radius, int *scanned, int diag)
{
    if (!out || !wgp_resolve_exports()) return 0;
    memset(out,0,sizeof(*out));
    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings_r(gw,actor,buildings,WGP_MAX_BUILDINGS,radius);
    if (scanned) *scanned=n;
    int best=0;
    for (int i=0;i<n;i++) {
        void *b=buildings[i];
        if (!readable(b,0x80)) continue;
        int special=wgp_building_special(b);
        int allowed=g_wgp_isplayer_building(b) ||
            special==WGP_BF_MINE || special==WGP_BF_MINE_NATURAL;
        if (diag && special==WGP_BF_CRAFTING && !allowed) {
            char dn[160]={0}; wgp_name(*(void **)((uintptr_t)b+0x40),dn,sizeof(dn));
            logline("[stobe] WORK_DIAG bench %s skipped: not player-owned",dn);
        }
        if (!allowed) continue;
        void *prod=wgp_building_production(b);
        /* Item 93: a crafting bench whose data lacks 'is production building' has no production
         * object, but the bench is its own ProductionBuilding (CraftingBuilding : ProductionBuilding). */
        int prod_self=0;
        if (!prod && special==WGP_BF_CRAFTING) { prod=b; prod_self=1; }
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
            if (diag) {
                char c0[96]={0},c1[96]={0},c2[96]={0};
                if (count>0) wgp_name(groups[0].g1,c0,sizeof(c0));
                if (count>1) wgp_name(groups[1].g1,c1,sizeof(c1));
                if (count>2) wgp_name(groups[2].g1,c2,sizeof(c2));
                logline("[stobe] WORK_DIAG bench %s prod_self=%d crafts=%d (lektor %u) first: %s | %s | %s",
                        bname,prod_self,count,list.count,c0,c1,c2);
            }
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

/* ---- real Kenshi jobs for goal machines (round 18d) ---- */
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

/* Bug 74: Kenshi rebuilds the job list panel only when the selection changes,
 * so a goal job added/removed for the selected character stayed invisible until
 * the player clicked away and back. Replay that selection change once. */
#define KLIB_PI_UPDATESEL_SYM "?updatePlayerSelection@PlayerInterface@@QEAAXAEBVhand@@0@Z"
typedef void (*pi_updatesel_t)(void *, const void *, const void *);
static void *g_job_ui_actor;
static int g_job_ui_dead;

static void wgp_job_ui_refresh(void *gw)
{
    void *actor = g_job_ui_actor;
    g_job_ui_actor = NULL;
    if (!actor || g_job_ui_dead || !readable(gw, GW_PLAYER + 8)) return;
    static pi_updatesel_t fn;
    if (!fn) {
        HMODULE k = GetModuleHandleA("KenshiLib.dll");
        if (k) fn = (pi_updatesel_t)GetProcAddress(k, KLIB_PI_UPDATESEL_SYM);
        if (!fn) { g_job_ui_dead = 1; logline("[stobe] GOAL_JOB ui refresh export missing -- disabled"); return; }
    }
    void *pi = *(void **)((uintptr_t)gw + GW_PLAYER);
    unsigned char *sel = (unsigned char *)pi + PI_SELECTED_CHAR;
    uint32_t *ah = (uint32_t *)((uintptr_t)actor + CHAR_HANDLE + HAND_IDS);
    if (!readable(sel, HAND_IDS + 20) || !readable(ah, 20)) return;
    if (memcmp(sel + HAND_IDS, ah, 20) != 0) { logline("[stobe] GOAL_JOB ui refresh skipped: not the selected character"); return; }
    unsigned char cur[HAND_IDS + 20], none[HAND_IDS + 20];
    memcpy(cur, sel, sizeof(cur)); /* sel is live: keep a copy across the two calls */
    memcpy(none, sel, sizeof(none));
    ((uint32_t *)(none + HAND_IDS))[0] = 0xb; /* null hand: "nothing was selected" */
    if (setjmp(g_guard_jb)) {
        g_guard_armed = 0; g_job_ui_dead = 1;
        logline("[stobe] GOAL_JOB ui refresh faulted -- disabled for this session");
        return;
    }
    guard_arm();
    fn(pi, cur, none); /* bug 74: click away ... */
    fn(pi, none, cur); /* ... and back, like the manual workaround */
    g_guard_armed = 0;
    logline("[stobe] GOAL_JOB ui refresh replayed selection");
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
    g_job_ui_actor = actor;
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
        g_job_ui_actor = actor;
    } else {
        logline("[stobe] GOAL_JOB add did not create one job (before=%d after=%d)", n, after);
    }
}

/* Bug 106: is she doing nothing right now? (no task, NULL_TASK 0 or IDLE 14) */
static int wgp_actor_idle(void *actor)
{
    void *tholder = readable((void *)((uintptr_t)actor + CHAR_TASKHOLDER), 8)
        ? *(void **)((uintptr_t)actor + CHAR_TASKHOLDER) : NULL;
    if (!readable(tholder, TASK_CUR + 8)) return 1;
    void *cur = *(void **)((uintptr_t)tholder + TASK_CUR);
    if (!cur) return 1;
    if (!readable(cur, TASK_DESC + 8)) return 0;
    void *desc = *(void **)((uintptr_t)cur + TASK_DESC);
    if (!readable(desc, TASKDESC_TYPE + 4)) return 0;
    int t = *(int *)((uintptr_t)desc + TASKDESC_TYPE);
    return t == 0 || t == 14;
}

/* Operate order for a goal; clears the old order first when the target building changes. */
static int wgp_issue_goal_task(void *actor, WgpGoal *g, WgpProducer *p)
{
    if (!actor || !p || !p->building) return 0;
    if (g->rt_task_building != p->building) {
        wgp_job_release_actor(actor, g);
        wgp_job_add(actor, g, p);
        if (g->rt_task_building && stobe_resolve_fight_exports()) {
            void *orders = g_stobe_getorders(actor);
            if (orders && readable(orders, 8)) g_stobe_clear_orders(orders);
            logline("[stobe] WORK_GOAL switch id=%s -> %s", g->id,
                    p->building_name[0] ? p->building_name : "building");
        }
        g->rt_task_building = p->building;
    }
    return wgp_issue_building_task(actor, p, -1);
}

static WgpSubstate *wgp_substate(WgpGoal *g, const char *item)
{
    for (int i=0;i<WGP_MAX_SUBSTATE;i++)
        if (g->subs[i].item[0] && !_stricmp(g->subs[i].item,item)) return &g->subs[i];
    for (int i=0;i<WGP_MAX_SUBSTATE;i++) if (!g->subs[i].item[0]) {
        strncpy(g->subs[i].item,item,sizeof(g->subs[i].item)-1);
        g->subs[i].last_have=-1;
        g->subs[i].consumed=0;
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
        int ynm_maybe=2; /* item 93c: YesNoMaybe::MAYBE */
        void *ci=g_wgp_add_craft(p->building,p->craft_base,p->craft_material,0.0f,&ynm_maybe);
        if (!ci) break;
        made++;
    }
    return made;
}

static int wgp_feed_inputs(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* stobe_task_goals.inc */
static int wgp_feed_carried(void *gw, void *actor, WgpGoal *g, WgpProducer *p); /* m26 */

/* 1 when the building's UseableStuff reports it is out of power (same check as Stobe.dll's base snapshot). */
static int wgp_building_unpowered(void *building)
{
    typedef void *(*us_t)(void *);
    typedef float (*oop_t)(void *);
    us_t us_fn=(us_t)wgp_vcall_ptr(building,0x300);   /* Building::getUseableStuff */
    void *us=us_fn?us_fn(building):NULL;
    if (!us || !readable(us,8)) return 0;
    oop_t oop=(oop_t)wgp_vcall_ptr(us,0x4B8);          /* UseableStuff::isOutOfPower */
    return oop ? (oop(us)>0.0f) : 0;
}

static int wgp_icontains(const char *hay, const char *needle)
{
    if (!hay || !needle || !*needle) return 0;
    size_t n=strlen(needle);
    for (const char *h=hay; *h; h++) if (!_strnicmp(h,needle,n)) return 1;
    return 0;
}

/* 0 = powered, 1 = waiting for power (step set), -1 = give up (reason set) */
static int wgp_power_gate(WgpGoal *g, WgpProducer *p, char *reason, size_t reason_sz)
{
    if (!p || !p->building) return 0;
    /* Idle machines read as out of power: judge power only once she has been
     * ordered onto this machine and its inputs are loaded (bug 61). */
    if (g->rt_task_building!=p->building) return 0;
    {
        void *m[WGP_MAX_MISSING]={0};
        if (p->production && wgp_missing(p->production,m,WGP_MAX_MISSING)>0) return 0;
    }
    DWORD now=stobe_game_ms();
    if (!wgp_building_unpowered(p->building)) {
        if (g->power_wait_building==p->building) { g->power_wait_building=NULL; g->power_wait_ms=0; }
        return 0;
    }
    const char *bn=p->building_name[0]?p->building_name:"the production building";
    if (g->power_wait_building!=p->building || !g->power_wait_ms) {
        g->power_wait_building=p->building; g->power_wait_ms=now;
        logline("[stobe] WORK_GOAL power wait id=%s building=%s",g->id,bn);
    }
    if ((LONG)(now-g->power_wait_ms)>WGP_POWER_WAIT_MS) {
        snprintf(reason,reason_sz,"%s has no power (check generators, batteries and wiring)",bn);
        return -1;
    }
    snprintf(g->current_step,sizeof(g->current_step),"Waiting for power at %s",bn);
    g->last_progress_ms=now; /* the power wait has its own timer */
    return 1;
}

/* m25 (16-fullbase): the parent bench reports `dep` missing. If none is on hand or queued
 * but item-95 accounting (consumed) would call it satisfied, the recipe takes more than one
 * per unit: raise the need so at least one more gets queued, and name the missing input. */
static int wgp_missing_dep_need(void *gw, void *actor, WgpGoal *g, const char *parent,
                                const char *dep, int need)
{
    WgpSubstate *ss=NULL;
    for (int i=0;i<WGP_MAX_SUBSTATE;i++)
        if (g->subs[i].item[0] && !_stricmp(g->subs[i].item,dep)) { ss=&g->subs[i]; break; }
    int have=wgp_item_count_world(gw,actor,dep);
    int bumped=need;
    /* keep the shortfall >= 1 (queue one) and, once queued, keep the dep "not ready" so she
     * is sent to craft it instead of item-95 calling it satisfied */
    if (ss && have<=0 && ss->consumed>0 && ss->consumed>=need)
        bumped=ss->consumed+(ss->queued>0?ss->queued:1);
    static DWORD s_md_ms; static char s_md_key[192];
    char key[192]; snprintf(key,sizeof(key),"%s|%s|%d|%d",g->id,dep,need,bumped);
    if (strcmp(key,s_md_key) || (LONG)(GetTickCount()-s_md_ms)>10000) {
        s_md_ms=GetTickCount(); strncpy(s_md_key,key,sizeof(s_md_key)-1);
        logline("[stobe] WORK_STEP id=%s %s missing input %s (have=%d queued=%d consumed=%d) need %d%s",
                g->id,parent,dep,have,ss?ss->queued:0,ss?ss->consumed:0,bumped,
                bumped>need?" (m25: recipe uses more per unit, queue 1 more)":"");
    }
    return bumped;
}

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
    int found_p=wgp_find_producer(gw,actor,item,&p);
    /* Item 95: track a crafted intermediate from the first look (stock used now must not be re-queued later) */
    WgpSubstate *ss95=NULL;
    if (found_p && p.is_crafting) {
        ss95=wgp_substate(g,item);
        if (ss95 && ss95->last_have<0) ss95->last_have=have;
        if (ss95 && have+ss95->consumed>=need) return 1;
    }
    if (!found_p) {
        logline("[stobe] WORK_STEP id=%s %s have=%d need=%d (inventory %d, buildings %d of %d scanned) no producer (Item 99b)",
                g->id,item,have,need,g_wgp_count_inv,have-g_wgp_count_inv,g_wgp_count_scanned);
        int purchase=stg_request_purchase_fallback(gw,actor,g->actor_serial,g->actor,g->id,item,need,reason,reason_sz);
        if(purchase>0){
            snprintf(g->current_step,sizeof(g->current_step),"%s",reason);
            return 0;
        }
        if(purchase<0)return -1;
        snprintf(reason,reason_sz,"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",item);
        return -1;
    }

    /* Item 90: some of it is in stock but its producer has no power: use the stock first
     * (the parent machine gets fed what exists); the power wait applies once it's gone. */
    if (have>0 && p.building && wgp_building_unpowered(p.building)) {
        static DWORD s_stock_log_ms;
        if ((LONG)(GetTickCount()-s_stock_log_ms)>10000) {
            s_stock_log_ms=GetTickCount();
            logline("[stobe] WORK_STEP id=%s using %d/%d %s in stock (%s has no power)",
                    g->id,have,need,item,p.building_name[0]?p.building_name:"producer");
        }
        return 1;
    }

    char next_chain[WGP_MAX_DEPTH+2][128];
    memset(next_chain,0,sizeof(next_chain));
    for (int i=0;i<chain_n && i<WGP_MAX_DEPTH+1;i++)
        strncpy(next_chain[i],chain[i],sizeof(next_chain[i])-1);
    if (chain_n<WGP_MAX_DEPTH+1) strncpy(next_chain[chain_n],item,sizeof(next_chain[0])-1);
    int next_n=chain_n<WGP_MAX_DEPTH+1 ? chain_n+1 : chain_n;

    if (p.is_crafting) {
        WgpSubstate *ss=ss95?ss95:wgp_substate(g,item);
        if (!ss) {
            snprintf(reason,reason_sz,"too many distinct dependency items while trying to make %s",item);
            return -1;
        }
        /* Queue only the shortfall that is not already waiting at the bench
         * (Item 95: nor already used by this goal's crafts). */
        int shortfall=need-have-ss->queued-ss->consumed;
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
    if (miss>0 && wgp_feed_carried(gw,actor,g,&p)) return 0; /* m26 */
    for (int i=0;i<miss;i++) {
        char dep[128]={0};
        if (!wgp_name(missing[i],dep,sizeof(dep)) || !dep[0]) continue;
        int dneed=p.is_crafting?need:wgp_input_need(p.production,p.building_name,missing[i],need);
        dneed=wgp_missing_dep_need(gw,actor,g,item,dep,dneed);
        int r=wgp_ensure_item(gw,actor,g,dep,dneed,depth+1,next_chain,next_n,budget,reason,reason_sz);
        if (r<0) return -1;
        if (r==0) {
            if (strncmp(g->current_step,"Waiting",7) && strncmp(g->current_step,"Fetching",8) &&
                strncmp(g->current_step,"Carrying",8) && strncmp(g->current_step,"Loaded",6) &&
                strncmp(g->current_step,"Picked",6))
                snprintf(g->current_step,sizeof(g->current_step),"Obtaining %s for %s",dep,item);
            return 0;
        }
    }

    { int pw=wgp_power_gate(g,&p,reason,reason_sz); if (pw<0) return -1; if (pw>0) return 0; }
    if (wgp_feed_inputs(gw,actor,g,&p)) return 0;
    if (g->rt_task_building != p.building ||
        ((LONG)(stobe_game_ms()-g->last_order_ms)>WGP_REORDER_MS && wgp_actor_idle(actor))) { /* bug 106 */
        wgp_issue_goal_task(actor,g,&p);
        g->last_order_ms=stobe_game_ms();
    }
    if (wgp_icontains(p.building_name,"farm")) {
        void *fm[WGP_MAX_MISSING]={0};
        int fmiss=p.production?wgp_missing(p.production,fm,WGP_MAX_MISSING):0;
        if (fmiss>0) {
            /* feed_inputs found nothing to carry: e.g. the well is dry/unpowered (bug 70). */
            char dn[128]={0}; wgp_name(fm[0],dn,sizeof(dn));
            DWORD now2=stobe_game_ms();
            if (!g->farm_dry_ms) g->farm_dry_ms=now2;
            if ((LONG)(now2-g->farm_dry_ms)>2*WGP_POWER_WAIT_MS) {
                snprintf(reason,reason_sz,"%s has no %s and none is available to carry (check the well or water storage)",
                         p.building_name,dn[0]?dn:"input");
                return -1;
            }
            snprintf(g->current_step,sizeof(g->current_step),"Waiting: %s needs %s and none is available",p.building_name,dn[0]?dn:"input");
            g->last_progress_ms=now2;
            return 0;
        }
        g->farm_dry_ms=0;
        /* Inputs are in; the crop needs game time. Not a stall. */
        snprintf(g->current_step,sizeof(g->current_step),"Waiting for %s to grow %s",p.building_name,item);
        g->last_progress_ms=stobe_game_ms();
        return 0;
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

    DWORD now=stobe_game_ms();
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
    int completed_before95=g->completed;
    g->completed=current-g->baseline;
    if (g->completed<0) g->completed=0;
    if (g->completed>completed_before95) { /* Item 95: finished root units no longer need their inputs */
        int done=g->completed-completed_before95;
        for (int i=0;i<WGP_MAX_SUBSTATE;i++) {
            if (!g->subs[i].item[0]) continue;
            g->subs[i].consumed-=done; if (g->subs[i].consumed<0) g->subs[i].consumed=0;
        }
    }
    if (current!=g->last_count) {
        g->last_count=current; g->last_progress_ms=now; g->rt_unit_start_ms=0; g_wgp_dirty=1;
    }
    /* Finished intermediate crafts: new units observed come off the queued count.
     * (The old code zeroed the counter whenever any existed, which re-queued the
     * full amount again and again -- a runaway crafting queue.) */
    for (int i=0;i<WGP_MAX_SUBSTATE;i++) {
        WgpSubstate *ss=&g->subs[i];
        if (!ss->item[0]) continue;
        int have=wgp_item_count_world(gw,actor,ss->item);
        if (ss->last_have>=0 && have<ss->last_have) { /* Item 95: used by the goal's own crafts */
            ss->consumed+=ss->last_have-have;
            logline("[stobe] WORK_STEP id=%s %s used %d (consumed=%d queued=%d)",g->id,ss->item,ss->last_have-have,ss->consumed,ss->queued);
        }
        if (ss->queued<=0) { ss->last_have=have; continue; } /* only intermediates still being crafted below */
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

    static DWORD s_step_log_ms; static char s_step_log_id[64];
    int slog=strcmp(s_step_log_id,g->id)!=0||(LONG)(GetTickCount()-s_step_log_ms)>10000;
    if (slog) { s_step_log_ms=GetTickCount(); strncpy(s_step_log_id,g->id,sizeof(s_step_log_id)-1);
        logline("[stobe] WORK_STEP id=%s find_producer start item=%s have=%d/%d",g->id,g->item,g->completed,g->quantity); }
    WgpProducer root;
    int found_root=wgp_find_producer(gw,actor,g->item,&root);
    if (slog) logline("[stobe] WORK_STEP id=%s find_producer done found=%d building=%s crafting=%d",
                      g->id,found_root,found_root?root.building_name:"",found_root?root.is_crafting:0);
    if (!found_root) {
        char r[256]={0};
        int outstanding=g->quantity-g->completed;if(outstanding<1)outstanding=1;
        int purchase=stg_request_purchase_fallback(gw,actor,g->actor_serial,g->actor,g->id,g->item,outstanding,r,sizeof(r));
        if(purchase>0){snprintf(g->current_step,sizeof(g->current_step),"%s",r);return;}
        if(purchase<0){wgp_goal_block(g,r);return;}
        snprintf(r,sizeof(r),"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",g->item);
        wgp_log_producer_diag(gw,actor,g->item); /* Item 93 */
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
    if (slog) logline("[stobe] WORK_STEP id=%s missing inputs=%d queued_root=%d",g->id,miss,g->queued_root);
    char chain[WGP_MAX_DEPTH+2][128]; memset(chain,0,sizeof(chain));
    g->dep_sig=0;
    strncpy(chain[0],g->item,sizeof(chain[0])-1);
    int budget=0;
    if (miss>0 && wgp_feed_carried(gw,actor,g,&root)) return; /* m26 */
    for (int i=0;i<miss;i++) {
        char dep[128]={0}, reason[256]={0};
        if (!wgp_name(missing[i],dep,sizeof(dep)) || !dep[0]) continue;
        int outstanding=g->quantity-g->completed;
        if (outstanding<1) outstanding=1;
        if (!root.is_crafting) outstanding=wgp_input_need(root.production,root.building_name,missing[i],outstanding);
        outstanding=wgp_missing_dep_need(gw,actor,g,g->item,dep,outstanding);
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

    {
        char pr[200]={0};
        int pw=wgp_power_gate(g,&root,pr,sizeof(pr));
        if (pw<0) { char full[256]; snprintf(full,sizeof(full),"cannot make %s because %s",g->item,pr); wgp_goal_block(g,full); return; }
        if (pw>0) return;
    }
    if (wgp_feed_inputs(gw,actor,g,&root)) return;
    if (g->rt_task_building != root.building ||
        ((LONG)(now-g->last_order_ms)>WGP_REORDER_MS && wgp_actor_idle(actor))) { /* bug 106 */
        wgp_issue_goal_task(actor,g,&root);
        g->last_order_ms=now;
    }
    snprintf(g->current_step,sizeof(g->current_step),"Making %s: %d/%d complete at %s",
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
        fprintf(f,"%s\t%u\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%.3f\t%.3f\t%.3f\t%s\t%d\t%d\t%s\t%s\t%d\t%s\t%.0f\n",
            g->id,g->actor_serial,g->actor,g->item,g->quantity,g->baseline,g->completed,
            g->queued_root,g->has_dest,g->dest.x,g->dest.y,g->dest.z,g->dest_label,
            g->state,g->last_count,g->current_step,g->reason,g->report_triggered,subbuf,g->created_gt);
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
        char *fields[20]={0};
        int n=0;
        char *p=line;
        while (n<20) {
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
        if (n>19) g.created_gt=atof(fields[19]);
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
        g.created_ms=stobe_game_ms();
        g.last_progress_ms=stobe_game_ms();
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
                slot->created_ms=stobe_game_ms();
                slot->created_gt=g_sgt_now;
                slot->last_progress_ms=stobe_game_ms();
                slot->rt_seen_active=1; /* walk back + report even if it blocks at once (R2) */
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
        if(g->state==2){g->reason[0]='\0';g->report_triggered=0;g->last_progress_ms=stobe_game_ms();}
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
        g->last_distance=0;g->last_progress_ms=stobe_game_ms();
    }
    else return;
    g_wgp_dirty=1;
}

/* One line per ended goal for the server's report turn (round 17f). */
static void stobe_goal_report_append(const char *id, const char *actor, const char *type)
{
    char path[MAX_PATH*2]={0};
    if (!stobe_mod_path(path,sizeof(path),"stobe_goal_report.request")) return;
    FILE *f=fopen(path,"ab");
    if (!f) return;
    fprintf(f,"%s\t%s\t%s\n",id?id:"",actor?actor:"",type?type:"");
    fclose(f);
}

/* Who a goal worker walks back / reports to: the selected squad member, unless
 * that is the worker herself (selected to watch her, or the selection read fell
 * back to squad slot 0); then the nearest other conscious squad member (bug 75). */
static void *wgp_return_target(void *gw, void *actor)
{
    void *sel=first_player_char(gw);
    if (sel && sel!=actor && char_valid(sel)) return sel;
    if (!actor || !readable(gw, GW_PLAYER + 8)) return NULL;
    void *player=*(void **)((uintptr_t)gw+GW_PLAYER);
    if (!readable(player,PI_PLAYERCHARS+LEK_STUFF+8)) return NULL;
    uint32_t count=*(uint32_t *)((uintptr_t)player+PI_PLAYERCHARS+LEK_COUNT);
    void **stuff=*(void ***)((uintptr_t)player+PI_PLAYERCHARS+LEK_STUFF);
    if (!stuff || count>4096 || !readable(stuff,count*sizeof(void*))) return NULL;
    Vec3 a={0,0,0}; if (!char_position(actor,&a)) return NULL;
    void *best=NULL; float bd=1e30f;
    for (uint32_t i=0;i<count;i++) {
        void *c=stuff[i]; Vec3 p={0,0,0};
        if (c==actor || !char_valid(c) || !char_position(c,&p)) continue;
        int pr=char_prone_state(c); if (pr==2||pr==3||pr==4) continue;
        float d=wgp_distance(a,p); if (d<bd) { bd=d; best=c; }
    }
    return best;
}

#define WGP_REPORT_FALLBACK_MS 200000 /* report anyway if she never gets back */

static void wgp_maybe_trigger_report(void *gw, WgpGoal *g)
{
    if (!g->used || g->report_triggered || (g->state!=1 && g->state!=2)) return;
    void *actor=wgp_find_squad_actor(gw,g->actor_serial,g->actor);
    void *player=wgp_return_target(gw,actor);
    Vec3 a={0,0,0}, p={0,0,0};
    if (!actor || !player || !char_position(actor,&a) || !char_position(player,&p)) return;
    int late=g->rt_end_ms && (LONG)(stobe_game_ms()-g->rt_end_ms)>WGP_REPORT_FALLBACK_MS;
    if (wgp_distance(a,p)>70.0f && !late) return; /* report once she is back (bug 65) */
    char flag[MAX_PATH*2]={0};
    if (!stobe_mod_path(flag,sizeof(flag),"lifelike_initiative.flag")) return;
    HANDLE h=CreateFileA(flag,GENERIC_WRITE,
                         FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                         NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if (h!=INVALID_HANDLE_VALUE) {
        CloseHandle(h);
        stobe_goal_report_append(g->id,g->actor,"work");
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
    static DWORD real_last;
    DWORD real=GetTickCount();
    stobe_game_clock_update(gw);
    DWORD now=stobe_game_ms();
    if (g_wgp_next_tick && (LONG)(now-g_wgp_next_tick)<0) return;
    if (real_last && (LONG)(real-real_last)<STOBE_GOAL_MIN_TICK_REAL_MS) return;
    real_last=real;
    g_wgp_next_tick=now+WGP_TICK_MS;
    wgp_load();
    stobe_world_time_update(gw);
    wgp_consume_requests(gw);
    wgp_controls();
    for (int i=0;i<WGP_MAX_GOALS;i++) {
        WgpGoal *g=&g_wgp_goals[i];
        if (!g->used || (g->state!=0 && g->state!=4) || !stobe_goal_from_future(g->created_gt)) continue;
        g->state=3; g->report_triggered=1; g->rt_return_started=1; g->rt_seen_active=0;
        strncpy(g->reason,"given after the loaded save was made; dropped on load",sizeof(g->reason)-1);
        logline("[stobe] GOAL_LOAD dropped id=%s actor=%s given_at=%.0f world_now=%.0f",g->id,g->actor,g->created_gt,g_sgt_now);
        g_wgp_dirty=1;
    }

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
                if (sgm_meal_tick(gw,g->actor_serial,g->actor,g->current_step,sizeof(g->current_step)))
                    g->last_progress_ms=stobe_game_ms(); /* eating: the goal waits */
                else
                    wgp_goal_tick_guarded(gw,g);
                if (g->state!=0) g->rt_end_ms=stobe_game_ms();
            } else if (g->baseline<0) {
                snprintf(g->current_step,sizeof(g->current_step),
                         "Queued behind an earlier active work goal");
            }
        }
        if (g->used && g->state!=0 && g->rt_job_tasker) {
            /* goal ended or paused: take its job out of her list */
            if (!g->rt_end_ms) g->rt_end_ms=stobe_game_ms();
            wgp_job_release_actor(wgp_find_squad_actor(gw,g->actor_serial,g->actor),g);
            g->rt_task_building=NULL; /* re-add on resume */
        }
        wgp_maybe_trigger_report(gw,g);
    }
    wgp_job_ui_refresh(gw);
    wgp_status_write();
    if (g_wgp_dirty && (!g_wgp_next_save || (LONG)(real-g_wgp_next_save)>=0)) {
        wgp_save();
        g_wgp_next_save=real+3000;
    }
}
