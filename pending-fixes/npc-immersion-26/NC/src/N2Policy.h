// N2Policy.h: pure (SDK-free) logic for the N2 native package. Header only, VS2010 compatible.
//  - Attention block JSON (what an NPC is busy with / how they are doing)
//  - AbandonTracker: "abandoned_in_danger" (a squad mate left a downed squad mate far behind)
//  - ProximityGate: when the native side may fire the optional bored/follow-up turn
#pragma once
#include <map>
#include <string>
#include <sstream>
#include <stdio.h>

namespace Stobe {
namespace N2Policy {

inline int ClampInt(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

inline std::string JsonEscape(const std::string &s) {
  std::string o;
  o.reserve(s.size() + 8);
  for (size_t i = 0; i < s.size(); ++i) {
    unsigned char c = (unsigned char)s[i];
    if (c == '"') o += "\\\"";
    else if (c == '\\') o += "\\\\";
    else if (c == '\n') o += "\\n";
    else if (c == '\r') o += "\\r";
    else if (c == '\t') o += "\\t";
    else if (c < 0x20) { char b[8]; sprintf(b, "\\u%04x", (unsigned)c); o += b; }
    else o += (char)c;
  }
  return o;
}

// Keep only printable ASCII (drops UTF-8 multi-byte so a cut can never split a character), max n chars.
inline std::string AsciiTruncate(const std::string &s, size_t n) {
  std::string o;
  for (size_t i = 0; i < s.size() && o.size() < n; ++i) {
    unsigned char c = (unsigned char)s[i];
    if (c >= 0x20 && c < 0x7f) o += (char)c;
    else if (c == '\t' || c == '\n' || c == '\r') o += ' ';
  }
  return o;
}

inline std::string BoolJson(bool b) { return b ? "true" : "false"; }

// ------------------------------------------------------------------ attention
struct AttentionInputs {
  bool observed, busy, sleeping, injured, crippled, bleeding, exhausted, afraid, fleeing, hungry, inCombat;
  int bloodPct; // 0..100, -1 = unknown (reported as 100)
  std::string busyReason;
  AttentionInputs()
      : observed(true), busy(false), sleeping(false), injured(false), crippled(false), bleeding(false),
        exhausted(false), afraid(false), fleeing(false), hungry(false), inCombat(false), bloodPct(-1) {}
};

// blood/maxBlood -> 0..100 (unknown max = -1)
inline int BloodPct(float blood, float maxBlood) {
  if (!(maxBlood > 0.0f)) return -1;
  int p = (int)(blood * 100.0f / maxBlood + 0.5f);
  return ClampInt(p, 0, 100);
}
// hunger: (hunger+fed)*100 clamped 0..300, hungry below 75 (same scale as the context "hunger" field)
inline int HungerValue(float hunger, float fed) {
  float v = (hunger + fed) * 100.0f;
  if (v > 300.0f) v = 300.0f;
  if (v < 0.0f) v = 0.0f;
  return (int)v;
}
inline bool HungryFrom(int hungerValue) { return hungerValue < 75; }
// starving (<8% of 300) or blood-loss trauma. Limb "rested state" is limb health, NOT fatigue: never used here.
inline bool ExhaustedFrom(int hungerValue, bool bloodlossTrauma) { return hungerValue < 24 || bloodlossTrauma; }
// worstFleshPct: lowest flesh% of any body part, -1 = unknown
inline bool InjuredFrom(int bloodPct, bool crippled, bool bleeding, int worstFleshPct) {
  if (crippled || bleeding) return true;
  if (bloodPct >= 0 && bloodPct < 50) return true;
  return worstFleshPct >= 0 && worstFleshPct < 70;
}

inline std::string AttentionJson(const AttentionInputs &a) {
  if (!a.observed) return "{\"observed\":false}";
  int blood = a.bloodPct < 0 ? 100 : ClampInt(a.bloodPct, 0, 100);
  std::string reason = AsciiTruncate(a.busyReason, 40);
  std::string j = "{\"observed\":true";
  j += ",\"busy\":" + BoolJson(a.busy);
  j += ",\"sleeping\":" + BoolJson(a.sleeping);
  j += ",\"injured\":" + BoolJson(a.injured);
  j += ",\"crippled\":" + BoolJson(a.crippled);
  j += ",\"bleeding\":" + BoolJson(a.bleeding);
  j += ",\"exhausted\":" + BoolJson(a.exhausted);
  j += ",\"afraid\":" + BoolJson(a.afraid);
  j += ",\"fleeing\":" + BoolJson(a.fleeing);
  j += ",\"hungry\":" + BoolJson(a.hungry);
  j += ",\"in_combat\":" + BoolJson(a.inCombat);
  std::ostringstream os;
  os << blood;
  j += ",\"blood_pct\":" + os.str();
  if (!reason.empty()) j += ",\"busy_reason\":\"" + JsonEscape(reason) + "\"";
  j += "}";
  return j;
}

// Insert ,"attention":<attn> before the final '}' of a native_ai object that reports observed:true.
// Anything else (empty, unobserved, already has attention, not an object) is returned unchanged.
inline std::string AppendAttention(const std::string &nativeAiJson, const std::string &attnJson) {
  if (attnJson.empty() || nativeAiJson.empty()) return nativeAiJson;
  size_t end = nativeAiJson.find_last_not_of(" \t\r\n");
  if (end == std::string::npos || nativeAiJson[end] != '}' || nativeAiJson[0] != '{') return nativeAiJson;
  if (nativeAiJson.find("\"observed\":true") == std::string::npos) return nativeAiJson;
  if (nativeAiJson.find("\"attention\":") != std::string::npos) return nativeAiJson;
  std::string head = nativeAiJson.substr(0, end);
  size_t last = head.find_last_not_of(" \t\r\n");
  bool empty = last != std::string::npos && head[last] == '{';
  return head + (empty ? "" : ",") + "\"attention\":" + attnJson + "}";
}

// ------------------------------------------------------------------ abandoned_in_danger
enum PartnerState { PS_NONE = 0, PS_KNOCKED_OUT = 1, PS_BLEEDING_OUT = 2, PS_DOWNED = 3 };
inline const char *PartnerStateName(int s) {
  return s == PS_KNOCKED_OUT ? "knocked_out" : (s == PS_BLEEDING_OUT ? "bleeding_out" : (s == PS_DOWNED ? "downed" : "none"));
}
inline int ClassifyPartner(bool dead, bool unconscious, bool bleeding, int bloodPct, bool bloodlossTrauma, bool down) {
  if (dead) return PS_NONE;
  if (unconscious) return PS_KNOCKED_OUT;
  if (bloodlossTrauma || (bleeding && bloodPct >= 0 && bloodPct < 50)) return PS_BLEEDING_OUT;
  if (down) return PS_DOWNED;
  return PS_NONE;
}

struct AbandonEvent {
  std::string evidenceId, partnerState;
  float distanceM;
  int seconds;
  AbandonEvent() : distanceM(0), seconds(0) {}
};

class AbandonTracker {
public:
  static float ArmRadius() { return 25.0f; }
  static float FarRadius() { return 30.0f; }
  static double FarSeconds() { return 20.0; }
  static double GapSeconds() { return 10.0; }

  AbandonTracker() {}
  void Reset() { m_pairs.clear(); m_episode.clear(); }

  // Call for every squad member each scan: down=false ends the partner's episode.
  void NotePartnerState(unsigned partner, int state, double nowSec) {
    std::map<unsigned, Episode>::iterator it = m_episode.find(partner);
    if (state == PS_NONE) {
      if (it != m_episode.end()) {
        m_episode.erase(it);
        for (std::map<Key, Pair>::iterator p = m_pairs.begin(); p != m_pairs.end();) {
          if (p->first.second == partner) m_pairs.erase(p++); else ++p;
        }
      }
      return;
    }
    if (it == m_episode.end()) { Episode e; e.start = nowSec; m_episode[partner] = e; }
  }

  // One (leaver, partner) observation. Returns true once per episode when the abandonment is proven.
  bool Observe(unsigned leaver, unsigned partner, bool leaverFree, int partnerState, float dist, double nowSec,
               AbandonEvent *out) {
    if (!leaver || !partner || leaver == partner) return false;
    NotePartnerState(partner, partnerState, nowSec);
    if (partnerState == PS_NONE) return false;
    Episode &ep = m_episode[partner];
    Key key(leaver, partner);
    std::map<Key, Pair>::iterator it = m_pairs.find(key);
    if (it == m_pairs.end()) { Pair p; p.episodeStart = ep.start; it = m_pairs.insert(std::make_pair(key, p)).first; }
    Pair &p = it->second;
    if (p.episodeStart != ep.start) { p = Pair(); p.episodeStart = ep.start; }
    if (p.lastSeen >= 0 && (nowSec < p.lastSeen || nowSec - p.lastSeen > GapSeconds())) p.farSince = -1.0;
    p.lastSeen = nowSec;
    if (!leaverFree) { p.farSince = -1.0; return false; }
    if (dist <= ArmRadius()) p.armed = true;
    if (dist < FarRadius()) { p.farSince = -1.0; return false; }
    if (!p.armed || p.fired) return false;
    if (p.farSince < 0.0) { p.farSince = nowSec; return false; }
    if (nowSec - p.farSince < FarSeconds()) return false;
    p.fired = true;
    if (out) {
      char buf[96];
      sprintf(buf, "abandon:%u:%u:%lld", leaver, partner, (long long)ep.start);
      out->evidenceId = buf;
      out->partnerState = PartnerStateName(partnerState);
      out->distanceM = dist;
      out->seconds = (int)(nowSec - p.farSince);
    }
    return true;
  }

private:
  typedef std::pair<unsigned, unsigned> Key;
  struct Episode { double start; Episode() : start(0) {} };
  struct Pair {
    double episodeStart, farSince, lastSeen;
    bool armed, fired;
    Pair() : episodeStart(0), farSince(-1.0), lastSeen(-1.0), armed(false), fired(false) {}
  };
  std::map<Key, Pair> m_pairs;
  std::map<unsigned, Episode> m_episode;
};

// ------------------------------------------------------------------ proximity follow-up gate
// Decides when the native side fires the optional bored turn (server answers "ok" when nothing is claimable).
class ProximityGate {
public:
  static double GlobalMinSec() { return 90.0; }
  static double PerNpcMinSec() { return 600.0; }
  static double AwaySec() { return 45.0; }
  static float AwayDist() { return 30.0f; }
  static float NearCap() { return 15.0f; }
  static double LoadDelaySec() { return 8.0; }
  static double CombatDelaySec() { return 1.5; }
  static double CombatStaleSec() { return 10.0; }
  static float CombatPlayerRange() { return 60.0f; }
  static float CombatCompanionRange() { return 40.0f; }

  ProximityGate() : m_lastFire(-1e9), m_combatDue(-1.0) {}
  void Reset() { m_npc.clear(); m_lastFire = -1e9; m_combatDue = -1.0; }

  static float NearRadius(float talkRadius) { return talkRadius < NearCap() ? talkRadius : NearCap(); }

  // Rate limits: global and per NPC. Records the fire when allowed.
  bool TryFire(unsigned npc, double now) {
    if (now < m_lastFire) m_lastFire = -1e9;
    if (now - m_lastFire < GlobalMinSec()) return false;
    Npc &n = m_npc[npc];
    if (n.lastFire > -1e8 && now >= n.lastFire && now - n.lastFire < PerNpcMinSec()) return false;
    m_lastFire = now;
    n.lastFire = now;
    return true;
  }

  // Per companion, per scan (only call while the caller's gates are open). nearestPlayerDist = metres to
  // the nearest player character. Returns true when the proximity turn should fire for this companion now.
  bool OnScan(unsigned npc, double now, bool idle, float nearestPlayerDist, float talkRadius) {
    Npc &n = m_npc[npc];
    float nearR = NearRadius(talkRadius);
    bool nearNow = nearestPlayerDist <= nearR;
    if (!n.seen) {
      n.seen = true;
      if (nearNow) n.loadDue = now + LoadDelaySec();
    }
    if (nearestPlayerDist > AwayDist()) {
      if (n.farSince < 0.0) n.farSince = now;
      if (now - n.farSince >= AwaySec()) n.away = true;
    } else {
      n.farSince = -1.0;
    }
    if (!idle) return false;
    if (n.loadDue >= 0.0) {
      if (!nearNow) n.loadDue = -1.0;
      else if (now >= n.loadDue) {
        n.loadDue = -1.0;
        if (TryFire(npc, now)) return true;
        return false;
      }
    }
    if (n.away && nearNow) {
      n.away = false;
      n.farSince = -1.0;
      return TryFire(npc, now);
    }
    return false;
  }

  // A combat_start happened `nearestPlayerDist` metres from the nearest player character.
  void NoteCombatStart(double now, float nearestPlayerDist) {
    if (nearestPlayerDist > CombatPlayerRange()) return;
    if (m_combatDue < 0.0) m_combatDue = now + CombatDelaySec();
  }
  // True once when a pending combat trigger is due (and not stale). The caller then picks the nearest
  // companion within CombatCompanionRange() and calls TryFire().
  bool TakeCombatDue(double now) {
    if (m_combatDue < 0.0) return false;
    if (now < m_combatDue) return false;
    bool stale = now - m_combatDue > CombatStaleSec();
    m_combatDue = -1.0;
    return !stale;
  }
  bool CombatPending() const { return m_combatDue >= 0.0; }

private:
  struct Npc {
    bool seen, away;
    double farSince, loadDue, lastFire;
    Npc() : seen(false), away(false), farSince(-1.0), loadDue(-1.0), lastFire(-1e9) {}
  };
  std::map<unsigned, Npc> m_npc;
  double m_lastFire, m_combatDue;
};

} // namespace N2Policy
} // namespace Stobe
