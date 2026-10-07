/* Camera zoom keeps direct-control ownership; native+visual static collision.
 * Floating-origin calibration uses the pre-offset anchor, never the orbit eye. */
static Vec3 g_view_anchor, g_view_written;
/* combat physics trace past characters (kfp_controls.inc, after the trace bindings): wall distance or -1 */
static float fp_view_trace_wall(const Vec3 *from,const Vec3 *dir,float range);
static unsigned g_view_trace_blocks;
static int g_view_have_anchor, g_view_collision_dead;
static volatile LONG g_view_injected_wheel;
static void fp_view_input(void) {
    LONG wheel=InterlockedExchange(&g_wheel_accum,0);
    LONG injected=InterlockedExchange(&g_view_injected_wheel,0);
    if (!game_has_focus()) wheel=0; /* physical input ignored in other apps */
    wheel+=injected; /* explicit harness injection follows the same zoom math */
    g_dbg_wheel=(int)wheel;
    if (!g_fp_mode || g_ui_open) return; /* discard UI/focus wheels */
    if (g_cfg_camera_zoom) kfp_view_wheel(&g_view,(int)wheel);
    else if (g_cfg_wheel) {
        g_speed_scale+=(float)wheel*(0.15f/120.0f);
        if (g_speed_scale<0.15f) g_speed_scale=0.15f;
        if (g_speed_scale>1.0f) g_speed_scale=1.0f;
    }
}
static int fp_view_is_eye(void) {
    return !g_cfg_camera_zoom || kfp_view_is_eye(&g_view);
}
static void fp_view_apply(Vec3 *eye) {
    g_view_anchor=*eye; g_view_have_anchor=1;
    if (!g_cfg_camera_zoom) { g_view.applied=0; g_view_written=*eye; return; }
    float wanted=kfp_view_next(&g_view,g_frame_dt);
    g_view.blocked=0; g_view.collision_known=1;
    if (wanted<=0.001f) { g_view.applied=0; g_view_written=*eye; return; }
    if (!g_have_t || !RVA_RAYCAST || !RVA_GROUND_NOHIT || g_view_collision_dead) {
        g_view.applied=0; g_view.collision_known=0; g_view_written=*eye; return;
    }
    float cp=cosf(g_pitch);
    Vec3 dir={-sinf(g_yaw)*cp,sinf(g_pitch),-cosf(g_yaw)*cp};
    Vec3 right={cosf(g_yaw),0,-sinf(g_yaw)};
    Vec3 up={-sinf(g_yaw)*sinf(g_pitch),-cp,-cosf(g_yaw)*sinf(g_pitch)};
    const float sides[5][2]={{0,0},{.18f,0},{-.18f,0},{0,.18f},{0,-.18f}};
    float allowed=wanted;
    void *old_perch_node=g_mr_perch_node;
    mr_cache_t *old_perch_cache=g_mr_perch_cache;
    if (setjmp(g_guard_jb)) {
        g_guard_armed=0; g_view_collision_dead=1;
        g_mr_perch_node=old_perch_node; g_mr_perch_cache=old_perch_cache;
        g_view.applied=0; g_view.collision_known=0; g_view_written=*eye;
        logline("[view] collision fault; camera stays at eyes"); return;
    }
    guard_arm();
    for (int i=0;i<5;++i) {
        Vec3 from={eye->x-g_tx+right.x*sides[i][0]+up.x*sides[i][1],
                   eye->y+right.y*sides[i][0]+up.y*sides[i][1],
                   eye->z-g_tz+right.z*sides[i][0]+up.z*sides[i][1]};
        Vec3 hit;
        {   /* the physics trace the aim uses stops at building walls (R10); fall_ray/mesh missed shack walls (b30) */
            float distance=fp_view_trace_wall(&from,&dir,wanted+.25f);
            if (distance>=0 && distance<allowed+.25f) {
                float limit=distance-.25f; if (limit<0) limit=0;
                if (limit<allowed) { allowed=limit; g_view.blocked=1; ++g_view_trace_blocks; }
            }
        }
        for (int visual=0;visual<2;++visual) {
            int got=visual?meshray_refine(&from,&dir,wanted+.25f,&hit):fall_ray(&from,&dir,&hit);
            if (!got) continue;
            float distance=(hit.x-from.x)*dir.x+(hit.y-from.y)*dir.y+(hit.z-from.z)*dir.z;
            if (isfinite(distance) && distance>=0 && distance<allowed+.25f) {
                float limit=distance-.25f; if (limit<0) limit=0;
                if (limit<allowed) { allowed=limit; g_view.blocked=1; }
            }
        }
    }
    g_mr_perch_node=old_perch_node; g_mr_perch_cache=old_perch_cache;
    g_guard_armed=0;
    g_view.applied=allowed;
    eye->x+=dir.x*allowed; eye->y+=dir.y*allowed; eye->z+=dir.z*allowed;
    g_view_written=*eye;
}
static int kah_fp_camera(const char *id,int argc,const char *const *argv,KAH_Reply *r,void *u) {
    (void)id; (void)u;
    if (argc==4 && !_stricmp(argv[1],"look")) {
        char *end;errno=0;float yaw=strtof(argv[2],&end);
        if (errno||end==argv[2]||*end||!isfinite(yaw)||fabsf(yaw)>6.283186f) {
            r->append(r,"yaw must be finite radians -2pi..2pi");return KAH_ERROR;
        }
        errno=0;float pitch=strtof(argv[3],&end);
        if (errno||end==argv[3]||*end||!isfinite(pitch)||fabsf(pitch)>1.4f) {
            r->append(r,"pitch must be finite radians -1.4..1.4");return KAH_ERROR;
        }
        if (!g_fp_mode||g_ui_open||g_is_down) {
            r->append(r,"direct camera control unavailable");return KAH_ERROR;
        }
        g_yaw=yaw;g_pitch=pitch;
        r->append(r,"look requested through normal camera update; verify actual state next frame");return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"distance")) {
        char *end; errno=0; float d=strtof(argv[2],&end);
        if (errno || end==argv[2] || *end || !isfinite(d) || d<0 || d>KFP_VIEW_MAX) {
            r->append(r,"distance must be finite 0..60"); return KAH_ERROR;
        }
        g_view.target=d; r->append(r,"camera distance requested; verify applied/actual state"); return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"wheel")) {
        char *end; errno=0; long n=strtol(argv[2],&end,10);
        if (errno || end==argv[2] || *end || n< -2400 || n>2400) {
            r->append(r,"wheel delta must be integer -2400..2400"); return KAH_ERROR;
        }
        InterlockedExchangeAdd(&g_view_injected_wheel,(LONG)n);
        r->append(r,"wheel input queued through normal zoom handler"); return KAH_OK;
    }
    if ((argc>=8 && argc<=10) && !_stricmp(argv[1],"ray")) {
        /* C05-STAIRS setup: one engine ray in game coords, `ray x y z dx dy dz [range] [mask]` (mask default
         * 0x88204 = the collision world: terrain, building shells/floors, rocks). Reply "ray d=<along dir>
         * hit=x,y,z mask=0x..." or "ray miss". The test scans a built house with downward rays for its floors. */
        float v[7]={0,0,0,0,0,0,1e9f}; unsigned mask=0x88204u; char *end;
        for (int i=0;i<7 && i+2<argc;++i) {
            errno=0; v[i]=strtof(argv[i+2],&end);
            if (errno||end==argv[i+2]||*end||!isfinite(v[i])) { r->append(r,"ray: x y z dx dy dz [range] must be finite numbers"); return KAH_ERROR; }
        }
        if (argc==10) { errno=0; unsigned long m=strtoul(argv[9],&end,0);
            if (errno||end==argv[9]||*end||!m) { r->append(r,"ray: mask must be a nonzero integer (0x.. ok)"); return KAH_ERROR; }
            mask=(unsigned)m; }
        float dl=sqrtf(v[3]*v[3]+v[4]*v[4]+v[5]*v[5]);
        if (!(dl>1e-6f)||!(v[6]>0)) { r->append(r,"ray: direction must be nonzero, range > 0"); return KAH_ERROR; }
        if (!g_base||!RVA_RAYCAST||!RVA_GROUND_NOHIT) { r->append(r,"ray unavailable (no raycast)"); return KAH_ERROR; }
        if (g_guard_armed) { r->append(r,"ray busy"); return KAH_ERROR; }
        Vec3 from={v[0],v[1],v[2]},dir={v[3]/dl,v[4]/dl,v[5]/dl},hit; int got;
        if (setjmp(g_guard_jb)) { g_guard_armed=0; r->append(r,"ray fault"); return KAH_ERROR; }
        guard_arm(); got=fall_ray_m(&from,&dir,&hit,mask); g_guard_armed=0;
        char b[200]; float d=got?(hit.x-from.x)*dir.x+(hit.y-from.y)*dir.y+(hit.z-from.z)*dir.z:-1.0f;
        if (!got||d>v[6]) snprintf(b,sizeof(b),"ray miss mask=0x%x",mask);
        else snprintf(b,sizeof(b),"ray d=%.2f hit=%.2f,%.2f,%.2f mask=0x%x",d,hit.x,hit.y,hit.z,mask);
        r->append(r,b); return KAH_OK;
    }
    if (argc==8 && !_stricmp(argv[1],"floors")) {
        /* C05-STAIRS setup: `floors cx cz half step ytop ybot` -- a grid of downward rays (mask 0x88204) over the
         * square cx+-half, cz+-half; per cell the surfaces from ytop down to ybot (each next ray starts 0.5 below
         * the last hit, at most 8 per cell). Reply "floors cells=N" then " x,z:y1/y2/..;" per cell with a hit. */
        float v[6]; char *end;
        for (int i=0;i<6;++i) { errno=0; v[i]=strtof(argv[i+2],&end);
            if (errno||end==argv[i+2]||*end||!isfinite(v[i])) { r->append(r,"floors: cx cz half step ytop ybot must be finite"); return KAH_ERROR; } }
        if (!(v[2]>0&&v[2]<=200&&v[3]>=1&&v[4]>v[5])||(int)(2*v[2]/v[3]+1)>81) { r->append(r,"floors: 0<half<=200, step>=1 (<=81 per side), ytop>ybot"); return KAH_ERROR; }
        if (!g_base||!RVA_RAYCAST||!RVA_GROUND_NOHIT) { r->append(r,"floors unavailable (no raycast)"); return KAH_ERROR; }
        if (g_guard_armed) { r->append(r,"floors busy"); return KAH_ERROR; }
        int cells=0; char b[160];
        static const Vec3 down={0,-1,0};
        for (float x=v[0]-v[2]; x<=v[0]+v[2]+0.01f; x+=v[3]) for (float z=v[1]-v[2]; z<=v[1]+v[2]+0.01f; z+=v[3]) {
            Vec3 from={x,v[4],z},hit; size_t n=0; int k;
            n+=snprintf(b,sizeof(b)," %.1f,%.1f:",x,z);
            for (k=0;k<8;++k) {
                int got;
                if (setjmp(g_guard_jb)) { g_guard_armed=0; r->append(r," fault"); return KAH_ERROR; }
                guard_arm(); got=fall_ray_m(&from,&down,&hit,0x88204u); g_guard_armed=0;
                if (!got||hit.y<v[5]||hit.y>from.y+0.01f) break;
                n+=snprintf(b+n,sizeof(b)-n,"%s%.1f",k?"/":"",hit.y);
                if (n>=sizeof(b)-12) break;
                from.y=hit.y-0.5f;
            }
            if (k) { snprintf(b+n,sizeof(b)-n,";"); if (!cells) r->append(r,"floors"); r->append(r,b); ++cells; }
        }
        snprintf(b,sizeof(b)," cells=%d",cells); r->append(r,b); return KAH_OK;
    }
    if (argc==2 && !_stricmp(argv[1],"probe")) {
        /* C05-INTERIOR diagnostics: the camera's pull-back ray (from the eye anchor, backwards along the look)
         * per collision mask: cam = the mask fp_view_apply uses (0x88204), all = every group but bit 0, mesh =
         * the visual mesh refine, bits = each single group bit that hits within 20 dm. Distances along the ray. */
        if (!g_view_have_anchor || !g_have_t || !RVA_RAYCAST || !RVA_GROUND_NOHIT) { r->append(r,"probe unavailable (no anchor/T/raycast)"); return KAH_ERROR; }
        if (g_guard_armed) { r->append(r,"probe busy"); return KAH_ERROR; }
        float cp=cosf(g_pitch);
        Vec3 dir={-sinf(g_yaw)*cp,sinf(g_pitch),-cosf(g_yaw)*cp};
        Vec3 from={g_view_anchor.x-g_tx,g_view_anchor.y,g_view_anchor.z-g_tz},hit;
        char b[900]; size_t n=0; float d;
        void *old_node=g_mr_perch_node; mr_cache_t *old_cache=g_mr_perch_cache;
        if (setjmp(g_guard_jb)) { g_guard_armed=0; g_mr_perch_node=old_node; g_mr_perch_cache=old_cache; r->append(r,"probe fault"); return KAH_ERROR; }
        guard_arm();
#define KFP_PROBE_D(got) ((got)?((hit.x-from.x)*dir.x+(hit.y-from.y)*dir.y+(hit.z-from.z)*dir.z):-1.0f)
        d=KFP_PROBE_D(fall_ray_m(&from,&dir,&hit,0x88204u)); n+=snprintf(b+n,sizeof(b)-n,"probe from=%.1f,%.1f,%.1f yaw=%.4f cam=%.2f",from.x,from.y,from.z,g_yaw,d);
        d=KFP_PROBE_D(fall_ray_m(&from,&dir,&hit,0xfffffffeu)); n+=snprintf(b+n,sizeof(b)-n," all=%.2f",d);
        d=KFP_PROBE_D(meshray_refine(&from,&dir,20.0f,&hit)); n+=snprintf(b+n,sizeof(b)-n," mesh=%.2f",d);
        d=fp_view_trace_wall(&from,&dir,KFP_VIEW_MAX+1.0f); n+=snprintf(b+n,sizeof(b)-n," trace=%.2f bits=",d);
        for (int bit=1;bit<32 && n<sizeof(b)-24;++bit) {
            d=KFP_PROBE_D(fall_ray_m(&from,&dir,&hit,1u<<bit));
            if (d>=0 && d<20.0f) n+=snprintf(b+n,sizeof(b)-n,"%d:%.2f,",bit,d);
        }
#undef KFP_PROBE_D
        g_guard_armed=0; g_mr_perch_node=old_node; g_mr_perch_cache=old_cache;
        r->append(r,b); return KAH_OK;
    }
    if (argc!=2 || _stricmp(argv[1],"state")) {
        r->append(r,"usage: fp_camera state|probe|distance <0..60>|wheel <-2400..2400>|look <yaw radians> <pitch radians>|ray x y z dx dy dz [range] [mask]|floors cx cz half step ytop ybot"); return KAH_ERROR;
    }
    Vec3 actual={0},fresh={0}; int have_actual=0,have_fresh=0;
    if (g_fp_mode && g_have_eye && g_fp_control_actor && g_ogre_ready && g_node_get_dpos && g_view_have_anchor) {
        void *cam=readable((void *)(g_base+RVA_CAM_INSTANCE),8)?*(void **)(g_base+RVA_CAM_INSTANCE):NULL;
        void *node=readable(cam,CC_NODE+8)?*(void **)((uintptr_t)cam+CC_NODE):NULL;
        if (readable(node,8)) {
            if (setjmp(g_guard_jb)) { g_guard_armed=0; r->append(r,"camera read fault"); return KAH_ERROR; }
            guard_arm();
            const Vec3 *p=g_node_get_dpos(node,&actual);
            if (readable((void *)p,sizeof(actual))) { actual=*p; have_actual=1; }
            if (g_node_getdpos_upd) {   /* forced scene-graph update: the cached value can be stale */
                const Vec3 *q=g_node_getdpos_upd(node,&fresh);
                if (readable((void *)q,sizeof(fresh))) { fresh=*q; have_fresh=1; }
            }
            g_guard_armed=0;
        }
    }
    float cached_distance=-1;
    if (have_actual) {
        float x=actual.x-g_view_anchor.x,y=actual.y-g_view_anchor.y,z=actual.z-g_view_anchor.z;
        cached_distance=sqrtf(x*x+y*y+z*z);
    }
    /* The cached derived position lags our set_dpos until the scene graph updates (the camera node is a
     * child of the center node): report the forced-update position as the actual camera. */
    if (have_fresh) actual=fresh;
    float distance=cached_distance;
    if (have_fresh) {
        float x=actual.x-g_view_anchor.x,y=actual.y-g_view_anchor.y,z=actual.z-g_view_anchor.z;
        distance=sqrtf(x*x+y*y+z*z);
    }
    float written_distance=-1;
    if (have_fresh) {
        float x=fresh.x-g_view_written.x,y=fresh.y-g_view_written.y,z=fresh.z-g_view_written.z;
        written_distance=sqrtf(x*x+y*y+z*z);
    }
    char b[640];
    snprintf(b,sizeof(b),"view_max=%.1f trace_blocks=%u direct=%d zoom=%d target=%.3f applied=%.3f actual_distance=%.3f actual_valid=%d eye=%d blocked=%d collision_known=%d speed_scale=%.3f yaw=%.6f pitch=%.6f world_valid=%d camera_x=%.6f camera_y=%.6f camera_z=%.6f body_yaw=%.6f body_yaw_valid=%d",
        (double)KFP_VIEW_MAX,g_view_trace_blocks,!!g_fp_mode,g_cfg_camera_zoom,g_view.target,g_view.applied,distance,have_actual,fp_view_is_eye(),
        g_view.blocked,g_view.collision_known,g_speed_scale,g_yaw,g_pitch,have_actual&&g_have_t,
        have_actual&&g_have_t?actual.x-g_tx:0,have_actual&&g_have_t?actual.y:0,
        have_actual&&g_have_t?actual.z-g_tz:0,(double)g_face_yaw,g_face_have);
    if (g_view_have_anchor) {
        size_t n=strlen(b);
        snprintf(b+n,sizeof(b)-n," cached_distance=%.3f fresh_valid=%d written_distance=%.3f anchor_x=%.3f anchor_y=%.3f anchor_z=%.3f",
            cached_distance,have_fresh,written_distance,g_view_anchor.x-(g_have_t?g_tx:0),g_view_anchor.y,g_view_anchor.z-(g_have_t?g_tz:0));
    }
    {   /* fp-eye-drift diagnostics */
        size_t n=strlen(b);
        snprintf(b+n,sizeof(b)-n," head_above=%.3f spine_manual=%d spine_pos_fix=%.4f spine_pos_fixes=%u",
            g_head_above,g_spine_manual,g_spine_pos_fix,g_spine_pos_fixes);
    }
    r->append(r,b); return KAH_OK;
}
