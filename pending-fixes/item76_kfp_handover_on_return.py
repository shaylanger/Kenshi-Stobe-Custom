#!/usr/bin/env python3
"""Item 76 (KenshiFP): a finished FETCH whose destination is a person (label, no coordinates; the
server sets it for "bring it to me") hands the fetched items to that person when her walk-back
(GOAL_RETURN) arrives. Usage: item76_kfp_handover_on_return.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'give_item[128]' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:70]!r}'
    s = s.replace(old, new)

rep(r'''typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; int cleared; int last_skip; int logged_target; } SgrReturn;''',
r'''typedef struct { uint32_t serial; char actor[128]; DWORD until_ms; DWORD next_ms; int cleared; int last_skip; int logged_target;
                 char give_item[128]; char give_to[128]; int give_qty; /* item 76: hand a fetch over on arrival */ } SgrReturn;''')
rep(r'''static void sgr_start(uint32_t serial,const char *actor)
{''',
r'''static void sgr_start_give(uint32_t serial,const char *actor,const char *give_item,const char *give_to,int give_qty);
static void sgr_start(uint32_t serial,const char *actor)
{
    sgr_start_give(serial,actor,NULL,NULL,0);
}

static void sgr_start_give(uint32_t serial,const char *actor,const char *give_item,const char *give_to,int give_qty)
{''')
rep(r'''    slot->until_ms=now+SGR_GIVEUP_MS;slot->next_ms=now+1500; /* let the last order settle */
    logline("[stobe] GOAL_RETURN start actor=%s",slot->actor);''',
r'''    slot->until_ms=now+SGR_GIVEUP_MS;slot->next_ms=now+1500; /* let the last order settle */
    if(give_item&&*give_item&&give_to&&*give_to&&give_qty>0){
        strncpy(slot->give_item,give_item,sizeof(slot->give_item)-1);
        strncpy(slot->give_to,give_to,sizeof(slot->give_to)-1);
        slot->give_qty=give_qty;
    }
    logline("[stobe] GOAL_RETURN start actor=%s%s%s",slot->actor,slot->give_item[0]?" give_to=":"",slot->give_item[0]?slot->give_to:"");''')
rep(r'''        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            logline("[stobe] GOAL_RETURN arrived actor=%s",r->actor);''',
r'''        if(wgp_distance(a,p)<=SGR_STOP_DIST){
            logline("[stobe] GOAL_RETURN arrived actor=%s",r->actor);
            if(r->give_item[0]&&r->give_qty>0){
                /* item 76: "bring it to me": the named person if close, else the return target when it is that person */
                void *dst=wgp_find_squad_actor(gw,0,r->give_to);
                Vec3 dp={0,0,0};
                if(!dst||!char_position(dst,&dp)||wgp_distance(a,dp)>SGR_STOP_DIST*2){
                    char tn[128]={0};stg_char_name(player,tn,sizeof(tn));
                    dst=wgp_name_match(tn,r->give_to)>0?player:NULL;
                }
                int moved=dst?stg_transfer_char_to_char(actor,dst,r->give_item,r->give_qty):0;
                char dn[128]={0};if(dst)stg_char_name(dst,dn,sizeof(dn));
                logline("[stobe] GOAL_RETURN handed actor=%s item=%s qty=%d/%d to=%s",r->actor,r->give_item,moved,r->give_qty,dst?dn:"(not here)");
            }''')
rep(r'''        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){
            g->rt_return_started=1;sgr_start(g->actor_serial,g->actor);
        }''',
r'''        if(g->rt_seen_active&&!g->rt_return_started&&g->state!=STG_STATE_PAUSED){
            g->rt_return_started=1;
            if(!strcmp(g->kind,"FETCH")&&g->state==STG_STATE_COMPLETE&&g->destination[0]&&!g->has_dest&&g->completed>0)
                sgr_start_give(g->actor_serial,g->actor,g->item,g->destination,g->completed); /* item 76 */
            else sgr_start(g->actor_serial,g->actor);
        }''')
p.write_text(s)
print('patched')
