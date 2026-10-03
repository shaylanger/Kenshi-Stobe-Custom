#!/usr/bin/env python3
"""Item 99 (STOBE 15, run m16 craft2): a work goal whose ingredient (Fabrics) only traders had blocked with
"no usable ... route can provide Fabrics" and no WAITING_APPROVAL row, although 14 traders within 600 m of the
player were given Fabrics. stg_request_purchase_fallback returns 0 silently on four different paths (no trader
within 220 m of the worker, shop exports missing, item not in that trader's shop inventory, no price). This adds
one KenshiFP.log line per goal+item saying which, so the next run is conclusive:
`[stobe] BUY_FALLBACK <goal> <item>: <reason>`. Behaviour is unchanged.
Usage: item99_purchase_fallback_diag.py <KenshiFP root>"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 99' in s: sys.exit('already applied')
def rep(old, new):
    global s
    if s.count(old) != 1: sys.exit('anchor missing: ' + old[:80])
    s = s.replace(old, new)
rep("""    char trader_name[128]={0};float dist=0;
    void *trader=stg_find_trader(gw,actor,"",trader_name,sizeof(trader_name),&dist);
    if(!trader){return 0;}
""", """    char trader_name[128]={0};float dist=0;
    /* Item 99: say once per goal+item why no purchase was offered */
    static char s_diag99[512];
    char key99[256];snprintf(key99,sizeof(key99),"%s|%s",parent_goal_id?parent_goal_id:"",item);
    int log99=strcmp(s_diag99,key99)!=0;
    if(log99){strncpy(s_diag99,key99,sizeof(s_diag99)-1);s_diag99[sizeof(s_diag99)-1]='\\0';}
    void *trader=stg_find_trader(gw,actor,"",trader_name,sizeof(trader_name),&dist);
    if(!trader){if(log99)logline("[stobe] BUY_FALLBACK %s %s: no trader within %.0f of %s (Item 99)",parent_goal_id?parent_goal_id:"",item,STG_SCAN_RADIUS,actor_name);return 0;}
""")
rep("""    if(!g_stg_shop_ctor||!g_stg_shop_inv||!g_stg_shop_dtor)return 0;
    void *shop=g_stg_shop_ctor(shop_mem,trader);if(!shop)return 0;
    void *inv=g_stg_shop_inv(shop);
    void *offer=inv?stg_first_matching(inv,item):NULL;
    int quote=offer?stg_item_value_single(offer,1):-1;
    g_stg_shop_dtor(shop);
    if(!offer||quote<0)return 0;
""", """    if(!g_stg_shop_ctor||!g_stg_shop_inv||!g_stg_shop_dtor){if(log99)logline("[stobe] BUY_FALLBACK %s %s: shop exports missing (Item 99)",parent_goal_id?parent_goal_id:"",item);return 0;}
    void *shop=g_stg_shop_ctor(shop_mem,trader);if(!shop){if(log99)logline("[stobe] BUY_FALLBACK %s %s: no shop for %s (Item 99)",parent_goal_id?parent_goal_id:"",item,trader_name);return 0;}
    void *inv=g_stg_shop_inv(shop);
    void *offer=inv?stg_first_matching(inv,item):NULL;
    int quote=offer?stg_item_value_single(offer,1):-1;
    g_stg_shop_dtor(shop);
    if(!offer||quote<0){if(log99)logline("[stobe] BUY_FALLBACK %s %s: nearest trader %s (%.0f away) %s (Item 99)",parent_goal_id?parent_goal_id:"",item,trader_name,dist,!inv?"has no shop inventory":!offer?"does not stock it":"has no price for it");return 0;}
""")
p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
