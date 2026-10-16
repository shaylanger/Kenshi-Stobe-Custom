// Offline tests for Stobe::ActivityApproach::Sample (NC9 mine approach ring).
#include "../src/ActivityApproachRing.h"
#include <cstdio>
#include <cmath>
using namespace Stobe::ActivityApproach;
static int fails=0, total=0;
static void Check(const char* n,bool ok){++total; if(!ok){printf("FAIL %s\n",n);++fails;} else printf("ok   %s\n",n);}
int main(){
 Check("count is 24",kCount==24);
 const float radii[3]={14,24,36};
 bool dist=true, distinct=true;
 float xs[kCount],zs[kCount];
 for(unsigned i=0;i<kCount;++i){
  Sample(100.0f,-50.0f,0.7f,i,xs[i],zs[i]);
  float d=std::sqrt((xs[i]-100)*(xs[i]-100)+(zs[i]+50)*(zs[i]+50));
  if(std::fabs(d-radii[i/kAngles])>0.01f) dist=false;
  for(unsigned j=0;j<i;++j) if(std::fabs(xs[i]-xs[j])<0.01f && std::fabs(zs[i]-zs[j])<0.01f) distinct=false;
 }
 Check("every sample on its ring radius",dist);
 Check("all 24 samples distinct",distinct);
 float x,z; Sample(0,0,0,0,x,z);
 Check("first sample lies in baseAngle direction (+x for angle 0), 14 u",std::fabs(x-14)<0.01f && std::fabs(z)<0.01f);
 Sample(0,0,3.14159265f,0,x,z);
 Check("base angle pi puts first sample at -x",std::fabs(x+14)<0.01f);
 Sample(0,0,0,24,x,z); // wraps ring index
 Check("index past count wraps without UB",std::fabs(std::sqrt(x*x+z*z)-14)<0.01f);
 printf("RESULT NC9-RING-TESTS %s %d/%d\n",fails?"FAIL":"PASS",total-fails,total);
 return fails?1:0;
}
