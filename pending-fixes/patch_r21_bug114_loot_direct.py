#!/usr/bin/env python3
"""Bug 114: a big worn weapon on a body ends up on the ground, not looted.

To loot a worn item the transfer first unequips it into the body's own
bag; a Staff didn't fit ("no carried section has room; dropped at feet"),
so it fell to the ground and the goal finished without it. For a dead or
downed body, take the worn item straight out of its inventory first
(removeItemDontDestroy, as the loot screen does); unequip only if that
fails.

Usage: patch_r21_bug114_loot_direct.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
old = """        if(readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED)){
            if(!stobe_unequip_item(src_char,it)){
"""
new = """        int worn=readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED);
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
"""
if 'bug 114' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
