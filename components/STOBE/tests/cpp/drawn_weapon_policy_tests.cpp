// Drawn-weapon reactions (StobeDrawnWeaponPolicy.h): speak once per cooldown, hostile warn -> attack,
// holster cancels, own squad / combat / not seen / out of range never react.
#include "StobeDrawnWeaponPolicy.h"

#include <cstdio>
#include <stdexcept>
#include <string>

using namespace StobeDrawn;

static int g_checks = 0;
static void check(bool ok, const std::string &what) {
  ++g_checks;
  if (!ok) throw std::runtime_error(what);
}

static Observation Obs(double now, Stance st, float dist, bool drawn = true, bool sees = true) {
  Observation o;
  o.now = now;
  o.stance = st;
  o.distance = dist;
  o.drawn = drawn;
  o.sees = sees;
  return o;
}

int main() {
  try {
    Config c; // radius 100, warn 4 s, attack distance 30, cooldown 90, rewarn 20, leave grace 6

    { // friendly: one line, then the cooldown
      PairState s;
      check(Step(c, s, Obs(0, STANCE_FRIENDLY, 80)) == ACT_SPEAK_FRIENDLY, "friendly speaks");
      check(Step(c, s, Obs(1, STANCE_FRIENDLY, 50)) == ACT_NONE, "friendly cooldown");
      check(Step(c, s, Obs(89, STANCE_FRIENDLY, 50)) == ACT_NONE, "friendly cooldown 89 s");
      check(Step(c, s, Obs(91, STANCE_FRIENDLY, 50)) == ACT_SPEAK_FRIENDLY, "friendly again after cooldown");
    }
    { // guard
      PairState s;
      check(Step(c, s, Obs(0, STANCE_GUARD, 60)) == ACT_SPEAK_GUARD, "guard tells to put it away");
      check(!s.warned, "guard never arms an attack");
      check(Step(c, s, Obs(10, STANCE_GUARD, 10)) == ACT_NONE, "guard cooldown, no attack");
    }
    { // gates
      PairState s;
      check(Step(c, s, Obs(0, STANCE_FRIENDLY, 80, false)) == ACT_NONE, "holstered: nothing");
      check(Step(c, s, Obs(0, STANCE_FRIENDLY, 80, true, false)) == ACT_NONE, "not seen: nothing");
      check(Step(c, s, Obs(0, STANCE_FRIENDLY, 101)) == ACT_NONE, "out of radius: nothing");
      Observation o = Obs(0, STANCE_HOSTILE, 50);
      o.ownSquad = true;
      check(Step(c, s, o) == ACT_NONE, "own squad: nothing");
      o.ownSquad = false;
      o.combat = true;
      check(Step(c, s, o) == ACT_NONE, "combat: nothing");
      Config off;
      off.enabled = false;
      check(Step(off, s, Obs(0, STANCE_HOSTILE, 50)) == ACT_NONE, "disabled: nothing");
      check(s.lastSpokeAt < 0, "gates leave no cooldown behind");
    }
    { // hostile: warn, keep the weapon out in range -> attack after warnSeconds
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 80)) == ACT_WARN, "hostile warns");
      check(s.warned, "warning pending");
      check(Step(c, s, Obs(2, STANCE_HOSTILE, 70)) == ACT_NONE, "still inside the warn time");
      check(Step(c, s, Obs(4.1, STANCE_HOSTILE, 70)) == ACT_ATTACK, "attack after warn seconds");
      check(!s.warned, "attack ends the warning");
      check(Step(c, s, Obs(5, STANCE_HOSTILE, 70)) == ACT_NONE, "no second warning right after the attack");
    }
    { // hostile: closing in attacks at once
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 90)) == ACT_WARN, "warn");
      check(Step(c, s, Obs(1, STANCE_HOSTILE, 29)) == ACT_ATTACK, "closing to attack distance attacks at once");
    }
    { // hostile: holster cancels, re-draw re-arms silently inside the window, then attacks
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 80)) == ACT_WARN, "warn");
      check(Step(c, s, Obs(2, STANCE_HOSTILE, 80, false)) == ACT_CANCEL_HOLSTER, "holster cancels");
      check(!s.warned, "no warning pending after holster");
      check(Step(c, s, Obs(10, STANCE_HOSTILE, 80, false)) == ACT_NONE, "stays holstered: no attack");
      check(Step(c, s, Obs(12, STANCE_HOSTILE, 80)) == ACT_REARM, "re-draw inside the window re-arms without a line");
      check(Step(c, s, Obs(16.5, STANCE_HOSTILE, 80)) == ACT_ATTACK, "re-armed warning runs out -> attack");
    }
    { // hostile: re-draw after the re-warn window but inside the cooldown -> nothing; after cooldown -> warn
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 80)) == ACT_WARN, "warn");
      check(Step(c, s, Obs(1, STANCE_HOSTILE, 80, false)) == ACT_CANCEL_HOLSTER, "holster");
      check(Step(c, s, Obs(30, STANCE_HOSTILE, 80)) == ACT_NONE, "outside the re-warn window, still cooling");
      check(Step(c, s, Obs(95, STANCE_HOSTILE, 80)) == ACT_WARN, "warns again after the cooldown");
    }
    { // hostile: walking away / out of sight drops the warning after the grace time
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 80)) == ACT_WARN, "warn");
      check(Step(c, s, Obs(3, STANCE_HOSTILE, 150)) == ACT_NONE, "out of range, grace");
      check(Step(c, s, Obs(5, STANCE_HOSTILE, 80, true, false)) == ACT_NONE, "out of sight, grace");
      check(Step(c, s, Obs(6.5, STANCE_HOSTILE, 150)) == ACT_CANCEL_LEFT, "left -> cancel");
    }
    { // hostile: combat starting some other way cancels
      PairState s;
      check(Step(c, s, Obs(0, STANCE_HOSTILE, 80)) == ACT_WARN, "warn");
      Observation o = Obs(1, STANCE_HOSTILE, 80);
      o.combat = true;
      check(Step(c, s, o) == ACT_CANCEL_COMBAT, "combat cancels");
    }
    std::printf("drawn_weapon_policy_tests: %d checks passed\n", g_checks);
    return 0;
  } catch (const std::exception &e) {
    std::printf("drawn_weapon_policy_tests FAILED after %d checks: %s\n", g_checks, e.what());
    return 1;
  }
}
