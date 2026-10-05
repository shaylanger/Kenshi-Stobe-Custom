#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
typedef struct {float x,y,z;} Vec3;
#define CHAR_HANDLE 16
#define HAND_IDS 8
static uintptr_t combat_unique_signature(const char *s) {(void)s;return 1;}
static unsigned char actor[64];
static void *resolved;
static int resolve_calls;
static int readable(void *p,size_t size) {return p==actor+CHAR_HANDLE+HAND_IDS&&size==20;}
static int char_valid(void *p) {return p==actor;}
#include "../client/kfp_combat_trace.inc"
#include "../client/kfp_combat_target.inc"
static void *ctor(void *p,char a,char b,float f) {(void)a;(void)b;(void)f;memset(p,0,0x60);return p;}
static void *resolve(const void *p) {
 const uint32_t *ids=(const uint32_t *)((const unsigned char *)p+8);
 assert(ids[0]==1&&ids[1]==2&&ids[2]==3&&ids[3]==4&&ids[4]==5);++resolve_calls;return resolved;
}
int main(void) {
 assert(fp_combat_trace_init()&&fp_combat_target_init());
 assert(combat_trace_ray(NULL,NULL,80,NULL)==-1);
 g_combat_hit_ctor=ctor;g_combat_hand_character=resolve;
 CombatRayHit hit={.shape=0x1234,.ids={1,2,3,4,5}};
 memcpy(actor+CHAR_HANDLE+HAND_IDS,hit.ids,20);resolved=actor;
 assert(combat_ray_target(&hit,NULL)==actor);assert(combat_ray_target(&hit,actor)==NULL);
 for(int i=0;i<5;++i) {
  ((uint32_t *)(actor+CHAR_HANDLE+HAND_IDS))[i]++;
  assert(combat_ray_target(&hit,NULL)==NULL);
  memcpy(actor+CHAR_HANDLE+HAND_IDS,hit.ids,20);
 }
 resolved=NULL;assert(combat_ray_target(&hit,NULL)==NULL);
 resolved=(void *)(uintptr_t)1;assert(combat_ray_target(&hit,NULL)==NULL);
 int before=resolve_calls;hit.ids[0]=11;assert(combat_ray_target(&hit,NULL)==NULL);
 hit.ids[0]=1;hit.shape=0;assert(combat_ray_target(&hit,NULL)==NULL);
 assert(combat_ray_target(NULL,NULL)==NULL);assert(resolve_calls==before);
 g_combat_camera_hit=hit;g_combat_hand_character=NULL;assert(combat_ray_target(&hit,NULL)==NULL);
 puts("B15 PASS intended target complete-identity/noncharacter/self/stale guards; native resolver not validated");return 0;
}
