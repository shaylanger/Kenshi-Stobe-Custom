/* kfp_meshray.h -- TRUE-GEOMETRY ray queries against the VISUAL .mesh triangles
 * (task #22). The physics/ray world only has the authored collision hulls
 * (coarse convex shapes -- rocks read "boxy" and their hull tops float above
 * the visible surface). This module closes that gap: identify the entities
 * along a ray with Ogre's own RaySceneQuery, pull each entity's REAL triangle
 * geometry once per Ogre::Mesh straight out of its vertex/index buffers (the
 * classic GetMeshInformation walk -- safe here because every caller runs on
 * the render thread inside our hooks), cache the triangles in mesh-local
 * space, and Moller-Trumbore the ray against them.
 *
 * Everything is resolved from OgreMain_x64.dll exports by mangled name
 * (harvested from the SHIPPED dll -- note Kenshi runs a patched Ogre: e.g.
 * HardwareBuffer::lock grew an UploadOptions parameter). Struct-layout reads
 * (SubMesh/VertexData/IndexData/VertexElement are plain public-member Ogre
 * classes with no exported accessors) are validated adaptively at runtime and
 * the module self-disables on the first inconsistency -- it must never be
 * able to crash the game for a cosmetic refinement.
 *
 * Coordinate spaces: callers pass GAME coordinates; Ogre positions differ by
 * the floating-origin translation T (g_tx/g_tz, calibrated by the camera
 * weld) in x/z only. Callers must check g_have_t. */

/* ---- Ogre export names (exact strings from Kenshi's OgreMain_x64.dll) ---- */
#define OMR_CREATEQ  "?createRayQuery@SceneManager@Ogre@@UEAAPEAVRaySceneQuery@2@AEBVRay@2@I@Z"
#define OMR_SORTQ    "?setSortByDistance@RaySceneQuery@Ogre@@UEAAX_NG@Z"
#define OMR_EXECQ    "?execute@RaySceneQuery@Ogre@@UEAAAEAV?$vector@URaySceneQueryResultEntry@Ogre@@V?$STLAllocator@URaySceneQueryResultEntry@Ogre@@V?$CategorisedAllocPolicy@$0A@@2@@2@@std@@XZ"
#define OMR_DESTROYQ "?destroyQuery@SceneManager@Ogre@@UEAAXPEAVSceneQuery@2@@Z"
#define OMR_GETMGR   "?_getManager@MovableObject@Ogre@@QEBAPEAVSceneManager@2@XZ"
#define OMR_MOVTYPE  "?getMovableType@Entity@Ogre@@UEBAAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@XZ"
#define OMR_GETMESH  "?getMesh@Entity@Ogre@@QEBAAEBV?$SharedPtr@VMesh@Ogre@@@2@XZ"
#define OMR_HASSKEL  "?hasSkeleton@Entity@Ogre@@QEBA_NXZ"
#define OMR_PARENTSN "?getParentSceneNode@MovableObject@Ogre@@QEBAPEAVSceneNode@2@XZ"
#define OMR_NUMSUB   "?getNumSubMeshes@Mesh@Ogre@@QEBAGXZ"
#define OMR_GETSUB   "?getSubMesh@Mesh@Ogre@@QEBAPEAVSubMesh@2@G@Z"
#define OMR_FINDELEM "?findElementBySemantic@VertexDeclaration@Ogre@@UEBAPEBVVertexElement@2@W4VertexElementSemantic@2@G@Z"
#define OMR_GETBUF   "?getBuffer@VertexBufferBinding@Ogre@@UEBAAEBVHardwareVertexBufferSharedPtr@2@G@Z"
#define OMR_VSIZE    "?getVertexSize@HardwareVertexBuffer@Ogre@@QEBA_KXZ"
#define OMR_LOCKFULL "?lock@HardwareBuffer@Ogre@@QEAAPEAXW4LockOptions@12@W4UploadOptions@12@@Z"
#define OMR_UNLOCK   "?unlock@HardwareBuffer@Ogre@@UEAAXXZ"
#define OMR_IDXTYPE  "?getType@HardwareIndexBuffer@Ogre@@QEBA?AW4IndexType@12@XZ"
#define OMR_NUMIDX   "?getNumIndexes@HardwareIndexBuffer@Ogre@@QEBA_KXZ"
#define OMR_DPOS     "?_getDerivedPosition@Node@Ogre@@QEBA?AVVector3@2@XZ"
#define OMR_DORI     "?_getDerivedOrientation@Node@Ogre@@QEBA?AVQuaternion@2@XZ"
#define OMR_DSCALE   "?_getDerivedScale@Node@Ogre@@QEBA?AVVector3@2@XZ"
#define OMR_GETCREATOR "?getCreator@SceneNode@Ogre@@QEBAPEAVSceneManager@2@XZ"

typedef void *(*omr_createq_t)(void *sm, const float *ray6, unsigned mask);
typedef void  (*omr_sortq_t)(void *q, unsigned char on, unsigned short maxr);
typedef void *(*omr_execq_t)(void *q);
typedef void  (*omr_destroyq_t)(void *sm, void *q);
typedef void *(*omr_getmgr_t)(void *mov);
typedef void *(*omr_movtype_t)(void *mov);
typedef void *(*omr_getmesh_t)(void *ent);
typedef unsigned char (*omr_hasskel_t)(void *ent);
typedef void *(*omr_parentsn_t)(void *mov);
typedef unsigned short (*omr_numsub_t)(void *mesh);
typedef void *(*omr_getsub_t)(void *mesh, unsigned short i);
typedef const unsigned char *(*omr_findelem_t)(void *decl, int semantic, unsigned short idx);
typedef void *(*omr_getbuf_t)(void *binding, unsigned short src);
typedef size_t (*omr_vsize_t)(void *vbuf);
typedef void *(*omr_lockfull_t)(void *buf, int lockopt, int upopt);
typedef void  (*omr_unlock_t)(void *buf);
typedef int    (*omr_idxtype_t)(void *ibuf);
typedef size_t (*omr_numidx_t)(void *ibuf);
typedef Vec3 *(*omr_dpos_t)(void *node, Vec3 *out);
typedef Quat *(*omr_dori_t)(void *node, Quat *out);
typedef Vec3 *(*omr_dscale_t)(void *node, Vec3 *out);

static omr_createq_t  omr_createq;
static omr_sortq_t    omr_sortq;
static omr_execq_t    omr_execq;
static omr_destroyq_t omr_destroyq;
static omr_getmgr_t   omr_getmgr;
static omr_movtype_t  omr_movtype;
static omr_getmesh_t  omr_getmesh;
static omr_hasskel_t  omr_hasskel;
static omr_parentsn_t omr_parentsn;
static omr_numsub_t   omr_numsub;
static omr_getsub_t   omr_getsub;
static omr_findelem_t omr_findelem;
static omr_getbuf_t   omr_getbuf;
static omr_vsize_t    omr_vsize;
static omr_lockfull_t omr_lockfull;
static omr_unlock_t   omr_unlock;
static omr_idxtype_t  omr_idxtype;
static omr_numidx_t   omr_numidx;
static omr_dpos_t     omr_dpos;
static omr_dori_t     omr_dori;
static omr_dscale_t   omr_dscale;
typedef void *(*omr_getcreator_t)(void *scenenode);
static omr_getcreator_t omr_getcreator;

static int g_mr_ready;          /* all exports resolved */
static int g_mr_dead;           /* first inconsistency/fault = permanently off */

static void meshray_init(HMODULE ogre)
{
    if (!ogre) return;
    omr_createq  = (omr_createq_t) GetProcAddress(ogre, OMR_CREATEQ);
    omr_sortq    = (omr_sortq_t)   GetProcAddress(ogre, OMR_SORTQ);
    omr_execq    = (omr_execq_t)   GetProcAddress(ogre, OMR_EXECQ);
    omr_destroyq = (omr_destroyq_t)GetProcAddress(ogre, OMR_DESTROYQ);
    omr_getmgr   = (omr_getmgr_t)  GetProcAddress(ogre, OMR_GETMGR);
    omr_movtype  = (omr_movtype_t) GetProcAddress(ogre, OMR_MOVTYPE);
    omr_getmesh  = (omr_getmesh_t) GetProcAddress(ogre, OMR_GETMESH);
    omr_hasskel  = (omr_hasskel_t) GetProcAddress(ogre, OMR_HASSKEL);
    omr_parentsn = (omr_parentsn_t)GetProcAddress(ogre, OMR_PARENTSN);
    omr_numsub   = (omr_numsub_t)  GetProcAddress(ogre, OMR_NUMSUB);
    omr_getsub   = (omr_getsub_t)  GetProcAddress(ogre, OMR_GETSUB);
    omr_findelem = (omr_findelem_t)GetProcAddress(ogre, OMR_FINDELEM);
    omr_getbuf   = (omr_getbuf_t)  GetProcAddress(ogre, OMR_GETBUF);
    omr_vsize    = (omr_vsize_t)   GetProcAddress(ogre, OMR_VSIZE);
    omr_lockfull = (omr_lockfull_t)GetProcAddress(ogre, OMR_LOCKFULL);
    omr_unlock   = (omr_unlock_t)  GetProcAddress(ogre, OMR_UNLOCK);
    omr_idxtype  = (omr_idxtype_t) GetProcAddress(ogre, OMR_IDXTYPE);
    omr_numidx   = (omr_numidx_t)  GetProcAddress(ogre, OMR_NUMIDX);
    omr_dpos     = (omr_dpos_t)    GetProcAddress(ogre, OMR_DPOS);
    omr_dori     = (omr_dori_t)    GetProcAddress(ogre, OMR_DORI);
    omr_dscale   = (omr_dscale_t)  GetProcAddress(ogre, OMR_DSCALE);
    omr_getcreator = (omr_getcreator_t)GetProcAddress(ogre, OMR_GETCREATOR);
    g_mr_ready = omr_createq && omr_sortq && omr_execq && omr_destroyq
              && omr_getmgr && omr_movtype && omr_getmesh && omr_parentsn
              && omr_numsub && omr_getsub && omr_findelem && omr_getbuf
              && omr_vsize && omr_lockfull && omr_unlock && omr_idxtype
              && omr_numidx && omr_dpos && omr_dori && omr_dscale;
    logline("[cmesh] Ogre exports %s (hasSkeleton=%p)",
            g_mr_ready ? "resolved" : "INCOMPLETE -- true-mesh queries off",
            (void *)omr_hasskel);
}

/* MSVC std::string reader (VC10 layout: {buf/ptr 16B, size 8, cap 8}) */
static const char *omr_cstr(const void *s)
{
    if (!readable(s, 0x20)) return "";
    size_t cap = *(const size_t *)((const unsigned char *)s + 0x18);
    return cap >= 16 ? *(const char *const *)s : (const char *)s;
}

/* ---- triangle cache: LOCAL-space triangle soup per Ogre::Mesh ---- */
#define MR_MAX_MESH 48
#define MR_MAX_TRI  80000
typedef struct { void *mesh; int ntri; float *v; } mr_cache_t;   /* v = ntri*9 floats */
static mr_cache_t g_mr_cache[MR_MAX_MESH];
static int g_mr_ncache;

/* Adaptive VertexData layout: Ogre 1.8 puts HardwareBufferManagerBase* mMgr
 * first ({mgr, decl, bind, start, count}); older layouts start at decl. We
 * validate whichever variant yields a declaration that findElementBySemantic
 * accepts and a sane vertex count. */
static int omr_vdata(void *vd, void **decl, void **bind, size_t *vstart, size_t *vcount)
{
    static int base = -1;                      /* discovered field base: 8 or 0 */
    for (int attempt = 0; attempt < 2; attempt++) {
        int b = (base >= 0) ? base : (attempt == 0 ? 8 : 0);
        if (!readable((unsigned char *)vd + b, 0x20)) { if (base >= 0) break; continue; }
        void *d  = *(void **)((unsigned char *)vd + b);
        void *bi = *(void **)((unsigned char *)vd + b + 8);
        size_t st = *(size_t *)((unsigned char *)vd + b + 16);
        size_t ct = *(size_t *)((unsigned char *)vd + b + 24);
        if (readable(d, 8) && readable(bi, 8) && ct > 0 && ct < 4000000 && st < 4000000) {
            const unsigned char *el = omr_findelem(d, 1 /*VES_POSITION*/, 0);
            if (readable(el, 0x18)) {
                if (base < 0) { base = b; logline("[cmesh] VertexData base=+%d", b); }
                *decl = d; *bind = bi; *vstart = st; *vcount = ct;
                return 1;
            }
        }
        if (base >= 0) break;
    }
    return 0;
}

static mr_cache_t *omr_cache_mesh(void *mesh)
{
    for (int i = 0; i < g_mr_ncache; i++)
        if (g_mr_cache[i].mesh == mesh) return g_mr_cache[i].ntri ? &g_mr_cache[i] : NULL;
    if (g_mr_ncache >= MR_MAX_MESH) return NULL;
    mr_cache_t *c = &g_mr_cache[g_mr_ncache++];
    c->mesh = mesh; c->ntri = 0; c->v = NULL;

    int cap = 20000;                       /* grown up to MR_MAX_TRI on demand */
    float *tris = (float *)malloc((size_t)cap * 9 * sizeof(float));
    if (!tris) return NULL;
    int ntri = 0, skipped_shared = 0;

    unsigned short ns = omr_numsub(mesh);
    if (ns > 64) { free(tris); return NULL; }   /* garbage guard */
    for (unsigned short si = 0; si < ns; si++) {
        void *sub = omr_getsub(mesh, si);
        if (!readable(sub, 0x18)) continue;
        /* SubMesh (1.8, non-virtual): useSharedVertices@0, opType@4,
         * vertexData@8, indexData@16 */
        unsigned char shared = *(unsigned char *)sub;
        if (shared > 1) continue;               /* layout mismatch guard */
        if (shared) { skipped_shared++; continue; }
        void *vd = *(void **)((unsigned char *)sub + 8);
        void *id = *(void **)((unsigned char *)sub + 16);
        if (!readable(vd, 0x30) || !readable(id, 0x20)) continue;

        void *decl, *bind; size_t vstart, vcount;
        if (!omr_vdata(vd, &decl, &bind, &vstart, &vcount)) continue;
        const unsigned char *el = omr_findelem(decl, 1, 0);
        if (!readable(el, 0x18)) continue;
        /* VertexElement: source u16@0, offset size_t@8, type u32@16 (FLOAT3=2) */
        unsigned short esrc = *(const unsigned short *)el;
        size_t eoff = *(const size_t *)(el + 8);
        unsigned etype = *(const unsigned *)(el + 16);
        if (etype != 2 /*VET_FLOAT3*/ || eoff > 512) continue;
        void *vbufp = omr_getbuf(bind, esrc);           /* -> SharedPtr& */
        void *vbuf = readable(vbufp, 8) ? *(void **)vbufp : NULL;
        if (!readable(vbuf, 8)) continue;
        size_t stride = omr_vsize(vbuf);
        if (stride < 12 || stride > 512) continue;

        /* IndexData: SharedPtr indexBuffer@0 (16B), indexStart@16, indexCount@24 */
        void *ibuf = *(void **)id;
        size_t istart = *(size_t *)((unsigned char *)id + 16);
        size_t icount = *(size_t *)((unsigned char *)id + 24);
        if (!readable(ibuf, 8) || icount < 3 || icount > 3000000) continue;
        int wide = omr_idxtype(ibuf) == 1;              /* IT_32BIT */
        size_t nidx = omr_numidx(ibuf);
        if (istart + icount > nidx) continue;

        unsigned char *vp = (unsigned char *)omr_lockfull(vbuf, 2 /*READ_ONLY*/, 0);
        if (!vp) continue;
        unsigned char *ip = (unsigned char *)omr_lockfull(ibuf, 2, 0);
        if (!ip) { omr_unlock(vbuf); continue; }
        for (size_t k = 0; k + 2 < icount && ntri < MR_MAX_TRI; k += 3) {
            unsigned i0, i1, i2;
            if (wide) { unsigned *w = (unsigned *)ip + istart + k; i0=w[0]; i1=w[1]; i2=w[2]; }
            else { unsigned short *w = (unsigned short *)ip + istart + k; i0=w[0]; i1=w[1]; i2=w[2]; }
            if (i0 >= vstart + vcount || i1 >= vstart + vcount || i2 >= vstart + vcount) continue;
            if (ntri >= cap) {
                if (cap >= MR_MAX_TRI) break;
                cap = cap * 2 > MR_MAX_TRI ? MR_MAX_TRI : cap * 2;
                float *nt = (float *)realloc(tris, (size_t)cap * 9 * sizeof(float));
                if (!nt) break;
                tris = nt;
            }
            float *t = tris + (size_t)ntri * 9;
            const float *p0 = (const float *)(vp + (size_t)i0 * stride + eoff);
            const float *p1 = (const float *)(vp + (size_t)i1 * stride + eoff);
            const float *p2 = (const float *)(vp + (size_t)i2 * stride + eoff);
            t[0]=p0[0]; t[1]=p0[1]; t[2]=p0[2];
            t[3]=p1[0]; t[4]=p1[1]; t[5]=p1[2];
            t[6]=p2[0]; t[7]=p2[1]; t[8]=p2[2];
            ntri++;
        }
        omr_unlock(ibuf);
        omr_unlock(vbuf);
    }
    if (!ntri) { free(tris); c->v = NULL;
        logline("[cmesh] mesh %p: no readable triangles (%d shared submeshes skipped)",
                mesh, skipped_shared);
        static int xd;                       /* offset-derivation dump: my SubMesh/
            * VertexData layout guesses failed for this build -- print raw bytes
            * so the real field offsets can be read off the field log */
        if (KFP_DEBUG_LOG && xd < 2 && ns > 0) { xd++;
            void *sub = omr_getsub(mesh, 0);
            if (readable(sub, 0x40)) {
                unsigned char *pb = (unsigned char *)sub;
                char hx[0x40 * 3 + 4]; int hp = 0;
                for (int i2 = 0; i2 < 0x40; i2++)
                    hp += snprintf(hx + hp, sizeof hx - hp, "%02x ", pb[i2]);
                logline("[cmesh] xdiag sub0=%p: %s", sub, hx);
                for (int cand = 0; cand < 0x30; cand += 8) {
                    void *q2 = *(void **)(pb + cand);
                    if (readable(q2, 0x40)) {
                        unsigned char *vb = (unsigned char *)q2;
                        char h2[0x40 * 3 + 4]; int p2 = 0;
                        for (int i2 = 0; i2 < 0x40; i2++)
                            p2 += snprintf(h2 + p2, sizeof h2 - p2, "%02x ", vb[i2]);
                        logline("[cmesh] xdiag sub0+%02x -> %p: %s", cand, q2, h2);
                    }
                }
            }
        }
        return NULL; }
    c->v = tris; c->ntri = ntri;
    logline("[cmesh] cached mesh %p: %d tris (%u submeshes%s)",
            mesh, ntri, (unsigned)ns, skipped_shared ? ", shared skipped" : "");
    return c;
}

/* Moller-Trumbore; returns t along (normalized) dir or -1 */
static float omr_tri_ray(const float *t, const Vec3 *o, const Vec3 *d)
{
    float e1x=t[3]-t[0], e1y=t[4]-t[1], e1z=t[5]-t[2];
    float e2x=t[6]-t[0], e2y=t[7]-t[1], e2z=t[8]-t[2];
    float px = d->y*e2z - d->z*e2y, py = d->z*e2x - d->x*e2z, pz = d->x*e2y - d->y*e2x;
    float det = e1x*px + e1y*py + e1z*pz;
    if (det > -1e-7f && det < 1e-7f) return -1.0f;
    float inv = 1.0f / det;
    float tx = o->x - t[0], ty = o->y - t[1], tz = o->z - t[2];
    float u = (tx*px + ty*py + tz*pz) * inv;
    if (u < -0.001f || u > 1.001f) return -1.0f;
    float qx = ty*e1z - tz*e1y, qy = tz*e1x - tx*e1z, qz = tx*e1y - ty*e1x;
    float v = (d->x*qx + d->y*qy + d->z*qz) * inv;
    if (v < -0.001f || u + v > 1.001f) return -1.0f;
    float tt = (e2x*qx + e2y*qy + e2z*qz) * inv;
    return tt > 0.0f ? tt : -1.0f;
}

static Vec3 omr_qrot(const Quat *q, Vec3 v)   /* rotate v by quaternion */
{
    Vec3 u = { q->x, q->y, q->z };
    float s = q->w;
    float du = u.x*v.x + u.y*v.y + u.z*v.z;
    float uu = u.x*u.x + u.y*u.y + u.z*u.z;
    Vec3 c = { u.y*v.z - u.z*v.y, u.z*v.x - u.x*v.z, u.x*v.y - u.y*v.x };
    Vec3 r = { 2*du*u.x + (s*s-uu)*v.x + 2*s*c.x,
               2*du*u.y + (s*s-uu)*v.y + 2*s*c.y,
               2*du*u.z + (s*s-uu)*v.z + 2*s*c.z };
    return r;
}

/* last-refined entity snapshot: the perch's rock. Lets per-foot ground queries
 * skip the scene query and test ONE cached mesh. */
static void *g_mr_perch_node;
static mr_cache_t *g_mr_perch_cache;

/* Down-column query against the snapshot entity only. GAME coords (x, z),
 * ray from ytop downward. Returns the surface y, or -99999 on miss. */
static float meshray_perch_column(float gx, float ytop, float gz)
{
    if (!g_mr_ready || g_mr_dead || !g_have_t) return -99999.0f;
    mr_cache_t *c = g_mr_perch_cache;
    void *node = g_mr_perch_node;
    if (!c || !c->ntri || !readable(node, 8)) return -99999.0f;
    Vec3 npos, nsc; Quat nori;
    omr_dpos(node, &npos); omr_dori(node, &nori); omr_dscale(node, &nsc);
    if (fabsf(nsc.x) < 1e-6f || fabsf(nsc.y) < 1e-6f || fabsf(nsc.z) < 1e-6f)
        return -99999.0f;
    Vec3 origin = { gx + g_tx, ytop, gz + g_tz };
    Vec3 dir = { 0.0f, -1.0f, 0.0f };
    Quat inv = { nori.w, -nori.x, -nori.y, -nori.z };
    Vec3 lo = omr_qrot(&inv, (Vec3){ origin.x - npos.x, origin.y - npos.y,
                                     origin.z - npos.z });
    lo.x /= nsc.x; lo.y /= nsc.y; lo.z /= nsc.z;
    Vec3 ld = omr_qrot(&inv, dir);
    ld.x /= nsc.x; ld.y /= nsc.y; ld.z /= nsc.z;
    float ll = sqrtf(ld.x*ld.x + ld.y*ld.y + ld.z*ld.z);
    if (ll < 1e-9f) return -99999.0f;
    ld.x /= ll; ld.y /= ll; ld.z /= ll;
    float bt = -1.0f;
    for (int ti = 0; ti < c->ntri; ti++) {
        float tt = omr_tri_ray(c->v + (size_t)ti * 9, &lo, &ld);
        if (tt > 0.0f && (bt < 0.0f || tt < bt)) bt = tt;
    }
    if (bt < 0.0f) return -99999.0f;
    Vec3 lh = { lo.x + ld.x * bt, lo.y + ld.y * bt, lo.z + ld.z * bt };
    lh.x *= nsc.x; lh.y *= nsc.y; lh.z *= nsc.z;
    Vec3 wh = omr_qrot(&nori, lh);
    return wh.y + npos.y;               /* y is not floating-origin shifted */
}

/* True-geometry raycast. GAME-coordinate in/out; needs g_have_t. Returns 1 and
 * writes the nearest visual-triangle hit within maxdist. */
static int meshray_refine(const Vec3 *game_from, const Vec3 *dir_in, float maxdist,
                          Vec3 *out_game)
{
    static int mrdiag;                        /* one-shot pipeline probe */
    if (!g_mr_ready || g_mr_dead || !g_have_t) return 0;
    void *cam = readable((void *)(g_base + RVA_CAM_INSTANCE), 8)
              ? *(void **)(g_base + RVA_CAM_INSTANCE) : NULL;
    if (!readable(cam, CC_CAMERA + 8)) return 0;
    /* SceneManager: from the CENTER SceneNode (CC_CENTER, proven live -- the
     * camera weld reads it every frame) via SceneNode::getCreator. The old
     * path tried MovableObject::_getManager on the +0x68/+0x58 slots, but the
     * vtable-in-OgreMain test can't tell a Camera from a SceneNode and
     * _getManager on a NODE read a null field -- the whole pipeline was dead
     * (field log: "_getManager unreadable (0)" on every perch tick). */
    void *sm = NULL;
    if (omr_getcreator) {
        void *center = *(void **)((uintptr_t)cam + CC_CENTER);
        if (readable(center, 8)) sm = omr_getcreator(center);
    }
    if (!readable(sm, 8)) {                    /* fallback: the old camera path */
        void *camObj = *(void **)((uintptr_t)cam + CC_CAMERA);
        sm = readable(camObj, 8) ? omr_getmgr(camObj) : NULL;
    }
    if (!readable(sm, 8)) {
        if (mrdiag < 3) { mrdiag++; logline("[cmesh] no SceneManager (creator+mgr both failed)"); }
        return 0;
    }

    float dl = sqrtf(dir_in->x*dir_in->x + dir_in->y*dir_in->y + dir_in->z*dir_in->z);
    if (dl < 1e-6f) return 0;
    Vec3 dir = { dir_in->x / dl, dir_in->y / dl, dir_in->z / dl };
    Vec3 origin = { game_from->x + g_tx, game_from->y, game_from->z + g_tz };
    float ray6[6] = { origin.x, origin.y, origin.z, dir.x, dir.y, dir.z };

    void *q = omr_createq(sm, ray6, 0xffffffffu);
    if (!q) { if (mrdiag < 3) { mrdiag++; logline("[cmesh] createRayQuery NULL"); } return 0; }
    omr_sortq(q, 1, 16);
    void *vec = omr_execq(q);                 /* std::vector<Entry{f32 dist, mov*, frag*}> */
    if (KFP_DEBUG_LOG && mrdiag < 3) {
        mrdiag++;
        int nn = readable(vec, 0x18)
               ? (int)((*((unsigned char **)vec + 1) - *(unsigned char **)vec) / 24) : -1;
        logline("[cmesh] probe: sm=%p q=%p entries=%d", sm, q, nn);
        unsigned char *f0 = readable(vec, 0x18) ? *(unsigned char **)vec : NULL;
        for (int e = 0; e < nn && e < 4; e++) {
            unsigned char *en = f0 + (size_t)e * 24;
            if (!readable(en, 24)) break;
            void *mv2 = *(void **)(en + 8);
            logline("[cmesh]   e%d dist=%.1f type=%s skel=%d", e, *(float *)en,
                    readable(mv2, 8) ? omr_cstr(omr_movtype(mv2)) : "?",
                    (omr_hasskel && readable(mv2, 8)) ? omr_hasskel(mv2) : -1);
        }
    }
    int hitok = 0;
    float bestw = maxdist;
    Vec3 best = {0,0,0};
    if (readable(vec, 0x18)) {
        unsigned char *first = *(unsigned char **)vec;
        unsigned char *last  = *((unsigned char **)vec + 1);
        int n = (int)((last - first) / 24);
        if (n > 16) n = 16;
        for (int e = 0; e < n; e++) {
            unsigned char *en = first + (size_t)e * 24;
            if (!readable(en, 24)) break;
            float edist = *(float *)en;
            void *mov = *(void **)(en + 8);
            if (edist > maxdist + 10.0f) break;          /* sorted: done */
            if (!readable(mov, 8)) continue;
            const char *ty = omr_cstr(omr_movtype(mov));
            if (strcmp(ty, "Entity") != 0) continue;
            if (omr_hasskel && omr_hasskel(mov)) continue;   /* characters (incl. self) */
            void *meshref = omr_getmesh(mov);
            void *mesh = readable(meshref, 8) ? *(void **)meshref : NULL;
            if (!readable(mesh, 8)) continue;
            void *node = omr_parentsn(mov);
            if (!readable(node, 8)) continue;
            mr_cache_t *c = omr_cache_mesh(mesh);
            if (!c) continue;
            Vec3 npos, nsc; Quat nori;
            omr_dpos(node, &npos); omr_dori(node, &nori); omr_dscale(node, &nsc);
            if (fabsf(nsc.x) < 1e-6f || fabsf(nsc.y) < 1e-6f || fabsf(nsc.z) < 1e-6f)
                continue;
            /* ray -> mesh-local: conj-rotate, divide scale */
            Quat inv = { nori.w, -nori.x, -nori.y, -nori.z };
            Vec3 lo = omr_qrot(&inv, (Vec3){ origin.x - npos.x, origin.y - npos.y,
                                             origin.z - npos.z });
            lo.x /= nsc.x; lo.y /= nsc.y; lo.z /= nsc.z;
            Vec3 ld = omr_qrot(&inv, dir);
            ld.x /= nsc.x; ld.y /= nsc.y; ld.z /= nsc.z;
            float ll = sqrtf(ld.x*ld.x + ld.y*ld.y + ld.z*ld.z);
            if (ll < 1e-9f) continue;
            ld.x /= ll; ld.y /= ll; ld.z /= ll;
            float bt = -1.0f;
            for (int ti = 0; ti < c->ntri; ti++) {
                float tt = omr_tri_ray(c->v + (size_t)ti * 9, &lo, &ld);
                if (tt > 0.0f && (bt < 0.0f || tt < bt)) bt = tt;
            }
            if (bt < 0.0f) continue;
            Vec3 lh = { lo.x + ld.x * bt, lo.y + ld.y * bt, lo.z + ld.z * bt };
            lh.x *= nsc.x; lh.y *= nsc.y; lh.z *= nsc.z;
            Vec3 wh = omr_qrot(&nori, lh);
            wh.x += npos.x; wh.y += npos.y; wh.z += npos.z;
            float wd = (wh.x - origin.x) * dir.x + (wh.y - origin.y) * dir.y
                     + (wh.z - origin.z) * dir.z;
            if (wd > 0.0f && wd < bestw) {
                bestw = wd; best = wh; hitok = 1;
                g_mr_perch_node = node; g_mr_perch_cache = c;   /* snapshot for
                    * fast column queries (perch foot IK) */
            }
        }
    }
    omr_destroyq(sm, q);
    if (hitok) {
        out_game->x = best.x - g_tx;
        out_game->y = best.y;
        out_game->z = best.z - g_tz;
    }
    return hitok;
}
