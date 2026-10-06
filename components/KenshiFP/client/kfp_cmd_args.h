/* Harness command argument classes (KAH convention: argv[0] is the command name). Pure, offline-tested
 * (tests/test_cmd_args.c): `fp_state` with no arguments returned the usage error when argv[0] was taken for the
 * first argument (4080 S03 SETUP FAIL, empty ui reasons). */
#ifndef KFP_CMD_ARGS_H
#define KFP_CMD_ARGS_H
#include <string.h>
enum { KFP_FPSTATE_USAGE=-1, KFP_FPSTATE_READ=0, KFP_FPSTATE_FREE_OFF=1 };
static int kfp_fp_state_args(int argc,const char *const *argv) {
    if (argc>=3 && !strcmp(argv[1],"free") && !strcmp(argv[2],"off")) return KFP_FPSTATE_FREE_OFF;
    return argc>=2 ? KFP_FPSTATE_USAGE : KFP_FPSTATE_READ;
}
#endif
