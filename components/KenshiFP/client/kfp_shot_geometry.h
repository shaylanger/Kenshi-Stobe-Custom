#ifndef KFP_SHOT_GEOMETRY_H
#define KFP_SHOT_GEOMETRY_H
#include <math.h>
/* Manual ranged shot geometry (R07/R09/R14), pure math, decimetres (B14).
 *
 * Native contract (static RE of RE_Kenshi/kenshi_x64.exe 1.0.65; root 1.0.68 exe = +0x3A0):
 *  - GunClass::shoot 0x43A390 never edits aimpos. It spawns the bolt at
 *    getBarrelPos() (vt+0x48 = gun position +0xE4 + orientation +0xF0 * barrel
 *    offset +0x90) and flies it along getAimDir(aimpos) (GunClassPersonal vt+0x60:
 *    normalise(aimpos - getBarrelPos())), then Ogre randomDeviant(random01*dev).
 *    target!=NULL only adds: harpoon intended-target hand (+0x8), damage falloff
 *    and target->ai notification.
 *  - The AI's aimpos (RC update 0x43AB40 -> 0x436970) is an absolute world point:
 *    victim bone "Bip01 Spine1"/"Spine2" plus velocity lead. Same convention as
 *    the crosshair point, so no conversion of the point itself is needed.
 *  - Bolt flight (0x437D40): a character the bolt meets that is NOT the intended
 *    target and not isEnemy (Character vt+0x3E8) is passed through with chance
 *    min(1, 0.015 * Precision Shooting) (harpoon +0x48). With target==NULL every
 *    non-hostile victim takes that roll: the cause of the manual 0-hit runs.
 *  - The bolt only collides with physics shapes; a shooter's own shape is skipped
 *    for that frame's trace, so a barrel inside the shooter loses the first
 *    (often only) trace segment at close range. */

/* Keep the physics ray's character as the intended target when the visual mesh
 * hit that replaced the aim point lies on the same body: in front of the physics
 * hit by at most `tolerance` (mesh skin vs physics shape). */
static int kfp_shot_keep_attribution(int physical_is_character,float physical_distance,
                                     float visual_distance,float tolerance) {
    if (!physical_is_character||!isfinite(physical_distance)||!isfinite(visual_distance)||
        !isfinite(tolerance)||tolerance<0||physical_distance<0||visual_distance<0) return 0;
    return visual_distance<=physical_distance && physical_distance-visual_distance<=tolerance;
}
/* GunClassPersonal::getAimDir: normalise(aim - barrel). 0 when degenerate. */
static int kfp_shot_dir(const float aim[3],const float barrel[3],float out[3]) {
    float d[3]={aim[0]-barrel[0],aim[1]-barrel[1],aim[2]-barrel[2]};
    float l=sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);
    if (!isfinite(l)||l<1e-4f) return 0;
    for(int i=0;i<3;++i) out[i]=d[i]/l;
    return 1;
}
/* getBarrelPos = position + R*offset, so moving the barrel to `want` only needs
 * position += want - barrel (orientation and offset untouched). */
static void kfp_shot_muzzle_shift(const float position[3],const float barrel[3],
                                  const float want[3],float out[3]) {
    for(int i=0;i<3;++i) out[i]=position[i]+(want[i]-barrel[i]);
}
/* Muzzle on the camera ray: origin + dir * ahead. */
static void kfp_shot_eye_muzzle(const float origin[3],const float dir[3],float ahead,float out[3]) {
    for(int i=0;i<3;++i) out[i]=origin[i]+dir[i]*ahead;
}
/* Angle (degrees) between the bolt direction and the eye->aim line: 0 = the bolt
 * leaves exactly along the crosshair. */
static float kfp_shot_angle_deg(const float a[3],const float b[3]) {
    float la=sqrtf(a[0]*a[0]+a[1]*a[1]+a[2]*a[2]),lb=sqrtf(b[0]*b[0]+b[1]*b[1]+b[2]*b[2]);
    if (!(la>0)||!(lb>0)) return NAN;
    float c=(a[0]*b[0]+a[1]*b[1]+a[2]*b[2])/(la*lb);
    c=c>1?1:c<-1?-1:c;
    return acosf(c)*57.29577951f;
}
/* getBarrelPos sanity (4080 batch 12, R07-R09 0 hits): after a gun (re)create the
 * GunClass position +0xE4 / orientation +0xF0 can stay zero/identity for a long
 * time (GunClass::update not yet writing the node's world transform), so the
 * native barrel is just the local offset (-1,5.9,0) and the bolt leaves from near
 * the world origin. A real muzzle sits at hand height within reach of the
 * shooter's feet position. Returns KFP_BARREL_OK or why it is unusable. */
#define KFP_BARREL_OK 0
#define KFP_BARREL_NONFINITE 1
#define KFP_BARREL_FAR 2          /* farther than max_dist from the shooter */
#define KFP_BARREL_LOCAL 3        /* no shooter position: barrel within near_origin of (0,0,0) */
#define KFP_SHOT_BARREL_MAX_DIST 30.0f   /* dm: feet -> muzzle (height ~15 + reach) */
#define KFP_SHOT_BARREL_NEAR_ORIGIN 20.0f
static int kfp_shot_barrel_check(const float barrel[3],const float shooter[3],int have_shooter,
                                 float max_dist,float near_origin) {
    if (!isfinite(barrel[0])||!isfinite(barrel[1])||!isfinite(barrel[2])) return KFP_BARREL_NONFINITE;
    if (have_shooter && isfinite(shooter[0]) && isfinite(shooter[1]) && isfinite(shooter[2])) {
        float d[3]={barrel[0]-shooter[0],barrel[1]-shooter[1],barrel[2]-shooter[2]};
        float l=sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);
        return isfinite(l)&&l<=max_dist?KFP_BARREL_OK:KFP_BARREL_FAR;
    }
    float l=sqrtf(barrel[0]*barrel[0]+barrel[1]*barrel[1]+barrel[2]*barrel[2]);
    return l<near_origin?KFP_BARREL_LOCAL:KFP_BARREL_OK;
}
#endif
