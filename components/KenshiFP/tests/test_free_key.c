/* Offline: free-cursor key clean-tap detector (B19). */
#include <assert.h>
#include <stdio.h>
#include "../client/kfp_free_key.h"
static int run(const int (*f)[3],int n){KfpFreeKey s={0,0};int t=0;for(int i=0;i<n;i++)t+=kfp_free_key_step(&s,f[i][0],f[i][1],f[i][2]);return t;}
int main(void){
    const int tap[][3]={{0,1,0},{1,1,0},{1,1,0},{0,1,0}};             /* clean tap -> 1 toggle on release */
    const int alttab[][3]={{1,1,0},{1,1,1},{1,0,1},{1,0,0},{0,0,0}};   /* Alt+Tab away -> none */
    const int altkey[][3]={{1,1,0},{1,1,1},{1,1,0},{0,1,0}};           /* Alt+Esc/F4 inside the game -> none */
    const int unfocused[][3]={{1,0,0},{1,1,0},{0,1,0}};                /* pressed while another window had focus -> none */
    const int held[][3]={{1,1,0},{1,1,0},{1,1,0}};                     /* still held -> nothing yet */
    const int two[][3]={{1,1,0},{0,1,0},{1,1,0},{0,1,0}};              /* two taps -> 2 */
    assert(run(tap,4)==1); assert(run(alttab,5)==0); assert(run(altkey,4)==0);
    assert(run(unfocused,3)==0); assert(run(held,3)==0); assert(run(two,4)==2);
    puts("RESULT B19 PASS free-cursor key: toggles on a clean tap release only (Alt+Tab, Alt+key, unfocused press ignored)");
    return 0;
}
