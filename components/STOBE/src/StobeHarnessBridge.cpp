// Stobe's test commands through the Kenshi Automation Harness (TEST ONLY).
//
// The harness (AutomationHarness.dll, its own RE_Kenshi mod) owns the test
// inbox, load/save, spawning and the other general commands. Stobe adds its
// chat commands as stobe_ping, stobe_mode, stobe_say, stobe_state,
// stobe_give_cats and stobe_give_item: the harness hands them over
// (KAH_PENDING), they are queued here and run from Stobe's player update
// hook, the same place the old test_inbox.txt was read, then answered with
// KAH_Complete. Before the harness gives an "attack" order, Stobe lifts its
// faction truce so the order sticks (as the old built-in harness did).
#include "StobeHarnessBridge.h"

#include "KenshiAutomationHarness.h"

#include <windows.h>

#include "Functions.h" // BreakFactionCeasefireForExplicitAttack
#include "Utils.h"     // Log

namespace Stobe {
namespace HarnessBridge {
namespace {

const char *const kCommands[][2] = {
    {"ping", "stobe_ping"},
    {"mode", "stobe_mode <mode>"},
    {"say", "stobe_say <target|@nearest|@selected> <text>"},
    {"state", "stobe_state <target>"},
    {"give_cats", "stobe_give_cats <1..1000000>"},
    {"give_item", "stobe_give_item <name> [count]"},
    {"shopprice", "stobe_shopprice <trader> [player]"},
    {"npcinfo", "stobe_npcinfo <open <target> [speaker]|chat|read|refresh|close> (read: key gen loaded portrait tex bio_state text)"}, // NPC info panel
    {"drawn", "stobe_drawn <status|draw <char>|sheathe <char>|hold <char> on|off|reset|set <key> <value>|pair <npc>>"}, // drawn-weapon reactions
};

KAH_Api g_kah;
bool g_connected = false;
DWORD g_lastTry = 0;

CRITICAL_SECTION g_queueLock;
struct QueueLockInit {
  QueueLockInit() { InitializeCriticalSection(&g_queueLock); }
} g_queueLockInit;
std::vector<std::vector<std::string> > g_queue;

int QueueCommand(const char *id, int argc, const char *const *argv, KAH_Reply *,
                 void *user) {
  std::vector<std::string> f;
  f.push_back(id ? id : "");
  f.push_back(static_cast<const char *>(user)); // the command without "stobe_"
  for (int i = 1; i < argc; ++i)
    f.push_back(argv[i] ? argv[i] : "");
  EnterCriticalSection(&g_queueLock);
  g_queue.push_back(f);
  LeaveCriticalSection(&g_queueLock);
  return KAH_PENDING;
}

void BeforeAttack(void *attacker, void *target, void *) {
  BreakFactionCeasefireForExplicitAttack(static_cast<Character *>(attacker),
                                         static_cast<Character *>(target),
                                         "test_attack_order");
  // Item 97: the harness `attack` acts like a player click: it ends the pair's personal truce too
  BreakPersonalTruceForExplicitAttack(static_cast<Character *>(attacker),
                                      static_cast<Character *>(target),
                                      "test_attack_order");
}

} // namespace

void Connect() {
  if (g_connected)
    return;
  g_lastTry = GetTickCount();
  if (!KAH_Connect(&g_kah))
    return;
  g_connected = true;
  int registered = 0;
  for (size_t i = 0; i < sizeof(kCommands) / sizeof(kCommands[0]); ++i)
    registered += g_kah.registerCommand(
        (std::string("stobe_") + kCommands[i][0]).c_str(), kCommands[i][1],
        &QueueCommand, (void *)kCommands[i][0]);
  g_kah.registerBeforeAttack(&BeforeAttack, nullptr);
  g_kah.log("Stobe: test commands registered");
  Log("TEST_HARNESS: connected to the automation harness, " +
      std::string(registered == 9 ? "9 commands" : "SOME COMMANDS REFUSED") +
      " (stobe_ping/mode/say/state/give_cats/give_item/shopprice/npcinfo/drawn)");
}

void Drain(GameWorld *world, Character *sel, RunFn run) {
  if (!g_connected) {
    if (GetTickCount() - g_lastTry >= 1000)
      Connect();
    return;
  }
  std::vector<std::vector<std::string> > batch;
  EnterCriticalSection(&g_queueLock);
  batch.swap(g_queue);
  LeaveCriticalSection(&g_queueLock);
  for (size_t i = 0; i < batch.size(); ++i) {
    bool ok = false;
    std::string detail;
    try {
      detail = run(world, sel, batch[i], ok);
    } catch (...) {
      ok = false;
      detail = "exception";
    }
    g_kah.complete(batch[i][0].c_str(), ok ? KAH_OK : KAH_ERROR, detail.c_str());
    if (!ok)
      Log("TEST_INBOX: error id=" + batch[i][0] + " " + detail);
  }
}

} // namespace HarnessBridge
} // namespace Stobe
