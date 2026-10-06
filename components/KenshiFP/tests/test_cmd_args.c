/* Offline: harness command argument parsing (argv[0] = command name). */
#include <assert.h>
#include <stdio.h>
#include "../client/kfp_cmd_args.h"
int main(void){
    const char *a0[]={"fp_state"},*a1[]={"fp_state","free","off"},*a2[]={"fp_state","free"},*a3[]={"fp_state","bogus"},
               *a4[]={"fp_state","off","free"};
    assert(kfp_fp_state_args(1,a0)==KFP_FPSTATE_READ);       /* bare fp_state = the state read (was usage) */
    assert(kfp_fp_state_args(3,a1)==KFP_FPSTATE_FREE_OFF);
    assert(kfp_fp_state_args(2,a2)==KFP_FPSTATE_USAGE);
    assert(kfp_fp_state_args(2,a3)==KFP_FPSTATE_USAGE);
    assert(kfp_fp_state_args(3,a4)==KFP_FPSTATE_USAGE);
    puts("RESULT B18 PASS fp_state args: bare read, free off, usage on anything else (argv[0] = command name)");
    return 0;
}
