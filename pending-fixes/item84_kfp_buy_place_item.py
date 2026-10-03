#!/usr/bin/env python3
"""Item 84 (KenshiFP): run m8 TRADE_RESULT: Inventory::buyItem took the money and returned the item
detached (in_inventory=0, physical=0, holder=0): the caller has to place it, as the trade UI does.
A detached bought item now goes to the buyer with Character::giveItem(item, dropOnFail=true,
destroyOnFail=false) (at her feet if there's no room); the result is re-checked and logged.
Usage: item84_kfp_buy_place_item.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'TRADE_PLACE' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:80]!r}'
    s = s.replace(old, new)

rep(r'''    logline("[stobe] TRADE_RESULT buying=%d item=%s moved=%p in_inventory=%d physical=%d holder=%u buyer=%u count %d->%d money %d->%d",
        buying,item_query,moved,in_inv,physical,holder,buyer,count_before,count_after,money_before,money_after);''',
r'''    logline("[stobe] TRADE_RESULT buying=%d item=%s moved=%p in_inventory=%d physical=%d holder=%u buyer=%u count %d->%d money %d->%d",
        buying,item_query,moved,in_inv,physical,holder,buyer,count_before,count_after,money_before,money_after);
    if(buying&&moved&&price>0&&delta<=0&&in_inv==0&&physical!=1&&g_stg_give){
        /* item 84: buyItem hands the item back detached; put it in her inventory (or at her feet) */
        int placed=g_stg_give(actor,moved,1,0)?1:0;
        count_after=stg_count_matching(actor_inv,item_query);
        delta=count_after-count_before;
        if(readable(moved,0x1D0)){
            in_inv=*(unsigned char *)((uintptr_t)moved+0xD8);
            physical=*(unsigned char *)((uintptr_t)moved+0x1C8);
            holder=((uint32_t *)((uintptr_t)moved+0x160+HAND_IDS))[4];
        }
        logline("[stobe] TRADE_PLACE give=%d in_inventory=%d physical=%d holder=%u count %d->%d",
            placed,in_inv,physical,holder,count_before,count_after);
    }''')
p.write_text(s)
print('patched')
