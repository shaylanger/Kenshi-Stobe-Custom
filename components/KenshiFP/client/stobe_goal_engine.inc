/* STOBE persistent finite goal/task planner.
 * Included after the normal gameplay action bridge, so it reuses:
 * stobe_mod_path, stobe_find_character_by_serial, stobe_issue_building_order,
 * stobe_copy_native_string, g_stobe_getobjects/getinv/rethink and Vec3.
 */
#define STOBE_GOAL_MAX_ACTIVE 8
#define STOBE_GOAL_MAX_DEPTH 10
#define STOBE_GOAL_MAX_NODES 128
#define STOBE_GOAL_ITEM_QTY 0x12C
#define STOBE_GOAL_BCTYPE_CRAFTING 6
#define STOBE_GOAL_TASK_OPERATE 87
#define STOBE_GOAL_TASK_DELIVER 88
#define STOBE_GOAL_TASK_COLLECT 92

#define STOBE_GOAL_GETCLASS_SYM "?_NV_getBuildingClass@Building@@QEBA?AW4BuildingClassType@@XZ"
#define STOBE_GOAL_GETFUNCTION_SYM "?_NV_getFunctionStuff@Building@@QEAAPEAVStorageBuilding@@XZ"
#define STOBE_GOAL_GETPRODUCTION_SYM "?_NV_getProductionBuilding@Building@@QEAAPEAVProductionBuilding@@XZ"
#define STOBE_GOAL_PRODITEM_SYM "?_NV_getProductionItemData@StorageBuilding@@QEAAPEAVGameData@@XZ"
#define STOBE_GOAL_NUMINPUTS_SYM "?_NV_getNumConsumtionItems@ProductionBuilding@@QEBAHXZ"
#define STOBE_GOAL_GETINPUT_SYM "?_NV_getConsumtionItems@ProductionBuilding@@QEAAPEAVConsumptionItem@StorageBuilding@@H@Z"
#define STOBE_GOAL_CRAFTS_SYM "?getAvailableCrafts@CraftingBuilding@@QEAAXAEAV?$lektor@VGameDataGroup@@@@@Z"
#define STOBE_GOAL_ADDCRAFT_SYM "?_addCraft@CraftingBuilding@@QEAAPEAVCraftingItem@@PEAVGameData@@0MVYesNoMaybe@@@Z"
#define STOBE_GOAL_HASCRAFT_SYM "?_NV_hasCraftingQueued@CraftingBuilding@@QEBA_NXZ"
#define STOBE_GOAL_COMBAT_SYM "?isInCombatMode@Character@@QEBA_N_N0@Z"
#define STOBE_GOAL_UNCONSCIOUS_SYM "?_NV_isUnconcious@Character@@QEBA_NXZ"
#define STOBE_GOAL_DEAD_SYM "?isDead@Character@@QEBA_NXZ"

typedef int (*stobe_goal_getclass_t)(void *);
typedef void *(*stobe_goal_getptr_t)(void *);
typedef int (*stobe_goal_numinputs_t)(void *);
typedef void *(*stobe_goal_getinput_t)(void *, int);
typedef void (*stobe_goal_getcrafts_t)(void *, void *);
typedef void *(*stobe_goal_addcraft_t)(void *, void *, void *, float, const int *); /* item 93c */
typedef int (*stobe_goal_hascraft_t)(void *);
typedef int (*stobe_goal_combat_t)(void *, int, int);
typedef int (*stobe_goal_boolchar_t)(void *);

static stobe_goal_getclass_t g_goal_getclass;
static stobe_goal_getptr_t g_goal_getfunction;
static stobe_goal_getptr_t g_goal_getproduction;
static stobe_goal_getptr_t g_goal_proditem;
static stobe_goal_numinputs_t g_goal_numinputs;
static stobe_goal_getinput_t g_goal_getinput;
static stobe_goal_getcrafts_t g_goal_getcrafts;
static stobe_goal_addcraft_t g_goal_addcraft;
static stobe_goal_hascraft_t g_goal_hascraft;
static stobe_goal_combat_t g_goal_incombat;
static stobe_goal_boolchar_t g_goal_unconscious;
static stobe_goal_boolchar_t g_goal_dead;

typedef struct StobeGoalDataGroup {
    void *g1;
    void *g2;
} StobeGoalDataGroup;

typedef struct StobeGoalGroupLektor {
    uintptr_t allocator_pad;
    uint32_t count;
    uint32_t max_size;
    StobeGoalDataGroup *stuff;
} StobeGoalGroupLektor;

typedef struct StobeGoalProducer {
    uint32_t serial;
    int crafting;
    void *recipe1;
    void *recipe2;
    char name[160];
} StobeGoalProducer;

typedef struct StobeGoalNode {
    char item[160];
    int target;
    int baseline;
    int depth;
    int stage;
    int craft_queued;
    int delivery_attempts;
    uint32_t producer_serial;
    DWORD stage_tick;
    DWORD last_order_tick;
    DWORD last_progress_tick;
    int last_have;
    void *recipe1;
    void *recipe2;
} StobeGoalNode;

typedef struct StobeGoalRuntime {
    int active;
    char key[80];
    uint32_t actor_serial;
    char root_item[160];
    int root_target;
    int root_baseline;
    int has_destination;
    char destination[160];
    Vec3 destination_pos;
    int max_depth;
    int max_nodes;
    int nodes_created;
    int top;
    int sequence;
    DWORD started_tick;
    DWORD last_tick;
    DWORD last_status_tick;
    DWORD last_move_tick;
    DWORD destination_progress_tick;
    float destination_best_dist2;
    StobeGoalNode stack[STOBE_GOAL_MAX_DEPTH + 1];
} StobeGoalRuntime;

static StobeGoalRuntime g_goal_runtime[STOBE_GOAL_MAX_ACTIVE];
static int try_move_to_pos(void *pc, const Vec3 *tgt);

static int stobe_goal_exports(void)
{
    if (!stobe_resolve_action_exports()) return 0;
    HMODULE k = GetModuleHandleA("KenshiLib.dll");
    if (!k) return 0;
    if (!g_goal_getclass) g_goal_getclass=(stobe_goal_getclass_t)GetProcAddress(k,STOBE_GOAL_GETCLASS_SYM);
    if (!g_goal_getfunction) g_goal_getfunction=(stobe_goal_getptr_t)GetProcAddress(k,STOBE_GOAL_GETFUNCTION_SYM);
    if (!g_goal_getproduction) g_goal_getproduction=(stobe_goal_getptr_t)GetProcAddress(k,STOBE_GOAL_GETPRODUCTION_SYM);
    if (!g_goal_proditem) g_goal_proditem=(stobe_goal_getptr_t)GetProcAddress(k,STOBE_GOAL_PRODITEM_SYM);
    if (!g_goal_numinputs) g_goal_numinputs=(stobe_goal_numinputs_t)GetProcAddress(k,STOBE_GOAL_NUMINPUTS_SYM);
    if (!g_goal_getinput) g_goal_getinput=(stobe_goal_getinput_t)GetProcAddress(k,STOBE_GOAL_GETINPUT_SYM);
    if (!g_goal_getcrafts) g_goal_getcrafts=(stobe_goal_getcrafts_t)GetProcAddress(k,STOBE_GOAL_CRAFTS_SYM);
    if (!g_goal_addcraft) g_goal_addcraft=(stobe_goal_addcraft_t)GetProcAddress(k,STOBE_GOAL_ADDCRAFT_SYM);
    if (!g_goal_hascraft) g_goal_hascraft=(stobe_goal_hascraft_t)GetProcAddress(k,STOBE_GOAL_HASCRAFT_SYM);
    if (!g_goal_incombat) g_goal_incombat=(stobe_goal_combat_t)GetProcAddress(k,STOBE_GOAL_COMBAT_SYM);
    if (!g_goal_unconscious) g_goal_unconscious=(stobe_goal_boolchar_t)GetProcAddress(k,STOBE_GOAL_UNCONSCIOUS_SYM);
    if (!g_goal_dead) g_goal_dead=(stobe_goal_boolchar_t)GetProcAddress(k,STOBE_GOAL_DEAD_SYM);
    return g_goal_getclass && g_goal_getfunction && g_goal_getproduction &&
           g_goal_proditem && g_goal_numinputs && g_goal_getinput &&
           g_goal_getcrafts && g_goal_addcraft && g_goal_hascraft;
}

static int stobe_goal_json_string(const char *json,const char *key,char *out,size_t cap)
{
    char needle[96]={0}; snprintf(needle,sizeof(needle),"\"%s\"",key);
    const char *p=strstr(json,needle); if(!p)return 0;
    p=strchr(p+strlen(needle),':'); if(!p)return 0; p++;
    while(*p==' '||*p=='\t')p++;
    if(*p!='"')return 0; p++;
    size_t n=0;
    while(*p && *p!='"' && n+1<cap){
        if(*p=='\\' && p[1]) p++;
        out[n++]=*p++;
    }
    out[n]='\0'; return n>0 || (p && *p=='"');
}
static long stobe_goal_json_long(const char *json,const char *key,long def)
{
    char needle[96]={0}; snprintf(needle,sizeof(needle),"\"%s\"",key);
    const char *p=strstr(json,needle); if(!p)return def;
    p=strchr(p+strlen(needle),':'); if(!p)return def; p++;
    while(*p==' '||*p=='\t')p++;
    char *end=NULL; long v=strtol(p,&end,10); return end!=p?v:def;
}
static double stobe_goal_json_double(const char *json,const char *key,double def,int *found)
{
    char needle[96]={0}; snprintf(needle,sizeof(needle),"\"%s\"",key);
    const char *p=strstr(json,needle); if(!p){if(found)*found=0;return def;}
    p=strchr(p+strlen(needle),':'); if(!p){if(found)*found=0;return def;} p++;
    while(*p==' '||*p=='\t')p++;
    if(!strncmp(p,"null",4)){if(found)*found=0;return def;}
    char *end=NULL; double v=strtod(p,&end); if(found)*found=(end!=p); return end!=p?v:def;
}
static void stobe_goal_json_escape(const char *src,char *dst,size_t cap)
{
    size_t n=0;
    for(;src&&*src&&n+2<cap;src++){
        unsigned char c=(unsigned char)*src;
        if(c=='"'||c=='\\'){dst[n++]='\\';dst[n++]=(char)c;}
        else if(c=='\n'||c=='\r'||c=='\t') dst[n++]=' ';
        else if(c>=32) dst[n++]=(char)c;
    }
    dst[n]='\0';
}
static void *stobe_goal_player_by_serial(void *gw,uint32_t serial)
{
    if(!gw||!serial||!readable(gw,GW_PLAYER+8))return NULL;
    void *player=*(void **)((uintptr_t)gw+GW_PLAYER);
    if(!readable(player,PI_PLAYERCHARS+LEK_STUFF+8))return NULL;
    uint32_t count=*(uint32_t *)((uintptr_t)player+PI_PLAYERCHARS+LEK_COUNT);
    void **stuff=*(void ***)((uintptr_t)player+PI_PLAYERCHARS+LEK_STUFF);
    if(!stuff||count>4096||!readable(stuff,(count?count:1)*8))return NULL;
    for(uint32_t i=0;i<count;i++){
        void *c=stuff[i];
        if(!char_valid(c)||!readable((void *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS),20))continue;
        uint32_t *ids=(uint32_t *)((uintptr_t)c+CHAR_HANDLE+HAND_IDS);
        if(ids[4]==serial)return c;
    }
    return NULL;
}
static void *stobe_goal_actor(void *gw,uint32_t serial)
{
    void *c=stobe_goal_player_by_serial(gw,serial);
    return c?c:stobe_find_character_by_serial(gw,serial);
}
static int stobe_goal_count_item(void *actor,const char *query)
{
    if(!actor||!query||!*query||!g_stobe_getinv)return 0;
    void *inv=g_stobe_getinv(actor);
    if(!inv||!readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor)))return 0;
    StobePtrLektor *items=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if(!items->stuff||items->count>4096||!readable(items->stuff,items->count*8))return 0;
    char q[192]={0};strncpy(q,query,sizeof(q)-1);stobe_ascii_lower(q);
    int exact=0,partial=0,partialKinds=0; char firstPartial[160]={0};
    for(uint32_t i=0;i<items->count;i++){
        void *it=items->stuff[i]; if(!readable(it,STOBE_GOAL_ITEM_QTY+4))continue;
        void *gd=*(void **)((uintptr_t)it+ITEM_GAMEDATA); if(!gd)continue;
        char name[160]={0}; if(!stobe_copy_native_string((void *)((uintptr_t)gd+GD_NAME),name,sizeof(name)))continue;
        char low[160]={0};strncpy(low,name,sizeof(low)-1);stobe_ascii_lower(low);
        int qty=*(int *)((uintptr_t)it+STOBE_GOAL_ITEM_QTY); if(qty<1)qty=1;
        if(!strcmp(low,q)) exact+=qty;
        else if(strstr(low,q)||strstr(q,low)){
            partial+=qty;
            if(!firstPartial[0])strncpy(firstPartial,low,sizeof(firstPartial)-1);
            else if(strcmp(firstPartial,low))partialKinds=2;
            else partialKinds=1;
        }
    }
    return exact>0?exact:(partialKinds<2?partial:0);
}
static uint32_t stobe_goal_serial(void *obj)
{
    if(!obj||!readable((void *)((uintptr_t)obj+CHAR_HANDLE+HAND_IDS),20))return 0;
    return ((uint32_t *)((uintptr_t)obj+CHAR_HANDLE+HAND_IDS))[4];
}
static void *stobe_goal_building_by_serial(void *gw,void *actor,uint32_t serial)
{
    if(!gw||!actor||!serial||!g_stobe_getobjects)return NULL;
    Vec3 pos={0};if(!char_position(actor,&pos))return NULL;
    void *buf[512]={0};StobePtrLektor out={0,0,512,buf};
    g_stobe_getobjects(gw,&out,&pos,900.0f,0,512,actor);
    if(out.count>512)return NULL;
    for(uint32_t i=0;i<out.count;i++)if(stobe_goal_serial(out.stuff[i])==serial)return out.stuff[i];
    return NULL;
}
static int stobe_goal_name(void *gd,char *out,size_t cap)
{
    return gd&&readable(gd,GD_NAME+0x20)&&stobe_copy_native_string((void *)((uintptr_t)gd+GD_NAME),out,cap);
}
static int stobe_goal_name_match(void *gd,const char *query)
{
    char n[160]={0},q[160]={0}; if(!stobe_goal_name(gd,n,sizeof(n)))return 0;
    strncpy(q,query,sizeof(q)-1);stobe_ascii_lower(q);stobe_ascii_lower(n);
    return !strcmp(n,q)||(strlen(q)>=3&&(strstr(n,q)||strstr(q,n)));
}
static int stobe_goal_find_producer(void *gw,void *actor,const char *item,StobeGoalProducer *out)
{
    memset(out,0,sizeof(*out)); if(!stobe_goal_exports())return 0;
    Vec3 pos={0};if(!char_position(actor,&pos))return 0;
    void *buf[512]={0};StobePtrLektor list={0,0,512,buf};
    g_stobe_getobjects(gw,&list,&pos,900.0f,0,512,actor);
    if(list.count>512)return 0;
    float best=1.0e30f;
    for(uint32_t i=0;i<list.count;i++){
        void *b=list.stuff[i]; if(!b||!readable(b,0x80))continue;
        int cls=g_goal_getclass(b);
        Vec3 bp=*(Vec3 *)((uintptr_t)b+0x48);
        float dx=bp.x-pos.x,dy=bp.y-pos.y,dz=bp.z-pos.z,dist=dx*dx+dy*dy+dz*dz;
        if(cls==STOBE_GOAL_BCTYPE_CRAFTING){
            StobeGoalDataGroup groups[256]; memset(groups,0,sizeof(groups));
            StobeGoalGroupLektor gl={0,0,256,groups};
            g_goal_getcrafts(b,&gl); if(gl.count>256)continue;
            for(uint32_t j=0;j<gl.count;j++){
                if((stobe_goal_name_match(groups[j].g1,item)||stobe_goal_name_match(groups[j].g2,item))&&dist<best){
                    out->serial=stobe_goal_serial(b);out->crafting=1;
                    out->recipe1=groups[j].g1;out->recipe2=groups[j].g2;
                    char bn[160]={0};void *bgd=*(void **)((uintptr_t)b+0x40);stobe_goal_name(bgd,bn,sizeof(bn));
                    strncpy(out->name,bn[0]?bn:"crafting bench",sizeof(out->name)-1);best=dist;
                }
            }
        }
        void *storage=g_goal_getfunction(b);
        void *prod=storage?g_goal_getproduction(b):NULL;
        void *output=storage?g_goal_proditem(storage):NULL;
        if(prod&&output&&stobe_goal_name_match(output,item)&&dist<best){
            out->serial=stobe_goal_serial(b);out->crafting=0;out->recipe1=NULL;out->recipe2=NULL;
            char bn[160]={0};void *bgd=*(void **)((uintptr_t)b+0x40);stobe_goal_name(bgd,bn,sizeof(bn));
            strncpy(out->name,bn[0]?bn:"production machine",sizeof(out->name)-1);best=dist;
        }
    }
    return out->serial!=0;
}
static int stobe_goal_missing_input(void *building,char *name,size_t cap,int *need)
{
    if(name&&cap)name[0]='\0';if(need)*need=0;
    if(!building||!g_goal_getproduction||!g_goal_numinputs||!g_goal_getinput)return 0;
    void *prod=g_goal_getproduction(building);if(!prod)return 0;
    int n=g_goal_numinputs(prod);if(n<0||n>32)return 0;
    for(int i=0;i<n;i++){
        unsigned char *ci=(unsigned char *)g_goal_getinput(prod,i);
        if(!ci||!readable(ci,0x20))continue;
        float amount=*(float *)(ci+0x0),rate=*(float *)(ci+0x4);
        void *gd=*(void **)(ci+0x10);
        float required=rate>0.001f?rate:1.0f;
        if(amount+0.001f<required&&gd&&stobe_goal_name(gd,name,cap)){
            int deficit=(int)ceil(required-amount);if(deficit<1)deficit=1;if(need)*need=deficit;return 1;
        }
    }
    return 0;
}
static int stobe_goal_cycle(StobeGoalRuntime *g,const char *item)
{
    char q[160]={0};strncpy(q,item,sizeof(q)-1);stobe_ascii_lower(q);
    for(int i=0;i<=g->top;i++){char n[160]={0};strncpy(n,g->stack[i].item,sizeof(n)-1);stobe_ascii_lower(n);if(!strcmp(n,q))return 1;}
    return 0;
}
static void stobe_goal_status(StobeGoalRuntime *g,const char *status,const char *message,void *actor)
{
    if(!g||!g->active)return;
    g->sequence++;
    int produced=actor?stobe_goal_count_item(actor,g->root_item)-g->root_baseline:0;if(produced<0)produced=0;
    char item[320]={0},msg[1400]={0},dest[320]={0};stobe_goal_json_escape(g->root_item,item,sizeof(item));
    stobe_goal_json_escape(message?message:"",msg,sizeof(msg));stobe_goal_json_escape(g->destination,dest,sizeof(dest));
    char plan[2200]={0};size_t used=0;used+=snprintf(plan+used,sizeof(plan)-used,"[");
    for(int i=0;i<=g->top&&used+200<sizeof(plan);i++){
        char ni[260]={0};stobe_goal_json_escape(g->stack[i].item,ni,sizeof(ni));
        used+=snprintf(plan+used,sizeof(plan)-used,"%s\"depth %d: produce %d %s\"",i?",":"",g->stack[i].depth,g->stack[i].target,ni);
    }
    snprintf(plan+used,sizeof(plan)-used,"]");
    char json[4096]={0};
    snprintf(json,sizeof(json),"{\"goal_key\":\"%s\",\"sequence\":%d,\"status\":\"%s\",\"message\":\"%s\",\"progress\":{\"produced\":%d,\"target\":%d,\"current_item\":\"%s\",\"depth\":%d,\"nodes\":%d},\"plan\":%s}\n",
        g->key,g->sequence,status,msg,produced,g->root_target,item,g->top,g->nodes_created,plan);
    char leaf[96]={0},path[MAX_PATH*2]={0},tmp[MAX_PATH*2]={0};
    snprintf(leaf,sizeof(leaf),"stobe_goal_%u.status",g->actor_serial);if(!stobe_mod_path(path,sizeof(path),leaf))return;
    snprintf(tmp,sizeof(tmp),"%s.tmp",path);
    HANDLE h=CreateFileA(tmp,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(h!=INVALID_HANDLE_VALUE){DWORD w=0;WriteFile(h,json,(DWORD)strlen(json),&w,NULL);CloseHandle(h);MoveFileExA(tmp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);}
    g->last_status_tick=GetTickCount();
}
static void stobe_goal_finish(StobeGoalRuntime *g,const char *status,const char *message,void *actor)
{
    stobe_goal_status(g,status,message,actor);
    char initiative[MAX_PATH*2]={0};
    if(stobe_mod_path(initiative,sizeof(initiative),"lifelike_initiative.flag")){
        HANDLE h=CreateFileA(initiative,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
            NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
        if(h!=INVALID_HANDLE_VALUE){const char *m="goal_status\n";DWORD w=0;WriteFile(h,m,(DWORD)strlen(m),&w,NULL);CloseHandle(h);}
    }
    g->active=0;
}
static int stobe_goal_push(StobeGoalRuntime *g,void *actor,const char *item,int qty)
{
    if(!g||!actor||!item||!*item)return 0;
    if(g->top+1>g->max_depth||g->top+1>STOBE_GOAL_MAX_DEPTH)return -1;
    if(g->nodes_created>=g->max_nodes||g->nodes_created>=STOBE_GOAL_MAX_NODES)return -2;
    if(stobe_goal_cycle(g,item))return -3;
    g->top++;g->nodes_created++;
    StobeGoalNode *n=&g->stack[g->top];memset(n,0,sizeof(*n));
    strncpy(n->item,item,sizeof(n->item)-1);n->target=qty>0?qty:1;n->baseline=stobe_goal_count_item(actor,item);
    n->depth=g->top;n->stage=0;n->stage_tick=GetTickCount();n->last_progress_tick=n->stage_tick;n->last_have=0;
    return 1;
}
static int stobe_goal_pop(StobeGoalRuntime *g)
{
    if(g->top<=0)return 0;g->top--;g->stack[g->top].stage=0;g->stack[g->top].stage_tick=GetTickCount();g->stack[g->top].last_progress_tick=g->stack[g->top].stage_tick;g->stack[g->top].last_have=0;return 1;
}
static StobeGoalRuntime *stobe_goal_slot(uint32_t actor,const char *key)
{
    for(int i=0;i<STOBE_GOAL_MAX_ACTIVE;i++)if(g_goal_runtime[i].active&&g_goal_runtime[i].actor_serial==actor)return &g_goal_runtime[i];
    for(int i=0;i<STOBE_GOAL_MAX_ACTIVE;i++)if(!g_goal_runtime[i].active)return &g_goal_runtime[i];
    return NULL;
}
static int stobe_goal_load_request(const char *path,void *gw)
{
    HANDLE h=CreateFileA(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(h==INVALID_HANDLE_VALUE)return 0;char json[4096]={0};DWORD got=0;BOOL ok=ReadFile(h,json,sizeof(json)-1,&got,NULL);CloseHandle(h);DeleteFileA(path);
    if(!ok||!got)return 0;json[got]='\0';
    char key[80]={0},item[160]={0},dest[160]={0};if(!stobe_goal_json_string(json,"goal_key",key,sizeof(key))||!stobe_goal_json_string(json,"item",item,sizeof(item)))return 0;
    uint32_t actor=(uint32_t)stobe_goal_json_long(json,"actor_serial",0);int qty=(int)stobe_goal_json_long(json,"quantity",1);
    stobe_goal_json_string(json,"destination",dest,sizeof(dest));
    StobeGoalRuntime *g=stobe_goal_slot(actor,key);if(!g)return 0;
    if(g->active&&g->actor_serial==actor&&!strcmp(g->key,key))return 1;
    if(g->active&&g->actor_serial==actor&&strcmp(g->key,key))return 0;
    memset(g,0,sizeof(*g));g->active=1;g->actor_serial=actor;strncpy(g->key,key,sizeof(g->key)-1);strncpy(g->root_item,item,sizeof(g->root_item)-1);
    g->root_target=qty>0?qty:1;g->max_depth=(int)stobe_goal_json_long(json,"max_depth",10);if(g->max_depth>10)g->max_depth=10;if(g->max_depth<1)g->max_depth=1;
    g->max_nodes=(int)stobe_goal_json_long(json,"max_nodes",64);if(g->max_nodes>128)g->max_nodes=128;if(g->max_nodes<8)g->max_nodes=8;
    int fx=0,fy=0,fz=0;g->destination_pos.x=(float)stobe_goal_json_double(json,"destination_x",0,&fx);g->destination_pos.y=(float)stobe_goal_json_double(json,"destination_y",0,&fy);g->destination_pos.z=(float)stobe_goal_json_double(json,"destination_z",0,&fz);
    g->has_destination=fx&&fy&&fz&&dest[0];strncpy(g->destination,dest,sizeof(g->destination)-1);g->top=0;g->nodes_created=1;g->sequence=0;g->started_tick=GetTickCount();
    void *a=stobe_goal_actor(gw,actor);g->root_baseline=a?stobe_goal_count_item(a,item):0;
    memset(&g->stack[0],0,sizeof(g->stack[0]));strncpy(g->stack[0].item,item,sizeof(g->stack[0].item)-1);g->stack[0].target=g->root_target;g->stack[0].baseline=g->root_baseline;g->stack[0].last_progress_tick=GetTickCount();
    g->destination_best_dist2=1.0e30f;g->destination_progress_tick=GetTickCount();
    stobe_goal_status(g,"ACTIVE",g->has_destination?"Travel prerequisite accepted; task planner will continue after arrival.":"Task planner accepted the finite production goal.",a);
    logline("[stobe] GOAL_TASK accepted actor=%u item=%s qty=%d destination=%s",actor,item,g->root_target,dest);
    return 1;
}
static void stobe_goal_scan_requests(void *gw)
{
    static DWORD last=0;DWORD now=GetTickCount();if(now-last<250)return;last=now;
    char pattern[MAX_PATH*2]={0};if(!stobe_mod_path(pattern,sizeof(pattern),"stobe_goal_*.request"))return;
    WIN32_FIND_DATAA fd;HANDLE find=FindFirstFileA(pattern,&fd);if(find==INVALID_HANDLE_VALUE)return;
    char dir[MAX_PATH*2]={0};strncpy(dir,pattern,sizeof(dir)-1);char *s=strrchr(dir,'\\');if(!s){FindClose(find);return;}s[1]='\0';
    do{if(!(fd.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)){char path[MAX_PATH*2]={0};snprintf(path,sizeof(path),"%s%s",dir,fd.cFileName);stobe_goal_load_request(path,gw);}}while(FindNextFileA(find,&fd));
    FindClose(find);
}
static void stobe_goal_tick_one(void *gw,StobeGoalRuntime *g)
{
    if(!g->active)return;void *actor=stobe_goal_actor(gw,g->actor_serial);
    if(!actor){if(GetTickCount()-g->last_status_tick>10000)stobe_goal_status(g,"ACTIVE","Waiting for the assigned NPC to be available in the loaded world.",NULL);return;}
    if(!stobe_goal_exports())return;
    if((g_goal_dead&&g_goal_dead(actor))||(g_goal_unconscious&&g_goal_unconscious(actor))){
        if(GetTickCount()-g->last_status_tick>10000)stobe_goal_status(g,"ACTIVE","Task paused while the NPC is incapacitated.",actor);
        return;
    }
    if(g_goal_incombat&&g_goal_incombat(actor,1,1)){
        if(GetTickCount()-g->last_status_tick>10000)stobe_goal_status(g,"ACTIVE","Task paused for combat; it will resume when safe.",actor);
        return;
    }
    if(g->has_destination){
        Vec3 p={0};if(!char_position(actor,&p))return;float dx=p.x-g->destination_pos.x,dy=p.y-g->destination_pos.y,dz=p.z-g->destination_pos.z;
        float dist2=dx*dx+dy*dy+dz*dz;
        if(dist2>100.0f){
            DWORD now=GetTickCount();
            if(dist2+25.0f<g->destination_best_dist2){g->destination_best_dist2=dist2;g->destination_progress_tick=now;}
            if(now-g->destination_progress_tick>90000){char m[360]={0};snprintf(m,sizeof(m),"I could not reach %s; travel made no progress for too long, so I stopped the task.",g->destination[0]?g->destination:"the requested destination");stobe_goal_finish(g,"BLOCKED",m,actor);return;}
            if(now-g->last_move_tick>5000){try_move_to_pos(actor,&g->destination_pos);g->last_move_tick=now;stobe_goal_status(g,"ACTIVE","Traveling to the requested destination before starting the work goal.",actor);}return;
        }
        g->has_destination=0;stobe_goal_status(g,"ACTIVE","Arrived at the requested destination; starting the production plan.",actor);
    }
    StobeGoalNode *n=&g->stack[g->top];int have=stobe_goal_count_item(actor,n->item)-n->baseline;if(have<0)have=0;
    DWORD progressNow=GetTickCount();if(have>n->last_have){n->last_have=have;n->last_progress_tick=progressNow;}
    if(n->stage>=3&&progressNow-n->last_progress_tick>1800000){char m[420]={0};snprintf(m,sizeof(m),"I stopped because production of %s made no progress for 30 minutes. The machine may be unpowered, inaccessible, full, or otherwise unable to work.",n->item);stobe_goal_finish(g,"BLOCKED",m,actor);return;}
    if(have>=n->target){if(g->top==0){char m[320]={0};snprintf(m,sizeof(m),"Completed the request: produced %d %s.",g->root_target,g->root_item);stobe_goal_finish(g,"COMPLETED",m,actor);return;}stobe_goal_pop(g);stobe_goal_status(g,"ACTIVE","A prerequisite resource was produced; resuming its parent task.",actor);return;}
    DWORD now=GetTickCount();
    if(n->stage==0){
        StobeGoalProducer prod;if(!stobe_goal_find_producer(gw,actor,n->item,&prod)){char m[420]={0};snprintf(m,sizeof(m),"I could not continue because I could not find any usable nearby mine, farm, processor, or crafting bench that can produce %s.",n->item);stobe_goal_finish(g,"BLOCKED",m,actor);return;}
        n->producer_serial=prod.serial;n->recipe1=prod.recipe1;n->recipe2=prod.recipe2;n->craft_queued=0;n->delivery_attempts=0;n->stage=1;n->stage_tick=now;
        char m[360]={0};snprintf(m,sizeof(m),"Found %s as a producer for %s; checking its inputs.",prod.name,n->item);stobe_goal_status(g,"ACTIVE",m,actor);return;
    }
    void *building=stobe_goal_building_by_serial(gw,actor,n->producer_serial);if(!building){n->stage=0;return;}
    if(n->stage==1){
        if(n->recipe1||n->recipe2){
            if(!g_goal_hascraft(building)&&!n->craft_queued){static const int ynm_maybe=2; void *ci=g_goal_addcraft(building,n->recipe1,n->recipe2,0.0f,&ynm_maybe);if(ci)n->craft_queued=1;}
        }
        char missing[160]={0};int need=0;
        if(stobe_goal_missing_input(building,missing,sizeof(missing),&need)){
            stobe_issue_building_order(actor,building,STOBE_GOAL_TASK_DELIVER);n->delivery_attempts++;n->stage=2;n->stage_tick=now;
            char m[360]={0};snprintf(m,sizeof(m),"The %s job needs %s; checking storage/delivery before creating a subgoal.",n->item,missing);stobe_goal_status(g,"ACTIVE",m,actor);return;
        }
        stobe_issue_building_order(actor,building,STOBE_GOAL_TASK_OPERATE);n->stage=3;n->stage_tick=now;n->last_order_tick=now;return;
    }
    if(n->stage==2){
        if(now-n->stage_tick<12000)return;
        char missing[160]={0};int need=0;
        if(!stobe_goal_missing_input(building,missing,sizeof(missing),&need)){n->stage=1;return;}
        if(stobe_goal_count_item(actor,missing)>0&&n->delivery_attempts<3){stobe_issue_building_order(actor,building,STOBE_GOAL_TASK_DELIVER);n->delivery_attempts++;n->stage_tick=now;return;}
        int pushed=stobe_goal_push(g,actor,missing,need);
        if(pushed==1){char m[360]={0};snprintf(m,sizeof(m),"Creating prerequisite subgoal: produce %d %s for %s.",need,missing,n->item);stobe_goal_status(g,"ACTIVE",m,actor);return;}
        char m[480]={0};if(pushed==-1)snprintf(m,sizeof(m),"I could not continue because the dependency chain for %s exceeded the maximum depth of %d.",missing,g->max_depth);else if(pushed==-2)snprintf(m,sizeof(m),"I could not continue because the plan exceeded its %d-subgoal safety limit while sourcing %s.",g->max_nodes,missing);else snprintf(m,sizeof(m),"I found a circular production dependency involving %s, so I stopped instead of looping.",missing);stobe_goal_finish(g,"BLOCKED",m,actor);return;
    }
    if(n->stage==3){
        if(now-n->last_order_tick>6000){stobe_issue_building_order(actor,building,STOBE_GOAL_TASK_COLLECT);n->last_order_tick=now;}
        int current=stobe_goal_count_item(actor,n->item)-n->baseline;if(current>=n->target){return;}
        if(now-n->stage_tick>10000){n->stage=1;n->stage_tick=now;n->craft_queued=0;}
        if(now-g->last_status_tick>10000){char m[320]={0};snprintf(m,sizeof(m),"Working on %s (%d of %d produced for this step).",n->item,current,n->target);stobe_goal_status(g,"ACTIVE",m,actor);}
    }
}
static void stobe_goal_engine_tick(void *gw)
{
    stobe_goal_scan_requests(gw);static DWORD last=0;DWORD now=GetTickCount();if(now-last<500)return;last=now;
    for(int i=0;i<STOBE_GOAL_MAX_ACTIVE;i++)if(g_goal_runtime[i].active){
        if(setjmp(g_guard_jb)){g_guard_armed=0;stobe_goal_finish(&g_goal_runtime[i],"FAILED","The task planner hit a protected Kenshi runtime error and stopped this goal safely.",NULL);continue;}
        guard_arm();stobe_goal_tick_one(gw,&g_goal_runtime[i]);g_guard_armed=0;
    }
}
