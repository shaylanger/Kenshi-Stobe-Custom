#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <setjmp.h>
#define _stricmp strcasecmp
#define KAH_OK 0
#define KAH_ERROR 1
typedef struct KAH_Reply {void (*append)(struct KAH_Reply *,const char *);} KAH_Reply;
static unsigned char pc[16],cc[0x2b8];
static void *g_gw_cache=(void *)1;
static int valid=1,allow_read=1;
static jmp_buf g_guard_jb;
static int g_guard_armed;
static char reply[1024];
static int char_valid(void *p){return valid&&p==pc;}
static void *fp_controlled_char(void *gw){assert(gw==g_gw_cache);return pc;}
static int readable(void *p,size_t n){return allow_read&&p==cc&&n<=sizeof(cc);}
static void guard_arm(void){g_guard_armed=1;}
static void logline(const char *fmt,...){(void)fmt;}
static void *native_get(void *p){assert(p==pc);return cc;}
static uintptr_t combat_unique_signature(const char *sig) {
 assert(!strcmp(sig,"48 8B 81 48 06 00 00 48 8B 40 08 C3"));
 return (uintptr_t)native_get;
}
static int fp_melee_state_append(char *b,size_t n,const void *c){(void)b;(void)n;assert(c==cc);return 0;}
/* harness API: only findCharacter is used (fp_melee state <npc>); NULL = old harness */
static struct {void *(*findCharacter)(const char *,char *,size_t);} g_kah;
static void fp_melee_set_passive(unsigned s){(void)s;}
static unsigned spam_n,spam_p;static void fp_melee_spam_start(unsigned n,unsigned p){spam_n=n;spam_p=p;}
static unsigned cl_ms,ss_resets;static void fp_melee_click_legal_start(unsigned ms){cl_ms=ms;}
static void fp_melee_swingstat_reset(void){++ss_resets;}
static int fp_melee_swingstat_append(char *b,size_t n){return snprintf(b,n,"atk_speed_mean=1.0000 techs=none");}
#include "../client/kfp_melee_observe.inc"
static void append(KAH_Reply *r,const char *s){(void)r;snprintf(reply,sizeof(reply),"%s",s);}
static void put_pointer(size_t off,void *v){memcpy(cc+off,&v,sizeof(v));}
static void put_int(size_t off,int v){memcpy(cc+off,&v,sizeof(v));}
static void put_float(size_t off,float v){memcpy(cc+off,&v,sizeof(v));}
static int command(const char *arg) {
 KAH_Reply r={append};const char *argv[]={"fp_melee",arg};reply[0]=0;
 return kah_fp_melee("test",2,argv,&r,NULL);
}
int main(void) {
 assert(command("state")==KAH_ERROR);
 fp_melee_observe_init();put_pointer(0x188,pc);
 cc[0x130]=1;cc[0x144]=1;cc[0x158]=0;
 put_int(0x1f0,0);put_int(0x1f4,4);put_int(0x228,2);
 put_float(0x140,.625f);put_float(0x148,.15f);put_float(0x14c,.25f);put_float(0x168,.016f);
 put_pointer(0x150,(void *)0x123456);put_pointer(0x290,(void *)0xabcdef);
 unsigned char saved[sizeof(cc)];memcpy(saved,cc,sizeof(cc));
 assert(command("state")==KAH_OK);assert(!g_guard_armed);
 assert(strstr(reply,"state=0 next=4 attacking=0.625000 dead=1 dead_left=0.150000"));
 assert(strstr(reply,"technique=123456 finished=0"));
 assert(strstr(reply,"target=abcdef"));assert(strstr(reply,"threats=2 frame_dt=0.016000"));
 assert(!memcmp(saved,cc,sizeof(cc))); /* Observer cannot mutate native readiness. */
 assert(command("on")==KAH_ERROR);
 allow_read=0;assert(command("state")==KAH_ERROR);assert(!g_guard_armed);allow_read=1;
 put_pointer(0x188,(void *)2);assert(command("state")==KAH_ERROR);assert(!g_guard_armed);
 valid=0;assert(command("state")==KAH_ERROR);
 {KAH_Reply r={append};const char *a3[]={"fp_melee","spam","15","200"},*a2[]={"fp_melee","spam","off"},*bad[]={"fp_melee","spam","0"},*badp[]={"fp_melee","spam","5","10"};
  assert(kah_fp_melee("t",4,a3,&r,NULL)==KAH_OK&&spam_n==15&&spam_p==200&&strstr(reply,"15 clicks every 200 ms"));
  assert(kah_fp_melee("t",3,a2,&r,NULL)==KAH_OK&&spam_n==0);
  assert(kah_fp_melee("t",3,bad,&r,NULL)==KAH_ERROR&&kah_fp_melee("t",4,badp,&r,NULL)==KAH_ERROR&&spam_n==0);
  const char *a1[]={"fp_melee","spam","7"};assert(kah_fp_melee("t",3,a1,&r,NULL)==KAH_OK&&spam_n==7&&spam_p==200);
  const char *c1[]={"fp_melee","click_legal"},*c2[]={"fp_melee","click_legal","2500"},*cb[]={"fp_melee","click_legal","50"},*cx[]={"fp_melee","click_legal","9x"};
  assert(kah_fp_melee("t",2,c1,&r,NULL)==KAH_OK&&cl_ms==6000&&kah_fp_melee("t",3,c2,&r,NULL)==KAH_OK&&cl_ms==2500);
  assert(kah_fp_melee("t",3,cb,&r,NULL)==KAH_ERROR&&kah_fp_melee("t",3,cx,&r,NULL)==KAH_ERROR&&cl_ms==2500);
  const char *w1[]={"fp_melee","swingstat"},*w2[]={"fp_melee","swingstat","reset"},*wb[]={"fp_melee","swingstat","x"};
  assert(kah_fp_melee("t",2,w1,&r,NULL)==KAH_OK&&ss_resets==0&&kah_fp_melee("t",3,w2,&r,NULL)==KAH_OK&&ss_resets==1);
  assert(kah_fp_melee("t",3,wb,&r,NULL)==KAH_ERROR&&ss_resets==1);}
 puts("RESULT B12 PASS production melee read-only snapshot, float state fields, ownership/binding guards, spam/click_legal/swingstat switch parsing; native layout/runtime unvalidated");
 return 0;
}
