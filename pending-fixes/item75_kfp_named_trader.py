#!/usr/bin/env python3
"""Item 75 (KenshiFP): a BUY/SELL goal for a named trader 285 away blocked with "requested trader is
not nearby/loaded": the trader search only covered STG_SCAN_RADIUS (220). A named trader is now
searched among loaded characters within 1000 (exact/contained name, then the name without its
bracket title) and walked to. Usage: item75_kfp_named_trader.py <KenshiFP root>"""
import sys, pathlib

p = pathlib.Path(sys.argv[1]) / 'client/stobe_task_goals.inc'
s = p.read_text()
if 'STG_TRADER_NAMED_RADIUS' in s:
    print('already patched'); sys.exit(0)

def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, f'anchor found {n} times: {old[:70]!r}'
    s = s.replace(old, new)

rep(r'''#define STG_SCAN_RADIUS 220.0f''',
r'''#define STG_SCAN_RADIUS 220.0f
#define STG_TRADER_NAMED_RADIUS 1000.0f /* item 75: a named trader further off is walked to */''')
rep(r'''static int stg_scan_chars(void *gw,void *actor,void **out,int max)
{
    if(!gw||!actor||!out||max<1)return 0;''',
r'''static int stg_scan_chars_r(void *gw,void *actor,void **out,int max,float radius);
static int stg_scan_chars(void *gw,void *actor,void **out,int max)
{
    return stg_scan_chars_r(gw,actor,out,max,STG_SCAN_RADIUS);
}

static int stg_scan_chars_r(void *gw,void *actor,void **out,int max,float radius)
{
    if(!gw||!actor||!out||max<1)return 0;''')
rep(r'''    g_stobe_getchars(gw,&l,&c,STG_SCAN_RADIUS,0,0,max,max,actor);''',
r'''    g_stobe_getchars(gw,&l,&c,radius,0,0,max,max,actor);''')
rep(r'''        g_stobe_getobjects(gw,&l2,&c,STG_SCAN_RADIUS,1,128,actor);''',
r'''        g_stobe_getobjects(gw,&l2,&c,radius,1,128,actor);''')
rep(r'''    void *chars[128]={0};int n=stg_scan_chars(gw,actor,chars,128);
    Vec3 ap={0,0,0};if(!char_position(actor,&ap))return NULL;
    void *best=NULL;float bestd=1.0e30f;char bestn[128]={0};
    for(int i=0;i<n;i++){
        void *c=chars[i];if(!char_valid(c)||c==actor||!g_stg_is_trader(c))continue;
        char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
        if(requested&&*requested&&wgp_name_match(cn,requested)<=0)continue;
        Vec3 cp={0,0,0};if(!char_position(c,&cp))continue;
        float d=wgp_distance(ap,cp);
        if(d<bestd){best=c;bestd=d;strncpy(bestn,cn,sizeof(bestn)-1);}
    }''',
r'''    /* Item 75: a named trader is looked up among loaded characters within
     * STG_TRADER_NAMED_RADIUS (she walks there); unnamed = the nearest one close by. */
    int named=requested&&*requested;
    void *chars[256]={0};int n=stg_scan_chars_r(gw,actor,chars,256,named?STG_TRADER_NAMED_RADIUS:STG_SCAN_RADIUS);
    Vec3 ap={0,0,0};if(!char_position(actor,&ap))return NULL;
    void *best=NULL;float bestd=1.0e30f;char bestn[128]={0};int bestq=0;
    for(int i=0;i<n;i++){
        void *c=chars[i];if(!char_valid(c)||c==actor||!g_stg_is_trader(c))continue;
        char cn[128]={0};stg_char_name(c,cn,sizeof(cn));
        int q=0;
        if(named){
            q=wgp_name_match(cn,requested); /* 3 exact, 2 contained */
            if(q<=0){ /* the name without its bracket title */
                char bare[128]={0};strncpy(bare,cn,sizeof(bare)-1);
                char *br=strchr(bare,'[');
                if(br){*br='\0';size_t L=strlen(bare);while(L&&bare[L-1]==' ')bare[--L]='\0';}
                if(bare[0]&&wgp_name_match(bare,requested)>0)q=1;
            }
            if(q<=0||q<bestq)continue;
        }
        Vec3 cp={0,0,0};if(!char_position(c,&cp))continue;
        float d=wgp_distance(ap,cp);
        if(q>bestq||d<bestd){best=c;bestd=d;bestq=q;strncpy(bestn,cn,sizeof(bestn)-1);}
    }''')
p.write_text(s)
print('patched')
