#include "NativeAiAwareness.h"
#include "KenshiAiRuntimeCompat.h"
#include "Utils.h"
#include "FollowExpiryPolicy.h"
#include "NativeAiOrdersJson.h"
#include <kenshi/Tasker.h>
#include <kenshi/Faction.h>
#include <map>
#include <vector>
#include <kenshi/AI/AITaskSystem.h>
#include <kenshi/Character.h>
#include <kenshi/GameWorld.h>
#include <kenshi/GameData.h>
#include <kenshi/Platoon.h>
#include <algorithm>
#include <cmath>
#include <float.h>
#include <ctime>
#include <cstdint>
#include <sstream>
#include <locale>

// Method-only compatibility declaration: the SDK Blackboard header pulls in
// incomplete AI types and duplicates the AIPackage enum. These out-of-line SDK
// accessors use the native object; this class is never allocated or sized.
class AIPackage;
class Blackboard {
public:
  std::string getCurrentAIPackageName() const;
  AIPackage* getCurrentPackage();
  bool hasContractJob() const;
  TimeOfDay getContractExpiryTime() const;
};

// Defined in Globals.cpp (legacy FOLLOW controller registry). Declared here to avoid pulling Globals.h.
std::map<unsigned int, hand> SnapshotFollowTargets();
bool GetFollowStart(unsigned int followerSerial, long long &startGameTs);

namespace Stobe { namespace NativeAiAwareness { namespace {
std::string Quote(const std::string& s) { return "\"" + EscapeJSON(s.substr(0, 160)) + "\""; }
std::string Bool(bool b) { return b ? "true" : "false"; }
std::string Number(double n) {
  if (!_finite(n)) return "null";
  std::ostringstream s; s.imbue(std::locale::classic());
  // default precision 6 rounded observed_unix/game_ts (1792103647 -> 1.7921e+09) so every native_ai snapshot looked stale
  if (n == floor(n) && n > -9e15 && n < 9e15) s << static_cast<long long>(n); else { s.precision(12); s << n; }
  return s.str();
}
template<class T> bool ReadField(const void* object, size_t offset, T& out) {
  if (reinterpret_cast<uintptr_t>(object) < 0x10000) return false;
  SIZE_T count = 0;
  return ReadProcessMemory(GetCurrentProcess(),
      reinterpret_cast<const unsigned char*>(object) + offset,
      &out, sizeof(out), &count) && count == sizeof(out);
}
// KenshiSDK hand.h documents scalar fields at 0x08..0x18; preserve the
// constructor's own vtable. Never copy a native vtable into a stack object.
bool ReadHandle(const void* object, size_t offset, hand& h) {
  return ReadField(object, offset + 0x08, h.type) &&
      ReadField(object, offset + 0x0c, h.container) &&
      ReadField(object, offset + 0x10, h.containerSerial) &&
      ReadField(object, offset + 0x14, h.index) &&
      ReadField(object, offset + 0x18, h.serial);
}
std::string HandleJson(const hand& h) {
  if (h.isNull() || !h.isValid()) return "null";
  std::string s = "{\"serial\":" + ToString(h.serial);
  Character* c = h.getCharacter();
  if (c) s += ",\"name\":" + Quote(c->getName());
  return s + "}";
}
std::string PackageJson(AIPackage* package) {
  if (!package) return "null";
  // AIPackage.h: missionTarget 0x28, missionEmployer 0x48, packageData 0x68.
  hand target, employer;
  GameData* data = NULL;
  if (!ReadHandle(package, 0x28, target) || !ReadHandle(package, 0x48, employer) ||
      !ReadField(package, 0x68, data)) return "{\"observed\":false}";
  std::string s = "{\"observed\":true,\"target\":" + HandleJson(target) +
      ",\"employer\":" + HandleJson(employer);
  if (data) s += ",\"package_name\":" + Quote(data->name);
  return s + "}";
}
// Order type the server understands, or empty to skip.
const char* OrderTypeName(TaskType key) {
  switch (key) {
    case FOLLOW_PLAYER_ORDER:
    case STAY_CLOSE_TO_TARGET: return "Follow";
    case PATROL:
    case PATROL_TOWN: return "Patrol";
    case HOLD_POSITION: return "Hold";
    case STAND_AT_BUILDING_GUARD_NODE:
    case STAND_AT_GUARD_NODE_HOMEBUILDING_IN_OUT:
    case STAND_AT_GUARD_NODE_HOMETOWN_OUTSIDE:
    case STAND_AT_GUARD_NODE_HOMEBUILDING_INDOORS_ONLY: return "Guard";
    default: return "";
  }
}
std::string PlayerOrdersBlock(Character* actor) {
  try {
    OrdersReceiver* orders = actor->getOrdersReciever();
    if (!orders || reinterpret_cast<uintptr_t>(orders) < 0x10000) return "null";
    std::vector<NativeAiOrdersJson::OrderRow> rows;
    const size_t total = orders->orders.list.size();
    for (size_t i = 0; i < total && i < 12; ++i) {
      Tasker* t = orders->orders.list[i];
      if (!t || reinterpret_cast<uintptr_t>(t) < 0x10000 || !t->taskData) continue;
      const char* name = OrderTypeName(t->key());
      if (!*name) continue;
      NativeAiOrdersJson::OrderRow row;
      row.type = name;
      if (!t->subject.isNull() && t->subject.isValid()) {
        row.target.serial = t->subject.serial;
        Character* c = t->subject.getCharacter();
        if (c) row.target.name = c->getName();
      }
      rows.push_back(row);
    }
    return NativeAiOrdersJson::PlayerOrdersJson(true, rows);
  } catch (...) { return "null"; }
}
std::string ActiveJobBlock(Character* actor) {
  try {
    OrdersReceiver* orders = actor->getOrdersReciever();
    if (!orders || reinterpret_cast<uintptr_t>(orders) < 0x10000) return NativeAiOrdersJson::ActiveJobJson(false, "");
    std::string name;
    if (orders->jobs.size() > 0 && orders->jobs.size() < 64) {
      Tasker* t = orders->jobs[0];
      if (t && reinterpret_cast<uintptr_t>(t) >= 0x10000) name = t->getDescription();
    }
    return NativeAiOrdersJson::ActiveJobJson(true, name);
  } catch (...) { return NativeAiOrdersJson::ActiveJobJson(false, ""); }
}
std::string CompanionBlock(Character* actor) {
  try {
    const unsigned int serial = actor->getHandle().serial;
    bool squad = false;
    Faction* faction = actor->getFaction();
    squad = faction && faction->isThePlayer();
    FollowExpiry::Info info;
    info.present = !squad && SnapshotFollowTargets().count(serial) != 0;
    if (info.present) {
      long long start = 0;
      if (GetFollowStart(serial, start)) info.startGameTs = start;
      info.nowGameTs = CurrentGameTsSeconds();
      info.limitSeconds = FollowExpiryLimitGameSeconds();
    }
    return FollowExpiry::TemporaryCompanionJson(info, squad, false, "");
  } catch (...) { return "{\"observed\":false}"; }
}
} // namespace

std::string CaptureJson(GameWorld* world, Character* actor) {
  if (!world || !actor) return "{\"observed\":false}";
  std::string s = "{\"version\":1,\"observed\":true,\"actor_serial\":" +
      ToString(actor->getHandle().serial) + ",\"observed_unix\":" +
      Number(static_cast<double>(std::time(NULL))) + ",\"game_ts\":" +
      Number(world->getTimeStamp_inGameHours().getTotalSeconds());
  std::string goal = "{\"observed\":false}";
  try {
    AI* ai = actor->getAI();
    AITaskSytem* tasks = ai ? ai->getTaskSystem() : NULL;
    if (tasks) {
      const TaskMatch& currentGoal = tasks->getCurrentGoal();
      goal = "{\"observed\":true,\"description\":" + Quote(tasks->getCurrentGoalString()) +
          ",\"target\":" + (currentGoal.taskData ? HandleJson(currentGoal.subject) : "null") +
          ",\"task_expired\":" + Bool(tasks->isTaskExpired()) +
          ",\"goal_expired\":" + Bool(tasks->isGoalExpired()) + "}";
    }
  } catch (...) { goal = "{\"observed\":false}"; }
  s += ",\"current_goal\":" + goal;
  std::string combat = "{\"observed\":false}";
  try {
    combat = "{\"observed\":true,\"in_combat\":" + Bool(actor->isInCombatMode(true, true)) +
        ",\"target\":" + HandleJson(actor->getAttackTarget()) + "}";
  } catch (...) { combat = "{\"observed\":false}"; }
  s += ",\"combat\":" + combat;
  std::string duties = "null";
  try {
    duties = "[";
    int count = std::min(8, std::max(0, actor->getPermajobCount()));
    for (int i = 0; i < count; ++i) {
      if (i) duties += ",";
      duties += Quote(actor->getPermajobName(i));
    }
    duties += "]";
  } catch (...) { duties = "null"; }
  s += ",\"assigned_jobs\":" + duties;
  std::string squad = "{\"observed\":false}";
  try {
    ActivePlatoon* active = actor->getPlatoon();
    Blackboard* board = active && active->me ? active->me->getBlackboard() : NULL;
    if (board) {
      AIPackage* current = board->getCurrentPackage();
      squad = "{\"observed\":true,\"current_package_name\":" +
          Quote(board->getCurrentAIPackageName()) + ",\"current_package\":" + PackageJson(current);
      if (!board->hasContractJob()) squad += ",\"contract\":{\"observed\":true,\"present\":false}";
      else {
        AIPackage* contract = NULL;
        // Blackboard.h: contractJob at 0x210. Do not walk unrelated packages.
        if (ReadField(board, 0x210, contract) && contract) {
          squad += ",\"contract\":{\"observed\":true,\"present\":true,\"active_package\":" +
              Bool(contract == current) + ",\"assignment\":" + PackageJson(contract);
          TimeOfDay expiry = board->getContractExpiryTime();
          if (!expiry.isUnset()) squad += ",\"remaining_game_hours\":" +
              Number(std::max(0.0, expiry.getTotalHours() - world->getTimeStamp_inGameHours().getTotalHours()));
          squad += "}";
        } else squad += ",\"contract\":{\"observed\":false}";
      }
      squad += "}";
    }
  } catch (...) { squad = "{\"observed\":false}"; }
  s += ",\"active_job\":" + ActiveJobBlock(actor);
  s += ",\"player_orders\":" + PlayerOrdersBlock(actor);
  s += ",\"temporary_companion\":" + CompanionBlock(actor);
  std::string activePackage = "{\"observed\":false}";
  try {
    ActivePlatoon* active = actor->getPlatoon();
    Blackboard* board = active && active->me ? active->me->getBlackboard() : NULL;
    if (board) {
      AIPackage* current = board->getCurrentPackage();
      activePackage = PackageJson(current);
      if (activePackage == "null") activePackage = "{\"observed\":true,\"package_name\":null}";
    }
  } catch (...) { activePackage = "{\"observed\":false}"; }
  s += ",\"active_package\":" + activePackage;
  return s + ",\"squad\":" + squad + "}";
}
} }
