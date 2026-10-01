#!/usr/bin/env python3
"""KenshiFP round 17h: bugs 65 (KenshiFP side), 67, 68, 69, 70.

65: goal reports were requested while she was still far off (180 units), and the
    DLL's initiative turn found no candidates. Reports now trigger within 70 units
    (after the walk-back arrives).
67: patrol waypoints were building centres (path_failed: Kenshi drops the move).
    Waypoints now sit 90 units from each building toward the patrol centre, and a
    waypoint that makes no progress for 8 ticks is skipped.
68: LOOT found no dead body (Sorth died at Home; "nothing on nearby downed targets").
    The character scan also merges getObjectsWithinSphere(type CHARACTER), and the
    first empty pass logs what it saw ("TASK_GOAL loot scan ...").
69: hauling took 2 Water out of the Bread Oven's input to water the farm. Haul
    sources are now storage, mines, and production buildings whose OUTPUT is the item.
70: the status hid "Waiting for <farm> to grow" (an outer "Obtaining X for Y"
    overwrote it), and a farm with no water to bring waited forever. Detail steps are
    kept; a farm missing an input that nobody can bring blocks after 60 s with
    "<farm> has no <Water> and none is available to carry".

Usage: patch_kfp_round17h.py <KenshiFP root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    f = root / "client" / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("stobe_work_planner.inc", [
    # 65
    ("    if (wgp_distance(a,p)>180.0f) return;", "    if (wgp_distance(a,p)>70.0f) return; /* report once she is back (bug 65) */"),
    # 70: runtime field
    ("    DWORD power_wait_ms;\n",
     "    DWORD power_wait_ms;\n    DWORD farm_dry_ms;          /* runtime only: farm missing an input nobody can bring */\n"),
    # 70: keep detail steps
    ('            snprintf(g->current_step,sizeof(g->current_step),"Obtaining %s for %s",dep,item);',
     '            if (strncmp(g->current_step,"Waiting",7) && strncmp(g->current_step,"Fetching",8) &&\n'
     '                strncmp(g->current_step,"Carrying",8) && strncmp(g->current_step,"Loaded",6) &&\n'
     '                strncmp(g->current_step,"Picked",6))\n'
     '                snprintf(g->current_step,sizeof(g->current_step),"Obtaining %s for %s",dep,item);'),
    # 70: dry farm
    ("""    if (wgp_icontains(p.building_name,"farm")) {
        /* Inputs are in; the crop needs game time. Not a stall. */
        snprintf(g->current_step,sizeof(g->current_step),"Waiting for %s to grow %s",p.building_name,item);
        g->last_progress_ms=GetTickCount();
        return 0;
    }""",
     """    if (wgp_icontains(p.building_name,"farm")) {
        void *fm[WGP_MAX_MISSING]={0};
        int fmiss=p.production?wgp_missing(p.production,fm,WGP_MAX_MISSING):0;
        if (fmiss>0) {
            /* feed_inputs found nothing to carry: e.g. the well is dry/unpowered (bug 70). */
            char dn[128]={0}; wgp_name(fm[0],dn,sizeof(dn));
            DWORD now2=GetTickCount();
            if (!g->farm_dry_ms) g->farm_dry_ms=now2;
            if ((LONG)(now2-g->farm_dry_ms)>2*WGP_POWER_WAIT_MS) {
                snprintf(reason,reason_sz,"%s has no %s and none is available to carry (check the well or water storage)",
                         p.building_name,dn[0]?dn:"input");
                return -1;
            }
            snprintf(g->current_step,sizeof(g->current_step),"Waiting: %s needs %s and none is available",p.building_name,dn[0]?dn:"input");
            g->last_progress_ms=now2;
            return 0;
        }
        g->farm_dry_ms=0;
        /* Inputs are in; the crop needs game time. Not a stall. */
        snprintf(g->current_step,sizeof(g->current_step),"Waiting for %s to grow %s",p.building_name,item);
        g->last_progress_ms=GetTickCount();
        return 0;
    }"""),
])

patch("stobe_task_goals.inc", [
    # 65 (task goals)
    ("||wgp_distance(a,p)>180.0f)return;", "||wgp_distance(a,p)>70.0f)return; /* report once she is back (bug 65) */"),
    # 69: haul sources
    ("            if(!g_wgp_isplayer_building(x)&&sp!=WGP_BF_MINE&&sp!=WGP_BF_MINE_NATURAL)continue;",
     """            if(!g_wgp_isplayer_building(x)&&sp!=WGP_BF_MINE&&sp!=WGP_BF_MINE_NATURAL)continue;
            {
                /* Only storage, mines, or a machine whose OUTPUT is this item: never
                 * another machine's input (bug 69: water taken out of the oven). */
                int ok_src=(sp==STG_BF_RESOURCE_STORAGE||sp==STG_BF_GENERAL_STORAGE||sp==WGP_BF_MINE||sp==WGP_BF_MINE_NATURAL);
                if(!ok_src){
                    void *pr=wgp_building_production(x);
                    void *ogd=pr?wgp_prod_item(pr):NULL;
                    char on[160]={0};
                    if(ogd&&wgp_name(ogd,on,sizeof(on))&&wgp_name_match(on,dep)>0)ok_src=1;
                }
                if(!ok_src)continue;
            }"""),
    # 68: scan merges object search for characters
    ("""    g_stobe_getchars(gw,&l,&c,STG_SCAN_RADIUS,0,0,max,max,actor);
    if(!l.stuff||l.count>(uint32_t)max)return 0;
    return (int)l.count;""",
     """    g_stobe_getchars(gw,&l,&c,STG_SCAN_RADIUS,0,0,max,max,actor);
    if(!l.stuff||l.count>(uint32_t)max)return 0;
    int n=(int)l.count;
    /* Dead bodies may not come back from the character sphere search (bug 68):
     * merge the generic object search for CHARACTER (itemType 1). */
    if(g_stobe_getobjects&&n<max){
        void *extra[128]={0};
        StobePtrLektor l2; memset(&l2,0,sizeof(l2)); l2.max_size=128; l2.stuff=extra;
        g_stobe_getobjects(gw,&l2,&c,STG_SCAN_RADIUS,1,128,actor);
        if(l2.stuff&&l2.count<=128){
            for(uint32_t i=0;i<l2.count&&n<max;i++){
                void *x=extra[i];int dup=0;
                if(!x)continue;
                for(int j=0;j<n;j++)if(out[j]==x){dup=1;break;}
                if(!dup)out[n++]=x;
            }
        }
    }
    return n;"""),
    # 68: diagnostics when a loot pass finds nothing
    ("""static void stg_tick_loot(void *gw,void *actor,StgGoal *g)
{""",
     """static void stg_loot_scan_log(void *gw,void *actor,StgGoal *g)
{
    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    int dead=0,downed=0,valid=0;
    for(int i=0;i<n;i++){
        void *c=chars[i];if(!c||!char_valid(c))continue;
        if(stg_exports()&&g_stg_isdead(c))dead++;
        int pr=char_prone_state(c);if(pr==2||pr==3||pr==4)downed++;
        if(stg_valid_downed(actor,c,g->target))valid++;
    }
    logline("[stobe] TASK_GOAL loot scan id=%s target=%s item=%s scanned=%d dead=%d downed=%d valid=%d",
            g->id,g->target,g->item,n,dead,downed,valid);
}

static void stg_tick_loot(void *gw,void *actor,StgGoal *g)
{"""),
    ("""    stg_finish(g,STG_STATE_COMPLETE,"no more matching items on nearby downed targets");""",
     """    if(g->completed<=0)stg_loot_scan_log(gw,actor,g);
    stg_finish(g,STG_STATE_COMPLETE,"no more matching items on nearby downed targets");"""),
    # 67: reachable waypoints + skip stuck ones
    ("""        Vec3 bp=*(Vec3 *)((uintptr_t)x+0x48);
        if(wgp_distance(bp,g->patrol_center)>STG_PATROL_RADIUS)continue;""",
     """        Vec3 bp=*(Vec3 *)((uintptr_t)x+0x48);
        float bd=wgp_distance(bp,g->patrol_center);
        if(bd>STG_PATROL_RADIUS)continue;
        if(bd>90.0f){ /* stand beside the building, not in its centre (bug 67) */
            float k=90.0f/bd;
            bp.x+= (g->patrol_center.x-bp.x)*k; bp.z+=(g->patrol_center.z-bp.z)*k;
        }"""),
    ("""    if(stg_walk_to_pos(actor,g,t,d)){
        g->patrol_idx=(g->patrol_idx+1)%np;
        g->last_progress_ms=GetTickCount();
    }""",
     """    if(stg_walk_to_pos(actor,g,t,d)||g->walk_still>=8){
        /* arrived, or this waypoint can't be reached (path_failed): next one */
        g->walk_still=0;g->walk_last_dist=0;g->walk_next_ms=0;
        g->patrol_idx=(g->patrol_idx+1)%np;
        g->last_progress_ms=GetTickCount();
    }"""),
])
