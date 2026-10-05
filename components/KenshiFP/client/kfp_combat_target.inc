/* Read-only intended-target context, independent of actual projectile victim.
 * Caller owns native crash guard. Full IDs must agree after native resolution. */
typedef void *(*combat_hand_character_t)(const void *);
static combat_hand_character_t g_combat_hand_character;
static void *combat_ray_target(const CombatRayHit *hit,void *shooter) {
    if (!hit||!hit->shape||hit->ids[0]!=1||!g_combat_hand_character||!g_combat_hit_ctor)return NULL;
    union {uint64_t alignment;unsigned char bytes[0x60];} raw={0};
    g_combat_hit_ctor(raw.bytes,0,1,-99.0f); /* constructs native embedded hand */
    memcpy(raw.bytes+0x38,hit->ids,sizeof(hit->ids));
    void *pc=g_combat_hand_character(raw.bytes+0x30);
    if (pc==shooter||!char_valid(pc)||
        !readable((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),sizeof(hit->ids))||
        memcmp((void *)((uintptr_t)pc+CHAR_HANDLE+HAND_IDS),hit->ids,sizeof(hit->ids)))return NULL;
    return pc;
}
static int fp_combat_target_init(void) {
    g_combat_hand_character=(combat_hand_character_t)combat_unique_signature(
      "40 57 48 83 EC 30 48 C7 44 24 20 FE FF FF FF 48 89 5C 24 48 48 8B F9 8B 41 08 83 F8 01 74 59 83 F8 5B 75 4D");
    return g_combat_hand_character!=NULL;
}
