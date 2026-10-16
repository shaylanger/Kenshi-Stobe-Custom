// imm26 10-f option A. See StobeDurableItem.h.
#define _CRT_RAND_S
#include <stdlib.h>
#include "StobeDurableItem.h"

#include "Utils.h"

#include <core/Functions.h>
#include <kenshi/GameData.h>
#include <kenshi/Item.h>
#include <kenshi/util/hand.h>

#include <map>
#include <string>

namespace Stobe {
namespace DurableItem {
namespace {

const char *kField = "StobeDurableItemId";
const size_t kMaxEntries = 8192;

struct Entry {
  std::string id;
  std::string prototype; // GameData stringID; a handle reused by another prototype drops the binding
};

CRITICAL_SECTION g_lock;
bool g_lockInit = false;
std::map<std::string, Entry> g_byHandle; // full handle string -> id
LONG g_counter = 0;

typedef GameData *(*SerialiseFn)(Item *, GameDataContainer *, GameData *);
typedef void (*LoadFn)(Item *, GameDataContainer *, GameData *);
SerialiseFn g_serialiseOrig = 0;
LoadFn g_loadOrig = 0;

struct Lock {
  Lock() { if (g_lockInit) EnterCriticalSection(&g_lock); }
  ~Lock() { if (g_lockInit) LeaveCriticalSection(&g_lock); }
};

std::string HandleKey(Item *item) {
  if (!item) return "";
  try { return item->getHandle().toString(); } catch (...) { return ""; }
}

std::string PrototypeOf(Item *item) {
  try {
    GameData *d = item ? item->getGameData() : 0;
    if (!d || (uintptr_t)d < 0x1000) return "";
    return d->stringID;
  } catch (...) { return ""; }
}

std::string Hex8(unsigned int v) {
  static const char *digits = "0123456789abcdef";
  std::string s(8, '0');
  for (int i = 7; i >= 0; --i) { s[i] = digits[v & 0xF]; v >>= 4; }
  return s;
}

std::string NewId() {
  unsigned int a = 0, b = 0;
  if (rand_s(&a) != 0 || rand_s(&b) != 0) { // OS random failed: time + counter still differ per call
    LARGE_INTEGER q; QueryPerformanceCounter(&q);
    a = (unsigned int)q.LowPart ^ (unsigned int)GetTickCount();
    b = (unsigned int)q.HighPart ^ (unsigned int)GetCurrentProcessId();
  }
  b ^= (unsigned int)InterlockedIncrement(&g_counter) * 2654435761u;
  return "sdi1-" + Hex8(a) + Hex8(b);
}

GameData *HookSerialise(Item *item, GameDataContainer *container, GameData *refs) {
  GameData *state = 0;
  try {
    state = g_serialiseOrig ? g_serialiseOrig(item, container, refs) : 0;
  } catch (...) {
    Log("DURABLE_ITEM: exception in Item::serialiseInInventory original");
    return state;
  }
  if (!item || !state) return state;
  try {
    const std::string id = IdOf(item);
    if (!id.empty()) {
      state->sdata[kField] = id;
      state->activeValues[kField] = true;
    }
  } catch (...) {
    Log("DURABLE_ITEM: exception writing id");
  }
  return state;
}

void HookLoad(Item *item, GameDataContainer *container, GameData *state) {
  std::string id;
  try {
    if (state) {
      auto it = state->sdata.find(kField);
      if (it != state->sdata.end()) id = it->second;
    }
  } catch (...) {}
  try {
    if (g_loadOrig) g_loadOrig(item, container, state);
  } catch (...) {
    Log("DURABLE_ITEM: exception in Item::loadFromSerialiseInInventory original");
    return;
  }
  if (!item) return;
  try {
    const std::string key = HandleKey(item);
    if (key.empty()) return;
    Lock lock;
    if (id.empty() || id.compare(0, 5, "sdi1-") != 0 || id.size() != 21) {
      g_byHandle.erase(key);
      return;
    }
    if (g_byHandle.size() >= kMaxEntries && !g_byHandle.count(key)) return;
    Entry e;
    e.id = id;
    e.prototype = PrototypeOf(item);
    g_byHandle[key] = e;
    Log("DURABLE_ITEM: restored id=" + id + " handle=" + key + " proto=" + e.prototype);
  } catch (...) {
    Log("DURABLE_ITEM: exception restoring id");
  }
}

bool HookOne(HMODULE lib, const char *symbol, void *detour, void **orig) {
  void *thunk = (void *)GetProcAddress(lib, symbol);
  if (!thunk) { Log(std::string("DURABLE_ITEM: symbol not found ") + symbol); return false; }
  intptr_t real = KenshiLib::GetRealAddress(thunk);
  if (!real) { Log(std::string("DURABLE_ITEM: no real address ") + symbol); return false; }
  const bool ok = KenshiLib::AddHook((void *)real, detour, orig) == KenshiLib::SUCCESS && *orig;
  Log(std::string("DURABLE_ITEM: ") + (ok ? "hooked " : "hook failed ") + symbol);
  return ok;
}

} // namespace

void Install(HMODULE lib) {
  if (!g_lockInit) { InitializeCriticalSection(&g_lock); g_lockInit = true; }
  if (!lib) { Log("DURABLE_ITEM: KenshiLib not loaded"); return; }
  const bool a = HookOne(lib, "?serialiseInInventory@Item@@UEAAPEAVGameData@@PEAVGameDataContainer@@PEAV2@@Z",
                         (void *)HookSerialise, (void **)&g_serialiseOrig);
  const bool b = HookOne(lib, "?loadFromSerialiseInInventory@Item@@UEAAXPEAVGameDataContainer@@PEAVGameData@@@Z",
                         (void *)HookLoad, (void **)&g_loadOrig);
  Log(std::string("DURABLE_ITEM: install serialise=") + (a ? "1" : "0") + " load=" + (b ? "1" : "0"));
}

void Reset() {
  Lock lock;
  g_byHandle.clear();
}

std::string IdOf(Item *item) {
  { Lock lock; if (g_byHandle.empty()) return ""; } // cheap exit: a save serialises thousands of items
  const std::string key = HandleKey(item);
  if (key.empty()) return "";
  const std::string proto = PrototypeOf(item);
  Lock lock;
  std::map<std::string, Entry>::iterator it = g_byHandle.find(key);
  if (it == g_byHandle.end()) return "";
  if (it->second.prototype != proto) { g_byHandle.erase(it); return ""; } // handle reused by another type
  return it->second.id;
}

std::string Stamp(Item *item) {
  const std::string key = HandleKey(item);
  const std::string proto = PrototypeOf(item);
  if (key.empty() || proto.empty()) return "";
  const std::string existing = IdOf(item);
  if (!existing.empty()) return existing;
  Lock lock;
  if (g_byHandle.size() >= kMaxEntries) return "";
  Entry e;
  e.id = NewId();
  e.prototype = proto;
  g_byHandle[key] = e;
  Log("DURABLE_ITEM: stamped id=" + e.id + " handle=" + key + " proto=" + proto);
  return e.id;
}

} // namespace DurableItem
} // namespace Stobe
