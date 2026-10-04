#!/usr/bin/env python3
"""m25 (16-fullbase): a bench that reports a crafted input missing gets at least one more queued.

Junkbow needs more than one Hinge per unit; the planner assumed 1 input per output and the
item-95 accounting (have + consumed >= need) then called the Hinge satisfied while the
Crossbow bench sat on "needs: [Hinge]" forever. When the parent bench reports the dep
missing and none is on hand or queued, raise the need so the shortfall is >= 1, and log
the missing input by name.
Usage: python3 m25-kfp-missing-dep.py <KenshiFP root>
"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])
f = root / "client" / "stobe_work_planner.inc"
s = f.read_text()
if "wgp_missing_dep_need" in s:
    print("already applied"); sys.exit(0)

HELPER = '''/* m25 (16-fullbase): the parent bench reports `dep` missing. If none is on hand or queued
 * but item-95 accounting (consumed) would call it satisfied, the recipe takes more than one
 * per unit: raise the need so at least one more gets queued, and name the missing input. */
static int wgp_missing_dep_need(void *gw, void *actor, WgpGoal *g, const char *parent,
                                const char *dep, int need)
{
    WgpSubstate *ss=NULL;
    for (int i=0;i<WGP_MAX_SUBSTATE;i++)
        if (g->subs[i].item[0] && !_stricmp(g->subs[i].item,dep)) { ss=&g->subs[i]; break; }
    int have=wgp_item_count_world(gw,actor,dep);
    int bumped=need;
    /* keep the shortfall >= 1 (queue one) and, once queued, keep the dep "not ready" so she
     * is sent to craft it instead of item-95 calling it satisfied */
    if (ss && have<=0 && ss->consumed>0 && ss->consumed>=need)
        bumped=ss->consumed+(ss->queued>0?ss->queued:1);
    static DWORD s_md_ms; static char s_md_key[192];
    char key[192]; snprintf(key,sizeof(key),"%s|%s|%d|%d",g->id,dep,need,bumped);
    if (strcmp(key,s_md_key) || (LONG)(GetTickCount()-s_md_ms)>10000) {
        s_md_ms=GetTickCount(); strncpy(s_md_key,key,sizeof(s_md_key)-1);
        logline("[stobe] WORK_STEP id=%s %s missing input %s (have=%d queued=%d consumed=%d) need %d%s",
                g->id,parent,dep,have,ss?ss->queued:0,ss?ss->consumed:0,bumped,
                bumped>need?" (m25: recipe uses more per unit, queue 1 more)":"");
    }
    return bumped;
}

/* return 1 ready/available, 0 working/waiting, -1 impossible */
static int wgp_ensure_item('''

A1 = '''/* return 1 ready/available, 0 working/waiting, -1 impossible */
static int wgp_ensure_item('''
A2 = '''        int dneed=p.is_crafting?need:wgp_input_need(p.production,p.building_name,missing[i],need);
'''
B2 = A2 + '''        dneed=wgp_missing_dep_need(gw,actor,g,item,dep,dneed);
'''
A3 = '''        if (!root.is_crafting) outstanding=wgp_input_need(root.production,root.building_name,missing[i],outstanding);
'''
B3 = A3 + '''        outstanding=wgp_missing_dep_need(gw,actor,g,g->item,dep,outstanding);
'''
for a in (A1, A2, A3):
    assert s.count(a) == 1, "anchor not unique/missing: " + a[:60]
s = s.replace(A1, HELPER).replace(A2, B2).replace(A3, B3)
f.write_text(s)
print("patched", f)
