#!/usr/bin/env python3
"""Bug 108: looting a body ignores what it wears (weapons, clothes).

Two causes in stg_transfer_char_to_char:
1. It only searches Inventory::_allItems, which doesn't hold worn items
   (those live in the equipment sections).
2. It unequips a worn item before moving it and stops at the first one it
   can't unequip; dead/downed bodies can't unequip.
For a dead or downed source: also search the inventory sections
(sectionsInSearchOrder @0x68; InventorySection::items vector @0x40 =
first/last pointers, 0x10-byte SectionItem with the Item* first) and take
worn items straight out with removeItemDontDestroy, as the loot screen does.
Standing characters keep what they wear.

Usage: patch_r21_bug108_loot_worn.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')

# Part 1 (round 21 first try) may already be in; normalize to the final form.
part1_old = """        if(readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED)){
            if(!stobe_unequip_item(src_char,it))break; /* still worn: leave it */
        }
"""
part1_first_try = """        if(readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED)){
            if(!stobe_unequip_item(src_char,it)){
                /* Bug 108: bodies can't unequip; take worn gear straight out of a
                 * dead or downed body's inventory, as the loot screen does. */
                int pr=char_prone_state(src_char);
                int body=(g_stg_isdead&&g_stg_isdead(src_char))||pr==2||pr==3||pr==4;
                if(!body)break; /* a standing character keeps what it wears */
                logline("[stobe] TASK_GOAL loot worn item from body (unequip refused, taking it directly)");
            }
        }
"""
part1_new = """        if(readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1) && *(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED)){
            if(!stobe_unequip_item(src_char,it)){
                /* Bug 108: bodies can't unequip; take worn gear straight out of a
                 * dead or downed body's inventory, as the loot screen does. */
                if(!body)break; /* a standing character keeps what it wears */
                logline("[stobe] TASK_GOAL loot worn item from body (unequip refused, taking it directly)");
            }
        }
"""
lookup_old = """    int moved=0,guard=0;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src,query);
        if(!it)break;
"""
lookup_new = """    int moved=0,guard=0;
    int pr=char_prone_state(src_char);
    int body=(g_stg_isdead&&g_stg_isdead(src_char))||pr==2||pr==3||pr==4;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src,query);
        if(!it&&body)it=stg_first_worn_matching(src,query); /* bug 108 */
        if(!it)break;
"""
helper_anchor = "static int stg_transfer_char_to_char(void *src_char,void *dst_char,const char *query,int maxqty)\n"
helper = """/* Bug 108: worn items aren't in Inventory::_allItems; they sit in the
 * equipment sections. sectionsInSearchOrder lektor @0x68; each
 * InventorySection holds a vector<SectionItem> @0x40 (first, last), 0x10 per
 * entry with the Item* first. Returns the first worn item matching query. */
static void *stg_first_worn_matching(void *inv,const char *query)
{
    if(!inv||!readable((void *)((uintptr_t)inv+0x68),sizeof(StobePtrLektor)))return NULL;
    StobePtrLektor *secs=(StobePtrLektor *)((uintptr_t)inv+0x68);
    if(!secs->stuff||secs->count>256||!readable(secs->stuff,secs->count*sizeof(void*)))return NULL;
    for(uint32_t s=0;s<secs->count;s++){
        void *sec=secs->stuff[s];
        if(!sec||!readable((void *)((uintptr_t)sec+0x40),16))continue;
        uintptr_t first=*(uintptr_t *)((uintptr_t)sec+0x40),last=*(uintptr_t *)((uintptr_t)sec+0x48);
        if(!first||last<first||(last-first)>0x10*512||!readable((void *)first,last-first))continue;
        for(uintptr_t e=first;e<last;e+=0x10){
            void *it=*(void **)e;
            if(!it||!readable((void *)((uintptr_t)it+ITEM_IS_EQUIPPED),1))continue;
            if(!*(unsigned char *)((uintptr_t)it+ITEM_IS_EQUIPPED))continue;
            if(stg_item_matches(it,query))return it;
        }
    }
    return NULL;
}

"""

if 'stg_first_worn_matching' in text:
    print('already patched')
    sys.exit(0)
if part1_first_try in text:
    text = text.replace(part1_first_try, part1_new)
else:
    assert text.count(part1_old) == 1, 'unequip anchor not found'
    text = text.replace(part1_old, part1_new)
assert text.count(lookup_old) == 1, 'lookup anchor not found'
text = text.replace(lookup_old, lookup_new)
assert text.count(helper_anchor) == 1, 'helper anchor not found'
text = text.replace(helper_anchor, helper + helper_anchor)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
