/* Synchronous native ray query. Call only under the main-loop guard.
 * Native abort policy is respected; no scene lock/scheduling bypass.
 * Shape/handle telemetry describes this query, not a projectile impact. */
typedef void *(*combat_hit_ctor_t)(void *,char,char,float);
typedef void (*combat_trace_t)(void *,const Vec3 *,const Vec3 *,unsigned);
static combat_hit_ctor_t g_combat_hit_ctor;
static combat_trace_t g_combat_physics_trace;
typedef struct {
    Vec3 position;
    float distance;
    uintptr_t shape;
    uint32_t ids[5];
    unsigned short group;
} CombatRayHit;
static CombatRayHit g_combat_camera_hit;
static int combat_trace_ray(const Vec3 *origin,const Vec3 *direction,float range,CombatRayHit *out) {
    if (!origin||!direction||!out||!g_combat_hit_ctor||!g_combat_physics_trace||
        !isfinite(range)||range<=0||!isfinite(origin->x)||!isfinite(origin->y)||!isfinite(origin->z)||
        !isfinite(direction->x)||!isfinite(direction->y)||!isfinite(direction->z))return -1;
    float norm=direction->x*direction->x+direction->y*direction->y+direction->z*direction->z;
    if (!isfinite(norm)||fabsf(norm-1)>0.001f)return -1;
    union { uint64_t alignment; unsigned char bytes[0x60]; } raw={0};
    g_combat_hit_ctor(raw.bytes,0,1,-99.0f);
    g_combat_physics_trace(raw.bytes,origin,direction,0x087f9e07u);
    if (raw.bytes[4])return -1; /* native scene unavailable */
    CombatRayHit result={0};
    if (!raw.bytes[7]) {*out=result;return 0;}
    memcpy(&result.position,raw.bytes+8,sizeof(Vec3));
    memcpy(&result.distance,raw.bytes+0x20,4);
    if (!isfinite(result.position.x)||!isfinite(result.position.y)||!isfinite(result.position.z)||
        !isfinite(result.distance)||result.distance<0)return -1;
    float along=(result.position.x-origin->x)*direction->x+
                (result.position.y-origin->y)*direction->y+(result.position.z-origin->z)*direction->z;
    if (!isfinite(along)||along<0)return -1;
    /* Native trace is infinite; only accept this finite aiming segment. */
    if (along>range||result.distance>range) {*out=(CombatRayHit){0};return 0;}
    memcpy(&result.shape,raw.bytes+0x28,sizeof(uintptr_t));
    memcpy(result.ids,raw.bytes+0x38,sizeof(result.ids));
    memcpy(&result.group,raw.bytes+0x50,2);
    *out=result;return 1;
}
static int fp_combat_trace_init(void) {
    g_combat_hit_ctor=(combat_hit_ctor_t)combat_unique_signature("40 53 48 83 EC 20 F3 0F 10 15 ?? ?? ?? ?? F3 0F 11 19 0F 57 DB 48 8B D9 C6 41 04 00 88 51 05 44 88 41 06 C6 41 07 00");
    g_combat_physics_trace=(combat_trace_t)combat_unique_signature("48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 81 EC 10 01 00 00 41 8B E9 49 8B F8 48 8B F2 48 8B D9 E8 ?? ?? ?? ?? 80 7B 05 00");
    return g_combat_hit_ctor&&g_combat_physics_trace;
}
