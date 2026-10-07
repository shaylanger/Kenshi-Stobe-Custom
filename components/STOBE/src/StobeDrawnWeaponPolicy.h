#pragma once
// Drawn-weapon reactions (Shay, 2026-10-06): NPCs react when a player character
// has a weapon drawn near them and they can see it. This header is the
// per-(NPC, player) state machine only, with no Kenshi types, so the offline
// tests cover it (tests/cpp/drawn_weapon_policy_tests.cpp). StobeDrawnWeapon.cpp
// gathers the observation each tick and carries out the returned action.
//
// Stances:
//   friendly = neutral-or-better relation: one Stobe line about the weapon
//              (per-NPC cooldown);
//   guard    = a town guard with neutral-or-better relation: tells the player to
//              put it away (same cooldown);
//   hostile  = below neutral: a warning line, then an attack if the player keeps
//              the weapon drawn in sight within the radius for warnSeconds, or
//              closes in to attackDistance. Holstering cancels the warning.
//              Every warning gets a real warning period: closing in only counts
//              after minWarnSeconds and only if the player came closer than where
//              he stood at the warning (warned already inside attackDistance and
//              standing still = the warnSeconds timer, m50 DW5/DW4).
// Never: the player's own squad/faction, during existing combat, when the NPC
// can't see the player, or outside the radius.

namespace StobeDrawn {

enum Stance { STANCE_FRIENDLY = 0, STANCE_GUARD = 1, STANCE_HOSTILE = 2 };

enum Action {
  ACT_NONE = 0,
  ACT_SPEAK_FRIENDLY, // ask why the weapon is out
  ACT_SPEAK_GUARD,    // tell the player to put it away
  ACT_WARN,           // hostile: warning line, warning pending
  ACT_REARM,          // hostile: warning pending again without a new line (re-drawn inside the re-warn window)
  ACT_ATTACK,         // hostile: the warning ran out / the player closed in
  ACT_CANCEL_HOLSTER, // the pending warning ended: weapon put away
  ACT_CANCEL_LEFT,    // the pending warning ended: out of range/sight too long
  ACT_CANCEL_COMBAT   // the pending warning ended: combat started some other way
};

struct Config {
  bool enabled;
  float radius;          // game units (10 = ~1 m), react inside this distance
  float warnSeconds;     // hostile: seconds after the warning before attacking
  float attackDistance;  // hostile: closing in this far after the warning attacks at once
  float cooldownSeconds; // per NPC between two lines
  float rewarnSeconds;   // hostile: a re-draw inside this window re-arms without a new line
  float leaveGraceSeconds; // hostile: pending warning dropped after this long out of range/sight
  float minWarnSeconds;  // hostile: no attack of any kind sooner than this after the warning
  float closeMargin;     // hostile: closing in = this much nearer than at the warning (game units)
  Config()
      : enabled(true), radius(100.0f), warnSeconds(4.0f), attackDistance(30.0f),
        cooldownSeconds(90.0f), rewarnSeconds(20.0f), leaveGraceSeconds(6.0f), minWarnSeconds(1.0f),
        closeMargin(5.0f) {}
};

struct Observation {
  bool drawn;    // the player character has a weapon in hand
  bool sees;     // the NPC can see the player (native senses)
  float distance;
  bool combat;   // either side is already fighting
  bool ownSquad; // the NPC belongs to the player's faction
  Stance stance;
  double now;    // seconds, only advancing while the game runs
  Observation()
      : drawn(false), sees(false), distance(1e9f), combat(false), ownSquad(false),
        stance(STANCE_FRIENDLY), now(0.0) {}
};

struct PairState {
  bool warned;          // a hostile warning is pending
  double warnedAt;
  float warnDistance;   // distance when the (re)warning started
  double lastSpokeAt;   // last line (any stance); <0 = never
  double lastSeenInRangeAt;
  double lastCancelAt;  // last time a pending warning ended; <0 = never
  int lastAction;
  PairState()
      : warned(false), warnedAt(0.0), warnDistance(1e9f), lastSpokeAt(-1.0), lastSeenInRangeAt(0.0),
        lastCancelAt(-1.0), lastAction(ACT_NONE) {}
};

inline bool InRangeAndSeen(const Config &c, const Observation &o) {
  return o.drawn && o.sees && o.distance <= c.radius;
}

// One tick for one (NPC, player) pair. Mutates the state, returns what to do.
inline Action Step(const Config &c, PairState &s, const Observation &o) {
  Action a = ACT_NONE;
  if (!c.enabled || o.ownSquad) {
    s.warned = false;
    return ACT_NONE;
  }
  if (s.warned) {
    if (o.combat) {
      a = ACT_CANCEL_COMBAT;
    } else if (!o.drawn) {
      a = ACT_CANCEL_HOLSTER;
    } else if (InRangeAndSeen(c, o)) {
      s.lastSeenInRangeAt = o.now;
      const double since = o.now - s.warnedAt;
      const bool closedIn = o.distance <= c.attackDistance && o.distance < s.warnDistance - c.closeMargin;
      if (since >= c.warnSeconds || (since >= c.minWarnSeconds && closedIn))
        a = ACT_ATTACK;
    } else if (o.now - s.lastSeenInRangeAt >= c.leaveGraceSeconds) {
      a = ACT_CANCEL_LEFT;
    }
    if (a != ACT_NONE) {
      s.warned = false;
      if (a != ACT_ATTACK)
        s.lastCancelAt = o.now;
      s.lastAction = a;
    }
    return a;
  }
  if (o.combat || !InRangeAndSeen(c, o))
    return ACT_NONE;
  const bool cooling = s.lastSpokeAt >= 0.0 && o.now - s.lastSpokeAt < c.cooldownSeconds;
  if (o.stance == STANCE_HOSTILE) {
    // A pending warning that was just cancelled (holstered/left) and the weapon
    // comes out again: arm again at once, with no second line inside the window.
    const bool recent = s.lastCancelAt >= 0.0 && o.now - s.lastCancelAt < c.rewarnSeconds;
    if (cooling && !recent && s.lastAction != ACT_ATTACK)
      return ACT_NONE;
    if (s.lastAction == ACT_ATTACK && cooling)
      return ACT_NONE; // already attacked recently; the fight (or its end) is native now
    s.warned = true;
    s.warnedAt = o.now;
    s.warnDistance = o.distance;
    s.lastSeenInRangeAt = o.now;
    if (cooling && recent) {
      a = ACT_REARM;
    } else {
      a = ACT_WARN;
      s.lastSpokeAt = o.now;
    }
    s.lastAction = a;
    return a;
  }
  if (cooling)
    return ACT_NONE;
  s.lastSpokeAt = o.now;
  a = o.stance == STANCE_GUARD ? ACT_SPEAK_GUARD : ACT_SPEAK_FRIENDLY;
  s.lastAction = a;
  return a;
}

inline const char *ActionName(int a) {
  switch (a) {
  case ACT_SPEAK_FRIENDLY: return "speak_friendly";
  case ACT_SPEAK_GUARD: return "speak_guard";
  case ACT_WARN: return "warn";
  case ACT_REARM: return "rearm";
  case ACT_ATTACK: return "attack";
  case ACT_CANCEL_HOLSTER: return "cancel_holstered";
  case ACT_CANCEL_LEFT: return "cancel_left";
  case ACT_CANCEL_COMBAT: return "cancel_combat";
  default: return "none";
  }
}

inline const char *StanceName(int s) {
  return s == STANCE_HOSTILE ? "hostile" : s == STANCE_GUARD ? "guard" : "friendly";
}

} // namespace StobeDrawn
