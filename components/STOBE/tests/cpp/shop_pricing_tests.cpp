// Item 104: relationship shop prices (ShopPricing.cpp): formula, floor, no buy/sell loop profit, reply parsing.
#include "ShopPricing.h"

#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>

using namespace StobeShopPricing;

static int g_checks = 0;
static void check(bool ok, const std::string &what) {
  ++g_checks;
  if (!ok) throw std::runtime_error(what);
}
static bool near(double a, double b, double eps) { return std::fabs(a - b) <= eps; }
static std::string S(int v) {
  char b[32];
  std::snprintf(b, sizeof(b), "%d", v);
  return b;
}

int main() {
  try {
    const Constants c;
    // Shay's spec numbers (memory stobe-negotiation-rules / server contract)
    check(BuyFactor(0, c) == 1.0 && SellFactor(0, c) == 1.0, "r=0 is vanilla");
    check(near(BuyFactor(10, c), 1 - 0.024, 0.0005), "+10 -> -2.4%");
    check(near(BuyFactor(56, c), 1 - 0.1585, 0.0005), "+56 -> -15.85%");
    check(near(BuyFactor(100, c), 0.70, 1e-9), "+100 -> -30%");
    check(near(BuyFactor(-10, c), 1.048, 0.0005), "-10 -> +4.8%");
    check(near(BuyFactor(-50, c), 3.0, 0.01), "-50 -> +200%");
    check(near(BuyFactor(-100, c), 11.0, 1e-9), "-100 -> +1000%");
    check(near(SellFactor(100, c), 1.10, 1e-9), "sell +100 -> +10%");
    check(near(SellFactor(-100, c), 0.10, 1e-9), "sell -100 -> -90%");
    check(SellFactor(-50, c) < 1.0 && SellFactor(-50, c) > 0.10, "sell -50 between");
    check(BuyFactor(150, c) == BuyFactor(100, c) && BuyFactor(-150, c) == BuyFactor(-100, c), "r clamped");
    for (int r = -100; r < 100; ++r) {
      check(BuyFactor(r + 1, c) <= BuyFactor(r, c), "buy factor falls as r rises at " + S(r));
      check(SellFactor(r + 1, c) >= SellFactor(r, c), "sell factor rises as r rises at " + S(r));
    }
    // the block line
    check(TradeBlocked(-80, c) && TradeBlocked(-100, c), "no trade at r <= -80");
    check(!TradeBlocked(-79, c) && !TradeBlocked(0, c), "trade at r > -80");

    // vanilla untouched at r = 0, whatever the numbers
    Prices p = Adjust(123, 45, 0, c);
    check(p.buy == 123 && p.sell == 45, "Adjust r=0 vanilla");

    // weapon-like item: the game charges 2x what it pays (TRADE_PROFIT_MARGINS)
    p = Adjust(1000, 500, 100, c);
    check(p.buy == 700 && p.sell == 550, "r=+100 weapon buy 700 sell 550, got " + S(p.buy) + "/" + S(p.sell));
    p = Adjust(1000, 500, 56, c);
    check(p.buy == 841 && p.sell == 526, "r=+56 weapon, got " + S(p.buy) + "/" + S(p.sell));
    p = Adjust(1000, 500, -50, c);
    check(p.buy == 3003, "r=-50 weapon buy x3.003, got " + S(p.buy));
    check(p.sell < 500, "r=-50 weapon sell below vanilla");
    p = Adjust(1000, 500, -100, c);
    check(p.buy == 11000 && p.sell == 50, "r=-100 weapon, got " + S(p.buy) + "/" + S(p.sell));

    // floor: thin margin (vanilla buy 1.1x sell): the discount stops at sell + 1 and at the vanilla sell value
    p = Adjust(110, 100, 100, c);
    check(p.buy >= p.sell + 1, "floor: buy > sell (thin margin)");
    check(p.buy >= 100, "floor: buy >= vanilla sell");
    check(p.buy <= 110, "liked never above vanilla buy");
    // trade goods: the game buys and sells at the same price -> no discount, no bonus, zero-profit loop
    p = Adjust(100, 100, 100, c);
    check(p.buy == 100 && p.sell == 100, "same-price item stays vanilla at +100, got " + S(p.buy) + "/" + S(p.sell));
    p = Adjust(100, 100, 30, c);
    check(p.buy == 100 && p.sell == 100, "same-price item stays vanilla at +30");

    // no buy/sell loop profit anywhere, and liked never costs more than vanilla
    const int vbs[] = {1, 2, 3, 7, 10, 25, 99, 100, 101, 250, 999, 1000, 12345, 80000};
    const double margins[] = {1.0, 1.05, 1.1, 1.25, 1.5, 2.0, 3.0};
    for (size_t i = 0; i < sizeof(vbs) / sizeof(vbs[0]); ++i)
      for (size_t m = 0; m < sizeof(margins) / sizeof(margins[0]); ++m) {
        const int vs = vbs[i];
        const int vb = (int)std::floor(vs * margins[m] + 0.5);
        for (int r = -100; r <= 100; ++r) {
          Prices q = Adjust(vb, vs, r, c);
          const std::string at = " vb=" + S(vb) + " vs=" + S(vs) + " r=" + S(r);
          check(q.sell <= q.buy, "loop profit" + at);
          if (r != 0 && vb > vs) check(q.buy >= q.sell + 1, "floor buy >= sell+1" + at);
          check(q.buy >= vs || r == 0, "floor buy >= vanilla sell" + at);
          if (r > 0) check(q.buy <= vb, "liked costs more than vanilla" + at);
          if (r > 0) check(q.sell >= vs, "liked pays less than vanilla" + at);
          if (r < 0) check(q.buy >= vb, "disliked cheaper than vanilla" + at);
          if (r < 0) check(q.sell <= vs, "disliked pays more than vanilla" + at);
          check(q.buy >= 0 && q.sell >= 0, "negative price" + at);
        }
      }
    // r rising after a good deal never opens a loop between two r values (buy at r1, sell at r2 > r1)
    for (int r1 = -100; r1 <= 100; r1 += 5)
      for (int r2 = r1; r2 <= 100 && r2 <= r1 + 10; ++r2) {
        Prices a = Adjust(1000, 500, r1, c), b = Adjust(1000, 500, r2, c);
        check(b.sell <= a.buy, "small r gain loop r1=" + S(r1) + " r2=" + S(r2));
      }
    // overflow guard
    p = Adjust(50000000, 1000, -100, c);
    check(p.buy == 100000000, "price capped at 1e8");

    // reply parsing
    int r = 0;
    bool found = false;
    Constants pc;
    const std::string live =
        "{\"ok\":true,\"player\":\"Shay\",\"constants\":{\"buy_discount_max\":0.3,\"buy_discount_exp\":1.1,"
        "\"buy_increase_max\":10,\"buy_increase_exp\":2.32,\"sell_bonus_max\":0.1,\"sell_bonus_exp\":1.1,"
        "\"sell_cut_max\":0.90,\"sell_cut_exp\":2.32,\"trader_buy_ratio\":0.5},\"entries\":[{\"query\":\"Malzin\","
        "\"npc\":\"Malzin\",\"found\":true,\"r\":100,\"buy_factor\":0.7,\"sell_factor\":1.1}]}";
    check(ParseReply(live, r, found, pc) && found && r == 100, "parse live reply");
    check(near(BuyFactor(r, pc), 0.7, 1e-9), "parsed constants");
    check(ParseReply("{\"ok\":true,\"entries\":[{\"query\":\"x\",\"found\":true,\"r\":-56}]}", r, found, pc) && r == -56,
          "parse negative r");
    check(ParseReply("{\"ok\":true,\"entries\":[{\"query\":\"x\",\"found\":false,\"r\":0}]}", r, found, pc) && !found &&
              r == 0,
          "parse not found -> 0");
    Constants pc2;
    check(ParseReply("{\"ok\":true,\"constants\":{\"sell_cut_max\":0.5},\"entries\":[{\"found\":true,\"r\":-100}]}", r,
                     found, pc2) &&
              near(SellFactor(r, pc2), 0.5, 1e-9) && near(pc2.buyIncreaseMax, 10.0, 1e-9),
          "partial constants keep defaults");
    check(!ParseReply("{\"ok\":false,\"error\":\"unsupported_endpoint\"}", r, found, pc), "ok:false -> vanilla");
    check(!ParseReply("", r, found, pc), "empty -> vanilla");
    check(!ParseReply("<html>502</html>", r, found, pc), "garbage -> vanilla");
    check(!ParseReply("{\"ok\":true,\"entries\":[]}", r, found, pc), "no entry -> vanilla");
  } catch (const std::exception &e) {
    std::printf("FAIL: %s\n", e.what());
    return 1;
  }
  std::printf("shop_pricing_tests: %d checks passed\n", g_checks);
  return 0;
}
