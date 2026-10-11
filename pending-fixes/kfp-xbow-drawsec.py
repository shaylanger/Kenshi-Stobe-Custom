#!/usr/bin/env python3
"""KenshiFP: the FP crossbow drawn by the combat adapter keeps its stock/body (Shay 2026-10-10 21:20, 5090 filler rg-05
R16 on kah-fpxbow: only limbs + string + bolt in hand, state RELOADING).
Cause (row XBMESH, fp-xbow-mesh.sh): the manual combat adapter draws a holstered crossbow with
drawWeapon(item, lastSection = "") (kfp_combat_native.inc holstered draw + RAISE draw). With "" the game sets
weaponInHands but leaves the item's mesh on its "back" sheath slot: the worn-item map gets a "hands" entry with no entity
(Item::mesh NULL = the stock) while the back-slot entity stays on the spine; the gun's limbs/string/bolt follow the hand.
The same bug as PT14 (melee mesh left on the hip), fixed then only in the R draw. Fresh loads with the bow already drawn
never hit it; every fp_combat re-arm after a sheathe did (filler rows: one row's cleanup sheathes, the next row's
fp_combat on draws). Not one of the 12 pending patches: same log signature in the 17:27 build (no kfp-two-hand).
Fix: every adapter draw passes the item's own section (Item::inventorySection @0xE8), as the native draw and the R draw
do; one helper (kfp_draw_section) shared by both adapter draw sites.
Usage: kfp-xbow-drawsec.py <KenshiFP tree root | client dir>   (patches client/kfp_combat_native.inc + kfp_viewmodel.inc)"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]); f = root / 'client/kfp_combat_native.inc'
if not f.exists(): f = root / 'kfp_combat_native.inc'
s = f.read_text()
def rep(old, new, n_expect=1):
    global s; n = s.count(old); assert n == n_expect, f"anchor count {n} != {n_expect}: {old[:70]!r}"; s = s.replace(old, new)
rep("""static void combat_rc_hook(void *rc,float dt,const void *a,const void *b) {""",
"""/* XBMESH (kfp-xbow-drawsec): drawWeapon(item, lastSection) needs the item's own sheath section (Item::inventorySection
 * @0xE8, e.g. "back"/"hip"); "" sets weaponInHands but leaves the mesh on the sheath (crossbow without its stock in FP,
 * PT14 for melee). Fills the by-value std::string temp. */
static unsigned g_combat_draw_nosec;
static void kfp_draw_section(void *item,unsigned char *out32,char *sec,size_t secn) {
    sec[0]=0;const unsigned char *ss=(const unsigned char *)((uintptr_t)item+0xE8);
    if (readable((void *)ss,32)) {size_t sl=*(size_t *)(ss+0x10),cap=*(size_t *)(ss+0x18);
        const char *sp=cap>15?(readable(*(void **)ss,1)?*(const char **)ss:NULL):(const char *)ss;
        if (sp && sl<secn && (cap<=15 || readable((void *)sp,sl+1))) {memcpy(sec,sp,sl);sec[sl]=0;}}
    if (!sec[0]) ++g_combat_draw_nosec;
    if (strlen(sec)>15) make_mstr_long(out32,sec); else make_mstr(out32,sec);
}
static void combat_rc_hook(void *rc,float dt,const void *a,const void *b) {""")
rep("""                unsigned char str[32];make_mstr(str,"");
                void *draw=combat_virtual(pc,0x3d8);
                int keep=g_aim_mode;g_aim_mode=0;   /* the draw may sheathe internally */""",
"""                unsigned char str[32];char sec[32];kfp_draw_section(weapon,str,sec,sizeof sec);
                void *draw=combat_virtual(pc,0x3d8);
                int keep=g_aim_mode;g_aim_mode=0;   /* the draw may sheathe internally */""")
rep("""                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;g_aim_mode=1;g_combat_why="drawing";g_combat_draw_cd=1.0f;""",
"""                if (g_combat_draws<8) logline("[combat] crossbow draw section='%s' ok=%d",sec,(int)ok);
                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;g_aim_mode=1;g_combat_why="drawing";g_combat_draw_cd=1.0f;""")
rep("""    if (action&KFP_ACT_RAISE) {
        unsigned char str[32];make_mstr(str,"");""",
"""    if (action&KFP_ACT_RAISE) {
        unsigned char str[32];char sec[32];kfp_draw_section(weapon,str,sec,sizeof sec);""")
# XBHOLD (5090 xbconfirm2, B5CE6AED, 2026-10-11): with XBDRAW gone, B-ready and D-ready (bow drawn by the adapter, aim
# released after the reload) went holstered within 1.2 s: the aim suppressor ends with the aim and the idle AI re-sheathes
# a bow it never drew itself. An adapter draw now takes the R draw's hold (fpc_suppress_sheathe, released by an R holster,
# fp_mode off or going down), so the bow stays out like an R-drawn one.
rep("""static unsigned g_combat_draw_nosec;""",
"""static unsigned g_combat_draw_nosec;
static void *g_fpc_hold_actor;   /* tentative decl; defined in kfp_controls.inc (XBHOLD: the R draw's anti-sheathe hold) */""")
rep("""                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;g_aim_mode=1;g_combat_why="drawing";g_combat_draw_cd=1.0f;""",
"""                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;g_aim_mode=1;g_combat_why="drawing";g_combat_draw_cd=1.0f;g_fpc_hold_actor=pc;""")
rep("""        if (draw && ((char (*)(void *,void *,void *))draw)(pc,weapon,str)) {
            g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */""",
"""        if (draw && ((char (*)(void *,void *,void *))draw)(pc,weapon,str)) {
            g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
            g_fpc_hold_actor=pc;   /* XBHOLD */""")
# (XBDRAW, the adapter's draw deferred to the controls tick with a 1.6 s settle, was tried 2026-10-11 and reverted:
# it did not fix the invisible viewmodel and made the bow sheathe/redraw (262FE675) or stay in hand at ready (8C72A4C4).)
f.write_text(s); print('kfp-xbow-drawsec applied to', f)
# XBPIN (4080 xbpin, 8C72A4C4, 2026-10-11): THE cause of the invisible viewmodel after an adapter draw. The C3 gun pin
# (vm_gun_pin) moves the node above the gun's string entity to the post-IK prop every frame, and it also ran while the
# crossbow was HOLSTERED (g_combat_item_gun is read from the item in or out of hands: adapter armed before the draw, D
# phase / a native sheathe with FP on). Afterwards the string entity hung directly on the body's node (string.parent =
# the node that is the gun node's grandparent when good; its parent has no parent), so the pin wrote the BODY node:
# skeleton<->world map residual ~25/frame, arms + bow off screen. boltpin 0 in that state recovered it (D0 PASS).
# Fix: pin only while the combat weapon is the one in hands, and never a node whose grandparent is a root-level node.
fv = f.parent / 'kfp_viewmodel.inc'; v = fv.read_text()
o1 = """    void *gun = g_combat_item_gun; if (!g_vm_boltpin || !gun) return;
    vm_bolt_syms();"""
assert v.count(o1) == 1, 'pin anchor 1'
v = v.replace(o1, """    void *gun = g_combat_item_gun; if (!g_vm_boltpin || !gun) return;
    {   /* XBPIN: only the crossbow in hands (a holstered bow's nodes are the sheath/body hierarchy) */
        void *wih = g_vm_pc && readable((void *)((uintptr_t)g_vm_pc + CHAR_WEAPON_IN_HANDS), 8) ? *(void **)((uintptr_t)g_vm_pc + CHAR_WEAPON_IN_HANDS) : NULL;
        /* XBPIN2 (xbmesh-v6 review, 7C886329: B/D aim showed a compact, far bow without its bolt = pin skipped):
         * a crossbow in hands is enough (wih == the adapter's weapon OR the FP controls see the ranged weapon drawn) */
        if (!wih || (wih != g_combat_weapon && !g_fpc_ranged)) {
            static void *lw; if (wih && wih != lw) { lw = wih; logline("[vm] XBPIN skip: wih=%p combat_weapon=%p fpc_ranged=%d", wih, g_combat_weapon, g_fpc_ranged); }
            g_vm_pin_mode = 35; return; } }
    vm_bolt_syms();""")
o2 = """    if (!readable(pb, 8)) { g_vm_pin_mode = 33; return; }"""
assert v.count(o2) == 1, 'pin anchor 2'
v = v.replace(o2, o2 + """
    if (!readable(g_vm_node_getparent(pb), 8)) { g_vm_pin_mode = 36; return; }   /* XBPIN: bp would be the body node */""")
o3 = """static void *g_combat_item_gun;              /* tentative decl; defined in kfp_combat_native.inc (crossbow item's GunClass) */"""
assert v.count(o3) == 1, 'pin anchor 3'
v = v.replace(o3, o3 + """
static void *g_combat_weapon;               /* tentative decl; defined in kfp_combat_native.inc (XBPIN) */
static int   g_fpc_ranged;                  /* tentative decl; defined in kfp_controls.inc (XBPIN2) */""")
fv.write_text(v); print('kfp-xbow-drawsec (XBPIN) applied to', fv)
# XBDEXP (xbconfirm3, 468B6D06, 2026-10-11): pin mode 36 = after an R holster (own sheathe) + ADAPTER draw the gun's
# string/slack/bolt nodes hang directly on the character node (string.parent = the node that is the gun node's parent
# after an R draw; the gun node level is missing), so the bow parts sit at the body (compact far bow, no bolt) and the
# C3 pin correctly refuses. R draw after the same holster = mode 1; adapter draw after a native sheathe (fp_mode off,
# phase B) = mode 1. The adapter draw differs from the R draw in: ranged combat mode set before drawWeapon, and
# g_combat_setup(rc,NULL,35) right after it. Test switch `fp_combat drawexp <mask>` (default 0 = unchanged):
# 1 = no setup after the draw (the drawn_no_gun path sets it up >= 1 s later, like after an R draw), 2 = ranged combat
# mode 0 during drawWeapon, 8 = rc state 0 during drawWeapon. Row XBDEXP (fp-xbow-drawexp.sh) compares pin modes.
s = f.read_text()
rep("""static unsigned g_combat_draw_nosec;""", """static unsigned g_combat_draw_nosec;
static int g_combat_drawexp;   /* XBDEXP test switch (fp_combat drawexp) */""")
rep("""                char ok=draw?((char (*)(void *,void *,void *))draw)(pc,weapon,str):0;""",
"""                unsigned char xm0=*(unsigned char *)((uintptr_t)rc+RC_COMBATMODE);int xs0=*(int *)((uintptr_t)rc+RC_STATE_OFF);
                if (g_combat_drawexp&2) *(unsigned char *)((uintptr_t)rc+RC_COMBATMODE)=0;
                if (g_combat_drawexp&8) *(int *)((uintptr_t)rc+RC_STATE_OFF)=0;
                char ok=draw?((char (*)(void *,void *,void *))draw)(pc,weapon,str):0;
                if (g_combat_drawexp&2) *(unsigned char *)((uintptr_t)rc+RC_COMBATMODE)=xm0;
                if (g_combat_drawexp&8) *(int *)((uintptr_t)rc+RC_STATE_OFF)=xs0;
                if (g_combat_drawexp) logline("[combat] XBDEXP draw mask=%d mode0=%d state0=%d ok=%d",g_combat_drawexp,(int)xm0,xs0,(int)ok);""")
rep("""                if (ok) {
                    g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;""",
"""                if (ok) {
                    if (!(g_combat_drawexp&1)) g_combat_setup(rc,NULL,35); /* STAT_CROSSBOWS */
                    ++g_combat_draws;""")
rep("""    if (argc==3 && !_stricmp(argv[1],"autoreload")) {""",
"""    if (argc==3 && !_stricmp(argv[1],"drawexp")) {   /* XBDEXP test switch */
        char b[48];g_combat_drawexp=atoi(argv[2]);snprintf(b,sizeof b,"drawexp=%d",g_combat_drawexp);r->append(r,b);return KAH_OK;
    }
    if (argc==3 && !_stricmp(argv[1],"autoreload")) {""")
f.write_text(s); print('kfp-xbow-drawsec (XBDEXP switch) applied to', f)
# XBDEXP 2 (5090 xbdexp2, 03012F04): masks 1/2/3/9 all still pin=36 after R holster + adapter draw (R draw = 1), so neither
# the setup call nor the combat mode DURING drawWeapon decides it. The R draw also leaves ranged combat mode OFF for the
# whole draw animation (the hand attach happens at an anim event later); the adapter writes mode 1 / state 3 every
# holstered tick. 32 = no mode/state writes while the bow is out of hand or drawing (draw cooldown running).
s = f.read_text()
rep("""            *(unsigned char *)((uintptr_t)rc+RC_COMBATMODE)=1;*(int *)((uintptr_t)rc+RC_STATE_OFF)=3;""",
"""            if (!(g_combat_drawexp&32) || (g_combat_wih && g_combat_draw_cd<=0)) {*(unsigned char *)((uintptr_t)rc+RC_COMBATMODE)=1;*(int *)((uintptr_t)rc+RC_STATE_OFF)=3;}""")
f.write_text(s); print('kfp-xbow-drawsec (XBDEXP 32) applied to', f)
# 64 = the adapter does not draw itself: it asks the FP controls tick for the R draw (fpc_draw_toggle, outside the
# RangedCombat hook, the exact R path); combine with 32 (+1) to mimic an R draw fully.
s = f.read_text()
rep("""static int g_combat_drawexp;   /* XBDEXP test switch (fp_combat drawexp) */""",
"""static int g_combat_drawexp;   /* XBDEXP test switch (fp_combat drawexp) */
static void *g_combat_draw_req;   /* XBDEXP 64: R draw requested from the FP controls tick */""")
rep("""                char ok=draw?((char (*)(void *,void *,void *))draw)(pc,weapon,str):0;""",
"""                char ok=(g_combat_drawexp&64)?(g_combat_draw_req=pc,(char)1):(draw?((char (*)(void *,void *,void *))draw)(pc,weapon,str):0);""")
f.write_text(s)
fc = f.parent / 'kfp_controls.inc'; c = fc.read_text()
o = """        if (edge[FPC_R]) fpc_draw_toggle(pc);   /* PT18: R only draws/holsters, also with RMB held */"""
assert c.count(o) == 1, 'controls anchor'
c = c.replace(o, o + """
        else if (g_combat_draw_req && g_combat_draw_req==pc) {g_combat_draw_req=NULL;logline("[controls] XBDEXP adapter draw via the R draw");fpc_draw_toggle(pc);}""")
o2 = "static void fpc_draw_toggle(void *pc) {"
assert c.count(o2) == 1, 'controls anchor 2'
c = c.replace(o2, "static void *g_combat_draw_req;   /* tentative decl; defined in kfp_combat_native.inc (XBDEXP 64) */" + chr(10) + o2)
fc.write_text(c); print('kfp-xbow-drawsec (XBDEXP 64) applied to', fc)
# XBPIN3 (5090 xbdexp2/3/4, 03012F04/CE098A22: every adapter-draw variant incl. the R draw itself issued while the adapter
# is armed gives pin mode 36; only an R draw with the adapter off rebuilds the gun node): the gun's string/slack/bolt nodes
# hang directly on the character node (no gun node). Their locals are the same constant offsets the game gives them under a
# gun node (drawn/slack at the node origin, the bolt ~6 dm along it), so pin each of them to the post-IK prop as if under a
# virtual gun node at the prop: world = prop * (char scale * learned local); the local is relearned when the game rewrites it
# or the node changes (new bolt each reload). Mode 37 = this flat pin ran (the take check fails 35/36 only).
v = fv.read_text()
o5 = """/* C3 pin: gun node (parent of the bolt + string nodes) = post-IK Prop2 world * rel. Called at the end of vm_apply. */"""
assert v.count(o5) == 1, 'flat anchor'
v = v.replace(o5, """/* XBPIN3: no gun node (parts directly on the character node cn): pin every part node as under a virtual gun node at the prop */
#define VM_FLAT_N 6
static void *g_vm_flat_nd[VM_FLAT_N]; static Vec3 g_vm_flat_rp[VM_FLAT_N], g_vm_flat_lw[VM_FLAT_N]; static Quat g_vm_flat_rq[VM_FLAT_N];
static int g_vm_flat_next; static unsigned g_vm_flat_n, g_vm_flat_learn;
static void vm_gun_pin_flat(void *gun, void *cn, void *prop)
{
    Vec3 wp, Cp, Cs; Quat wq, Cq; void *nds[VM_FLAT_N]; int n = 0; unsigned cnt = 0;
    if (!g_vm_node_getori || !g_get_parent_scenenode) { g_vm_pin_mode = 38; return; }
    if (!vm_prop_ogre_world(prop, &wp, &wq)) { g_vm_pin_mode = 4; return; }
    if (!vm_node_world_u(cn, &Cp, &Cq, &Cs) || Cs.x < 1e-6f) { g_vm_pin_mode = 5; return; }
    for (int s = 0; s < 2; s++) {
        void *o = readable((void *)((uintptr_t)gun + 0x100 + 8 * s), 8) ? *(void **)((uintptr_t)gun + 0x100 + 8 * s) : NULL;
        void *nd = readable(o, 8) ? g_get_parent_scenenode(o) : NULL;
        if (readable(nd, 8) && g_vm_node_getparent(nd) == cn) nds[n++] = nd;
    }
    vm_gun_ammo(gun, 0, &cnt);
    for (int i = 0; i < (int)cnt && i < 4 && n < VM_FLAT_N; i++) {
        void *o = vm_gun_ammo(gun, i, NULL), *nd = o ? g_get_parent_scenenode(o) : NULL; int dup = 0;
        for (int j = 0; j < n; j++) dup |= nds[j] == nd;
        if (!dup && readable(nd, 8) && g_vm_node_getparent(nd) == cn) nds[n++] = nd;
    }
    if (!n) { g_vm_pin_mode = 39; return; }
    for (int j = 0; j < n; j++) {
        void *nd = nds[j]; int k = -1; Vec3 lp0; g_vm_ngpos_v(nd, &lp0);
        for (int i = 0; i < VM_FLAT_N; i++) if (g_vm_flat_nd[i] == nd) k = i;
        if (k < 0 || memcmp(&lp0, &g_vm_flat_lw[k], sizeof(Vec3)) != 0) {   /* new node or the game wrote it: learn its local */
            if (k < 0) { k = g_vm_flat_next; g_vm_flat_next = (g_vm_flat_next + 1) % VM_FLAT_N; g_vm_flat_nd[k] = nd; }
            Quat lq0 = { 1, 0, 0, 0 }; g_vm_node_getori(nd, &lq0);
            g_vm_flat_rp[k] = lp0; g_vm_flat_rq[k] = quat_norm(lq0); g_vm_flat_learn++;
        }
        Vec3 P = vm_add(wp, quat_rotvec(wq, vm_mul(g_vm_flat_rp[k], Cs.x))); Quat Q = quat_norm(quat_mul(wq, g_vm_flat_rq[k]));
        Vec3 lp = vm_mul(quat_rotvec(quat_conj(Cq), vm_sub(P, Cp)), 1.0f / Cs.x); Quat lq = quat_norm(quat_mul(quat_conj(Cq), Q));
        g_node_set_pos(nd, &lp); g_node_set_ori(nd, &lq); g_vm_ngpos_v(nd, &g_vm_flat_lw[k]);
    }
    g_vm_flat_n++; g_vm_pin_mode = 37; g_vm_pin_n++;
}
""" + o5)
o6 = """    if (!readable(g_vm_node_getparent(pb), 8)) { g_vm_pin_mode = 36; return; }   /* XBPIN: bp would be the body node */"""
assert v.count(o6) == 1, 'flat anchor 2'
v = v.replace(o6, """    if (!readable(g_vm_node_getparent(pb), 8)) { if (g_vm_boltpin == 1) vm_gun_pin_flat(gun, bp, prop); else g_vm_pin_mode = 36; return; }   /* XBPIN3: bp = the char node, no gun node */""")
fv.write_text(v); print('kfp-xbow-drawsec (XBPIN3 flat pin) applied to', fv)
