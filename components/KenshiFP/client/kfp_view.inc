/* Camera zoom keeps direct-control ownership; native+visual static collision.
 * Floating-origin calibration uses the pre-offset anchor, never the orbit eye. */
static Vec3 g_view_anchor, g_view_written;
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
    if (argc==3 && !_stricmp(argv[1],"distance")) {
        char *end; errno=0; float d=strtof(argv[2],&end);
        if (errno || end==argv[2] || *end || !isfinite(d) || d<0 || d>KFP_VIEW_MAX) {
            r->append(r,"distance must be finite 0..12"); return KAH_ERROR;
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
    if (argc!=2 || _stricmp(argv[1],"state")) {
        r->append(r,"usage: fp_camera state|distance <0..12>|wheel <-2400..2400>"); return KAH_ERROR;
    }
    Vec3 actual; int have_actual=0;
    if (g_fp_mode && g_have_eye && g_fp_control_actor && g_ogre_ready && g_node_get_dpos && g_view_have_anchor) {
        void *cam=readable((void *)(g_base+RVA_CAM_INSTANCE),8)?*(void **)(g_base+RVA_CAM_INSTANCE):NULL;
        void *node=readable(cam,CC_NODE+8)?*(void **)((uintptr_t)cam+CC_NODE):NULL;
        if (readable(node,8)) {
            if (setjmp(g_guard_jb)) { g_guard_armed=0; r->append(r,"camera read fault"); return KAH_ERROR; }
            guard_arm();
            const Vec3 *p=g_node_get_dpos(node,&actual);
            if (readable((void *)p,sizeof(actual))) { actual=*p; have_actual=1; }
            g_guard_armed=0;
        }
    }
    float distance=-1;
    if (have_actual) {
        float x=actual.x-g_view_anchor.x,y=actual.y-g_view_anchor.y,z=actual.z-g_view_anchor.z;
        distance=sqrtf(x*x+y*y+z*z);
    }
    char b[240];
    snprintf(b,sizeof(b),"direct=%d zoom=%d target=%.3f applied=%.3f actual_distance=%.3f actual_valid=%d eye=%d blocked=%d collision_known=%d speed_scale=%.3f",
        !!g_fp_mode,g_cfg_camera_zoom,g_view.target,g_view.applied,distance,have_actual,fp_view_is_eye(),
        g_view.blocked,g_view.collision_known,g_speed_scale);
    r->append(r,b); return KAH_OK;
}
