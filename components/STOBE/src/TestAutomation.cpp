// Test automation commands (TEST ONLY): load/save games, spawn characters,
// move, hurt or knock out anyone, set hunger and faction relations.
//
// Active only while mods\Stobe\test_inbox.flag exists (same switch as the
// chat test inbox). Tooling writes auto_inbox.txt (id<TAB>command<TAB>args,
// one per line); the DLL consumes it on the game thread and appends
// id<TAB>ok|error<TAB>detail lines to auto_outbox.txt. Commands run from the
// Ogre frame listener, so load/status also work at the main menu.
// autoload.txt (one save name) is loaded once the main menu is up.
#ifndef NOMINMAX
#define NOMINMAX // OgreRoot.h uses std::min/max
#endif
#include "TestAutomation.h"

#include <core/Functions.h>
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/Damages.h>
#include <kenshi/Faction.h>
#include <kenshi/FactionRelations.h>
#include <kenshi/GameData.h>
#include <kenshi/GameWorld.h>
#include <kenshi/Globals.h> // ou
#include <kenshi/Inventory.h>
#include <kenshi/Item.h>
#include <kenshi/Kenshi.h>
#include <kenshi/MedicalSystem.h>
#include <kenshi/Platoon.h>
#include <kenshi/PlayerInterface.h>
#include <kenshi/RootObjectFactory.h>
#include <kenshi/SaveManager.h>
#include <kenshi/util/hand.h>
#include <mygui/MyGUI_Delegate.h>
#include <mygui/MyGUI_Gui.h>
#include <ogre/OgreFrameListener.h>
#include <ogre/OgreRenderSystem.h>
#include <ogre/OgreRenderWindow.h>
#include <ogre/OgreRoot.h>

#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "AutonomySafetyProbe.h" // GetTestInboxDir
#include "Context.h"             // BuildInventorySnapshot
#include "Functions.h"           // BreakFactionCeasefireForExplicitAttack
#include "Utils.h"               // Log

namespace {

DWORD g_lastPoll = 0;
bool g_loggedFirstTick = false;

std::string Lower(const std::string &value) {
  std::string out = value;
  for (size_t i = 0; i < out.size(); ++i)
    out[i] = (char)tolower((unsigned char)out[i]);
  return out;
}

std::string OneLine(const std::string &value) {
  std::string out = value;
  for (size_t i = 0; i < out.size(); ++i)
    if (out[i] == '\r' || out[i] == '\n' || out[i] == '\t')
      out[i] = ' ';
  return out;
}

std::string Num(double v) {
  std::ostringstream s;
  s.setf(std::ios::fixed);
  s.precision(1);
  s << v;
  return s.str();
}

std::string Int(long long v) {
  std::ostringstream s;
  s << v;
  return s.str();
}

bool Valid(const void *p) { return p && (uintptr_t)p > 0x10000; }

bool FileExists(const std::string &path) {
  return GetFileAttributesA(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

PlayerInterface *Player(GameWorld *world) {
  return (Valid(world) && Valid(world->player)) ? world->player : nullptr;
}

bool InWorld(GameWorld *world) {
  PlayerInterface *player = Player(world);
  return player && player->playerCharacters.size() > 0;
}

Character *FirstPlayerCharacter(GameWorld *world) {
  PlayerInterface *player = Player(world);
  if (!player || player->playerCharacters.size() == 0)
    return nullptr;
  return player->playerCharacters[0];
}

// Every live character, plus characters (incl. dead bodies, which drop out of
// the update list) within `radius` of `origin`.
void CollectCharacters(GameWorld *world, const Ogre::Vector3 &origin, float radius,
                       std::vector<Character *> &out) {
  const ogre_unordered_set<Character *>::type &chars = world->getCharacterUpdateList();
  for (ogre_unordered_set<Character *>::type::const_iterator it = chars.begin();
       it != chars.end(); ++it)
    if (Valid(*it))
      out.push_back(*it);
  lektor<RootObject *> nearby;
  try {
    world->getObjectsWithinSphere(nearby, origin, radius, CHARACTER, 256, nullptr);
  } catch (...) {
    return;
  }
  for (uint32_t i = 0; i < nearby.size(); ++i) {
    Character *c = dynamic_cast<Character *>(nearby.stuff[i]);
    if (Valid(c) && std::find(out.begin(), out.end(), c) == out.end())
      out.push_back(c);
  }
}

// "@player" (first squad member), "@selected", or a name: exact
// (case-insensitive) match nearest the player wins, else nearest substring.
Character *FindCharacter(GameWorld *world, const std::string &name) {
  if (!InWorld(world))
    return nullptr;
  Character *player = FirstPlayerCharacter(world);
  if (name == "@player")
    return player;
  if (name == "@selected") {
    Character *sel = nullptr;
    try {
      sel = dynamic_cast<Character *>(world->player->selectedCharacter.getRootObject());
    } catch (...) {
      sel = nullptr;
    }
    return sel;
  }
  Ogre::Vector3 origin(0, 0, 0);
  if (Valid(player)) {
    try {
      origin = player->getPosition();
    } catch (...) {
    }
  }
  const std::string wanted = Lower(name);
  const bool bySerial = !name.empty() && name[0] == '#';
  const unsigned long serial = bySerial ? strtoul(name.c_str() + 1, nullptr, 10) : 0;
  Character *exact = nullptr, *partial = nullptr;
  float exactDist = 0, partialDist = 0;
  std::vector<Character *> chars;
  CollectCharacters(world, origin, 500.0f, chars);
  for (size_t i = 0; i < chars.size(); ++i) {
    Character *c = chars[i];
    if (bySerial) {
      try {
        if ((unsigned long)c->getHandle().serial == serial)
          return c;
      } catch (...) {
      }
      continue;
    }
    std::string cname;
    float dist = 0;
    try {
      cname = Lower(c->getName());
      dist = c->getPosition().distance(origin);
    } catch (...) {
      continue;
    }
    if (cname == wanted) {
      if (!exact || dist < exactDist) {
        exact = c;
        exactDist = dist;
      }
    } else if (cname.find(wanted) != std::string::npos) {
      if (!partial || dist < partialDist) {
        partial = c;
        partialDist = dist;
      }
    }
  }
  return exact ? exact : partial;
}

std::string Describe(Character *c, const Ogre::Vector3 *origin) {
  std::string out;
  try {
    out = c->getName();
    out += " #" + Int(c->getHandle().serial);
    Faction *f = c->getFaction();
    out += " [" + std::string(Valid(f) ? f->getName() : "?") + "]";
    Ogre::Vector3 p = c->getPosition();
    out += " pos=" + Num(p.x) + "," + Num(p.y) + "," + Num(p.z);
    if (origin)
      out += " dist=" + Num(p.distance(*origin));
    if (c->isDead())
      out += " DEAD";
    else if (c->isUnconcious())
      out += " KO";
  } catch (...) {
    out += " (unreadable)";
  }
  return out;
}

GameData *FindData(GameWorld *world, itemType type, const std::string &name,
                   std::string &error) {
  const std::string wanted = Lower(name);
  std::vector<GameData *> partial;
  const auto categoryIt = world->gamedata.gamedataCatSID.find((int)type);
  if (categoryIt != world->gamedata.gamedataCatSID.end()) {
    const auto &entries = categoryIt->second;
    for (auto it = entries.begin(); it != entries.end(); ++it) {
      GameData *data = it->second;
      if (!Valid(data))
        continue;
      std::string dataName = Lower(data->name);
      if (dataName == wanted)
        return data;
      if (dataName.find(wanted) != std::string::npos)
        partial.push_back(data);
    }
  }
  if (partial.size() == 1)
    return partial[0];
  if (partial.empty()) {
    error = "no data named: " + name;
  } else {
    error = "ambiguous name, candidates:";
    for (size_t i = 0; i < partial.size() && i < 15; ++i)
      error += " [" + partial[i]->name + "]";
  }
  return nullptr;
}

Faction *FindFaction(GameWorld *world, const std::string &name) {
  if (!Valid(world->factionMgr))
    return nullptr;
  Faction *f = nullptr;
  try {
    f = world->factionMgr->getFactionByName(name);
  } catch (...) {
    f = nullptr;
  }
  return Valid(f) ? f : nullptr;
}

// Parses "x y z" or a character name into a position.
bool ResolvePosition(GameWorld *world, const std::vector<std::string> &f, size_t at,
                     Ogre::Vector3 &pos, std::string &error) {
  if (f.size() >= at + 3) {
    char *e1, *e2, *e3;
    double x = strtod(f[at].c_str(), &e1), y = strtod(f[at + 1].c_str(), &e2),
           z = strtod(f[at + 2].c_str(), &e3);
    if (!*e1 && !*e2 && !*e3) {
      pos = Ogre::Vector3((float)x, (float)y, (float)z);
      return true;
    }
  }
  if (f.size() <= at) {
    error = "missing position (<npc> or x y z)";
    return false;
  }
  Character *c = FindCharacter(world, f[at]);
  if (!c) {
    error = "no character named: " + f[at];
    return false;
  }
  pos = c->getPosition();
  return true;
}

// Reads "key value" options after the positional arguments.
std::string Option(const std::vector<std::string> &f, size_t from, const std::string &key,
                   const std::string &fallback) {
  for (size_t i = from; i + 1 < f.size(); ++i)
    if (Lower(f[i]) == key)
      return f[i + 1];
  return fallback;
}

void SetAllParts(Character *c, float fraction) {
  MedicalSystem &med = c->medical;
  int count = med.getPartCount();
  for (int i = 0; i < count; ++i) {
    MedicalSystem::HealthPartStatus *part = med.getPart((unsigned __int64)i);
    if (!Valid(part))
      continue;
    float maxHp = part->maxHealth();
    part->flesh = maxHp * fraction;
    part->fleshStun = maxHp * fraction;
  }
}

// After a load command the old world stays "in world" for a few frames, so a
// pending load only ends once the squad list emptied and filled again (or
// after 120 s).
bool g_loadPending = false;
bool g_loadSawEmpty = false;
DWORD g_loadStarted = 0;
Character *g_loadOldLeader = nullptr; // squad leader object before the load

std::string Phase(GameWorld *world) {
  if (!Valid(world))
    return "starting";
  bool loading = false;
  try {
    loading = world->isLoadingFromASaveGame();
  } catch (...) {
  }
  const bool inWorld = InWorld(world);
  if (g_loadPending) {
    if (!inWorld || loading)
      g_loadSawEmpty = true;
    else if (g_loadSawEmpty || FirstPlayerCharacter(world) != g_loadOldLeader ||
             GetTickCount() - g_loadStarted > 120000)
      g_loadPending = false;
    if (g_loadPending)
      return "loading";
  }
  if (loading)
    return "loading";
  return inWorld ? "world" : "menu";
}

std::string CurrentSave() {
  try {
    SaveManager *sm = SaveManager::getSingleton();
    if (Valid(sm))
      return sm->getCurrentGame();
  } catch (...) {
  }
  return "";
}

std::string RunCommand(GameWorld *world, const std::vector<std::string> &f, bool &ok) {
  ok = false;
  const std::string cmd = Lower(f[1]);

  if (cmd == "status") {
    ok = true;
    std::string out = "phase=" + Phase(world) + " save=" + CurrentSave();
    if (Valid(world)) {
      out += " paused=" + std::string(world->paused ? "1" : "0");
      out += " speed=" + Num(world->frameSpeedMult);
    }
    if (InWorld(world))
      out += " squad=" + Int(world->player->playerCharacters.size()) + " player=" +
             FirstPlayerCharacter(world)->getName();
    return out;
  }

  if (cmd == "load") {
    if (f.size() < 3 || f[2].empty())
      return "usage: load <save name>";
    SaveManager *sm = SaveManager::getSingleton();
    if (!Valid(sm))
      return "no SaveManager";
    if (!sm->saveExists(sm->getSavePath(), f[2]))
      return "no save named: " + f[2] + " (in " + sm->getSavePath() + ")";
    Log("TEST_AUTO: load save=" + f[2] + " phase=" + Phase(world));
    sm->load(f[2]);
    g_loadPending = true;
    g_loadSawEmpty = false;
    g_loadStarted = GetTickCount();
    g_loadOldLeader = FirstPlayerCharacter(world);
    ok = true;
    return "loading " + f[2];
  }

  if (cmd == "save") {
    if (f.size() < 3 || f[2].empty())
      return "usage: save <save name>";
    if (!InWorld(world))
      return "no game loaded";
    SaveManager *sm = SaveManager::getSingleton();
    if (!Valid(sm))
      return "no SaveManager";
    Log("TEST_AUTO: save save=" + f[2]);
    sm->save(f[2], false);
    ok = true;
    return "saving " + f[2];
  }

  if (!InWorld(world))
    return "no game loaded (phase=" + Phase(world) + ")";
  Character *player = FirstPlayerCharacter(world);
  Ogre::Vector3 origin = player->getPosition();

  if (cmd == "chars") {
    float radius = f.size() >= 3 ? (float)atof(f[2].c_str()) : 100.0f;
    std::string out;
    int n = 0;
    std::vector<Character *> chars;
    CollectCharacters(world, origin, radius, chars);
    for (size_t i = 0; i < chars.size() && n < 40; ++i) {
      Character *c = chars[i];
      try {
        if (c->getPosition().distance(origin) > radius)
          continue;
      } catch (...) {
        continue;
      }
      out += (n ? " | " : "") + Describe(c, &origin);
      ++n;
    }
    ok = true;
    return Int(n) + " within " + Num(radius) + ": " + out;
  }

  if (cmd == "find") { // find <character|squad|item|faction> <substring>
    if (f.size() < 4)
      return "usage: find <character|squad|item|weapon|armour> <text>";
    const std::string kind = Lower(f[2]);
    itemType type = kind == "squad" ? SQUAD_TEMPLATE
                    : kind == "item" ? ITEM
                    : kind == "weapon" ? WEAPON
                    : kind == "armour" ? ARMOUR
                                       : CHARACTER;
    std::string error;
    GameData *data = FindData(world, type, f[3], error);
    ok = data != nullptr;
    return data ? "[" + data->name + "] sid=" + data->stringID : error;
  }

  if (cmd == "spawn") {
    // spawn <character|squad template> <faction> [near <npc>|at x y z] [count n] [dist m] [target <npc>]
    if (f.size() < 4)
      return "usage: spawn <template> <faction> [near <npc> | at x y z] [count n] [dist m] "
             "[target <npc>]";
    Faction *faction = FindFaction(world, f[3]);
    if (!faction)
      return "no faction named: " + f[3];
    Ogre::Vector3 pos = origin;
    std::string error;
    for (size_t i = 4; i < f.size(); ++i) {
      if (Lower(f[i]) == "near" && !ResolvePosition(world, f, i + 1, pos, error))
        return error;
      if (Lower(f[i]) == "at" && !ResolvePosition(world, f, i + 1, pos, error))
        return error;
    }
    float dist = (float)atof(Option(f, 4, "dist", "8").c_str());
    int count = atoi(Option(f, 4, "count", "1").c_str());
    if (count < 1 || count > 10)
      return "count must be 1..10";
    pos.x += dist;
    if (!Valid(world->theFactory))
      return "no factory";
    std::string squadError;
    GameData *squad = FindData(world, SQUAD_TEMPLATE, f[2], squadError);
    if (squad && Lower(squad->name) == Lower(f[2])) {
      // "target <npc>": the squad's AI goes for that character (a raid on the
      // player); without it spawned squads walk off to their own goals.
      hand aiTarget;
      const std::string targetName = Option(f, 4, "target", "");
      if (!targetName.empty()) {
        Character *t = FindCharacter(world, targetName);
        if (!t)
          return "no character named: " + targetName;
        aiTarget = t->getHandle();
      }
      // "size <mult>": the template decides the squad size; this scales it.
      float sizeMult = (float)atof(Option(f, 4, "size", "1").c_str());
      if (sizeMult <= 0.0f || sizeMult > 3.0f)
        return "size must be 0..3";
      Platoon *p = world->theFactory->createRandomSquad(
          faction, pos, nullptr, count, nullptr, squad, nullptr, nullptr, nullptr, false,
          aiTarget, nullptr, sizeMult, SQ_ROAMING, false);
      Log("TEST_AUTO: spawn squad=" + squad->name + " faction=" + faction->getName() +
          " ok=" + (Valid(p) ? "1" : "0"));
      ok = Valid(p);
      return std::string(ok ? "spawned squad " : "squad spawn failed ") + squad->name +
             " at " + Num(pos.x) + "," + Num(pos.y) + "," + Num(pos.z);
    }
    GameData *charData = FindData(world, CHARACTER, f[2], error);
    if (!charData)
      return error + (squad ? " (squad match: [" + squad->name + "])" : "");
    int made = 0;
    std::string names;
    for (int i = 0; i < count; ++i) {
      Ogre::Vector3 at = pos;
      at.z += 2.0f * i;
      RootObject *obj = world->theFactory->createRandomCharacter(faction, at, nullptr,
                                                                 charData, nullptr, -1.0f);
      Character *c = dynamic_cast<Character *>(obj);
      if (!Valid(c))
        break;
      ++made;
      names += (made > 1 ? ", " : "") + c->getName() + " #" + Int(c->getHandle().serial);
    }
    Log("TEST_AUTO: spawn character=" + charData->name + " faction=" + faction->getName() +
        " made=" + Int(made) + " " + names);
    ok = made > 0;
    return "spawned " + Int(made) + "/" + Int(count) + " " + charData->name + ": " + names;
  }

  if (cmd == "stash") { // stash <item> <count> [near <npc>]: fill the nearest storage
    if (f.size() < 4)
      return "usage: stash <item> <count> [near <npc>]";
    int count = atoi(f[3].c_str());
    if (count < 1 || count > 50)
      return "count must be 1..50";
    Ogre::Vector3 at = origin;
    std::string error;
    if (f.size() >= 6 && Lower(f[4]) == "near" && !ResolvePosition(world, f, 5, at, error))
      return error;
    GameData *data = nullptr;
    const itemType types[] = {ITEM, WEAPON, ARMOUR};
    for (int t = 0; t < 3 && !data; ++t)
      data = FindData(world, types[t], f[2], error);
    if (!data)
      return error;
    lektor<RootObject *> nearby;
    world->getObjectsWithinSphere(nearby, at, 300.0f, BUILDING, 256, nullptr);
    RootObject *best = nullptr;
    float bestDist = 0.0f;
    for (uint32_t i = 0; i < nearby.size(); ++i) {
      RootObject *b = nearby.stuff[i];
      if (!Valid(b))
        continue;
      std::string name;
      try {
        name = Lower(b->getName());
      } catch (...) {
        continue;
      }
      if (name.find("storage") == std::string::npos && name.find("chest") == std::string::npos)
        continue;
      Inventory *inv = nullptr;
      try {
        inv = b->getInventory();
      } catch (...) {
        inv = nullptr;
      }
      if (!Valid(inv))
        continue;
      float d = b->getPosition().distance(at);
      if (!best || d < bestDist) {
        best = b;
        bestDist = d;
      }
    }
    if (!best)
      return "no storage chest within 300";
    Inventory *inv = best->getInventory();
    int added = 0;
    for (int i = 0; i < count; ++i) {
      Item *item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1, nullptr);
      if (!Valid(item) || !inv->addItem(item, 1, false, true))
        break;
      ++added;
    }
    ok = added > 0;
    Log("TEST_AUTO: stash " + data->name + " x" + Int(added) + " in " + best->getName());
    return "stashed " + Int(added) + "/" + Int(count) + " " + data->name + " in " +
           best->getName() + " (" + Num(bestDist) + " away)";
  }

  // The remaining commands take a character first.
  if (f.size() < 3)
    return "usage: " + cmd + " <npc> ...";
  Character *c = FindCharacter(world, f[2]);
  if (!c)
    return "no character named: " + f[2];

  if (cmd == "where") {
    ok = true;
    return Describe(c, &origin);
  }

  if (cmd == "hp") { // per body part flesh/max, and the worst part in %
    MedicalSystem &med = c->medical;
    std::string out;
    float worst = 1.0f;
    int count = med.getPartCount();
    for (int i = 0; i < count; ++i) {
      MedicalSystem::HealthPartStatus *part = med.getPart((unsigned __int64)i);
      if (!Valid(part))
        continue;
      float maxHp = part->maxHealth();
      if (maxHp > 0.0f && part->flesh / maxHp < worst)
        worst = part->flesh / maxHp;
      out += " " + Int(i) + ":" + Num(part->flesh) + "/" + Num(maxHp);
    }
    ok = true;
    return c->getName() + " worst=" + Int((long long)(worst * 100.0f)) + "% blood=" +
           Num(med.blood) + "/" + Num(med.getMaxBlood()) + (c->isUnconcious() ? " KO" : "") +
           " parts" + out;
  }

  if (cmd == "inv") { // inventory incl. worn items, as JSON (works on bodies)
    std::string json, hash;
    int count = 0;
    ok = BuildInventorySnapshot(c, json, hash, count);
    return Describe(c, nullptr) + " items=" + Int(count) + " " + json;
  }

  if (cmd == "teleport") { // teleport <npc> <npc2 | x y z> [dist m]
    Ogre::Vector3 to;
    std::string error;
    if (!ResolvePosition(world, f, 3, to, error))
      return error;
    to.x += (float)atof(Option(f, 3, "dist", "0").c_str());
    c->teleport(to, Ogre::Quaternion::IDENTITY);
    ok = true;
    Log("TEST_AUTO: teleport " + Describe(c, nullptr));
    return "teleported: " + Describe(c, &origin);
  }

  if (cmd == "ko") { // ko <npc> [seconds]
    float seconds = f.size() >= 4 ? (float)atof(f[3].c_str()) : 30.0f;
    c->medical.knockoutForceTimer(seconds);
    ok = true;
    Log("TEST_AUTO: ko " + c->getName() + " seconds=" + Num(seconds));
    return "knocked out " + c->getName() + " for " + Num(seconds) + " s";
  }

  if (cmd == "health") { // health <npc> <percent of max for every body part>
    if (f.size() < 4)
      return "usage: health <npc> <percent, e.g. 30 or -50>";
    float pct = (float)atof(f[3].c_str());
    SetAllParts(c, pct / 100.0f);
    if (pct >= 100.0f)
      c->medical.blood = c->medical.getMaxBlood();
    ok = true;
    Log("TEST_AUTO: health " + c->getName() + " pct=" + Num(pct));
    return "set every body part of " + c->getName() + " to " + Num(pct) + "%";
  }

  if (cmd == "kill") {
    SetAllParts(c, -2.0f);
    ok = true;
    Log("TEST_AUTO: kill " + c->getName());
    return "killed " + c->getName() + " (body parts at -200%)";
  }

  if (cmd == "hunger") { // hunger <npc> <game UI value, 0..300>
    if (f.size() < 4)
      return "usage: hunger <npc> <value as shown in game, 0..300>";
    float before = c->medical.hunger * 100.0f;
    c->medical.hunger = (float)atof(f[3].c_str()) / 100.0f;
    ok = true;
    Log("TEST_AUTO: hunger " + c->getName() + " " + Num(before) + " -> " + f[3]);
    return c->getName() + " hunger " + Num(before) + " -> " + Num(c->medical.hunger * 100.0f);
  }

  if (cmd == "attack") { // attack <attacker> <target>
    if (f.size() < 4)
      return "usage: attack <attacker> <target>";
    Character *target = FindCharacter(world, f[3]);
    if (!target)
      return "no character named: " + f[3];
    // A real order, as the player gives it: break a truce, queue the attack.
    BreakFactionCeasefireForExplicitAttack(c, target, "test_attack_order");
    OrdersReceiver *orders = c->getOrdersReciever();
    if (orders && (uintptr_t)orders > 0x1000)
      orders->addOrder(UNPROVOKED_FOCUSED_MELEE_ATTACK, target->getHandle(),
                       target->getPosition(), true, false);
    c->attackTarget(target);
    ok = true;
    Log("TEST_AUTO: attack " + c->getName() + " -> " + target->getName());
    return c->getName() + " attacks " + target->getName();
  }

  if (cmd == "money") { // money <npc> <delta>: add (or with a minus, take) cats
    if (f.size() < 4)
      return "usage: money <npc> <delta>";
    int delta = atoi(f[3].c_str());
    int before = c->getMoney();
    c->takeMoney(-delta);
    ok = true;
    Log("TEST_AUTO: money " + c->getName() + " " + Int(before) + " -> " + Int(c->getMoney()));
    return c->getName() + " cats " + Int(before) + " -> " + Int(c->getMoney());
  }

  if (cmd == "buy") { // buy <buyer> <seller> <item> <price>: one atomic purchase
    if (f.size() < 6)
      return "usage: buy <buyer> <seller> <item> <price>";
    Character *seller = FindCharacter(world, f[3]);
    if (!seller)
      return "no character named: " + f[3];
    int price = atoi(f[5].c_str());
    std::string error;
    GameData *data = nullptr;
    const itemType types[] = {ITEM, WEAPON, ARMOUR};
    for (int t = 0; t < 3 && !data; ++t)
      data = FindData(world, types[t], f[4], error);
    if (!data)
      return error;
    Item *item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1, nullptr);
    Inventory *inv = c->getInventory();
    if (!Valid(item) || !Valid(inv) || !inv->addItem(item, 1, false, true))
      return "could not add the item";
    c->takeMoney(price);
    seller->takeMoney(-price);
    ok = true;
    Log("TEST_AUTO: buy " + c->getName() + " <- " + seller->getName() + " " + data->name +
        " for " + Int(price));
    return c->getName() + " bought " + data->name + " from " + seller->getName() + " for " +
           Int(price);
  }

  if (cmd == "select") {
    world->player->selectObject(c, false);
    ok = true;
    return "selected " + c->getName();
  }

  if (cmd == "recruit") {
    ok = world->player->recruit(c, false);
    Log("TEST_AUTO: recruit " + c->getName() + " ok=" + (ok ? "1" : "0"));
    return (ok ? "recruited " : "recruit failed: ") + c->getName();
  }

  if (cmd == "give") { // give <npc> <item> [count]
    if (f.size() < 4)
      return "usage: give <npc> <item> [count]";
    int count = f.size() >= 5 ? atoi(f[4].c_str()) : 1;
    if (count < 1 || count > 50)
      return "count must be 1..50";
    std::string error;
    GameData *data = nullptr;
    const itemType types[] = {ITEM, WEAPON, ARMOUR};
    for (int t = 0; t < 3 && !data; ++t)
      data = FindData(world, types[t], f[3], error);
    if (!data)
      return error;
    Inventory *inv = c->getInventory();
    if (!Valid(inv))
      return "no inventory";
    int added = 0;
    int countBefore = inv->countItems(data);
    for (int i = 0; i < count; ++i) {
      Item *item = world->theFactory->createItem(data, hand(), nullptr, nullptr, -1, nullptr);
      if (!Valid(item) || !inv->addItem(item, 1, false, true))
        break;
      ++added;
    }
    // addItem can report success for items that don't stay: report what really arrived.
    int real = inv->countItems(data) - countBefore;
    Log("TEST_AUTO: give " + c->getName() + " item=" + data->name + " added=" + Int(added) +
        " real=" + Int(real) + " now=" + Int(countBefore + real));
    ok = real > 0;
    return c->getName() + " got " + Int(real) + "/" + Int(count) + " " + data->name +
           " (now " + Int(countBefore + real) + ")";
  }

  if (cmd == "relation") { // relation <npc> <value -100..100>: npc's faction <-> player faction
    if (f.size() < 4)
      return "usage: relation <npc> <value -100..100>";
    Faction *theirs = c->getFaction();
    Faction *ours = player->getFaction();
    if (!Valid(theirs) || !Valid(ours) || !Valid(theirs->relations) || !Valid(ours->relations))
      return "faction not found";
    float v = (float)atof(f[3].c_str());
    float before = theirs->relations->getFactionRelation(ours);
    theirs->relations->setRelation(ours, v);
    ours->relations->setRelation(theirs, v);
    ok = true;
    Log("TEST_AUTO: relation " + theirs->getName() + " <-> " + ours->getName() + " " +
        Num(before) + " -> " + Num(v));
    return theirs->getName() + " <-> " + ours->getName() + ": " + Num(before) + " -> " +
           Num(theirs->relations->getFactionRelation(ours));
  }

  return "unknown command: " + cmd;
}

void ProcessInbox(GameWorld *world) {
  const std::string dir = GetTestInboxDir();
  if (!FileExists(dir + "\\test_inbox.flag"))
    return;


  const std::string autoload = dir + "\\autoload.txt";
  if (FileExists(autoload) && Phase(world) == "menu") {
    std::string name;
    {
      std::ifstream in(autoload.c_str());
      std::getline(in, name);
    }
    DeleteFileA(autoload.c_str());
    while (!name.empty() && (name[name.size() - 1] == '\r' || name[name.size() - 1] == ' '))
      name.erase(name.size() - 1);
    std::vector<std::string> f;
    f.push_back("autoload");
    f.push_back("load");
    f.push_back(name);
    bool ok = false;
    std::string detail;
    try {
      detail = RunCommand(world, f, ok);
    } catch (...) {
      detail = "exception";
    }
    Log("TEST_AUTO: autoload " + name + ": " + detail);
    std::ofstream out((dir + "\\auto_outbox.txt").c_str(), std::ios::app);
    out << "autoload\t" << (ok ? "ok" : "error") << "\t" << OneLine(detail) << "\n";
  }

  const std::string inboxPath = dir + "\\auto_inbox.txt";
  std::vector<std::string> lines;
  {
    std::ifstream in(inboxPath.c_str());
    if (!in)
      return;
    std::string line;
    while (std::getline(in, line)) {
      if (!line.empty() && line[line.size() - 1] == '\r')
        line.erase(line.size() - 1);
      if (!line.empty())
        lines.push_back(line);
    }
  }
  DeleteFileA(inboxPath.c_str());
  std::ofstream out((dir + "\\auto_outbox.txt").c_str(), std::ios::app);
  for (size_t i = 0; i < lines.size(); ++i) {
    std::vector<std::string> fields;
    size_t start = 0;
    while (true) {
      size_t tab = lines[i].find('\t', start);
      fields.push_back(lines[i].substr(start, tab == std::string::npos ? std::string::npos
                                                                        : tab - start));
      if (tab == std::string::npos)
        break;
      start = tab + 1;
    }
    bool ok = false;
    std::string detail;
    if (fields.size() < 2) {
      detail = "malformed line";
    } else {
      try {
        detail = RunCommand(world, fields, ok);
      } catch (...) {
        detail = "exception";
      }
    }
    out << fields[0] << "\t" << (ok ? "ok" : "error") << "\t" << OneLine(detail) << "\n";
    out.flush();
    if (!ok)
      Log("TEST_AUTO: error id=" + fields[0] + " " + detail);
  }
}

// Runs once per frame on the game thread, at the main menu too
// (GameWorld::mainLoop only runs once a game is loaded).
void Tick(const char *source) {
  GameWorld *world = ou;
  if (!g_loggedFirstTick) {
    g_loggedFirstTick = true;
    Log(std::string("TEST_AUTO: frame listener running (source=") + source +
        " phase=" + Phase(world) + " thread=" + Int(GetCurrentThreadId()) + ")");
  }
  DWORD now = GetTickCount();
  if (now - g_lastPoll < 250)
    return;
  g_lastPoll = now;
  try {
    if (g_loadPending)
      Phase(world); // notice the moment the old squad is gone
    ProcessInbox(world);
  } catch (...) {
    Log("TEST_AUTO: exception in ProcessInbox");
  }
}

class AutomationFrameListener : public Ogre::FrameListener {
public:
  virtual bool frameStarted(const Ogre::FrameEvent &) {
    Tick("ogre");
    return true;
  }
};

AutomationFrameListener g_frameListener;

// Test sessions must not overwrite Shay's autosave slots: skip the autosave
// update while the test inbox switch is on (checked once a second).
typedef void(__fastcall *UpdateAutoSaveFn)(SaveManager *);
UpdateAutoSaveFn g_updateAutoSaveOrig = nullptr;

void __fastcall Hook_UpdateAutoSave(SaveManager *sm) {
  static DWORD lastCheck = 0;
  static bool testing = false;
  DWORD now = GetTickCount();
  if (now - lastCheck >= 1000) {
    lastCheck = now;
    bool was = testing;
    testing = FileExists(GetTestInboxDir() + "\\test_inbox.flag");
    if (testing != was)
      Log(std::string("TEST_AUTO: autosave ") + (testing ? "off (test inbox on)" : "on"));
  }
  if (!testing)
    g_updateAutoSaveOrig(sm);
}

void OnGuiFrame(float) { Tick("mygui"); }

} // namespace

void InstallTestAutomationHooks() {
  __int64 autoSaveAddr = KenshiLib::GetRealAddress(&SaveManager::updateAutoSave);
  if (autoSaveAddr) {
    KenshiLib::HookStatus autoSaveStatus = KenshiLib::AddHook(
        (void *)autoSaveAddr, (void *)Hook_UpdateAutoSave, (void **)&g_updateAutoSaveOrig);
    Log("TEST_AUTO: SaveManager::updateAutoSave hook status=" + Int((int)autoSaveStatus));
  } else {
    Log("TEST_AUTO: SaveManager::updateAutoSave not found; autosave stays on");
  }

  Ogre::Root *root = Ogre::Root::getSingletonPtr();
  if (!root) {
    Log("TEST_AUTO: no Ogre::Root yet; automation commands off.");
    return;
  }
  root->addFrameListener(&g_frameListener);
  MyGUI::Gui *gui = MyGUI::Gui::getInstancePtr();
  if (gui)
    gui->eventFrameStart += MyGUI::newDelegate(&OnGuiFrame);
  Log("TEST_AUTO: frame listener added (mygui=" + std::string(gui ? "yes" : "no") +
      " thread=" + Int(GetCurrentThreadId()) + ")");

  // Ogre stops rendering (and the game stops updating) while its window is
  // in the background; automated runs keep the game running unfocused.
  if (!FileExists(GetTestInboxDir() + "\\test_inbox.flag"))
    return;
  int windows = 0;
  Ogre::RenderSystem *rs = root->getRenderSystem();
  if (rs) {
    Ogre::RenderSystem::RenderTargetIterator it = rs->getRenderTargetIterator();
    while (it.hasMoreElements()) {
      Ogre::RenderWindow *win = dynamic_cast<Ogre::RenderWindow *>(it.getNext());
      if (!win)
        continue;
      win->setDeactivateOnFocusChange(false);
      win->setActive(true);
      ++windows;
    }
  }
  Log("TEST_AUTO: keep running in background: " + Int(windows) + " render window(s)");
}
