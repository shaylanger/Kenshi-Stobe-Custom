#pragma once
// Pure logic (no Kenshi SDK): turns per-agreement observations into the structured
// in-progress events the server accepts (operation "event"; server WP-E ActivityEvents.php).
// Only structured fields are produced; the server composes every sentence.
// Event ids are unique per agreement ([A-Za-z0-9:_-]{1,64}) and each id is emitted once.
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>
namespace Stobe { namespace Activity { namespace Events {

// Strip anything the server would drop anyway (quotes, backslash, control chars) and
// cut at a UTF-8 boundary so the JSON stays valid.
inline std::string SafeText(const std::string& in, size_t maxBytes) {
 std::string out; out.reserve(in.size());
 for (size_t i = 0; i < in.size(); ++i) {
  const unsigned char c = static_cast<unsigned char>(in[i]);
  if (c < 0x20 || c == '"' || c == '\\' || c == 0x7f) continue;
  out += static_cast<char>(c);
 }
 if (out.size() > maxBytes) {
  size_t cut = maxBytes;
  while (cut > 0 && (static_cast<unsigned char>(out[cut]) & 0xC0) == 0x80) --cut;
  out.erase(cut);
 }
 return out;
}

struct Observation {
 std::string agreementId, phase, resource, routeLabel;
 bool routePending;            // goal's pending command is the route travel
 unsigned delivered, quantity; // goal.delivered / agreement quantity
 bool handBackReturning;       // hand-back walk toward the requester started
 unsigned handBackCount;       // >0 once the reward was handed over
 bool threatObserved; unsigned threatSerial; std::string threatName; int threatDistance;
 bool actorHealthValid; int actorPercent;
 bool requesterHealthValid; int requesterPercent;
 unsigned long nowMs;
 Observation() : routePending(false), delivered(0), quantity(0), handBackReturning(false), handBackCount(0),
  threatObserved(false), threatSerial(0), threatDistance(-1), actorHealthValid(false), actorPercent(100),
  requesterHealthValid(false), requesterPercent(100), nowMs(0) {}
};
struct Event { std::string agreementId, id, kind, json; };

class Tracker {
public:
 static unsigned InjuryDropPoints() { return 15; }
 static unsigned long InjuryCooldownMs() { return 20000; }
 static unsigned long ThreatCooldownMs() { return 30000; }
 static unsigned long ThreatForgetMs() { return 60000; }
 static unsigned MaxThreats() { return 6; }
 static unsigned MaxEvents() { return 40; }

 // Appends zero or more new events. Each id is produced at most once per agreement.
 void Observe(const Observation& o, std::vector<Event>& out) {
  if (o.agreementId.empty()) return;
  State& s = states_[o.agreementId];
  const bool live = o.phase != "cancelled" && o.phase != "failed" && o.phase != "cleanup_pending" && o.phase != "dormant";
  if (!s.seeded) {
   s.seeded = true; s.lastDelivered = o.delivered; s.prevRoute = o.routePending;
   s.actor.Seed(o.actorHealthValid, o.actorPercent); s.requester.Seed(o.requesterHealthValid, o.requesterPercent);
  }
  if (!live) { s.prevRoute = o.routePending; return; }
  // arrival: the route leg ended and the activity moved on (never on failure).
  if (s.prevRoute && !o.routePending && !s.arrived && o.phase != "routing") {
   s.arrived = true;
   std::ostringstream j; j << "{\"id\":\"arr\",\"kind\":\"arrival\"";
   const std::string place = SafeText(o.routeLabel, 48);
   if (!place.empty()) j << ",\"place\":\"" << place << "\"";
   j << "}"; Push(s, o, "arr", "arrival", j.str(), out);
  }
  s.prevRoute = o.routePending;
  // progress: deliveries only ever increase.
  if (o.delivered > s.lastDelivered) {
   s.lastDelivered = o.delivered;
   std::ostringstream id; id << "p" << o.delivered;
   std::ostringstream j; j << "{\"id\":\"" << id.str() << "\",\"kind\":\"progress\",\"delivered\":" << o.delivered;
   if (o.quantity > 0) j << ",\"quantity\":" << o.quantity;
   const std::string r = SafeText(o.resource, 48);
   if (!r.empty()) j << ",\"resource\":\"" << r << "\"";
   j << "}"; Push(s, o, id.str(), "progress", j.str(), out);
  }
  // threat: one event per hostile serial, spaced out, capped.
  if (o.threatObserved && o.threatSerial) {
   s.threatLastSeenMs = o.nowMs; s.threatSeen = true;
   if (!s.threats.count(o.threatSerial) && s.threatCount < MaxThreats() &&
       (s.threatCount == 0 || o.nowMs - s.lastThreatMs >= ThreatCooldownMs())) {
    s.threats.insert(o.threatSerial); ++s.threatCount; s.lastThreatMs = o.nowMs;
    std::ostringstream id; id << "t" << s.threatCount;
    std::ostringstream j; j << "{\"id\":\"" << id.str() << "\",\"kind\":\"threat\"";
    const std::string n = SafeText(o.threatName, 40);
    if (!n.empty()) j << ",\"subject\":\"" << n << "\"";
    if (o.threatDistance >= 0 && o.threatDistance <= 2000) j << ",\"distance\":" << o.threatDistance;
    j << "}"; Push(s, o, id.str(), "threat", j.str(), out);
   }
  } else if (s.threatSeen && o.nowMs - s.threatLastSeenMs >= ThreatForgetMs()) {
   s.threats.clear(); s.threatSeen = false; // a new episode may be reported again
  }
  // injury: a drop of >= 15 percentage points since the last reported/healthy baseline.
  CheckInjury(s.actor, o.actorHealthValid, o.actorPercent, "actor", "ia", s, o, out);
  CheckInjury(s.requester, o.requesterHealthValid, o.requesterPercent, "requester", "ir", s, o, out);
  // hand-back
  if (o.handBackReturning && !s.returning) {
   s.returning = true;
   Push(s, o, "ret", "phase", "{\"id\":\"ret\",\"kind\":\"phase\",\"phase\":\"returning\"}", out);
  }
  if (o.handBackCount > 0 && !s.handedBack) {
   s.handedBack = true;
   std::ostringstream j; j << "{\"id\":\"hb\",\"kind\":\"handback\",\"count\":" << o.handBackCount << ",\"toRequester\":true";
   const std::string r = SafeText(o.resource, 48);
   if (!r.empty()) j << ",\"resource\":\"" << r << "\"";
   j << "}"; Push(s, o, "hb", "handback", j.str(), out);
  }
 }
 void Forget(const std::string& agreementId) { states_.erase(agreementId); }
 void Clear() { states_.clear(); }
private:
 struct Health {
  int baseline; unsigned long lastMs; unsigned count; bool reported;
  Health() : baseline(-1), lastMs(0), count(0), reported(false) {}
  static int Clamp(int p) { return p < 0 ? 0 : (p > 100 ? 100 : p); }
  void Seed(bool valid, int pct) { if (valid) baseline = Clamp(pct); }
 };
 struct State {
  bool seeded, prevRoute, arrived, returning, handedBack, threatSeen;
  unsigned lastDelivered, threatCount, total;
  unsigned long lastThreatMs, threatLastSeenMs;
  std::set<unsigned> threats; Health actor, requester;
  State() : seeded(false), prevRoute(false), arrived(false), returning(false), handedBack(false), threatSeen(false),
   lastDelivered(0), threatCount(0), total(0), lastThreatMs(0), threatLastSeenMs(0) {}
 };
 std::map<std::string, State> states_;
 static void Push(State& s, const Observation& o, const std::string& id, const char* kind, const std::string& json, std::vector<Event>& out) {
  if (s.total >= MaxEvents()) return;
  ++s.total; Event e; e.agreementId = o.agreementId; e.id = id; e.kind = kind; e.json = json; out.push_back(e);
 }
 static void CheckInjury(Health& h, bool valid, int pctIn, const char* who, const char* prefix, State& s,
                         const Observation& o, std::vector<Event>& out) {
  if (!valid) return;
  const int pct = Health::Clamp(pctIn);
  if (h.baseline < 0 || pct > h.baseline) { h.baseline = pct; return; }
  if (h.baseline - pct < static_cast<int>(InjuryDropPoints())) return;
  if (h.reported && o.nowMs - h.lastMs < InjuryCooldownMs()) return;
  h.reported = true; h.lastMs = o.nowMs; h.baseline = pct; ++h.count;
  std::ostringstream id; id << prefix << h.count;
  std::ostringstream j; j << "{\"id\":\"" << id.str() << "\",\"kind\":\"injury\",\"who\":\"" << who << "\",\"healthPercent\":" << pct << "}";
  Push(s, o, id.str(), "injury", j.str(), out);
 }
};
} } }
