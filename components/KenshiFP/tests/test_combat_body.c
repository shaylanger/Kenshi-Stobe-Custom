#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#define CHAR_ANIM 8
#define ANIM_SKELETON 16
static unsigned char pc[64],anim[64],entity[256];
static int skeleton,other;
static void *g_fp_control_actor=pc;
static int g_guard_armed,g_anim_ent_off=-1,probes;
static int char_valid(void *p) {return p==pc;}
static int readable(void *p,size_t size) {
 uintptr_t x=(uintptr_t)p;
 uintptr_t starts[]={(uintptr_t)pc,(uintptr_t)anim,(uintptr_t)entity};
 size_t sizes[]={sizeof(pc),sizeof(anim),sizeof(entity)};
 for(int i=0;i<3;++i)if(x>=starts[i]&&x-starts[i]<=sizes[i]&&size<=sizes[i]-(x-starts[i]))return 1;
 return 0;
}
static void *find_body_entity(void *p) {assert(!g_guard_armed&&p==anim);++probes;g_anim_ent_off=24;return entity;}
static void *getskel(void *p) {assert(p==entity);return &skeleton;}
static void *(*g_entity_getskel)(void *)=getskel;
#include "../client/kfp_combat_body.inc"
int main(void) {
 void *p=anim;memcpy(pc+CHAR_ANIM,&p,8);p=&skeleton;memcpy(anim+ANIM_SKELETON,&p,8);
 p=entity;memcpy(anim+24,&p,8);
 g_guard_armed=1;combat_prepare_body_entity();assert(!probes);
 g_guard_armed=0;combat_prepare_body_entity();assert(probes==1&&g_anim_ent_off==24);
 g_guard_armed=1;assert(combat_cached_body_entity(anim)==entity);assert(probes==1);
 p=&other;memcpy(anim+ANIM_SKELETON,&p,8);assert(!combat_cached_body_entity(anim));
 g_anim_ent_off=-1;assert(!combat_cached_body_entity(anim));
 g_guard_armed=0;g_fp_control_actor=NULL;combat_prepare_body_entity();assert(probes==1);
 g_anim_ent_off=24;g_entity_getskel=NULL;assert(!combat_cached_body_entity(anim));
 puts("B16 PASS body probe guard exclusion and cached skeleton identity; native Entity not validated");return 0;
}
