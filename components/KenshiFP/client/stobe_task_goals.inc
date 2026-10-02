/* STOBE persistent non-production task goals.
 * Isolated from stobe_work_planner.inc so production dependency planning stays stable.
 */
#define STG_MAX_GOALS 20
#define STG_MAX_SEEN 64
#define STG_SCAN_RADIUS 220.0f
#define STG_TICK_MS 800
#define STG_STATE_ACTIVE 0
#define STG_STATE_COMPLETE 1
#define STG_STATE_BLOCKED 2
#define STG_STATE_CANCELLED 3
#define STG_STATE_PAUSED 4
#define STG_STATE_APPROVAL 5

#define STG_BF_RESOURCE_STORAGE 2
#define STG_BF_GENERAL_STORAGE 13
#define STG_TASK_FIRST_AID 25
#define STG_TASK_PATROL 22
#define STG_TASK_HOLD_POSITION 30
#define STG_TASK_BODYGUARD 45
#define STG_TASK_FIND_RESCUE 105
#define STG_TASK_FIND_BED_PUT_IN 106
#define STG_TASK_FIND_CAGE_PUT_IN 112
#define STG_TASK_RELEASE_PRISONER 110
#define STG_TASK_REPAIR 95
#define STG_TASK_JOB_BUILDER 125

#define STG_REMOVE_SYM "?_NV_removeItemDontDestroy_returnsItem@Inventory@@QEAAPEAVItem@@PEAV2@H_N@Z"
#define STG_ADD_SYM "?_NV_addItem@Inventory@@QEAA_NPEAVItem@@H_N1@Z"
#define STG_GIVE_SYM "?_NV_giveItem@Character@@QEAA_NPEAVItem@@_N1@Z"
#define STG_ISDEAD_SYM "?isDead@Character@@QEBA_NXZ"
#define STG_ISPLAYER_SYM "?isPlayerCharacter@Character@@QEBA_NXZ"
#define STG_ISANIMAL_SYM "?_NV_isAnimal@Character@@QEAAPEAVCharacterAnimal@@XZ"
#define STG_ISINJURED_SYM "?isInjured@Character@@QEBA_N_N@Z"
#define STG_TAKE_STACK_SYM "?takeItem_EntireStack@Inventory@@QEAA_NPEAVItem@@@Z"
#define STG_ON_GROUND_SYM "?onGround@InventoryItemBase@@QEBA_NXZ"
#define STG_NEEDED_MATS_SYM "?getNeededMats@ConstructionState@Building@@QEAAXAEAV?$lektor@PEAVBuildMaterial@ConstructionState@Building@@@@@Z"

typedef void *(*stg_remove_t)(void *, void *, int, int);
typedef unsigned char (*stg_add_t)(void *, void *, int, int, int);
typedef unsigned char (*stg_give_t)(void *, void *, int, int);
typedef unsigned char (*stg_boolchar_t)(void *);
typedef void *(*stg_isanimal_t)(void *);
typedef void *(*stg_shop_ctor_t)(void *, void *);
typedef void (*stg_shop_dtor_t)(void *);
typedef void *(*stg_shop_inv_t)(void *);
typedef void *(*stg_buy_item_t)(void *, void *, void *);
typedef int (*stg_get_money_t)(void *);
typedef unsigned char (*stg_is_trader_t)(void *);
typedef unsigned char (*stg_is_injured_t)(void *, int);
typedef int (*stg_take_stack_t)(void *, void *);
typedef unsigned char (*stg_on_ground_t)(void *);
typedef void (*stg_needed_mats_t)(void *, void *);

#define STG_SHOP_CTOR_SYM "?_CONSTRUCTOR@ShopTrader@@QEAAPEAV1@PEAVCharacter@@@Z"
#define STG_SHOP_DTOR_SYM "?_DESTRUCTOR@ShopTrader@@QEAAXXZ"
#define STG_SHOP_INV_SYM "?_NV_getInventory@ShopTrader@@QEBAPEAVInventory@@XZ"
#define STG_BUY_ITEM_SYM "?buyItem@Inventory@@QEAAPEAVItem@@PEAV2@PEAVRootObject@@@Z"
#define STG_GET_MONEY_SYM "?_NV_getMoney@Character@@QEBAHXZ"
#define STG_IS_TRADER_SYM "?isATrader@Character@@QEBA_NXZ"

typedef struct StgGoal {
    int used;
    char id[64];
    uint32_t actor_serial;
    char actor[128];
    char kind[40];
    char item[128];
    char target[128];
    char destination[128];
    int has_dest;
    Vec3 dest;
    float last_distance;
    int quantity;
    int completed;
    int state;
    int store_after;
    int minimum_stock;
    int explicit_purchase;
    int approved_purchase;
    int max_spend;
    int spent;
    DWORD created_ms;
    double created_gt;   /* in-game seconds when given (bug 83) */
    DWORD last_action_ms;
    DWORD last_progress_ms;
    uint32_t seen[STG_MAX_SEEN];
    int seen_count;
    char current_step[220];
    char reason[320];
    int report_triggered;
    int rt_seen_active;     /* runtime only: was ACTIVE this session */
    int rt_return_started;  /* runtime only: walk-back already requested */
    float walk_last_dist;   /* runtime only: walking to a storage building */
    DWORD rt_end_ms;        /* runtime only: when the goal ended (label) */
    Vec3 patrol_center;     /* runtime only: custom patrol loop */
    int patrol_init;
    int patrol_idx;
    int walk_still;
    DWORD walk_next_ms;
} StgGoal;

static StgGoal g_stg_goals[STG_MAX_GOALS];
static int g_stg_loaded;
static DWORD g_stg_next_tick;
static DWORD g_stg_next_save;
static int g_stg_dirty;
static int g_stg_loot_no_room; /* bug 111: a hand-over failed for lack of room */
static stg_remove_t g_stg_remove;
static stg_add_t g_stg_add;
static stg_give_t g_stg_give;
static stg_boolchar_t g_stg_isdead;
static stg_boolchar_t g_stg_isplayer;
static stg_isanimal_t g_stg_isanimal;
static stg_shop_ctor_t g_stg_shop_ctor;
static stg_shop_dtor_t g_stg_shop_dtor;
static stg_shop_inv_t g_stg_shop_inv;
static stg_buy_item_t g_stg_buy_item;
static stg_get_money_t g_stg_get_money;
static stg_is_trader_t g_stg_is_trader;
static stg_is_injured_t g_stg_is_injured;
static stg_take_stack_t g_stg_take_stack;
static stg_on_ground_t g_stg_on_ground;
static stg_needed_mats_t g_stg_needed_mats;

static int stg_char_name(void *c,char *out,size_t outsz);
static int stg_at_destination(void *actor,StgGoal *g);

static int stg_exports(void)
{
    if (!wgp_resolve_exports()) return 0;
    HMODULE k=GetModuleHandleA("KenshiLib.dll");
    if (!k) return 0;
    /* was only resolved by the equipment code: a goal step right after a load
     * called it NULL (crash 2026-10-01 14:18, sgm_meal_tick) */
    if (!g_stobe_getinv) g_stobe_getinv=(stobe_getinv_t)GetProcAddress(k,KLIB_GETINV_SYM);
    if (!g_stobe_getinv) return 0;
    if (!g_stg_remove) g_stg_remove=(stg_remove_t)GetProcAddress(k,STG_REMOVE_SYM);
    if (!g_stg_add) g_stg_add=(stg_add_t)GetProcAddress(k,STG_ADD_SYM);
    if (!g_stg_give) g_stg_give=(stg_give_t)GetProcAddress(k,STG_GIVE_SYM);
    if (!g_stg_isdead) g_stg_isdead=(stg_boolchar_t)GetProcAddress(k,STG_ISDEAD_SYM);
    if (!g_stg_isplayer) g_stg_isplayer=(stg_boolchar_t)GetProcAddress(k,STG_ISPLAYER_SYM);
    if (!g_stg_isanimal) g_stg_isanimal=(stg_isanimal_t)GetProcAddress(k,STG_ISANIMAL_SYM);
    if (!g_stg_shop_ctor) g_stg_shop_ctor=(stg_shop_ctor_t)GetProcAddress(k,STG_SHOP_CTOR_SYM);
    if (!g_stg_shop_dtor) g_stg_shop_dtor=(stg_shop_dtor_t)GetProcAddress(k,STG_SHOP_DTOR_SYM);
    if (!g_stg_shop_inv) g_stg_shop_inv=(stg_shop_inv_t)GetProcAddress(k,STG_SHOP_INV_SYM);
    if (!g_stg_buy_item) g_stg_buy_item=(stg_buy_item_t)GetProcAddress(k,STG_BUY_ITEM_SYM);
    if (!g_stg_get_money) g_stg_get_money=(stg_get_money_t)GetProcAddress(k,STG_GET_MONEY_SYM);
    if (!g_stg_is_trader) g_stg_is_trader=(stg_is_trader_t)GetProcAddress(k,STG_IS_TRADER_SYM);
    if (!g_stg_is_injured) g_stg_is_injured=(stg_is_injured_t)GetProcAddress(k,STG_ISINJURED_SYM);
    if (!g_stg_take_stack) g_stg_take_stack=(stg_take_stack_t)GetProcAddress(k,STG_TAKE_STACK_SYM);
    if (!g_stg_on_ground) g_stg_on_ground=(stg_on_ground_t)GetProcAddress(k,STG_ON_GROUND_SYM);
    if (!g_stg_needed_mats) g_stg_needed_mats=(stg_needed_mats_t)GetProcAddress(k,STG_NEEDED_MATS_SYM);
    return g_stg_remove && g_stg_add && g_stg_give && g_stg_isdead && g_stg_isplayer;
}

static const char *stg_state_name(int s)
{
    switch(s){
        case STG_STATE_COMPLETE:return "COMPLETE";
        case STG_STATE_BLOCKED:return "BLOCKED";
        case STG_STATE_CANCELLED:return "CANCELLED";
        case STG_STATE_PAUSED:return "PAUSED";
        case STG_STATE_APPROVAL:return "WAITING_APPROVAL";
        default:return "ACTIVE";
    }
}

static void stg_clean(char *s)
{
    if(!s)return;
    for(;*s;s++) if(*s=='\t'||*s=='\r'||*s=='\n'||*s=='|') *s=' ';
}

static uint32_t stg_serial(void *c)
{
    if(!c||!readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20)) return 0;
    uint32_t *h=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
    return h[4];
}

static int stg_seen(StgGoal *g,uint32_t serial)
{
    for(int i=0;i<g->seen_count;i++) if(g->seen[i]==serial) return 1;
    return 0;
}

static void stg_mark_seen(StgGoal *g,uint32_t serial)
{
    if(!serial||stg_seen(g,serial))return;
    if(g->seen_count<STG_MAX_SEEN) g->seen[g->seen_count++]=serial;
}

static int stg_item_matches(void *item,const char *query)
{
    if(!item||!query||!*query||!readable(item,0x139)) return 0;
    char q[128]={0}; strncpy(q,query,sizeof(q)-1); stobe_ascii_lower(q);
    int fn=*(int *)((uintptr_t)item+0x124);
    void *gd=stobe_item_gamedata(item);
    int type=-1;
    if(gd&&readable((void *)((uintptr_t)gd+0x50),4)) type=*(int *)((uintptr_t)gd+0x50);
    if(!strcmp(q,"all")||!strcmp(q,"everything")||!strcmp(q,"loot")||!strcmp(q,"items")) return 1;
    if(!strcmp(q,"weapon")||!strcmp(q,"weapons")) return type==2||fn==5;
    if(!strcmp(q,"armor")||!strcmp(q,"armour")||!strcmp(q,"clothing")||!strcmp(q,"gear")) return type==3||fn==6;
    if(!strcmp(q,"food")||!strcmp(q,"food items")) return fn==3||fn==15;
    if(!strcmp(q,"medical")||!strcmp(q,"medkit")||!strcmp(q,"medkits")||!strcmp(q,"first aid")) return fn==1||fn==2||fn==12;
    if(!strcmp(q,"ammo")||!strcmp(q,"ammunition")||!strcmp(q,"bolts")) return fn==16;
    char n[160]={0};
    return wgp_name(gd,n,sizeof(n)) && wgp_name_match(n,query)>0;
}

static int stg_count_matching(void *inv,const char *query)
{
    if(!inv||!readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor)))return 0;
    StobePtrLektor *l=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if(!l->stuff||l->count>4096||!readable(l->stuff,l->count*sizeof(void*)))return 0;
    int total=0;
    for(uint32_t i=0;i<l->count;i++){
        void *it=l->stuff[i];
        if(!stg_item_matches(it,query))continue;
        int q=*(int *)((uintptr_t)it+0x12C); total+=q>0?q:1;
    }
    return total;
}

static void *stg_first_matching(void *inv,const char *query)
{
    if(!inv||!readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor)))return NULL;
    StobePtrLektor *l=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if(!l->stuff||l->count>4096||!readable(l->stuff,l->count*sizeof(void*)))return NULL;
    for(uint32_t i=0;i<l->count;i++) if(stg_item_matches(l->stuff[i],query)) return l->stuff[i];
    return NULL;
}

static void *stg_trade_matching_stack(void *inv,const char *query,int max_units,int *stack_out)
{
    if(stack_out)*stack_out=0;
    if(!inv||!readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor)))return NULL;
    StobePtrLektor *l=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if(!l->stuff||l->count>4096||!readable(l->stuff,l->count*sizeof(void*)))return NULL;
    void *best=NULL;int best_stack=0;
    for(uint32_t i=0;i<l->count;i++){
        void *it=l->stuff[i];
        if(!stg_item_matches(it,query))continue;
        int stack=readable((void *)((uintptr_t)it+0x12C),4)?*(int *)((uintptr_t)it+0x12C):1;
        if(stack<1)stack=1;
        if(max_units>0&&stack>max_units)continue;
        if(!best||stack>best_stack){best=it;best_stack=stack;}
    }
    if(best&&stack_out)*stack_out=best_stack;
    return best;
}

static int stg_transfer_inventory(void *src_inv,void *dst_inv,const char *query,int maxqty)
{
    if(!src_inv||!dst_inv||maxqty<=0||!stg_exports())return 0;
    int moved=0,guard=0;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src_inv,query);
        if(!it)break;
        int avail=readable((void *)((uintptr_t)it+0x12C),4)?*(int *)((uintptr_t)it+0x12C):1;
        if(avail<1)avail=1;
        int take=maxqty-moved; if(take>avail)take=avail;
        void *det=g_stg_remove(src_inv,it,take,take<avail?1:0); /* item 42 */
        if(!det)break;
        int actual=readable((void *)((uintptr_t)det+0x12C),4)?*(int *)((uintptr_t)det+0x12C):take;
        if(actual<1)actual=take;
        if(!g_stg_add(dst_inv,det,actual,0,0)){
            g_stg_add(src_inv,det,actual,1,0);
            break;
        }
        moved+=actual;
    }
    return moved;
}

static int stg_transfer_to_character(void *src_inv,void *dst_char,const char *query,int maxqty)
{
    if(!src_inv||!dst_char||maxqty<=0||!stg_exports())return 0;
    int moved=0,guard=0,cap=0;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src_inv,query);
        if(!it)break;
        int avail=*(int *)((uintptr_t)it+0x12C); if(avail<1)avail=1;
        int take=maxqty-moved; if(take>avail)take=avail;
        if(cap>0&&take>cap)take=cap;
        /* item 42: a partial take needs returnCopyIfSomeLeft, else it returns NULL */
        void *det=g_stg_remove(src_inv,it,take,take<avail?1:0);
        if(!det){logline("[stobe] WORK_GOAL haul: could not split %d %s (stack %d)",take,query,avail);break;}
        int actual=*(int *)((uintptr_t)det+0x12C); if(actual<1)actual=take;
        /* item 42: her inventory's addItem, not Character::giveItem: giveItem reported
         * failure yet handed the stones over (then they went back to the mine too) */
        void *dinv=g_stobe_getinv(dst_char);
        if(!(dinv&&g_stg_add(dinv,det,actual,0,0))){
            /* addItem puts in what fits and leaves the rest in the stack */
            int rem=readable((void *)((uintptr_t)det+0x12C),4)?*(int *)((uintptr_t)det+0x12C):actual;
            if(rem>=0&&rem<actual){
                moved+=actual-rem;
                if(rem>0)g_stg_add(src_inv,det,rem,1,0);
                break; /* her pack is full now */
            }
            g_stg_add(src_inv,det,actual,1,0);
            if(actual>1){cap=actual/2;continue;} /* item 42: didn't fit; try half as many */
            logline("[stobe] WORK_GOAL haul: 1 %s does not fit in her pack",query);
            break;
        }
        moved+=actual;
    }
    return moved;
}

/* Bug 108: worn items aren't in Inventory::_allItems; they sit in the
 * equipment sections. sectionsInSearchOrder lektor @0x68; each
 * InventorySection holds a vector<SectionItem> @0x40 (first, last), 0x10 per
 * entry with the Item* first. Returns the first worn item matching query. */
static void *stg_first_worn_matching(void *inv,const char *query)
{
    if(!inv||!readable((void *)((uintptr_t)inv+0x68),sizeof(StobePtrLektor)))return NULL;
    StobePtrLektor *secs=(StobePtrLektor *)((uintptr_t)inv+0x68);
    if(!secs->stuff||secs->count>256||!readable(secs->stuff,secs->count*sizeof(void*)))return NULL;
    for(uint32_t s=0;s<secs->count;s++){
        void *sec=secs->stuff[s];
        if(!sec||!readable((void *)((uintptr_t)sec+0x40),16))continue;
        uintptr_t first=*(uintptr_t *)((uintptr_t)sec+0x40),last=*(uintptr_t *)((uintptr_t)sec+0x48);
        if(!first||last<first||(last-first)>0x10*512||!readable((void *)first,last-first))continue;
        for(uintptr_t e=first;e<last;e+=0x10){
            void *it=*(void **)e;
            if(!it||!readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1))continue;
            if(!*(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED))continue;
            if(stg_item_matches(it,query))return it;
        }
    }
    return NULL;
}

static int stg_transfer_char_to_char(void *src_char,void *dst_char,const char *query,int maxqty)
{
    if(!src_char||!dst_char||maxqty<=0||!stg_exports())return 0;
    void *src=g_stobe_getinv(src_char);
    if(!src)return 0;
    int moved=0,guard=0;
    int pr=char_prone_state(src_char);
    int body=(g_stg_isdead&&g_stg_isdead(src_char))||pr==2||pr==3||pr==4;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src,query);
        if(!it&&body)it=stg_first_worn_matching(src,query); /* bug 108 */
        if(!it)break;
        int worn=readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED);
        void *direct=NULL;
        if(worn&&body){ /* bug 114: unequip into a full body bag drops big weapons on the ground */
            int availw=*(int *)((uintptr_t)it+0x12C);if(availw<1)availw=1;
            int takew=maxqty-moved;if(takew>availw)takew=availw;
            direct=g_stg_remove(src,it,takew,0);
            if(direct)logline("[stobe] TASK_GOAL loot worn item straight from body");
        }
        if(direct){
            int actual=*(int *)((uintptr_t)direct+0x12C);if(actual<1)actual=1;
            if(!g_stg_give(dst_char,direct,0,0)){g_stg_add(src,direct,actual,1,0);g_stg_loot_no_room=1;break;}
            moved+=actual;
            continue;
        }
        if(worn){
            if(!stobe_unequip_item(src_char,it)){
                /* Bug 108: bodies can't unequip; take worn gear straight out of a
                 * dead or downed body's inventory, as the loot screen does. */
                if(!body)break; /* a standing character keeps what it wears */
                logline("[stobe] TASK_GOAL loot worn item from body (unequip refused, taking it directly)");
            }
        }
        int avail=*(int *)((uintptr_t)it+0x12C);if(avail<1)avail=1;
        int take=maxqty-moved;if(take>avail)take=avail;
        void *det=g_stg_remove(src,it,take,take<avail?1:0);if(!det)break; /* item 42 */
        int actual=*(int *)((uintptr_t)det+0x12C);if(actual<1)actual=take;
        if(!g_stg_give(dst_char,det,0,0)){g_stg_add(src,det,actual,1,0);g_stg_loot_no_room=1;break;}
        moved+=actual;
    }
    return moved;
}

static int stg_loot_from_character(void *src_char,void *dst_char,const char *query,int maxqty)
{
    return stg_transfer_char_to_char(src_char,dst_char,query,maxqty);
}

static int stg_scan_chars(void *gw,void *actor,void **out,int max)
{
    if(!gw||!actor||!out||max<1)return 0;
    if(!g_stobe_getchars){
        HMODULE k=GetModuleHandleA("KenshiLib.dll");
        if(k)g_stobe_getchars=(stobe_getchars_t)GetProcAddress(k,KLIB_GETCHARS_SYM);
    }
    if(!g_stobe_getchars)return 0;
    Vec3 c={0,0,0}; if(!char_position(actor,&c))return 0;
    StobePtrLektor l; memset(&l,0,sizeof(l)); l.max_size=max; l.stuff=out;
    g_stobe_getchars(gw,&l,&c,STG_SCAN_RADIUS,0,0,max,max,actor);
    if(!l.stuff||l.count>(uint32_t)max)return 0;
    int n=(int)l.count;
    /* Dead bodies may not come back from the character sphere search (bug 68):
     * merge the generic object search for CHARACTER (itemType 1). */
    if(g_stobe_getobjects&&n<max){
        void *extra[128]={0};
        StobePtrLektor l2; memset(&l2,0,sizeof(l2)); l2.max_size=128; l2.stuff=extra;
        g_stobe_getobjects(gw,&l2,&c,STG_SCAN_RADIUS,1,128,actor);
        if(l2.stuff&&l2.count<=128){
            for(uint32_t i=0;i<l2.count&&n<max;i++){
                void *x=extra[i];int dup=0;
                if(!x)continue;
                for(int j=0;j<n;j++)if(out[j]==x){dup=1;break;}
                if(!dup)out[n++]=x;
            }
        }
    }
    return n;
}

static int stg_character_enemy(void *actor,void *candidate)
{
    typedef int (*fn_t)(void *,void *,int);
    static fn_t fn;
    if(!fn){HMODULE k=GetModuleHandleA("KenshiLib.dll");if(k)fn=(fn_t)GetProcAddress(k,"?_NV_isEnemy@Character@@QEAA_NPEAV1@_N@Z");}
    return fn ? (fn(actor,candidate,1)&0xFF)!=0 : 0;
}

/* Bug 101: lower-case, punctuation/brackets -> one space ("Pax [Hungry Bandit]" -> "pax hungry bandit"). */
static void stg_norm_name(char *s)
{
    char *w=s;int sp=1;
    for(char *r=s;*r;r++){
        unsigned char ch=(unsigned char)*r;
        if(isalnum(ch)){*w++=(char)tolower(ch);sp=0;}
        else if(!sp){*w++=' ';sp=1;}
    }
    if(w>s&&w[-1]==' ')w--;
    *w='\0';
}

static int stg_valid_downed(void *actor,void *c,const char *filter)
{
    if(!c||!char_valid(c)||!stg_exports())return 0;
    if(g_stg_isplayer(c))return 0;
    int dead=g_stg_isdead(c);
    int prone=char_prone_state(c);
    if(!dead && prone!=2 && prone!=3 && prone!=4)return 0;

    if(filter&&*filter){
        char f[128]={0};strncpy(f,filter,sizeof(f)-1);stobe_ascii_lower(f);
        int animal=g_stg_isanimal && g_stg_isanimal(c)!=NULL;
        char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
        char cnlow[128]={0};strncpy(cnlow,cn,sizeof(cnlow)-1);stobe_ascii_lower(cnlow);

        if(!strcmp(f,"animal")||!strcmp(f,"animals")) return animal;
        if(!strcmp(f,"goat")||!strcmp(f,"goats")) return animal && strstr(cnlow,"goat")!=NULL;
        if(!strcmp(f,"humanoid")) return !animal;
        if(!strcmp(f,"enemy")||!strcmp(f,"enemies")||!strcmp(f,"hostile")||!strcmp(f,"hostiles")||
           !strcmp(f,"raider")||!strcmp(f,"raiders"))
            return !animal && stg_character_enemy(actor,c);
        stg_norm_name(f);stg_norm_name(cnlow);
        if(!*f) return 0;
        if(strstr(cnlow,f)==NULL){ /* "bandits" vs "[Hungry Bandit]": try the singular */
            size_t fl=strlen(f);
            if(fl<4||f[fl-1]!='s') return 0;
            f[fl-1]='\0';
            if(strstr(cnlow,f)==NULL) return 0;
        }
    }
    return 1;
}

static void *stg_find_storage(void *gw,void *actor,const char *query,int need_space_for_item)
{
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    for(int i=0;i<n;i++){
        void *x=b[i]; if(!x)continue;
        int sp=wgp_building_special(x);
        if(sp!=STG_BF_RESOURCE_STORAGE&&sp!=STG_BF_GENERAL_STORAGE)continue;
        if(!g_wgp_isplayer_building(x))continue;
        if(query&&*query){
            char name[160]={0};void *gd=*(void **)((uintptr_t)x+0x40);
            wgp_name(gd,name,sizeof(name));
            if(wgp_name_match(name,query)<=0 && strcasecmp(query,"storage") && strcasecmp(query,"put away"))continue;
        }
        void *inv=wgp_building_inventory(x);
        if(inv)return inv;
    }
    return NULL;
}

/* ---- work-goal input hauling (round 17c, bug 47) ---- */
#define WGP_HAUL_REACH 45.0f
#define WGP_HAUL_NEAR 160.0f
#define WGP_HAUL_BATCH 10

/* 1 = arrived (or as close as pathing gets), 0 = still walking */
static int wgp_haul_walk(void *actor,WgpGoal *g,Vec3 target,float dist,DWORD now)
{
    if(dist<=WGP_HAUL_REACH){g->haul_still=0;g->haul_last_dist=0;return 1;}
    if(g->haul_last_dist<=0||dist<g->haul_last_dist-3.0f){g->haul_last_dist=dist;g->haul_still=0;g->last_progress_ms=now;}
    else g->haul_still++;
    if(dist<=WGP_HAUL_NEAR&&g->haul_still>=4){g->haul_still=0;g->haul_last_dist=0;return 1;}
    if((LONG)(now-g->haul_next_ms)>=0){try_move_to_pos(actor,&target);g->haul_next_ms=now+3000;}
    return 0;
}

static void *g_haul_fail_goal; static int g_haul_fails; /* bug 121 / item 42 */

/* 1 = hauling in progress this tick (caller must not issue operate), 0 = nothing to haul */
static int wgp_feed_inputs(void *gw,void *actor,WgpGoal *g,WgpProducer *p)
{
    if(!p||!p->building||!p->production||!stg_exports())return 0;
    void *missing[WGP_MAX_MISSING]={0};
    int miss=wgp_missing(p->production,missing,WGP_MAX_MISSING);
    if(miss<=0)return 0;
    void *ainv=g_stobe_getinv(actor);
    Vec3 apos={0,0,0};if(!ainv||!char_position(actor,&apos))return 0;
    Vec3 mpos=*(Vec3 *)((uintptr_t)p->building+0x48);
    void *minv=wgp_building_inventory(p->building);
    const char *mname=p->building_name[0]?p->building_name:"the machine";
    DWORD now=stobe_game_ms();
    for(int i=0;i<miss;i++){
        char dep[128]={0};
        if(!wgp_name(missing[i],dep,sizeof(dep))||!dep[0])continue;
        int carried=wgp_item_count_inventory(ainv,dep);
        if(carried>0){
            float d=wgp_distance(apos,mpos);
            if(!wgp_haul_walk(actor,g,mpos,d,now)){
                snprintf(g->current_step,sizeof(g->current_step),"Carrying %s to %s (%.0f)",dep,mname,d);
                return 1;
            }
            int m=minv?stg_transfer_inventory(ainv,minv,dep,carried):0;
            if(m>0){
                g_haul_fails=0; /* item 42 */
                g->last_progress_ms=now;g->last_order_ms=0;g->haul_last_dist=0;g_wgp_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Loaded %d %s into %s",m,dep,mname);
                logline("[stobe] WORK_GOAL haul loaded id=%s %d %s into %s",g->id,m,dep,mname);
                return 1;
            }
            logline("[stobe] WORK_GOAL haul: %s would not accept %s",mname,dep);
            return 0;
        }
        void *b[WGP_MAX_BUILDINGS]={0};
        int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
        void *src=NULL;float best=1e30f;int have=0;
        for(int j=0;j<n;j++){
            void *x=b[j];
            if(!x||x==p->building||!readable(x,0x80))continue;
            int sp=wgp_building_special(x);
            if(!g_wgp_isplayer_building(x)&&sp!=WGP_BF_MINE&&sp!=WGP_BF_MINE_NATURAL)continue;
            {
                /* Only storage, mines, or a machine whose OUTPUT is this item: never
                 * another machine's input (bug 69: water taken out of the oven). */
                int ok_src=(sp==STG_BF_RESOURCE_STORAGE||sp==STG_BF_GENERAL_STORAGE||sp==WGP_BF_MINE||sp==WGP_BF_MINE_NATURAL);
                if(!ok_src){
                    void *pr=wgp_building_production(x);
                    void *ogd=pr?wgp_prod_item(pr):NULL;
                    char on[160]={0};
                    if(ogd&&wgp_name(ogd,on,sizeof(on))&&wgp_name_match(on,dep)>0)ok_src=1;
                }
                if(!ok_src)continue;
            }
            int c=wgp_item_count_inventory(wgp_building_inventory(x),dep);
            if(c<=0)continue;
            float d=wgp_distance(apos,*(Vec3 *)((uintptr_t)x+0x48));
            if(d<best){best=d;src=x;have=c;}
        }
        if(!src)continue; /* not stocked anywhere yet: producing it is handled by the planner */
        char sname[160]={0};
        wgp_name(*(void **)((uintptr_t)src+0x40),sname,sizeof(sname));
        if(!wgp_haul_walk(actor,g,*(Vec3 *)((uintptr_t)src+0x48),best,now)){
            snprintf(g->current_step,sizeof(g->current_step),"Fetching %s from %s for %s (%.0f)",dep,sname,mname,best);
            return 1;
        }
        int take=have<WGP_HAUL_BATCH?have:WGP_HAUL_BATCH;
        int m=stg_transfer_to_character(wgp_building_inventory(src),actor,dep,take);
        if(m>0){
            g_haul_fails=0; /* item 42: only misses in a row block */
            g->last_progress_ms=now;g->haul_last_dist=0;g_wgp_dirty=1;
            snprintf(g->current_step,sizeof(g->current_step),"Picked up %d %s from %s",m,dep,sname);
            logline("[stobe] WORK_GOAL haul picked id=%s %d %s from %s",g->id,m,dep,sname);
            return 1;
        }
        { /* bug 121: a take that keeps failing means her pack is full: block with the
           * reason instead of retrying every tick */
            if(g_haul_fail_goal!=(void *)g){g_haul_fail_goal=(void *)g;g_haul_fails=0;}
            if(++g_haul_fails>=5){
                char why[256];
                snprintf(why,sizeof(why),"her pack is full: can't carry %s from %s",dep,sname);
                logline("[stobe] WORK_GOAL haul: could not take %s from %s -- blocking",dep,sname);
                g_haul_fails=0;g_haul_fail_goal=NULL;
                wgp_goal_block(g,why);
                return 1;
            }
            snprintf(g->current_step,sizeof(g->current_step),"Her pack is full: can't carry %s from %s",dep,sname);
        }
        return 1;
    }
    return 0;
}

static int stg_store_from_actor(void *gw,void *actor,const char *query,int qty)
{
    void *src=g_stobe_getinv(actor); if(!src)return 0;
    int left=qty,moved=0;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    for(int i=0;i<n&&left>0;i++){
        void *x=b[i]; if(!x)continue;
        int sp=wgp_building_special(x);
        if(sp!=STG_BF_RESOURCE_STORAGE&&sp!=STG_BF_GENERAL_STORAGE)continue;
        if(!g_wgp_isplayer_building(x))continue;
        void *dst=wgp_building_inventory(x); if(!dst)continue;
        int m=stg_transfer_inventory(src,dst,query,left);
        moved+=m;left-=m;
    }
    return moved;
}

static int stg_fetch_to_actor(void *gw,void *actor,const char *query,int qty)
{
    int left=qty,moved=0;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    for(int i=0;i<n&&left>0;i++){
        void *x=b[i];if(!x)continue;
        int sp=wgp_building_special(x);
        if(sp!=STG_BF_RESOURCE_STORAGE&&sp!=STG_BF_GENERAL_STORAGE)continue;
        if(!g_wgp_isplayer_building(x))continue;
        void *src=wgp_building_inventory(x); if(!src)continue;
        int m=stg_transfer_to_character(src,actor,query,left);
        moved+=m;left-=m;
    }
    return moved;
}

static void stg_finish(StgGoal *g,int state,const char *reason)
{
    g->state=state;
    if(reason)strncpy(g->reason,reason,sizeof(g->reason)-1);
    g_stg_dirty=1;
    logline("[stobe] TASK_GOAL %s id=%s actor=%s kind=%s completed=%d reason=%s",
            stg_state_name(state),g->id,g->actor,g->kind,g->completed,g->reason);
}

static int stg_actor_item_count(void *actor,const char *query)
{
    return stg_count_matching(g_stobe_getinv(actor),query);
}

static int stg_walk_to_pos(void *actor,StgGoal *g,Vec3 t,float d);

static int stg_loot_scan_log(void *gw,void *actor,StgGoal *g)
{
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    int dead=0,downed=0,valid=0;
    for(int i=0;i<n;i++){
        void *c=chars[i];if(!c||!char_valid(c))continue;
        if(stg_exports()&&g_stg_isdead(c))dead++;
        int pr=char_prone_state(c);if(pr==2||pr==3||pr==4)downed++;
        int ok=stg_valid_downed(actor,c,g->target);if(ok)valid++;
        if(stg_exports()&&(g_stg_isdead(c)||pr==2||pr==3||pr==4)){
            char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
            logline("[stobe] TASK_GOAL loot scan body name=%s dead=%d prone=%d player=%d match=%d",
                    cn,(int)g_stg_isdead(c),pr,(int)g_stg_isplayer(c),ok);
        }
    }
    logline("[stobe] TASK_GOAL loot scan id=%s target=%s item=%s scanned=%d dead=%d downed=%d valid=%d",
            g->id,g->target,g->item,n,dead,downed,valid);
    return valid;
}

static void stg_tick_loot(void *gw,void *actor,StgGoal *g)
{
    if(g->quantity>0&&g->completed>=g->quantity){
        if(g->store_after){
            int travel=stg_at_destination(actor,g);if(travel<=0)return;
            int have=stg_actor_item_count(actor,g->item);
            if(have>0){
                int s=stg_store_from_actor(gw,actor,g->item,have);
                if(s<=0){snprintf(g->current_step,sizeof(g->current_step),"Waiting for usable player storage for %s",g->item);return;}
            }
        }
        stg_finish(g,STG_STATE_COMPLETE,"");return;
    }
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    for(int i=0;i<n;i++){
        void *c=chars[i];uint32_t ser=stg_serial(c);
        if(!ser||stg_seen(g,ser)||!stg_valid_downed(actor,c,g->target))continue;
        void *src=g_stobe_getinv(c); if(!src){stg_mark_seen(g,ser);continue;}
        {
            Vec3 a={0,0,0},cp={0,0,0};
            if(char_position(actor,&a)&&char_position(c,&cp)){
                float d=wgp_distance(a,cp);
                if(!stg_walk_to_pos(actor,g,cp,d)){
                    char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
                    snprintf(g->current_step,sizeof(g->current_step),"Walking to %s to loot %s (%.0f)",cn[0]?cn:"the body",g->item[0]?g->item:"items",d);
                    return;
                }
            }
        }
        int want=g->quantity>0?g->quantity-g->completed:100000;
        int before=stg_actor_item_count(actor,g->item);
        int moved=stg_loot_from_character(c,actor,g->item,want);
        int after=stg_actor_item_count(actor,g->item);
        int got=after-before;if(moved>got)got=moved; /* bug 112: equipped on arrival = not in the pack */
        if(got>0){g->completed+=got;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;}
        stg_mark_seen(g,ser);
        snprintf(g->current_step,sizeof(g->current_step),"Looted %d %s so far; checking nearby downed targets",g->completed,g->item);
        return;
    }
    if(g->store_after){
        int travel=stg_at_destination(actor,g);if(travel<=0)return;
        int have=stg_actor_item_count(actor,g->item);
        if(have>0){
            int s=stg_store_from_actor(gw,actor,g->item,have);
            if(s<=0){snprintf(g->current_step,sizeof(g->current_step),"Looting finished; waiting for usable player storage");return;}
        }
    }
    if(g->completed<=0){ /* bug 104: nothing taken is not "done" */
        int matched=stg_loot_scan_log(gw,actor,g);
        char r[256];
        if(g->target[0]&&matched==0)snprintf(r,sizeof(r),"couldn't find %s's body nearby",g->target);
        else if(g_stg_loot_no_room)snprintf(r,sizeof(r),"no room to carry the %s (pack and slots full)",g->item[0]&&strcmp(g->item,"all")?g->item:"items");
        else snprintf(r,sizeof(r),"found no %s to take on the nearby bodies",g->item[0]&&strcmp(g->item,"all")?g->item:"items");
        stg_finish(g,STG_STATE_BLOCKED,r);
        return;
    }
    stg_finish(g,STG_STATE_COMPLETE,g_stg_loot_no_room?"took what fit; left the rest (no room to carry more)":"no more matching items on nearby downed targets");
}

/* ---- walking fetch/store (round 17e, bug 51) ---- */
static void *stg_nearest_storage(void *gw,void *actor,const char *query,float *dist_out,char *name,size_t namesz)
{
    Vec3 a={0,0,0};if(!char_position(actor,&a))return NULL;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    void *best=NULL;float bd=1e30f;
    for(int i=0;i<n;i++){
        void *x=b[i];if(!x||!readable(x,0x80))continue;
        int sp=wgp_building_special(x);
        if(sp!=STG_BF_RESOURCE_STORAGE&&sp!=STG_BF_GENERAL_STORAGE)continue;
        if(!g_wgp_isplayer_building(x))continue;
        void *inv=wgp_building_inventory(x);if(!inv)continue;
        if(query&&stg_count_matching(inv,query)<=0)continue;
        float d=wgp_distance(a,*(Vec3 *)((uintptr_t)x+0x48));
        if(d<bd){bd=d;best=x;}
    }
    if(best){
        if(dist_out)*dist_out=bd;
        if(name&&namesz){name[0]='\0';wgp_name(*(void **)((uintptr_t)best+0x40),name,namesz);}
    }
    return best;
}

/* 1 = at the position (or as close as pathing gets), 0 = walking */
static int stg_walk_to_pos(void *actor,StgGoal *g,Vec3 t,float d)
{
    DWORD now=stobe_game_ms();
    if(d<=WGP_HAUL_REACH){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if(g->walk_last_dist<=0||d<g->walk_last_dist-3.0f){g->walk_last_dist=d;g->walk_still=0;g->last_progress_ms=now;}
    else g->walk_still++;
    if(d<=WGP_HAUL_NEAR&&g->walk_still>=4){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if((LONG)(now-g->walk_next_ms)>=0){try_move_to_pos(actor,&t);g->walk_next_ms=now+3000;}
    return 0;
}

/* 1 = at the storage (or as close as pathing gets), 0 = walking */
static int stg_walk_to(void *actor,StgGoal *g,void *building,float d)
{
    DWORD now=stobe_game_ms();
    if(d<=WGP_HAUL_REACH){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if(g->walk_last_dist<=0||d<g->walk_last_dist-3.0f){g->walk_last_dist=d;g->walk_still=0;g->last_progress_ms=now;}
    else g->walk_still++;
    if(d<=WGP_HAUL_NEAR&&g->walk_still>=4){g->walk_still=0;g->walk_last_dist=0;return 1;}
    if((LONG)(now-g->walk_next_ms)>=0){Vec3 t=*(Vec3 *)((uintptr_t)building+0x48);try_move_to_pos(actor,&t);g->walk_next_ms=now+3000;}
    return 0;
}

static void stg_tick_store_any(void *gw,void *actor,StgGoal *g);

static void stg_tick_store(void *gw,void *actor,StgGoal *g)
{
    if(stg_actor_item_count(actor,g->item)>0){
        float d=0;char sn[160]={0};
        void *dst=stg_nearest_storage(gw,actor,NULL,&d,sn,sizeof(sn));
        if(dst&&!stg_walk_to(actor,g,dst,d)){
            snprintf(g->current_step,sizeof(g->current_step),"Walking to %s to store %s (%.0f)",sn[0]?sn:"storage",g->item,d);
            return;
        }
        if(dst){
            int want=g->quantity>0?g->quantity-g->completed:stg_actor_item_count(actor,g->item);
            int m=want>0?stg_transfer_inventory(g_stobe_getinv(actor),wgp_building_inventory(dst),g->item,want):0;
            if(m>0){g->completed+=m;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Stored %d %s in %s",g->completed,g->item,sn[0]?sn:"storage");
                if((g->quantity>0&&g->completed>=g->quantity)||stg_actor_item_count(actor,g->item)<=0)stg_finish(g,STG_STATE_COMPLETE,"");
                return;
            }
        }
    }
    stg_tick_store_any(gw,actor,g); /* nearest took nothing: try the rest (old behaviour) */
}

static void stg_tick_store_any(void *gw,void *actor,StgGoal *g)
{
    int have=stg_actor_item_count(actor,g->item);
    if(have<=0){stg_finish(g,STG_STATE_COMPLETE,"");return;}
    int want=g->quantity>0?g->quantity-g->completed:have;
    if(want<=0){stg_finish(g,STG_STATE_COMPLETE,"");return;}
    int moved=stg_store_from_actor(gw,actor,g->item,want);
    if(moved>0){g->completed+=moved;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;}
    snprintf(g->current_step,sizeof(g->current_step),"Stored %d %s",g->completed,g->item);
    if((g->quantity>0&&g->completed>=g->quantity)||stg_actor_item_count(actor,g->item)<=0)stg_finish(g,STG_STATE_COMPLETE,"");
    else if(moved<=0)stg_finish(g,STG_STATE_BLOCKED,"no compatible player storage has room for the requested items");
}

static void stg_tick_fetch(void *gw,void *actor,StgGoal *g)
{
    int need=g->quantity-g->completed;if(need<=0){stg_finish(g,STG_STATE_COMPLETE,"");return;}
    float d=0;char sn[160]={0};
    void *src=stg_nearest_storage(gw,actor,g->item,&d,sn,sizeof(sn));
    if(src&&!stg_walk_to(actor,g,src,d)){
        snprintf(g->current_step,sizeof(g->current_step),"Walking to %s for %s (%.0f)",sn[0]?sn:"storage",g->item,d);
        return;
    }
    int moved=src?stg_transfer_to_character(wgp_building_inventory(src),actor,g->item,need):0;
    if(moved>0){g->completed+=moved;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;
        snprintf(g->current_step,sizeof(g->current_step),"Fetched %d/%d %s from %s",g->completed,g->quantity,g->item,sn[0]?sn:"storage");
        if(g->completed>=g->quantity)stg_finish(g,STG_STATE_COMPLETE,"");
        return; /* next tick: next storage if still short */
    }
    moved=0;
    if(moved>0){g->completed+=moved;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;}
    snprintf(g->current_step,sizeof(g->current_step),"Fetched %d/%d %s from player storage",g->completed,g->quantity,g->item);
    if(g->completed>=g->quantity)stg_finish(g,STG_STATE_COMPLETE,"");
    else if(moved<=0)stg_finish(g,STG_STATE_BLOCKED,"not enough matching items were found in nearby player storage");
}

static void stg_tick_deliver(void *gw,void *actor,StgGoal *g)
{
    void *dst=wgp_find_squad_actor(gw,0,g->target);
    if(!dst){snprintf(g->current_step,sizeof(g->current_step),"Waiting for %s to be loaded/nearby",g->target);return;}
    int need=g->quantity-g->completed;if(need<=0){stg_finish(g,STG_STATE_COMPLETE,"");return;}
    int moved=stg_transfer_char_to_char(actor,dst,g->item,need);
    if(moved>0){g->completed+=moved;g_stg_dirty=1;}
    snprintf(g->current_step,sizeof(g->current_step),"Delivered %d/%d %s to %s",g->completed,g->quantity,g->item,g->target);
    if(g->completed>=g->quantity)stg_finish(g,STG_STATE_COMPLETE,"");
    else if(moved<=0)stg_finish(g,STG_STATE_BLOCKED,"actor does not have enough matching items or recipient inventory cannot accept them");
}

static void stg_tick_medical(void *gw,void *actor,StgGoal *g)
{
    if(!readable(gw,GW_PLAYER+8)){return;}
    void *player=*(void **)((uintptr_t)gw+GW_PLAYER);
    uint32_t count=readable((void *)((uintptr_t)player+PI_PLAYERCHARS+LEK_COUNT),4)?*(uint32_t *)((uintptr_t)player+PI_PLAYERCHARS+LEK_COUNT):0;
    void **stuff=readable((void *)((uintptr_t)player+PI_PLAYERCHARS+LEK_STUFF),8)?*(void ***)((uintptr_t)player+PI_PLAYERCHARS+LEK_STUFF):NULL;
    if(!stuff||count>4096)return;
    for(uint32_t i=0;i<count;i++){
        void *c=stuff[i]; if(!char_valid(c)||c==actor)continue;
        uint32_t ser=stg_serial(c);if(!ser||stg_seen(g,ser))continue;
        if(g_stg_isdead(c)){stg_mark_seen(g,ser);continue;}
        int prone=char_prone_state(c);
        int down=(prone==2||prone==3||prone==4);
        int injured=g_stg_is_injured ? (g_stg_is_injured(c,0)||g_stg_is_injured(c,1)) : down;
        if(!down&&!injured){stg_mark_seen(g,ser);continue;}
        int task=down?STG_TASK_FIND_RESCUE:STG_TASK_FIRST_AID;
        if(stobe_issue_order(actor,task,c)){
            stg_mark_seen(g,ser);g->completed++;
            snprintf(g->current_step,sizeof(g->current_step),task==STG_TASK_FIND_RESCUE?"Rescuing/assisting %u":"Checking/treating squad member %u",ser);
            g->last_action_ms=stobe_game_ms();g_stg_dirty=1;return;
        }
        stg_mark_seen(g,ser);
    }
    stg_finish(g,STG_STATE_COMPLETE,"finished checking loaded squad members");
}

static void stg_tick_imprison(void *gw,void *actor,StgGoal *g)
{
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    for(int i=0;i<n;i++){
        void *c=chars[i];uint32_t ser=stg_serial(c);
        if(!ser||stg_seen(g,ser)||!stg_valid_downed(actor,c,g->target))continue;
        if(g_stg_isanimal&&g_stg_isanimal(c)){stg_mark_seen(g,ser);continue;}
        if(stobe_issue_order(actor,STG_TASK_FIND_CAGE_PUT_IN,c)){
            stg_mark_seen(g,ser);g->completed++;g_stg_dirty=1;
            snprintf(g->current_step,sizeof(g->current_step),"Taking downed target %u to an available cage",ser);
            return;
        }
        stg_mark_seen(g,ser);
    }
    stg_finish(g,STG_STATE_COMPLETE,"no more eligible nearby downed targets");
}

/* "sub-<first 26 chars of parent id>-<item>" belongs to the parent task goal. */
static int stg_is_subgoal_of(const WgpGoal *w,const StgGoal *g)
{
    if(!w||!g||strncmp(w->id,"sub-",4))return 0;
    size_t n=strlen(g->id);if(n>26)n=26;
    return n>0&&!strncmp(w->id+4,g->id,n);
}

static int stg_actor_has_active_work(uint32_t actor_serial)
{
    for(int i=0;i<WGP_MAX_GOALS;i++){
        WgpGoal *w=&g_wgp_goals[i];
        if(w->used&&w->actor_serial==actor_serial&&(w->state==0||w->state==4))return 1;
    }
    return 0;
}

static WgpGoal *stg_find_work_for_item(uint32_t actor_serial,const char *item)
{
    for(int i=0;i<WGP_MAX_GOALS;i++){
        WgpGoal *w=&g_wgp_goals[i];
        if(!w->used||w->actor_serial!=actor_serial||strcasecmp(w->item,item))continue;
        if(w->state==0||w->state==4)return w;
    }
    return NULL;
}

/* A production sub-goal for this item that is BLOCKED and was created recently. */
static WgpGoal *stg_recent_blocked_work(uint32_t actor_serial,const char *item)
{
    for(int i=0;i<WGP_MAX_GOALS;i++){
        WgpGoal *w=&g_wgp_goals[i];
        if(!w->used||w->actor_serial!=actor_serial||strcasecmp(w->item,item)||w->state!=2)continue;
        if((LONG)(stobe_game_ms()-w->created_ms)<600000)return w;
    }
    return NULL;
}

/* returns 1 spawned/exists, 0 no slot, -1 recently blocked (retry after cooldown) */
static int stg_spawn_work_goal(void *gw,void *actor,StgGoal *g,const char *item,int qty)
{
    if(qty<1)return 1;
    if(stg_find_work_for_item(g->actor_serial,item))return 1;
    if(stg_recent_blocked_work(g->actor_serial,item))return -1;
    WgpGoal *slot=NULL;
    for(int i=0;i<WGP_MAX_GOALS;i++)if(!g_wgp_goals[i].used){slot=&g_wgp_goals[i];break;}
    if(!slot)for(int i=0;i<WGP_MAX_GOALS;i++)if(g_wgp_goals[i].state!=0&&g_wgp_goals[i].state!=4){slot=&g_wgp_goals[i];break;}
    if(!slot)return 0;
    memset(slot,0,sizeof(*slot));
    slot->used=1;slot->baseline=-1;slot->actor_serial=g->actor_serial;
    strncpy(slot->actor,g->actor,sizeof(slot->actor)-1);
    strncpy(slot->item,item,sizeof(slot->item)-1);
    slot->quantity=qty;
    snprintf(slot->id,sizeof(slot->id),"sub-%.26s-%.28s",g->id,item);
    slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();slot->created_gt=g->created_gt>0?g->created_gt:g_sgt_now;
    snprintf(slot->current_step,sizeof(slot->current_step),"Subgoal for %s: produce/obtain %d %s",g->id,qty,item);
    g_wgp_dirty=1;
    return 1;
}


static int stg_char_name(void *c,char *out,size_t outsz)
{
    if(!c||!out||outsz<2)return 0;
    return stobe_copy_native_string((void *)((uintptr_t)c+0x18),out,outsz);
}

static int stg_item_value_single(void *item,int buying)
{
    typedef int (*fn_t)(void *,int);
    fn_t fn=(fn_t)wgp_vcall_ptr(item,0x288);
    return fn?fn(item,buying?1:0):-1;
}

static int stg_item_value_all(void *item,int buying)
{
    typedef int (*fn_t)(void *,int);
    fn_t fn=(fn_t)wgp_vcall_ptr(item,0x290);
    return fn?fn(item,buying?1:0):-1;
}

static void *stg_find_trader(void *gw,void *actor,const char *requested,char *name,size_t namesz,float *dist_out)
{
    if(name&&namesz)name[0]='\0';
    if(dist_out)*dist_out=1.0e30f;
    if(!stg_exports()||!g_stg_is_trader)return NULL;
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    Vec3 ap={0,0,0};if(!char_position(actor,&ap))return NULL;
    void *best=NULL;float bestd=1.0e30f;char bestn[128]={0};
    for(int i=0;i<n;i++){
        void *c=chars[i];if(!char_valid(c)||c==actor||!g_stg_is_trader(c))continue;
        char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
        if(requested&&*requested&&wgp_name_match(cn,requested)<=0)continue;
        Vec3 cp={0,0,0};if(!char_position(c,&cp))continue;
        float d=wgp_distance(ap,cp);
        if(d<bestd){best=c;bestd=d;strncpy(bestn,cn,sizeof(bestn)-1);}
    }
    if(best&&name&&namesz){strncpy(name,bestn,namesz-1);name[namesz-1]='\0';}
    if(best&&dist_out)*dist_out=bestd;
    return best;
}

static int stg_trade_once(void *actor,void *trader_char,const char *item_query,int buying,
                          int max_units,int max_total,int already_spent,
                          int *actual_price,int *units_moved,char *why,size_t why_sz)
{
    if(actual_price)*actual_price=0;
    if(units_moved)*units_moved=0;
    if(why&&why_sz)why[0]='\0';
    if(!actor||!trader_char||!stg_exports()||!g_stg_shop_ctor||!g_stg_shop_dtor||
       !g_stg_shop_inv||!g_stg_buy_item||!g_stg_get_money){
        if(why)snprintf(why,why_sz,"trade API unavailable");return 0;
    }

    unsigned char shop_mem[0xE0] __attribute__((aligned(16)));
    memset(shop_mem,0,sizeof(shop_mem));
    void *shop=g_stg_shop_ctor(shop_mem,trader_char);
    if(!shop){if(why)snprintf(why,why_sz,"could not open trader inventory");return 0;}

    int ok=0;
    void *shop_inv=g_stg_shop_inv(shop);
    void *actor_inv=g_stobe_getinv(actor);
    if(!shop_inv||!actor_inv){
        if(why)snprintf(why,why_sz,"trade inventory unavailable");
        g_stg_shop_dtor(shop);return 0;
    }

    void *source=buying?shop_inv:actor_inv;
    int chosen_stack=0;
    void *item=stg_trade_matching_stack(source,item_query,max_units,&chosen_stack);
    if(!item){
        void *any=stg_first_matching(source,item_query);
        if(any&&max_units>0){
            int stack=readable((void *)((uintptr_t)any+0x12C),4)?*(int *)((uintptr_t)any+0x12C):1;
            if(stack<1)stack=1;
            if(why)snprintf(why,why_sz,
                "only a stack of %d %s is available, larger than the remaining exact quantity of %d",
                stack,item_query,max_units);
        }else if(why){
            snprintf(why,why_sz,buying?"merchant does not have %s":"NPC does not have %s",item_query);
        }
        g_stg_shop_dtor(shop);return 0;
    }

    int quote=stg_item_value_all(item,buying);
    if(quote<0){
        if(why)snprintf(why,why_sz,"could not determine current trade price");
        g_stg_shop_dtor(shop);return 0;
    }
    if(buying&&max_total>0&&already_spent+quote>max_total){
        if(actual_price)*actual_price=quote;
        if(why)snprintf(why,why_sz,
            "purchase would exceed approved spending cap (%d Cats); next stack costs %d Cats",
            max_total,quote);
        g_stg_shop_dtor(shop);return 0;
    }

    int money_before=g_stg_get_money(actor);
    int count_before=stg_count_matching(actor_inv,item_query);
    void *moved=g_stg_buy_item(source,item,buying?actor:shop);
    int money_after=g_stg_get_money(actor);
    int count_after=stg_count_matching(actor_inv,item_query);
    int delta=buying?count_after-count_before:count_before-count_after;
    int price=buying?money_before-money_after:money_after-money_before;
    if(moved&&price>=0&&delta>0){
        ok=1;
        if(actual_price)*actual_price=price;
        if(units_moved)*units_moved=delta;
    }else if(why){
        snprintf(why,why_sz,buying?"Kenshi rejected the purchase":"Kenshi rejected the sale");
    }
    g_stg_shop_dtor(shop);
    return ok;
}

static void stg_tick_trade(void *gw,void *actor,StgGoal *g,int buying)
{
    if(buying&&g->quantity<1){stg_finish(g,STG_STATE_BLOCKED,"purchase quantity must be positive");return;}
    if(!buying&&g->quantity==0&&stg_actor_item_count(actor,g->item)<=0){
        stg_finish(g,STG_STATE_COMPLETE,g->completed>0?"sold all matching carried items":"no matching carried items remained to sell");return;
    }
    if(g->quantity>0&&g->completed>=g->quantity){stg_finish(g,STG_STATE_COMPLETE,"");return;}

    char trader_name[128]={0};float dist=0;
    void *trader=stg_find_trader(gw,actor,g->target,trader_name,sizeof(trader_name),&dist);
    if(!trader){
        stg_finish(g,STG_STATE_BLOCKED,g->target[0]?"requested trader is not nearby/loaded":"no nearby loaded trader was found");
        return;
    }
    if(dist>14.0f){
        Vec3 tp={0,0,0};
        if(char_position(trader,&tp)&&try_move_to_pos(actor,&tp)){
            snprintf(g->current_step,sizeof(g->current_step),"Walking to trader %s",trader_name[0]?trader_name:"merchant");
            g->last_action_ms=stobe_game_ms();return;
        }
        stg_finish(g,STG_STATE_BLOCKED,"could not approach trader");return;
    }

    int remaining=g->quantity>0?g->quantity-g->completed:0;
    char why[256]={0};int actual=0,units=0;
    if(!stg_trade_once(actor,trader,g->item,buying,remaining,g->max_spend,g->spent,&actual,&units,why,sizeof(why))){
        if(buying&&actual>0&&g->max_spend>0&&g->spent+actual>g->max_spend){
            g->state=STG_STATE_APPROVAL;
            g->approved_purchase=0;
            g->max_spend=g->spent+actual;
            snprintf(g->current_step,sizeof(g->current_step),
                     "Need renewed approval: next %s purchase would raise authorized spend to %d Cats",
                     g->item,g->max_spend);
            snprintf(g->reason,sizeof(g->reason),
                     "Price changed or the available stack costs more than the previous approved cap");
            g->report_triggered=0;g_stg_dirty=1;return;
        }
        stg_finish(g,STG_STATE_BLOCKED,why[0]?why:"trade failed");return;
    }

    g->completed+=units;
    if(buying)g->spent+=actual;
    g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;
    if(buying){
        snprintf(g->current_step,sizeof(g->current_step),
                 "Bought %d/%d %s from %s; spent %d Cats",
                 g->completed,g->quantity,g->item,trader_name[0]?trader_name:"merchant",g->spent);
    }else if(g->quantity>0){
        snprintf(g->current_step,sizeof(g->current_step),
                 "Sold %d/%d %s to %s",
                 g->completed,g->quantity,g->item,trader_name[0]?trader_name:"merchant");
    }else{
        snprintf(g->current_step,sizeof(g->current_step),
                 "Sold %d %s to %s so far",
                 g->completed,g->item,trader_name[0]?trader_name:"merchant");
    }
    if(g->quantity>0&&g->completed>=g->quantity)stg_finish(g,STG_STATE_COMPLETE,"");
}

static int stg_purchase_fallback_state(uint32_t actor_serial,const char *parent_goal_id,const char *item)
{
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];
        if(!g->used||g->actor_serial!=actor_serial||strcmp(g->kind,"BUY")||strcasecmp(g->item,item))continue;
        if(parent_goal_id&&*parent_goal_id){
            char expected[64]={0};
            snprintf(expected,sizeof(expected),"buy-%.28s-%.28s",parent_goal_id,item);
            if(strcmp(g->id,expected)!=0)continue;
        }
        if(g->state==STG_STATE_CANCELLED||g->state==STG_STATE_BLOCKED)return -1;
        if(g->state==STG_STATE_COMPLETE)return 2;
        return 1;
    }
    return 0;
}

static int stg_request_purchase_fallback(void *gw,void *actor,uint32_t actor_serial,const char *actor_name,const char *parent_goal_id,const char *item,int qty,char *reason,size_t reason_sz)
{
    int existing=stg_purchase_fallback_state(actor_serial,parent_goal_id,item);
    if(existing<0){snprintf(reason,reason_sz,"purchase of %s was declined or failed",item);return -1;}
    if(existing>0){snprintf(reason,reason_sz,existing==2?"purchase of %s completed":"waiting for approval to buy %s",item);return existing==2?2:1;}

    char trader_name[128]={0};float dist=0;
    void *trader=stg_find_trader(gw,actor,"",trader_name,sizeof(trader_name),&dist);
    if(!trader){return 0;}

    unsigned char shop_mem[0xE0] __attribute__((aligned(16)));
    memset(shop_mem,0,sizeof(shop_mem));
    if(!g_stg_shop_ctor||!g_stg_shop_inv||!g_stg_shop_dtor)return 0;
    void *shop=g_stg_shop_ctor(shop_mem,trader);if(!shop)return 0;
    void *inv=g_stg_shop_inv(shop);
    void *offer=inv?stg_first_matching(inv,item):NULL;
    int quote=offer?stg_item_value_single(offer,1):-1;
    g_stg_shop_dtor(shop);
    if(!offer||quote<0)return 0;

    StgGoal *slot=NULL;
    for(int i=0;i<STG_MAX_GOALS;i++)if(!g_stg_goals[i].used||g_stg_goals[i].state==STG_STATE_COMPLETE||g_stg_goals[i].state==STG_STATE_CANCELLED||g_stg_goals[i].state==STG_STATE_BLOCKED){slot=&g_stg_goals[i];break;}
    if(!slot)return 0;
    memset(slot,0,sizeof(*slot));slot->used=1;
    if(parent_goal_id&&*parent_goal_id)
        snprintf(slot->id,sizeof(slot->id),"buy-%.28s-%.28s",parent_goal_id,item);
    else
        snprintf(slot->id,sizeof(slot->id),"buy-%.32s-%u",item,(unsigned)stobe_game_ms());
    slot->actor_serial=actor_serial;strncpy(slot->actor,actor_name,sizeof(slot->actor)-1);
    strncpy(slot->kind,"BUY",sizeof(slot->kind)-1);strncpy(slot->item,item,sizeof(slot->item)-1);
    strncpy(slot->target,trader_name,sizeof(slot->target)-1);
    slot->quantity=qty>0?qty:1;slot->max_spend=quote*slot->quantity;
    slot->state=STG_STATE_APPROVAL;slot->created_ms=stobe_game_ms();slot->last_progress_ms=stobe_game_ms();slot->created_gt=g_sgt_now;
    snprintf(slot->current_step,sizeof(slot->current_step),"Need approval to buy %d %s from %s for up to %d Cats",
             slot->quantity,item,trader_name[0]?trader_name:"nearby trader",slot->max_spend);
    snprintf(slot->reason,sizeof(slot->reason),"No owned/gatherable/producible route was found; buying is the last available nearby option");
    g_stg_dirty=1;
    snprintf(reason,reason_sz,"waiting for approval to buy %d %s for up to %d Cats",slot->quantity,item,slot->max_spend);
    return 1;
}

static void stg_tick_stock(void *gw,void *actor,StgGoal *g)
{
    int minimum=g->minimum_stock>0?g->minimum_stock:g->quantity;
    if(minimum<1){stg_finish(g,STG_STATE_BLOCKED,"stock target has no minimum quantity");return;}
    int have=wgp_item_count_world(gw,actor,g->item);
    g->completed=have;g_stg_dirty=1;
    if(have>=minimum){
        snprintf(g->current_step,sizeof(g->current_step),"Stock healthy: %d/%d %s available",have,minimum,g->item);
        return;
    }
    int deficit=minimum-have;
    int spawned=stg_spawn_work_goal(gw,actor,g,g->item,deficit);
    if(spawned<0){
        WgpGoal *w=stg_recent_blocked_work(g->actor_serial,g->item);
        snprintf(g->current_step,sizeof(g->current_step),"Stock low: %d/%d %s; production is blocked (%s), retrying later",
                 have,minimum,g->item,w&&w->reason[0]?w->reason:"see production goal");
        return;
    }
    if(!spawned){
        stg_finish(g,STG_STATE_BLOCKED,"no free production-goal slot was available");
        return;
    }
    snprintf(g->current_step,sizeof(g->current_step),"Stock low: %d/%d %s; producing deficit of %d",have,minimum,g->item,deficit);
}

static void stg_tick_guard(void *gw,void *actor,StgGoal *g)
{
    if((LONG)(stobe_game_ms()-g->last_action_ms)<5000)return;
    if(g->target[0]){
        void *target=wgp_find_squad_actor(gw,0,g->target);
        if(!target){snprintf(g->current_step,sizeof(g->current_step),"Guarding while waiting for %s to be loaded",g->target);return;}
        stobe_issue_order(actor,STG_TASK_BODYGUARD,target);
        snprintf(g->current_step,sizeof(g->current_step),"Guarding %s until paused or cancelled",g->target);
    }else{
        stobe_issue_order(actor,STG_TASK_HOLD_POSITION,NULL);
        snprintf(g->current_step,sizeof(g->current_step),"Guarding current position until paused or cancelled");
    }
    g->last_action_ms=stobe_game_ms();
}

static void stg_tick_wait_for(void *gw,void *actor,StgGoal *g)
{
    if(!g->target[0]){stg_finish(g,STG_STATE_BLOCKED,"WaitFor requires a named squad member");return;}
    void *target=wgp_find_squad_actor(gw,0,g->target);
    if(target){
        Vec3 a={0,0,0},t={0,0,0};
        if(char_position(actor,&a)&&char_position(target,&t)&&wgp_distance(a,t)<=35.0f){
            stg_finish(g,STG_STATE_COMPLETE,"wait condition satisfied; target returned nearby");return;
        }
    }
    if((LONG)(stobe_game_ms()-g->last_action_ms)>5000){
        stobe_issue_order(actor,STG_TASK_HOLD_POSITION,NULL);
        g->last_action_ms=stobe_game_ms();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Waiting here for %s to return nearby",g->target);
}

static void stg_tick_release_all(void *gw,void *actor,StgGoal *g)
{
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    for(int i=0;i<n;i++){
        void *c=chars[i];uint32_t ser=stg_serial(c);
        if(!ser||stg_seen(g,ser)||!char_valid(c)||g_stg_isplayer(c))continue;
        if(g_stg_isanimal&&g_stg_isanimal(c)){stg_mark_seen(g,ser);continue;}
        if(g->target[0]){
            char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
            if(wgp_name_match(cn,g->target)<=0){stg_mark_seen(g,ser);continue;}
        }
        if(stobe_issue_order(actor,STG_TASK_RELEASE_PRISONER,c)){
            stg_mark_seen(g,ser);g->completed++;g_stg_dirty=1;
            snprintf(g->current_step,sizeof(g->current_step),"Attempting to release nearby prisoner target %u",ser);
            return;
        }
        stg_mark_seen(g,ser);
    }
    stg_finish(g,STG_STATE_COMPLETE,"finished checking nearby humanoids for releasable prisoners");
}

/* Patrol loop between the player's own buildings near the start point (bug 62).
 * Kenshi's PATROL order without waypoints wanders the whole region. */
#define STG_PATROL_RADIUS 700.0f
static void stg_tick_patrol(void *gw,void *actor,StgGoal *g)
{
    Vec3 a={0,0,0};if(!char_position(actor,&a))return;
    if(!g->patrol_init){g->patrol_center=g->has_dest?g->dest:a;g->patrol_init=1;g->patrol_idx=0;}
    Vec3 pts[12];int np=0;
    void *b[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,b,WGP_MAX_BUILDINGS);
    for(int i=0;i<n&&np<12;i++){
        void *x=b[i];if(!x||!readable(x,0x80)||!g_wgp_isplayer_building(x))continue;
        Vec3 bp=*(Vec3 *)((uintptr_t)x+0x48);
        float bd=wgp_distance(bp,g->patrol_center);
        if(bd>STG_PATROL_RADIUS)continue;
        if(bd>90.0f){ /* stand beside the building, not in its centre (bug 67) */
            float k=90.0f/bd;
            bp.x+= (g->patrol_center.x-bp.x)*k; bp.z+=(g->patrol_center.z-bp.z)*k;
        }
        int dup=0;for(int k=0;k<np;k++)if(wgp_distance(pts[k],bp)<60.0f){dup=1;break;}
        if(!dup)pts[np++]=bp;
    }
    if(np<2){
        static const float off[4][2]={{150,0},{0,150},{-150,0},{0,-150}};
        np=0;for(int k=0;k<4;k++){pts[np]=g->patrol_center;pts[np].x+=off[k][0];pts[np].z+=off[k][1];np++;}
    }
    if(g->patrol_idx>=np)g->patrol_idx=0;
    Vec3 t=pts[g->patrol_idx];
    float d=wgp_distance(a,t);
    if(stg_walk_to_pos(actor,g,t,d)||g->walk_still>=8){
        /* arrived, or this waypoint can't be reached (path_failed): next one */
        g->walk_still=0;g->walk_last_dist=0;g->walk_next_ms=0;
        g->patrol_idx=(g->patrol_idx+1)%np;
        g->last_progress_ms=stobe_game_ms();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Patrolling (%d/%d waypoints) until cancelled or paused",g->patrol_idx+1,np);
}

/* A direct standing order (hold, come here, guard, patrol) ends patrol/guard goals (bug 63). */
static void stg_cancel_standing_goals(uint32_t actor_serial)
{
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];
        if(!g->used||g->actor_serial!=actor_serial)continue;
        if(g->state!=STG_STATE_ACTIVE&&g->state!=STG_STATE_PAUSED)continue;
        if(strcmp(g->kind,"PATROL")&&strcmp(g->kind,"GUARD"))continue;
        g->rt_return_started=1; /* replaced by a new order: no walk-back */
        stg_finish(g,STG_STATE_CANCELLED,"replaced by a new order");
    }
}


static int stg_at_destination(void *actor,StgGoal *g)
{
    if(!g->has_dest)return 1;
    Vec3 p={0,0,0};if(!char_position(actor,&p))return 0;
    float d=wgp_distance(p,g->dest);
    if(d<=WGP_ARRIVE_DIST)return 1;
    if((LONG)(stobe_game_ms()-g->last_action_ms)>3000){
        if(!try_move_to_pos(actor,&g->dest)){stg_finish(g,STG_STATE_BLOCKED,"could not issue destination travel order");return -1;}
        g->last_action_ms=stobe_game_ms();
    }
    snprintf(g->current_step,sizeof(g->current_step),"Traveling to %s (%.0fm remaining)",
             g->destination[0]?g->destination:"destination",d);
    return 0;
}

static int stg_scan_world_items(void *gw,void *actor,void **out,int max)
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
}

static void stg_tick_recover_ground(void *gw,void *actor,StgGoal *g)
{
    if(g->quantity>0&&g->completed>=g->quantity){stg_finish(g,STG_STATE_COMPLETE,"");return;}
    void *items[192]={0};int n=stg_scan_world_items(gw,actor,items,192);
    Vec3 ap={0,0,0};char_position(actor,&ap);
    for(int i=0;i<n;i++){
        void *it=items[i];if(!it||!readable(it,0x170)||!stg_item_matches(it,g->item))continue;
        if(g_stg_on_ground&&!g_stg_on_ground(it))continue;
        uint32_t ser=stg_serial(it);if(ser&&stg_seen(g,ser))continue;
        int stack=readable((void *)((uintptr_t)it+0x12C),4)?*(int *)((uintptr_t)it+0x12C):1;if(stack<1)stack=1;
        int remain=g->quantity>0?g->quantity-g->completed:stack;
        if(g->quantity>0&&stack>remain){if(ser)stg_mark_seen(g,ser);continue;}
        Vec3 ip=readable((void *)((uintptr_t)it+0x48),sizeof(Vec3))?*(Vec3 *)((uintptr_t)it+0x48):ap;
        float dist=wgp_distance(ap,ip);
        if(dist>12.0f){
            if(try_move_to_pos(actor,&ip)){snprintf(g->current_step,sizeof(g->current_step),"Moving to recover dropped %s",g->item);g->last_action_ms=stobe_game_ms();return;}
            if(ser)stg_mark_seen(g,ser);continue;
        }
        void *inv=g_stobe_getinv(actor);
        if(inv&&g_stg_take_stack&&g_stg_take_stack(inv,it)){
            g->completed+=stack;g->last_progress_ms=stobe_game_ms();g_stg_dirty=1;
            if(ser)stg_mark_seen(g,ser);
            snprintf(g->current_step,sizeof(g->current_step),"Recovered %d%s %s from the ground",
                     g->completed,g->quantity>0?"/":"",g->item);
            return;
        }
        if(ser)stg_mark_seen(g,ser);
    }
    stg_finish(g,STG_STATE_COMPLETE,"no more matching dropped items nearby");
}

static void *stg_build_state(void *building)
{
    typedef void *(*fn_t)(void *);
    fn_t fn=(fn_t)wgp_vcall_ptr(building,0x228);
    return fn?fn(building):NULL;
}

static int stg_build_missing_material(void *buildstate,char *name,size_t namesz,int *qty)
{
    if(name&&namesz)name[0]='\0';if(qty)*qty=0;
    if(!buildstate||!g_stg_needed_mats)return 0;
    void *ptrs[32]={0};StobePtrLektor l;memset(&l,0,sizeof(l));l.max_size=32;l.stuff=ptrs;
    g_stg_needed_mats(buildstate,&l);
    if(!l.stuff||l.count>32)return 0;
    for(uint32_t i=0;i<l.count;i++){
        unsigned char *m=(unsigned char *)l.stuff[i];if(!m||!readable(m,0x10))continue;
        void *gd=*(void **)m;float total=*(float *)(m+8);float present=*(float *)(m+12);
        float remain=total-present;if(remain<=0.001f)continue;
        if(!wgp_name(gd,name,namesz))continue;
        int q=(int)ceilf(remain-0.0001f);if(q<1)q=1;if(qty)*qty=q;
        return 1;
    }
    return 0;
}

static void stg_tick_build_or_repair(void *gw,void *actor,StgGoal *g,int repair)
{
    char matched[160]={0};
    void *b=stobe_find_building_by_query(gw,actor,g->target[0]?g->target:g->item,matched,sizeof(matched));
    if(!b){stg_finish(g,STG_STATE_BLOCKED,"requested player building/structure is not nearby");return;}

    if(repair){
        typedef int (*dam_t)(void *);
        dam_t damaged=(dam_t)wgp_vcall_ptr(b,0x328);
        if(damaged&&!damaged(b)){stg_finish(g,STG_STATE_COMPLETE,"structure is fully repaired");return;}
    }else{
        void *bs=stg_build_state(b);
        if(bs&&readable(bs,1)&&*(unsigned char *)bs){stg_finish(g,STG_STATE_COMPLETE,"construction is complete");return;}
        char mat[128]={0};int need=0;
        if(bs&&stg_build_missing_material(bs,mat,sizeof(mat),&need)){
            int have=wgp_item_count_world(gw,actor,mat);
            if(have<need){
                int spawned=stg_spawn_work_goal(gw,actor,g,mat,need-have);
                if(spawned<0){
                    WgpGoal *w=stg_recent_blocked_work(g->actor_serial,mat);
                    char r[320];snprintf(r,sizeof(r),"cannot obtain %d %s for construction: %s",need-have,mat,w&&w->reason[0]?w->reason:"production is blocked");
                    stg_finish(g,STG_STATE_BLOCKED,r);return;
                }
                if(!spawned){stg_finish(g,STG_STATE_BLOCKED,"could not create construction-material production subgoal");return;}
                snprintf(g->current_step,sizeof(g->current_step),"Need %d %s for %s; sourcing missing materials",need-have,mat,matched[0]?matched:"construction");
                return;
            }
        }
    }

    if((LONG)(stobe_game_ms()-g->last_action_ms)>2500){
        if(!stobe_issue_order(actor,repair?STG_TASK_REPAIR:STG_TASK_JOB_BUILDER,b)){
            stg_finish(g,STG_STATE_BLOCKED,repair?"could not issue repair job":"could not issue builder job");return;
        }
        g->last_action_ms=stobe_game_ms();
    }
    snprintf(g->current_step,sizeof(g->current_step),repair?"Repairing %s":"Building %s",matched[0]?matched:"structure");
}

static void stg_tick_goal(void *gw,StgGoal *g)
{
    if(!g->used||g->state!=STG_STATE_ACTIVE)return;
    void *actor=wgp_find_squad_actor(gw,g->actor_serial,g->actor);
    if(!actor){snprintf(g->current_step,sizeof(g->current_step),"Waiting for NPC to be loaded");return;}
    if(strcmp(g->kind,"LOOT_AREA")&&strcmp(g->kind,"LOOT_STORE")){
        int travel=stg_at_destination(actor,g);if(travel<=0)return;
    }
    if(!strcmp(g->kind,"LOOT_AREA")||!strcmp(g->kind,"LOOT_STORE"))stg_tick_loot(gw,actor,g);
    else if(!strcmp(g->kind,"STORE"))stg_tick_store(gw,actor,g);
    else if(!strcmp(g->kind,"FETCH"))stg_tick_fetch(gw,actor,g);
    else if(!strcmp(g->kind,"DELIVER"))stg_tick_deliver(gw,actor,g);
    else if(!strcmp(g->kind,"MEDICAL_CLEANUP"))stg_tick_medical(gw,actor,g);
    else if(!strcmp(g->kind,"IMPRISON_ALL"))stg_tick_imprison(gw,actor,g);
    else if(!strcmp(g->kind,"PATROL"))stg_tick_patrol(gw,actor,g);
    else if(!strcmp(g->kind,"STOCK"))stg_tick_stock(gw,actor,g);
    else if(!strcmp(g->kind,"BUY"))stg_tick_trade(gw,actor,g,1);
    else if(!strcmp(g->kind,"SELL"))stg_tick_trade(gw,actor,g,0);
    else if(!strcmp(g->kind,"GUARD"))stg_tick_guard(gw,actor,g);
    else if(!strcmp(g->kind,"WAIT_FOR"))stg_tick_wait_for(gw,actor,g);
    else if(!strcmp(g->kind,"RELEASE_ALL"))stg_tick_release_all(gw,actor,g);
    else if(!strcmp(g->kind,"RECOVER_GROUND"))stg_tick_recover_ground(gw,actor,g);
    else if(!strcmp(g->kind,"BUILD_GOAL"))stg_tick_build_or_repair(gw,actor,g,0);
    else if(!strcmp(g->kind,"REPAIR_GOAL"))stg_tick_build_or_repair(gw,actor,g,1);
}

static void stg_save(void)
{
    char path[MAX_PATH*2]={0};if(!stobe_mod_path(path,sizeof(path),"stobe_task_goals.tsv"))return;
    FILE *f=fopen(path,"wb");if(!f)return;
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];if(!g->used)continue;
        stg_clean(g->actor);stg_clean(g->kind);stg_clean(g->item);stg_clean(g->target);stg_clean(g->destination);stg_clean(g->current_step);stg_clean(g->reason);
        char seen[1024]={0};
        for(int j=0;j<g->seen_count;j++){char p[24];snprintf(p,sizeof(p),"%u,",g->seen[j]);if(strlen(seen)+strlen(p)<sizeof(seen)-1)strcat(seen,p);}
        fprintf(f,"%s\t%u\t%s\t%s\t%s\t%s\t%s\t%d\t%.3f\t%.3f\t%.3f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%.0f\n",
            g->id,g->actor_serial,g->actor,g->kind,g->item,g->target,g->destination,
            g->has_dest,g->dest.x,g->dest.y,g->dest.z,
            g->quantity,g->completed,g->state,g->store_after,g->minimum_stock,
            g->explicit_purchase,g->approved_purchase,g->max_spend,g->spent,
            g->current_step,g->reason,seen,g->created_gt);
    }
    fclose(f);g_stg_dirty=0;
}

static void stg_status(void)
{
    char path[MAX_PATH*2]={0},tmp[MAX_PATH*2]={0};if(!stobe_mod_path(path,sizeof(path),"stobe_task_goal.status"))return;
    snprintf(tmp,sizeof(tmp),"%s.tmp",path);FILE *f=fopen(tmp,"wb");if(!f)return;
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];if(!g->used)continue;
        fprintf(f,"%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%d\t%d\t%d\n",
            g->id,g->actor,stg_state_name(g->state),g->kind,g->item,g->quantity,g->completed,
            g->target,g->destination,g->current_step,g->reason,g->max_spend,g->spent,g->approved_purchase);
    }
    fclose(f);MoveFileExA(tmp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}

static void stg_load(void)
{
    if(g_stg_loaded)return;g_stg_loaded=1;
    char path[MAX_PATH*2]={0};if(!stobe_mod_path(path,sizeof(path),"stobe_task_goals.tsv"))return;
    FILE *f=fopen(path,"rb");if(!f)return;char line[6144];
    while(fgets(line,sizeof(line),f)){
        char *fields[24]={0};int n=0;char *p=line;
        while(n<24){fields[n++]=p;char *t=strchr(p,'\t');if(!t)break;*t='\0';p=t+1;}
        if(n<22)continue;char *e=strpbrk(fields[n-1],"\r\n");if(e)*e='\0';
        StgGoal g;memset(&g,0,sizeof(g));g.used=1;
        strncpy(g.id,fields[0],63);g.actor_serial=(uint32_t)strtoul(fields[1],NULL,10);
        strncpy(g.actor,fields[2],127);strncpy(g.kind,fields[3],39);strncpy(g.item,fields[4],127);
        strncpy(g.target,fields[5],127);strncpy(g.destination,fields[6],127);
        g.has_dest=atoi(fields[7]);g.dest.x=(float)atof(fields[8]);g.dest.y=(float)atof(fields[9]);g.dest.z=(float)atof(fields[10]);
        g.quantity=atoi(fields[11]);g.completed=atoi(fields[12]);g.state=atoi(fields[13]);
        if(g.state==STG_STATE_COMPLETE||g.state==STG_STATE_BLOCKED||g.state==STG_STATE_CANCELLED){g.report_triggered=1;g.rt_return_started=1;} /* bug 94: ended before this launch: already reported */
        g.store_after=atoi(fields[14]);g.minimum_stock=atoi(fields[15]);g.explicit_purchase=atoi(fields[16]);
        g.approved_purchase=atoi(fields[17]);g.max_spend=atoi(fields[18]);g.spent=atoi(fields[19]);
        strncpy(g.current_step,fields[20],219);strncpy(g.reason,fields[21],319);
        if(n>22&&fields[22]){char *ss=fields[22];while(ss&&*ss&&g.seen_count<STG_MAX_SEEN){char *c=strchr(ss,',');if(c)*c='\0';uint32_t v=(uint32_t)strtoul(ss,NULL,10);if(v)g.seen[g.seen_count++]=v;if(!c)break;ss=c+1;}}
        if(n>23)g.created_gt=atof(fields[23]);
        g.created_ms=stobe_game_ms();g.last_progress_ms=stobe_game_ms();
        for(int i=0;i<STG_MAX_GOALS;i++)if(!g_stg_goals[i].used){g_stg_goals[i]=g;break;}
    }
    fclose(f);
}

static void stg_consume_requests(void)
{
    char path[MAX_PATH*2]={0};if(!stobe_mod_path(path,sizeof(path),"stobe_task_goal.request"))return;
    FILE *f=fopen(path,"rb");if(!f)return;char data[16384]={0};size_t got=fread(data,1,sizeof(data)-1,f);fclose(f);DeleteFileA(path);if(!got)return;
    char *line=data;
    while(line&&*line){
        char *next=strpbrk(line,"\r\n");if(next){*next='\0';char *a=next+1;while(*a=='\r'||*a=='\n')a++;next=a;}
        char *v[15]={0};int n=0;char *p=line;while(n<15&&p){v[n++]=p;char *t=strchr(p,'\t');if(!t)break;*t='\0';p=t+1;}
        if(n>=8){
            StgGoal *g=NULL;
            for(int i=0;i<STG_MAX_GOALS;i++)if(!g_stg_goals[i].used||g_stg_goals[i].state==STG_STATE_COMPLETE||g_stg_goals[i].state==STG_STATE_CANCELLED||g_stg_goals[i].state==STG_STATE_BLOCKED){g=&g_stg_goals[i];break;}
            if(g){
                memset(g,0,sizeof(*g));g->used=1;
                strncpy(g->id,v[0],63);g->actor_serial=(uint32_t)strtoul(v[1],NULL,10);strncpy(g->actor,v[2],127);
                strncpy(g->kind,v[3],39);strncpy(g->item,v[4],127);strncpy(g->target,v[5],127);strncpy(g->destination,v[6],127);
                g->quantity=atoi(v[7]);if(g->quantity<0)g->quantity=0;
                if(n>8)g->store_after=atoi(v[8]);if(n>9)g->minimum_stock=atoi(v[9]);if(n>10)g->max_spend=atoi(v[10]);
                if(n>11&&v[11]&&*v[11]){g->has_dest=1;g->dest.x=(float)atof(v[11]);g->dest.y=(float)atof(v[12]);g->dest.z=(float)atof(v[13]);}
                if(n>14)g->explicit_purchase=atoi(v[14]);
                if(!strcmp(g->kind,"BUY")&&g->explicit_purchase){g->approved_purchase=1;g->state=STG_STATE_ACTIVE;}
                g->created_ms=stobe_game_ms();g->last_progress_ms=stobe_game_ms();g->created_gt=g_sgt_now;
                g->rt_seen_active=1; /* walk back + report even if it ends at once */
                snprintf(g->current_step,sizeof(g->current_step),"Accepted %s goal",g->kind);g_stg_dirty=1;
                g_stg_loot_no_room=0;
                logline("[stobe] TASK_GOAL accepted id=%s actor=%s kind=%s item=%s qty=%d target=%s dest=%s",
                        g->id,g->actor,g->kind,g->item,g->quantity,g->target,g->destination);
            }
        }
        line=next;
    }
}

static StgGoal *stg_find_id(const char *id)
{
    for(int i=0;i<STG_MAX_GOALS;i++)if(g_stg_goals[i].used&&!strcmp(g_stg_goals[i].id,id))return &g_stg_goals[i];
    return NULL;
}

static void stg_control_line(char *line);
static void stg_controls(void)
{
    char path[MAX_PATH*2]={0};if(!stobe_mod_path(path,sizeof(path),"stobe_task_goal.control"))return;
    FILE *f=fopen(path,"rb");if(!f)return;char line[1024];
    while(fgets(line,sizeof(line),f))stg_control_line(line);
    fclose(f);DeleteFileA(path);
}

static void stg_control_line(char *line)
{
    char *id=strtok(line,"\t\r\n");char *cmd=strtok(NULL,"\t\r\n");char *arg=strtok(NULL,"\t\r\n");if(!id||!cmd)return;
    StgGoal *g=stg_find_id(id);if(!g)return;
    if(!_stricmp(cmd,"PAUSE")&&g->state==STG_STATE_ACTIVE){
        g->state=STG_STATE_PAUSED;
        for(int i=0;i<WGP_MAX_GOALS;i++)if(g_wgp_goals[i].used&&stg_is_subgoal_of(&g_wgp_goals[i],g)&&g_wgp_goals[i].state==0)g_wgp_goals[i].state=4;
    }
    else if(!_stricmp(cmd,"RESUME")&&g->state==STG_STATE_PAUSED){
        g->state=STG_STATE_ACTIVE;
        for(int i=0;i<WGP_MAX_GOALS;i++)if(g_wgp_goals[i].used&&stg_is_subgoal_of(&g_wgp_goals[i],g)&&g_wgp_goals[i].state==4)g_wgp_goals[i].state=0;
    }
    else if(!_stricmp(cmd,"CANCEL")){
        g->state=STG_STATE_CANCELLED;
        for(int i=0;i<WGP_MAX_GOALS;i++)if(g_wgp_goals[i].used&&stg_is_subgoal_of(&g_wgp_goals[i],g)&&(g_wgp_goals[i].state==0||g_wgp_goals[i].state==4))g_wgp_goals[i].state=3;
        g_wgp_dirty=1;
    }
    else if(!_stricmp(cmd,"APPROVE")&&g->state==STG_STATE_APPROVAL){g->approved_purchase=1;g->state=STG_STATE_ACTIVE;}
    else if(!_stricmp(cmd,"QUANTITY")&&arg){int q=atoi(arg);if(q>0&&q<=1000)g->quantity=q;}
    else if(!_stricmp(cmd,"DESTINATION")&&arg){
        char buf[512]={0};strncpy(buf,arg,sizeof(buf)-1);
        char *a=buf,*b=strchr(a,'^'),*c=NULL,*d=NULL;
        if(!b)return;*b++='\0';c=strchr(b,'^');if(!c)return;*c++='\0';d=strchr(c,'^');if(!d)return;*d++='\0';
        strncpy(g->destination,a,sizeof(g->destination)-1);g->dest.x=(float)atof(b);g->dest.y=(float)atof(c);g->dest.z=(float)atof(d);g->has_dest=1;
    }
    else return;
    g_stg_dirty=1;
}

static void stg_maybe_trigger_report(void *gw,StgGoal *g)
{
    if(!g->used||g->report_triggered)return;
    if(g->state!=STG_STATE_COMPLETE&&g->state!=STG_STATE_BLOCKED&&g->state!=STG_STATE_APPROVAL)return;
    void *actor=wgp_find_squad_actor(gw,g->actor_serial,g->actor);
    void *player=wgp_return_target(gw,actor);
    Vec3 a={0,0,0},p={0,0,0};
    if(!actor||!player||!char_position(actor,&a)||!char_position(player,&p))return;
    int late=g->rt_end_ms&&(LONG)(stobe_game_ms()-g->rt_end_ms)>WGP_REPORT_FALLBACK_MS;
    if(wgp_distance(a,p)>70.0f&&!late)return; /* report once she is back (bug 65) */
    char flag[MAX_PATH*2]={0};if(!stobe_mod_path(flag,sizeof(flag),"lifelike_initiative.flag"))return;
    HANDLE h=CreateFileA(flag,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(h!=INVALID_HANDLE_VALUE){CloseHandle(h);stobe_goal_report_append(g->id,g->actor,"task");g->report_triggered=1;g_stg_dirty=1;}
}

static void stg_tick_goal_guarded(void *gw,StgGoal *g)
{
    if(setjmp(g_guard_jb)){
        g_guard_armed=0;
        stg_finish(g,STG_STATE_BLOCKED,"a native game call faulted while working on this task; stopped safely to protect the game");
        return;
    }
    guard_arm();
    stg_tick_goal(gw,g);
    g_guard_armed=0;
}

/* ---- walk back to the player when a goal ends (round 17b) ---- */
#define SGR_MAX 8
#define SGR_STOP_DIST 60.0f
#define SGR_GIVEUP_MS 180000
#define SGR_REORDER_MS 4000
typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; int cleared; int last_skip; int logged_target; } SgrReturn;
static SgrReturn g_sgr[SGR_MAX];

static int sgr_actor_busy(uint32_t serial)
{
    for(int i=0;i<WGP_MAX_GOALS;i++)
        if(g_wgp_goals[i].used&&g_wgp_goals[i].state==0&&g_wgp_goals[i].actor_serial==serial)return 1;
    for(int i=0;i<STG_MAX_GOALS;i++)
        if(g_stg_goals[i].used&&g_stg_goals[i].state==STG_STATE_ACTIVE&&g_stg_goals[i].actor_serial==serial)return 1;
    return 0;
}

static void sgr_start(uint32_t serial,const char *actor)
{
    if(!serial)return;
    SgrReturn *slot=NULL;DWORD now=stobe_game_ms();
    for(int i=0;i<SGR_MAX;i++)if(g_sgr[i].serial==serial){slot=&g_sgr[i];break;}
    if(!slot)for(int i=0;i<SGR_MAX;i++)if(!g_sgr[i].serial){slot=&g_sgr[i];break;}
    if(!slot)return;
    memset(slot,0,sizeof(*slot));
    slot->serial=serial;strncpy(slot->actor,actor?actor:"",sizeof(slot->actor)-1);
    slot->until_ms=now+SGR_GIVEUP_MS;slot->next_ms=now+1500; /* let the last order settle */
    logline("[stobe] GOAL_RETURN start actor=%s",slot->actor);
}

static void sgr_tick(void *gw)
{
    DWORD now=stobe_game_ms();
    for(int i=0;i<SGR_MAX;i++){
        SgrReturn *r=&g_sgr[i];if(!r->serial)continue;
        if((LONG)(now-r->until_ms)>0){logline("[stobe] GOAL_RETURN gave up actor=%s",r->actor);memset(r,0,sizeof(*r));continue;}
        if(sgr_actor_busy(r->serial)){memset(r,0,sizeof(*r));continue;} /* a new goal took over */
        if((LONG)(now-r->next_ms)<0)continue;
        r->next_ms=now+SGR_REORDER_MS;
        void *actor=wgp_find_squad_actor(gw,r->serial,r->actor);
        void *player=actor?wgp_return_target(gw,actor):NULL;
        Vec3 a={0,0,0},p={0,0,0};
        int skip=!actor?1:!player?2:!char_position(actor,&a)?3:!char_position(player,&p)?4:0;
        if(!skip){int pr=char_prone_state(actor);if(pr==2||pr==3||pr==4)skip=5;}
        if(skip){
            /* bug 75: these used to fail silently until the 180 s give-up */
            static const char *why[]={"","actor not in squad","no other squad member to return to","actor position","target position","actor is down"};
            if(skip!=r->last_skip)logline("[stobe] GOAL_RETURN waiting actor=%s reason=%s",r->actor,why[skip]);
            r->last_skip=skip;continue;
        }
        r->last_skip=0;
        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            logline("[stobe] GOAL_RETURN arrived actor=%s",r->actor);
            memset(r,0,sizeof(*r));continue;
        }
        if(!r->cleared){
            /* Her goal's operate/collect orders would win over the walk-back (bug 50). */
            if(stobe_resolve_fight_exports()){void *o=g_stobe_getorders(actor);if(o&&readable(o,8))g_stobe_clear_orders(o);}
            r->cleared=1;
        }
        if(!r->logged_target){
            char tn[128]={0};stg_char_name(player,tn,sizeof(tn));
            logline("[stobe] GOAL_RETURN walking actor=%s to=%s dist=%.0f",r->actor,tn,wgp_distance(a,p));
            r->logged_target=1;
        }
        if(!try_move_to_pos(actor,&p)){logline("[stobe] GOAL_RETURN move failed actor=%s",r->actor);memset(r,0,sizeof(*r));}
    }
}

static void sgr_scan(void)
{
    for(int i=0;i<WGP_MAX_GOALS;i++){
        WgpGoal *g=&g_wgp_goals[i];if(!g->used)continue;
        if(g->state==0){g->rt_seen_active=1;continue;}
        if(g->rt_seen_active&&!g->rt_return_started&&g->state>=1&&g->state<=3){
            g->rt_return_started=1;sgr_start(g->actor_serial,g->actor);
        }
    }
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];if(!g->used)continue;
        if(g->state==STG_STATE_ACTIVE){g->rt_seen_active=1;g->rt_end_ms=0;continue;}
        if(g->rt_seen_active&&!g->rt_end_ms)g->rt_end_ms=stobe_game_ms();
        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){
            g->rt_return_started=1;sgr_start(g->actor_serial,g->actor);
        }
    }
}

/* ---- on-screen goal label for the selected squad member (round 18d) ---- */
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
    DWORD now=stobe_game_ms();
    const char *actor="";char head[200]="",step[260]="";int more=0,found=0;
    /* work goals first: active/paused, else the most recent ended one still in the keep window */
    for(int pass=0;pass<2&&!found;pass++){
        for(int i=0;i<WGP_MAX_GOALS;i++){
            WgpGoal *g=&g_wgp_goals[i];
            if(!g->used||g->actor_serial!=serial)continue;
            int live=(g->state==0||g->state==4);
            int recent=g->rt_end_ms&&(double)(LONG)(now-g->rt_end_ms)<GOAL_LABEL_KEEP_MS*(g_sgc_speed>1.0f?g_sgc_speed:1.0f);
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
            int recent=g->rt_end_ms&&(double)(LONG)(now-g->rt_end_ms)<GOAL_LABEL_KEEP_MS*(g_sgc_speed>1.0f?g_sgc_speed:1.0f);
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

/* ---- meals during goals (round 19) ----
 * Goals used to work her until she passed out from hunger. While a goal is
 * active and her food level (Kenshi: hunger = fullness 0..300, plus fed = still digesting; bug 81) is low, the goal waits
 * while she eats: from her pack, else from the nearest base storage with food
 * (walks there). No food anywhere: she says so once and keeps working. */
#define SGM_MAX 8
#define SGM_START_LEVEL 150.0f   /* half of 300; KO thresholds seen: 76-87 */
#define SGM_STOP_LEVEL 250.0f
#define SGM_MAX_ITEMS 6
#define CHAR_MEDICAL 0x458
#define MED_HUNGER 0x60
#define MED_FED 0x64
#define KLIB_EATITEM_SYM "?eatItem@Character@@QEAA_NPEAVItem@@PEAVInventory@@@Z"
typedef unsigned char (*chr_eatitem_t)(void *, void *, void *);
typedef struct { uint32_t serial; int eating; int eaten; int warned; float last_d; int still; DWORD next_ms; DWORD retry_ms; int packnote; } SgmMeal;
#define SGM_NOFOOD_RETRY_MS 600000 /* bug 92: no food anywhere -> look again in 10 game min */
#define SGM_PACK_RETRY_MS 60000 /* bug 115: food in her pack -> the game eats; look again in 1 game min */
#define SGM_TAKE_FOOD 3
static SgmMeal g_sgm[SGM_MAX];
static chr_eatitem_t g_chr_eatitem;
static int g_sgm_dead;

static int sgm_food_level(void *actor,float *out)
{
    unsigned char *m=(unsigned char *)actor+CHAR_MEDICAL;
    if(!readable(m+MED_HUNGER,8))return 0;
    float h=*(float *)(m+MED_HUNGER),f=*(float *)(m+MED_FED);
    /* hunger is fullness on a 0..3 scale; the game UI shows it x100 (216 = 2.16,
     * max 300, KO ~76-87). fed = food still digesting, same scale (bug 81). */
    float lvl=(h+f)*100.0f;
    if(!(lvl>-50.0f&&lvl<1000.0f))return 0;
    *out=lvl;return 1;
}

static SgmMeal *sgm_slot(uint32_t serial)
{
    SgmMeal *free_slot=NULL;
    for(int i=0;i<SGM_MAX;i++){if(g_sgm[i].serial==serial)return &g_sgm[i];if(!g_sgm[i].serial&&!free_slot)free_slot=&g_sgm[i];}
    if(free_slot){memset(free_slot,0,sizeof(*free_slot));free_slot->serial=serial;}
    return free_slot;
}

static int sgm_eat_one(void *actor,void *inv)
{
    void *food=stg_first_matching(inv,"food");
    if(!food)return 0;
    return g_chr_eatitem(actor,food,inv)!=0; /* runs under sgm_meal_tick's crash guard */
}

static int sgm_meal_tick_body(void *gw,uint32_t serial,const char *name,char *step,size_t stepsz);

/* 1 = she is busy with a meal this tick (the goal waits); step gets the status.
 * The whole step runs under the crash guard: a fault turns meals off for the
 * session instead of taking the game down. */
static int sgm_meal_tick(void *gw,uint32_t serial,const char *name,char *step,size_t stepsz)
{
    if(g_sgm_dead)return 0;
    if(setjmp(g_guard_jb)){g_guard_armed=0;g_sgm_dead=1;logline("[stobe] GOAL_MEAL faulted -- meals disabled for this session");return 0;}
    guard_arm();
    int r=sgm_meal_tick_body(gw,serial,name,step,stepsz);
    g_guard_armed=0;
    return r;
}

static int sgm_meal_tick_body(void *gw,uint32_t serial,const char *name,char *step,size_t stepsz)
{
    if(g_sgm_dead||!serial||!stg_exports()||!g_stobe_getinv)return 0;
    if(!g_chr_eatitem){
        HMODULE k=GetModuleHandleA("KenshiLib.dll");
        if(k)g_chr_eatitem=(chr_eatitem_t)GetProcAddress(k,KLIB_EATITEM_SYM);
        if(!g_chr_eatitem){g_sgm_dead=1;logline("[stobe] GOAL_MEAL eatItem export missing -- meals disabled");return 0;}
    }
    void *actor=wgp_find_squad_actor(gw,serial,name);
    float lvl=0;if(!actor||!sgm_food_level(actor,&lvl))return 0;
    {   /* bug 81: calibrate -- raw values once per ~10 game min per actor */
        static uint32_t diag_serial[SGM_MAX];static DWORD diag_ms[SGM_MAX];
        int k=(int)(serial%SGM_MAX);DWORD t=stobe_game_ms();
        if(diag_serial[k]!=serial||(LONG)(t-diag_ms[k])>600000){
            unsigned char *md=(unsigned char *)actor+CHAR_MEDICAL;
            logline("[stobe] GOAL_MEAL diag actor=%s hunger=%.1f fed=%.1f level=%.0f",name,*(float *)(md+MED_HUNGER),*(float *)(md+MED_FED),lvl);
            diag_serial[k]=serial;diag_ms[k]=t;
        }
    }
    int pr=char_prone_state(actor);if(pr!=0&&pr!=1)return 0; /* down, KO'd or not loaded yet */
    if(g_stg_isdead&&g_stg_isdead(actor))return 0;
    SgmMeal *m=sgm_slot(serial);if(!m)return 0;
    DWORD now=stobe_game_ms();
    if(!m->eating){
        if(lvl>=SGM_START_LEVEL){if(lvl>=SGM_STOP_LEVEL){m->warned=0;m->packnote=0;}m->retry_ms=0;return 0;}
        if(m->retry_ms&&(LONG)(now-m->retry_ms)<0)return 0; /* bug 92 */
        m->eating=1;m->eaten=0;m->last_d=0;m->still=0;m->retry_ms=0;
        if(!m->packnote)logline("[stobe] GOAL_MEAL hungry actor=%s level=%.0f",name,lvl);
    }
    if(lvl>=SGM_STOP_LEVEL||m->eaten>=SGM_MAX_ITEMS){
        logline("[stobe] GOAL_MEAL done actor=%s ate=%d level=%.0f",name,m->eaten,lvl);
        m->eating=0;m->warned=0;return 0;
    }
    if(m->next_ms&&(LONG)(now-m->next_ms)<0){snprintf(step,stepsz,"Eating (hungry)");return 1;}
    void *own=g_stobe_getinv(actor);
    if(own&&stg_count_matching(own,"food")>0){
        /* bug 115: eatItem used the food up without the meal (~+1 per Dried Meat,
         * the game's own eating gives ~+14). With food in her pack the game feeds her. */
        if(!m->packnote){m->packnote=1;logline("[stobe] GOAL_MEAL food in her pack; the game feeds her actor=%s level=%.0f",name,lvl);}
        m->eating=0;m->retry_ms=now+SGM_PACK_RETRY_MS;return 0;
    }
    float d=0;char sn[160]={0};
    void *store=stg_nearest_storage(gw,actor,"food",&d,sn,sizeof(sn));
    if(!store){
        m->eating=0;m->retry_ms=now+SGM_NOFOOD_RETRY_MS;
        if(!m->warned){
            m->warned=1;
            logline("[stobe] GOAL_MEAL no food anywhere actor=%s level=%.0f -- keeps working",name,lvl);
            char flag[MAX_PATH*2]={0};
            if(stobe_mod_path(flag,sizeof(flag),"lifelike_initiative.flag")){
                HANDLE h=CreateFileA(flag,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
                if(h!=INVALID_HANDLE_VALUE){CloseHandle(h);char id[64];snprintf(id,sizeof(id),"hunger-%u-%u",serial,(unsigned)GetTickCount());stobe_goal_report_append(id,name,"hunger");}
            }
        }
        return 0;
    }
    if(d>WGP_HAUL_REACH){
        if(m->last_d<=0||d<m->last_d-3.0f){m->last_d=d;m->still=0;}else m->still++;
        if(!(d<=WGP_HAUL_NEAR&&m->still>=4)){
            if(m->still>40){m->eating=0;logline("[stobe] GOAL_MEAL can't reach %s actor=%s",sn,name);return 0;}
            Vec3 t=*(Vec3 *)((uintptr_t)store+0x48);try_move_to_pos(actor,&t);
            snprintf(step,stepsz,"Hungry: walking to %s for food (%.0f)",sn[0]?sn:"storage",d);
            return 1;
        }
    }
    { /* bug 115: take food into her pack; the game feeds her from there */
        int took=stg_transfer_to_character(wgp_building_inventory(store),actor,"food",SGM_TAKE_FOOD);
        m->eating=0;m->last_d=0;m->still=0;
        if(took>0){m->retry_ms=now+SGM_PACK_RETRY_MS;logline("[stobe] GOAL_MEAL took %d food from %s actor=%s level=%.0f",took,sn,name,lvl);}
        else logline("[stobe] GOAL_MEAL could not take food from %s actor=%s",sn,name);
        return 0;
    }
}

static void stobe_task_goal_tick(void *gw)
{
    static DWORD real_last;DWORD real=GetTickCount();
    stobe_game_clock_update(gw);
    DWORD now=stobe_game_ms();if(g_stg_next_tick&&(LONG)(now-g_stg_next_tick)<0)return;
    if(real_last&&(LONG)(real-real_last)<STOBE_GOAL_MIN_TICK_REAL_MS)return;
    real_last=real;g_stg_next_tick=now+STG_TICK_MS;
    stg_load();stobe_world_time_update(gw);stg_consume_requests();stg_controls();
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];
        if(!g->used||(g->state!=STG_STATE_ACTIVE&&g->state!=STG_STATE_PAUSED&&g->state!=STG_STATE_APPROVAL)||!stobe_goal_from_future(g->created_gt))continue;
        g->state=STG_STATE_CANCELLED;g->report_triggered=1;g->rt_return_started=1;g->rt_seen_active=0;
        strncpy(g->reason,"given after the loaded save was made; dropped on load",sizeof(g->reason)-1);
        logline("[stobe] GOAL_LOAD dropped id=%s actor=%s kind=%s given_at=%.0f world_now=%.0f",g->id,g->actor,g->kind,g->created_gt,g_sgt_now);
        g_stg_dirty=1;
    }
    uint32_t active[STG_MAX_GOALS]={0};int ac=0;
    for(int i=0;i<STG_MAX_GOALS;i++){
        StgGoal *g=&g_stg_goals[i];if(!g->used)continue;
        if(g->state==STG_STATE_ACTIVE){
            int busy=0;for(int j=0;j<ac;j++)if(active[j]==g->actor_serial){busy=1;break;}
            if(!busy){
                active[ac++]=g->actor_serial;
                if(strcmp(g->kind,"STOCK")&&stg_actor_has_active_work(g->actor_serial))
                    snprintf(g->current_step,sizeof(g->current_step),"Queued behind an active production goal");
                else if(sgm_meal_tick(gw,g->actor_serial,g->actor,g->current_step,sizeof(g->current_step)))
                    g->last_progress_ms=stobe_game_ms(); /* eating: the goal waits */
                else
                    stg_tick_goal_guarded(gw,g);
            }
            else snprintf(g->current_step,sizeof(g->current_step),"Queued behind another active task goal");
        }
        stg_maybe_trigger_report(gw,g);
    }
    sgr_scan();
    sgr_tick(gw);
    stg_status();
    if(g_stg_dirty&&(!g_stg_next_save||(LONG)(real-g_stg_next_save)>=0)){stg_save();g_stg_next_save=real+2500;}
}

