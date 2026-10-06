// Offline x64 v100 test for StobeGoals.cpp (moved from KenshiFP). No game: fake GameWorld,
// stubbed Stobe internals. Build/run: pending-fixes/decouple/run-offline-test.bat
#include "../../src/StobeGoals.cpp"
#include <direct.h>
#include <stdexcept>

static float g_prox = 80.0f;
static int g_interrupts;
float *StobeGoals_ProximityRadius(void) { return &g_prox; }
long StobeGoals_ChatInterrupt(void) { return ++g_interrupts; }

static int g_fail;
#define CHECK(c, what) do { if (c) printf("ok   %s\n", what); else { printf("FAIL %s\n", what); g_fail = 1; } } while (0)

static int file_exists(const char *leaf)
{
    char p[MAX_PATH * 2]; if (!stobe_mod_path(p, sizeof p, leaf)) return 0;
    return GetFileAttributesA(p) != INVALID_FILE_ATTRIBUTES;
}
static void write_file(const char *leaf, const char *text, int age_s)
{
    char p[MAX_PATH * 2]; stobe_mod_path(p, sizeof p, leaf);
    FILE *f = fopen(p, "wb"); fputs(text, f); fclose(f);
    if (age_s) {
        HANDLE h = CreateFileA(p, FILE_WRITE_ATTRIBUTES, 0, NULL, OPEN_EXISTING, 0, NULL);
        FILETIME ft; GetSystemTimeAsFileTime(&ft);
        ULARGE_INTEGER u; u.LowPart = ft.dwLowDateTime; u.HighPart = ft.dwHighDateTime;
        u.QuadPart -= (ULONGLONG)age_s * 10000000ULL;
        ft.dwLowDateTime = u.LowPart; ft.dwHighDateTime = u.HighPart;
        SetFileTime(h, NULL, NULL, &ft); CloseHandle(h);
    }
}
static int log_has(const char *needle)
{
    if (g_log) fflush(g_log);
    char p[MAX_PATH * 2]; stobe_mod_path(p, sizeof p, "stobe_goals.log");
    FILE *f = fopen(p, "rb"); if (!f) return 0;
    static char buf[1 << 16]; size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = 0; fclose(f);
    return strstr(buf, needle) != NULL;
}
static int guarded_null_read(void)
{
    volatile int *p = NULL;
    __try { return *p; } __except (STOBE_SEH_FILTER) { return -1; }
}
static void throw_cpp(void) { throw std::runtime_error("x"); }
static int guarded_cpp_throw(void)
{
    __try { throw_cpp(); return 0; } __except (STOBE_SEH_FILTER) { return -1; }
}

int main(void)
{
    char exe[MAX_PATH]; GetModuleFileNameA(NULL, exe, MAX_PATH);
    *strrchr(exe, '\\') = 0;
    char dir[MAX_PATH * 2]; sprintf(dir, "%s\\mods", exe); _mkdir(dir);
    strcat(dir, "\\Stobe"); _mkdir(dir);
    static unsigned char fake_gw[0x2000]; // zeroed: no player, no world loaded

    char p[MAX_PATH * 2];
    CHECK(stobe_mod_path(p, sizeof p, "x") && strstr(p, "mods\\Stobe\\x"), "stobe_mod_path finds mods\\Stobe");

    write_file("lifelike_interrupt.flag", "combat\n1\n", 0);
    StobeGoals_Tick(fake_gw);
    CHECK(g_interrupts == 1 && !file_exists("lifelike_interrupt.flag"), "fresh lifelike_interrupt.flag -> one chat interrupt, file consumed");
    CHECK(log_has("goal executor running in Stobe.dll"), "stobe_goals.log written with startup line");

    Sleep(150);
    write_file("lifelike_interrupt.flag", "combat\n1\n", 120);
    StobeGoals_Tick(fake_gw);
    CHECK(g_interrupts == 1 && !file_exists("lifelike_interrupt.flag") && log_has("flag stale"), "stale (120 s) interrupt flag dropped without interrupt");

    Sleep(60);
    write_file("stobe_action.request", "123\tbodyguard\t456\t\n", 0);
    StobeGoals_Tick(fake_gw);
    CHECK(!file_exists("stobe_action.request"), "stobe_action.request consumed");
    CHECK(log_has("ACTION_BRIDGE actor not found serial=123 command=BODYGUARD"), "action bridge parsed + upper-cased command, no actor in fake world");

    Sleep(60);
    write_file("unequip_item.request", "77\tIron Helmet\n", 0);
    StobeGoals_Tick(fake_gw);
    CHECK(!file_exists("unequip_item.request"), "unequip_item.request consumed");

    CHECK(stobe_set_voice_range_lock(1) && g_prox == 500.0f, "voice range lock widens Stobe proximity radius to 500");
    CHECK(stobe_set_voice_range_lock(0) && g_prox == 80.0f, "voice range lock restores 80");

    CHECK(StobeFightTruceActive() == 0, "no truce pending");
    stobe_fight_truce_add(42);
    CHECK(StobeFightTruceActive() == 1, "STOP_FIGHT truce visible through export");

    CHECK(guarded_null_read() == -1 && g_seh_code == EXCEPTION_ACCESS_VIOLATION, "SEH guard catches access violation");
    CHECK(guarded_cpp_throw() == -1 && g_seh_code == 0xE06D7363u, "SEH guard catches uncaught C++ throw");

    // goal ticks on a fake (unloaded) world must not write or crash
    write_file("stobe_work_goal.request", "wg-1\t123\tTester\tBread\t2\n", 0);
    for (int i = 0; i < 5; ++i) { StobeGoals_Tick(fake_gw); Sleep(60); }
    CHECK(1, "work/task/label ticks survive an unloaded world");

    // 16-fb: carried Hinge seeded (1 in her pack), the game's job AI holds it (gone), then it comes back
    {
        static WgpGoal tg; memset(&tg, 0, sizeof tg); strcpy(tg.id, "wg-t16");
        WgpSubstate *ss = wgp_substate(&tg, "Hinge");
        CHECK(ss && ss->last_have == -1 && ss->last_inv == -1, "16-fb new substate: last_have/last_inv unknown");
        ss->last_have = 1; ss->last_inv = 1;              // wgp_seed_carried_deps
        wgp_substate_observe(&tg, ss, 0, 0);              // vanished from every counted inventory
        CHECK(ss->consumed == 1 && log_has("wg-t16 Hinge used 1 (consumed=1 queued=0)"), "16-fb vanished carried Hinge counted as used");
        int shortfall = 2 - 0 - ss->queued - ss->consumed;
        CHECK(shortfall == 1, "16-fb 2 Junkbows with 1 carried Hinge: shortfall 1 (queue 1, not 2)");
        ss->queued = 1;                                   // wgp_ensure_item queued the 1
        wgp_substate_observe(&tg, ss, 1, 1);              // the same Hinge back in her pack
        CHECK(ss->consumed == 0 && ss->queued == 1 && ss->last_have == 1 && log_has("wg-t16 Hinge back 1 in her pack"),
              "16-fb returned Hinge cancels consumed, keeps the real queued craft");
        wgp_substate_observe(&tg, ss, 2, 1);              // crafted Hinge appears in the bench
        CHECK(ss->queued == 0 && ss->consumed == 0 && ss->last_have == 2, "16-fb finished craft (bench, not pack) comes off queued");
        wgp_substate_observe(&tg, ss, 1, 0);              // Junkbow craft uses one
        CHECK(ss->consumed == 1 && ss->last_inv == 0, "16-fb use after the return counted again");
    }

    printf(g_fail ? "RESULT stobe-goals-offline FAIL\n" : "RESULT stobe-goals-offline PASS\n");
    return g_fail;
}
