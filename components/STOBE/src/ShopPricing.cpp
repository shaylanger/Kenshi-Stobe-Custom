#include "ShopPricing.h"

#include <cmath>
#include <cstdlib>

namespace StobeShopPricing {

Constants::Constants()
    : buyDiscountMax(0.30), buyDiscountExp(1.1), buyIncreaseMax(10.0),
      buyIncreaseExp(2.32), sellBonusMax(0.10), sellBonusExp(1.1),
      sellCutMax(0.75), sellCutExp(2.32), blockAtOrBelow(-80) {}

int ClampR(int r) { return r < -100 ? -100 : (r > 100 ? 100 : r); }

static double Shape(int r, double maxv, double expv) {
  const double x = std::fabs((double)ClampR(r)) / 100.0;
  return maxv * std::pow(x, expv);
}

double BuyFactor(int r, const Constants &c) {
  r = ClampR(r);
  if (r > 0) return 1.0 - Shape(r, c.buyDiscountMax, c.buyDiscountExp);
  if (r < 0) return 1.0 + Shape(r, c.buyIncreaseMax, c.buyIncreaseExp);
  return 1.0;
}

double SellFactor(int r, const Constants &c) {
  r = ClampR(r);
  double f = 1.0;
  if (r > 0) f = 1.0 + Shape(r, c.sellBonusMax, c.sellBonusExp);
  if (r < 0) f = 1.0 - Shape(r, c.sellCutMax, c.sellCutExp);
  return f < 0.0 ? 0.0 : f;
}

bool TradeBlocked(int r, const Constants &c) { return ClampR(r) <= c.blockAtOrBelow; }

static int RoundPrice(double v) {
  if (v <= 0.0) return 0;
  if (v > 100000000.0) return 100000000; // keeps getValueAll (x quantity) inside int
  return (int)std::floor(v + 0.5);
}

Prices Adjust(int vanillaBuy, int vanillaSell, int r, const Constants &c) {
  Prices p;
  p.buy = vanillaBuy;
  p.sell = vanillaSell;
  r = ClampR(r);
  if (r == 0 || (vanillaBuy <= 0 && vanillaSell <= 0)) return p;
  const int vb = vanillaBuy > 0 ? vanillaBuy : 0;
  const int vs = vanillaSell > 0 ? vanillaSell : 0;
  int sell = RoundPrice(vs * SellFactor(r, c));
  int buy = RoundPrice(vb * BuyFactor(r, c));
  if (vb > 0) {
    // floor: never below what the trader pays the player for it now (+1), nor the vanilla sell value
    if (buy < sell + 1) buy = sell + 1;
    if (buy < vs) buy = vs;
    if (r > 0 && buy > vb) {
      buy = vb; // liked never costs more than vanilla
      if (sell >= buy) {
        sell = buy - 1;
        if (sell < vs && vs <= buy) sell = vs; // game itself buys == sells: keep vanilla, zero-profit loop
      }
    }
  }
  p.buy = buy;
  p.sell = sell;
  return p;
}

// --- tiny JSON readers (flat numbers/bools only) ---
static bool FindKey(const std::string &s, const std::string &key, size_t from, size_t &valuePos) {
  const std::string q = "\"" + key + "\"";
  size_t k = s.find(q, from);
  while (k != std::string::npos) {
    size_t i = k + q.size();
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
    if (i < s.size() && s[i] == ':') {
      ++i;
      while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
      valuePos = i;
      return true;
    }
    k = s.find(q, k + 1);
  }
  return false;
}

static bool ReadNumber(const std::string &s, const std::string &key, size_t from, double &out) {
  size_t v = 0;
  if (!FindKey(s, key, from, v)) return false;
  const char *start = s.c_str() + v;
  char *end = 0;
  double d = std::strtod(start, &end);
  if (end == start) return false;
  out = d;
  return true;
}

static bool ReadBool(const std::string &s, const std::string &key, size_t from, bool &out) {
  size_t v = 0;
  if (!FindKey(s, key, from, v)) return false;
  if (s.compare(v, 4, "true") == 0) { out = true; return true; }
  if (s.compare(v, 5, "false") == 0) { out = false; return true; }
  return false;
}

bool ParseReply(const std::string &json, int &rOut, bool &foundOut, Constants &c) {
  bool ok = false;
  if (!ReadBool(json, "ok", 0, ok) || !ok) return false;
  size_t constantsPos = json.find("\"constants\"");
  if (constantsPos != std::string::npos) {
    ReadNumber(json, "buy_discount_max", constantsPos, c.buyDiscountMax);
    ReadNumber(json, "buy_discount_exp", constantsPos, c.buyDiscountExp);
    ReadNumber(json, "buy_increase_max", constantsPos, c.buyIncreaseMax);
    ReadNumber(json, "buy_increase_exp", constantsPos, c.buyIncreaseExp);
    ReadNumber(json, "sell_bonus_max", constantsPos, c.sellBonusMax);
    ReadNumber(json, "sell_bonus_exp", constantsPos, c.sellBonusExp);
    ReadNumber(json, "sell_cut_max", constantsPos, c.sellCutMax);
    ReadNumber(json, "sell_cut_exp", constantsPos, c.sellCutExp);
  }
  size_t entries = json.find("\"entries\"");
  if (entries == std::string::npos) return false;
  size_t obj = json.find('{', entries);
  if (obj == std::string::npos) return false;
  double r = 0.0;
  if (!ReadNumber(json, "r", obj, r)) return false;
  bool found = false;
  ReadBool(json, "found", obj, found);
  rOut = ClampR((int)(r < 0 ? r - 0.5 : r + 0.5));
  foundOut = found;
  if (!found) rOut = 0;
  return true;
}

} // namespace StobeShopPricing
