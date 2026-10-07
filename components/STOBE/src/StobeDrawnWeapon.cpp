// Drawn-weapon reactions. See StobeDrawnWeapon.h (behaviour, settings) and
// StobeDrawnWeaponPolicy.h (the per-pair state machine, offline-tested).
#include "StobeDrawnWeapon.h"

#include "ChatBox.h"
#include "Functions.h"
#include "ShopPriceHook.h"
#include "StobeDrawnWeaponPolicy.h"
#include "Utils.h"

#include <core/Functions.h>
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/CharacterHuman.h>
#include <kenshi/Enums.h>
#include <kenshi/Faction.h>
#include <kenshi/GameWorld.h>
#include <kenshi/Gear.h>
#include <kenshi/Item.h>
#include <kenshi/PlayerInterface.h>
#include <kenshi/RootObject.h>
#include <kenshi/SensoryData.h>
#include <kenshi/util/hand.h>

#include <cctype>
#include <stdint.h>
#include <cstdlib>
#include <map>
#include <set>
#include <windows.h>

namespace Stobe {
namespace DrawnWeapon {
namespace {

using namespace StobeDrawn;

Config g_cfg;
float g_hostileBelow = 0.0f; // faction relation / Stobe relationship below this = hostile stance
float g_minFov = -1.0f;      // optional: SeenSomeone::FOVScore must be at least this (-1 = native sight only)
const DWORD kScanMs = 250;
const double kSpeechGapSeconds = 3.0; // at most one reaction line every 3 s, all NPCs together

struct Pair {
  PairState s;
  std::string npcName, playerName;
  unsigned int npcSerial, playerSerial;
  int stance;
  float dist, fov, relFaction;
  int relStobe; // -999 = unknown
  bool sees, combat;
  bool attackIssued;
  bool attackConfirmed;
  Pair()
      : npcSerial(0), playerSerial(0), stance(STANCE_FRIENDLY), dist(-1.0f), fov(-1.0f),
        relFaction(0.0f), relStobe(-999), sees(false), combat(false), attackIssued(false),
        attackConfirmed(false) {}
};

std::map<unsigned long long, Pair> g_pairs;
std::set<unsigned int> g_hold; // test aid: player serials kept drawn
double g_clock = 0.0;
DWORD g_lastTick = 0, g_lastScan = 0;
double g_lastSpeechAt = -1000.0;
int g_counts[16] = {0};
std::string g_last = "none";

unsigned int SerialOf(Character *c) {
  try {
    return c ? c->getHandle().serial : 0;
  } catch (...) {
    return 0;
  }
}

std::string NameOf(RootObjectBase *c) {
  try {
    return c ? c->getName() : std::string();
  } catch (...) {
    return std::string();
  }
}

std::string Lower(std::string s) {
  for (size_t i = 0; i < s.size(); ++i)
    s[i] = (char)tolower((unsigned char)s[i]);
  return s;
}

std::string F1(float v) {
  char b[32];
  _snprintf(b, sizeof(b), "%.1f", v);
  b[sizeof(b) - 1] = 0;
  return b;
}

Weapon *WeaponInHands(Character *c) {
  try {
    CharacterHuman *h = c ? c->isHuman() : nullptr;
    if (!h || (uintptr_t)h < 0x1000)
      return nullptr;
    Weapon *w = h->weaponInHands;
    return w && (uintptr_t)w > 0x1000 ? w : nullptr;
  } catch (...) {
    return nullptr;
  }
}

bool IsPlayerFaction(Character *c) {
  try {
    Faction *f = c ? c->getFaction() : nullptr;
    return f && (uintptr_t)f > 0x1000 && f->isThePlayer();
  } catch (...) {
    return false;
  }
}

bool HasAttackTarget(Character *c) {
  try {
    hand t = c->getAttackTarget();
    return t.isValid() && !t.isNull();
  } catch (...) {
    return false;
  }
}

Character *AttackTargetOf(Character *c) {
  try {
    hand t = c->getAttackTarget();
    if (t.isValid() && !t.isNull())
      return t.getCharacter();
  } catch (...) {
  }
  return nullptr;
}

bool IsGuard(Character *npc) {
  std::string n = Lower(NameOf(npc));
  if (n.find("guard") != std::string::npos || n.find("samurai") != std::string::npos ||
      n.find("sentinel") != std::string::npos || n.find("watchman") != std::string::npos)
    return true;
  try {
    OrdersReceiver *orders = npc->getOrdersReciever();
    if (orders && (uintptr_t)orders > 0x1000 && orders->currentGoal.taskData) {
      TaskType t = orders->currentGoal.key();
      return t == STAND_AT_GUARD_NODE_HOMEBUILDING_IN_OUT || t == STAND_AT_BUILDING_GUARD_NODE ||
             t == STAND_AT_GUARD_NODE_HOMETOWN_OUTSIDE || t == STAND_AT_GUARD_NODE_HOMEBUILDING_INDOORS_ONLY ||
             t == PATROL_TOWN || t == MAN_THE_GATE;
    }
  } catch (...) {
  }
  return false;
}

// Native senses: canISeeThisGuy (the AI's own sight: range, view, stealth), its FOV score for the log.
bool Sees(Character *npc, Character *player, float &fov) {
  fov = -1.0f;
  try {
    SensoryData *sd = npc->getSensoryData();
    if (!sd || (uintptr_t)sd < 0x1000)
      return false;
    bool sees = sd->canISeeThisGuy(player);
    SeenSomeone *s = sd->getDataFor(player);
    if (s && (uintptr_t)s > 0x1000)
      fov = s->FOVScore;
    if (sees && g_minFov >= 0.0f && fov < g_minFov)
      return false;
    return sees;
  } catch (...) {
    return false;
  }
}

int ResolveStance(Character *npc, Character *player, Pair &p) {
  bool enemy = false, ceasefire = false;
  p.relFaction = 0.0f;
  try {
    SensoryData *sd = npc->getSensoryData();
    if (sd && (uintptr_t)sd > 0x1000)
      p.relFaction = sd->getFactionRelation(player);
  } catch (...) {
  }
  try {
    enemy = npc->isEnemy(player, true);
  } catch (...) {
  }
  try {
    ceasefire = ShouldTreatFactionCeasefireTargetAsNeutral(npc, (RootObjectBase *)player);
  } catch (...) {
  }
  int r = 0;
  p.relStobe = Stobe::ShopPrice::RelationshipR(npc, player, r) ? r : -999; // cached; queues a fetch
  const bool hostile =
      !ceasefire && (enemy || p.relFaction < g_hostileBelow || (p.relStobe != -999 && p.relStobe < g_hostileBelow));
  if (hostile)
    return STANCE_HOSTILE;
  return IsGuard(npc) ? STANCE_GUARD : STANCE_FRIENDLY;
}

void Attack(Character *npc, Character *player) {
  BreakFactionCeasefireForExplicitAttack(npc, player, "drawn_weapon");
  BreakPersonalTruceForExplicitAttack(npc, player, "drawn_weapon");
  npc->attackTarget(player);
  npc->addGoal(MELEE_ATTACK, (RootObjectBase *)player);
  npc->reThinkCurrentAIAction();
}

std::string PairLine(const Pair &p) {
  return "npc=" + p.npcName + " player=" + p.playerName + " stance=" + StanceName(p.stance) + " dist=" + F1(p.dist) +
         " sees=" + (p.sees ? "1" : "0") + " fov=" + F1(p.fov) + " rel=" + F1(p.relFaction) +
         " r=" + (p.relStobe == -999 ? std::string("?") : ToString(p.relStobe)) +
         " warned=" + (p.s.warned ? "1" : "0") + " last=" + ActionName(p.s.lastAction);
}

void Carry(GameWorld *world, Pair &p, Action a, Character *npc, Character *player, Weapon *weapon) {
  if (a == ACT_NONE)
    return;
  ++g_counts[a];
  std::string weaponName = NameOf((RootObjectBase *)weapon);
  if (weaponName.empty())
    weaponName = "weapon";
  std::string extra;
  if (a == ACT_SPEAK_FRIENDLY || a == ACT_SPEAK_GUARD || a == ACT_WARN) {
    const char *kind = a == ACT_WARN ? "warn" : a == ACT_SPEAK_GUARD ? "guard" : "friendly";
    g_lastSpeechAt = g_clock;
    bool sent = false;
    try {
      sent = Stobe::UI::TriggerReactionTurn(world, npc, player, "drawn_weapon", kind, weaponName, (int)p.dist);
    } catch (...) {
      sent = false;
    }
    extra = std::string(" kind=") + kind + " weapon=" + weaponName + " speech=" + (sent ? "sent" : "failed");
  } else if (a == ACT_ATTACK) {
    bool done = false;
    try {
      if (npc && player) {
        Attack(npc, player);
        done = true;
      }
    } catch (...) {
      done = false;
    }
    p.attackIssued = done;
    extra += " since_warn=" + F1((float)(g_clock - p.s.warnedAt)) + " warn_dist=" + F1(p.s.warnDistance);
    p.attackConfirmed = false;
    extra = std::string(" weapon=") + weaponName + " order=" + (done ? "1" : "0");
  }
  g_last = std::string(ActionName(a)) + ":" + p.npcName + "@" + F1((float)g_clock);
  Log(std::string("DRAWN_WEAPON: ") + ActionName(a) + " " + PairLine(p) + extra + " t=" + F1((float)g_clock));
}

void Scan(GameWorld *world) {
  PlayerInterface *pi = world->player;
  if (!pi || (uintptr_t)pi < 0x1000)
    return;
  std::map<unsigned int, std::pair<Character *, Weapon *> > players; // serial -> (char, weapon in hand)
  for (uint32_t i = 0; i < pi->playerCharacters.size(); ++i) {
    Character *pc = pi->playerCharacters[i];
    if (!pc || (uintptr_t)pc < 0x1000)
      continue;
    unsigned int ps = SerialOf(pc);
    if (!ps)
      continue;
    Weapon *w = WeaponInHands(pc);
    if (!w && g_hold.count(ps)) { // test aid: keep it drawn
      try {
        Weapon *pref = pc->getThePreferredWeapon();
        if (pref)
          pc->drawWeapon((Item *)pref, std::string(""));
      } catch (...) {
      }
      w = WeaponInHands(pc);
    }
    players[ps] = std::make_pair(pc, w);
  }
  std::set<unsigned long long> visited;
  for (std::map<unsigned int, std::pair<Character *, Weapon *> >::iterator it = players.begin(); it != players.end();
       ++it) {
    Character *pc = it->second.first;
    Weapon *weapon = it->second.second;
    if (!weapon)
      continue;
    bool pcDead = false;
    try {
      pcDead = pc->isDead() || pc->isUnconcious();
    } catch (...) {
      pcDead = true;
    }
    if (pcDead)
      continue;
    lektor<RootObject *> nearby;
    try {
      world->getCharactersWithinSphere(nearby, pc->getPosition(), g_cfg.radius * 1.5f, 0.0f, 0.0f, 24, 0, pc);
    } catch (...) {
      continue;
    }
    const bool pcCombat = HasAttackTarget(pc);
    for (uint32_t i = 0; i < nearby.size(); ++i) {
      Character *npc = (Character *)nearby.stuff[i];
      if (!npc || (uintptr_t)npc < 0x1000 || npc == pc)
        continue;
      unsigned int ns = SerialOf(npc);
      if (!ns)
        continue;
      try {
        if (!npc->isHuman() || npc->isDead() || npc->isUnconcious())
          continue; // animals don't talk about weapons; KO/dead see nothing
      } catch (...) {
        continue;
      }
      if (IsPlayerFaction(npc))
        continue; // own squad: never tracked, no pair record (m50 DW7)
      const unsigned long long key = ((unsigned long long)ns << 32) | it->first;
      Pair &p = g_pairs[key];
      visited.insert(key);
      p.npcSerial = ns;
      p.playerSerial = it->first;
      p.npcName = NameOf(npc);
      p.playerName = NameOf(pc);
      Observation o;
      o.now = g_clock;
      o.drawn = true;
      o.ownSquad = false;
      try {
        o.distance = npc->getPosition().distance(pc->getPosition());
      } catch (...) {
        o.distance = 1e9f;
      }
      p.dist = o.distance;
      bool npcCombat = HasAttackTarget(npc);
      try {
        npcCombat = npcCombat || npc->isInCombatMode(true, true);
      } catch (...) {
      }
      if (p.attackIssued && !p.attackConfirmed && AttackTargetOf(npc) == pc) {
        p.attackConfirmed = true;
        Log("DRAWN_WEAPON: attack_confirmed " + PairLine(p) + " t=" + F1((float)g_clock));
      }
      o.combat = pcCombat || npcCombat;
      p.combat = o.combat;
      o.sees = o.distance <= g_cfg.radius && Sees(npc, pc, p.fov);
      p.sees = o.sees;
      if (o.sees && !o.combat)
        p.stance = ResolveStance(npc, pc, p);
      o.stance = (StobeDrawn::Stance)p.stance;
      // One line at a time: a new line waits for the gap (a pending warning always steps).
      if (!p.s.warned && g_clock - g_lastSpeechAt < kSpeechGapSeconds)
        continue;
      Action a = Step(g_cfg, p.s, o);
      Carry(world, p, a, npc, pc, weapon);
    }
  }
  // Pending warnings not seen this scan: holstered, out of range, the player gone.
  for (std::map<unsigned long long, Pair>::iterator it = g_pairs.begin(); it != g_pairs.end(); ++it) {
    Pair &p = it->second;
    if (!p.s.warned || visited.count(it->first))
      continue;
    std::map<unsigned int, std::pair<Character *, Weapon *> >::iterator pl = players.find(p.playerSerial);
    Observation o;
    o.now = g_clock;
    o.drawn = pl != players.end() && pl->second.second != nullptr;
    o.sees = false;
    o.distance = 1e9f;
    o.stance = (StobeDrawn::Stance)p.stance;
    p.sees = false;
    Action a = Step(g_cfg, p.s, o);
    Carry(world, p, a, nullptr, nullptr, pl != players.end() ? pl->second.second : nullptr);
  }
  if (g_pairs.size() > 512) { // forget idle pairs whose cooldown ran out
    for (std::map<unsigned long long, Pair>::iterator it = g_pairs.begin(); it != g_pairs.end();) {
      if (!it->second.s.warned && (it->second.s.lastSpokeAt < 0 || g_clock - it->second.s.lastSpokeAt > g_cfg.cooldownSeconds))
        g_pairs.erase(it++);
      else
        ++it;
    }
  }
}

float ParseF(const std::string &s, float def) {
  if (s.empty())
    return def;
  char *end = nullptr;
  double v = strtod(s.c_str(), &end);
  return end && end != s.c_str() ? (float)v : def;
}

std::string ConfigLine() {
  return std::string("enabled=") + (g_cfg.enabled ? "1" : "0") + " radius=" + F1(g_cfg.radius) +
         " warn=" + F1(g_cfg.warnSeconds) + " attack_dist=" + F1(g_cfg.attackDistance) +
         " min_warn=" + F1(g_cfg.minWarnSeconds) + " close_margin=" + F1(g_cfg.closeMargin) +
         " cooldown=" + F1(g_cfg.cooldownSeconds) + " rewarn=" + F1(g_cfg.rewarnSeconds) +
         " hostile_below=" + F1(g_hostileBelow) + " min_fov=" + F1(g_minFov) + " units=game(10=1m)";
}

} // namespace

void LoadConfig(IniStringFn read) {
  g_cfg.enabled = ParseF(read("DrawnWeapon", "Enabled", "1"), 1.0f) != 0.0f;
  g_cfg.radius = ParseF(read("DrawnWeapon", "Radius", "100"), 100.0f);
  g_cfg.warnSeconds = ParseF(read("DrawnWeapon", "WarnSeconds", "4"), 4.0f);
  g_cfg.attackDistance = ParseF(read("DrawnWeapon", "AttackDistance", "30"), 30.0f);
  g_cfg.cooldownSeconds = ParseF(read("DrawnWeapon", "CooldownSeconds", "90"), 90.0f);
  g_cfg.rewarnSeconds = ParseF(read("DrawnWeapon", "RewarnSeconds", "20"), 20.0f);
  g_cfg.minWarnSeconds = ParseF(read("DrawnWeapon", "MinWarnSeconds", "1"), 1.0f);
  g_cfg.closeMargin = ParseF(read("DrawnWeapon", "CloseMargin", "5"), 5.0f);
  g_hostileBelow = ParseF(read("DrawnWeapon", "HostileRelationBelow", "0"), 0.0f);
  g_minFov = ParseF(read("DrawnWeapon", "MinFovScore", "-1"), -1.0f);
  if (g_cfg.radius < 10.0f)
    g_cfg.radius = 10.0f;
  Log("CONFIG: DrawnWeapon " + ConfigLine());
}

void Reset() {
  g_pairs.clear();
  g_lastSpeechAt = -1000.0;
}

void Update(GameWorld *world) {
  DWORD now = GetTickCount();
  DWORD dt = g_lastTick ? now - g_lastTick : 0;
  g_lastTick = now;
  if (!world || (uintptr_t)world < 0x1000)
    return;
  bool paused = true;
  try {
    paused = world->isPaused();
  } catch (...) {
  }
  if (!paused && dt < 1000) // the reaction clock only runs while the game does
    g_clock += dt / 1000.0;
  if (!g_cfg.enabled && g_hold.empty())
    return;
  if (paused || now - g_lastScan < kScanMs)
    return;
  g_lastScan = now;
  try {
    Scan(world);
  } catch (...) {
    Log("DRAWN_WEAPON: scan exception");
  }
}

std::string TestCommand(GameWorld *world, Character *sel, const std::vector<std::string> &f, bool &ok,
                        Character *(*resolve)(GameWorld *, Character *, const std::string &)) {
  ok = false;
  const std::string sub = f.size() >= 3 ? f[2] : "status";
  if (sub == "status") {
    std::string drawn;
    if (world && world->player) {
      for (uint32_t i = 0; i < world->player->playerCharacters.size(); ++i) {
        Character *pc = world->player->playerCharacters[i];
        Weapon *w = WeaponInHands(pc);
        if (w)
          drawn += (drawn.empty() ? "" : ",") + NameOf(pc) + ":" + NameOf((RootObjectBase *)w);
      }
    }
    int warned = 0;
    for (std::map<unsigned long long, Pair>::iterator it = g_pairs.begin(); it != g_pairs.end(); ++it)
      warned += it->second.s.warned ? 1 : 0;
    ok = true;
    return ConfigLine() + " drawn=" + (drawn.empty() ? "none" : drawn) + " pairs=" + ToString((int)g_pairs.size()) +
           " warned=" + ToString(warned) + " speak=" + ToString(g_counts[ACT_SPEAK_FRIENDLY]) +
           " guard=" + ToString(g_counts[ACT_SPEAK_GUARD]) + " warn=" + ToString(g_counts[ACT_WARN]) +
           " rearm=" + ToString(g_counts[ACT_REARM]) + " attack=" + ToString(g_counts[ACT_ATTACK]) +
           " cancel_holstered=" + ToString(g_counts[ACT_CANCEL_HOLSTER]) +
           " cancel_left=" + ToString(g_counts[ACT_CANCEL_LEFT]) +
           " cancel_combat=" + ToString(g_counts[ACT_CANCEL_COMBAT]) + " last=" + g_last +
           " t=" + F1((float)g_clock);
  }
  if (sub == "reset") { // forget per-NPC state, cooldowns and counters
    Reset();
    for (int i = 0; i < 16; ++i)
      g_counts[i] = 0;
    g_last = "none";
    ok = true;
    return "reset " + ConfigLine();
  }
  if (sub == "set") { // set <enabled|radius|warn|attack_dist|cooldown|rewarn|hostile_below|min_fov> <value>
    if (f.size() < 5)
      return "usage: drawn set <enabled|radius|warn|attack_dist|cooldown|rewarn|hostile_below|min_fov> <value>";
    const std::string k = f[3];
    const float v = ParseF(f[4], -12345.0f);
    if (v == -12345.0f)
      return "bad value: " + f[4];
    if (k == "enabled") g_cfg.enabled = v != 0.0f;
    else if (k == "radius") g_cfg.radius = v < 10.0f ? 10.0f : v;
    else if (k == "warn") g_cfg.warnSeconds = v;
    else if (k == "attack_dist") g_cfg.attackDistance = v;
    else if (k == "cooldown") g_cfg.cooldownSeconds = v;
    else if (k == "rewarn") g_cfg.rewarnSeconds = v;
    else if (k == "min_warn") g_cfg.minWarnSeconds = v;
    else if (k == "close_margin") g_cfg.closeMargin = v;
    else if (k == "hostile_below") g_hostileBelow = v;
    else if (k == "min_fov") g_minFov = v;
    else return "unknown key: " + k;
    Log("DRAWN_WEAPON: set " + k + "=" + f[4] + " (test command)");
    ok = true;
    return ConfigLine();
  }
  if (sub == "draw" || sub == "sheathe" || sub == "hold") { // draw|sheathe <char>, hold <char> on|off
    if (f.size() < 4)
      return "usage: drawn draw|sheathe <char> / drawn hold <char> on|off";
    Character *c = resolve(world, sel, f[3]);
    if (!c)
      return "target not found: " + f[3];
    if (sub == "hold") {
      const bool on = f.size() < 5 || f[4] != "off";
      if (on) g_hold.insert(SerialOf(c));
      else g_hold.erase(SerialOf(c));
    }
    try {
      if (sub == "sheathe" || (sub == "hold" && f.size() >= 5 && f[4] == "off")) {
        if (WeaponInHands(c))
          c->sheatheWeapon();
      } else if (!WeaponInHands(c)) {
        Weapon *pref = c->getThePreferredWeapon();
        if (!pref)
          return NameOf(c) + " has no weapon to draw";
        c->drawWeapon((Item *)pref, std::string(""));
      }
    } catch (...) {
      return "draw/sheathe exception";
    }
    Weapon *w = WeaponInHands(c);
    Log("DRAWN_WEAPON: test " + sub + " " + NameOf(c) + " drawn=" + (w ? "1" : "0"));
    ok = true;
    return NameOf(c) + " drawn=" + (w ? "1" : "0") + " weapon=" + (w ? NameOf((RootObjectBase *)w) : std::string("none")) +
           " hold=" + (g_hold.count(SerialOf(c)) ? "1" : "0");
  }
  if (sub == "pair") { // pair <npc>: what the reaction state says about her (every player character)
    if (f.size() < 4)
      return "usage: drawn pair <npc>";
    Character *n = resolve(world, sel, f[3]);
    if (!n)
      return "target not found: " + f[3];
    const unsigned int ns = SerialOf(n);
    std::string out;
    for (std::map<unsigned long long, Pair>::iterator it = g_pairs.begin(); it != g_pairs.end(); ++it) {
      if (it->second.npcSerial != ns)
        continue;
      if (!out.empty())
        out += " | ";
      out += PairLine(it->second) + " attack_issued=" + (it->second.attackIssued ? "1" : "0");
    }
    Character *t = AttackTargetOf(n);
    ok = true;
    return (out.empty() ? "npc=" + NameOf(n) + " no_pair" : out) +
           " attack_target=" + (t ? NameOf(t) : std::string("none"));
  }
  return "usage: drawn <status|draw <char>|sheathe <char>|hold <char> on|off|reset|set <key> <value>|pair <npc>>";
}

} // namespace DrawnWeapon
} // namespace Stobe
