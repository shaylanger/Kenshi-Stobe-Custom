#!/usr/bin/env python3
"""Bug 38 (plan item 38): the work planner assumed 1 input per output.

wgp_ensure_item() got `need` = outputs still wanted and passed the same number to
every missing input, so a machine that eats 2 raw stone per building material got
only half the stone and sent her back to the mine.

Now the input count comes from the machine's own consumption data
(StorageBuilding::getNumConsumtionItems 0x588 / getConsumtionItems 0x590 and the
output's ConsumptionItem at 0x448): inputs = ceil(outputs * input.rate / output.rate).
Crafting benches keep the old behaviour (their recipes are queued per craft).
Logged once per change: `WORK_GOAL input ratio <machine>: <input> x<ratio>`.

Usage: patch_kfp_r24_input_ratio.py <KenshiFP root>  (idempotent)
"""
import sys
from pathlib import Path

f = Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
s = f.read_text(encoding='utf-8')
if 'wgp_input_need' in s:
    print('already patched'); sys.exit(0)

def sub(old, new, count=1):
    global s
    n = s.count(old)
    assert n == count, f'anchor found {n}x (want {count}): {old[:60]!r}'
    s = s.replace(old, new)

helper_anchor = "static int wgp_find_producer(void *gw, void *actor, const char *query, WgpProducer *out)\n{"
helper = r'''/* Bug 38: how many units of input `dep_gd` the machine eats for `outputs` units of
 * its product, from its consumption rates (input.rate / output.rate). Falls back
 * to 1:1 when the data can't be read. */
static int wgp_input_need(void *prod, const char *machine, void *dep_gd, int outputs)
{
    typedef int (*num_t)(void *);
    typedef void *(*get_t)(void *, int);
    if (outputs<1 || !prod || !dep_gd || !readable(prod,0x468)) return outputs;
    num_t nf=(num_t)wgp_vcall_ptr(prod,0x588);
    get_t gf=(get_t)wgp_vcall_ptr(prod,0x590);
    void *out=*(void **)((uintptr_t)prod+0x448);
    if (!nf || !gf || !readable(out,0x20)) return outputs;
    float orate=*(float *)((uintptr_t)out+4);
    if (!(orate>0.0f)) return outputs;
    int n=nf(prod);
    if (n<1 || n>8) return outputs;
    for (int i=0;i<n;i++) {
        void *ci=gf(prod,i);
        if (!ci || ci==out || !readable(ci,0x20)) continue;
        if (*(void **)((uintptr_t)ci+0x10)!=dep_gd) continue;
        float r=*(float *)((uintptr_t)ci+4);
        if (!(r>0.0f)) return outputs;
        float ratio=r/orate;
        if (ratio<0.05f || ratio>20.0f) return outputs;
        int need=(int)(outputs*ratio+0.999f);
        if (need<1) need=1;
        {
            static void *last_dep; static float last_ratio;
            if (last_dep!=dep_gd || last_ratio!=ratio) {
                char dn[128]={0}; wgp_name(dep_gd,dn,sizeof(dn));
                logline("[stobe] WORK_GOAL input ratio %s: %s x%.2f (in %.3f / out %.3f) -> %d for %d",
                        machine&&machine[0]?machine:"machine",dn,ratio,r,orate,need,outputs);
                last_dep=dep_gd; last_ratio=ratio;
            }
        }
        return need;
    }
    return outputs;
}

'''
sub(helper_anchor, helper + helper_anchor)

# recursion inside wgp_ensure_item
sub("        int r=wgp_ensure_item(gw,actor,g,dep,need,depth+1,next_chain,next_n,budget,reason,reason_sz);",
    "        int dneed=p.is_crafting?need:wgp_input_need(p.production,p.building_name,missing[i],need);\n"
    "        int r=wgp_ensure_item(gw,actor,g,dep,dneed,depth+1,next_chain,next_n,budget,reason,reason_sz);")

# root goal loop
sub("        int r=wgp_ensure_item(gw,actor,g,dep,outstanding,1,chain,1,&budget,reason,sizeof(reason));",
    "        if (!root.is_crafting) outstanding=wgp_input_need(root.production,root.building_name,missing[i],outstanding);\n"
    "        int r=wgp_ensure_item(gw,actor,g,dep,outstanding,1,chain,1,&budget,reason,sizeof(reason));")

f.write_text(s, encoding='utf-8')
print('patched', f)
