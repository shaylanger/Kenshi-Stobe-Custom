#!/usr/bin/env python3
"""Item 82 (KenshiFP): (a) a finished BUY with a person label hands the bought items over on the
walk-back, like FETCH (item 76); (b) the walk-back target is locked when first found (run m6:
"walking … to=Shay dist=259" then "arrived" 4 s later: the target is re-picked every tick from the
selection and can switch to someone close), and the arrival line logs the target and distance.
Usage: item82_kfp_buy_handover_locked_target.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'target_serial;' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:80]!r}'
    s = s.replace(old, new)

rep(r'''                 char give_item[128]; char give_to[128]; int give_qty; /* item 76: hand a fetch over on arrival */ } SgrReturn;''',
r'''                 char give_item[128]; char give_to[128]; int give_qty; /* item 76: hand a fetch over on arrival */
                 uint32_t target_serial; /* item 82: the walk-back target, locked when first found */ } SgrReturn;''')
rep(r'''        void *actor=wgp_find_squad_actor(gw,r->serial,r->actor);
        void *player=actor?wgp_return_target(gw,actor):NULL;''',
r'''        void *actor=wgp_find_squad_actor(gw,r->serial,r->actor);
        void *player=NULL;
        if(actor&&r->target_serial)player=wgp_find_squad_actor(gw,r->target_serial,NULL); /* item 82: locked */
        if(actor&&!player){player=wgp_return_target(gw,actor);if(player)r->target_serial=stg_serial(player);}''')
rep(r'''        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            logline("[stobe] GOAL_RETURN arrived actor=%s",r->actor);''',
r'''        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            {char an[128]={0};stg_char_name(player,an,sizeof(an));
             logline("[stobe] GOAL_RETURN arrived actor=%s at=%s dist=%.0f",r->actor,an,wgp_distance(a,p));}''')
rep(r'''            if(!strcmp(g->kind,"FETCH")&&g->state==STG_STATE_COMPLETE&&g->destination[0]&&!g->has_dest&&g->completed>0)
                sgr_start_give(g->actor_serial,g->actor,g->item,g->destination,g->completed); /* item 76 */''',
r'''            if((!strcmp(g->kind,"FETCH")||!strcmp(g->kind,"BUY"))&&g->state==STG_STATE_COMPLETE&&g->destination[0]&&!g->has_dest&&g->completed>0)
                sgr_start_give(g->actor_serial,g->actor,g->item,g->destination,g->completed); /* items 76/82 */''')
p.write_text(s)
print('patched')
