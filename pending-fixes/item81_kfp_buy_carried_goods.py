#!/usr/bin/env python3
"""Item 81 (KenshiFP): BUY from Apothecary Abia blocked with "merchant does not have Standard First Aid
Kit" while she carried one (harness shopstock: "(carried) … Standard First Aid Kit x1"): the buy path
only searched the ShopTrader inventory. Like the game's trade window (and the harness `trade`
command, Inventory::buyItem from her carried goods), a purchase now also takes unworn goods the trader
carries. Usage: item81_kfp_buy_carried_goods.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'stg_trade_matching_unworn' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:80]!r}'
    s = s.replace(old, new)

rep(r'''static int stg_transfer_inventory(void *src_inv,void *dst_inv,const char *query,int maxqty)
{''',
r'''/* Item 81: like stg_trade_matching_stack, but never an item the trader wears. */
static void *stg_trade_matching_unworn(void *inv,const char *query,int max_units,int *stack_out)
{
    if(stack_out)*stack_out=0;
    if(!inv||!readable((void *)((uintptr_t)inv+INV_ALLITEMS),sizeof(StobePtrLektor)))return NULL;
    StobePtrLektor *l=(StobePtrLektor *)((uintptr_t)inv+INV_ALLITEMS);
    if(!l->stuff||l->count>4096||!readable(l->stuff,l->count*sizeof(void*)))return NULL;
    void *best=NULL;int best_stack=0;
    for(uint32_t i=0;i<l->count;i++){
        void *it=l->stuff[i];
        if(!it||!readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1))continue;
        if(*(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED))continue;
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
{''')

rep(r'''    void *source=buying?shop_inv:actor_inv;
    int chosen_stack=0;
    void *item=stg_trade_matching_stack(source,item_query,max_units,&chosen_stack);
    if(!item){''',
r'''    void *source=buying?shop_inv:actor_inv;
    int chosen_stack=0;
    void *item=stg_trade_matching_stack(source,item_query,max_units,&chosen_stack);
    if(!item&&buying){
        /* item 81: goods the trader carries (the trade window shows them too) */
        void *carried=g_stobe_getinv(trader_char);
        void *it2=carried?stg_trade_matching_unworn(carried,item_query,max_units,&chosen_stack):NULL;
        if(it2){item=it2;source=carried;logline("[stobe] TRADE buying from the trader's carried goods: %s",item_query);}
    }
    if(!item){''')
p.write_text(s)
print('patched')
