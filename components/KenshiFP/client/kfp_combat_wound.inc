/* R08 spatial body part for manual-adapter bolts (included by kfp_combat_native.inc).
 *
 * Native chain (kenshi_x64 1.0.65, static RE 2026-10-05; RVAs are notes only,
 * binding is by unique signature):
 *   GunClass::shoot -> spawn helper (0x43a2f0) returns the Harpoon*.
 *   Projectile manager (0x43afe0) per frame: Harpoon update (0x4380e0) reads its
 *   async tracer's PhysHit (harpoon+0x68 -> +8: hit +7, position +8, hand +0x30,
 *   group +0x50, root +0x58); a character hit stores victim at +0x78 and state
 *   +0x70 = 2 (3 = world, 1 = flying). Next the manager deletes the tracer and
 *   calls victim->iShotYou (0x439c90) -> MedicalSystem::addWound (0x6508d0,
 *   medical = character+0x458, CUT_PIERCED, Harpoon* last arg).
 *   addWound picks the part by weighted random over anatomy (+0x190 lektor:
 *   count +0x198, parts +0x1A0) with weight HealthPartStatus::hitChance (+0x38)
 *   (x hitChanceMult only for non-pierce cuts); parts that are destroyed or
 *   otherwise ineligible are skipped. hitChance is read nowhere else there.
 *
 * Spatial pick: only for harpoons spawned inside the manual dispatch (thread +
 * g_combat_dispatch), the REAL collision point (the PhysHit the native update
 * consumed, snapshotted just before it runs) and only when the PhysHit victim is
 * the wounded character and the attacker is the shooter. The part comes from
 * the victim's Biped bones (nearest segment; pose-aware) or, without a skeleton,
 * from the impact height above the feet. For that one addWound call the chosen
 * part's hitChance is multiplied by 1e6 and restored right after: damage, armour,
 * bleeding, hostility and XP stay native; a chosen part the native code skips
 * (destroyed limb etc.) leaves the native weighted pick among the rest.
 * Any failure -> untouched native call, counted in wound_native_fallback. */
#include "kfp_wound_geometry.h"
#define WOUND_CHAR_MEDICAL  0x458
#define WOUND_MED_ANAT_N    0x198
#define WOUND_MED_ANAT_P    0x1A0
#define WOUND_HPS_DATA      0x00
#define WOUND_HPS_TYPE      0x08
#define WOUND_HPS_SIDE      0x20
#define WOUND_HPS_HITCHANCE 0x38
#define WOUND_HARP_TRACER   0x68
#define WOUND_HARP_STATE    0x70
#define WOUND_HARP_VICTIM   0x78
#define WOUND_PH_HIT        0x07
#define WOUND_PH_POS        0x08
#define WOUND_PH_HAND       0x30
#define WOUND_PH_GROUP      0x50
#define WOUND_PH_ROOT       0x58
#define WOUND_PH_SIZE       0x60
#define WOUND_SLOTS 16
#define WOUND_MAX_AGE_MS 30000ULL
#define WOUND_BOOST 1.0e6f
typedef struct {
    void *harpoon,*shooter,*victim;
    float impact[3];
    float dir[3];          /* bolt direction at the shot (NAN: unknown) */
    int captured;          /* 0 flying, 1 impact captured, -1 hit without usable impact */
    const char *why;       /* reason when captured==-1 */
    ULONGLONG t;
} WoundShot;
typedef void *(*wound_spawn_t)(void *,void *,void *,void *);
typedef void (*wound_hupd_t)(void *);
typedef void *(*wound_add_t)(void *,char,int,void *,int *,void *,int *,void *);
static wound_spawn_t g_wound_spawn_orig;
static wound_hupd_t g_wound_hupd_orig;
static wound_add_t g_wound_add_orig;
static WoundShot g_wound_shot[WOUND_SLOTS];
/* Pre-spread direction of the manual shot being dispatched (set by combat_shot_prepare). */
static float g_wound_next_dir[3]={NAN,NAN,NAN};
static int g_wound_live, g_wound_ready, g_wound_fault, g_wound_enabled=1;
static unsigned g_wound_spawn_any,g_wound_spawn_dispatch; /* bolt spawns: any caller / inside our dispatch */
static unsigned g_wound_tracked, g_wound_impacts, g_wound_missed, g_wound_spatial, g_wound_fallback;
static int g_wound_last_part=-1, g_wound_last_group=KFP_WG_NONE;
static float g_wound_last_rel_h=NAN, g_wound_last_dist=NAN, g_wound_last_lat=NAN;
static float g_wound_last_bh[KFP_WH_COUNT]={NAN,NAN,NAN,NAN,NAN};  /* victim bone heights of the last wound */
static const char *g_wound_last_src="none", *g_wound_last_why="none";
static KfpWoundPick g_wound_last_pick={KFP_WG_NONE,NAN,NAN,KFP_WG_NONE,NAN,-1};  /* last bones pick (core_s, seg) */
static float g_wound_last_bw[KFP_WB_COUNT][3];   /* victim bone world points at that impact */
static int g_wound_last_have_bw;
/* Test switch (R11-LIMB): `fp_combat wound force <group>` replaces the spatial pick of the NEXT tracked bolt with
 * <group>, so the rest of the real path (part mapping, hit-chance boost, native addWound, spatial/fallback
 * accounting) runs on a group the geometry rarely yields (a fully severed leg has no physics shape: real impacts
 * near the hip are inside the torso silhouette). One-shot; last_src=forced marks the shot. */
static int g_wound_force_group=-1;
static unsigned g_wound_forced;
static unsigned char g_wound_bone_str[KFP_WB_COUNT][32];
static const char *const g_wound_bone_names[KFP_WB_COUNT]={
    "Bip01 Head","Bip01 HeadNub","Bip01 Neck","Bip01 Pelvis",
    "Bip01 L UpperArm","Bip01 L Forearm","Bip01 L Hand",
    "Bip01 R UpperArm","Bip01 R Forearm","Bip01 R Hand",
    "Bip01 L Thigh","Bip01 L Calf","Bip01 L Foot",
    "Bip01 R Thigh","Bip01 R Calf","Bip01 R Foot"};
/* MSVC std::string over a static literal (read-only consumer; never freed). */
static void wound_mstr(unsigned char *b32,const char *s) {
    size_t len=strlen(s);
    if (len<16) {make_mstr(b32,s);return;}
    memset(b32,0,32);*(const char **)b32=s;
    *(size_t *)(b32+0x10)=len;*(size_t *)(b32+0x18)=len;
}
static WoundShot *wound_find(void *harpoon) {
    ULONGLONG now=GetTickCount64();
    WoundShot *hit=NULL;
    for(int i=0;i<WOUND_SLOTS;++i) {
        WoundShot *s=&g_wound_shot[i];
        if (!s->harpoon) continue;
        if (now-s->t>WOUND_MAX_AGE_MS) {memset(s,0,sizeof(*s));--g_wound_live;continue;}
        if (s->harpoon==harpoon) hit=s;
    }
    return hit;
}
static void wound_drop(WoundShot *s) {
    if (s && s->harpoon) {memset(s,0,sizeof(*s));--g_wound_live;}
}
/* Harpoon spawn: remember bolts fired by the manual dispatch. Runs nested inside
 * the adapter's guarded tick: plain reads only, never arms the guard. */
static void *wound_spawn_hook(void *a,void *b,void *c,void *d) {
    void *h=g_wound_spawn_orig(a,b,c,d);
    ++g_wound_spawn_any;
    if (g_tur_dispatch && h) g_tur_harp=h;   /* T4: the FP turret shot's harpoon (kfp_turret.inc tracks its flight) */
    if (g_combat_dispatch && GetCurrentThreadId()==g_combat_dispatch_tid) ++g_wound_spawn_dispatch;
    if (!h) return h;
    if (g_wound_live) wound_drop(wound_find(h));     /* pooled address reused */
    if (g_wound_enabled && !g_wound_fault && g_combat_dispatch && g_combat_pc &&
        GetCurrentThreadId()==g_combat_dispatch_tid) {
        WoundShot *slot=NULL;
        for(int i=0;i<WOUND_SLOTS&&!slot;++i) if(!g_wound_shot[i].harpoon) slot=&g_wound_shot[i];
        if (!slot) {                                  /* full: replace the oldest */
            slot=&g_wound_shot[0];
            for(int i=1;i<WOUND_SLOTS;++i) if(g_wound_shot[i].t<slot->t) slot=&g_wound_shot[i];
            wound_drop(slot);
        }
        memset(slot,0,sizeof(*slot));
        slot->harpoon=h;slot->shooter=g_combat_pc;slot->t=GetTickCount64();
        memcpy(slot->dir,g_wound_next_dir,sizeof(slot->dir));
        ++g_wound_live;++g_wound_tracked;
    }
    return h;
}
/* Harpoon update: snapshot the PhysHit the native update is about to consume. */
static void wound_hupd_hook(void *h) {
    if (!g_wound_live) {g_wound_hupd_orig(h);return;}
    WoundShot *s=wound_find(h);
    unsigned char ph[WOUND_PH_SIZE];int have=0;
    if (s && !s->captured && readable(h,WOUND_HARP_VICTIM+8) &&
        *(int *)((uintptr_t)h+WOUND_HARP_STATE)==1) {
        void *tracer=*(void **)((uintptr_t)h+WOUND_HARP_TRACER);
        void *hit=readable(tracer,0x10)?*(void **)((uintptr_t)tracer+8):NULL;
        if (readable(hit,WOUND_PH_SIZE)) {memcpy(ph,hit,WOUND_PH_SIZE);have=1;}
    }
    g_wound_hupd_orig(h);
    if (!s || s->harpoon!=h || s->captured) return;
    int state=readable(h,WOUND_HARP_VICTIM+8)?*(int *)((uintptr_t)h+WOUND_HARP_STATE):-1;
    if (state==1) return;
    if (state!=2) {++g_wound_missed;wound_drop(s);return;}   /* world hit / gone */
    void *victim=*(void **)((uintptr_t)h+WOUND_HARP_VICTIM);
    s->victim=victim;s->captured=-1;
    float pos[3];memcpy(pos,ph+WOUND_PH_POS,sizeof(pos));
    void *root=have?*(void **)(ph+WOUND_PH_ROOT):NULL;
    int same=root?root==victim:
        have && char_valid(victim) && readable((void *)((uintptr_t)victim+CHAR_HANDLE+HAND_IDS),20) &&
        !memcmp(ph+WOUND_PH_HAND+HAND_IDS,(void *)((uintptr_t)victim+CHAR_HANDLE+HAND_IDS),20);
    if (!have) s->why="no_physhit";
    else if (!ph[WOUND_PH_HIT]) s->why="physhit_empty";
    else if (*(unsigned short *)(ph+WOUND_PH_GROUP)>1) s->why="physhit_group";
    else if (!kfp_wg_finite3(pos)) s->why="physhit_pos";
    else if (!same) s->why="physhit_victim";
    else {memcpy(s->impact,pos,sizeof(pos));s->captured=1;++g_wound_impacts;}
}
/* Victim Biped bones (world). Caller owns the crash guard. Returns 1 when every
 * bone but HeadNub is present (missing bones are NAN). */
static int wound_read_bones(void *victim,const Vec3 *feet,float bones[KFP_WB_COUNT][3]) {
    for(int b=0;b<KFP_WB_COUNT;++b) bones[b][0]=bones[b][1]=bones[b][2]=NAN;
    /* getBoneWorldPosition dereferences the AnimationClass: no skeleton -> no bones */
    void *anim=readable((void *)((uintptr_t)victim+CHAR_ANIM),8)?*(void **)((uintptr_t)victim+CHAR_ANIM):NULL;
    int have_bones=g_get_bone_world&&RVA_GET_BONE_WORLD&&readable(anim,ANIM_SKELETON+8)&&
                   readable(*(void **)((uintptr_t)anim+ANIM_SKELETON),8);
    for(int b=0;b<KFP_WB_COUNT&&have_bones;++b) {
        Vec3 w={NAN,NAN,NAN};
        g_get_bone_world(victim,&w,g_wound_bone_str[b]);
        /* the native call returns getPosition when the bone is missing */
        int missing=!isfinite(w.x)||!isfinite(w.y)||!isfinite(w.z)||(w.x==feet->x&&w.y==feet->y&&w.z==feet->z);
        if (!missing) {bones[b][0]=w.x;bones[b][1]=w.y;bones[b][2]=w.z;}
        if (missing && b!=KFP_WB_HEADNUB) have_bones=0;
    }
    return have_bones;
}
/* Bone heights above the feet (fp_combat aim). Caller owns the crash guard. */
static void wound_victim_heights(void *victim,float bh[KFP_WH_COUNT]) {
    Vec3 feet;float bones[KFP_WB_COUNT][3];
    for(int i=0;i<KFP_WH_COUNT;++i) bh[i]=NAN;
    if (!char_valid(victim)||!char_position(victim,&feet)) return;
    wound_read_bones(victim,&feet,bones);
    kfp_wound_bone_heights((const float (*)[3])bones,feet.y,bh);
}
/* Chooses anatomy part(s) for a captured impact. Own crash guard (never nested). */
static int wound_choose(void *med,void *victim,const WoundShot *s,void *parts[2],int idx[2],
                        const char **src,const char **why) {
    if (setjmp(g_guard_jb)) {g_guard_armed=0;g_wound_fault=1;*why="fault";
        logline("[combat] wound spatial read FAULTED -- spatial body part disabled");return 0;}
    guard_arm();
    int n=0,types[8],sides[8];
    unsigned count=readable((void *)((uintptr_t)med+WOUND_MED_ANAT_P),8)?*(unsigned *)((uintptr_t)med+WOUND_MED_ANAT_N):0;
    void **anat=count?*(void ***)((uintptr_t)med+WOUND_MED_ANAT_P):NULL;
    if (count<1||count>8||!readable(anat,count*8)) {*why="anatomy";goto out;}
    for(unsigned i=0;i<count;++i) {
        if (!readable(anat[i],WOUND_HPS_HITCHANCE+4)) {*why="anatomy";goto out;}
        types[i]=*(int *)((uintptr_t)anat[i]+WOUND_HPS_TYPE);
        sides[i]=*(int *)((uintptr_t)anat[i]+WOUND_HPS_SIDE);
    }
    if (!kfp_wound_humanoid(types,sides,(int)count)) {*why="anatomy";goto out;}
    Vec3 feet;
    if (!char_position(victim,&feet)) {*why="position";goto out;}
    float centre[3]={feet.x,feet.y,feet.z};
    g_wound_last_rel_h=s->impact[1]-feet.y;
    void *mv=readable((void *)((uintptr_t)victim+CHAR_MOVEMENT),8)?*(void **)((uintptr_t)victim+CHAR_MOVEMENT):NULL;
    g_wound_last_lat=readable((void *)((uintptr_t)mv+0xD0),12)?   /* CharMovement facing (world) */
        kfp_wound_lateral(s->impact,centre,*(float *)((uintptr_t)mv+0xD0),*(float *)((uintptr_t)mv+0xD8)):NAN;
    KfpWoundPick pick={KFP_WG_NONE,NAN,NAN,KFP_WG_NONE,NAN,-1};
    float bones[KFP_WB_COUNT][3];
    int have_bones=wound_read_bones(victim,&feet,bones);   /* no skeleton -> height mode */
    memcpy(g_wound_last_bw,bones,sizeof(bones));g_wound_last_have_bw=have_bones;
    kfp_wound_bone_heights((const float (*)[3])bones,feet.y,g_wound_last_bh);
    if (g_wound_force_group!=KFP_WG_NONE) {
        pick.group=g_wound_force_group;g_wound_force_group=KFP_WG_NONE;++g_wound_forced;*src="forced";
    } else if (have_bones && kfp_wound_from_bones(s->impact,(const float (*)[3])bones,s->dir,&pick)) *src="bones";
    else if (have_bones) {*why="bones_far";goto out;}
    else if (char_prone_state(victim)!=PS_NORMAL) {*why="pose";goto out;}
    else if (kfp_wound_from_height(g_wound_last_rel_h,g_wound_last_lat,&pick)) *src="height";
    else {*why="height";goto out;}
    g_wound_last_group=pick.group;g_wound_last_dist=pick.dist;g_wound_last_pick=pick;
    n=kfp_wound_part_index(pick.group,types,sides,(int)count,idx);
    if (!n) {*why="part_map";goto out;}
    for(int i=0;i<n;++i) parts[i]=anat[idx[i]];
out:
    g_guard_armed=0;
    return n;
}
/* Melee hit evidence (M08-UNARMED, 5090 batch m50-b): unarmed manual swings never moved the target's flesh and the
 * blood test could not tell a hit from the bleeding of older cuts. Every non-bolt addWound (lowBlow, cut direction,
 * Damages cut/blunt, attacker) is counted; melee_hits / melee_cut / melee_blunt are the ones whose attacker is the
 * fighter last owned by the manual melee adapter (set by fp_melee_manual_tick), wounds_any all of them. */
static void *g_wound_melee_attacker;
static unsigned g_wound_melee_hits,g_wound_any;
static float g_wound_melee_cut,g_wound_melee_blunt;
/* Wound ring (5090 m50-c: unarmed swings gave melee_hits +0 while wounds_any rose +15): the last 16 addWound calls
 * with victim, attacker, the owned fighter at that moment and the Damages fields, read by `fp_melee wounds [reset]`.
 * The wrapper maps the pointers to names with `fp_melee state <npc>` (actor=). */
typedef struct {void *victim,*attacker,*owned;float cut,blunt,pierce,stun;int area,low,bolt;unsigned n;} KfpWoundRec;
#define KFP_WOUND_RING 16
static KfpWoundRec g_wound_ring[KFP_WOUND_RING];
static unsigned g_wound_ring_n;
static void wound_ring_add(void *med,char low,int area,void *dmg,void *attacker,void *harpoon) {
    KfpWoundRec *w=&g_wound_ring[g_wound_ring_n%KFP_WOUND_RING];
    w->victim=(void *)((uintptr_t)med-WOUND_CHAR_MEDICAL);w->attacker=attacker;w->owned=g_wound_melee_attacker;
    w->cut=w->blunt=w->pierce=w->stun=NAN;
    if (dmg && readable(dmg,16)) {float *d=(float *)dmg;w->cut=d[0];w->blunt=d[1];w->pierce=d[2];w->stun=d[3];}
    w->area=area;w->low=low;w->bolt=harpoon!=NULL;w->n=++g_wound_ring_n;
}
static void fp_wound_ring_append(char *b,size_t n) {
    size_t l=(size_t)snprintf(b,n,"wounds=%u owned=%llx",g_wound_ring_n,(unsigned long long)(uintptr_t)g_wound_melee_attacker);
    unsigned first=g_wound_ring_n>KFP_WOUND_RING?g_wound_ring_n-KFP_WOUND_RING:0;
    for (unsigned i=first;i<g_wound_ring_n && l<n;++i) {
        KfpWoundRec *w=&g_wound_ring[i%KFP_WOUND_RING];
        l+=(size_t)snprintf(b+l,n-l," | #%u v=%llx a=%llx%s c=%.1f b=%.1f p=%.1f s=%.1f area=%d low=%d%s",w->n,(unsigned long long)(uintptr_t)w->victim,(unsigned long long)(uintptr_t)w->attacker,
            w->attacker&&w->attacker==w->owned?"(owned)":w->victim==w->owned?"(owned_victim)":"",w->cut,w->blunt,w->pierce,w->stun,w->area,w->low,w->bolt?" bolt":"");
    }
}
static void fp_wound_ring_reset(void) {g_wound_ring_n=0;}
static void *wound_add_hook(void *med,char low,int area,void *dmg,int *mat,void *attacker,int *dir,void *harpoon) {
    wound_ring_add(med,low,area,dmg,attacker,harpoon);
    if (!harpoon && attacker) {
        ++g_wound_any;
        if (attacker==g_wound_melee_attacker) {
            ++g_wound_melee_hits;
            if (dmg && readable(dmg,8)) {
                float c=((float *)dmg)[0],bl=((float *)dmg)[1];
                if (isfinite(c)) g_wound_melee_cut+=c;
                if (isfinite(bl)) g_wound_melee_blunt+=bl;
            }
        }
    }
    if (!harpoon || !g_wound_live) return g_wound_add_orig(med,low,area,dmg,mat,attacker,dir,harpoon);
    WoundShot *found=wound_find(harpoon);
    if (!found) return g_wound_add_orig(med,low,area,dmg,mat,attacker,dir,harpoon);
    WoundShot s=*found;wound_drop(found);           /* one wound per bolt */
    void *victim=(void *)((uintptr_t)med-WOUND_CHAR_MEDICAL);
    void *parts[2]={0};int idx[2]={-1,-1},n=0;float saved[2];
    const char *why=NULL,*src="none";
    g_wound_last_rel_h=NAN;g_wound_last_lat=NAN;g_wound_last_dist=NAN;g_wound_last_group=KFP_WG_NONE;
    for(int i=0;i<KFP_WH_COUNT;++i) g_wound_last_bh[i]=NAN;
    {KfpWoundPick z={KFP_WG_NONE,NAN,NAN,KFP_WG_NONE,NAN,-1};g_wound_last_pick=z;g_wound_last_have_bw=0;}
    if (!g_wound_enabled) why="off";
    else if (g_wound_fault) why="fault";
    else if (s.captured!=1) why=s.why?s.why:"no_impact";
    else if (victim!=s.victim) why="victim";
    else if (attacker!=s.shooter) why="attacker";
    else if (g_guard_armed) why="guard_busy";
    else n=wound_choose(med,victim,&s,parts,idx,&src,&why);
    int boosted=0;
    for(int i=0;i<n;++i) {
        float *w=(float *)((uintptr_t)parts[i]+WOUND_HPS_HITCHANCE);
        saved[i]=*w;
        if (isfinite(*w)&&*w>0) {*w*=WOUND_BOOST;++boosted;}
    }
    if (n&&!boosted) {why="weight0";}
    void *ret=g_wound_add_orig(med,low,area,dmg,mat,attacker,dir,harpoon);
    for(int i=0;i<n;++i) *(float *)((uintptr_t)parts[i]+WOUND_HPS_HITCHANCE)=saved[i];
    int chosen=-1;
    for(int i=0;i<n&&boosted;++i) if(ret && ret==*(void **)((uintptr_t)parts[i]+WOUND_HPS_DATA)) chosen=idx[i];
    g_wound_last_src=src;
    char bs[96];kfp_wound_heights_str(g_wound_last_bh,"",bs,sizeof(bs));
    char ps[640];kfp_wound_pick_str(&g_wound_last_pick,g_wound_last_have_bw?(const float (*)[3])g_wound_last_bw:NULL,"",ps,sizeof(ps));
    if (chosen>=0) {
        ++g_wound_spatial;g_wound_last_part=chosen;g_wound_last_why="none";
        logline("[combat] wound spatial part=%d %s src=%s rel_h=%.2f lat=%.2f dist=%.2f impact=%.2f,%.2f,%.2f dir=%.3f,%.3f,%.3f %s victim=%p%s",
            chosen,kfp_wound_group_name(g_wound_last_group),src,g_wound_last_rel_h,g_wound_last_lat,
            g_wound_last_dist,s.impact[0],s.impact[1],s.impact[2],s.dir[0],s.dir[1],s.dir[2],bs,victim,ps);
    } else {
        if (!why) why="ineligible";               /* native skipped the chosen part */
        ++g_wound_fallback;g_wound_last_part=-1;g_wound_last_why=why;
        logline("[combat] wound native fallback why=%s group=%s src=%s rel_h=%.2f %s victim=%p%s",
            why,kfp_wound_group_name(g_wound_last_group),src,g_wound_last_rel_h,bs,victim,ps);
    }
    return ret;
}
static void fp_combat_wound_state(char *b,size_t n) {
    char bs[96];kfp_wound_heights_str(g_wound_last_bh,"last_",bs,sizeof(bs));
    snprintf(b,n," wound_ready=%d wound_enabled=%d wound_fault=%d wound_tracked=%u wound_impacts=%u wound_missed=%u wound_spatial=%u wound_native_fallback=%u last_part=%d last_group=%s last_src=%s last_rel_h=%.2f last_lat=%.2f last_dist=%.2f last_fallback=%s %s last_core=%s last_core_s=%.2f last_seg=%s",
        g_wound_ready,g_wound_enabled,g_wound_fault,g_wound_tracked,g_wound_impacts,g_wound_missed,
        g_wound_spatial,g_wound_fallback,g_wound_last_part,kfp_wound_group_name(g_wound_last_group),
        g_wound_last_src,g_wound_last_rel_h,g_wound_last_lat,g_wound_last_dist,g_wound_last_why,bs,
        kfp_wound_group_name(g_wound_last_pick.core),g_wound_last_pick.core_s,kfp_wound_bone_name(g_wound_last_pick.seg));
}
/* fp_combat wound [on|off|reset] */
static int kah_fp_combat_wound(int argc,const char *const *argv,KAH_Reply *r) {
    if (argc==3 && !_stricmp(argv[2],"on")) g_wound_enabled=1;
    else if (argc==3 && !_stricmp(argv[2],"off")) g_wound_enabled=0;
    else if (argc==3 && !_stricmp(argv[2],"reset")) {
        g_wound_tracked=g_wound_impacts=g_wound_missed=g_wound_spatial=g_wound_fallback=0;
        g_wound_last_part=-1;g_wound_last_group=KFP_WG_NONE;g_wound_last_src=g_wound_last_why="none";
        g_wound_last_rel_h=g_wound_last_lat=g_wound_last_dist=NAN;
        for(int i=0;i<KFP_WH_COUNT;++i) g_wound_last_bh[i]=NAN;
        {KfpWoundPick z={KFP_WG_NONE,NAN,NAN,KFP_WG_NONE,NAN,-1};g_wound_last_pick=z;g_wound_last_have_bw=0;}
    } else if (argc==4 && !_stricmp(argv[2],"force")) {
        int g=kfp_wound_group_parse(argv[3]);
        if (g==KFP_WG_NONE && strcmp(argv[3],"none")) {r->append(r,"usage: fp_combat wound force head|chest|stomach|arm_l|arm_r|leg_l|leg_r|legs|none");return KAH_ERROR;}
        g_wound_force_group=g;
    } else if (argc!=2) {r->append(r,"usage: fp_combat wound [on|off|reset|force <group|none>]");return KAH_ERROR;}
    char b[900];fp_combat_wound_state(b,sizeof(b));
    {size_t l=strlen(b);snprintf(b+l,sizeof(b)-l," wound_force=%s wound_forced=%u",kfp_wound_group_name(g_wound_force_group),g_wound_forced);}
    r->append(r,b+1);return KAH_OK;
}
static void fp_combat_wound_init(void) {
    for(int i=0;i<KFP_WB_COUNT;++i) wound_mstr(g_wound_bone_str[i],g_wound_bone_names[i]);
    uintptr_t add=combat_unique_signature("48 8B C4 55 56 57 41 54 41 55 41 56 41 57 48 8D A8 F8 FC FF FF 48 81 EC D0 03 00 00 48 C7 45 50 FE FF FF FF 48 89 58 10 0F 29 70 B8 0F 29 78 A8");
    const char *add_how="prologue";
    if (!add) {
        /* 4080 batch 4: the full-prologue signature (unique in the 1.0.65 RE_Kenshi exe file at
         * 0x64FE40, 1.0.68 at 0x6508D0) found nothing in the live image: something patches the
         * first instructions at runtime (another plugin's hook). Bind by the body after the
         * 0x15-byte push/lea head (unique in both exes) and step back; KenshiLib::AddHook chains over a
         * hook another KenshiLib plugin already placed there. */
        uintptr_t body=combat_unique_signature("48 81 EC D0 03 00 00 48 C7 45 50 FE FF FF FF 48 89 58 10 0F 29 70 B8 0F 29 78 A8 44 0F 29 40 98 44 0F 29 48 88 44 0F 29 90 78 FF");
        if (body) {add=body-0x15;add_how="body-0x15";}
        else add_how="missing";
        if (add && readable((void *)add,8)) {
            const unsigned char *h=(const unsigned char *)add;
            logline("[combat] addWound prologue patched at runtime: head %02X %02X %02X %02X %02X %02X (bound by %s)",
                h[0],h[1],h[2],h[3],h[4],h[5],add_how);
        }
    }
    uintptr_t upd=combat_unique_signature("48 8B C4 55 57 48 8D 68 A1 48 81 EC E8 00 00 00 83 79 70 01 F3 0F 10 05 ?? ?? ?? ?? 48 8B F9 F3 0F 58 41 60 F3 0F 11 41");
    uintptr_t spawn=combat_unique_signature("4C 8B DC 56 57 41 54 41 55 41 56 48 81 EC F0 00 00 00 48 C7 44 24 60 FE FF FF FF 49 89 5B 20 48 8B 05 ?? ?? ?? ?? 48 33");
    int a=0,u=0,s=0;
    /* Hook order: consumers first, so a partial install never tracks bolts it can't use. */
    if (add && upd && spawn) {
        a=install_hook((void *)add,(void *)wound_add_hook,(void **)&g_wound_add_orig);
        u=a&&install_hook((void *)upd,(void *)wound_hupd_hook,(void **)&g_wound_hupd_orig);
        s=u&&install_hook((void *)spawn,(void *)wound_spawn_hook,(void **)&g_wound_spawn_orig);
    }
    g_wound_ready=a&&u&&s;   /* without the spawn hook nothing is tracked: all native */
    logline("[combat] spatial wound addWound bind=%s",add_how);
    logline("[combat] spatial wound hooks addWound=%p/%d harpoonUpdate=%p/%d spawn=%p/%d ready=%d boneWorld=%d",
        (void *)add,a,(void *)upd,u,(void *)spawn,s,g_wound_ready,!!(g_get_bone_world&&RVA_GET_BONE_WORLD));
}
