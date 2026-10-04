# m26: WORK_STEP "missing input" throttle kept one key, so two alternating lines (Bread/Strawflour,
# Strawflour/Wheatstraw in A8) logged every ~60 ms. Keep a small ring of recent keys instead.
import sys
p=sys.argv[1]+'/client/stobe_work_planner.inc'
s=open(p).read()
old='''    static DWORD s_md_ms; static char s_md_key[192];
    char key[192]; snprintf(key,sizeof(key),"%s|%s|%d|%d",g->id,dep,need,bumped);
    if (strcmp(key,s_md_key) || (LONG)(GetTickCount()-s_md_ms)>10000) {
        s_md_ms=GetTickCount(); strncpy(s_md_key,key,sizeof(s_md_key)-1);
'''
new='''    /* m26: a ring of recent keys (one key let alternating chain lines through every tick) */
    static DWORD s_md_ms[8]; static char s_md_key[8][192]; static int s_md_next;
    char key[192]; snprintf(key,sizeof(key),"%s|%s|%d|%d",g->id,dep,need,bumped);
    int md_slot=-1; DWORD md_now=GetTickCount();
    for (int i=0;i<8;i++) if (!strcmp(key,s_md_key[i])) { md_slot=i; break; }
    if (md_slot<0 || (LONG)(md_now-s_md_ms[md_slot])>10000) {
        if (md_slot<0) { md_slot=s_md_next; s_md_next=(s_md_next+1)%8;
                         strncpy(s_md_key[md_slot],key,sizeof(s_md_key[0])-1); }
        s_md_ms[md_slot]=md_now;
'''
assert s.count(old)==1, 'anchor'
open(p,'w').write(s.replace(old,new))
print('patched')
