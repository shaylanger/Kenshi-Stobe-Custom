#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../client/kfp_shot_geometry.h"
static int near(float a,float b,float e){return fabsf(a-b)<=e;}
int main(void) {
    /* Attribution: mesh skin 1.5 dm in front of the physics shape = same body. */
    assert(kfp_shot_keep_attribution(1,46.0f,44.5f,8.0f));
    assert(kfp_shot_keep_attribution(1,26.0f,26.0f,8.0f));
    assert(!kfp_shot_keep_attribution(1,46.0f,30.0f,8.0f));   /* something well in front */
    assert(!kfp_shot_keep_attribution(0,46.0f,44.5f,8.0f));   /* physics hit is not a character */
    assert(!kfp_shot_keep_attribution(1,46.0f,47.0f,8.0f));   /* visual behind physics */
    assert(!kfp_shot_keep_attribution(1,NAN,44.0f,8.0f));
    assert(!kfp_shot_keep_attribution(1,46.0f,44.0f,-1.0f));
    /* getAimDir: normalise(aim - barrel). */
    float aim[3]={10,13.6f,46},barrel[3]={1.5f,14.0f,2.0f},d[3];
    assert(kfp_shot_dir(aim,barrel,d));
    float l=sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);assert(near(l,1,1e-5f));
    /* the line barrel + t*d passes through aim */
    float t=(aim[2]-barrel[2])/d[2];
    assert(near(barrel[0]+t*d[0],aim[0],1e-3f)&&near(barrel[1]+t*d[1],aim[1],1e-3f));
    assert(!kfp_shot_dir(aim,aim,d));
    /* Muzzle shift: barrel = pos + R*off, so the shifted position yields exactly want. */
    float pos[3]={100,50,-20},off[3]={0.3f,-0.2f,2.5f},bar[3],want[3]={101,51.5f,-19},np[3];
    for(int i=0;i<3;++i) bar[i]=pos[i]+off[i];
    kfp_shot_muzzle_shift(pos,bar,want,np);
    for(int i=0;i<3;++i) assert(near(np[i]+off[i],want[i],1e-4f));
    /* Eye muzzle + direction: bolt leaves along the crosshair (0 deg). */
    float eye[3]={0,16,0},cd[3]={0,-0.0434f,0.99906f},m[3],sd[3],tgt[3];
    kfp_shot_eye_muzzle(eye,cd,1.0f,m);
    for(int i=0;i<3;++i) tgt[i]=eye[i]+cd[i]*46.0f;
    assert(kfp_shot_dir(tgt,m,sd));
    assert(kfp_shot_angle_deg(sd,cd)<0.05f);
    /* A barrel 3 dm right / 2 dm low still aims through the point: angle small but non-zero. */
    float b2[3]={-3,14,0.5f};assert(kfp_shot_dir(tgt,b2,sd));
    float a=kfp_shot_angle_deg(sd,cd);assert(a>1.0f&&a<6.0f);
    assert(isnan(kfp_shot_angle_deg((float[3]){0,0,0},cd)));
    /* Barrel sanity: the 4080 batch 12 local-offset barrel vs a real muzzle. */
    float bogus[3]={-1.0f,5.9f,0.0f},real[3]={-54070.71f,661.42f,6772.67f},feet[3]={-54071.5f,647.8f,6773.4f};
    assert(kfp_shot_barrel_check(real,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_OK);
    assert(kfp_shot_barrel_check(bogus,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_FAR);
    assert(kfp_shot_barrel_check(bogus,feet,0,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_LOCAL);
    assert(kfp_shot_barrel_check(real,feet,0,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_OK);
    float zero[3]={0,0,0};
    assert(kfp_shot_barrel_check(zero,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_FAR);
    float nanb[3]={NAN,1,2};
    assert(kfp_shot_barrel_check(nanb,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_NONFINITE);
    float nanf[3]={NAN,0,0};   /* unusable shooter position = treated as unknown */
    assert(kfp_shot_barrel_check(bogus,nanf,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_LOCAL);
    float edge[3]={feet[0]+29.0f,feet[1],feet[2]},past[3]={feet[0]+31.0f,feet[1],feet[2]};
    assert(kfp_shot_barrel_check(edge,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_OK);
    assert(kfp_shot_barrel_check(past,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_FAR);
    /* The fix: shifting the stale position moves the barrel exactly onto the eye muzzle. */
    {float gp[3]={0,0,0},np2[3],em[3]={-54071.0f,662.0f,6772.0f};
     kfp_shot_muzzle_shift(gp,bogus,em,np2);
     for(int i=0;i<3;++i) assert(near(np2[i]+bogus[i]-gp[i],em[i],1e-2f));
     assert(kfp_shot_barrel_check(em,feet,1,KFP_SHOT_BARREL_MAX_DIST,KFP_SHOT_BARREL_NEAR_ORIGIN)==KFP_BARREL_OK);}
    puts("shot geometry ok");
    return 0;
}
