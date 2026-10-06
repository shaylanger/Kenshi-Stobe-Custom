#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "../client/kfp_wound_geometry.h"
/* Upright human at the origin facing +Z, feet y=0, decimetres. Its left side is +X. */
static float bones[KFP_WB_COUNT][3];
static void set(int b,float x,float y,float z){bones[b][0]=x;bones[b][1]=y;bones[b][2]=z;}
static void human(void) {
    set(KFP_WB_HEAD,0,15.8f,0);set(KFP_WB_HEADNUB,0,17.6f,0);set(KFP_WB_NECK,0,14.8f,0);set(KFP_WB_PELVIS,0,9.6f,0);
    set(KFP_WB_L_UPPERARM,1.8f,14.2f,0);set(KFP_WB_L_FOREARM,2.0f,11.4f,0);set(KFP_WB_L_HAND,2.1f,8.6f,0);
    set(KFP_WB_R_UPPERARM,-1.8f,14.2f,0);set(KFP_WB_R_FOREARM,-2.0f,11.4f,0);set(KFP_WB_R_HAND,-2.1f,8.6f,0);
    set(KFP_WB_L_THIGH,0.9f,9.2f,0);set(KFP_WB_L_CALF,0.9f,5.0f,0.2f);set(KFP_WB_L_FOOT,0.9f,0.8f,0);
    set(KFP_WB_R_THIGH,-0.9f,9.2f,0);set(KFP_WB_R_CALF,-0.9f,5.0f,0.2f);set(KFP_WB_R_FOOT,-0.9f,0.8f,0);
}
static const float *g_dir;   /* bolt direction for pick() (NULL: 3D) */
static int pick(float x,float y,float z) {
    float p[3]={x,y,z};KfpWoundPick k;
    int ok=kfp_wound_from_bones(p,bones,g_dir,&k);
    assert(ok==(k.group!=KFP_WG_NONE));
    return k.group;
}
static int band(float h,float lat){KfpWoundPick k;kfp_wound_from_height(h,lat,&k);return k.group;}
int main(void) {
    human();
    /* R08 aim heights (head 16.5, chest 12.5, legs 4 dm) on the front surface. */
    assert(pick(0,16.5f,2)==KFP_WG_HEAD);
    assert(pick(0,12.5f,2)==KFP_WG_CHEST);
    assert(pick(0,10.2f,2)==KFP_WG_STOMACH);
    assert(pick(0.5f,4,2)==KFP_WG_LEG_L);
    assert(pick(-0.5f,4,2)==KFP_WG_LEG_R);
    assert(pick(2.6f,12,0.5f)==KFP_WG_ARM_L);
    assert(pick(-2.6f,10,0.5f)==KFP_WG_ARM_R);
    assert(pick(0,12,9)==KFP_WG_NONE);              /* not on the body */
    /* Pose-aware: the same victim lying on its back along +Z (KO) still maps the head. */
    for(int i=0;i<KFP_WB_COUNT;++i){float y=bones[i][1];bones[i][1]=1.5f;bones[i][2]=y;}
    assert(pick(0,3,16.5f)==KFP_WG_HEAD);
    assert(pick(0.6f,3,4)==KFP_WG_LEG_L);
    human();
    /* Missing head nub: extrapolated from neck->head. */
    bones[KFP_WB_HEADNUB][0]=NAN;
    assert(pick(0,16.8f,2)==KFP_WG_HEAD);
    /* Any other missing bone: no pick (caller falls back to native). */
    human();bones[KFP_WB_R_CALF][1]=NAN;
    assert(pick(0,12.5f,2)==KFP_WG_NONE);
    human();{float p[3]={NAN,1,1};KfpWoundPick k;assert(!kfp_wound_from_bones(p,bones,NULL,&k));}
    /* R08 batch 6: guard stance (forearms raised in front of face and chest), shooter
     * in front (+Z), bolt flying -Z. The impact is the physics-shape contact ~3 dm in
     * front of the bones. The old nearest-bone pick chose the forearms here. */
    {static const float in[3]={0,-0.05f,-1};g_dir=in;
     human();
     set(KFP_WB_L_UPPERARM,1.7f,14.1f,0.3f);set(KFP_WB_L_FOREARM,1.6f,12.0f,1.8f);set(KFP_WB_L_HAND,0.3f,13.6f,2.5f);
     set(KFP_WB_R_UPPERARM,-1.7f,14.1f,0.3f);set(KFP_WB_R_FOREARM,-1.4f,13.4f,2.0f);set(KFP_WB_R_HAND,-0.2f,16.0f,2.6f);
     assert(pick(-0.5f,16.6f,3.0f)==KFP_WG_HEAD);       /* head aims: rel_h 16.5-16.8, lat ~-0.5 */
     assert(pick(0.4f,16.8f,3.0f)==KFP_WG_HEAD);
     assert(pick(0.1f,13.0f,3.1f)==KFP_WG_CHEST);       /* chest aims: rel_h ~13 */
     assert(pick(-1.2f,13.1f,3.0f)==KFP_WG_CHEST);
     assert(pick(0.5f,5.5f,2.8f)==KFP_WG_LEG_L);        /* legs aims stay legs */
     assert(pick(-1.1f,5.4f,2.9f)==KFP_WG_LEG_R);
     assert(pick(3.0f,12.0f,1.0f)==KFP_WG_ARM_L);       /* clearly beside the core: arm */
     assert(pick(-2.9f,13.5f,1.5f)==KFP_WG_ARM_R);
     /* Same shots without a bolt direction still avoid the forearms when centred. */
     g_dir=NULL;
     assert(pick(-0.5f,16.6f,1.2f)==KFP_WG_HEAD);
     /* An unusable direction falls back to 3D distances. */
     static const float zero[3]={0,0,0};g_dir=zero;
     assert(pick(3.0f,12.0f,1.0f)==KFP_WG_ARM_L);
     g_dir=NULL;human();}
    /* Side shot (bolt -X) through a relaxed arm: still the core silhouette. */
    {static const float side[3]={-1,0,0};g_dir=side;human();
     assert(pick(3.0f,12.5f,0.2f)==KFP_WG_CHEST);
     assert(pick(3.0f,16.4f,0.3f)==KFP_WG_HEAD);
     g_dir=NULL;}
    /* Batch 7: a taller skeleton (neck 16, Head bone 17, pelvis 10.5). Head aims at
     * rel_h 16.6 (above the neck, below the Head bone) sit ~1 dm from the neck end of
     * the torso segment; the torso's 1.4 dm radius took them (chest). The spine-axis
     * boundary keeps everything past the neck on the head. */
    {static const float in[3]={0.999f,0.023f,-0.036f};g_dir=in;human();
     set(KFP_WB_HEAD,0,17.0f,0);set(KFP_WB_HEADNUB,0,18.9f,0);set(KFP_WB_NECK,0,16.0f,0);set(KFP_WB_PELVIS,0,10.5f,0);
     /* bolt along +X: shooter at -X, impact on the -X surface */
     assert(pick(-1.1f,16.62f,-0.47f)==KFP_WG_HEAD);
     assert(pick(-1.5f,16.74f,-0.18f)==KFP_WG_HEAD);
     g_dir=NULL;}
    /* Bone heights + bone-derived aim heights, and the pick at those heights, for a
     * 1.25x scaled victim standing 3 dm above y=0 (any skeleton size, any ground). */
    {static const float in[3]={0,-0.03f,-1};g_dir=in;human();
     for(int i=0;i<KFP_WB_COUNT;++i){for(int k=0;k<3;++k)bones[i][k]*=1.25f;bones[i][1]+=3.0f;}
     float h[KFP_WH_COUNT],ah,ac,al;kfp_wound_bone_heights((const float (*)[3])bones,3.0f,h);
     assert(fabsf(h[KFP_WH_HEAD]-19.75f)<1e-3f&&fabsf(h[KFP_WH_NECK]-18.5f)<1e-3f&&fabsf(h[KFP_WH_PELVIS]-12.0f)<1e-3f);
     assert(fabsf(h[KFP_WH_CALF]-6.25f)<1e-3f);
     assert(kfp_wound_aim_heights(h,&ah,&ac,&al));
     assert(fabsf(ah-18.0f)<1e-3f&&fabsf(ac-16.55f)<1e-3f&&fabsf(al-6.25f)<1e-3f);
     /* front surface (+Z, ~2.5 dm in front of the bones), small lateral jitter */
     for(int j=-1;j<=1;++j){float x=0.3f*j;
       assert(pick(x,3.0f+ah,2.5f)==KFP_WG_HEAD);
       assert(pick(x,3.0f+ac,3.0f)==KFP_WG_CHEST);
       int lg=pick(x+0.6f,3.0f+al,2.0f);assert(lg==KFP_WG_LEG_L||lg==KFP_WG_LEG_R);}
     /* the fixed 17 dm-human heights miss this victim's parts: 16.5 is chest, 12.5 stomach */
     assert(pick(0,3.0f+16.5f,3.0f)==KFP_WG_CHEST);
     assert(pick(0,3.0f+12.5f,3.0f)==KFP_WG_STOMACH);
     /* missing head nub: aims unaffected */
     h[KFP_WH_HEADNUB]=NAN;assert(kfp_wound_aim_heights(h,&ah,&ac,&al)&&fabsf(ah-18.0f)<1e-3f);
     char b[160];kfp_wound_heights_str(h,"last_",b,sizeof(b));
     assert(!strcmp(b,"last_bones=19.75,nan,18.50,12.00,6.25 last_aim=18.00,16.55,6.25"));
     h[KFP_WH_PELVIS]=NAN;assert(!kfp_wound_aim_heights(h,&ah,&ac,&al));
     kfp_wound_heights_str(h,"",b,sizeof(b));assert(strstr(b," aim=none"));
     g_dir=NULL;human();}
    /* fp-5090-5 victim (Skaera): bones head 18.01 headnub 19.72 neck 16.95 pelvis 10.33
     * calves 5.90; the physics shape tops out below ~17.2 (no ray hit 17.25-17.99) and
     * batch 6/7 impacts maxed ~16.8. Bolt ~+X, impact on the shape front (-X).
     * Head zone starts at the shoulder line 16.95-1.0 = 15.95. */
    {static const float in[3]={0.993f,-0.05f,-0.05f};g_dir=in;human();
     set(KFP_WB_HEAD,0,18.01f,0);set(KFP_WB_HEADNUB,0,19.72f,0);set(KFP_WB_NECK,0,16.95f,0);set(KFP_WB_PELVIS,0,10.33f,0);
     set(KFP_WB_L_UPPERARM,0,16.2f,1.9f);set(KFP_WB_L_FOREARM,0.3f,13.2f,2.1f);set(KFP_WB_L_HAND,0.4f,10.6f,2.2f);
     set(KFP_WB_R_UPPERARM,0,16.2f,-1.9f);set(KFP_WB_R_FOREARM,0.3f,13.2f,-2.1f);set(KFP_WB_R_HAND,0.4f,10.6f,-2.2f);
     set(KFP_WB_L_THIGH,0,9.9f,0.9f);set(KFP_WB_L_CALF,0.1f,5.9f,0.9f);set(KFP_WB_L_FOOT,0,0.8f,0.9f);
     set(KFP_WB_R_THIGH,0,9.9f,-0.9f);set(KFP_WB_R_CALF,0.1f,5.9f,-0.9f);set(KFP_WB_R_FOOT,0,0.8f,-0.9f);
     assert(pick(-1.2f,16.8f,-0.2f)==KFP_WG_HEAD);     /* top of the shape */
     assert(pick(-1.2f,16.62f,-0.47f)==KFP_WG_HEAD);   /* batch 7 head-aim impacts */
     assert(pick(-1.3f,16.74f,-0.18f)==KFP_WG_HEAD);
     assert(pick(-1.3f,16.1f,0.3f)==KFP_WG_HEAD);
     assert(pick(-1.4f,15.7f,0)==KFP_WG_CHEST);        /* below the shoulder line */
     assert(pick(-1.4f,14.97f,0.4f)==KFP_WG_CHEST);    /* fp-5090-5 chest aim never head */
     assert(pick(-1.4f,14.97f,-0.4f)==KFP_WG_CHEST);
     assert(pick(-1.4f,15.3f,0)==KFP_WG_CHEST);
     float h[KFP_WH_COUNT],ah,ac,al;kfp_wound_bone_heights((const float (*)[3])bones,0,h);
     assert(kfp_wound_aim_heights(h,&ah,&ac,&al)&&fabsf(ah-16.45f)<1e-3f&&ah<17.2f&&ah>15.95f);
     assert(pick(-1.3f,ah,0)==KFP_WG_HEAD&&pick(-1.4f,ac,0)==KFP_WG_CHEST);
     g_dir=NULL;human();}
    /* Same aim rule on the reference human: still inside each part. */
    {static const float in[3]={0,-0.03f,-1};g_dir=in;human();
     float h[KFP_WH_COUNT],ah,ac,al;kfp_wound_bone_heights((const float (*)[3])bones,0,h);
     assert(kfp_wound_aim_heights(h,&ah,&ac,&al));
     assert(pick(0,ah,2.0f)==KFP_WG_HEAD&&pick(0,ac,2.5f)==KFP_WG_CHEST);
     g_dir=NULL;}
    /* Height bands. */
    assert(band(16.5f,NAN)==KFP_WG_HEAD);
    assert(band(12.5f,NAN)==KFP_WG_CHEST);
    assert(band(9.0f,NAN)==KFP_WG_STOMACH);
    assert(band(4,1)==KFP_WG_LEG_R);
    assert(band(4,-1)==KFP_WG_LEG_L);
    assert(band(4,0.1f)==KFP_WG_LEGS);
    assert(band(4,NAN)==KFP_WG_LEGS);
    assert(band(25,NAN)==KFP_WG_NONE);
    assert(band(-3,NAN)==KFP_WG_NONE);
    assert(band(NAN,0)==KFP_WG_NONE);
    /* Lateral: facing +Z, the right side is -X. */
    {float c[3]={0,0,0},p[3]={-1,5,2};
     assert(fabsf(kfp_wound_lateral(p,c,0,1)-1)<1e-5f);
     assert(fabsf(kfp_wound_lateral(p,c,0,-3)+1)<1e-5f);   /* facing -Z, unnormalised */
     assert(isnan(kfp_wound_lateral(p,c,0,0)));}
    /* Anatomy mapping = harness `hp` index. */
    int types[7]={KFP_PART_HEAD,KFP_PART_TORSO,KFP_PART_TORSO,KFP_PART_ARM,KFP_PART_ARM,KFP_PART_LEG,KFP_PART_LEG};
    int sides[7]={0,0,0,KFP_SIDE_LEFT,KFP_SIDE_RIGHT,KFP_SIDE_LEFT,KFP_SIDE_RIGHT};
    int idx[2];
    assert(kfp_wound_humanoid(types,sides,7));
    assert(kfp_wound_part_index(KFP_WG_HEAD,types,sides,7,idx)==1&&idx[0]==0);
    assert(kfp_wound_part_index(KFP_WG_CHEST,types,sides,7,idx)==1&&idx[0]==1);
    assert(kfp_wound_part_index(KFP_WG_STOMACH,types,sides,7,idx)==1&&idx[0]==2);
    assert(kfp_wound_part_index(KFP_WG_ARM_L,types,sides,7,idx)==1&&idx[0]==3);
    assert(kfp_wound_part_index(KFP_WG_ARM_R,types,sides,7,idx)==1&&idx[0]==4);
    assert(kfp_wound_part_index(KFP_WG_LEG_L,types,sides,7,idx)==1&&idx[0]==5);
    assert(kfp_wound_part_index(KFP_WG_LEG_R,types,sides,7,idx)==1&&idx[0]==6);
    assert(kfp_wound_part_index(KFP_WG_LEGS,types,sides,7,idx)==2&&idx[0]==5&&idx[1]==6);
    assert(kfp_wound_part_index(KFP_WG_NONE,types,sides,7,idx)==0);
    /* Sides come from the part, not the slot order. */
    int swapped[7]={0,0,0,KFP_SIDE_RIGHT,KFP_SIDE_LEFT,KFP_SIDE_RIGHT,KFP_SIDE_LEFT};
    assert(kfp_wound_part_index(KFP_WG_ARM_L,types,swapped,7,idx)==1&&idx[0]==4);
    assert(kfp_wound_part_index(KFP_WG_LEG_R,types,swapped,7,idx)==1&&idx[0]==5);
    /* Non-human anatomy is rejected. */
    int animal[5]={KFP_PART_HEAD,KFP_PART_TORSO,KFP_PART_LEG,KFP_PART_LEG,KFP_PART_LEG};
    int aside[5]={0,0,1,2,1};
    assert(!kfp_wound_humanoid(animal,aside,5));
    int onetorso[7]={KFP_PART_HEAD,KFP_PART_TORSO,KFP_PART_HEAD,KFP_PART_ARM,KFP_PART_ARM,KFP_PART_LEG,KFP_PART_LEG};
    assert(!kfp_wound_humanoid(onetorso,sides,7));
    assert(kfp_wound_part_index(KFP_WG_STOMACH,onetorso,sides,7,idx)==0);
    assert(!strcmp(kfp_wound_group_name(KFP_WG_CHEST),"chest"));
    assert(!strcmp(kfp_wound_group_name(KFP_WG_NONE),"none"));
    assert(kfp_wound_group_parse("leg_l")==KFP_WG_LEG_L);
    assert(kfp_wound_group_parse("head")==KFP_WG_HEAD);
    assert(kfp_wound_group_parse("legs")==KFP_WG_LEGS);
    assert(kfp_wound_group_parse("none")==KFP_WG_NONE);
    assert(kfp_wound_group_parse("leg")==KFP_WG_NONE);
    assert(kfp_wound_group_parse(NULL)==KFP_WG_NONE);
    for(int g=0;g<=KFP_WG_LEGS;++g) assert(kfp_wound_group_parse(kfp_wound_group_name(g))==g);
    puts("wound geometry ok");
    return 0;
}
