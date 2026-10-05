#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
typedef struct {float x,y,z;} Vec3;
static uintptr_t combat_unique_signature(const char *s) {(void)s;return 1;}
#include "../client/kfp_combat_trace.inc"
static unsigned char fixture[0x60];
static int calls;
static void *ctor(void *p,char abort,char group,float fallback) {
 assert(!abort&&group&&fallback==-99.0f);memset(p,0,0x60);return p;
}
static void trace(void *p,const Vec3 *o,const Vec3 *d,unsigned mask) {
 assert(o&&d&&mask==0x087f9e07u);memcpy(p,fixture,sizeof(fixture));++calls;
}
static void hit(Vec3 pos,float distance) {
 memset(fixture,0,sizeof(fixture));fixture[7]=1;
 memcpy(fixture+8,&pos,sizeof(pos));memcpy(fixture+0x20,&distance,4);
 uintptr_t shape=0x1234;uint32_t ids[5]={1,2,3,4,5};unsigned short group=17;
 memcpy(fixture+0x28,&shape,sizeof(shape));memcpy(fixture+0x38,ids,sizeof(ids));memcpy(fixture+0x50,&group,2);
}
int main(void) {
 assert(fp_combat_trace_init());g_combat_hit_ctor=ctor;g_combat_physics_trace=trace;
 Vec3 origin={0,0,0},direction={0,0,1};CombatRayHit result={0},sentinel={0};
 sentinel.distance=123;result=sentinel;
 fixture[4]=1;assert(combat_trace_ray(&origin,&direction,80,&result)==-1);assert(result.distance==123);
 memset(fixture,0,sizeof(fixture));assert(combat_trace_ray(&origin,&direction,80,&result)==0);assert(!result.shape&&!result.distance);
 hit((Vec3){0,0,10},10);assert(combat_trace_ray(&origin,&direction,80,&result)==1);
 assert(result.shape==0x1234&&result.group==17&&result.ids[4]==5&&result.distance==10);
 g_combat_camera_hit=result;assert(g_combat_camera_hit.ids[0]==1);
 hit((Vec3){0,0,81},81);assert(combat_trace_ray(&origin,&direction,80,&result)==0);assert(!result.shape);
 hit((Vec3){0,0,-1},1);result=sentinel;assert(combat_trace_ray(&origin,&direction,80,&result)==-1);assert(result.distance==123);
 hit((Vec3){NAN,0,10},10);assert(combat_trace_ray(&origin,&direction,80,&result)==-1);
 hit((Vec3){0,0,10},NAN);assert(combat_trace_ray(&origin,&direction,80,&result)==-1);
 int before=calls;Vec3 invalid={0,0,0};assert(combat_trace_ray(&origin,&invalid,80,&result)==-1);
 assert(combat_trace_ray(&origin,&direction,NAN,&result)==-1);assert(calls==before);
 g_combat_physics_trace=NULL;assert(combat_trace_ray(&origin,&direction,80,&result)==-1);
 puts("B14 PASS native trace adapter abort/miss/range/finite/identity contracts; native physics not validated");return 0;
}
