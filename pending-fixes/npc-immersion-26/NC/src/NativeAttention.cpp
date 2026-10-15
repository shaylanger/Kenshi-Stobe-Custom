#include "NativeAttention.h"
#include "N2Policy.h"
#include "Utils.h"
#include <kenshi/Character.h>
#include <kenshi/CharBody.h>
#include <kenshi/Faction.h>
#include <kenshi/GameWorld.h>
#include <kenshi/MedicalSystem.h>
#include <kenshi/Platoon.h>
#include <kenshi/RootObjectBase.h>
#include <kenshi/StateBroadcastData.h>
#include <kenshi/Tasker.h>
#include <kenshi/util/YesNoMaybe.h>
#include <stdint.h>

namespace Stobe { namespace NativeAttention {
namespace {
bool Ok(const void* p) { return p && (uintptr_t)p >= 0x1000; }

TaskType CurrentTask(Character* c) {
  try {
    CharBody* body = c->getBody();
    if (!Ok(body)) return NULL_TASK;
    Tasker* action = body->currentAction;
    if (!Ok(action) || !Ok(action->taskData)) return NULL_TASK;
    return action->taskData->key;
  } catch (...) { return NULL_TASK; }
}

bool IsSleepTask(TaskType t) { return t == SLEEP_ON_FLOOR || t == USE_BED || t == USE_BED_ORDER || t == REST; }
bool IsFearTask(TaskType t) {
  return t == RUN_AWAY || t == RUN_AWAY_HOMETOWN || t == RETREAT_HOMETOWN || t == RUN_AWAY_FORCED || t == SELF_PRESERVATION;
}
// Reason text for tasks that mean "occupied with a job"; "" = free (idle, wandering, following, standing).
const char* BusyReason(TaskType t) {
  switch (t) {
  case BUILD: case ADD_MATERIALS_TO_BUILDING: case JOB_BUILDER: return "building";
  case REPAIR: case JOB_REPAIR_ROBOT: return "repairing";
  case DISMANTLE: return "dismantling";
  case OPERATE_MACHINERY: case OPERATE_AUTOMATIC_MACHINERY: case PRETEND_TO_OPERATE_MACHINERY:
  case JOB_KEEP_EVERYTHING_RUNNING: case FILL_MACHINE: case WANT_TO_FILL_MACHINE: case UNJAM_ALL_MACHINES:
  case UNJAM_MACHINE: case COLLECT_OUTPUT_RESOURCE: case COLLECT_OUTPUT_RESOURCE_BUILD_MATS: case EMPTYING_MACHINE:
  case EMPTY_MACHINE_OUTPUTS: return "operating machinery";
  case FIRST_AID_ORDER: case FIRST_AID_ROBOT: case JOB_MEDIC: case SPLINT_ORDER: case SPLINT_JOB: case HEAL_MY_LEGS:
    return "giving first aid";
  case USE_TRAINING_DUMMY: return "training";
  case SHOPPING: case BUY_SHIT: case FIND_A_SHOP: return "shopping";
  case STAND_AT_SHOPKEEPER_NODE: case WANDERING_TRADER: case OPEN_UP_SHOP_DOORS: return "tending a shop";
  case PATROL: case PATROL_TOWN: case STAND_AT_GUARD_NODE_HOMEBUILDING_IN_OUT: case STAND_AT_GUARD_NODE_HOMETOWN_OUTSIDE:
  case STAND_AT_GUARD_NODE_HOMEBUILDING_INDOORS_ONLY: case STAND_AT_BUILDING_GUARD_NODE: case MAN_THE_GATE:
    return "on guard duty";
  case MAN_A_TURRET: case MAN_A_TURRET_ON_BUILDING: case MAN_A_TURRET_PLAYER_JOB: case USE_TURRET: return "manning a turret";
  case PROSPECTING: return "prospecting";
  case AUTO_LABOURING_MINES: case AUTO_LABOURING_MINES_PRETEND: case WORK_THE_SLAVES: return "working";
  case OPERATE_STORAGE: case PUT_LOOT_IN_STORAGE: case DELIVER_RESOURCES: return "hauling goods";
  case PICK_LOCK: case LOCK_DOOR: case UNLOCK_DOOR: return "working a lock";
  case TRAVEL_TO_TARGET_TOWN: case TRAVEL_TO_TARGET_TOWN_FAST: case TRAVEL_TO_TARGET_PACKAGE: return "travelling";
  case LOOT_TARGET: case LOOT_THE_DEAD: case LOOT_CONTAINER: return "looting";
  default: return "";
  }
}

struct Vitals {
  bool ok, dead, unconscious, bleeding, trauma;
  int bloodPct, hungerValue, worstFleshPct;
  Vitals() : ok(false), dead(false), unconscious(false), bleeding(false), trauma(false), bloodPct(-1), hungerValue(300), worstFleshPct(-1) {}
};

Vitals ReadVitals(Character* c) {
  Vitals v;
  try {
    MedicalSystem* med = c->getMedical();
    if (!Ok(med)) return v;
    v.ok = true;
    v.dead = med->dead;
    v.unconscious = med->unconcious;
    v.bloodPct = N2Policy::BloodPct(med->blood, med->getMaxBlood());
    v.bleeding = med->currentBleedRate > 0.0f;
    v.trauma = med->isInBloodlossTrauma();
    v.hungerValue = N2Policy::HungerValue(med->hunger, med->fed);
    MedicalSystem::HealthPartStatus* parts[6] = {med->getPart(0), med->getPart(1), med->leftArm, med->rightArm, med->leftLeg, med->rightLeg};
    int worst = 100;
    bool any = false;
    for (int i = 0; i < 6; ++i) {
      MedicalSystem::HealthPartStatus* p = parts[i];
      if (!Ok(p)) continue;
      float mx = p->maxHealth();
      if (!(mx > 0.0f)) continue;
      int pct = (int)(p->flesh * 100.0f / mx);
      if (pct < worst) worst = pct;
      any = true;
    }
    if (any) v.worstFleshPct = worst < 0 ? 0 : worst;
  } catch (...) { v = Vitals(); }
  return v;
}

bool IsAsleep(Character* c, TaskType task) {
  try {
    if (c->inSomething == IN_BED || IsSleepTask(task)) return true;
    StateBroadcastData* sb = c->stateBroadcast;
    if (Ok(sb) && sb->isSleeping.key == YesNoMaybe::YES) return true;
  } catch (...) {}
  return false;
}
} // namespace

std::string AttentionJson(Character* npc) {
  if (!Ok(npc)) return "{\"observed\":false}";
  N2Policy::AttentionInputs a;
  Vitals v = ReadVitals(npc);
  if (!v.ok) return "{\"observed\":false}";
  TaskType task = CurrentTask(npc);
  a.bloodPct = v.bloodPct;
  a.bleeding = v.bleeding;
  a.hungry = N2Policy::HungryFrom(v.hungerValue);
  a.exhausted = N2Policy::ExhaustedFrom(v.hungerValue, v.trauma);
  try { a.crippled = npc->isCrippled(); } catch (...) { a.crippled = false; }
  try { a.fleeing = npc->isFleeing(); } catch (...) { a.fleeing = false; }
  try { a.inCombat = npc->isInCombatMode(true, true); } catch (...) { a.inCombat = false; }
  a.injured = N2Policy::InjuredFrom(v.bloodPct, a.crippled, a.bleeding, v.worstFleshPct);
  a.sleeping = IsAsleep(npc, task);
  a.afraid = a.fleeing || IsFearTask(task);
  const char* reason = BusyReason(task);
  a.busy = reason[0] != 0;
  a.busyReason = reason;
  return N2Policy::AttentionJson(a);
}

std::string WithAttention(const std::string& nativeAiJson, Character* npc) {
  try { return N2Policy::AppendAttention(nativeAiJson, AttentionJson(npc)); }
  catch (...) { return nativeAiJson; }
}

std::string RoleFor(Character* npc) {
  if (!Ok(npc)) return "";
  try {
    TaskType t = CurrentTask(npc);
    if (npc->isSlave() == IS_SLAVE) return "slave";
    if (t == STAND_AT_SHOPKEEPER_NODE) return "shopkeeper";
    if (npc->isATrader() || t == WANDERING_TRADER) return "trader";
    if (t == JOB_MEDIC) return "medic";
    if (npc->isLawEnforcement() || t == PATROL || t == PATROL_TOWN || t == STAND_AT_GUARD_NODE_HOMEBUILDING_IN_OUT ||
        t == STAND_AT_GUARD_NODE_HOMETOWN_OUTSIDE || t == STAND_AT_BUILDING_GUARD_NODE)
      return "guard";
  } catch (...) {}
  return "";
}

std::string SquadName(Character* npc) {
  if (!Ok(npc)) return "";
  try {
    ActivePlatoon* g = npc->getPlatoon();
    if (!Ok(g)) return "";
    return N2Policy::AsciiTruncate(g->getName(), 60);
  } catch (...) { return ""; }
}

unsigned SquadId(Character* npc) {
  if (!Ok(npc)) return 0;
  try {
    ActivePlatoon* g = npc->getPlatoon();
    if (!Ok(g) || !Ok(g->me)) return 0;
    return g->me->getHandle().serial;
  } catch (...) { return 0; }
}

std::string SettlementName(Character* npc) {
  if (!Ok(npc)) return "";
  try {
    TownBase* town = npc->getCurrentTownLocation();
    if (!Ok(town)) return "";
    return N2Policy::AsciiTruncate(((RootObjectBase*)town)->getName(), 60);
  } catch (...) { return ""; }
}

int PartnerState(Character* npc) {
  if (!Ok(npc)) return N2Policy::PS_NONE;
  Vitals v = ReadVitals(npc);
  if (!v.ok) return N2Policy::PS_NONE;
  bool down = false;
  try { down = npc->isDown(); } catch (...) { down = false; }
  return N2Policy::ClassifyPartner(v.dead, v.unconscious, v.bleeding, v.bloodPct, v.trauma, down);
}

bool IsFree(Character* npc) {
  if (!Ok(npc)) return false;
  Vitals v = ReadVitals(npc);
  if (!v.ok || v.dead || v.unconscious) return false;
  try { return !npc->isDown(); } catch (...) { return false; }
}

bool IsIdle(Character* npc) {
  if (!IsFree(npc)) return false;
  TaskType task = CurrentTask(npc);
  try {
    if (npc->isInCombatMode(true, true) || npc->isFleeing()) return false;
  } catch (...) { return false; }
  if (IsAsleep(npc, task) || IsFearTask(task)) return false;
  return BusyReason(task)[0] == 0;
}
} }
