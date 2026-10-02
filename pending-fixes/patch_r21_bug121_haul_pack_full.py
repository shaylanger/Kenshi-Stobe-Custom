#!/usr/bin/env python3
"""Bug 121: a work goal with a full pack loops "could not take" forever.

Run 9 (test 37): Malzin's pack was full; her building-material goal logged
"WORK_GOAL haul: could not take Raw Stone from Stone Mine" about once a
second, never blocked, and the step kept saying "Making ... 0/3". After 5
failed takes in a row the goal is now BLOCKED "her pack is full: can't
carry <item> from <source>" (one log line).

Usage: patch_r21_bug121_haul_pack_full.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
old = """        logline("[stobe] WORK_GOAL haul: could not take %s from %s",dep,sname);
        return 0;
"""
new = """        { /* bug 121: a take that keeps failing means her pack is full: block with the
           * reason instead of retrying every tick */
            static void *fail_goal; static int fails;
            if(fail_goal!=(void *)g){fail_goal=(void *)g;fails=0;}
            if(++fails>=5){
                char why[256];
                snprintf(why,sizeof(why),"her pack is full: can't carry %s from %s",dep,sname);
                logline("[stobe] WORK_GOAL haul: could not take %s from %s -- blocking",dep,sname);
                fails=0;fail_goal=NULL;
                wgp_goal_block(g,why);
                return 1;
            }
            snprintf(g->current_step,sizeof(g->current_step),"Her pack is full: can't carry %s from %s",dep,sname);
        }
        return 1;
"""
if 'bug 121' in text:
    print('already patched')
    sys.exit(0)
assert text.count(old) == 1, 'anchor not found exactly once'
path.write_text(text.replace(old, new), encoding='utf-8', newline='')
print('patched', path)
