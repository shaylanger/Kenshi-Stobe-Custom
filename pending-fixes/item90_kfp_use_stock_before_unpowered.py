#!/usr/bin/env python3
"""Item 90 (KenshiFP): "make 2 bread": Bread 2 <- Strawflour 2 <- Wheatstraw 20 <- the farm needs 20
Water; Well III held 5 Water in its output but was unpowered, so the planner went to make more water
and blocked "Well III has no power". Now, when part of an input is in stock and its producer has no
power, the stock is used first (the parent machine is fed what exists); the power wait / block only
applies once nothing is left. Also: wgp_missing gave a game call an exactly-sized lektor (item 89
pattern): now a scratch lektor with room, copied out.
Usage: item90_kfp_use_stock_before_unpowered.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_work_planner.inc'
s = p.read_text()

def rep(old, new):
    global s
    if new in s:
        print('already:', new[:60].strip()); return
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:70]!r}'
    s = s.replace(old, new)

rep(r'''static int wgp_missing(void *prod, void **out, int max)
{
    typedef void (*fn_t)(void *, StobePtrLektor *);
    fn_t fn=(fn_t)wgp_vcall_ptr(prod,0x560);
    if (!fn || !out || max<1) return 0;
    StobePtrLektor list; memset(&list,0,sizeof(list));
    list.max_size=(uint32_t)max; list.stuff=out;
    fn(prod,&list);
    if (!list.stuff || list.count>(uint32_t)max) return 0;
    return (int)list.count;
}''',
r'''static void *g_wgp_missing_buf[256]; /* item 90: room so the game never grows our buffer */
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
}''')

rep(r'''    char next_chain[WGP_MAX_DEPTH+2][128];
    memset(next_chain,0,sizeof(next_chain));''',
r'''    /* Item 90: some of it is in stock but its producer has no power: use the stock first
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
    memset(next_chain,0,sizeof(next_chain));''')
p.write_text(s)
print('patched')
