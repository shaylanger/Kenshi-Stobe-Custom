#pragma once
// Relationship-shaped shop prices (item 104): the pure math behind the shop
// price hook (ShopPriceHook.cpp). No Kenshi or Windows dependencies, so the
// portable tests (tests/cpp/shop_pricing_tests.cpp) cover it.
//
// r = the trader's relationship toward the trading squad member, -100..100;
// no data = 0 = vanilla. Names follow the server contract
// (pending-fixes/relationship-pricing-interface.md):
//   vanillaBuy  = what the trader charges the player (game value, isPlayer=true)
//   vanillaSell = what the trader pays the player    (game value, isPlayer=false)

#include <string>

namespace StobeShopPricing {

struct Constants {
  double buyDiscountMax, buyDiscountExp;  // r>0, player buys: -30% at +100, shape 1.1
  double buyIncreaseMax, buyIncreaseExp;  // r<0, player buys: +1000% at -100, shape 2.32
  double sellBonusMax, sellBonusExp;      // r>0, player sells: +10% at +100, shape 1.1
  double sellCutMax, sellCutExp;          // r<0, player sells: -75% at -100, shape 2.32
  int blockAtOrBelow;                     // no trade at r <= -80
  Constants();
};

int ClampR(int r);
double BuyFactor(int r, const Constants &c);
double SellFactor(int r, const Constants &c);
bool TradeBlocked(int r, const Constants &c);

struct Prices {
  int buy;  // what the player pays the trader
  int sell; // what the trader pays the player
};

// Applies r to one item's vanilla prices, with the anti-exploit floor:
// - buy >= sell + 1 and buy >= vanillaSell (no buy/sell loop profit);
// - a liked trader (r > 0) never charges more than vanilla; if the floor would
//   push the buy price above vanilla (items the game buys and sells at the same
//   price), the buy price stays vanilla and the sell price is capped so that
//   sell <= buy (never a profit; at worst buy == sell == vanilla).
// r == 0 returns the vanilla prices untouched.
Prices Adjust(int vanillaBuy, int vanillaSell, int r, const Constants &c);

// Parses the reply of relationship_pricing.php for the first entry: r, found,
// and the constants (missing fields keep their defaults). False when the reply
// isn't ok:true or has no entry.
bool ParseReply(const std::string &json, int &rOut, bool &foundOut, Constants &c);

} // namespace StobeShopPricing
