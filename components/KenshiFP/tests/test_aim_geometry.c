#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../client/kfp_aim_geometry.h"
static void near(float a,float b){assert(fabsf(a-b)<.0002f);}
int main(void) {
    float scene[3]={1005,8,-1990},o[3],d[3],e[3];
    assert(kfp_aim_geometry(scene,1000,-2000,0,0,80,o,d,e));
    near(o[0],5);near(o[1],8);near(o[2],10);
    near(d[0],0);near(d[1],0);near(d[2],1);near(e[2],90);
    /* Same world eye after floating origin shifts gives the same ray. */
    float shifted[3]={2005,8,3010},o2[3],d2[3],e2[3];
    assert(kfp_aim_geometry(shifted,2000,3000,0,0,80,o2,d2,e2));
    for(int i=0;i<3;++i){near(o[i],o2[i]);near(d[i],d2[i]);near(e[i],e2[i]);}
    /* Third-person camera keeps forward direction but begins behind eyes. */
    scene[2]-=5;
    assert(kfp_aim_geometry(scene,1000,-2000,0,0,80,o,d,e));
    near(o[2],5);near(e[2],85);
    assert(kfp_aim_geometry(scene,1000,-2000,1.57079632679f,0,80,o,d,e));
    near(d[0],1);near(d[2],0);near(e[0],85);
    assert(kfp_aim_geometry(scene,1000,-2000,.73f,.4f,80,o,d,e));
    near(d[0]*d[0]+d[1]*d[1]+d[2]*d[2],1);
    assert(d[1]<0);
    for(int i=0;i<3;++i){o[i]=17;d[i]=18;e[i]=19;}
    assert(!kfp_aim_geometry(scene,NAN,-2000,0,0,80,o,d,e));
    assert(!kfp_aim_geometry(scene,1000,-2000,INFINITY,0,80,o,d,e));
    assert(!kfp_aim_geometry(scene,1000,-2000,0,0,0,o,d,e));
    scene[1]=NAN;
    assert(!kfp_aim_geometry(scene,1000,-2000,0,0,80,o,d,e));
    for(int i=0;i<3;++i){near(o[i],17);near(d[i],18);near(e[i],19);}
    puts("RESULT B11 PASS camera ray/floating-origin/third-person geometry and invalid input; native collision unvalidated");
    return 0;
}
