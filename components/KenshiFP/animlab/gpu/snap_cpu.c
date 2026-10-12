/* snap_cpu.c -- gpugen CPU TU: state snapshot writer / reader (gpu-lab 2026-10-11).
 * Snapshot = every mutable global (segment kind 0, gpugen order) + every live tracked heap block (kind 1), plus a
 * relocation for every 8-byte word that holds a pointer into a segment (1), a function (2) or a read-only string of the
 * binary (3). Little-endian binary:
 *   "KSN1" u32 nseg u32 nglobals u32 nfuncs
 *   nseg x { u32 kind u32 id u64 size bytes[size] }
 *   u32 nrel  nrel x { u32 seg u32 kind u64 off u32 tgt u32 pad u64 toff }
 *   u32 nstr  nstr x { u32 len bytes[len] }   (len includes the NUL)
 * A GPU thread's KSt holds the same globals (device layout from kst_layout); gpu/kfpgpu.py moves bytes + relocations.
 * Words below 2^32 are never pointers (float/int pairs); a word is a pointer only if it lands in a known place. */
#define AL_NG ((int)(sizeof al_globals / sizeof al_globals[0]))
#define AL_NF ((int)(sizeof al_funcs / sizeof al_funcs[0]))
typedef struct { void *p; size_t n; } AlBlk;
static AlBlk *al_blk; static int al_nblk, al_cblk;
static void al_blk_add(void *p, size_t n) { if (!p) return; if (al_nblk == al_cblk) { al_cblk = al_cblk ? 2 * al_cblk : 64; al_blk = realloc(al_blk, sizeof(AlBlk) * al_cblk); } al_blk[al_nblk].p = p; al_blk[al_nblk++].n = n; }
static void al_blk_del(void *p) { for (int i = 0; i < al_nblk; i++) if (al_blk[i].p == p) { al_blk[i] = al_blk[--al_nblk]; return; } }
static void *al_malloc(size_t n) { void *p = malloc(n); al_blk_add(p, n); return p; }
static void *al_calloc(size_t a, size_t b) { void *p = calloc(a, b); al_blk_add(p, a * b); return p; }
static void *al_realloc(void *p, size_t n) { void *q = realloc(p, n); if (q) { al_blk_del(p); al_blk_add(q, n); } return q; }
static void al_free(void *p) { al_blk_del(p); free(p); }

extern char etext[], edata[];   /* read-only data (strings) of the binary lies after .text, before the end of .data
 * (pointers into known globals/heap are matched first); no system #include here: cpu.c is already preprocessed */
static int al_is_ro(uintptr_t v) { return v >= (uintptr_t)etext && v < (uintptr_t)edata; }

typedef struct { uintptr_t lo, hi; int seg; } AlSeg;
static int al_segcmp(const void *a, const void *b) { uintptr_t x = ((const AlSeg *)a)->lo, y = ((const AlSeg *)b)->lo; return x < y ? -1 : x > y; }
static void al_w32(FILE *f, unsigned v) { fwrite(&v, 4, 1, f); }
static void al_w64(FILE *f, unsigned long long v) { fwrite(&v, 8, 1, f); }
typedef struct { unsigned seg, kind; unsigned long long off; unsigned tgt; unsigned long long toff; } AlRel;

static int al_func_find(uintptr_t v) { for (int k = 0; k < AL_NF; k++) if ((uintptr_t)al_funcs[k].addr == v) return k; return -1; }

static int al_snap_noheap;   /* 1 = globals only (heap pointers stay raw: hot-spot captures that never touch the heap) */
/* write the whole state; returns 0 */
static int al_snap_write(FILE *f)
{
    int ns = AL_NG + (al_snap_noheap ? 0 : al_nblk); AlSeg *sg = malloc(sizeof(AlSeg) * ns);
    for (int i = 0; i < AL_NG; i++) { sg[i].lo = (uintptr_t)al_globals[i].addr; sg[i].hi = sg[i].lo + al_globals[i].size; sg[i].seg = i; }
    for (int i = 0; i < ns - AL_NG; i++) { sg[AL_NG + i].lo = (uintptr_t)al_blk[i].p; sg[AL_NG + i].hi = sg[AL_NG + i].lo + al_blk[i].n; sg[AL_NG + i].seg = AL_NG + i; }
    AlSeg *ss = malloc(sizeof(AlSeg) * ns); memcpy(ss, sg, sizeof(AlSeg) * ns); qsort(ss, ns, sizeof(AlSeg), al_segcmp);
    fwrite("KSN1", 4, 1, f); al_w32(f, ns); al_w32(f, AL_NG); al_w32(f, AL_NF);
    int nrel = 0, crel = 1024; AlRel *rel = malloc(sizeof(AlRel) * crel);
    int nstr = 0; static const char *strs[4096];
    for (int s = 0; s < ns; s++) {
        al_w32(f, s < AL_NG ? 0 : 1); al_w32(f, s < AL_NG ? s : s - AL_NG); al_w64(f, sg[s].hi - sg[s].lo);
        fwrite((void *)sg[s].lo, 1, sg[s].hi - sg[s].lo, f);
        for (uintptr_t a = (sg[s].lo + 7) & ~(uintptr_t)7; a + 8 <= sg[s].hi; a += 8) {
            uintptr_t v; memcpy(&v, (void *)a, 8);
            if (v < 0x100000000ull) continue;
            AlRel r = { (unsigned)s, 0, a - sg[s].lo, 0, 0 };
            int lo = 0, hi = ns - 1, hit = -1;   /* last segment with lo <= v */
            while (lo <= hi) { int m = (lo + hi) / 2; if (ss[m].lo <= v) { hit = m; lo = m + 1; } else hi = m - 1; }
            if (hit >= 0 && v < ss[hit].hi) { r.kind = 1; r.tgt = ss[hit].seg; r.toff = v - ss[hit].lo; }
            else if (hit >= 0 && v == ss[hit].hi && ss[hit].hi > ss[hit].lo && al_func_find(v) < 0) { r.kind = 1; r.tgt = ss[hit].seg; r.toff = v - ss[hit].lo; }   /* one past the end */
            else { int k = al_func_find(v); if (k >= 0) { r.kind = 2; r.tgt = k; }
                else if (al_is_ro(v)) { for (k = 0; k < nstr; k++) if ((uintptr_t)strs[k] == v) break;
                    if (k == nstr && nstr < 4096) strs[nstr++] = (const char *)v;
                    if (k < 4096) { r.kind = 3; r.tgt = k; } } }
            if (!r.kind) continue;
            if (nrel == crel) { crel *= 2; rel = realloc(rel, sizeof(AlRel) * crel); }
            rel[nrel++] = r;
        }
    }
    al_w32(f, nrel); for (int i = 0; i < nrel; i++) { al_w32(f, rel[i].seg); al_w32(f, rel[i].kind); al_w64(f, rel[i].off); al_w32(f, rel[i].tgt); al_w32(f, 0); al_w64(f, rel[i].toff); }
    al_w32(f, nstr); for (int i = 0; i < nstr; i++) { unsigned n = strlen(strs[i]) + 1; al_w32(f, n); fwrite(strs[i], 1, n, f); }
    free(rel); free(ss); free(sg); return 0;
}

/* read a state written by al_snap_write / kfpgpu.py into this process: globals overwritten, heap segments become new
 * tracked blocks (old tracked blocks are left alone), pointers relocated to this process. Returns 0 or -1. */
static int al_snap_read(FILE *f)
{
    char mg[4]; unsigned ns, ng, nf;
    if (fread(mg, 4, 1, f) != 1 || memcmp(mg, "KSN1", 4) || fread(&ns, 4, 1, f) != 1 || fread(&ng, 4, 1, f) != 1 || fread(&nf, 4, 1, f) != 1) return -1;
    if (ng != (unsigned)AL_NG || nf != (unsigned)AL_NF) { fprintf(stderr, "al_snap_read: table mismatch %u/%d globals %u/%d funcs\n", ng, AL_NG, nf, AL_NF); return -1; }
    void **base = malloc(sizeof(void *) * ns);
    for (unsigned s = 0; s < ns; s++) { unsigned k, id; unsigned long long n;
        if (fread(&k, 4, 1, f) != 1 || fread(&id, 4, 1, f) != 1 || fread(&n, 8, 1, f) != 1) return -1;
        if (k == 0) { if (id >= (unsigned)AL_NG || n != al_globals[id].size) { fprintf(stderr, "al_snap_read: global %u size %llu\n", id, n); return -1; } base[s] = al_globals[id].addr; }
        else base[s] = al_malloc(n ? n : 1);
        if (n && fread(base[s], 1, n, f) != n) return -1; }
    unsigned nrel; if (fread(&nrel, 4, 1, f) != 1) return -1;
    AlRel *rel = malloc(sizeof(AlRel) * (nrel + 1));
    for (unsigned i = 0; i < nrel; i++) { unsigned pad; if (fread(&rel[i].seg, 4, 1, f) != 1 || fread(&rel[i].kind, 4, 1, f) != 1 || fread(&rel[i].off, 8, 1, f) != 1
        || fread(&rel[i].tgt, 4, 1, f) != 1 || fread(&pad, 4, 1, f) != 1 || fread(&rel[i].toff, 8, 1, f) != 1) return -1; }
    unsigned nstr; if (fread(&nstr, 4, 1, f) != 1) return -1;
    char **str = malloc(sizeof(char *) * (nstr + 1));
    for (unsigned i = 0; i < nstr; i++) { unsigned n; if (fread(&n, 4, 1, f) != 1) return -1; str[i] = malloc(n); if (fread(str[i], 1, n, f) != n) return -1; }
    for (unsigned i = 0; i < nrel; i++) { uintptr_t v = 0;
        if (rel[i].kind == 1) v = (uintptr_t)base[rel[i].tgt] + rel[i].toff;
        else if (rel[i].kind == 2) v = (uintptr_t)al_funcs[rel[i].tgt].addr;
        else if (rel[i].kind == 3) v = (uintptr_t)str[rel[i].tgt];
        memcpy((char *)base[rel[i].seg] + rel[i].off, &v, 8); }
    free(rel); free(base); return 0;
}
