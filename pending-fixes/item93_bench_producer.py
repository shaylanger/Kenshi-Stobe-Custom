#!/usr/bin/env python3
"""Item 93 (STOBE 16, run m16, kah-crafting): "make 2 Junkbows" -> WORK_GOAL accepted, then at once
`find_producer done found=0` and BLOCKED "no usable ... crafting bench" although `benches 200 crafts` lists
Junkbow at the Crossbow Crafting Bench (research done).

Suspects (the game was on another fixture when this was written, so both are covered and the next run says
which one it was):
 a) the bench has no production object: wgp_find_producer skips any building whose
    Building::getProductionBuilding() is NULL before it even looks at crafting benches. In this install's
    game data the Crossbow Crafting Bench's functionality ("crossbow smith", Newwworld.mod) is the only bench
    without the 'is production building' flag. A crafting bench IS its own ProductionBuilding
    (CraftingBuilding : ProductionBuilding, single inheritance), so use the building itself.
 b) the scan is capped (256 objects within 1400 m) and the Hub town fills it: if nothing matched and the scan
    came back full, look again within 300 m.
Plus a one-time diagnostic per goal when no producer is found: every crafting bench seen (player-owned,
production object, crafts count, first crafts) -> KenshiFP.log `WORK_DIAG`.
Usage: python3 item93_bench_producer.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 93' in s:
    sys.exit('already applied')

def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit('anchor not found exactly once: ' + old[:70])
    s = s.replace(old, new)

# scan with a radius parameter (old function keeps its signature)
rep("""static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;""",
"""static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius);
static int wgp_scan_buildings(void *gw, void *actor, void **out, int max)
{
    return wgp_scan_buildings_r(gw,actor,out,max,WGP_SCAN_RADIUS);
}

/* Item 93: radius as a parameter (a busy town fills the 1400 m scan) */
static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius)
{
    if (!gw || !actor || !out || max<1 || !wgp_resolve_exports()) return 0;""")
rep("""    g_stobe_getobjects(gw,&list,&center,WGP_SCAN_RADIUS,0,max,actor);""",
    """    g_stobe_getobjects(gw,&list,&center,radius,0,max,actor);""")

# producer search: radius pass + crafting bench without a production object + diagnostics
rep("""static int wgp_find_producer(void *gw, void *actor, const char *query, WgpProducer *out)
{
    if (!out || !wgp_resolve_exports()) return 0;
    memset(out,0,sizeof(*out));
    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,buildings,WGP_MAX_BUILDINGS);
    int best=0;
    for (int i=0;i<n;i++) {""",
"""static int wgp_find_producer_r(void *gw, void *actor, const char *query, WgpProducer *out, float radius, int *scanned, int diag);
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
    for (int i=0;i<n;i++) {""")
rep("""        if (!allowed) continue;
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
            int count=(int)(list.count>WGP_MAX_CRAFTS?WGP_MAX_CRAFTS:list.count);""",
"""        if (diag && special==WGP_BF_CRAFTING && !allowed) {
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
            }""")

rep("""        snprintf(r,sizeof(r),"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",g->item);
        wgp_goal_block(g,r); return;
    }
    if (root.is_crafting && g->queued_root<g->quantity) {""",
"""        snprintf(r,sizeof(r),"no usable mine, farm, production machine, crafting bench, or approved nearby purchase route can provide %s",g->item);
        wgp_log_producer_diag(gw,actor,g->item); /* Item 93 */
        wgp_goal_block(g,r); return;
    }
    if (root.is_crafting && g->queued_root<g->quantity) {""")

p.write_text(s, encoding='utf-8', errors='surrogateescape')
print('patched', p)
