/* prelude.h -- stubs that let KenshiFP's kfp_viewmodel.inc compile and run offline (Linux gcc, no game).
 * Game/Ogre access goes through the same function pointers the plugin resolves at runtime; here they point at
 * the fake skeleton in kfpvm_replay.c. Windows timing is a virtual clock the replay advances by the recorded dt. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>

typedef void *HMODULE; typedef unsigned long DWORD;
typedef union { long long QuadPart; } LARGE_INTEGER;
static double g_al_clock;   /* virtual seconds */
static int QueryPerformanceCounter(LARGE_INTEGER *x) { x->QuadPart = (long long)(g_al_clock * 1e7 + 0.5); return 1; }
static int QueryPerformanceFrequency(LARGE_INTEGER *x) { x->QuadPart = 10000000; return 1; }
static void Sleep(DWORD ms) { (void)ms; }
static void *GetProcAddress(HMODULE m, const char *s) { (void)m; (void)s; return NULL; }
static HMODULE GetModuleHandleA(const char *s) { (void)s; return NULL; }

typedef struct KAH_Reply { void *impl; void (*append)(struct KAH_Reply *reply, const char *text); } KAH_Reply;
#define KAH_ERROR 0
#define KAH_OK 1

typedef struct { float x, y, z; } Vec3;
typedef struct { float w, x, y, z; } Quat;   /* Ogre::Quaternion order */
#include "kfp_view.h"

#define CHAR_ANIM            0x448
#define CHAR_WEAPON_IN_HANDS 0x6D8
#define ANIM_SKELETON        0xB8

/* Ogre / game entry points (same typedefs as kenshifp_client.c) */
typedef Vec3 *(*get_bone_world_t)(void *character, Vec3 *ret, const void *name);
typedef void *(*skel_getbone_t)(void *skel, const void *name);
typedef const Quat *(*oldnode_getdori_t)(void *node);
typedef const Vec3 *(*oldnode_getdpos_t)(void *node);
typedef const Quat *(*oldnode_getori_t)(void *node);
typedef void (*oldnode_setori_t)(void *node, const Quat *q);
typedef void (*oldnode_needupd_t)(void *node, char force);
typedef void *(*oldnode_getparent_t)(void *node);
typedef void (*oldnode_setpos_t)(void *node, const Vec3 *p);
typedef const Vec3 *(*oldnode_getpos_t)(void *node);
typedef const Vec3 *(*oldnode_getdscale_t)(void *node);
static get_bone_world_t g_get_bone_world; static skel_getbone_t g_skel_getbone;
static oldnode_getdori_t g_oldnode_getdori; static oldnode_getdpos_t g_oldnode_getdpos; static oldnode_getori_t g_oldnode_getori;
static oldnode_setori_t g_oldnode_setori; static oldnode_needupd_t g_oldnode_needupd; static oldnode_getparent_t g_oldnode_getparent;
static oldnode_setpos_t g_oldnode_setpos; static oldnode_getpos_t g_oldnode_getpos; static oldnode_getdscale_t g_oldnode_getdscale;

/* game state the viewmodel reads (set per frame by the replay) */
static float g_yaw, g_pitch, g_tx, g_tz;
static KfpView g_view; static int g_view_have_anchor; static Vec3 g_view_anchor, g_last_eye;
static int g_fp_mode = 1, g_have_eye = 1, g_fpc_holster_pending; static float g_fpc_holster_prog;
static jmp_buf g_guard_jb; static int g_guard_armed; static DWORD g_guard_tid;
static void guard_arm(void) { g_guard_armed = 1; }
static int readable(const void *p, size_t n) { (void)n; return p != NULL; }
static int g_al_quiet;
static void logline(const char *fmt, ...) { if (g_al_quiet) return; va_list a; va_start(a, fmt); fputs("log: ", stderr); vfprintf(stderr, fmt, a); fputc('\n', stderr); va_end(a); }
static void make_mstr(unsigned char *b32, const char *s) { memset(b32, 0, 32); strncpy((char *)b32, s, 31); }
static void *make_mstr_long(unsigned char *b32, const char *s) { make_mstr(b32, s); return b32; }
static int install_hook(void *t, void *d, void **o) { (void)t; (void)d; (void)o; return 1; }
static int char_position(void *c, Vec3 *out);
