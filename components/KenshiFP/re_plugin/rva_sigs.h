/* Resolution table for the RE_Kenshi (Path B) build -- populates g_rva by
 * runtime scanning instead of the hard-coded T_1068/T_1065 tables, so KenshiFP
 * works on ANY Kenshi build RE_Kenshi runs (Steam versions, GOG, older).
 *
 * Included into kenshifp_client.c under KFP_RE_PLUGIN, AFTER addr_table_t /
 * g_rva / g_base are declared. Three resolution kinds:
 *   R_FUNC  : scan .text for the function's prologue signature -> absolute addr
 *   R_DATA  : scan for a code site referencing the global, follow the rip disp32
 *   R_DELTA : anchor field's address +/- a version-stable byte delta
 * All signatures verified UNIQUE in 1.0.65 and cross-checked vs 1.0.68 (bytes
 * that differ between versions -- rip displacements -- are wildcarded '??').
 * g_rva stores RVAs (absolute - g_base), matching the RVA_X macros' g_base+X. */
#ifndef KFP_RVA_SIGS_H
#define KFP_RVA_SIGS_H
#include "sigscan.h"

/* rip-relative follow: sig matched at `at`; disp32 at at+dispoff; the referenced
 * global = (disp field addr + 4) + disp32. */
static uintptr_t kfp_follow(uintptr_t at, int dispoff)
{
    if (!at) return 0;
    int32_t disp = *(int32_t *)(at + dispoff);
    return at + dispoff + 4 + disp;
}

typedef enum { R_FUNC, R_DATA, R_DELTA } rkind_t;
typedef struct {
    size_t   field;     /* offsetof(addr_table_t, X) */
    rkind_t  kind;
    const char *sig;    /* R_FUNC / R_DATA */
    int      dispoff;   /* R_DATA: byte offset of disp32 within the matched sig */
    size_t   anchor;    /* R_DELTA: offsetof of the anchor field */
    long     delta;     /* R_DELTA: signed byte delta from the anchor */
} rentry_t;

#define AF(x) offsetof(addr_table_t, x)

static const rentry_t KFP_RTAB[] = {
  /* ---- functions (prologue signatures) ---- */
  { AF(MAINLOOP),        R_FUNC, "48 8B C4 56 57 41 54 48 83 EC 70 48 C7 44 24 20 FE FF FF FF 48 89 58 10", 0,0,0 },
  { AF(FOLLOW_OBJECT),   R_FUNC, "8B 42 08 48 83 C1 48 89 41 E8 8B 42 0C 89 41 EC 8B 42 10 89 41 F0 8B 42 14 89 41 F4", 0,0,0 },
  { AF(STOP_FOLLOW),     R_FUNC, "8B 05 ?? ?? 78 01 48 83 C1 48 89 41 E8 8B 05 ?? ?? 78 01 89 41 EC 8B 05 ?? ?? 78 01", 0,0,0 },
  { AF(CHARMOVE_SETDEST),R_FUNC, "40 55 53 56 57 41 54 41 55 41 56 48 8D AC 24 10 FF FF FF 48 81 EC F0 01 00 00 48 C7", 0,0,0 },
  /* Character teleport+facing placement (walk-off fall tier). Unique in 1.0.65
   * (0x5c7a50) / 1.0.68 (0x5c84e0); IAT disp wildcarded. */
  { AF(CHAR_SETDEST),    R_FUNC, "48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 20 48 8B F1 48 83 C1 48 49 8B D8 48 8B FA FF 15 ?? ?? ?? ?? 48 8B 8E 40 06 00 00 48 8B 01 4C 8B C3 48 8B D7 FF 90 C0 00 00 00 48 8B 8E 48 04 00 00", 0,0,0 },
  { AF(CAM_UPDATE),      R_FUNC, "40 55 53 57 48 8B EC 48 81 EC 80 00 00 00 80 B9 BF 00 00 00 00 0F B6 FA 48 8B D9 74", 0,0,0 },
  { AF(NEAREST_TOWN),    R_FUNC, "48 89 5C 24 08 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 40 F3 0F 10 5A 08 F3 0F 10", 0,0,0 },
  { AF(INTERIOR_LOAD),   R_FUNC, "48 89 5C 24 20 55 48 83 EC 20 48 8B 19 48 8B E9 48 85 DB 0F 84 28 01 00 00 48 8B CB", 0,0,0 },
  { AF(GET_BONE_WORLD),  R_FUNC, "48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 30 48 8B 01 49 8B D8 48 8B FA 48 8B F1 FF", 0,0,0 },
  { AF(RANGED_ANIMUPD),  R_FUNC, "48 8B C4 55 57 41 54 41 55 41 56 48 8D 68 A1 48 81 EC 90 00 00 00 48 C7 45 D7 FE FF FF FF 48 89 58 10 48 89", 0,0,0 },
  { AF(GUN_SHOOT),       R_FUNC, "48 8B C4 57 41 54 41 55 48 81 EC B0 00 00 00 48 C7 44 24 40 FE FF FF FF 48 89 58 10", 0,0,0 },
  { AF(FACE_DIR),        R_FUNC, "48 89 5C 24 08 57 48 83 EC 20 48 8B FA 48 8B 15 ?? ?? BE 01 48 8B D9 48 8B CF FF 15", 0,0,0 },
  { AF(GUN_RELOAD),      R_FUNC, "4C 8B DC 57 48 83 EC 60 48 C7 44 24 20 FE FF FF FF 49 89 5B 10 49 89 73 18 48 8B 05 ?? ?? ?? 01 48 33 C4 48 89 44 24 50 48 8B D9 8B", 0,0,0 },
  { AF(SHEATHE),         R_FUNC, "40 53 48 83 EC 60 48 C7 44 24 20 FE FF FF FF 48 8B 05 ?? ?? B4 01 48 33 C4 48 89 44 24 50 48 8B D9 48 C7 44", 0,0,0 },
  { AF(GUN_CREATEPHYS),  R_FUNC, "40 57 48 83 EC 60 48 C7 44 24 20 FE FF FF FF 48 89 5C 24 78 48 89 B4 24 80 00 00 00 48 8B 05 ?? ?? ?? 01 48 33 C4 48 89 44 24 50 48 8B F1 E8 ?? ?? C1 FF 80 BE 60 01 00", 0,0,0 },
  { AF(RC_GETGUN),       R_FUNC, "48 89 5C 24 08 57 48 83 EC 20 48 8B D9 48 8B 49 68 48 8B 01 FF 90 C0 03 00 00 48 8B", 0,0,0 },
  { AF(CAM_MANUAL_SETOZ),R_FUNC, "40 53 48 83 EC 40 0F 10 02 48 8B D9 48 8B 49 58 48 8D 54 24 20 0F 29 74 24 30 0F 28", 0,0,0 },
  { AF(SET_DIRECT_MOVE), R_FUNC, "48 89 5C 24 08 57 48 83 EC 30 48 8B DA BA 02 00 00 00 0F 29 74 24 20 0F 28 F2 48 8B", 0,0,0 },
  /* CharMovement::manualMovement: REAL override (the vtable +0x70 slot is the base-class
   * no-op). pos += v + ground clamp + speed=|v|. Telltale `add rcx,0xC4` (position field)
   * in the prologue; verified unique in 1.0.65 (0x65d370) and 1.0.68 (0x65de00). */
  { AF(MANUAL_MOVE),     R_FUNC, "48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 40 48 8B D9 48 81 C1 C4 00 00 00 48 8B FA", 0,0,0 },
  /* CharMovement path destroy (invalidatePath): frees + nulls the path objects that
   * hijack the mode-0 displacement branch. Unique in 1.0.65 (0x65f3b0) / 1.0.68 (0x65fe40). */
  { AF(INVALIDATE_PATH), R_FUNC, "48 89 5C 24 10 56 48 83 EC 20 48 8B B1 B0 03 00 00 48 8B D9 48 85 F6 0F 84 84 00 00 00", 0,0,0 },
  /* AnimationClass::setPositionAndDirection -- the call that turns the rendered body.
   * Unique in 1.0.65 (0x5b0e60) / 1.0.68 (0x5b18f0). */
  { AF(ANIM_SETPOSDIR),  R_FUNC, "48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 50 F3 0F 10 81 C8 02 00 00 F3 0F 10 52 04 F3 0F 10 5A 08 48 8B D9 49 8B F8 48 8B F2", 0,0,0 },
  /* ground height query incl. building floors/stairs (the manualMovement ground clamp).
   * Unique in 1.0.65 (0x9b3010) / 1.0.68 (0x9b3ee0). */
  { AF(GROUND_AT),       R_FUNC, "48 83 EC 38 45 84 C0 B8 00 82 08 00 41 B9 00 02 00 00 44 0F 45 C8 84 D2 74 04 41 83 C9 04", 0,0,0 },
  /* Character::ragdollQueued(this, bool on, u32 mask) -- the real knockdown API (queues
   * {on,mask} into char+0x3E0; mask 1 = whole body). Unique in 1.0.65 (0x5cb2d0) /
   * 1.0.68 (0x5cbd60); the E8 call disp is wildcarded. */
  { AF(RAGDOLL_QUEUED),  R_FUNC, "45 85 C0 0F 84 13 02 00 00 44 89 44 24 18 53 55 48 83 EC 68 48 8B D9 48 8B 89 48 04 00 00 0F B6 EA 48 8D 94 24 90 00 00 00 E8 ?? ?? ?? ?? 40 3A E8 75 38", 0,0,0 },
  /* Character::stopRagdoll(this, bool immediate): {off, 0x8000=all}. Unique in
   * 1.0.65 (0x5d2290) / 1.0.68 (0x5d2d20). */
  { AF(STOP_RAGDOLL),    R_FUNC, "48 89 5C 24 10 48 89 74 24 18 57 48 83 EC 20 48 8B F9 48 81 C1 E0 03 00 00 0F B6 DA E8 ?? ?? ?? ?? C6 44 24 30 00 C7 44 24 34 00 80 00 00 48 8D 54 24 30 84 DB", 0,0,0 },
  /* CharMovement::createMover: rebuilds the +0x320 physics mover after a ragdoll.
   * Unique in 1.0.65 (0x661500) / 1.0.68 (0x661f90). */
  { AF(CREATE_MOVER),    R_FUNC, "48 8B C4 55 57 41 54 41 55 41 56 48 8D 68 A1 48 81 EC E0 00 00 00 48 C7 45 97 FE FF FF FF 48 89 58 10 48 89 70 18 0F 29 70 C8 0F 29 78 B8 44 0F 29 48 A8", 0,0,0 },
  /* Character::setUnconscious(this, bool): the 0x800 KO ragdoll enter/exit. Unique in
   * 1.0.65 (0x5cdf30) / 1.0.68 (0x5ce9c0). */
  { AF(SET_UNCON),       R_FUNC, "48 8B C4 53 56 57 48 83 EC 60 48 8B D9 84 D2 0F 84 7E 02 00 00 48 8B 89 48 04 00 00 48 8D 50 10 C7 40 10 00 08 00 00 E8 ?? ?? ?? ?? 3C 01 75 2F", 0,0,0 },
  { AF(CHARMOVE_UPDATE), R_FUNC, "48 8B C4 55 56 57 41 54 41 55 41 56 41 57 48 8D A8 58 FE FF FF 48 81 EC 70 02 00 00", 0,0,0 },
  /* CharStats::xpRunning(time,speed) -- athletics+strength XP tick; distinctive
   * prologue: mov this; save xmm6/7; movaps xmm6,xmm1; movaps xmm7,xmm2; call
   * [rax+0x58]; cmp [rax+0x250],0. */
  { AF(XP_RUNNING), R_FUNC, "40 53 48 83 EC 40 48 8B D9 48 8B 49 10 0F 29 74 24 30 48 8B 01 0F 29 7C 24 20 0F 28 F1 0F 28 FA FF 50 58 48 83 B8 50 02 00 00 00 74 76 48 8B 4B 10", 0,0,0 },
  /* setPause(GameWorld*, char): stashes/restores frameSpeedMult(+0x700) through a
   * saved-speed global (decomp-verified). Swallows the vanilla spacebar pause under
   * the FP jump. Sig = 26-byte masked prologue, unique in Steam 1.0.68 AND 1.0.65. */
  { AF(SET_PAUSE), R_FUNC, "48 89 5C 24 10 48 89 6C 24 18 48 89 74 24 20 57 48 83 EC 30 8B 05 ?? ?? ?? ?? 0F 29 74 24 20", 0,0,0 },
  /* MainListener::keyPressed (OIS KeyListener sub-vtable +0x20 slot 1; keycode at
   * evt+0x10). Hooked to swallow the FP jump key's keydown before command dispatch
   * (kills the vanilla space-pause + its sound). Unique 34B in Steam 1.0.68/1.0.65. */
  { AF(KEYPRESSED), R_FUNC, "40 56 57 41 54 48 83 EC 40 48 C7 44 24 28 FE FF FF FF 48 89 5C 24 70 48 89 6C 24 78 48 8B 05 ?? ?? ?? ??", 0,0,0 },
  /* General ray query (GROUND_AT's inner fn): raycast(out, origin, dir, mask) --
   * hit point out, GROUND_NOHIT sentinel on miss. Basis of arc wall collision. */
  { AF(RAYCAST), R_FUNC, "48 8B C4 48 89 58 08 57 48 81 EC E0 00 00 00 F3 0F 10 02 F3 0F 10 4A 04 F3 0F 10 52 08 0F 29 70", 0,0,0 },
  /* InputHandler::keyDownEvent(this, int key) -- the only producer of the command queue
   * (toggle_fps_camera etc.). Hooked so FP-bound keys never reach vanilla commands (CS05).
   * 48B prologue (shift/ctrl DIK tests, +0xD9/+0xD8 writes), unique in 1.0.68 (0x360b30)
   * and 1.0.65 (0x360ad0). */
  { AF(IH_KEYDOWN), R_FUNC, "40 53 48 83 EC 30 44 8B C2 48 8B D9 83 FA 2A 74 05 83 FA 36 75 07 C6 81 D9 00 00 00 01 83 FA 1D 74 08 81 FA 9D 00 00 00 75 07 C6 81 D8 00 00 00", 0,0,0 },
  /* ScreenLabel::update -- per-frame world->screen projector for the floating status
   * texts ("Pick failed", "Pick success!", "*Thunk*", ...). Hooked to pin the FP
   * character's own statuses at the crosshair. Unique in 1.0.65 (0x6ea250) / 1.0.68
   * (0x6ea9f0); the stack-cookie rip disp is wildcarded -> GOG-safe. Telltale tail:
   * cmp byte [rcx+0x18],0 (the textChanged flag). */
  { AF(SLABEL_UPDATE), R_FUNC, "48 8B C4 55 48 8D 68 D8 48 81 EC 20 01 00 00 48 C7 44 24 78 FE FF FF FF 48 89 58 10 48 89 70 18 48 89 78 20 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 45 10 48 8B F9 80 79 18 00", 0,0,0 },
  /* FloatingProgressBar::update -- the lockpicking/job % bar layout. Byte-identical
   * prologue in 1.0.65 (0x6e8020) / 1.0.68 (0x6e87c0), no rip disps in the first 40
   * bytes. Telltales: cmp [rcx+0x18],0 / cmp qword [rcx+0x50],0 (lazy widget) /
   * mov ecx,0xB0 (widget wrapper operator new size). */
  { AF(PBAR_UPDATE), R_FUNC, "40 57 48 83 EC 30 48 C7 44 24 20 FE FF FF FF 48 89 5C 24 58 48 8B D9 80 79 18 00 74 35 48 83 79 50 00 75 21 B9 B0 00 00 00", 0,0,0 },

  /* GUI panel getVisible thunks (mov rcx,[rcx+X]; jmp [rip->getVisible]).
   * Near-identical prologues; disambiguated by trailing next-function bytes.
   * All rip displacements wildcarded -> GOG-safe. Drive cursor-release +
   * the map/overview stand-down. */
  { AF(DLG_GETVIS), R_FUNC, "48 8B 49 38 48 FF 25 ?? ?? ?? ?? CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 8B 49 38 48 8B 01 48 FF 60 18 CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 8B 81 00 01 00 00 8B", 0,0,0 },
  { AF(ESC_GETVIS), R_FUNC, "48 8B 49 08 48 FF 25 ?? ?? ?? ?? CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 40 53 48 83 EC 50 48 C7", 0,0,0 },
  { AF(OVW_GETVIS), R_FUNC, "48 8B 49 08 48 FF 25 ?? ?? ?? ?? CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 8B 89 D0 02 00 00 48", 0,0,0 },
  { AF(OPT_GETVIS), R_FUNC, "48 8B 49 38 48 FF 25 ?? ?? ?? ?? CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 83 EC 28 48 83 B9 18", 0,0,0 },
  { AF(PRO_GETVIS), R_FUNC, "48 8B 49 08 48 FF 25 ?? ?? ?? ?? CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC CC 48 8B 09 48 FF", 0,0,0 },

  /* ---- data globals (ref-follow) ---- */
  { AF(CAM_INSTANCE), R_DATA, "08 57 48 83 EC 60 48 8B 0D ?? ?? ?? ?? 48 8D 54 24 20 48 8B 49 70 FF 15 C8 63", 9,0,0 },
  { AF(SCENE_CTX),    R_DATA, "48 8B FA 48 8B E9 48 8B 05 ?? ?? ?? ?? 48 8B 48 60 48 8B 01 45 33 C0 FF 90 B0", 9,0,0 },
  { AF(TERRAIN_PTR),  R_DATA, "10 1D B5 B0 D4 01 48 8B 0D ?? ?? ?? ?? F3 0F 59 1D 16 77 29 01 0F 28 D1 F3 0F", 9,0,0 },
  { AF(GUI_STATS_BEG),R_DATA, "81 01 48 39 05 ?? ?? ?? ?? 75 37 48 8B 0D 8E C4 81 01 48", 5,0,0 },
  { AF(GUI_DLGWND),   R_DATA, "48 85 DB 74 12 48 8B 0D ?? ?? ?? ?? 45 33 C0 48 8B D3 E8 E1 C2 9A FF", 8,0,0 },
  { AF(ESCMENU_PTR),  R_DATA, "43 CB 01 EB 07 48 8B 05 ?? ?? ?? ?? 48 83 C4 38 C3 CC CC CC CC CC CC", 8,0,0 },
  { AF(OVERVIEW_PTR), R_DATA, "20 FE FF FF FF 48 8B 05 ?? ?? ?? ?? 48 85 C0 75 24 B9 D8 02 00 00 E8 B7 E9 C3 00", 8,0,0 },
  { AF(OPTIONS_PTR),  R_DATA, "FA D3 01 EB 07 48 8B 05 ?? ?? ?? ?? 48 C7 80 F8 00 00 00 00 00 00 00", 8,0,0 },
  { AF(PROSPECT_PTR), R_DATA, "56 DF 01 EB 07 48 8B 05 ?? ?? ?? ?? 48 83 C4 38 C3 CC CC CC CC CC CC", 8,0,0 },
  { AF(SAVELOAD_PTR), R_DATA, "8F DB 01 EB 07 48 8B 05 ?? ?? ?? ?? 48 8D 55 B0 48 8B C8 E8 D8 C3 CA", 8,0,0 },
  { AF(MSGBOX_COUNT), R_DATA, "CC CC CC CC CC 44 8B 05 ?? ?? ?? ?? 33 C9 45 85 C0 74 29 48 8B 15 63", 8,0,0 },
  { AF(PLAYER_IFACE), R_DATA, "E8 93 CB DE 00 48 8B 05 ?? ?? ?? ?? 48 83 B8 98 02 00 00 00 74 0A C7", 8,0,0 },
  { AF(CTXMENU_VISIBLE),R_DATA,"75 09 40 38 3D ?? ?? ?? ?? 74 07 66 89 BE F3 02 00 00 4C", 5,0,0 },
  { AF(TOWNMGR_PTR),  R_DATA, "E8 35 A8 E1 00 4C 8B 25 ?? ?? ?? ?? 41 83 7C 24 58 00 0F 85 A8 00 00", 8,0,0 },
  /* GROUND_NOHIT float sentinel: loaded in the prologue of the inner groundAt raycast
   * (movss xmm6,[rip]). Unique in 1.0.65 (site 0x9b2420 -> 0x168ada0) / 1.0.68
   * (site 0x9b32f0 -> 0x168bda0). */
  { AF(GROUND_NOHIT), R_DATA, "48 81 EC 88 00 00 00 0F 29 74 24 70 F3 0F 10 35 ?? ?? ?? ?? 0F 29 7C 24 60 44 0F 29 44 24 50 0F 28 F9 44 0F 28 C0 4D 85 C0", 16,0,0 },
  { AF(INPUT_CONTROLENABLED), R_DATA, "75 2C 44 38 35 ?? ?? ?? ?? 74 15 84 DB 75 11 48 8D 15 20", 5,0,0 },

  /* ---- anchor+delta (no direct rip-ref; version-stable offset from anchor) ---- */
  { AF(GUI_INV_COUNT), R_DELTA, 0,0, AF(GUI_STATS_BEG), -0x108 },
  { AF(GUI_STATS_END), R_DELTA, 0,0, AF(GUI_STATS_BEG),  0x008 },
  { AF(GUI_WINSTACK),  R_DELTA, 0,0, AF(GUI_STATS_BEG),  0x048 },

  /* NOTE: DLG/ESC/OVW/OPT/PRO_GETVIS (tiny near-identical jmp thunks) and a few
   * unused fields (INPUT_MWHEEL, SAVELOAD used only for cursor release) resolve
   * later; left 0 -> their features degrade gracefully. */
};

/* Populate g_rva by resolution. Returns the count of fields resolved; logs each
 * failure. MUST run before any hook install (a hook's jmp overwrites the very
 * prologue bytes a later scan would match). */
static int kfp_resolve_all(uintptr_t base)
{
    unsigned char *tbl = (unsigned char *)&g_rva;
    int ok = 0, n = (int)(sizeof(KFP_RTAB) / sizeof(KFP_RTAB[0]));
    for (int i = 0; i < n; i++) {
        const rentry_t *e = &KFP_RTAB[i];
        uintptr_t addr = 0;
        if (e->kind == R_FUNC) {
            addr = kfp_sig(e->sig);
        } else if (e->kind == R_DATA) {
            uintptr_t at = kfp_sig(e->sig);
            addr = kfp_follow(at, e->dispoff);
        } else { /* R_DELTA */
            uintptr_t anchor_rva = *(uintptr_t *)(tbl + e->anchor);
            if (anchor_rva) addr = base + anchor_rva + e->delta;
        }
        if (addr) { *(uintptr_t *)(tbl + e->field) = addr - base; ok++; }
    }
    return ok;
}


/* Fill ONLY the fields a recognised static table left at 0. Verified per-build
 * tables stay authoritative; this closes gaps like the GOG tables' SET_PAUSE /
 * KEYPRESSED / RAYCAST (transplanted from a GOG exe we do not have on hand),
 * so GOG users get the same features as Steam instead of silent degradation.
 * A signature that does not match leaves the field 0 = exactly the previous
 * behaviour, and every guard around these fields already tests for 0. */
static int kfp_resolve_missing(uintptr_t base)
{
    unsigned char *tbl = (unsigned char *)&g_rva;
    int filled = 0, n = (int)(sizeof(KFP_RTAB) / sizeof(KFP_RTAB[0]));
    for (int i = 0; i < n; i++) {
        const rentry_t *e = &KFP_RTAB[i];
        if (*(uintptr_t *)(tbl + e->field)) continue;      /* table value wins */
        uintptr_t addr = 0;
        if (e->kind == R_FUNC) {
            addr = kfp_sig(e->sig);
        } else if (e->kind == R_DATA) {
            addr = kfp_follow(kfp_sig(e->sig), e->dispoff);
        } else {
            uintptr_t anchor_rva = *(uintptr_t *)(tbl + e->anchor);
            if (anchor_rva) addr = base + anchor_rva + e->delta;
        }
        if (addr) { *(uintptr_t *)(tbl + e->field) = addr - base; filled++; }
    }
    /* caller logs: this header is included before logline is declared */
    return filled;
}

#endif
