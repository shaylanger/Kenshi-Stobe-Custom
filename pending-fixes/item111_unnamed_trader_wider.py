#!/usr/bin/env python3
"""Item 111 (KenshiFP): an unnamed BUY ("from the shop here") also finds a trader beyond 220 m.

m18 Squin STOBE 14: the shop's trader (Double) was 272 m from Kint; an unnamed trader search only scans
STG_SCAN_RADIUS (220), so "the shop here" would block with "no nearby loaded trader". Now the unnamed
search retries with STG_TRADER_NAMED_RADIUS (1000, she walks there) when nothing is within 220.

Usage: item111_unnamed_trader_wider.py <KenshiFP root>
"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = p.read_text()
old = """    int named=requested&&*requested;
    void *chars[256]={0};int n=stg_scan_chars_r(gw,actor,chars,256,named?STG_TRADER_NAMED_RADIUS:STG_SCAN_RADIUS);
    Vec3 ap={0,0,0};if(!char_position(actor,&ap))return NULL;
    void *best=NULL;float bestd=1.0e30f;char bestn[128]={0};int bestq=0;
    for(int i=0;i<n;i++){"""
new = """    int named=requested&&*requested;
    Vec3 ap={0,0,0};if(!char_position(actor,&ap))return NULL;
    void *best=NULL;float bestd=1.0e30f;char bestn[128]={0};int bestq=0;
    /* Item 111: unnamed ("the shop here") retries out to the named radius when none is close by. */
    for(int pass=0;pass<(named?1:2)&&!best;pass++){
    void *chars[256]={0};int n=stg_scan_chars_r(gw,actor,chars,256,(named||pass)?STG_TRADER_NAMED_RADIUS:STG_SCAN_RADIUS);
    for(int i=0;i<n;i++){"""
if new in s:
    print('already patched'); sys.exit(0)
assert s.count(old) == 1, 'anchor 1'
s = s.replace(old, new)
old2 = """        if(q>bestq||d<bestd){best=c;bestd=d;bestq=q;strncpy(bestn,cn,sizeof(bestn)-1);}
    }
    if(best&&name&&namesz){"""
new2 = """        if(q>bestq||d<bestd){best=c;bestd=d;bestq=q;strncpy(bestn,cn,sizeof(bestn)-1);}
    }
    }
    if(best&&name&&namesz){"""
assert s.count(old2) == 1, 'anchor 2'
s = s.replace(old2, new2)
p.write_text(s)
print('patched')
