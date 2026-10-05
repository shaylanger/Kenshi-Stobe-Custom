#ifndef KFP_AIM_GEOMETRY_H
#define KFP_AIM_GEOMETRY_H
#include <math.h>
/* Scene-to-world eye conversion and camera-forward aim are shared by FP/TPS.
 * Geometry only: no damage, RNG, hit grants or weapon readiness decisions. */
static int kfp_aim_geometry(const float scene[3],float tx,float tz,
                            float yaw,float pitch,float range,
                            float origin[3],float direction[3],float end[3]) {
    if (!isfinite(tx)||!isfinite(tz)||!isfinite(yaw)||!isfinite(pitch)||
        !isfinite(range)||range<=0) return 0;
    for(int i=0;i<3;++i) if(!isfinite(scene[i]))return 0;
    float cp=cosf(pitch);
    float d[3]={sinf(yaw)*cp,-sinf(pitch),cosf(yaw)*cp};
    float o[3]={scene[0]-tx,scene[1],scene[2]-tz};
    for(int i=0;i<3;++i) {
        float e=o[i]+d[i]*range;
        if(!isfinite(o[i])||!isfinite(d[i])||!isfinite(e))return 0;
    }
    for(int i=0;i<3;++i) {origin[i]=o[i];direction[i]=d[i];end[i]=o[i]+d[i]*range;}
    return 1;
}
#endif
