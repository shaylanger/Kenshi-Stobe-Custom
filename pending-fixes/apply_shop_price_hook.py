#!/usr/bin/env python3
"""Item 104: wire the relationship shop-price hook into Stobe (anchor edits).

Usage: apply_shop_price_hook.py <STOBE tree root>
New files (src/ShopPricing.*, src/ShopPriceHook.*, tests/cpp/shop_pricing_tests.cpp; snapshot in
components/STOBE) are copied separately, and C:\StobeBuild\build_portable.bat needs "ShopPricing ShopPriceHook"
appended to SOURCES;
this script only edits existing files and asserts every anchor.
"""
import sys, os

root = sys.argv[1]

def edit(rel, old, new, count=1):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8', newline='').read()
    n = s.count(old)
    assert n == count, f"{rel}: anchor found {n}x (want {count}): {old[:80]!r}"
    s = s.replace(old, new)
    open(p, 'w', encoding='utf-8', newline='').write(s)

# main.cpp: include
edit('src/main.cpp', '#include "StobeHarnessBridge.h"\n',
     '#include "StobeHarnessBridge.h"\n#include "ShopPriceHook.h"\n')

# main.cpp: buyItem hook -> relationship context + r <= -80 refusal
edit('src/main.cpp',
     '''  Item *result = nullptr;
  if (buyItem_orig) {
    result = buyItem_orig(inv, itemToBuy, sendingTo);
  }
''',
     '''  // Item 104: relationship shop prices. The value hooks price this purchase for the
  // (trader, squad member) pair; at r <= -80 the trader refuses (nothing moves).
  Character *shopBuyerChar = buyerObj ? ResolveCharacterBySerialForInventoryEvent(
                                            ResolveRootObjectSerialForEvent(buyerObj))
                                      : nullptr;
  Character *shopSellerChar = sellerObj ? ResolveCharacterBySerialForInventoryEvent(
                                              ResolveRootObjectSerialForEvent(sellerObj))
                                        : nullptr;
  if (shopBuyerChar && (RootObject *)shopBuyerChar != buyerObj) shopBuyerChar = nullptr;
  if (shopSellerChar && (RootObject *)shopSellerChar != sellerObj) shopSellerChar = nullptr;
  if (Stobe::ShopPrice::BeginBuy(shopBuyerChar, shopSellerChar)) {
    Stobe::ShopPrice::EndBuy();
    return nullptr;
  }

  Item *result = nullptr;
  if (buyItem_orig) {
    try {
      result = buyItem_orig(inv, itemToBuy, sendingTo);
    } catch (...) {
      Stobe::ShopPrice::EndBuy();
      throw;
    }
  }
  Stobe::ShopPrice::EndBuy();
''')

# main.cpp: install after the buyItem hook
edit('src/main.cpp',
     '''      Log("HOOK_DIAG: Inventory::buyItem AddHook status=" +
          ToString((int)buyItemStatus) + " orig=" +
          ToString((unsigned int)(uintptr_t)buyItem_orig));
    }
  }
''',
     '''      Log("HOOK_DIAG: Inventory::buyItem AddHook status=" +
          ToString((int)buyItemStatus) + " orig=" +
          ToString((unsigned int)(uintptr_t)buyItem_orig));
    }
  }
  Stobe::ShopPrice::Install(hLib); // item 104: relationship shop prices
''')

# main.cpp: forget cached r on load / new game / import
for fn in ('void __fastcall LoadCampaign(SaveFileSystem* fs, const std::string& path) {\n    PlaythroughSession::BeginLoad();\n',
           'void __fastcall NewCampaign(SaveManager* manager, const std::string& start) {\n    PlaythroughSession::BeginLoad(true);\n',
           'void __fastcall ImportCampaign(SaveManager* manager, const SaveInfo& save, int flags) {\n    PlaythroughSession::BeginLoad();\n'):
    edit('src/main.cpp', fn, fn + '    Stobe::ShopPrice::ClearCache();\n')

# main.cpp: test command stobe_shopprice <trader> [player]
edit('src/main.cpp',
     '''  if (cmd == "state") {
    if (f.size() < 3)
      return "usage: state <target>";
''',
     '''  if (cmd == "shopprice") { // item 104: refetch r for (trader, player) and show the cached value
    if (f.size() < 3)
      return "usage: shopprice <trader> [player]";
    Character *trader = ResolveTestInboxTarget(world, sel, speaker, f[2]);
    if (!trader)
      return "target not found: " + f[2];
    Character *player = speaker;
    if (f.size() >= 4 && !f[3].empty()) {
      player = ResolveTestInboxTarget(world, sel, speaker, f[3]);
      if (!player)
        return "target not found: " + f[3];
    }
    ok = true;
    return Stobe::ShopPrice::DebugRefresh(trader, player);
  }
  if (cmd == "state") {
    if (f.size() < 3)
      return "usage: state <target>";
''')

# harness bridge: register stobe_shopprice
edit('src/StobeHarnessBridge.cpp',
     '''    {"give_item", "stobe_give_item <name> [count]"},
};''',
     '''    {"give_item", "stobe_give_item <name> [count]"},
    {"shopprice", "stobe_shopprice <trader> [player]"},
};''')
edit('src/StobeHarnessBridge.cpp',
     '''      std::string(registered == 6 ? "6 commands" : "SOME COMMANDS REFUSED") +
      " (stobe_ping/mode/say/state/give_cats/give_item)");''',
     '''      std::string(registered == 7 ? "7 commands" : "SOME COMMANDS REFUSED") +
      " (stobe_ping/mode/say/state/give_cats/give_item/shopprice)");''')

# Comm.cpp: GET route for the pricing endpoint (jsonData = the query string)
edit('src/Comm.cpp',
     '''  if (endpoint == L"/rename") {
    request.path = L"/StobeServer/rename.php";
    return request;
  }
''',
     '''  if (endpoint == L"/rename") {
    request.path = L"/StobeServer/rename.php";
    return request;
  }

  if (endpoint == L"/relationship_pricing") { // item 104: jsonData = "player=..&npcs=.." (url-encoded)
    request.method = L"GET";
    request.path = L"/StobeServer/relationship_pricing.php?" + ToWide(jsonData);
    request.body.clear();
    return request;
  }
''')

# build lists
edit('CMakeLists.txt', '  src/StobeHarnessBridge.cpp\n',
     '  src/StobeHarnessBridge.cpp\n  src/ShopPricing.cpp\n  src/ShopPriceHook.cpp\n')
edit('tests/cpp/CMakeLists.txt',
     'add_test(NAME social_protocol_tests COMMAND social_protocol_tests)\n',
     'add_test(NAME social_protocol_tests COMMAND social_protocol_tests)\n\n'
     'add_executable(shop_pricing_tests shop_pricing_tests.cpp ../../src/ShopPricing.cpp)\n'
     'target_include_directories(shop_pricing_tests PRIVATE ../../src)\n'
     'add_test(NAME shop_pricing_tests COMMAND shop_pricing_tests)\n')
print("ok")
