/* The legacy Entity probe owns/clobbers the shared guard: never nest it.
 * Probe before arming manual native calls; verify cached skeleton inside them. */
static void combat_prepare_body_entity(void) {
    if (g_guard_armed||g_anim_ent_off!=-1||!char_valid(g_fp_control_actor))return;
    void *pc=g_fp_control_actor;
    void *anim=readable((void *)((uintptr_t)pc+CHAR_ANIM),8)?
        *(void **)((uintptr_t)pc+CHAR_ANIM):NULL;
    if (readable(anim,ANIM_SKELETON+8))find_body_entity(anim);
}
static void *combat_cached_body_entity(void *anim) {
    if (g_anim_ent_off<0||!g_entity_getskel||!readable(anim,ANIM_SKELETON+8)||
        !readable((void *)((uintptr_t)anim+g_anim_ent_off),8))return NULL;
    void *entity=*(void **)((uintptr_t)anim+g_anim_ent_off);
    void *skeleton=*(void **)((uintptr_t)anim+ANIM_SKELETON);
    if (!skeleton||!readable(entity,0x100)||g_entity_getskel(entity)!=skeleton)return NULL;
    return entity;
}
