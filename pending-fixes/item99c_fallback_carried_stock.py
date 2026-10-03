#!/usr/bin/env python3
"""Item 99c (m16 craft6): Apothecary Abia stood 30 m from Malzin with 5 Fabrics (harness `shopstock`: carried),
yet `BUY_FALLBACK ... Fabrics: none of 1 trader(s) within 220 of Malzin stocks it`. The fallback only read the
ShopTrader inventory; goods a trader carries unworn are sold too, and the real buy path (stg_trade_once) already
falls back to them (stg_trade_matching_unworn on the trader's own inventory). The fallback now does the same, so
its "stocks it" matches what a purchase can actually take.
Usage: item99c_fallback_carried_stock.py <KenshiFP root>   (needs 99b)"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 99c' in s: sys.exit('already applied')
old = """            void *offer=inv?stg_first_matching(inv,item):NULL;
            int q=offer?stg_item_value_single(offer,1):-1;
            g_stg_shop_dtor(shop);
            if(!offer||q<0)continue;"""
new = """            void *offer=inv?stg_first_matching(inv,item):NULL;
            int q=offer?stg_item_value_single(offer,1):-1;
            g_stg_shop_dtor(shop);
            if(!offer||q<0){ /* Item 99c: carried, unworn goods are sold too (as stg_trade_once does) */
                void *carried=g_stobe_getinv?g_stobe_getinv(c):NULL;int st=0;
                offer=carried?stg_trade_matching_unworn(carried,item,0,&st):NULL;
                q=offer?stg_item_value_single(offer,1):-1;
            }
            if(!offer||q<0)continue;"""
if s.count(old) != 1: sys.exit('anchor missing (item 99b applied?)')
s = s.replace(old, new)
p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
