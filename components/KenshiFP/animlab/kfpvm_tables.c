/* kfpvm_tables.c -- offline fp_tables (KenshiFP live animation tables, kfp_tables.inc) on the lab build of the client.
 * Same parser, registry and hash as the game, so a variant file is checked (and its hash known) before any take.
 * Usage (build: build.sh --main kfpvm_tables.c --out /root/animlab-build/kfpvm_tables [--src <client>|--patch ..]):
 *   kfpvm_tables check <file> [<dump out>]   load the file like `fp_tables load`: prints the fp_tables state line
 *                                            (hash=, changed=, bad=, first bad line); exit 1 on a bad line
 *   kfpvm_tables defaults <out>              the compiled values (fp_tables dump <out> defaults)
 *   kfpvm_tables cmd <fp_tables args..>      any fp_tables command (state, list, get pose m_ready, ...)
 * Every line starts with the reply of the game command. Needs a client source with kfp_tables.inc. */
#include "prelude.h"
#include "gen_helpers.h"
#include "kfp_viewmodel.inc"

static void reply_print(KAH_Reply *r, const char *t) { (void)r; fputs(t, stdout); }
static int run(int argc, const char *const *argv)
{
#ifdef KFP_TABLES
    KAH_Reply rp = { NULL, reply_print }; int rc = kah_fp_tables("animlab", argc, argv, &rp, NULL); fputc('\n', stdout);
    return rc == KAH_OK ? 0 : 1;
#else
    (void)argc; (void)argv; fprintf(stderr, "kfpvm_tables: this client source has no kfp_tables.inc\n"); return 2;
#endif
}
int main(int argc, char **argv)
{
    g_al_quiet = 1;
    if (argc >= 3 && !strcmp(argv[1], "check")) {
        const char *a[3] = { "fp_tables", "load", argv[2] }; int rc = run(3, a);
#ifdef KFP_TABLES
        if (rc == 0 && g_kt_bad) rc = 1;
#endif
        if (argc >= 4) { const char *d[3] = { "fp_tables", "dump", argv[3] }; if (run(3, d)) rc = 1; }
        return rc;
    }
    if (argc >= 3 && !strcmp(argv[1], "defaults")) { const char *a[4] = { "fp_tables", "dump", argv[2], "defaults" }; return run(4, a); }
    if (argc >= 3 && !strcmp(argv[1], "cmd")) { argv[1] = "fp_tables"; return run(argc - 1, (const char *const *)argv + 1); }
    fprintf(stderr, "usage: kfpvm_tables check <file> [<dump out>] | defaults <out> | cmd <fp_tables args..>\n"); return 2;
}
