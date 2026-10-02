#!/usr/bin/env python3
"""Plan item 42: a haul blocks with "her pack is full" although one unit would fit.

Run 12, "make 5 building materials" at 50x: she loaded 1 Raw Stone four times, then
BLOCKED "her pack is full: can't carry Raw Stone from Stone Mine" with only Bread x1
and Chewing Tobacco in her pack.
- stg_transfer_to_character took a whole stack (up to WGP_HAUL_BATCH); if it didn't fit
  in her pack, giveItem failed, the stack went back and nothing moved.
- the bug 121 fail counter only reset when the goal changed, so misses added up over
  the whole goal and the 5th one blocked it.
- a partial take (fewer than the whole stack) always failed: the remove was called with
  returnCopyIfSomeLeft=0, which returns NULL when some are left (diagnostic run 12:
  give of 9 failed, then "remove failed avail=10 take=1").
  The same call is used for chest/machine moves and taking from another character.
- a stack bigger than her pack: the add put in what fit (2 stones) and reported
  failure; those stones were never counted, so every trip looked like a miss.
  The pick-up now uses her inventory's addItem and counts a partial add.
Now partial takes ask for the copy (all three places), a stack that doesn't fit is retried at half the size
down to one, and a successful pick-up or load resets the counter (5 misses in a row with no progress
still block).

Usage: patch_kfp_r24_haul_what_fits.py <KenshiFP root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = f.read_text(encoding='utf-8')
if 'g_haul_fails' in s:
    print('already patched'); sys.exit(0)

def sub(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n}x: {old[:60]!r}'
    s = s.replace(old, new)

sub("""    int moved=0,guard=0;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src_inv,query);
        if(!it)break;
        int avail=*(int *)((uintptr_t)it+0x12C); if(avail<1)avail=1;
        int take=maxqty-moved; if(take>avail)take=avail;
        void *det=g_stg_remove(src_inv,it,take,0);
        if(!det)break;
        int actual=*(int *)((uintptr_t)det+0x12C); if(actual<1)actual=take;
        if(!g_stg_give(dst_char,det,0,0)){
            g_stg_add(src_inv,det,actual,1,0);
            break;
        }
        moved+=actual;
    }
    return moved;""",
"""    int moved=0,guard=0,cap=0;
    while(moved<maxqty && guard++<64){
        void *it=stg_first_matching(src_inv,query);
        if(!it)break;
        int avail=*(int *)((uintptr_t)it+0x12C); if(avail<1)avail=1;
        int take=maxqty-moved; if(take>avail)take=avail;
        if(cap>0&&take>cap)take=cap;
        /* item 42: a partial take needs returnCopyIfSomeLeft, else it returns NULL */
        void *det=g_stg_remove(src_inv,it,take,take<avail?1:0);
        if(!det){logline("[stobe] WORK_GOAL haul: could not split %d %s (stack %d)",take,query,avail);break;}
        int actual=*(int *)((uintptr_t)det+0x12C); if(actual<1)actual=take;
        /* item 42: her inventory's addItem, not Character::giveItem: giveItem reported
         * failure yet handed the stones over (then they went back to the mine too) */
        void *dinv=g_stobe_getinv(dst_char);
        if(!(dinv&&g_stg_add(dinv,det,actual,0,0))){
            /* addItem puts in what fits and leaves the rest in the stack */
            int rem=readable((void *)((uintptr_t)det+0x12C),4)?*(int *)((uintptr_t)det+0x12C):actual;
            if(rem>=0&&rem<actual){
                moved+=actual-rem;
                if(rem>0)g_stg_add(src_inv,det,rem,1,0);
                break; /* her pack is full now */
            }
            g_stg_add(src_inv,det,actual,1,0);
            if(actual>1){cap=actual/2;continue;} /* item 42: didn't fit; try half as many */
            logline("[stobe] WORK_GOAL haul: 1 %s does not fit in her pack",query);
            break;
        }
        moved+=actual;
    }
    return moved;""")

# A load into the machine is progress too: she got the stones another way (her mine job).
sub("""            if(m>0){
                g->last_progress_ms=now;g->last_order_ms=0;g->haul_last_dist=0;g_wgp_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Loaded %d %s into %s",m,dep,mname);""",
"""            if(m>0){
                g_haul_fails=0; /* item 42 */
                g->last_progress_ms=now;g->last_order_ms=0;g->haul_last_dist=0;g_wgp_dirty=1;
                snprintf(g->current_step,sizeof(g->current_step),"Loaded %d %s into %s",m,dep,mname);""")

# Same partial-take bug in the inventory-to-inventory and character-to-character moves.
sub("""        void *det=g_stg_remove(src_inv,it,take,0);
        if(!det)break;
        int actual=readable(""",
"""        void *det=g_stg_remove(src_inv,it,take,take<avail?1:0); /* item 42 */
        if(!det)break;
        int actual=readable(""")
sub("""        void *det=g_stg_remove(src,it,take,0);if(!det)break;""",
"""        void *det=g_stg_remove(src,it,take,take<avail?1:0);if(!det)break; /* item 42 */""")

sub("""        int take=have<WGP_HAUL_BATCH?have:WGP_HAUL_BATCH;
        int m=stg_transfer_to_character(wgp_building_inventory(src),actor,dep,take);
        if(m>0){""",
"""        int take=have<WGP_HAUL_BATCH?have:WGP_HAUL_BATCH;
        int m=stg_transfer_to_character(wgp_building_inventory(src),actor,dep,take);
        if(m>0){
            g_haul_fails=0; /* item 42: only misses in a row block */""")

sub("""            static void *fail_goal; static int fails;
            if(fail_goal!=(void *)g){fail_goal=(void *)g;fails=0;}
            if(++fails>=5){""",
"""            if(g_haul_fail_goal!=(void *)g){g_haul_fail_goal=(void *)g;g_haul_fails=0;}
            if(++g_haul_fails>=5){""")
sub("""                fails=0;fail_goal=NULL;
                wgp_goal_block(g,why);""",
"""                g_haul_fails=0;g_haul_fail_goal=NULL;
                wgp_goal_block(g,why);""")

sub("/* 1 = hauling in progress this tick (caller must not issue operate), 0 = nothing to haul */",
    "static void *g_haul_fail_goal; static int g_haul_fails; /* bug 121 / item 42 */\n\n"
    "/* 1 = hauling in progress this tick (caller must not issue operate), 0 = nothing to haul */")

f.write_text(s, encoding='utf-8')
print('patched', f)
