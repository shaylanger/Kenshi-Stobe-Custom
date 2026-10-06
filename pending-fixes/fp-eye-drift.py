#!/usr/bin/env python3
"""fp-eye-drift: stop the FP eye height creeping up while a ranged weapon is aimed.

Root cause: bend_spine() marks spine1/spine2 manuallyControlled and rewrites only
their ORIENTATION each frame. Ogre's OldSkeleton::reset() skips manual bones, but
the animation tracks are still applied to them, and NodeAnimationTrack applies
relatively (node->translate(key.translate)). With no reset, the aim animation's
spine translation key is added again every frame -> the spine (and the head bone
riding on it, which is the FP eye: eyeW.y = head.y - EYE_DROP) climbs while
aimed=1 (dec-5090-4: 665.0 -> 677.8 over 19 shots, flat before the aim). Fix:
pin both bones' local POSITION to the bind position every frame alongside the
orientation write. Diagnostics: fp_camera state gains head_above (head y - feet
y), spine_pos_fix (last per-frame correction length) and spine_pos_fixes.

Usage: python3 fp-eye-drift.py /root/KenshiFP
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/root/KenshiFP")
MARK = "fp-eye-drift"


def patch(path, edits):
    p = root / path
    s = p.read_text()
    if MARK in s:
        print(f"{path}: already patched"); return
    for old, new in edits:
        n = s.count(old)
        assert n == 1, f"{path}: anchor found {n}x: {old[:70]!r}"
        s = s.replace(old, new)
    p.write_text(s)
    print(f"{path}: patched ({len(edits)} edits)")


C = "client/kenshifp_client.c"
patch(C, [
    # A: optional local-position getter (diagnostic)
    ("static oldnode_setpos_t     g_oldnode_setpos;\n",
     "static oldnode_setpos_t     g_oldnode_setpos;\n"
     "typedef const Vec3 *(*oldnode_getpos_t)(void *node);  /* getPosition (LOCAL); fp-eye-drift diag */\n"
     "static oldnode_getpos_t     g_oldnode_getpos;\n"),
    # B: captured rest positions + counters
    ("static Quat g_spine_rest[3];                    /* captured reference pose the aim pivots around */\n",
     "static Quat g_spine_rest[3];                    /* captured reference pose the aim pivots around */\n"
     "/* fp-eye-drift: manual bones are not reset by the animation, but its tracks still\n"
     " * translate() them each frame -> position must be re-pinned every frame too. */\n"
     "static Vec3 g_spine_rest_pos[3]; static int g_spine_rest_pos_ok[3];\n"
     "static float g_spine_pos_fix; static unsigned g_spine_pos_fixes;\n"),
    # C: capture bind position with the rest orientation
    ("            g_spine_rest[i] = readable((void *)lq, 16) ? *lq : (Quat){ 1, 0, 0, 0 };\n",
     "            g_spine_rest[i] = readable((void *)lq, 16) ? *lq : (Quat){ 1, 0, 0, 0 };\n"
     "            {   /* fp-eye-drift: bind position = what the vanilla reset would restore */\n"
     "                const Vec3 *ip = g_oldnode_getinitpos ? g_oldnode_getinitpos(bones[i]) : NULL;\n"
     "                g_spine_rest_pos_ok[i] = readable((void *)ip, 12);\n"
     "                if (g_spine_rest_pos_ok[i]) g_spine_rest_pos[i] = *ip;\n"
     "            }\n"),
    # D: pin position each frame next to the orientation write
    ("        g_oldnode_setori(bones[i], &nq);\n"
     "        g_oldnode_needupd(bones[i], 1);\n"
     "        if (logit)\n"
     "            logline(\"[spine] %s a=",
     "        g_oldnode_setori(bones[i], &nq);\n"
     "        if (g_oldnode_setpos && g_spine_rest_pos_ok[i]) {   /* fp-eye-drift */\n"
     "            const Vec3 *cp = g_oldnode_getpos ? g_oldnode_getpos(bones[i]) : NULL;\n"
     "            if (readable((void *)cp, 12)) {\n"
     "                float dx = cp->x - g_spine_rest_pos[i].x, dy = cp->y - g_spine_rest_pos[i].y,\n"
     "                      dz = cp->z - g_spine_rest_pos[i].z;\n"
     "                float dl = sqrtf(dx*dx + dy*dy + dz*dz);\n"
     "                if (i == 0) g_spine_pos_fix = dl; else if (dl > g_spine_pos_fix) g_spine_pos_fix = dl;\n"
     "                if (dl > 1e-4f) g_spine_pos_fixes++;\n"
     "            }\n"
     "            g_oldnode_setpos(bones[i], &g_spine_rest_pos[i]);\n"
     "        }\n"
     "        g_oldnode_needupd(bones[i], 1);\n"
     "        if (logit)\n"
     "            logline(\"[spine] %s a="),
    # E: resolve the getter
    ("        g_oldnode_setpos     = (oldnode_setpos_t)GetProcAddress(ogre, OGRE_OLDNODE_SETPOS_SYM);\n",
     "        g_oldnode_setpos     = (oldnode_setpos_t)GetProcAddress(ogre, OGRE_OLDNODE_SETPOS_SYM);\n"
     "        g_oldnode_getpos     = (oldnode_getpos_t)GetProcAddress(ogre,   /* fp-eye-drift */\n"
     "                                   \"?getPosition@OldNode@Ogre@@UEBAAEBVVector3@2@XZ\");\n"),
])

V = "client/kfp_view.inc"
patch(V, [
    ("            cached_distance,have_fresh,written_distance,g_view_anchor.x-(g_have_t?g_tx:0),g_view_anchor.y,g_view_anchor.z-(g_have_t?g_tz:0));\n"
     "    }\n",
     "            cached_distance,have_fresh,written_distance,g_view_anchor.x-(g_have_t?g_tx:0),g_view_anchor.y,g_view_anchor.z-(g_have_t?g_tz:0));\n"
     "    }\n"
     "    {   /* fp-eye-drift diagnostics */\n"
     "        size_t n=strlen(b);\n"
     "        snprintf(b+n,sizeof(b)-n,\" head_above=%.3f spine_manual=%d spine_pos_fix=%.4f spine_pos_fixes=%u\",\n"
     "            g_head_above,g_spine_manual,g_spine_pos_fix,g_spine_pos_fixes);\n"
     "    }\n"),
])
