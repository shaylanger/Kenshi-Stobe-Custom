#!/usr/bin/env python3
"""Item 83 (KenshiFP): run m7: the game sold the kit (money moved 57 cats, [EVENT] trade) but the goal
said "Kenshi rejected the purchase": the check only counted the buyer's own inventory list, so a
bought item that lands elsewhere (a worn backpack's inventory, another section) read as a failure.
Now: a returned item with the money paid is a purchase; units = the returned stack; a TRADE_RESULT
line logs where it went (inInventory, physical/on the ground, the holder's serial vs the buyer's,
counts and money before/after). If the item is on the ground, the goal blocks with that reason.
Usage: item83_kfp_buy_verify.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'TRADE_RESULT' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:80]!r}'
    s = s.replace(old, new)

rep(r'''    int delta=buying?count_after-count_before:count_before-count_after;
    int price=buying?money_before-money_after:money_after-money_before;
    if(moved&&price>=0&&delta>0){
        ok=1;
        if(actual_price)*actual_price=price;
        if(units_moved)*units_moved=delta;
    }else if(why){''',
r'''    int delta=buying?count_after-count_before:count_before-count_after;
    int price=buying?money_before-money_after:money_after-money_before;
    /* item 83: where did it go? (Item: isInInventory 0xD8, _whosInventoryWeAreIn hand 0x160, _isPhysical 0x1C8) */
    int in_inv=-1,physical=-1;uint32_t holder=0,buyer=stg_serial(actor);int mq=0;
    if(moved&&readable(moved,0x1D0)){
        in_inv=*(unsigned char *)((uintptr_t)moved+0xD8);
        physical=*(unsigned char *)((uintptr_t)moved+0x1C8);
        holder=((uint32_t *)((uintptr_t)moved+0x160+HAND_IDS))[4];
        mq=*(int *)((uintptr_t)moved+0x12C);if(mq<1)mq=1;
    }
    logline("[stobe] TRADE_RESULT buying=%d item=%s moved=%p in_inventory=%d physical=%d holder=%u buyer=%u count %d->%d money %d->%d",
        buying,item_query,moved,in_inv,physical,holder,buyer,count_before,count_after,money_before,money_after);
    if(moved&&price>=0&&delta>0){
        ok=1;
        if(actual_price)*actual_price=price;
        if(units_moved)*units_moved=delta;
    }else if(buying&&moved&&price>0&&in_inv==1&&physical!=1){
        /* item 83: paid and in an inventory that isn't her main list (e.g. her backpack) */
        ok=1;
        if(actual_price)*actual_price=price;
        if(units_moved)*units_moved=mq;
    }else if(buying&&moved&&price>0&&physical==1){
        if(why)snprintf(why,why_sz,"bought %s but it fell to the ground (no room)",item_query);
    }else if(why){''')
p.write_text(s)
print('patched')
