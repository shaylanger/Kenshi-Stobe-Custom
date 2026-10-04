// Item 104: relationship-shaped shop prices. See ShopPriceHook.h.
#include "ShopPriceHook.h"

#include "Comm.h"
#include "ShopPricing.h"
#include "Utils.h"

#include <core/Functions.h>
#include <kenshi/Character.h>
#include <kenshi/Faction.h>
#include <kenshi/Item.h>
#include <kenshi/gui/InventoryGUI.h>
#include <kenshi/util/hand.h>

#include <cstring>
#include <deque>
#include <map>
#include <string>

namespace Stobe {
namespace UI {
void QueueUiNotifyAction(const std::string &message); // ChatBox.cpp
}
}

namespace Stobe {
namespace ShopPrice {
namespace {

using StobeShopPricing::Constants;

const DWORD kFreshMs = 30000; // refetch an entry older than this (the old value stays in use meanwhile)
const DWORD kRetryMs = 15000; // after a failed fetch (vanilla meanwhile)
const DWORD kFirstWaitMs = 400; // a purchase with no r cached yet waits this long for the fetch

struct Entry {
  int r;
  bool known;   // a reply (or a failure) arrived
  bool pending; // a fetch is queued/running
  DWORD tick;   // when it arrived
  Constants c;
  Entry() : r(0), known(false), pending(false), tick(0) {}
};

struct Request {
  unsigned long long key;
  std::string traderName, playerName;
};

CRITICAL_SECTION g_lock;
bool g_lockReady = false;
std::map<unsigned long long, Entry> g_cache;
std::deque<Request> g_queue;
HANDLE g_wake = NULL;
HANDLE g_thread = NULL;

// the value functions' originals
typedef int (*ValueFn)(InventoryItemBase *, bool);
const int kHookCount = 5;
ValueFn g_orig[kHookCount] = {0, 0, 0, 0, 0};

// Inventory::buyItem context (set by BeginBuy on the calling thread)
struct BuyCtx {
  int depth;
  bool playerTrade;
  Character *trader;
  Character *player;
  bool logged;
};
__declspec(thread) BuyCtx t_buy = {0, false, 0, 0, false};
__declspec(thread) int t_inHook = 0;

// InventoryGUI::traders (static std::map<InventoryGUI*, InventoryTradeData>):
// the address of its _Myhead pointer, read from getPlayerTradeCharacter's code.
char **g_tradersHead = 0;

DWORD g_lastNotify = 0;

unsigned long long KeyOf(Character *trader, Character *player) {
  unsigned int a = 0, b = 0;
  try {
    a = trader->getHandle().serial;
    b = player->getHandle().serial;
  } catch (...) {
    return 0;
  }
  return ((unsigned long long)a << 32) | b;
}

std::string NameOf(Character *c) {
  try {
    return c ? c->getName() : std::string();
  } catch (...) {
    return std::string();
  }
}

bool IsPlayerFaction(Character *c) {
  if (!c || (uintptr_t)c < 0x1000) return false;
  try {
    Faction *f = c->getFaction();
    return f && f->isPlayer != 0;
  } catch (...) {
    return false;
  }
}

DWORD WINAPI Worker(LPVOID) {
  for (;;) {
    WaitForSingleObject(g_wake, 5000);
    for (;;) {
      Request q;
      EnterCriticalSection(&g_lock);
      if (g_queue.empty()) {
        LeaveCriticalSection(&g_lock);
        break;
      }
      q = g_queue.front();
      g_queue.pop_front();
      LeaveCriticalSection(&g_lock);

      std::string reply;
      try {
        reply = PostToStobeWithResponse(L"/relationship_pricing",
                                        "player=" + UrlEncode(q.playerName) + "&npcs=" + UrlEncode(q.traderName));
      } catch (...) {
        reply.clear();
      }
      int r = 0;
      bool found = false;
      Constants c;
      const bool ok = StobeShopPricing::ParseReply(reply, r, found, c);
      if (!ok) {
        r = 0;
        c = Constants();
      }

      EnterCriticalSection(&g_lock);
      Entry &e = g_cache[q.key];
      e.pending = false;
      e.known = true;
      e.r = r;
      e.c = c;
      // a failure is retried sooner (vanilla meanwhile)
      e.tick = ok ? GetTickCount() : GetTickCount() - (kFreshMs - kRetryMs);
      LeaveCriticalSection(&g_lock);
      Log("SHOP_PRICE: r trader=" + q.traderName + " player=" + q.playerName + " r=" + ToString(r) +
          (ok ? (found ? "" : " (no profile: vanilla)") : " (fetch failed: vanilla)") +
          " buy_factor=" + ToString((float)StobeShopPricing::BuyFactor(r, c)) +
          " sell_factor=" + ToString((float)StobeShopPricing::SellFactor(r, c)) +
          (StobeShopPricing::TradeBlocked(r, c) ? " blocked=1" : ""));
    }
  }
  return 0;
}

void EnsureWorker() {
  if (g_thread) return;
  g_wake = CreateEventA(NULL, FALSE, FALSE, NULL);
  g_thread = CreateThread(NULL, 0, &Worker, NULL, 0, NULL);
}

// Under g_lock. Queues a fetch for the key unless one is running.
void QueueFetchLocked(unsigned long long key, Entry &e, Character *trader, Character *player) {
  if (e.pending || !g_wake) return;
  Request q;
  q.key = key;
  q.traderName = NameOf(trader);
  q.playerName = NameOf(player);
  if (q.traderName.empty()) return;
  e.pending = true;
  g_queue.push_back(q);
  SetEvent(g_wake);
}

// r for the pair; false = nothing known yet (vanilla). Never waits for the network.
bool LookupR(Character *trader, Character *player, int &r, Constants &c) {
  if (!g_lockReady || !trader || !player) return false;
  const unsigned long long key = KeyOf(trader, player);
  if (!key) return false;
  bool known = false;
  EnterCriticalSection(&g_lock);
  Entry &e = g_cache[key];
  if (e.known) {
    known = true;
    r = e.r;
    c = e.c;
  }
  if (!e.known || GetTickCount() - e.tick > kFreshMs) QueueFetchLocked(key, e, trader, player);
  LeaveCriticalSection(&g_lock);
  return known;
}

// Like LookupR, but never queues a fetch.
bool PeekR(Character *trader, Character *player, int &r, Constants &c) {
  if (!g_lockReady || !trader || !player) return false;
  const unsigned long long key = KeyOf(trader, player);
  if (!key) return false;
  bool known = false;
  EnterCriticalSection(&g_lock);
  std::map<unsigned long long, Entry>::iterator it = g_cache.find(key);
  if (it != g_cache.end() && it->second.known) {
    known = true;
    r = it->second.r;
    c = it->second.c;
  }
  LeaveCriticalSection(&g_lock);
  return known;
}

// The squad member on the player side of the open trade window. Walks
// InventoryGUI::traders with the node layout getPlayerTradeCharacter uses
// (VS2010 std::map node: +0x0 left, +0x10 right, +0x2a InventoryTradeData::isPlayer,
// +0x30 owner hand, +0x51 _Isnil).
Character *WindowPlayerCharacter() {
  if (!g_tradersHead) return 0;
  try {
    char *head = *g_tradersHead;
    if (!head) return 0;
    char *stack[32];
    int n = 0;
    char *root = *(char **)(head + 0x8);
    if (root && root != head && !*(root + 0x51)) stack[n++] = root;
    int guard = 0;
    while (n > 0 && guard++ < 64) {
      char *node = stack[--n];
      if (*(node + 0x2a)) {
        const hand *h = reinterpret_cast<const hand *>(node + 0x30);
        Character *c = h->getCharacter();
        if (c && IsPlayerFaction(c)) return c;
      }
      char *l = *(char **)(node + 0x0), *rt = *(char **)(node + 0x10);
      if (n < 30 && l && l != head && !*(l + 0x51)) stack[n++] = l;
      if (n < 30 && rt && rt != head && !*(rt + 0x51)) stack[n++] = rt;
    }
  } catch (...) {
  }
  return 0;
}

bool WindowOpen() {
  try {
    return InventoryGUI::isTradingForMoney_static() != 0;
  } catch (...) {
    return false;
  }
}

Character *WindowTrader() {
  try {
    return InventoryGUI::getNPCTrader();
  } catch (...) {
    return 0;
  }
}

// Who trades right now; false = not a player trade (vanilla).
bool ResolvePair(Character *&trader, Character *&player, bool &inBuy) {
  inBuy = t_buy.depth > 0;
  if (inBuy) {
    if (!t_buy.playerTrade) return false;
    trader = t_buy.trader;
    player = t_buy.player;
    return trader && player;
  }
  if (!WindowOpen()) return false;
  trader = WindowTrader();
  if (!trader || IsPlayerFaction(trader)) return false;
  player = WindowPlayerCharacter();
  return player != 0;
}

int Price(int idx, InventoryItemBase *self, bool isPlayer) {
  ValueFn orig = g_orig[idx];
  if (t_inHook) return orig(self, isPlayer);
  // An override may call the (also hooked) base getValueSingle: keep that inner call vanilla
  // so the price is adjusted once.
  ++t_inHook;
  int vanilla = 0;
  try {
    vanilla = orig(self, isPlayer);
  } catch (...) {
    --t_inHook;
    throw;
  }
  --t_inHook;
  Character *trader = 0, *player = 0;
  bool inBuy = false;
  if (!ResolvePair(trader, player, inBuy)) return vanilla;
  int r = 0;
  Constants c;
  if (!LookupR(trader, player, r, c) || r == 0) return vanilla;
  ++t_inHook;
  int other = vanilla;
  try {
    other = orig(self, !isPlayer);
  } catch (...) {
    other = vanilla;
  }
  --t_inHook;
  const int vanillaBuy = isPlayer ? vanilla : other;
  const int vanillaSell = isPlayer ? other : vanilla;
  const StobeShopPricing::Prices p = StobeShopPricing::Adjust(vanillaBuy, vanillaSell, r, c);
  const int out = isPlayer ? p.buy : p.sell;
  if (inBuy && !t_buy.logged) {
    t_buy.logged = true;
    std::string item;
    try {
      item = self->getName();
    } catch (...) {
    }
    Log(std::string("SHOP_PRICE: ") + (isPlayer ? "player buys" : "player sells") + " item=" + item +
        " trader=" + NameOf(trader) + " player=" + NameOf(player) + " r=" + ToString(r) +
        " vanilla_buy=" + ToString(vanillaBuy) + " vanilla_sell=" + ToString(vanillaSell) +
        " price=" + ToString(out) + " (each)");
  }
  return out;
}

// one detour per hooked class (VS2010 can't cast a template function's address to void*)
int ValueHook0(InventoryItemBase *self, bool isPlayer) { return Price(0, self, isPlayer); }
int ValueHook1(InventoryItemBase *self, bool isPlayer) { return Price(1, self, isPlayer); }
int ValueHook2(InventoryItemBase *self, bool isPlayer) { return Price(2, self, isPlayer); }
int ValueHook3(InventoryItemBase *self, bool isPlayer) { return Price(3, self, isPlayer); }
int ValueHook4(InventoryItemBase *self, bool isPlayer) { return Price(4, self, isPlayer); }

bool HookOne(HMODULE lib, const char *symbol, void *hook, int idx) {
  void *thunk = (void *)GetProcAddress(lib, symbol);
  if (!thunk) {
    Log(std::string("HOOK_WARN: SHOP_PRICE symbol not found: ") + symbol);
    return false;
  }
  intptr_t real = KenshiLib::GetRealAddress(thunk);
  if (!real) {
    Log(std::string("HOOK_WARN: SHOP_PRICE GetRealAddress failed: ") + symbol);
    return false;
  }
  KenshiLib::HookStatus st = KenshiLib::AddHook((void *)real, hook, (void **)&g_orig[idx]);
  if (st != KenshiLib::SUCCESS || !g_orig[idx]) {
    Log(std::string("HOOK_WARN: SHOP_PRICE AddHook failed: ") + symbol + " status=" + ToString((int)st));
    g_orig[idx] = 0;
    return false;
  }
  return true;
}

void ResolveTradersMap(HMODULE lib) {
  void *thunk = (void *)GetProcAddress(lib, "?getPlayerTradeCharacter@InventoryGUI@@QEAAPEAVRootObject@@XZ");
  if (!thunk) {
    Log("SHOP_PRICE: getPlayerTradeCharacter not exported: trade window stays vanilla");
    return;
  }
  const unsigned char *p = (const unsigned char *)KenshiLib::GetRealAddress(thunk);
  // push rbx; sub rsp,40h; mov r8,[rip+disp32]   (also accepts the REX-prefixed push)
  static const unsigned char kSig[] = {0x53, 0x48, 0x83, 0xEC, 0x40, 0x4C, 0x8B, 0x05};
  static const unsigned char kSigRex[] = {0x40, 0x53, 0x48, 0x83, 0xEC, 0x40, 0x4C, 0x8B, 0x05};
  int at = -1;
  if (p && memcmp(p, kSig, sizeof(kSig)) == 0)
    at = (int)sizeof(kSig);
  else if (p && memcmp(p, kSigRex, sizeof(kSigRex)) == 0)
    at = (int)sizeof(kSigRex);
  if (at < 0) {
    Log("SHOP_PRICE: getPlayerTradeCharacter code not recognised: trade window stays vanilla");
    return;
  }
  int disp = 0;
  memcpy(&disp, p + at, 4);
  g_tradersHead = (char **)(p + at + 4 + disp);
  Log("SHOP_PRICE: trade window map found");
}

} // namespace

void Install(HMODULE lib) {
  if (!g_lockReady) {
    InitializeCriticalSection(&g_lock);
    g_lockReady = true;
  }
  EnsureWorker();
  ResolveTradersMap(lib);
  int ok = 0;
  ok += HookOne(lib, "?getValueSingle@InventoryItemBase@@UEBAH_N@Z", (void *)&ValueHook0, 0) ? 1 : 0;
  ok += HookOne(lib, "?getValueSingle@Weapon@@UEBAH_N@Z", (void *)&ValueHook1, 1) ? 1 : 0;
  ok += HookOne(lib, "?getValueSingle@Armour@@UEBAH_N@Z", (void *)&ValueHook2, 2) ? 1 : 0;
  ok += HookOne(lib, "?getValueSingle@BlueprintItem@@UEBAH_N@Z", (void *)&ValueHook3, 3) ? 1 : 0;
  ok += HookOne(lib, "?getValueSingle@MapItem@@UEBAH_N@Z", (void *)&ValueHook4, 4) ? 1 : 0;
  Log("SHOP_PRICE: relationship price hooks installed " + ToString(ok) + "/5");
}

bool BeginBuy(Character *buyer, Character *seller) {
  BuyCtx &b = t_buy;
  if (b.depth++ > 0) return false; // nested: keep the outer context
  b.playerTrade = false;
  b.trader = 0;
  b.player = 0;
  b.logged = false;
  const bool buyerPlayer = IsPlayerFaction(buyer), sellerPlayer = IsPlayerFaction(seller);
  if (buyerPlayer == sellerPlayer) return false; // squad to squad, or no squad member involved
  b.player = buyerPlayer ? buyer : seller;
  Character *other = buyerPlayer ? seller : buyer;
  if (!other && WindowOpen()) other = WindowTrader(); // shop goods owned by the shop, not the trader
  if (!other || IsPlayerFaction(other)) return false;
  b.trader = other;
  b.playerTrade = true;
  int r = 0;
  Constants c;
  bool known = LookupR(b.trader, b.player, r, c);
  if (!known) {
    // First purchase for this pair (no trade window warmed the cache): wait briefly for the
    // background fetch so the first deal already gets the right price / refusal. Bounded;
    // after kFirstWaitMs it goes through at vanilla.
    const DWORD start = GetTickCount();
    while (!known && GetTickCount() - start < kFirstWaitMs) {
      Sleep(10);
      known = PeekR(b.trader, b.player, r, c);
    }
    if (!known) Log("SHOP_PRICE: r not known yet for trader=" + NameOf(b.trader) + ": this trade at vanilla");
  }
  if (known && StobeShopPricing::TradeBlocked(r, c)) {
    const std::string t = NameOf(b.trader), pl = NameOf(b.player);
    Log("SHOP_PRICE: blocked " + std::string(buyerPlayer ? "purchase" : "sale") + " trader=" + t + " player=" + pl +
        " r=" + ToString(r) + " (no trade at r <= " + ToString(c.blockAtOrBelow) + ")");
    const DWORD now = GetTickCount();
    if (now - g_lastNotify > 2000) {
      g_lastNotify = now;
      Stobe::UI::QueueUiNotifyAction(t + " refuses to trade with " + pl + ".");
    }
    return true;
  }
  return false;
}

void EndBuy() {
  if (t_buy.depth > 0 && --t_buy.depth == 0) {
    t_buy.playerTrade = false;
    t_buy.trader = 0;
    t_buy.player = 0;
  }
}

void ClearCache() {
  if (!g_lockReady) return;
  EnterCriticalSection(&g_lock);
  for (std::map<unsigned long long, Entry>::iterator it = g_cache.begin(); it != g_cache.end();) {
    if (it->second.pending)
      ++it; // the worker writes it back
    else
      g_cache.erase(it++);
  }
  LeaveCriticalSection(&g_lock);
}

std::string DebugRefresh(Character *trader, Character *player) {
  if (!g_lockReady) return "shop price hook not installed";
  if (!trader || !player) return "usage: shopprice <trader> [player]";
  const unsigned long long key = KeyOf(trader, player);
  std::string out = "trader=" + NameOf(trader) + " player=" + NameOf(player);
  EnterCriticalSection(&g_lock);
  Entry &e = g_cache[key];
  if (e.known)
    out += " cached_r=" + ToString(e.r) + " age_ms=" + ToString((int)(GetTickCount() - e.tick)) +
           " buy_factor=" + ToString((float)StobeShopPricing::BuyFactor(e.r, e.c)) +
           " sell_factor=" + ToString((float)StobeShopPricing::SellFactor(e.r, e.c)) +
           " blocked=" + (StobeShopPricing::TradeBlocked(e.r, e.c) ? "1" : "0");
  else
    out += " cached_r=none";
  e.tick = GetTickCount() - kFreshMs - 1; // stale: refetch now
  QueueFetchLocked(key, e, trader, player);
  out += e.pending ? " refetch=queued" : " refetch=no";
  LeaveCriticalSection(&g_lock);
  out += std::string(" window=") + (WindowOpen() ? "1" : "0");
  return out;
}

} // namespace ShopPrice
} // namespace Stobe
