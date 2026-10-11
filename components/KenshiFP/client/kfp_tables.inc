/* kfp_tables.inc -- live KenshiFP animation tables (Shay 2026-10-10: tune poses/strokes in the running game, no rebuild).
 * Included at the end of kfp_viewmodel.inc (so the animlab adapter, which compiles kfp_viewmodel.inc, has it too).
 *
 * Every registered table (viewmodel poses, sword stroke keys + times, fist technique keys, grip roll/slide, off-hand
 * points, fade/near-clip/timing scalars) can be replaced from a text file, set one value at a time, dumped and hashed.
 * The compiled values are the defaults: they are copied at DLL load (constructor), so with no file nothing changes.
 *
 * File: <KenshiFP dll folder>\fp_tables.txt (DLL: read when it appears, re-read when its write time changes, ~2 Hz;
 * deleted = back to the compiled values). A (re)load first resets every registered table to the compiled values, then
 * applies the file, so a file describes one whole variant. Lines (# = comment):
 *   <table> = v0 v1 ...            the table's floats from element 0 (row-major; fewer values = only the first n)
 *   <table>.<key> = v0 v1 ...      from element <key> on: <flat index> | <row> | <row>.<col>; row = index or row name
 *                                  (pose: m_ready m_aim m_reload m_block r_ready ..; swk: k1..k5; swk_alt: s1_k1..s3_k5;
 *                                  low: m r; fist tables: L0.. R0..; pole: m_L m_R r_L r_R), col = index or name
 *                                  (poses: px py pz fx fy fz ux uy uz; vectors: x y z)
 *   vm.<key> = v                   any `fp_vm set` key (also ones not registered here, e.g. new patch keys)
 * Scalars are 1-element tables named after their fp_vm set key (tau, zf0, nearclip, ...): writes go through vm_set, so
 * its range checks apply. The same file format is read by the animlab (kfpvm_replay/kfpvm_drive --tables <file>,
 * harness tools/animlab/fptables.py). Harness: fp_tables state|list|reload [file]|load <file>|set <table> <key> <v..>|
 * get <table> [key]|dump <file> [diff|defaults]|reset ; every reply carries hash=<8 hex> (FNV-1a of every registered
 * float + the vm.<key> overrides) so a take logs exactly which variant it filmed. fp_vm rec dump writes
 * `# tables <hash>` + `# set -1 t.<table>.<i> <v>` for every value that differed from the compiled one at `rec on`,
 * so a recording replays its variant in the lab with no extra file. vm_set key `t.<table>.<key>` = one table value
 * (KenshiFP.ini vm_t.<table>.<key>=v, fp_vm set t.<table>.<key> v, lab --set t.<table>.<key>=v).
 * New tables (a patch adding one): add a KT_* line to g_kt[] below. */
#define KFP_TABLES 1
typedef struct { const char *name; float *p; int n, cols; const char *cn; int rk; const char *vmkey; } KfpTab;
enum { KT_RNUM, KT_RPOSE, KT_RK, KT_RSWALT, KT_RMR, KT_RLRN, KT_RLR, KT_RPOLE };
#define KT_CPOSE "px py pz fx fy fz ux uy uz"
#define KT_NF(a) ((int)(sizeof(a) / sizeof(float)))
#define KT_POSES(nm, a, rk) { nm, (float *)(a), KT_NF(a), 9, KT_CPOSE, rk, NULL }
#define KT_VEC(nm, a, rk)   { nm, (float *)(a), KT_NF(a), 3, "x y z", rk, NULL }   /* array of Vec3 */
#define KT_VEC1(nm, v)      { nm, (float *)&(v), KT_NF(v), 3, "x y z", KT_RNUM, NULL }   /* one Vec3 */
#define KT_ROW(nm, a)       { nm, (float *)(a), KT_NF(a), KT_NF(a), NULL, KT_RNUM, NULL }
#define KT_SCAL(key, v)     { key, &(v), 1, 1, NULL, KT_RNUM, key }
static KfpTab g_kt[] = {
    KT_POSES("pose", g_vm_pose, KT_RPOSE), KT_POSES("swk", g_vm_swk, KT_RK), KT_POSES("swk_alt", g_vm_swk_alt, KT_RSWALT),
    KT_ROW("swk_u", g_vm_swk_u), KT_ROW("swk_ul", g_vm_swk_ul), KT_POSES("low", g_vm_low, KT_RMR),
    KT_ROW("groll", g_vm_groll), KT_ROW("plsl", g_vm_plsl),
    KT_VEC1("rest", g_vm_rest), KT_VEC1("sup", g_vm_sup), KT_VEC("pole", g_vm_pole, KT_RPOLE),
    KT_VEC1("kick_p", g_vm_kick_p),
    KT_POSES("fist_guard", g_vm_fist_guard, KT_RLR),
    KT_ROW("fist_badpunch_u", g_vm_fist_u_badpunch), KT_POSES("fist_badpunch", g_vm_fist_badpunch, KT_RLRN),
    KT_ROW("fist_ma_chudan_u", g_vm_fist_u_ma_chudan), KT_POSES("fist_ma_chudan", g_vm_fist_ma_chudan, KT_RLRN),
    KT_ROW("fist_ma_2strike_u", g_vm_fist_u_ma_2strike), KT_POSES("fist_ma_2strike", g_vm_fist_ma_2strike, KT_RLRN),
    KT_ROW("fist_shoteil_u", g_vm_fist_u_shoteil), KT_POSES("fist_shoteil", g_vm_fist_shoteil, KT_RLRN),
    /* scalars: fp_vm set keys (timing, fade, near clip, elbow/wrist solver, E1 lead, reload) */
    KT_SCAL("zf0", g_vm_zf0), KT_SCAL("zf1", g_vm_zf1), KT_SCAL("nearclip", g_vm_nc),
    KT_SCAL("sw_dur", g_vm_sw_dur), KT_SCAL("tau", g_vm_tau), KT_SCAL("taurl", g_vm_tau_rl), KT_SCAL("tauw", g_vm_tau_w),
    KT_SCAL("twist", g_vm_twist), KT_SCAL("fire_hold", g_vm_fire_hold), KT_SCAL("kick_up", g_vm_kick_up),
    KT_SCAL("kickrise", g_vm_kick_rise), KT_SCAL("kickdur", g_vm_kick_dur), KT_SCAL("offnear", g_vm_off_near),
    KT_SCAL("aimdist", g_vm_aim_dist), KT_SCAL("omdraw", g_vm_om_draw), KT_SCAL("lowerdur", g_vm_lower_dur),
    KT_SCAL("xwpy", g_vm_xwp_y), KT_SCAL("xwptol", g_vm_xwp_tol), KT_SCAL("xwpdz", g_vm_xwp_dz), KT_SCAL("xwpm", g_vm_xwpm),
    KT_SCAL("wband", g_vm_wband), KT_SCAL("elbnat", g_vm_elb_nat), KT_SCAL("wroll", g_vm_wroll),
    KT_SCAL("x4end", g_x4_end), KT_SCAL("x4lead", g_x4_lead),
    KT_SCAL("rltr", g_vm_rltr), KT_SCAL("rlfwd", g_vm_rlfwd), KT_SCAL("rlrise", g_vm_rlrise), KT_SCAL("rlstill", g_vm_rlstill),
    KT_SCAL("rlto", g_vm_rlto), KT_SCAL("rlmin", g_vm_rlmin), KT_SCAL("rlcone", g_vm_rlcone), KT_SCAL("rlblend", g_vm_rlblend),
    KT_SCAL("rl_dy", g_vm_rl_dy), KT_SCAL("rlper", g_vm_rl_per), KT_SCAL("rlamp", g_vm_rl_amp),
    KT_SCAL("e1wal", g_vm_e1wal), KT_SCAL("e1inl", g_vm_e1inl), KT_SCAL("e1ia", g_vm_e1ia), KT_SCAL("e1ib", g_vm_e1ib),
    KT_SCAL("e1w0", g_vm_e1w0), KT_SCAL("e1hs", g_vm_e1hs), KT_SCAL("e1hr", g_vm_e1hr), KT_SCAL("e1cap", g_vm_e1cap),
    KT_SCAL("swlse", g_vm_swl_se), KT_SCAL("swlin", g_vm_swl_in), KT_SCAL("swlout", g_vm_swl_out),
    KT_SCAL("edgectol", g_vm_ectol), KT_SCAL("edgepen", g_vm_edge_pen), KT_SCAL("edgesgn", g_vm_edgesgn),
    KT_SCAL("edgetol", g_vm_edge_tol), KT_SCAL("elbslow", g_vm_elb_slow), KT_SCAL("elbsmall", g_vm_elb_small),
    KT_SCAL("elbhyst", g_vm_elb_hyst), KT_SCAL("xwalign", g_vm_xwalign), KT_SCAL("stdb", g_vm_stdb),
    KT_SCAL("stretch", g_vm_stretch), KT_SCAL("hroll", g_vm_hroll), KT_SCAL("swbcap", g_vm_swb_cap),
    KT_SCAL("reseeddur", g_vm_reseed_dur), KT_SCAL("reseedtau", g_vm_reseed_tau), KT_SCAL("swbtrig", g_vm_swb_trig),
    KT_SCAL("swbtau", g_vm_swb_tau), KT_SCAL("elbstrdy", g_vm_elb_strdy), KT_SCAL("elbstmax", g_vm_elb_stmax),
    KT_SCAL("elbm", g_vm_elb_m), KT_SCAL("elbzc", g_vm_elb_zc), KT_SCAL("elbr", g_vm_elb_r), KT_SCAL("elbrate", g_vm_elb_rate),
    KT_SCAL("elbdmax", g_vm_elb_dmax), KT_SCAL("elblama", g_vm_elb_lama), KT_SCAL("elblawm", g_vm_elb_lawm),
    KT_SCAL("wrl", g_vm_wrl), KT_SCAL("wrlmin", g_vm_wrlmin), KT_SCAL("wrllag", g_vm_wrllag), KT_SCAL("wrdmp", g_vm_wrdmp),
    KT_SCAL("hand_sa", g_vm_hs_a), KT_SCAL("hand_sc", g_vm_hs_c), KT_SCAL("elbptau", g_vm_elb_ptau),
    KT_SCAL("rbw", g_vm_rbw), KT_SCAL("rbwr", g_vm_rbwr), KT_SCAL("rbcos", g_vm_rbcos), KT_SCAL("rbpen", g_vm_rbpen),
    KT_SCAL("elbkeep", g_vm_elb_keep), KT_SCAL("elbtau", g_vm_elb_tau),
};
#define KT_N ((int)(sizeof g_kt / sizeof g_kt[0]))
static float *g_kt_def, *g_kt_snap; static int g_kt_nf, g_kt_snap_ok; static unsigned g_kt_snap_hash;   /* compiled values; values (+ hash) at the last `rec on` */
#define KT_NOV 128
static struct { char k[40]; float v; } g_kt_ov[KT_NOV]; static int g_kt_nov;   /* vm.<key> overrides from the file / set */
static char g_kt_file[512] = "-"; static int g_kt_lines, g_kt_bad, g_kt_loaded;
static char g_kt_err[160];

static int kt_off(int ti) { int o = 0; for (int i = 0; i < ti; i++) o += g_kt[i].n; return o; }
static void kt_init(void)
{
    if (g_kt_def) return;
    g_kt_nf = kt_off(KT_N);
    g_kt_def = (float *)malloc(sizeof(float) * (size_t)g_kt_nf); g_kt_snap = (float *)malloc(sizeof(float) * (size_t)g_kt_nf);
    if (!g_kt_def || !g_kt_snap) { free(g_kt_def); free(g_kt_snap); g_kt_def = g_kt_snap = NULL; return; }
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++) memcpy(g_kt_def + o, g_kt[i].p, sizeof(float) * (size_t)g_kt[i].n);
}
__attribute__((constructor)) static void kt_ctor(void) { kt_init(); }   /* before any ini/command can change a value */

static int kt_find(const char *name, size_t n)
{
    for (int i = 0; i < KT_N; i++) if (strlen(g_kt[i].name) == n && !strncmp(g_kt[i].name, name, n)) return i;
    return -1;
}
static void kt_rowname(const KfpTab *t, int r, char *b, size_t bn)
{
    int rows = t->n / t->cols;
    switch (t->rk) {
    case KT_RPOSE:  snprintf(b, bn, "%c_%s", r / VM_NT ? 'r' : 'm', g_vm_tname[r % VM_NT]); break;
    case KT_RK:     snprintf(b, bn, "k%d", r + 1); break;
    case KT_RSWALT: snprintf(b, bn, "s%d_k%d", r / VM_SWK + 1, r % VM_SWK + 1); break;
    case KT_RMR:    snprintf(b, bn, "%c", r ? 'r' : 'm'); break;
    case KT_RLR:    snprintf(b, bn, "%c", r ? 'R' : 'L'); break;
    case KT_RLRN:   snprintf(b, bn, "%c%d", r < rows / 2 ? 'L' : 'R', r % (rows / 2 ? rows / 2 : 1)); break;
    case KT_RPOLE:  snprintf(b, bn, "%c_%c", r / 2 ? 'r' : 'm', r % 2 ? 'R' : 'L'); break;
    default:        snprintf(b, bn, "%d", r); break;
    }
}
static int kt_isnum(const char *s, size_t n) { if (!n) return 0; for (size_t i = 0; i < n; i++) if (s[i] < '0' || s[i] > '9') return 0; return 1; }
static int kt_col(const KfpTab *t, const char *s, size_t n)
{
    if (kt_isnum(s, n)) { int c = atoi(s); return c < t->cols ? c : -1; }
    if (!t->cn) return -1;
    const char *p = t->cn; int c = 0;
    while (*p) { const char *e = strchr(p, ' '); size_t l = e ? (size_t)(e - p) : strlen(p);
        if (l == n && !strncmp(p, s, n)) return c; c++; if (!e) break; p = e + 1; }
    return -1;
}
static int kt_row(const KfpTab *t, const char *s, size_t n)
{
    int rows = t->n / t->cols; char b[24];
    if (kt_isnum(s, n)) { int r = atoi(s); return r < rows ? r : -1; }
    for (int r = 0; r < rows; r++) { kt_rowname(t, r, b, sizeof b); if (strlen(b) == n && !strncmp(b, s, n)) return r; }
    return -1;
}
/* element index of <key> in table t: "" = 0, flat index, row, row.col (single-row tables: col name too); -1 = bad */
static int kt_index(const KfpTab *t, const char *key)
{
    size_t n = strlen(key); if (!n || !strcmp(key, "*")) return 0;
    const char *dot = strchr(key, '.');
    if (!dot) {
        if (kt_isnum(key, n)) { int i = atoi(key); return i < t->n ? i : -1; }
        int r = kt_row(t, key, n); if (r >= 0) return r * t->cols;
        int c = t->n / t->cols == 1 ? kt_col(t, key, n) : -1; return c;
    }
    int r = kt_row(t, key, (size_t)(dot - key)), c = kt_col(t, dot + 1, strlen(dot + 1));
    return r >= 0 && c >= 0 ? r * t->cols + c : -1;
}
static int kt_write(int ti, int idx, float v, int log)
{
    KfpTab *t = &g_kt[ti]; if (idx < 0 || idx >= t->n) return 0;
    float old = t->p[idx];
    if (t->vmkey) { if (!vm_set(t->vmkey, v) || memcmp(&t->p[idx], &v, sizeof v)) return 0; }   /* rejected or clamped by its range check */
    else t->p[idx] = v;
    if (log && g_vm_rec_on && t->p[idx] != old) {   /* mid-recording change: the lab replays it at this frame */
        char k[40]; if (t->vmkey) snprintf(k, sizeof k, "%s", t->vmkey); else snprintf(k, sizeof k, "t.%s.%d", t->name, idx);
        vm_setlog(k, t->p[idx]);
    }
    return 1;
}
static int kt_setkey(const char *k, float x)   /* vm_set "t.<table>.<key>" */
{
    const char *dot = strchr(k, '.'); int ti = kt_find(k, dot ? (size_t)(dot - k) : strlen(k));
    if (ti < 0) return 0;
    int i = kt_index(&g_kt[ti], dot ? dot + 1 : ""); return i >= 0 && kt_write(ti, i, x, 0);
}
static void kt_ov_put(const char *k, float v)
{
    for (int i = 0; i < g_kt_nov; i++) if (!strcmp(g_kt_ov[i].k, k)) { g_kt_ov[i].v = v; return; }
    if (g_kt_nov < KT_NOV) { snprintf(g_kt_ov[g_kt_nov].k, sizeof g_kt_ov[0].k, "%s", k); g_kt_ov[g_kt_nov++].v = v; }
}
static unsigned kt_hash(void)
{
    unsigned h = 2166136261u;
    for (int i = 0; i < KT_N; i++) { const unsigned char *b = (const unsigned char *)g_kt[i].p;
        for (size_t j = 0; j < sizeof(float) * (size_t)g_kt[i].n; j++) { h ^= b[j]; h *= 16777619u; } }
    for (int i = 0; i < g_kt_nov; i++) {
        for (const char *c = g_kt_ov[i].k; *c; c++) { h ^= (unsigned char)*c; h *= 16777619u; }
        const unsigned char *b = (const unsigned char *)&g_kt_ov[i].v;
        for (int j = 0; j < 4; j++) { h ^= b[j]; h *= 16777619u; } }
    return h;
}
static int kt_ndiff(void)
{
    int d = g_kt_nov; if (!g_kt_def) return d;
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++)
        for (int j = 0; j < g_kt[i].n; j++) if (memcmp(&g_kt[i].p[j], &g_kt_def[o + j], sizeof(float))) d++;
    return d;
}
static void kt_reset(int log)
{
    kt_init(); if (!g_kt_def) return;
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++)
        for (int j = 0; j < g_kt[i].n; j++) {
            float v = g_kt_def[o + j];
            if (memcmp(&g_kt[i].p[j], &v, sizeof v)) { if (g_kt[i].vmkey) { float old = g_kt[i].p[j]; g_kt[i].p[j] = v;   /* bypass the range check: compiled value */
                    if (log && g_vm_rec_on && old != v) vm_setlog(g_kt[i].vmkey, v); }
                else kt_write(i, j, v, log); }
        }
    g_kt_nov = 0;   /* vm.<key> overrides: their keys keep the last value (no compiled copy of unregistered keys) */
}
static char *kt_trim(char *s) { while (*s == ' ' || *s == '\t') s++; char *e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n')) *--e = 0; return s; }
/* apply one "<lhs> = values" line; 0 = bad */
static int kt_apply_line(char *line, int log)
{
    char *s = kt_trim(line); if (!*s || *s == '#' || *s == ';') return 1;
    char *eq = strchr(s, '='); if (!eq) return 0;
    *eq = 0; char *lhs = kt_trim(s), *rhs = eq + 1;
    if (!strncmp(lhs, "vm.", 3)) { float v = (float)atof(rhs); if (!vm_set(lhs + 3, v)) return 0;
        kt_ov_put(lhs + 3, v); if (log && g_vm_rec_on) vm_setlog(lhs + 3, v); return 1; }
    char *dot = strchr(lhs, '.'); int ti = kt_find(lhs, dot ? (size_t)(dot - lhs) : strlen(lhs)); if (ti < 0) return 0;
    int i = kt_index(&g_kt[ti], dot ? dot + 1 : ""); if (i < 0) return 0;
    int nv = 0; char *p = rhs, *e;
    for (;;) { float v = strtof(p, &e); if (e == p) break; if (!kt_write(ti, i + nv, v, log)) return 0; nv++; p = e; }
    return nv > 0;
}
static int kt_load(const char *path, int log)
{
    FILE *f = fopen(path, "r"); if (!f) { snprintf(g_kt_err, sizeof g_kt_err, "cannot open %s", path); return -1; }
    kt_reset(log); char line[4096]; int ln = 0; g_kt_lines = g_kt_bad = 0; g_kt_err[0] = 0;
    while (fgets(line, sizeof line, f)) { ln++; char cp[80]; snprintf(cp, sizeof cp, "%s", line);
        if (kt_apply_line(line, log)) { char *t = kt_trim(cp); if (*t && *t != '#' && *t != ';') g_kt_lines++; }
        else { if (!g_kt_bad) snprintf(g_kt_err, sizeof g_kt_err, "line %d: %.60s", ln, kt_trim(cp)); g_kt_bad++; } }
    fclose(f); g_kt_loaded = 1;
    logline("[tables] loaded %s: %d lines, %d bad%s%s, %d values off the compiled ones, hash=%08x", path, g_kt_lines, g_kt_bad,
            g_kt_bad ? " first " : "", g_kt_bad ? g_kt_err : "", kt_ndiff(), kt_hash());
    return g_kt_bad;
}
/* which: 0 = current, 1 = only rows that differ from the compiled values, 2 = the compiled values */
static int kt_dump(const char *path, int which)
{
    kt_init(); if (which && !g_kt_def) return -1;
    FILE *fo = fopen(path, "w"); if (!fo) return -1;
    fprintf(fo, "# KenshiFP fp_tables %s hash=%08x (format: kfp_tables.inc header; <table>[.<row>] = values)\n",
            which == 2 ? "defaults" : which == 1 ? "diff" : "dump", kt_hash());
    int rowsout = 0; char rn[24];
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++) {
        const KfpTab *t = &g_kt[i]; int rows = t->n / t->cols; const float *src = which == 2 ? g_kt_def + o : t->p;
        if (!which || which == 2) fprintf(fo, "# %s rows=%d cols=%d%s%s\n", t->name, rows, t->cols, t->cn ? " cols: " : "", t->cn ? t->cn : "");
        for (int r = 0; r < rows; r++) {
            if (which == 1 && !memcmp(t->p + r * t->cols, g_kt_def + o + r * t->cols, sizeof(float) * (size_t)t->cols)) continue;
            if (rows == 1) fprintf(fo, "%s =", t->name); else { kt_rowname(t, r, rn, sizeof rn); fprintf(fo, "%s.%s =", t->name, rn); }
            for (int c = 0; c < t->cols; c++) fprintf(fo, " %.9g", src[r * t->cols + c]);
            fputc('\n', fo); rowsout++;
        }
    }
    if (which != 2) for (int i = 0; i < g_kt_nov; i++) fprintf(fo, "vm.%s = %.9g\n", g_kt_ov[i].k, g_kt_ov[i].v);
    fclose(fo); return rowsout;
}
/* fp_vm rec: values at `rec on`, written into the dump so the lab replays the variant */
static void kt_rec_mark(void)
{
    kt_init(); if (!g_kt_snap) return;
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++) memcpy(g_kt_snap + o, g_kt[i].p, sizeof(float) * (size_t)g_kt[i].n);
    g_kt_snap_ok = 1; g_kt_snap_hash = kt_hash();
}
static void kt_rec_header(FILE *fo)
{
    kt_init(); if (!g_kt_def) return;
    fprintf(fo, "# tables %08x now=%08x file=%s\n", g_kt_snap_ok ? g_kt_snap_hash : kt_hash(), kt_hash(), g_kt_file);   /* at rec on, at the dump */
    for (int i = 0, o = 0; i < KT_N; o += g_kt[i].n, i++)
        for (int j = 0; j < g_kt[i].n; j++) {
            float v = g_kt_snap_ok ? g_kt_snap[o + j] : g_kt[i].p[j];
            if (!memcmp(&v, &g_kt_def[o + j], sizeof v)) continue;
            if (g_kt[i].vmkey) fprintf(fo, "# set -1 %s %.9g\n", g_kt[i].vmkey, v);
            else fprintf(fo, "# set -1 t.%s.%d %.9g\n", g_kt[i].name, j, v);
        }
    for (int i = 0; i < g_kt_nov; i++) fprintf(fo, "# set -1 %s %.9g\n", g_kt_ov[i].k, g_kt_ov[i].v);
}
static int kah_fp_tables(const char *id, int argc, const char *const *argv, KAH_Reply *r, void *u)
{
    (void)id; (void)u; char b[1400]; int k = 0;
    const char *a = argc > 1 ? argv[1] : "state";
    kt_init(); if (!g_kt_def) { r->append(r, "fp_tables: no memory"); return KAH_ERROR; }
    if (!strcmp(a, "reload") || (!strcmp(a, "load") && argc > 2)) {
        const char *p = argc > 2 ? argv[2] : g_kt_file;
        if (!strcmp(p, "-")) { r->append(r, "fp_tables reload: no file (give a path)"); return KAH_ERROR; }
        int bad = kt_load(p, 1);
        if (bad < 0) { snprintf(b, sizeof b, "fp_tables: %s", g_kt_err); r->append(r, b); return KAH_ERROR; }
        if (!strcmp(a, "load") || argc > 2) snprintf(g_kt_file, sizeof g_kt_file, "%s", p);
        k = snprintf(b, sizeof b, "tables loaded file=%s lines=%d bad=%d%s%s ", p, g_kt_lines, bad, bad ? " first=" : "", bad ? g_kt_err : "");
    } else if (!strcmp(a, "set") && argc > 4) {
        const char *key = argv[3]; int ti = kt_find(argv[2], strlen(argv[2]));
        if (!strcmp(argv[2], "vm")) { float v = (float)atof(argv[4]);
            if (!vm_set_logged(key, v)) { r->append(r, "fp_tables set vm: unknown fp_vm key or value out of range"); return KAH_ERROR; }
            kt_ov_put(key, v); k = snprintf(b, sizeof b, "set vm.%s=%g ", key, v); }
        else {
            int i = ti >= 0 ? kt_index(&g_kt[ti], key) : -1;
            if (i < 0) { snprintf(b, sizeof b, "fp_tables set: unknown %s %s (fp_tables list)", ti < 0 ? "table" : "key", ti < 0 ? argv[2] : key); r->append(r, b); return KAH_ERROR; }
            int nv = 0;
            for (int j = 4; j < argc; j++, nv++) {
                float v = (float)atof(argv[j]);
                if (!kt_write(ti, i + nv, v, 0)) { snprintf(b, sizeof b, "fp_tables set: %s[%d]=%g rejected (out of range/table)", argv[2], i + nv, v); r->append(r, b); return KAH_ERROR; }
                char lk[40]; if (g_kt[ti].vmkey) snprintf(lk, sizeof lk, "%s", g_kt[ti].vmkey); else snprintf(lk, sizeof lk, "t.%s.%d", g_kt[ti].name, i + nv);
                vm_setlog(lk, g_kt[ti].p[i + nv]);
            }
            k = snprintf(b, sizeof b, "set %s[%d..%d] ", argv[2], i, i + nv - 1);
        }
    } else if (!strcmp(a, "get") && argc > 2) {
        int ti = kt_find(argv[2], strlen(argv[2])); if (ti < 0) { r->append(r, "fp_tables get: unknown table (fp_tables list)"); return KAH_ERROR; }
        const KfpTab *t = &g_kt[ti]; int i0 = 0, n = t->n;
        if (argc > 3) { i0 = kt_index(t, argv[3]); if (i0 < 0) { r->append(r, "fp_tables get: unknown key"); return KAH_ERROR; }
            n = (strchr(argv[3], '.') || kt_isnum(argv[3], strlen(argv[3])) || t->n == t->cols) ? 1 : t->cols; }
        k = snprintf(b, sizeof b, "%s[%d]", t->name, i0);
        for (int j = i0; j < i0 + n && j < t->n && k < (int)sizeof b - 200; j++) k += snprintf(b + k, sizeof b - k, " %.6g", t->p[j]);
        k += snprintf(b + k, sizeof b - k, " | ");
    } else if (!strcmp(a, "dump") && argc > 2) {
        int which = argc > 3 ? (!strcmp(argv[3], "diff") ? 1 : !strcmp(argv[3], "defaults") ? 2 : 0) : 0;
        int n = kt_dump(argv[2], which); if (n < 0) { snprintf(b, sizeof b, "fp_tables dump: cannot write %s", argv[2]); r->append(r, b); return KAH_ERROR; }
        k = snprintf(b, sizeof b, "dump %s rows=%d which=%s ", argv[2], n, which == 2 ? "defaults" : which ? "diff" : "all");
    } else if (!strcmp(a, "reset")) { kt_reset(1); k = snprintf(b, sizeof b, "reset to compiled values "); }
    else if (!strcmp(a, "list")) {
        for (int i = 0; i < KT_N && k < (int)sizeof b - 60; i++) k += snprintf(b + k, sizeof b - k, "%s%s %dx%d", i ? ", " : "tables ", g_kt[i].name, g_kt[i].n / g_kt[i].cols, g_kt[i].cols);
        k += snprintf(b + k, sizeof b - k, " | ");
    } else if (strcmp(a, "state")) {
        r->append(r, "usage: fp_tables state|list|reload [file]|load <file>|set <table> <key> <v..>|set vm <fp_vm key> <v>|get <table> [key]|dump <file> [diff|defaults]|reset");
        return KAH_ERROR;
    }
    snprintf(b + k, sizeof b - k, "tables hash=%08x default=%d changed=%d file=%s loaded=%d lines=%d bad=%d", kt_hash(), kt_ndiff() == 0, kt_ndiff(), g_kt_file, g_kt_loaded, g_kt_lines, g_kt_bad);
    r->append(r, b); return KAH_OK;
}
#ifdef KFP_HAVE_SELF_SHA   /* DLL only: watch <dll folder>\fp_tables.txt */
static void kt_tick(void)
{
    static DWORD last; static FILETIME wt; static int have, init; static char path[MAX_PATH];
    DWORD now = GetTickCount(); if (init && now - last < 500) return; last = now;
    if (!init) { init = 1; char d[MAX_PATH]; DWORD n = GetModuleFileNameA(g_hinst, d, MAX_PATH);
        if (n > 0 && n < MAX_PATH) { for (DWORD i = n; i > 0; i--) if (d[i-1] == '\\' || d[i-1] == '/') { d[i-1] = 0; break; }
            snprintf(path, sizeof path, "%s\\fp_tables.txt", d); } else strcpy(path, "fp_tables.txt"); }
    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (!GetFileAttributesExA(path, GetFileExInfoStandard, &fad)) {
        if (have) { have = 0; kt_reset(1); snprintf(g_kt_file, sizeof g_kt_file, "-"); g_kt_loaded = 0;
            logline("[tables] %s removed: compiled values, hash=%08x", path, kt_hash()); }
        return; }
    if (have && !CompareFileTime(&fad.ftLastWriteTime, &wt)) return;
    have = 1; wt = fad.ftLastWriteTime; snprintf(g_kt_file, sizeof g_kt_file, "%s", path);
    kt_load(path, 1);
}
#endif
