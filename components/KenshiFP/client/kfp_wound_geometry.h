#ifndef KFP_WOUND_GEOMETRY_H
#define KFP_WOUND_GEOMETRY_H
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
/* R08 spatial body part: pure geometry, no game memory. World units are
 * decimetres (B14). Groups map onto the victim's MedicalSystem anatomy
 * (the harness `hp` part index) by part type/side in kfp_wound_part_index. */
enum {
    KFP_WG_NONE=-1, KFP_WG_HEAD=0, KFP_WG_CHEST, KFP_WG_STOMACH,
    KFP_WG_ARM_L, KFP_WG_ARM_R, KFP_WG_LEG_L, KFP_WG_LEG_R,
    KFP_WG_LEGS            /* legs, side unknown: both legs stay eligible */
};
/* Biped bones read from the victim (Character::getBoneWorldPosition). */
enum {
    KFP_WB_HEAD, KFP_WB_HEADNUB, KFP_WB_NECK, KFP_WB_PELVIS,
    KFP_WB_L_UPPERARM, KFP_WB_L_FOREARM, KFP_WB_L_HAND,
    KFP_WB_R_UPPERARM, KFP_WB_R_FOREARM, KFP_WB_R_HAND,
    KFP_WB_L_THIGH, KFP_WB_L_CALF, KFP_WB_L_FOOT,
    KFP_WB_R_THIGH, KFP_WB_R_CALF, KFP_WB_R_FOOT,
    KFP_WB_COUNT
};
/* MedicalSystem::HealthPartStatus::PartType and LeftRight values. */
enum { KFP_PART_TORSO=0, KFP_PART_LEG=1, KFP_PART_ARM=2, KFP_PART_HEAD=3 };
enum { KFP_SIDE_NEITHER=0, KFP_SIDE_LEFT=1, KFP_SIDE_RIGHT=2 };
#define KFP_WOUND_CHEST_T   0.5f   /* pelvis->neck fraction where the chest starts */
#define KFP_WOUND_MAX_DIST  6.0f   /* impact farther than this from every segment: no pick */
/* Height-band fallback (standing ~17 dm column, feet = getPosition y). */
#define KFP_WOUND_H_HEAD    14.5f
#define KFP_WOUND_H_CHEST   11.0f
#define KFP_WOUND_H_STOMACH  8.5f
#define KFP_WOUND_H_MIN     -2.0f
#define KFP_WOUND_H_MAX     22.0f
#define KFP_WOUND_SIDE_MIN   0.3f  /* |lateral| below this: leg side unknown */
/* core/core_s: the head/torso candidate and its silhouette distance (view distance
 * minus radius, dm; limbs compete only above KFP_WOUND_CORE_MARGIN); seg: bone that
 * starts the winning limb segment, -1 when the core won (diagnostics, R08 5090 b9). */
typedef struct { int group; float dist; float torso_t; int core; float core_s; int seg; } KfpWoundPick;

static int kfp_wg_finite3(const float v[3]) {
    return isfinite(v[0])&&isfinite(v[1])&&isfinite(v[2]);
}
/* Distance from p to segment a-b; *t = clamped fraction along a->b. */
static float kfp_wg_seg_dist(const float p[3],const float a[3],const float b[3],float *t) {
    float ab[3]={b[0]-a[0],b[1]-a[1],b[2]-a[2]},ap[3]={p[0]-a[0],p[1]-a[1],p[2]-a[2]};
    float len2=ab[0]*ab[0]+ab[1]*ab[1]+ab[2]*ab[2],f=0;
    if (len2>1e-12f) {f=(ap[0]*ab[0]+ap[1]*ab[1]+ap[2]*ab[2])/len2;if(f<0)f=0;if(f>1)f=1;}
    float d[3]={ap[0]-ab[0]*f,ap[1]-ab[1]*f,ap[2]-ab[2]*f};
    if (t) *t=f;
    return sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);
}
/* Body part radii (dm) around the bone segments. */
#define KFP_WOUND_R_HEAD     1.0f
#define KFP_WOUND_R_TORSO    1.4f
#define KFP_WOUND_R_UPPERARM 0.5f
#define KFP_WOUND_R_FOREARM  0.45f
#define KFP_WOUND_R_THIGH    0.8f
#define KFP_WOUND_R_CALF     0.6f
#define KFP_WOUND_CORE_MARGIN 0.3f /* impact this close to the head/torso surface: core wins */
/* p minus its component along the unit vector u (u NULL: unchanged). */
static void kfp_wg_flat(const float p[3],const float o[3],const float *u,float out[3]) {
    float v[3]={p[0]-o[0],p[1]-o[1],p[2]-o[2]};
    float k=u?v[0]*u[0]+v[1]*u[1]+v[2]*u[2]:0;
    for(int i=0;i<3;++i) out[i]=v[i]-(u?u[i]*k:0);
}
/* Distance from the impact to segment a-b as the shooter sees it: measured
 * perpendicular to the bolt direction u (NULL: plain 3D). */
static float kfp_wg_view_dist(const float a[3],const float b[3],const float impact[3],const float *u,float *t) {
    static const float z[3]={0,0,0};
    float fa[3],fb[3];
    kfp_wg_flat(a,impact,u,fa);kfp_wg_flat(b,impact,u,fb);
    return kfp_wg_seg_dist(z,fa,fb,t);
}
/* Pelvis->neck fraction where the head zone starts: the neck bone minus one head
 * radius along the real (3D) spine (the shoulder line). */
static float kfp_wound_head_t(const float bones[KFP_WB_COUNT][3]) {
    float d[3]={bones[KFP_WB_NECK][0]-bones[KFP_WB_PELVIS][0],bones[KFP_WB_NECK][1]-bones[KFP_WB_PELVIS][1],
                bones[KFP_WB_NECK][2]-bones[KFP_WB_PELVIS][2]};
    float l=sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]),t=l>1e-3f?1.0f-KFP_WOUND_R_HEAD/l:1.0f;
    return t>KFP_WOUND_CHEST_T+0.1f?t:KFP_WOUND_CHEST_T+0.1f;   /* tiny skeletons keep a chest band */
}
/* Body part under the impact point (pose-aware: crouch, lean, KO, guard).
 * dir = bolt direction (any length; NULL/invalid: 3D distances). The impact is
 * the physics-shape contact, which sits in front of the bones, so distances are
 * taken perpendicular to the bolt and minus each part's radius. Head/torso win
 * whenever the impact lies on their silhouette: a guard stance holds the
 * forearms in front of face and chest, and an arm is picked only for an impact
 * clearly beside the core. */
static int kfp_wound_from_bones(const float impact[3],const float bones[KFP_WB_COUNT][3],const float *dir,KfpWoundPick *out) {
    out->group=KFP_WG_NONE;out->dist=NAN;out->torso_t=NAN;out->core=KFP_WG_NONE;out->core_s=NAN;out->seg=-1;
    if (!kfp_wg_finite3(impact)) return 0;
    for(int i=0;i<KFP_WB_COUNT;++i) if(i!=KFP_WB_HEADNUB && !kfp_wg_finite3(bones[i])) return 0;
    float u[3],*up=NULL;
    if (dir && kfp_wg_finite3(dir)) {
        float n=sqrtf(dir[0]*dir[0]+dir[1]*dir[1]+dir[2]*dir[2]);
        if (n>1e-4f) {for(int i=0;i<3;++i) u[i]=dir[i]/n;up=u;}
    }
    float top[3];
    if (kfp_wg_finite3(bones[KFP_WB_HEADNUB])) {
        for(int i=0;i<3;++i) top[i]=bones[KFP_WB_HEADNUB][i];
    } else {
        for(int i=0;i<3;++i) top[i]=bones[KFP_WB_HEAD][i]+(bones[KFP_WB_HEAD][i]-bones[KFP_WB_NECK][i]);
    }
    float t,torso_t;
    float dh=kfp_wg_view_dist(bones[KFP_WB_HEAD],top,impact,up,&t);
    float dt=kfp_wg_view_dist(bones[KFP_WB_PELVIS],bones[KFP_WB_NECK],impact,up,&torso_t);
    float sh=dh-KFP_WOUND_R_HEAD,st=dt-KFP_WOUND_R_TORSO;
    /* Head/torso boundary on the victim's own spine axis, one head radius below the
     * neck bone (the shoulder line): KFP_WOUND_HEAD_T. The character's physics shape
     * tops out at/below the neck bone (fp-5090-3/5: the camera ray found no shape
     * above ~17.2 dm with the neck bone at 16.95 and the Head bone at 18.0; impacts
     * maxed ~16.8), so a boundary at the neck made head wounds impossible. Above
     * the line (pelvis->neck fraction, as the shooter sees it) is head, whatever
     * the skeleton's size. Spine seen end-on (axis < 1 dm in view): nearest
     * silhouette. */
    int head=sh<st;
    {float fp[3],fn[3];kfp_wg_flat(bones[KFP_WB_PELVIS],impact,up,fp);kfp_wg_flat(bones[KFP_WB_NECK],impact,up,fn);
     float ax[3]={fn[0]-fp[0],fn[1]-fp[1],fn[2]-fp[2]},l2=ax[0]*ax[0]+ax[1]*ax[1]+ax[2]*ax[2];
     if (l2>=1.0f) head=-(fp[0]*ax[0]+fp[1]*ax[1]+fp[2]*ax[2])/l2>kfp_wound_head_t(bones);}
    /* head zone silhouette = neck->top (the neck counts as head, as in the zone rule) */
    if (head) {dh=kfp_wg_view_dist(bones[KFP_WB_NECK],top,impact,up,&t);sh=dh-KFP_WOUND_R_HEAD;}
    int core=head?KFP_WG_HEAD:torso_t>=KFP_WOUND_CHEST_T?KFP_WG_CHEST:KFP_WG_STOMACH;
    float core_s=head?sh:st,core_d=head?dh:dt;
    static const int limb[4][4]={
        {KFP_WG_ARM_L,KFP_WB_L_UPPERARM,KFP_WB_L_FOREARM,KFP_WB_L_HAND},
        {KFP_WG_ARM_R,KFP_WB_R_UPPERARM,KFP_WB_R_FOREARM,KFP_WB_R_HAND},
        {KFP_WG_LEG_L,KFP_WB_L_THIGH,KFP_WB_L_CALF,KFP_WB_L_FOOT},
        {KFP_WG_LEG_R,KFP_WB_R_THIGH,KFP_WB_R_CALF,KFP_WB_R_FOOT}};
    int group=core,seg=-1;float best_s=core_s,best_d=core_d;
    out->core=core;out->core_s=core_s;
    if (!(core_s<=KFP_WOUND_CORE_MARGIN)) {
        for(int l=0;l<4;++l) for(int s=1;s<3;++s) {
            float r=l<2?(s==1?KFP_WOUND_R_UPPERARM:KFP_WOUND_R_FOREARM):(s==1?KFP_WOUND_R_THIGH:KFP_WOUND_R_CALF);
            float d=kfp_wg_view_dist(bones[limb[l][s]],bones[limb[l][s+1]],impact,up,&t);
            if (d-r<best_s) {best_s=d-r;best_d=d;group=limb[l][0];seg=limb[l][s];}
        }
    }
    if (!isfinite(best_s) || best_d>KFP_WOUND_MAX_DIST) return 0;
    out->group=group;out->dist=best_d;out->torso_t=torso_t;out->seg=seg;
    return 1;
}
/* Bone heights above the feet (dm): head, headnub, neck, pelvis, calf (mean of
 * both calves = knees). NAN where a bone is missing. */
enum { KFP_WH_HEAD, KFP_WH_HEADNUB, KFP_WH_NECK, KFP_WH_PELVIS, KFP_WH_CALF, KFP_WH_COUNT };
static void kfp_wound_bone_heights(const float bones[KFP_WB_COUNT][3],float feet_y,float h[KFP_WH_COUNT]) {
    h[KFP_WH_HEAD]=bones[KFP_WB_HEAD][1]-feet_y;h[KFP_WH_HEADNUB]=bones[KFP_WB_HEADNUB][1]-feet_y;
    h[KFP_WH_NECK]=bones[KFP_WB_NECK][1]-feet_y;h[KFP_WH_PELVIS]=bones[KFP_WB_PELVIS][1]-feet_y;
    h[KFP_WH_CALF]=(bones[KFP_WB_L_CALF][1]+bones[KFP_WB_R_CALF][1])*0.5f-feet_y;
}
/* Aim heights (dm above the feet) inside each R08 part of an upright victim:
 * head = half a head radius under the neck bone (inside the head zone, which
 * starts one radius under the neck, and under the physics shape's top, which sits
 * near the neck bone), chest = 70% of pelvis->neck (chest starts at
 * KFP_WOUND_CHEST_T), legs = knees. */
static int kfp_wound_aim_heights(const float h[KFP_WH_COUNT],float *head,float *chest,float *legs) {
    *head=h[KFP_WH_NECK]-0.5f*KFP_WOUND_R_HEAD;
    *chest=h[KFP_WH_PELVIS]+0.7f*(h[KFP_WH_NECK]-h[KFP_WH_PELVIS]);
    *legs=h[KFP_WH_CALF];
    return isfinite(h[KFP_WH_HEAD])&&isfinite(*head)&&isfinite(*chest)&&isfinite(*legs)&&*legs<*chest&&*chest<*head;
}
/* "<p>bones=head,headnub,neck,pelvis,calf <p>aim=head,chest,legs" (aim=none: unusable). */
static void kfp_wound_heights_str(const float h[KFP_WH_COUNT],const char *p,char *b,size_t n) {
    float a,c,l;int ok=kfp_wound_aim_heights(h,&a,&c,&l);
    int k=snprintf(b,n,"%sbones=%.2f,%.2f,%.2f,%.2f,%.2f",p,h[0],h[1],h[2],h[3],h[4]);
    if (k<0||(size_t)k>=n) return;
    if (ok) snprintf(b+k,n-k," %saim=%.2f,%.2f,%.2f",p,a,c,l);
    else snprintf(b+k,n-k," %saim=none",p);
}
/* Fallback when the skeleton is unavailable: height above the feet (dm) of an
 * upright victim; lateral = offset toward the victim's right (dm), NAN unknown. */
static int kfp_wound_from_height(float rel_h,float lateral,KfpWoundPick *out) {
    out->group=KFP_WG_NONE;out->dist=NAN;out->torso_t=NAN;out->core=KFP_WG_NONE;out->core_s=NAN;out->seg=-1;
    if (!isfinite(rel_h)||rel_h<KFP_WOUND_H_MIN||rel_h>KFP_WOUND_H_MAX) return 0;
    if (rel_h>=KFP_WOUND_H_HEAD) out->group=KFP_WG_HEAD;
    else if (rel_h>=KFP_WOUND_H_CHEST) out->group=KFP_WG_CHEST;
    else if (rel_h>=KFP_WOUND_H_STOMACH) out->group=KFP_WG_STOMACH;
    else if (isfinite(lateral)&&fabsf(lateral)>=KFP_WOUND_SIDE_MIN) out->group=lateral<0?KFP_WG_LEG_L:KFP_WG_LEG_R;
    else out->group=KFP_WG_LEGS;
    return 1;
}
/* Lateral offset of impact from the victim centre toward its right side.
 * Ogre is right-handed, Y up: facing (fx,fz) has its right side at (-fz,fx). */
static float kfp_wound_lateral(const float impact[3],const float centre[3],float fx,float fz) {
    float n=sqrtf(fx*fx+fz*fz);
    if (!isfinite(n)||n<1e-4f||!kfp_wg_finite3(impact)||!kfp_wg_finite3(centre)) return NAN;
    return ((impact[0]-centre[0])*-fz+(impact[2]-centre[2])*fx)/n;
}
/* Group -> anatomy indices (harness `hp` part index). Head = HEAD part,
 * chest/stomach = first/second TORSO part in anatomy order, limbs by type+side.
 * Returns the number of indices written to idx (0 = anatomy doesn't fit). */
static int kfp_wound_part_index(int group,const int *types,const int *sides,int count,int idx[2]) {
    int n=0,torso=0;
    if (!types||!sides||count<=0) return 0;
    for(int i=0;i<count&&n<2;++i) {
        int ty=types[i],sd=sides[i];
        switch(group) {
        case KFP_WG_HEAD: if(ty==KFP_PART_HEAD) return idx[0]=i,1; break;
        case KFP_WG_CHEST: if(ty==KFP_PART_TORSO) return idx[0]=i,1; break;
        case KFP_WG_STOMACH: if(ty==KFP_PART_TORSO && torso++) return idx[0]=i,1; break;
        case KFP_WG_ARM_L: if(ty==KFP_PART_ARM&&sd==KFP_SIDE_LEFT) return idx[0]=i,1; break;
        case KFP_WG_ARM_R: if(ty==KFP_PART_ARM&&sd==KFP_SIDE_RIGHT) return idx[0]=i,1; break;
        case KFP_WG_LEG_L: if(ty==KFP_PART_LEG&&sd==KFP_SIDE_LEFT) return idx[0]=i,1; break;
        case KFP_WG_LEG_R: if(ty==KFP_PART_LEG&&sd==KFP_SIDE_RIGHT) return idx[0]=i,1; break;
        case KFP_WG_LEGS: if(ty==KFP_PART_LEG) idx[n++]=i; break;
        default: return 0;
        }
    }
    return group==KFP_WG_LEGS&&n==2?2:0;   /* stomach needs a second torso part */
}
/* Human anatomy only (head, 2 torso, left/right arm, left/right leg): the
 * Biped bone names and height bands don't describe animals or odd races. */
static int kfp_wound_humanoid(const int *types,const int *sides,int count) {
    int head=0,torso=0,arm[3]={0},leg[3]={0};
    if (!types||!sides||count!=7) return 0;
    for(int i=0;i<count;++i) {
        int sd=sides[i];if(sd<0||sd>2)return 0;
        switch(types[i]) {
        case KFP_PART_HEAD: ++head; break;
        case KFP_PART_TORSO: ++torso; break;
        case KFP_PART_ARM: ++arm[sd]; break;
        case KFP_PART_LEG: ++leg[sd]; break;
        default: return 0;
        }
    }
    return head==1&&torso==2&&arm[1]==1&&arm[2]==1&&leg[1]==1&&leg[2]==1;
}
static const char *kfp_wound_group_name(int group) {
    static const char *names[]={"head","chest","stomach","arm_l","arm_r","leg_l","leg_r","legs"};
    return group>=0&&group<=KFP_WG_LEGS?names[group]:"none";
}
/* Short bone names for logs (KFP_WB_*); "none" for -1/unknown. */
static const char *kfp_wound_bone_name(int b) {
    static const char *names[KFP_WB_COUNT]={"head","headnub","neck","pelvis","luarm","lfarm","lhand",
        "ruarm","rfarm","rhand","lthigh","lcalf","lfoot","rthigh","rcalf","rfoot"};
    return b>=0&&b<KFP_WB_COUNT?names[b]:"none";
}
/* " core=<g> core_s=<s> seg=<bone>" + world points of the upper-body bones that
 * decide head vs arm (prefix p on every key). */
static void kfp_wound_pick_str(const KfpWoundPick *k,const float bones[KFP_WB_COUNT][3],const char *p,char *b,size_t n) {
    static const int pts[]={KFP_WB_HEAD,KFP_WB_HEADNUB,KFP_WB_NECK,KFP_WB_PELVIS,KFP_WB_L_UPPERARM,KFP_WB_L_FOREARM,
        KFP_WB_L_HAND,KFP_WB_R_UPPERARM,KFP_WB_R_FOREARM,KFP_WB_R_HAND};
    int l=snprintf(b,n," %score=%s %score_s=%.2f %sseg=%s",p,kfp_wound_group_name(k->core),p,k->core_s,p,kfp_wound_bone_name(k->seg));
    for(size_t i=0;bones&&i<sizeof(pts)/sizeof(pts[0]);++i) {
        if (l<0||(size_t)l>=n) return;
        const float *q=bones[pts[i]];
        l+=snprintf(b+l,n-l," %sbw_%s=%.2f,%.2f,%.2f",p,kfp_wound_bone_name(pts[i]),q[0],q[1],q[2]);
    }
}
/* Inverse of kfp_wound_group_name; KFP_WG_NONE for "none"/unknown (test hook `fp_combat wound force`). */
static int kfp_wound_group_parse(const char *name) {
    if (!name) return KFP_WG_NONE;
    for(int g=0;g<=KFP_WG_LEGS;++g) if(!strcmp(kfp_wound_group_name(g),name)) return g;
    return KFP_WG_NONE;
}
#endif
