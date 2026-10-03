#!/usr/bin/env python3
"""Item 99b (m16 craft3, KenshiFP 616FBF45 diagnostics):
 - STOBE 15: `BUY_FALLBACK ... Fabrics: nearest trader Security Spider Domesticated (40 away) does not stock it`.
   The purchase fallback asked only the nearest trader, and a trader squad's pack animals count as traders. It now
   checks every trader within STG_SCAN_RADIUS (220) of the worker and takes the nearest one that stocks the item
   with a price; the log names how many traders it checked.
 - STOBE 16: `BUY_FALLBACK ... Steel Bars: no trader within 220` although Malzin carried 6 and 10 were in the
   base chest. Counting stock scans 256 objects within 1400 m; in the Hub that scan is full and can miss the base
   chest. A full scan is now repeated within 300 m (the same rule item 93 gave the producer search), and when a
   needed item has no producer the planner logs where it counted (`WORK_STEP ... have=<n> (inventory <i>, buildings
   <b> of <scanned>)`) so a miscount is visible.
Usage: item99b_fallback_trader_and_counts.py <KenshiFP root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]) / 'client'

def patch(name, reps):
    p = root / name
    s = p.read_text(encoding='utf-8', errors='surrogateescape')
    if 'Item 99b' in s: sys.exit(name + ': already applied')
    for old, new in reps:
        if s.count(old) != 1: sys.exit(name + ': anchor missing: ' + old[:80])
        s = s.replace(old, new)
    p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)

patch('stobe_task_goals.inc', [(
"""    void *trader=stg_find_trader(gw,actor,"",trader_name,sizeof(trader_name),&dist);
    if(!trader){if(log99)logline("[stobe] BUY_FALLBACK %s %s: no trader within %.0f of %s (Item 99)",parent_goal_id?parent_goal_id:"",item,STG_SCAN_RADIUS,actor_name);return 0;}

    unsigned char shop_mem[0xE0] __attribute__((aligned(16)));
    memset(shop_mem,0,sizeof(shop_mem));
    if(!g_stg_shop_ctor||!g_stg_shop_inv||!g_stg_shop_dtor){if(log99)logline("[stobe] BUY_FALLBACK %s %s: shop exports missing (Item 99)",parent_goal_id?parent_goal_id:"",item);return 0;}
    void *shop=g_stg_shop_ctor(shop_mem,trader);if(!shop){if(log99)logline("[stobe] BUY_FALLBACK %s %s: no shop for %s (Item 99)",parent_goal_id?parent_goal_id:"",item,trader_name);return 0;}
    void *inv=g_stg_shop_inv(shop);
    void *offer=inv?stg_first_matching(inv,item):NULL;
    int quote=offer?stg_item_value_single(offer,1):-1;
    g_stg_shop_dtor(shop);
    if(!offer||quote<0){if(log99)logline("[stobe] BUY_FALLBACK %s %s: nearest trader %s (%.0f away) %s (Item 99)",parent_goal_id?parent_goal_id:"",item,trader_name,dist,!inv?"has no shop inventory":!offer?"does not stock it":"has no price for it");return 0;}
""",
"""    /* Item 99b: the nearest trader that stocks it (pack animals of a trader squad count as traders too) */
    if(!stg_exports()||!g_stg_is_trader||!g_stg_shop_ctor||!g_stg_shop_inv||!g_stg_shop_dtor){if(log99)logline("[stobe] BUY_FALLBACK %s %s: trader/shop exports missing (Item 99)",parent_goal_id?parent_goal_id:"",item);return 0;}
    void *trader=NULL;int quote=-1,checked=0;dist=1.0e30f;
    {
        void *chars[256]={0};int n=stg_scan_chars_r(gw,actor,chars,256,STG_SCAN_RADIUS);
        Vec3 ap={0,0,0};if(!char_position(actor,&ap))n=0;
        for(int i=0;i<n;i++){
            void *c=chars[i];if(!char_valid(c)||c==actor||!g_stg_is_trader(c))continue;
            Vec3 cp={0,0,0};if(!char_position(c,&cp))continue;
            float d=wgp_distance(ap,cp);if(d>=dist)continue;
            checked++;
            unsigned char shop_mem[0xE0] __attribute__((aligned(16)));
            memset(shop_mem,0,sizeof(shop_mem));
            void *shop=g_stg_shop_ctor(shop_mem,c);if(!shop)continue;
            void *inv=g_stg_shop_inv(shop);
            void *offer=inv?stg_first_matching(inv,item):NULL;
            int q=offer?stg_item_value_single(offer,1):-1;
            g_stg_shop_dtor(shop);
            if(!offer||q<0)continue;
            trader=c;quote=q;dist=d;stg_char_name(c,trader_name,sizeof(trader_name));
        }
    }
    if(!trader){if(log99)logline("[stobe] BUY_FALLBACK %s %s: none of %d trader(s) within %.0f of %s stocks it (Item 99b)",parent_goal_id?parent_goal_id:"",item,checked,STG_SCAN_RADIUS,actor_name);return 0;}
    if(log99)logline("[stobe] BUY_FALLBACK %s %s: %s (%.0f away) sells it for %d (Item 99b)",parent_goal_id?parent_goal_id:"",item,trader_name,dist,quote);
""")])

patch('stobe_work_planner.inc', [
("""    void *buildings[WGP_MAX_BUILDINGS]={0};
    int n=wgp_scan_buildings(gw,actor,buildings,WGP_MAX_BUILDINGS);
    for (int i=0;i<n;i++) {
        void *b=buildings[i];
        if (!readable(b,0x80)) continue;
        int special=wgp_building_special(b);
        int allowed=g_wgp_isplayer_building(b) ||
            special==WGP_BF_MINE || special==WGP_BF_MINE_NATURAL;
        if (!allowed) continue;
        void *binv=wgp_building_inventory(b);""",
"""    void *buildings[WGP_MAX_BUILDINGS]={0};
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
        void *binv=wgp_building_inventory(b);"""),
("""static int wgp_item_count_world(void *gw, void *actor, const char *query)
{""",
"""static int g_wgp_count_scanned, g_wgp_count_inv; /* Item 99b: last count's sources (log only) */
static int wgp_scan_buildings_r(void *gw, void *actor, void **out, int max, float radius);
static int wgp_item_count_world(void *gw, void *actor, const char *query)
{"""),
("""    if (!found_p) {
        int purchase=stg_request_purchase_fallback(""",
"""    if (!found_p) {
        logline("[stobe] WORK_STEP id=%s %s have=%d need=%d (inventory %d, buildings %d of %d scanned) no producer (Item 99b)",
                g->id,item,have,need,g_wgp_count_inv,have-g_wgp_count_inv,g_wgp_count_scanned);
        int purchase=stg_request_purchase_fallback("""),
])
